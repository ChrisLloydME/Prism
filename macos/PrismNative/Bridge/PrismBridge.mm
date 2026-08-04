#import "PrismBridge.h"

#include <cmath>
#include <dispatch/dispatch.h>
#include <memory>

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

NSString *nullableStringCopy(NSString *value)
{
    return isNonEmptyString(value) ? [value copy] : nil;
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
        if (!state->_cancelled && state->_handler) {
            try {
                @try {
                    state->_handler(value);
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
}

@property(nonatomic, copy, readwrite) NSURL *dataRootURL;
@property(nonatomic, copy, readwrite, nullable) PRBridgeLifecycleHandler cancellationHandler;
@property(nonatomic, copy, readwrite, nullable) PRBridgeLifecycleHandler shutdownHandler;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *instanceObservationStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *taskObservationStates;
@property(nonatomic, strong) NSLock *observationLock;

- (void)removeInstanceObservation:(PRBridgeObservationState *)observation;
- (void)removeTaskObservation:(PRBridgeObservationState *)observation;
- (void)cancelAllObservations;
- (void)publishInstanceSummary:(PRInstanceSummary *)summary;
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

@interface PRTaskStatus ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, assign, readwrite) PRTaskState state;
@property(nonatomic, assign, readwrite) PRTaskProgressKind progressKind;
@property(nonatomic, assign, readwrite) double progressFraction;
@property(nonatomic, assign, readwrite) BOOL cancellationAllowed;

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

@implementation PRTaskStatus

- (instancetype)initWithIdentifier:(NSString *)identifier
                              state:(PRTaskState)state
                       progressKind:(PRTaskProgressKind)progressKind
                   progressFraction:(double)progressFraction
                cancellationAllowed:(BOOL)cancellationAllowed
{
    if (!isNonEmptyString(identifier) || !isKnownTaskState(state) || !isValidProgress(progressKind, progressFraction)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.state = state;
        self.progressKind = progressKind;
        self.progressFraction = progressFraction;
        self.cancellationAllowed = cancellationAllowed;
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
    NSURL *normalizedURL = normalizedDataRootURL(dataRootURL);
    if (!normalizedURL) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.dataRootURL = normalizedURL;
        self.cancellationHandler = cancellationHandler;
        self.shutdownHandler = shutdownHandler;
        self.instanceObservationStates = [NSMutableArray array];
        self.taskObservationStates = [NSMutableArray array];
        self.observationLock = [[NSLock alloc] init];
        _lifecycle = std::make_unique<NativeFacadeLifecycle>();
    }
    return self;
}

- (PRBridgeObservationToken *)observeInstanceSummariesWithHandler:(PRInstanceSummaryObservationHandler)handler
{
    if (!handler || !_lifecycle || _lifecycle->state() != PRBridgeLifecycleStateRunning) {
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
    if (!_lifecycle || _lifecycle->state() != PRBridgeLifecycleStateRunning) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.instanceObservationStates addObject:observation];
    [self.observationLock unlock];

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)observeTaskStatusWithHandler:(PRTaskStatusObservationHandler)handler
{
    if (!handler || !_lifecycle || _lifecycle->state() != PRBridgeLifecycleStateRunning) {
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
    if (!_lifecycle || _lifecycle->state() != PRBridgeLifecycleStateRunning) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.taskObservationStates addObject:observation];
    [self.observationLock unlock];

    return [[PRBridgeObservationToken alloc] initWithState:observation];
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

- (void)removeTaskObservation:(PRBridgeObservationState *)observation
{
    [self.observationLock lock];
    NSUInteger index = [self.taskObservationStates indexOfObjectIdenticalTo:observation];
    if (index != NSNotFound) {
        [self.taskObservationStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)cancelAllObservations
{
    [self.observationLock lock];
    NSArray<PRBridgeObservationState *> *observations = [self.instanceObservationStates arrayByAddingObjectsFromArray:self.taskObservationStates];
    [self.instanceObservationStates removeAllObjects];
    [self.taskObservationStates removeAllObjects];
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
    return _lifecycle ? _lifecycle->state() : PRBridgeLifecycleStateStopped;
}

- (BOOL)shutdown
{
    if (!_lifecycle || !_lifecycle->beginShutdown()) {
        return NO;
    }

    [self cancelAllObservations];
    invokeHandler(self.cancellationHandler);
    invokeHandler(self.shutdownHandler);

    self.cancellationHandler = nil;
    self.shutdownHandler = nil;
    _lifecycle->finishShutdown();
    return YES;
}

- (void)dealloc
{
    [self shutdown];
}

@end
