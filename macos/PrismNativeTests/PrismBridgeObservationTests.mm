#import <XCTest/XCTest.h>

#import "../PrismNative/Bridge/PrismBridge.h"

@interface PRPrismBridge (Testing)

- (void)publishInstanceSummary:(PRInstanceSummary *)summary;
- (void)publishTaskStatus:(PRTaskStatus *)status;

@end

@interface PrismBridgeObservationTests : XCTestCase

@property(nonatomic, strong) NSURL *fixtureRootURL;

@end

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

- (void)testInstanceObservationDeliversFixtureValuesAndCancelsIdempotently
{
    PRPrismBridge *bridge = [self bridge];
    NSMutableArray<NSString *> *receivedIdentifiers = [NSMutableArray array];
    PRBridgeObservationToken *token = [bridge observeInstanceSummariesWithHandler:^(PRInstanceSummary *summary) {
        [receivedIdentifiers addObject:summary.identifier];
    }];

    XCTAssertNotNil(token);
    [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.before"]];
    XCTAssertEqualObjects(receivedIdentifiers, (@[@"fixture.before"]));

    XCTAssertTrue([token cancel]);
    XCTAssertFalse([token cancel]);
    [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.after"]];
    XCTAssertEqualObjects(receivedIdentifiers, (@[@"fixture.before"]));
}

- (void)testTaskObservationDeliversImmutableFixtureStatus
{
    PRPrismBridge *bridge = [self bridge];
    NSMutableArray<NSString *> *receivedIdentifiers = [NSMutableArray array];
    NSMutableArray<NSNumber *> *receivedFractions = [NSMutableArray array];
    PRBridgeObservationToken *token = [bridge observeTaskStatusWithHandler:^(PRTaskStatus *status) {
        [receivedIdentifiers addObject:status.identifier];
        [receivedFractions addObject:@(status.progressFraction)];
    }];
    PRTaskStatus *status = [[PRTaskStatus alloc] initWithIdentifier:@"task.fixture"
                                                               state:PRTaskStateRunning
                                                        progressKind:PRTaskProgressKindDeterminate
                                                    progressFraction:0.75
                                                 cancellationAllowed:YES];

    XCTAssertNotNil(token);
    XCTAssertNotNil(status);
    [bridge publishTaskStatus:status];
    XCTAssertEqualObjects(receivedIdentifiers, (@[@"task.fixture"]));
    XCTAssertEqualObjects(receivedFractions, (@[@0.75]));
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
    XCTAssertEqual(deliveryCount, (NSUInteger)1);

    XCTAssertTrue([token cancel]);
    dispatch_async(queue, ^{
        [bridge publishInstanceSummary:[self summaryWithIdentifier:@"fixture.second"]];
    });
    dispatch_sync(queue, ^{
    });
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
