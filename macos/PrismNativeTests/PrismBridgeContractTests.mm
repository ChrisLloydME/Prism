#import <XCTest/XCTest.h>

#import "../PrismNative/Bridge/PrismBridge.h"

@interface PRPrismBridge (ContractTesting)

- (void)publishInstanceSummary:(PRInstanceSummary *)summary;
- (PRBridgeError *)bridgeErrorForFailureKind:(NSInteger)failureKind
                               diagnosticText:(nullable NSString *)diagnosticText
                           substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues;

@end

typedef NS_ENUM(NSInteger, PRBridgeContractFailureKind) {
    PRBridgeContractFailureKindAuthenticationRequired = 3,
};

@interface PrismBridgeContractTests : XCTestCase

@property(nonatomic, strong) NSURL *fixtureRootURL;

@end

@implementation PrismBridgeContractTests

- (void)setUp
{
    [super setUp];
    self.fixtureRootURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"PrismNativeContract-%@", NSUUID.UUID.UUIDString]]
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
                                                  iconKey:@"icon.fixture"
                                                  groupID:@"group.fixture"];
}

- (void)drainMainQueue
{
    XCTestExpectation *drained = [self expectationWithDescription:@"Main actor queue drained"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [drained fulfill];
    });
    [self waitForExpectations:@[drained] timeout:1.0];
}

- (void)testInitializationUsesOnlyTheTemporaryFixtureRoot
{
    PRPrismBridge *bridge = [self bridge];

    XCTAssertNotNil(bridge);
    XCTAssertEqualObjects(bridge.dataRootURL.standardizedURL, self.fixtureRootURL.standardizedURL);
    XCTAssertEqual(bridge.lifecycleState, PRBridgeLifecycleStateRunning);
    XCTAssertTrue([self.fixtureRootURL.path hasPrefix:NSTemporaryDirectory()]);
    XCTAssertFalse([self.fixtureRootURL.path containsString:@"Application Support/PrismLauncher"]);
}

- (void)testEmptyFixtureDoesNotProduceAPlaceholderInstance
{
    PRPrismBridge *bridge = [self bridge];
    __block NSUInteger deliveryCount = 0;
    PRBridgeObservationToken *token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *) {
        deliveryCount += 1;
    }];

    XCTAssertNotNil(token);
    [self drainMainQueue];
    XCTAssertEqual(deliveryCount, (NSUInteger)0);
    XCTAssertTrue([token cancel]);
}

- (void)testFixtureInstanceSnapshotCrossesBridgeWithCopiedMetadata
{
    PRPrismBridge *bridge = [self bridge];
    XCTestExpectation *delivery = [self expectationWithDescription:@"Fixture snapshot delivered"];
    __block NSString *receivedIdentifier = nil;
    __block NSString *receivedName = nil;
    __block NSString *receivedIconKey = nil;
    __block NSString *receivedGroupID = nil;
    PRBridgeObservationToken *token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *summary) {
        receivedIdentifier = summary.identifier;
        receivedName = summary.name;
        receivedIconKey = summary.iconKey;
        receivedGroupID = summary.groupID;
        [delivery fulfill];
    }];

    NSMutableString *identifier = [NSMutableString stringWithString:@"fixture.bridge"];
    NSMutableString *name = [NSMutableString stringWithString:@"Fixture Bridge Instance"];
    NSMutableString *iconKey = [NSMutableString stringWithString:@"icon.bridge"];
    NSMutableString *groupID = [NSMutableString stringWithString:@"group.bridge"];
    PRInstanceSummary *summary = [[PRInstanceSummary alloc] initWithIdentifier:identifier
                                                                            name:name
                                                                         iconKey:iconKey
                                                                         groupID:groupID];
    [identifier appendString:@".mutated"];
    [name appendString:@" Mutated"];
    [iconKey appendString:@".mutated"];
    [groupID appendString:@".mutated"];

    XCTAssertNotNil(token);
    XCTAssertNotNil(summary);
    [bridge publishInstanceSummary:summary];
    [self waitForExpectations:@[delivery] timeout:1.0];
    XCTAssertEqualObjects(receivedIdentifier, @"fixture.bridge");
    XCTAssertEqualObjects(receivedName, @"Fixture Bridge Instance");
    XCTAssertEqualObjects(receivedIconKey, @"icon.bridge");
    XCTAssertEqualObjects(receivedGroupID, @"group.bridge");
}

- (void)testCancellationSuppressesQueuedFixtureSnapshot
{
    PRPrismBridge *bridge = [self bridge];
    __block NSUInteger deliveryCount = 0;
    PRBridgeObservationToken *token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *) {
        deliveryCount += 1;
    }];

    XCTAssertNotNil(token);
    [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.cancelled"]];
    XCTAssertTrue([token cancel]);
    [self drainMainQueue];
    XCTAssertEqual(deliveryCount, (NSUInteger)0);
}

- (void)testShutdownCancelsQueuedSnapshotBeforeLifecycleCallbacks
{
    __block NSMutableArray<NSString *> *lifecycleEvents = [NSMutableArray array];
    __block PRBridgeLifecycleState callbackState = PRBridgeLifecycleStateRunning;
    __block PRPrismBridge *bridge = nil;
    bridge = [[PRPrismBridge alloc] initWithDataRootURL:self.fixtureRootURL
                                     cancellationHandler:^{
                                         [lifecycleEvents addObject:@"cancel"];
                                     }
                                        shutdownHandler:^{
                                            callbackState = bridge.lifecycleState;
                                            [lifecycleEvents addObject:@"shutdown"];
                                        }];
    __block NSUInteger deliveryCount = 0;
    PRBridgeObservationToken *token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *) {
        deliveryCount += 1;
    }];

    XCTAssertNotNil(token);
    [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.shutdown"]];
    XCTAssertTrue([bridge shutdown]);
    [self drainMainQueue];
    XCTAssertEqual(deliveryCount, (NSUInteger)0);
    XCTAssertTrue(token.isCancelled);
    XCTAssertEqualObjects(lifecycleEvents, (@[ @"cancel", @"shutdown" ]));
    XCTAssertEqual(callbackState, PRBridgeLifecycleStateShuttingDown);
}

- (void)testReleasedObserverIsNotRetainedByARegisteredBridgeCallback
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
    token = nil;
    XCTAssertNil(weakToken);
    XCTAssertNil(weakObserver);

    [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.released"]];
    [self drainMainQueue];
    XCTAssertEqual(deliveryCount, (NSUInteger)0);
}

- (void)testStableErrorValuesRemainAvailableAlongsideFixtureBridgeState
{
    PRPrismBridge *bridge = [self bridge];
    PRBridgeError *error = [bridge bridgeErrorForFailureKind:PRBridgeContractFailureKindAuthenticationRequired
                                               diagnosticText:@"fixture authentication required"
                                           substitutionValues:@{ @"source": @"fixture" }];

    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PRBridgeErrorDomain);
    XCTAssertEqual(error.code, PRBridgeErrorCodeAuthenticationRequired);
    XCTAssertEqualObjects(error.localizationKey, @"bridge.error.authenticationRequired");
    XCTAssertEqualObjects(error.substitutionValues, (@{ @"source": @"fixture" }));
    XCTAssertEqual(error.recoveryKind, PRBridgeErrorRecoveryKindAuthenticate);
    XCTAssertEqualObjects(error.foundationError.domain, PRBridgeErrorDomain);
    XCTAssertEqual(error.foundationError.code, PRBridgeErrorCodeAuthenticationRequired);
}

@end
