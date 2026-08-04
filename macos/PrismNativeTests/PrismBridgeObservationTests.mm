#import <XCTest/XCTest.h>

#import "../PrismNative/Bridge/PrismBridge.h"

@interface PRPrismBridge (Testing)

- (void)publishInstanceSummary:(PRInstanceSummary *)summary;
- (void)publishTaskStatus:(PRTaskStatus *)status;
- (PRBridgeError *)bridgeErrorForFailureKind:(NSInteger)failureKind
                               diagnosticText:(nullable NSString *)diagnosticText
                           substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues;

@end

@interface PrismBridgeObservationTests : XCTestCase

@property(nonatomic, strong) NSURL *fixtureRootURL;

@end

typedef NS_ENUM(NSInteger, PRBridgeFixtureFailureKind) {
    PRBridgeFixtureFailureKindUnknown = 0,
    PRBridgeFixtureFailureKindInvalidInput = 1,
    PRBridgeFixtureFailureKindDataUnavailable = 2,
    PRBridgeFixtureFailureKindAuthenticationRequired = 3,
    PRBridgeFixtureFailureKindOperationCancelled = 4,
    PRBridgeFixtureFailureKindPermissionDenied = 5,
    PRBridgeFixtureFailureKindNetworkUnavailable = 6,
};

@implementation PrismBridgeObservationTests

- (void)setUp
{
    [super setUp];
    self.fixtureRootURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"PrismNativeObservation-%@", NSUUID.UUID.UUIDString]]
                                     isDirectory:YES];
    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtURL:self.fixtureRootURL
                                             withIntermediateDirectories:NO
                                                              attributes:nil
                                                                   error:&error];
    XCTAssertTrue(created, @"Fixture root creation failed: %@", error);
}

- (void)tearDown
{
    if (self.fixtureRootURL) {
        [[NSFileManager defaultManager] removeItemAtURL:self.fixtureRootURL error:nil];
    }
    self.fixtureRootURL = nil;
    [super tearDown];
}

- (PRPrismBridge *)bridge
{
    return [[PRPrismBridge alloc] initWithDataRootURL:self.fixtureRootURL
                                   cancellationHandler:nil
                                      shutdownHandler:nil];
}

- (PRInstanceSummary *)summaryWithIdentifier:(NSString *)identifier
{
    return [[PRInstanceSummary alloc] initWithIdentifier:identifier
                                                     name:@"Fixture Instance"
                                                  iconKey:nil
                                                  groupID:nil];
}

- (void)drainMainQueue
{
    XCTestExpectation *drained = [self expectationWithDescription:@"Main actor queue drained"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [drained fulfill];
    });
    [self waitForExpectations:@[drained] timeout:1.0];
}

- (void)testInstanceObservationDeliversFixtureValuesAndCancelsIdempotently
{
    PRPrismBridge *bridge = [self bridge];
    NSMutableArray<NSString *> *receivedIdentifiers = [NSMutableArray array];
    XCTestExpectation *delivery = [self expectationWithDescription:@"Instance summary delivered"];
    PRBridgeObservationToken *token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *summary) {
        [receivedIdentifiers addObject:summary.identifier];
        [delivery fulfill];
    }];

    XCTAssertNotNil(token);
    [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.before"]];
    [self waitForExpectations:@[delivery] timeout:1.0];
    XCTAssertEqualObjects(receivedIdentifiers, (@[@"fixture.before"]));

    XCTAssertTrue([token cancel]);
    XCTAssertFalse([token cancel]);
    [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.after"]];
    [self drainMainQueue];
    XCTAssertEqualObjects(receivedIdentifiers, (@[@"fixture.before"]));
}

- (void)testTaskObservationDeliversImmutableFixtureStatus
{
    PRPrismBridge *bridge = [self bridge];
    NSMutableArray<NSString *> *receivedIdentifiers = [NSMutableArray array];
    NSMutableArray<NSNumber *> *receivedFractions = [NSMutableArray array];
    XCTestExpectation *delivery = [self expectationWithDescription:@"Task status delivered"];
    PRBridgeObservationToken *token = [bridge observeTaskStatusWithHandler:^(PRTaskStatus *status) {
        [receivedIdentifiers addObject:status.identifier];
        [receivedFractions addObject:@(status.progressFraction)];
        XCTAssertEqualObjects(status.title, @"Fixture Task");
        XCTAssertEqual(status.subtasks.count, (NSUInteger)1);
        XCTAssertEqualObjects(status.subtasks.firstObject.identifier, @"subtask.fixture");
        XCTAssertEqualObjects(status.subtasks.firstObject.name, @"Download fixture");
        [delivery fulfill];
    }];
    PRTaskSubtaskStatus *subtask = [[PRTaskSubtaskStatus alloc] initWithIdentifier:@"subtask.fixture"
                                                                                  name:@"Download fixture"
                                                                                 state:PRTaskStateRunning
                                                                          progressKind:PRTaskProgressKindDeterminate
                                                                      progressFraction:0.25];
    PRTaskStatus *status = [[PRTaskStatus alloc] initWithIdentifier:@"task.fixture"
                                                               title:@"Fixture Task"
                                                               state:PRTaskStateRunning
                                                        progressKind:PRTaskProgressKindDeterminate
                                                    progressFraction:0.75
                                                 cancellationAllowed:YES
                                                           subtasks:@[ subtask ]
                                                      terminalResult:nil];

    XCTAssertNotNil(token);
    XCTAssertNotNil(status);
    [bridge publishTaskStatus:status];
    [self waitForExpectations:@[delivery] timeout:1.0];
    XCTAssertEqualObjects(receivedIdentifiers, (@[@"task.fixture"]));
    XCTAssertEqualObjects(receivedFractions, (@[@0.75]));
}

- (void)testObservationsDeliverOnMainActorWithoutBlockingPublisher
{
    PRPrismBridge *bridge = [self bridge];
    XCTestExpectation *delivery = [self expectationWithDescription:@"Main actor observation delivered"];
    __block BOOL publisherReturned = NO;
    __block BOOL callbackRanOnMainThread = NO;
    PRBridgeObservationToken *token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *summary) {
        callbackRanOnMainThread = [NSThread isMainThread];
        XCTAssertTrue(callbackRanOnMainThread);
        XCTAssertTrue(publisherReturned);
        XCTAssertEqualObjects(summary.identifier, @"fixture.main-actor");
        [delivery fulfill];
    }];
    XCTAssertNotNil(token);

    dispatch_queue_t backendQueue = dispatch_queue_create("com.lloydME.PrismNativeTests.backend", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t publisherFinished = dispatch_semaphore_create(0);
    dispatch_async(backendQueue, ^{
        [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.main-actor"]];
        publisherReturned = YES;
        dispatch_semaphore_signal(publisherFinished);
    });

    XCTAssertEqual(dispatch_semaphore_wait(publisherFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [self waitForExpectations:@[delivery] timeout:1.0];
    XCTAssertTrue(callbackRanOnMainThread);
}

- (void)testErrorTranslationProvidesStableFoundationValues
{
    PRPrismBridge *bridge = [self bridge];
    NSMutableDictionary<NSString *, NSString *> *substitutionValues = [@{ @"account": @"fixture" } mutableCopy];
    PRBridgeError *authenticationError = [bridge bridgeErrorForFailureKind:PRBridgeFixtureFailureKindAuthenticationRequired
                                                              diagnosticText:@"fixture authentication failure"
                                                          substitutionValues:substitutionValues];
    substitutionValues[@"account"] = @"mutated";

    XCTAssertNotNil(authenticationError);
    XCTAssertEqualObjects(authenticationError.domain, PRBridgeErrorDomain);
    XCTAssertEqual(authenticationError.code, PRBridgeErrorCodeAuthenticationRequired);
    XCTAssertEqualObjects(authenticationError.localizationKey, @"bridge.error.authenticationRequired");
    XCTAssertEqualObjects(authenticationError.substitutionValues, (@{ @"account": @"fixture" }));
    XCTAssertEqualObjects(authenticationError.diagnosticText, @"fixture authentication failure");
    XCTAssertEqual(authenticationError.recoveryKind, PRBridgeErrorRecoveryKindAuthenticate);
    XCTAssertFalse(authenticationError.partialChangesRolledBack);
    XCTAssertEqualObjects(authenticationError.foundationError.domain, PRBridgeErrorDomain);
    XCTAssertEqual(authenticationError.foundationError.code, PRBridgeErrorCodeAuthenticationRequired);
    XCTAssertEqualObjects(authenticationError.foundationError.userInfo[PRBridgeErrorLocalizationKeyUserInfoKey],
                          @"bridge.error.authenticationRequired");
    XCTAssertEqualObjects(authenticationError.foundationError.userInfo[PRBridgeErrorSubstitutionValuesUserInfoKey],
                          (@{ @"account": @"fixture" }));
    XCTAssertEqualObjects(authenticationError.foundationError.userInfo[PRBridgeErrorDiagnosticTextUserInfoKey],
                          @"fixture authentication failure");

    PRBridgeError *unknownError = [bridge bridgeErrorForFailureKind:99
                                                       diagnosticText:@"fixture unknown failure"
                                                   substitutionValues:@{}];
    XCTAssertEqual(unknownError.code, PRBridgeErrorCodeUnknown);
    XCTAssertEqualObjects(unknownError.localizationKey, @"bridge.error.unknown");
    XCTAssertEqual(unknownError.recoveryKind, PRBridgeErrorRecoveryKindNone);
    XCTAssertFalse(unknownError.partialChangesRolledBack);
}

- (void)testCancellationBeforeQueuedFixtureDeliverySuppressesCallback
{
    PRPrismBridge *bridge = [self bridge];
    __block NSUInteger deliveryCount = 0;
    PRBridgeObservationToken *token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *) {
        deliveryCount += 1;
    }];
    dispatch_queue_t queue = dispatch_queue_create("com.lloydME.PrismNativeTests.observation", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);

    dispatch_async(queue, ^{
        dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
        [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.queued"]];
    });

    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(gate);
    dispatch_sync(queue, ^{
    });
    [self drainMainQueue];
    XCTAssertEqual(deliveryCount, (NSUInteger)0);
}

- (void)testCancellationAfterQueuedFixtureDeliveryStopsLaterCallbacks
{
    PRPrismBridge *bridge = [self bridge];
    __block NSUInteger deliveryCount = 0;
    PRBridgeObservationToken *token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *) {
        deliveryCount += 1;
    }];
    dispatch_queue_t queue = dispatch_queue_create("com.lloydME.PrismNativeTests.observation.after", DISPATCH_QUEUE_SERIAL);

    dispatch_async(queue, ^{
        [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.first"]];
    });
    dispatch_sync(queue, ^{
    });
    [self drainMainQueue];
    XCTAssertEqual(deliveryCount, (NSUInteger)1);

    XCTAssertTrue([token cancel]);
    dispatch_async(queue, ^{
        [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.second"]];
    });
    dispatch_sync(queue, ^{
    });
    [self drainMainQueue];
    XCTAssertEqual(deliveryCount, (NSUInteger)1);
}

- (void)testReleasedObservationTokenReleasesObserverAndStopsDelivery
{
    PRPrismBridge *bridge = [self bridge];
    __block __weak NSObject *weakObserver = nil;
    __block __weak PRBridgeObservationToken *weakToken = nil;
    __block NSUInteger deliveryCount = 0;
    __block PRBridgeObservationToken *token = nil;
    void (^registerObservation)(void) = ^{
        NSObject *observer = [[NSObject alloc] init];
        weakObserver = observer;
        token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *) {
            (void)observer;
            deliveryCount += 1;
        }];
        weakToken = token;
    };

    registerObservation();
    registerObservation = nil;
    XCTAssertNotNil(weakToken);
    token = nil;
    XCTAssertNil(weakToken);
    XCTAssertNil(weakObserver);

    [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.released"]];
    [self drainMainQueue];
    XCTAssertEqual(deliveryCount, (NSUInteger)0);
}

- (void)testShutdownSuppressesQueuedMainActorDelivery
{
    PRPrismBridge *bridge = [self bridge];
    __block NSUInteger deliveryCount = 0;
    PRBridgeObservationToken *token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *) {
        deliveryCount += 1;
    }];
    XCTAssertNotNil(token);

    dispatch_queue_t backendQueue = dispatch_queue_create("com.lloydME.PrismNativeTests.shutdown", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t publisherFinished = dispatch_semaphore_create(0);
    dispatch_async(backendQueue, ^{
        [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.shutdown"]];
        dispatch_semaphore_signal(publisherFinished);
    });

    XCTAssertEqual(dispatch_semaphore_wait(publisherFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    XCTAssertTrue([bridge shutdown]);
    [self drainMainQueue];
    XCTAssertTrue(token.isCancelled);
    XCTAssertEqual(deliveryCount, (NSUInteger)0);
}

- (void)testShutdownCancelsObservationTokensAndRejectsNewObservers
{
    PRPrismBridge *bridge = [self bridge];
    PRBridgeObservationToken *token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *) {
    }];

    XCTAssertNotNil(token);
    XCTAssertTrue([bridge shutdown]);
    XCTAssertTrue(token.isCancelled);
    XCTAssertFalse([token cancel]);
    XCTAssertNil([bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *) {
    }]);
    XCTAssertNil([bridge observeTaskStatusWithHandler:^(PRTaskStatus *) {
    }]);
}

@end
