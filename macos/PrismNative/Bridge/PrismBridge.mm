#import "PrismBridge.h"

#include "FrontendFacade.h"

#include <chrono>
#include <cmath>
#include <dispatch/dispatch.h>
#include <exception>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <utility>
#include <vector>

namespace {
NSString *const kPrismBundleIdentifier = @"com.lloydME.Prism";
NSString *const kPrismApplicationName = @"Prism";

class NativeFacadeLifecycle final {
public:
    bool beginShutdown() noexcept
    {
        if (m_state != PRBridgeLifecycleStateRunning) {
            return false;
        }
        m_state = PRBridgeLifecycleStateShuttingDown;
        return true;
    }

    void finishShutdown() noexcept
    {
        m_state = PRBridgeLifecycleStateStopped;
    }

    PRBridgeLifecycleState state() const noexcept
    {
        return m_state;
    }

private:
    PRBridgeLifecycleState m_state = PRBridgeLifecycleStateRunning;
};

NSURL *normalizedDataRootURL(NSURL *candidateURL)
{
    if (!candidateURL.isFileURL || candidateURL.path.length == 0 || !candidateURL.path.isAbsolutePath) {
        return nil;
    }

    NSURL *normalizedURL = candidateURL.standardizedURL;
    if (!normalizedURL.isFileURL || normalizedURL.path.length == 0 || !normalizedURL.path.isAbsolutePath) {
        return nil;
    }
    return normalizedURL;
}

void invokeHandler(PRBridgeLifecycleHandler handler) noexcept
{
    if (!handler) {
        return;
    }

    try {
        @try {
            handler();
        } @catch (NSException *) {
        }
    } catch (...) {
    }
}

bool isNonEmptyString(NSString *value)
{
    return [value isKindOfClass:NSString.class] && value.length > 0;
}

bool isKnownInstanceCommandKind(PRInstanceCommandKind kind)
{
    switch (kind) {
        case PRInstanceCommandKindLaunch:
        case PRInstanceCommandKindStop:
            return true;
    }
    return false;
}

bool isKnownInstanceCommandOutcome(PRInstanceCommandOutcome outcome)
{
    switch (outcome) {
        case PRInstanceCommandOutcomeSucceeded:
        case PRInstanceCommandOutcomeUnknownInstance:
        case PRInstanceCommandOutcomeRejected:
            return true;
    }
    return false;
}

std::string stableIdentifierFromFoundation(NSString *identifier)
{
    if (![identifier isKindOfClass:NSString.class]) {
        throw std::invalid_argument("Instance commands require a string identifier");
    }

    NSString *normalized = [identifier stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (normalized.length == 0) {
        throw std::invalid_argument("Instance commands require a stable identifier");
    }

    const char *utf8 = normalized.UTF8String;
    if (utf8 == nullptr || utf8[0] == '\0') {
        throw std::invalid_argument("Instance commands require valid UTF-8 text");
    }
    return std::string(utf8);
}

NSString *nullableStringCopy(NSString *value)
{
    return isNonEmptyString(value) ? [value copy] : nil;
}

PRInstanceCommandOutcome commandOutcomeFromFacadeResult(FrontendInstanceCommandResult result)
{
    switch (result) {
        case FrontendInstanceCommandResult::Succeeded:
            return PRInstanceCommandOutcomeSucceeded;
        case FrontendInstanceCommandResult::UnknownInstance:
            return PRInstanceCommandOutcomeUnknownInstance;
        case FrontendInstanceCommandResult::Rejected:
            return PRInstanceCommandOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown instance command result");
}

bool isKnownInstanceChangeKind(PRInstanceChangeKind kind)
{
    switch (kind) {
        case PRInstanceChangeKindAdded:
        case PRInstanceChangeKindUpdated:
        case PRInstanceChangeKindRemoved:
            return true;
    }
    return false;
}

FrontendRuntimeDependencies defaultRuntimeDependencies()
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] {
        return std::chrono::system_clock::now();
    };
    dependencies.cancelPendingWork = [] {};
    dependencies.shutdown = [] {};
    return dependencies;
}

std::filesystem::path dataRootPathForURL(NSURL *dataRootURL)
{
    const char *fileSystemRepresentation = dataRootURL.fileSystemRepresentation;
    if (fileSystemRepresentation == nullptr || fileSystemRepresentation[0] == '\0') {
        throw std::invalid_argument("Bridge data root must have a filesystem representation");
    }
    return std::filesystem::path(fileSystemRepresentation);
}

NSString *foundationStringFromUTF8(const std::string& value)
{
    if (value.empty()) {
        return nil;
    }

    NSString *string = [NSString stringWithUTF8String:value.c_str()];
    if (!string) {
        throw std::invalid_argument("Facade returned invalid UTF-8 text");
    }
    return string;
}

PRInstanceSummary *summaryFromFacadeSnapshot(const FrontendInstanceSnapshot& snapshot)
{
    NSString *identifier = foundationStringFromUTF8(snapshot.id);
    NSString *name = foundationStringFromUTF8(snapshot.name);
    NSString *iconKey = foundationStringFromUTF8(snapshot.iconKey);
    NSString *groupID = foundationStringFromUTF8(snapshot.groupId);
    PRInstanceSummary *summary = [[PRInstanceSummary alloc] initWithIdentifier:identifier
                                                                             name:name
                                                                          iconKey:iconKey
                                                                          groupID:groupID];
    if (!summary) {
        throw std::invalid_argument("Facade returned an invalid instance snapshot");
    }
    return summary;
}

NSArray<PRInstanceSummary *> *summariesFromFacadeSnapshots(const std::vector<FrontendInstanceSnapshot>& snapshots)
{
    NSMutableArray<PRInstanceSummary *> *converted = [NSMutableArray arrayWithCapacity:snapshots.size()];
    for (const FrontendInstanceSnapshot& snapshot : snapshots) {
        [converted addObject:summaryFromFacadeSnapshot(snapshot)];
    }
    return [converted copy];
}

PRInstanceChange *changeFromFacadeChange(const FrontendInstanceChange& change)
{
    NSString *identifier = foundationStringFromUTF8(change.instance.id);
    if (!identifier) {
        throw std::invalid_argument("Facade returned an instance change without an identifier");
    }

    PRInstanceChangeKind kind = PRInstanceChangeKindUpdated;
    PRInstanceSummary *summary = nil;
    switch (change.kind) {
        case FrontendInstanceChangeKind::Added:
            kind = PRInstanceChangeKindAdded;
            summary = summaryFromFacadeSnapshot(change.instance);
            break;
        case FrontendInstanceChangeKind::Updated:
            kind = PRInstanceChangeKindUpdated;
            summary = summaryFromFacadeSnapshot(change.instance);
            break;
        case FrontendInstanceChangeKind::Removed:
            kind = PRInstanceChangeKindRemoved;
            break;
        default:
            throw std::invalid_argument("Facade returned an unknown instance change kind");
    }

    PRInstanceChange *converted = [[PRInstanceChange alloc] initWithKind:kind
                                                                 identifier:identifier
                                                                    summary:summary];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid instance change");
    }
    return converted;
}

NSArray<PRInstanceChange *> *changesFromFacadeChanges(const std::vector<FrontendInstanceChange>& changes)
{
    NSMutableArray<PRInstanceChange *> *converted = [NSMutableArray arrayWithCapacity:changes.size()];
    for (const FrontendInstanceChange& change : changes) {
        [converted addObject:changeFromFacadeChange(change)];
    }
    return [converted copy];
}

PRTaskTerminalOutcome terminalOutcomeFromFacadeResult(FrontendTaskTerminalOutcome outcome);
PRTaskCancellationOutcome cancellationOutcomeFromFacadeResult(FrontendTaskCancellationResult outcome);

PRTaskState taskStateFromFacadeState(FrontendTaskState state)
{
    switch (state) {
        case FrontendTaskState::Queued:
            return PRTaskStateQueued;
        case FrontendTaskState::Running:
            return PRTaskStateRunning;
        case FrontendTaskState::Cancelling:
            return PRTaskStateCancelling;
        case FrontendTaskState::Succeeded:
            return PRTaskStateSucceeded;
        case FrontendTaskState::Failed:
            return PRTaskStateFailed;
        case FrontendTaskState::Cancelled:
            return PRTaskStateCancelled;
    }
    throw std::invalid_argument("Facade returned an unknown task state");
}

PRTaskProgressKind taskProgressKindFromFacadeKind(FrontendTaskProgressKind progressKind)
{
    switch (progressKind) {
        case FrontendTaskProgressKind::None:
            return PRTaskProgressKindNone;
        case FrontendTaskProgressKind::Indeterminate:
            return PRTaskProgressKindIndeterminate;
        case FrontendTaskProgressKind::Determinate:
            return PRTaskProgressKindDeterminate;
    }
    throw std::invalid_argument("Facade returned an unknown task progress kind");
}

NSDictionary<NSString *, NSString *> *substitutionValuesFromFacade(
    const std::vector<std::pair<std::string, std::string>>& values)
{
    NSMutableDictionary<NSString *, NSString *> *converted = [NSMutableDictionary dictionaryWithCapacity:values.size()];
    for (const auto& [key, value] : values) {
        NSString *foundationKey = foundationStringFromUTF8(key);
        NSString *foundationValue = foundationStringFromUTF8(value);
        if (!foundationKey || !foundationValue) {
            throw std::invalid_argument("Facade returned invalid task substitution values");
        }
        converted[foundationKey] = foundationValue;
    }
    return [converted copy];
}

PRTaskSubtaskStatus *subtaskFromFacadeSnapshot(const FrontendTaskSubtaskSnapshot& subtask)
{
    PRTaskSubtaskStatus *converted = [[PRTaskSubtaskStatus alloc]
        initWithIdentifier:foundationStringFromUTF8(subtask.id)
                       name:foundationStringFromUTF8(subtask.name)
                      state:taskStateFromFacadeState(subtask.state)
               progressKind:taskProgressKindFromFacadeKind(subtask.progressKind)
           progressFraction:subtask.progressFraction];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid task subtask");
    }
    return converted;
}

PRTaskTerminalResult *terminalResultFromFacadeResult(const FrontendTaskTerminalResult& result)
{
    PRTaskTerminalResult *converted = [[PRTaskTerminalResult alloc]
        initWithOutcome:terminalOutcomeFromFacadeResult(result.outcome)
         localizationKey:foundationStringFromUTF8(result.localizationKey)
     substitutionValues:substitutionValuesFromFacade(result.substitutionValues)
         diagnosticText:foundationStringFromUTF8(result.diagnosticText)
partialChangesRolledBack:result.partialChangesRolledBack];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid task terminal result");
    }
    return converted;
}

PRTaskStatus *taskStatusFromFacadeSnapshot(const FrontendTaskSnapshot& snapshot)
{
    NSMutableArray<PRTaskSubtaskStatus *> *subtasks = [NSMutableArray arrayWithCapacity:snapshot.subtasks.size()];
    for (const FrontendTaskSubtaskSnapshot& subtask : snapshot.subtasks) {
        [subtasks addObject:subtaskFromFacadeSnapshot(subtask)];
    }

    PRTaskTerminalResult *terminalResult = snapshot.terminalResult.has_value()
        ? terminalResultFromFacadeResult(*snapshot.terminalResult)
        : nil;
    PRTaskStatus *converted = [[PRTaskStatus alloc]
        initWithIdentifier:foundationStringFromUTF8(snapshot.id)
                      title:foundationStringFromUTF8(snapshot.title)
                      state:taskStateFromFacadeState(snapshot.state)
               progressKind:taskProgressKindFromFacadeKind(snapshot.progressKind)
           progressFraction:snapshot.progressFraction
        cancellationAllowed:snapshot.cancellationAllowed
                  subtasks:subtasks
             terminalResult:terminalResult];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid task snapshot");
    }
    return converted;
}

bool isKnownTaskState(PRTaskState state)
{
    switch (state) {
        case PRTaskStateQueued:
        case PRTaskStateRunning:
        case PRTaskStateCancelling:
        case PRTaskStateSucceeded:
        case PRTaskStateFailed:
        case PRTaskStateCancelled:
            return true;
    }
    return false;
}

bool isKnownTaskProgressKind(PRTaskProgressKind progressKind)
{
    switch (progressKind) {
        case PRTaskProgressKindNone:
        case PRTaskProgressKindIndeterminate:
        case PRTaskProgressKindDeterminate:
            return true;
    }
    return false;
}

bool isValidProgress(PRTaskProgressKind progressKind, double progressFraction)
{
    if (!std::isfinite(progressFraction) || !isKnownTaskProgressKind(progressKind)) {
        return false;
    }

    if (progressKind == PRTaskProgressKindDeterminate) {
        return progressFraction >= 0.0 && progressFraction <= 1.0;
    }
    return progressFraction == 0.0;
}

bool isTerminalTaskState(PRTaskState state)
{
    return state == PRTaskStateSucceeded || state == PRTaskStateFailed || state == PRTaskStateCancelled;
}

bool isKnownTaskTerminalOutcome(PRTaskTerminalOutcome outcome)
{
    switch (outcome) {
        case PRTaskTerminalOutcomeSucceeded:
        case PRTaskTerminalOutcomeFailed:
        case PRTaskTerminalOutcomeCancelled:
            return true;
    }
    return false;
}

bool isKnownTaskCancellationOutcome(PRTaskCancellationOutcome outcome)
{
    switch (outcome) {
        case PRTaskCancellationOutcomeRequested:
        case PRTaskCancellationOutcomeAlreadyTerminal:
        case PRTaskCancellationOutcomeUnknownTask:
        case PRTaskCancellationOutcomeRejected:
            return true;
    }
    return false;
}

PRTaskTerminalOutcome terminalOutcomeFromFacadeResult(FrontendTaskTerminalOutcome outcome)
{
    switch (outcome) {
        case FrontendTaskTerminalOutcome::Succeeded:
            return PRTaskTerminalOutcomeSucceeded;
        case FrontendTaskTerminalOutcome::Failed:
            return PRTaskTerminalOutcomeFailed;
        case FrontendTaskTerminalOutcome::Cancelled:
            return PRTaskTerminalOutcomeCancelled;
    }
    throw std::invalid_argument("Facade returned an unknown task terminal outcome");
}

PRTaskCancellationOutcome cancellationOutcomeFromFacadeResult(FrontendTaskCancellationResult outcome)
{
    switch (outcome) {
        case FrontendTaskCancellationResult::Requested:
            return PRTaskCancellationOutcomeRequested;
        case FrontendTaskCancellationResult::AlreadyTerminal:
            return PRTaskCancellationOutcomeAlreadyTerminal;
        case FrontendTaskCancellationResult::UnknownTask:
            return PRTaskCancellationOutcomeUnknownTask;
        case FrontendTaskCancellationResult::Rejected:
            return PRTaskCancellationOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown task cancellation outcome");
}

bool isKnownBridgeErrorCode(PRBridgeErrorCode code)
{
    switch (code) {
        case PRBridgeErrorCodeUnknown:
        case PRBridgeErrorCodeInvalidInput:
        case PRBridgeErrorCodeDataUnavailable:
        case PRBridgeErrorCodeAuthenticationRequired:
        case PRBridgeErrorCodeOperationCancelled:
        case PRBridgeErrorCodePermissionDenied:
        case PRBridgeErrorCodeNetworkUnavailable:
            return true;
    }
    return false;
}

bool isKnownBridgeErrorRecoveryKind(PRBridgeErrorRecoveryKind recoveryKind)
{
    switch (recoveryKind) {
        case PRBridgeErrorRecoveryKindNone:
        case PRBridgeErrorRecoveryKindRetry:
        case PRBridgeErrorRecoveryKindAuthenticate:
        case PRBridgeErrorRecoveryKindChooseFile:
        case PRBridgeErrorRecoveryKindRevealPath:
        case PRBridgeErrorRecoveryKindOpenSettings:
            return true;
    }
    return false;
}

NSDictionary<NSString *, NSString *> *copyStringDictionary(NSDictionary *candidate)
{
    if (![candidate isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *copy = [NSMutableDictionary dictionaryWithCapacity:candidate.count];
    for (id key in candidate) {
        id value = candidate[key];
        if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class] || [key length] == 0) {
            return nil;
        }
        copy[[key copy]] = [value copy];
    }
    return [copy copy];
}
}

NSErrorDomain const PRBridgeErrorDomain = @"com.lloydME.Prism.bridge";
NSString *const PRBridgeErrorLocalizationKeyUserInfoKey = @"PRBridgeErrorLocalizationKey";
NSString *const PRBridgeErrorSubstitutionValuesUserInfoKey = @"PRBridgeErrorSubstitutionValues";
NSString *const PRBridgeErrorDiagnosticTextUserInfoKey = @"PRBridgeErrorDiagnosticText";
NSString *const PRBridgeErrorRecoveryKindUserInfoKey = @"PRBridgeErrorRecoveryKind";
NSString *const PRBridgeErrorPartialChangesRolledBackUserInfoKey = @"PRBridgeErrorPartialChangesRolledBack";

namespace {
enum class NativeFacadeFailureKind : NSInteger {
    Unknown = 0,
    InvalidInput = 1,
    DataUnavailable = 2,
    AuthenticationRequired = 3,
    OperationCancelled = 4,
    PermissionDenied = 5,
    NetworkUnavailable = 6,
};

PRBridgeError *translatedErrorForFailureKind(NSInteger failureKind,
                                             NSString *diagnosticText,
                                             NSDictionary<NSString *, NSString *> *substitutionValues)
{
    PRBridgeErrorCode code = PRBridgeErrorCodeUnknown;
    NSString *localizationKey = @"bridge.error.unknown";
    PRBridgeErrorRecoveryKind recoveryKind = PRBridgeErrorRecoveryKindNone;

    switch (static_cast<NativeFacadeFailureKind>(failureKind)) {
        case NativeFacadeFailureKind::Unknown:
            break;
        case NativeFacadeFailureKind::InvalidInput:
            code = PRBridgeErrorCodeInvalidInput;
            localizationKey = @"bridge.error.invalidInput";
            break;
        case NativeFacadeFailureKind::DataUnavailable:
            code = PRBridgeErrorCodeDataUnavailable;
            localizationKey = @"bridge.error.dataUnavailable";
            recoveryKind = PRBridgeErrorRecoveryKindRetry;
            break;
        case NativeFacadeFailureKind::AuthenticationRequired:
            code = PRBridgeErrorCodeAuthenticationRequired;
            localizationKey = @"bridge.error.authenticationRequired";
            recoveryKind = PRBridgeErrorRecoveryKindAuthenticate;
            break;
        case NativeFacadeFailureKind::OperationCancelled:
            code = PRBridgeErrorCodeOperationCancelled;
            localizationKey = @"bridge.error.operationCancelled";
            break;
        case NativeFacadeFailureKind::PermissionDenied:
            code = PRBridgeErrorCodePermissionDenied;
            localizationKey = @"bridge.error.permissionDenied";
            recoveryKind = PRBridgeErrorRecoveryKindOpenSettings;
            break;
        case NativeFacadeFailureKind::NetworkUnavailable:
            code = PRBridgeErrorCodeNetworkUnavailable;
            localizationKey = @"bridge.error.networkUnavailable";
            recoveryKind = PRBridgeErrorRecoveryKindRetry;
            break;
    }

    return [[PRBridgeError alloc] initWithCode:code
                               localizationKey:localizationKey
                           substitutionValues:substitutionValues ?: @{}
                               diagnosticText:diagnosticText
                                  recoveryKind:recoveryKind
                     partialChangesRolledBack:NO];
}
}

typedef void (^PRBridgeObservationDelivery)(id value);
typedef void (^PRBridgeObservationRemovalHandler)(void);

@interface PRBridgeObservationState : NSObject

- (instancetype)initWithHandler:(PRBridgeObservationDelivery)handler;

@property(nonatomic, copy, nullable) PRBridgeObservationRemovalHandler removalHandler;
@property(nonatomic, assign, readonly, getter=isCancelled) BOOL cancelled;

- (BOOL)cancel;
- (void)deliverOnMainActor:(id)value;

@end

@interface PRBridgeObservationState () {
    NSRecursiveLock *_lock;
    PRBridgeObservationDelivery _handler;
    BOOL _cancelled;
}
@end

@implementation PRBridgeObservationState

- (instancetype)initWithHandler:(PRBridgeObservationDelivery)handler
{
    self = [super init];
    if (self) {
        _lock = [[NSRecursiveLock alloc] init];
        _handler = [handler copy];
    }
    return self;
}

- (BOOL)isCancelled
{
    [_lock lock];
    BOOL cancelled = _cancelled;
    [_lock unlock];
    return cancelled;
}

- (BOOL)cancel
{
    [_lock lock];
    if (_cancelled) {
        [_lock unlock];
        return NO;
    }

    _cancelled = YES;
    _handler = nil;
    PRBridgeObservationRemovalHandler removalHandler = [self.removalHandler copy];
    self.removalHandler = nil;
    [_lock unlock];

    if (removalHandler) {
        removalHandler();
    }
    return YES;
}

- (void)deliverOnMainActor:(id)value
{
    [_lock lock];
    BOOL canSchedule = !_cancelled && _handler != nil;
    [_lock unlock];

    if (!canSchedule) {
        return;
    }

    PRBridgeObservationState *state = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [state->_lock lock];
        PRBridgeObservationDelivery handler = (!state->_cancelled && state->_handler) ? [state->_handler copy] : nil;
        if (handler) {
            try {
                @try {
                    handler(value);
                } @catch (NSException *) {
                }
            } catch (...) {
            }
        }
        [state->_lock unlock];
    });
}

- (void)dealloc
{
    [self cancel];
}

@end

@interface PRBridgeArrayResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithValues:(NSArray *)values error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSArray *values;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeArrayResult

- (instancetype)initWithValues:(NSArray *)values error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _values = [values copy] ?: @[];
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeCommandResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRInstanceCommandResult *)result
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceCommandResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeCommandResult

- (instancetype)initWithResult:(PRInstanceCommandResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeTaskStatusResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStatus:(nullable PRTaskStatus *)status
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskStatus *status;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeTaskStatusResult

- (instancetype)initWithStatus:(PRTaskStatus *)status error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _status = status;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeTaskCancellationResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRTaskCancellationResult *)result
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskCancellationResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeTaskCancellationResult

- (instancetype)initWithResult:(PRTaskCancellationResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeObservationToken ()

@property(nonatomic, strong) PRBridgeObservationState *state;
- (instancetype)initWithState:(PRBridgeObservationState *)state NS_DESIGNATED_INITIALIZER;

@end

@implementation PRBridgeObservationToken

- (instancetype)initWithState:(PRBridgeObservationState *)state
{
    self = [super init];
    if (self) {
        self.state = state;
    }
    return self;
}

- (BOOL)isCancelled
{
    return self.state.isCancelled;
}

- (BOOL)cancel
{
    return [self.state cancel];
}

- (void)dealloc
{
    [self.state cancel];
}

@end

@interface PRApplicationIdentity ()

@property(nonatomic, copy, readwrite) NSString *bundleIdentifier;
@property(nonatomic, copy, readwrite) NSURL *applicationSupportDirectory;

@end

@interface PRPrismBridge () {
    std::unique_ptr<NativeFacadeLifecycle> _lifecycle;
    std::unique_ptr<FrontendFacade> _facade;
    std::mutex _lifecycleLock;
    std::mutex _facadeLock;
    dispatch_queue_t _backendQueue;
}

@property(nonatomic, copy, readwrite) NSURL *dataRootURL;
@property(nonatomic, copy, readwrite, nullable) PRBridgeLifecycleHandler cancellationHandler;
@property(nonatomic, copy, readwrite, nullable) PRBridgeLifecycleHandler shutdownHandler;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *instanceObservationStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *instanceChangeObservationStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *taskObservationStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *snapshotRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *changeRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *taskRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *taskCancellationRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *commandRequestStates;
@property(nonatomic, strong) NSLock *observationLock;

- (nullable instancetype)initWithDataRootURL:(NSURL *)dataRootURL
                          cancellationHandler:(nullable PRBridgeLifecycleHandler)cancellationHandler
                             shutdownHandler:(nullable PRBridgeLifecycleHandler)shutdownHandler
                   frontendRuntimeDependencies:(FrontendRuntimeDependencies)runtimeDependencies NS_DESIGNATED_INITIALIZER;
- (BOOL)isLifecycleRunning;
- (void)removeInstanceObservation:(PRBridgeObservationState *)observation;
- (void)removeInstanceChangeObservation:(PRBridgeObservationState *)observation;
- (void)removeTaskObservation:(PRBridgeObservationState *)observation;
- (void)removeSnapshotRequest:(PRBridgeObservationState *)request;
- (void)removeChangeRequest:(PRBridgeObservationState *)request;
- (void)removeTaskRequest:(PRBridgeObservationState *)request;
- (void)removeTaskCancellationRequest:(PRBridgeObservationState *)request;
- (void)removeCommandRequest:(PRBridgeObservationState *)request;
- (nullable PRBridgeObservationToken *)loadTaskStatusWithIdentifier:(NSString *)identifier
                                                            completion:(PRTaskStatusCompletionHandler)completion;
- (nullable PRBridgeObservationToken *)performTaskCancellationWithIdentifier:(NSString *)identifier
                                                                     completion:(PRTaskCancellationCompletionHandler)completion;
- (nullable PRBridgeObservationToken *)performInstanceCommand:(PRInstanceCommandKind)kind
                                                      identifier:(NSString *)identifier
                                                     completion:(PRInstanceCommandCompletionHandler)completion;
- (void)cancelAllObservations;
- (void)publishInstanceSummary:(PRInstanceSummary *)summary;
- (void)publishInstanceChange:(PRInstanceChange *)change;
- (void)publishTaskStatus:(PRTaskStatus *)status;
- (PRBridgeError *)bridgeErrorForFailureKind:(NSInteger)failureKind
                               diagnosticText:(nullable NSString *)diagnosticText
                           substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues;

@end

@interface PRInstanceSummary ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite, nullable) NSString *iconKey;
@property(nonatomic, copy, readwrite, nullable) NSString *groupID;

@end

@interface PRInstanceCommandResult ()

@property(nonatomic, assign, readwrite) PRInstanceCommandKind kind;
@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, assign, readwrite) PRInstanceCommandOutcome outcome;

@end

@interface PRInstanceChange ()

@property(nonatomic, assign, readwrite) PRInstanceChangeKind kind;
@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, strong, readwrite, nullable) PRInstanceSummary *summary;

@end

@interface PRTaskSubtaskStatus ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, assign, readwrite) PRTaskState state;
@property(nonatomic, assign, readwrite) PRTaskProgressKind progressKind;
@property(nonatomic, assign, readwrite) double progressFraction;

@end

@interface PRTaskTerminalResult ()

@property(nonatomic, assign, readwrite) PRTaskTerminalOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *substitutionValues;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL partialChangesRolledBack;

@end

@interface PRTaskStatus ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite, nullable) NSString *title;
@property(nonatomic, assign, readwrite) PRTaskState state;
@property(nonatomic, assign, readwrite) PRTaskProgressKind progressKind;
@property(nonatomic, assign, readwrite) double progressFraction;
@property(nonatomic, assign, readwrite) BOOL cancellationAllowed;
@property(nonatomic, copy, readwrite) NSArray<PRTaskSubtaskStatus *> *subtasks;
@property(nonatomic, strong, readwrite, nullable) PRTaskTerminalResult *terminalResult;


@end

@interface PRTaskCancellationResult ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, assign, readwrite) PRTaskCancellationOutcome outcome;

@end

@interface PRBridgeError ()

@property(nonatomic, copy, readwrite) NSString *domain;
@property(nonatomic, assign, readwrite) PRBridgeErrorCode code;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *substitutionValues;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) PRBridgeErrorRecoveryKind recoveryKind;
@property(nonatomic, assign, readwrite) BOOL partialChangesRolledBack;
@property(nonatomic, copy, readwrite) NSError *foundationError;

@end

@implementation PRApplicationIdentity

+ (NSString *)requiredBundleIdentifier
{
    return kPrismBundleIdentifier;
}

+ (NSString *)applicationName
{
    return kPrismApplicationName;
}

- (instancetype)init
{
    NSURL *baseURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                            inDomain:NSUserDomainMask
                                                   appropriateForURL:nil
                                                              create:NO
                                                               error:nil];
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"";
    return [self initWithBundleIdentifier:bundleIdentifier
            applicationSupportBaseDirectory:baseURL];
}

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
           applicationSupportBaseDirectory:(NSURL *)applicationSupportBaseDirectory
{
    self = [super init];
    if (self) {
        self.bundleIdentifier = bundleIdentifier;
        self.applicationSupportDirectory = [applicationSupportBaseDirectory URLByAppendingPathComponent:kPrismApplicationName
                                                                                               isDirectory:YES];
    }
    return self;
}

- (NSString *)applicationName
{
    return kPrismApplicationName;
}

@end

@implementation PRInstanceSummary

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                            iconKey:(NSString *)iconKey
                            groupID:(NSString *)groupID
{
    if (!isNonEmptyString(identifier) || !isNonEmptyString(name)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.name = [name copy];
        self.iconKey = nullableStringCopy(iconKey);
        self.groupID = nullableStringCopy(groupID);
    }
    return self;
}

@end

@implementation PRInstanceCommandResult

- (instancetype)initWithKind:(PRInstanceCommandKind)kind
                   identifier:(NSString *)identifier
                      outcome:(PRInstanceCommandOutcome)outcome
{
    if (!isKnownInstanceCommandKind(kind) || !isNonEmptyString(identifier) || !isKnownInstanceCommandOutcome(outcome)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.kind = kind;
        self.identifier = [identifier copy];
        self.outcome = outcome;
    }
    return self;
}

@end

@implementation PRTaskSubtaskStatus

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                              state:(PRTaskState)state
                       progressKind:(PRTaskProgressKind)progressKind
                   progressFraction:(double)progressFraction
{
    if (!isNonEmptyString(identifier) || !isNonEmptyString(name) || !isKnownTaskState(state)
        || !isValidProgress(progressKind, progressFraction)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.name = [name copy];
        self.state = state;
        self.progressKind = progressKind;
        self.progressFraction = progressFraction;
    }
    return self;
}

@end

@implementation PRTaskTerminalResult

- (instancetype)initWithOutcome:(PRTaskTerminalOutcome)outcome
                 localizationKey:(NSString *)localizationKey
             substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues
                 diagnosticText:(NSString *)diagnosticText
        partialChangesRolledBack:(BOOL)partialChangesRolledBack
{
    NSDictionary<NSString *, NSString *> *copiedSubstitutionValues = copyStringDictionary(substitutionValues);
    if (!isKnownTaskTerminalOutcome(outcome) || !isNonEmptyString(localizationKey) || !copiedSubstitutionValues) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.substitutionValues = copiedSubstitutionValues;
        self.diagnosticText = nullableStringCopy(diagnosticText);
        self.partialChangesRolledBack = partialChangesRolledBack;
    }
    return self;
}

@end

@implementation PRInstanceChange

- (instancetype)initWithKind:(PRInstanceChangeKind)kind
                   identifier:(NSString *)identifier
                      summary:(PRInstanceSummary *)summary
{
    if (!isKnownInstanceChangeKind(kind) || !isNonEmptyString(identifier)) {
        return nil;
    }

    if ((kind == PRInstanceChangeKindAdded || kind == PRInstanceChangeKindUpdated) && !summary) {
        return nil;
    }
    if (summary && ![summary.identifier isEqualToString:identifier]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.kind = kind;
        self.identifier = [identifier copy];
        self.summary = summary;
    }
    return self;
}

@end

@implementation PRTaskStatus

- (instancetype)initWithIdentifier:(NSString *)identifier
                              state:(PRTaskState)state
                       progressKind:(PRTaskProgressKind)progressKind
                   progressFraction:(double)progressFraction
                cancellationAllowed:(BOOL)cancellationAllowed
{
    return [self initWithIdentifier:identifier
                               title:nil
                               state:state
                        progressKind:progressKind
                    progressFraction:progressFraction
                 cancellationAllowed:cancellationAllowed
                           subtasks:@[]
                      terminalResult:nil];
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                              title:(NSString *)title
                              state:(PRTaskState)state
                       progressKind:(PRTaskProgressKind)progressKind
                   progressFraction:(double)progressFraction
                cancellationAllowed:(BOOL)cancellationAllowed
                          subtasks:(NSArray<PRTaskSubtaskStatus *> *)subtasks
                     terminalResult:(PRTaskTerminalResult *)terminalResult
{
    if (!isNonEmptyString(identifier) || !isKnownTaskState(state) || !isValidProgress(progressKind, progressFraction)
        || ![subtasks isKindOfClass:NSArray.class]) {
        return nil;
    }

    if ((state == PRTaskStateCancelling || isTerminalTaskState(state)) && cancellationAllowed) {
        return nil;
    }

    NSMutableSet<NSString *> *subtaskIdentifiers = [NSMutableSet setWithCapacity:subtasks.count];
    for (id candidate in subtasks) {
        if (![candidate isKindOfClass:PRTaskSubtaskStatus.class]) {
            return nil;
        }
        PRTaskSubtaskStatus *subtask = (PRTaskSubtaskStatus *)candidate;
        if ([subtaskIdentifiers containsObject:subtask.identifier]) {
            return nil;
        }
        [subtaskIdentifiers addObject:subtask.identifier];
    }

    if (terminalResult && !isTerminalTaskState(state)) {
        return nil;
    }
    if (isTerminalTaskState(state) && !terminalResult) {
        return nil;
    }
    if (terminalResult) {
        BOOL matchingOutcome = (state == PRTaskStateSucceeded && terminalResult.outcome == PRTaskTerminalOutcomeSucceeded)
            || (state == PRTaskStateFailed && terminalResult.outcome == PRTaskTerminalOutcomeFailed)
            || (state == PRTaskStateCancelled && terminalResult.outcome == PRTaskTerminalOutcomeCancelled);
        if (!matchingOutcome) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.title = nullableStringCopy(title);
        self.state = state;
        self.progressKind = progressKind;
        self.progressFraction = progressFraction;
        self.cancellationAllowed = cancellationAllowed;
        self.subtasks = [subtasks copy];
        self.terminalResult = terminalResult;
    }
    return self;
}

@end

@implementation PRTaskCancellationResult

- (instancetype)initWithIdentifier:(NSString *)identifier outcome:(PRTaskCancellationOutcome)outcome
{
    if (!isNonEmptyString(identifier) || !isKnownTaskCancellationOutcome(outcome)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.outcome = outcome;
    }
    return self;
}

@end

@implementation PRBridgeError

- (instancetype)initWithCode:(PRBridgeErrorCode)code
               localizationKey:(NSString *)localizationKey
           substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues
               diagnosticText:(NSString *)diagnosticText
                  recoveryKind:(PRBridgeErrorRecoveryKind)recoveryKind
     partialChangesRolledBack:(BOOL)partialChangesRolledBack
{
    NSDictionary<NSString *, NSString *> *copiedSubstitutionValues = copyStringDictionary(substitutionValues);
    if (!isKnownBridgeErrorCode(code) || !isNonEmptyString(localizationKey) || !copiedSubstitutionValues
        || !isKnownBridgeErrorRecoveryKind(recoveryKind)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.domain = PRBridgeErrorDomain;
        self.code = code;
        self.localizationKey = [localizationKey copy];
        self.substitutionValues = copiedSubstitutionValues;
        self.diagnosticText = nullableStringCopy(diagnosticText);
        self.recoveryKind = recoveryKind;
        self.partialChangesRolledBack = partialChangesRolledBack;

        NSMutableDictionary *userInfo = [@{
            PRBridgeErrorLocalizationKeyUserInfoKey: self.localizationKey,
            PRBridgeErrorSubstitutionValuesUserInfoKey: self.substitutionValues,
            PRBridgeErrorRecoveryKindUserInfoKey: @(self.recoveryKind),
            PRBridgeErrorPartialChangesRolledBackUserInfoKey: @(self.partialChangesRolledBack),
        } mutableCopy];
        if (self.diagnosticText) {
            userInfo[PRBridgeErrorDiagnosticTextUserInfoKey] = self.diagnosticText;
        }
        self.foundationError = [NSError errorWithDomain:self.domain code:self.code userInfo:userInfo];
    }
    return self;
}

@end

@implementation PRPrismBridge

- (instancetype)initWithDataRootURL:(NSURL *)dataRootURL
                  cancellationHandler:(PRBridgeLifecycleHandler)cancellationHandler
                     shutdownHandler:(PRBridgeLifecycleHandler)shutdownHandler
{
    return [self initWithDataRootURL:dataRootURL
                   cancellationHandler:cancellationHandler
                      shutdownHandler:shutdownHandler
            frontendRuntimeDependencies:defaultRuntimeDependencies()];
}

- (instancetype)initWithDataRootURL:(NSURL *)dataRootURL
                  cancellationHandler:(PRBridgeLifecycleHandler)cancellationHandler
                     shutdownHandler:(PRBridgeLifecycleHandler)shutdownHandler
           frontendRuntimeDependencies:(FrontendRuntimeDependencies)runtimeDependencies
{
    NSURL *normalizedURL = normalizedDataRootURL(dataRootURL);
    if (!normalizedURL) {
        return nil;
    }

    std::unique_ptr<FrontendFacade> facade;
    try {
        facade = std::make_unique<FrontendFacade>(dataRootPathForURL(normalizedURL), std::move(runtimeDependencies));
    } catch (...) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.dataRootURL = normalizedURL;
        self.cancellationHandler = cancellationHandler;
        self.shutdownHandler = shutdownHandler;
        self.instanceObservationStates = [NSMutableArray array];
        self.instanceChangeObservationStates = [NSMutableArray array];
        self.taskObservationStates = [NSMutableArray array];
        self.snapshotRequestStates = [NSMutableArray array];
        self.changeRequestStates = [NSMutableArray array];
        self.taskRequestStates = [NSMutableArray array];
        self.taskCancellationRequestStates = [NSMutableArray array];
        self.commandRequestStates = [NSMutableArray array];
        self.observationLock = [[NSLock alloc] init];
        _lifecycle = std::make_unique<NativeFacadeLifecycle>();
        _facade = std::move(facade);
        _backendQueue = dispatch_queue_create("com.lloydME.PrismNative.frontend", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)isLifecycleRunning
{
    std::lock_guard<std::mutex> lock(_lifecycleLock);
    return _lifecycle && _lifecycle->state() == PRBridgeLifecycleStateRunning;
}

- (PRBridgeObservationToken *)observeInstanceSummariesWithHandler:(PRInstanceSummaryObservationHandler)handler
{
    if (!handler || ![self isLifecycleRunning]) {
        return nil;
    }

    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        handler((PRInstanceSummary *)value);
    }];
    __weak PRPrismBridge *weakBridge = self;
    __weak PRBridgeObservationState *weakObservation = observation;
    observation.removalHandler = ^{
        [weakBridge removeInstanceObservation:weakObservation];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning]) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.instanceObservationStates addObject:observation];
    [self.observationLock unlock];

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)observeInstanceChangesWithHandler:(PRInstanceChangeObservationHandler)handler
{
    if (!handler || ![self isLifecycleRunning]) {
        return nil;
    }

    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        handler((PRInstanceChange *)value);
    }];
    __weak PRPrismBridge *weakBridge = self;
    __weak PRBridgeObservationState *weakObservation = observation;
    observation.removalHandler = ^{
        [weakBridge removeInstanceChangeObservation:weakObservation];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning]) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.instanceChangeObservationStates addObject:observation];
    [self.observationLock unlock];

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)observeTaskStatusWithHandler:(PRTaskStatusObservationHandler)handler
{
    if (!handler || ![self isLifecycleRunning]) {
        return nil;
    }

    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        handler((PRTaskStatus *)value);
    }];
    __weak PRPrismBridge *weakBridge = self;
    __weak PRBridgeObservationState *weakObservation = observation;
    observation.removalHandler = ^{
        [weakBridge removeTaskObservation:weakObservation];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning]) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.taskObservationStates addObject:observation];
    [self.observationLock unlock];

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)loadInstanceSummariesWithCompletion:(PRInstanceSummariesCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeArrayResult *result = (PRBridgeArrayResult *)value;
        [weakRequest cancel];
        completion((NSArray<PRInstanceSummary *> *)result.values, result.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeSnapshotRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.snapshotRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        NSArray<PRInstanceSummary *> *summaries = @[];
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    summaries = summariesFromFacadeSnapshots(bridge->_facade->instanceSnapshots());
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid facade snapshot"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Facade operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Facade data unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown facade failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeArrayResult alloc] initWithValues:summaries error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadInstanceChangesWithCompletion:(PRInstanceChangesCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeArrayResult *result = (PRBridgeArrayResult *)value;
        [weakRequest cancel];
        completion((NSArray<PRInstanceChange *> *)result.values, result.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeChangeRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.changeRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        NSArray<PRInstanceChange *> *changes = @[];
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    changes = changesFromFacadeChanges(bridge->_facade->instanceChanges());
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid facade change"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Facade operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Facade data unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown facade failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled && !error) {
            for (PRInstanceChange *change in changes) {
                if (state.isCancelled) {
                    break;
                }
                [bridge publishInstanceChange:change];
            }
        }
        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeArrayResult alloc] initWithValues:changes error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadTaskStatusWithIdentifier:(NSString *)identifier
                                                  completion:(PRTaskStatusCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeTaskStatusResult *taskResult = (PRBridgeTaskStatusResult *)value;
        [weakRequest cancel];
        completion(taskResult.status, taskResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeTaskRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.taskRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRTaskStatus *status = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string taskIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    const std::optional<FrontendTaskSnapshot> snapshot = bridge->_facade->taskSnapshot(taskIdentifier);
                    if (!snapshot.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Task identifier is not available"
                                               substitutionValues:@{ @"taskIdentifier": identifierCopy ?: @"" }];
                    } else {
                        status = taskStatusFromFacadeSnapshot(*snapshot);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid task identifier"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Task operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Task data unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown task failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeTaskStatusResult alloc] initWithStatus:status error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)performTaskCancellationWithIdentifier:(NSString *)identifier
                                                            completion:(PRTaskCancellationCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeTaskCancellationResult *taskResult = (PRBridgeTaskCancellationResult *)value;
        [weakRequest cancel];
        completion(taskResult.result, taskResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeTaskCancellationRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.taskCancellationRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRTaskCancellationResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string taskIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    const FrontendTaskCancellationResult cancellationResult = bridge->_facade->cancelTask(taskIdentifier);
                    NSString *foundationIdentifier = [NSString stringWithUTF8String:taskIdentifier.c_str()];
                    result = [[PRTaskCancellationResult alloc]
                        initWithIdentifier:foundationIdentifier
                                    outcome:cancellationOutcomeFromFacadeResult(cancellationResult)];
                    if (!result) {
                        throw std::invalid_argument("Facade returned an invalid task cancellation result");
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid task identifier"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Task cancellation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Task cancellation unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown task cancellation failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeTaskCancellationResult alloc] initWithResult:result error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)cancelTaskWithIdentifier:(NSString *)identifier
                                               completion:(PRTaskCancellationCompletionHandler)completion
{
    return [self performTaskCancellationWithIdentifier:identifier completion:completion];
}

- (PRBridgeObservationToken *)performInstanceCommand:(PRInstanceCommandKind)kind
                                           identifier:(NSString *)identifier
                                          completion:(PRInstanceCommandCompletionHandler)completion
{
    if (!completion || !isKnownInstanceCommandKind(kind) || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeCommandResult *commandResult = (PRBridgeCommandResult *)value;
        [weakRequest cancel];
        completion(commandResult.result, commandResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeCommandRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.commandRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceCommandResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string instanceIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    const FrontendInstanceCommandResult commandResult = kind == PRInstanceCommandKindLaunch
                        ? bridge->_facade->launchInstance(instanceIdentifier)
                        : bridge->_facade->stopInstance(instanceIdentifier);
                    NSString *foundationIdentifier = [NSString stringWithUTF8String:instanceIdentifier.c_str()];
                    PRInstanceCommandOutcome outcome = commandOutcomeFromFacadeResult(commandResult);
                    result = [[PRInstanceCommandResult alloc] initWithKind:kind
                                                                   identifier:foundationIdentifier
                                                                      outcome:outcome];
                    if (!result) {
                        throw std::invalid_argument("Facade returned an invalid instance command result");
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance command"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance command cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance command unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance command failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeCommandResult alloc] initWithResult:result error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)launchInstanceWithIdentifier:(NSString *)identifier
                                                  completion:(PRInstanceCommandCompletionHandler)completion
{
    return [self performInstanceCommand:PRInstanceCommandKindLaunch identifier:identifier completion:completion];
}

- (PRBridgeObservationToken *)stopInstanceWithIdentifier:(NSString *)identifier
                                                completion:(PRInstanceCommandCompletionHandler)completion
{
    return [self performInstanceCommand:PRInstanceCommandKindStop identifier:identifier completion:completion];
}

- (void)removeInstanceObservation:(PRBridgeObservationState *)observation
{
    [self.observationLock lock];
    NSUInteger index = [self.instanceObservationStates indexOfObjectIdenticalTo:observation];
    if (index != NSNotFound) {
        [self.instanceObservationStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeInstanceChangeObservation:(PRBridgeObservationState *)observation
{
    [self.observationLock lock];
    NSUInteger index = [self.instanceChangeObservationStates indexOfObjectIdenticalTo:observation];
    if (index != NSNotFound) {
        [self.instanceChangeObservationStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeTaskObservation:(PRBridgeObservationState *)observation
{
    [self.observationLock lock];
    NSUInteger index = [self.taskObservationStates indexOfObjectIdenticalTo:observation];
    if (index != NSNotFound) {
        [self.taskObservationStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeSnapshotRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.snapshotRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.snapshotRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeChangeRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.changeRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.changeRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeTaskRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.taskRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.taskRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeTaskCancellationRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.taskCancellationRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.taskCancellationRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeCommandRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.commandRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.commandRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)cancelAllObservations
{
    [self.observationLock lock];
    NSMutableArray<PRBridgeObservationState *> *observations = [NSMutableArray array];
    [observations addObjectsFromArray:self.instanceObservationStates];
    [observations addObjectsFromArray:self.instanceChangeObservationStates];
    [observations addObjectsFromArray:self.taskObservationStates];
    [observations addObjectsFromArray:self.snapshotRequestStates];
    [observations addObjectsFromArray:self.changeRequestStates];
    [observations addObjectsFromArray:self.taskRequestStates];
    [observations addObjectsFromArray:self.taskCancellationRequestStates];
    [observations addObjectsFromArray:self.commandRequestStates];
    [self.instanceObservationStates removeAllObjects];
    [self.instanceChangeObservationStates removeAllObjects];
    [self.taskObservationStates removeAllObjects];
    [self.snapshotRequestStates removeAllObjects];
    [self.changeRequestStates removeAllObjects];
    [self.taskRequestStates removeAllObjects];
    [self.taskCancellationRequestStates removeAllObjects];
    [self.commandRequestStates removeAllObjects];
    [self.observationLock unlock];

    for (PRBridgeObservationState *observation in observations) {
        [observation cancel];
    }
}

- (void)publishInstanceSummary:(PRInstanceSummary *)summary
{
    if (!summary) {
        return;
    }

    [self.observationLock lock];
    NSArray<PRBridgeObservationState *> *observations = [self.instanceObservationStates copy];
    [self.observationLock unlock];
    for (PRBridgeObservationState *observation in observations) {
        [observation deliverOnMainActor:summary];
    }
}

- (void)publishInstanceChange:(PRInstanceChange *)change
{
    if (!change) {
        return;
    }

    [self.observationLock lock];
    NSArray<PRBridgeObservationState *> *observations = [self.instanceChangeObservationStates copy];
    [self.observationLock unlock];
    for (PRBridgeObservationState *observation in observations) {
        [observation deliverOnMainActor:change];
    }
}

- (void)publishTaskStatus:(PRTaskStatus *)status
{
    if (!status) {
        return;
    }

    [self.observationLock lock];
    NSArray<PRBridgeObservationState *> *observations = [self.taskObservationStates copy];
    [self.observationLock unlock];
    for (PRBridgeObservationState *observation in observations) {
        [observation deliverOnMainActor:status];
    }
}

- (PRBridgeError *)bridgeErrorForFailureKind:(NSInteger)failureKind
                               diagnosticText:(NSString *)diagnosticText
                           substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues
{
    return translatedErrorForFailureKind(failureKind, diagnosticText, substitutionValues);
}

- (PRBridgeLifecycleState)lifecycleState
{
    std::lock_guard<std::mutex> lock(_lifecycleLock);
    return _lifecycle ? _lifecycle->state() : PRBridgeLifecycleStateStopped;
}

- (BOOL)shutdown
{
    {
        std::lock_guard<std::mutex> lock(_lifecycleLock);
        if (!_lifecycle || !_lifecycle->beginShutdown()) {
            return NO;
        }
    }

    [self cancelAllObservations];
    invokeHandler(self.cancellationHandler);
    {
        std::lock_guard<std::mutex> lock(_facadeLock);
        if (_facade) {
            _facade->shutdown();
        }
    }
    invokeHandler(self.shutdownHandler);

    self.cancellationHandler = nil;
    self.shutdownHandler = nil;
    {
        std::lock_guard<std::mutex> lock(_lifecycleLock);
        if (_lifecycle) {
            _lifecycle->finishShutdown();
        }
    }
    return YES;
}

- (void)dealloc
{
    [self shutdown];
}

@end
