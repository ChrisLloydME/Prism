#import "PrismBridge.h"

#include <cmath>
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
}

typedef void (^PRBridgeObservationDelivery)(id value);
typedef void (^PRBridgeObservationRemovalHandler)(void);

@interface PRBridgeObservationState : NSObject

- (instancetype)initWithHandler:(PRBridgeObservationDelivery)handler;

@property(nonatomic, copy, nullable) PRBridgeObservationRemovalHandler removalHandler;
@property(nonatomic, assign, readonly, getter=isCancelled) BOOL cancelled;

- (BOOL)cancel;
- (void)deliver:(id)value;

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

- (void)deliver:(id)value
{
    [_lock lock];
    if (!_cancelled && _handler) {
        try {
            @try {
                _handler(value);
            } @catch (NSException *) {
            }
        } catch (...) {
        }
    }
    [_lock unlock];
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
        [observation deliver:summary];
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
        [observation deliver:status];
    }
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
