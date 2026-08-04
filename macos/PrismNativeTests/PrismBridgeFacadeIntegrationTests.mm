#import <XCTest/XCTest.h>

#import "../PrismNative/Bridge/PrismBridge.h"

#include "FrontendFacade.h"

#include <atomic>
#include <chrono>
#include <dispatch/dispatch.h>
#include <memory>
#include <string>
#include <utility>
#include <vector>

@interface PRPrismBridge (FrontendTesting)

- (nullable instancetype)initWithDataRootURL:(NSURL *)dataRootURL
                          cancellationHandler:(nullable PRBridgeLifecycleHandler)cancellationHandler
                             shutdownHandler:(nullable PRBridgeLifecycleHandler)shutdownHandler
                   frontendRuntimeDependencies:(FrontendRuntimeDependencies)runtimeDependencies;

@end

namespace {

FrontendInstanceSnapshot fixtureSnapshot(const char *identifier,
                                         const char *name,
                                         const char *iconKey,
                                         const char *groupID)
{
    return FrontendInstanceSnapshot{identifier, name, iconKey, groupID};
}

FrontendRuntimeDependencies baseFixtureDependencies()
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] {
        return std::chrono::system_clock::time_point(std::chrono::seconds(123));
    };
    dependencies.cancelPendingWork = [] {};
    dependencies.shutdown = [] {};
    return dependencies;
}

}  // namespace

@interface PrismBridgeFacadeIntegrationTests : XCTestCase

@property(nonatomic, strong) NSURL *fixtureRootURL;

@end

@implementation PrismBridgeFacadeIntegrationTests

- (void)setUp
{
    [super setUp];
    self.fixtureRootURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"PrismNativeFacade-%@", NSUUID.UUID.UUIDString]]
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

- (PRPrismBridge *)bridgeWithDependencies:(FrontendRuntimeDependencies)dependencies
                       cancellationHandler:(PRBridgeLifecycleHandler)cancellationHandler
                          shutdownHandler:(PRBridgeLifecycleHandler)shutdownHandler
{
    return [[PRPrismBridge alloc] initWithDataRootURL:self.fixtureRootURL
                                   cancellationHandler:cancellationHandler
                                      shutdownHandler:shutdownHandler
                            frontendRuntimeDependencies:std::move(dependencies)];
}

- (void)testFacadeSnapshotsAreLoadedAndConvertedOnMainActor
{
    auto loadedRoot = std::make_shared<std::string>();
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadInstanceSnapshots = [loadedRoot](const std::filesystem::path& root) {
        *loadedRoot = root.string();
        return std::vector<FrontendInstanceSnapshot>{
            fixtureSnapshot("fixture.one", "Fixture One", "icon.one", "group.one"),
            fixtureSnapshot("fixture.two", "Fixture Two", "", ""),
        };
    };
    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *completion = [self expectationWithDescription:@"Facade snapshots completed"];
    __block NSArray<PRInstanceSummary *> *receivedSummaries = nil;
    __block PRBridgeError *receivedError = nil;
    __block BOOL callbackRanOnMainThread = NO;
    PRBridgeObservationToken *token = [bridge loadInstanceSummariesWithCompletion:^(NSArray<PRInstanceSummary *> *summaries,
                                                                                      PRBridgeError *error) {
        callbackRanOnMainThread = [NSThread isMainThread];
        receivedSummaries = summaries;
        receivedError = error;
        [completion fulfill];
    }];

    XCTAssertNotNil(token);
    [self waitForExpectations:@[ completion ] timeout:2.0];
    XCTAssertTrue(callbackRanOnMainThread);
    XCTAssertNil(receivedError);
    XCTAssertEqual(receivedSummaries.count, (NSUInteger)2);
    XCTAssertEqualObjects(receivedSummaries[0].identifier, @"fixture.one");
    XCTAssertEqualObjects(receivedSummaries[0].name, @"Fixture One");
    XCTAssertEqualObjects(receivedSummaries[0].iconKey, @"icon.one");
    XCTAssertEqualObjects(receivedSummaries[0].groupID, @"group.one");
    XCTAssertEqualObjects(receivedSummaries[1].identifier, @"fixture.two");
    XCTAssertNil(receivedSummaries[1].iconKey);
    XCTAssertNil(receivedSummaries[1].groupID);
    XCTAssertEqualObjects([NSString stringWithUTF8String:loadedRoot->c_str()], self.fixtureRootURL.standardizedURL.path);
    XCTAssertTrue(token.isCancelled);
}

- (void)testFacadeCommandsConvertFoundationIdentifiersAndPreserveFixtureOutcomes
{
    auto launchCalls = std::make_shared<std::vector<std::string>>();
    auto stopCalls = std::make_shared<std::vector<std::string>>();
    auto commandRootMatches = std::make_shared<std::atomic<bool>>(true);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.launchInstance = [launchCalls, commandRootMatches, fixtureRoot = self.fixtureRootURL.path.UTF8String](
                                      const std::filesystem::path& root,
                                      const std::string& identifier) {
        *commandRootMatches = *commandRootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        launchCalls->push_back(identifier);
        if (identifier == "fixture.one") {
            return FrontendInstanceCommandResult::Succeeded;
        }
        if (identifier == "unknown-instance") {
            return FrontendInstanceCommandResult::UnknownInstance;
        }
        return FrontendInstanceCommandResult::Rejected;
    };
    dependencies.stopInstance = [stopCalls, commandRootMatches, fixtureRoot = self.fixtureRootURL.path.UTF8String](
                                    const std::filesystem::path& root,
                                    const std::string& identifier) {
        *commandRootMatches = *commandRootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        stopCalls->push_back(identifier);
        if (identifier == "fixture.one") {
            return FrontendInstanceCommandResult::Succeeded;
        }
        if (identifier == "unknown-instance") {
            return FrontendInstanceCommandResult::UnknownInstance;
        }
        return FrontendInstanceCommandResult::Rejected;
    };
    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    __block PRInstanceCommandResult *receivedResult = nil;
    __block PRBridgeError *receivedError = nil;
    void (^runCommand)(PRInstanceCommandKind, NSString *) = ^(PRInstanceCommandKind kind, NSString *identifier) {
        receivedResult = nil;
        receivedError = nil;
        XCTestExpectation *completion = [self expectationWithDescription:@"Facade command completed"];
        PRBridgeObservationToken *token = nil;
        PRInstanceCommandCompletionHandler handler = ^(PRInstanceCommandResult *result, PRBridgeError *error) {
            XCTAssertTrue([NSThread isMainThread]);
            receivedResult = result;
            receivedError = error;
            [completion fulfill];
        };
        if (kind == PRInstanceCommandKindLaunch) {
            token = [bridge launchInstanceWithIdentifier:identifier completion:handler];
        } else {
            token = [bridge stopInstanceWithIdentifier:identifier completion:handler];
        }
        XCTAssertNotNil(token);
        [self waitForExpectations:@[ completion ] timeout:2.0];
    };

    NSMutableString *mutableIdentifier = [NSMutableString stringWithString:@" fixture.one "];
    runCommand(PRInstanceCommandKindLaunch, mutableIdentifier);
    [mutableIdentifier setString:@"fixture.rejected.after-call"];
    XCTAssertNil(receivedError);
    XCTAssertEqual(receivedResult.kind, PRInstanceCommandKindLaunch);
    XCTAssertEqual(receivedResult.outcome, PRInstanceCommandOutcomeSucceeded);
    XCTAssertEqualObjects(receivedResult.identifier, @"fixture.one");

    runCommand(PRInstanceCommandKindLaunch, @"fixture.one");
    XCTAssertEqual(receivedResult.outcome, PRInstanceCommandOutcomeSucceeded);
    runCommand(PRInstanceCommandKindLaunch, @"unknown-instance");
    XCTAssertEqual(receivedResult.outcome, PRInstanceCommandOutcomeUnknownInstance);
    runCommand(PRInstanceCommandKindLaunch, @"rejected-instance");
    XCTAssertEqual(receivedResult.outcome, PRInstanceCommandOutcomeRejected);

    runCommand(PRInstanceCommandKindStop, @"fixture.one");
    XCTAssertEqual(receivedResult.kind, PRInstanceCommandKindStop);
    XCTAssertEqual(receivedResult.outcome, PRInstanceCommandOutcomeSucceeded);
    runCommand(PRInstanceCommandKindStop, @"fixture.one");
    XCTAssertEqual(receivedResult.outcome, PRInstanceCommandOutcomeSucceeded);
    runCommand(PRInstanceCommandKindStop, @"unknown-instance");
    XCTAssertEqual(receivedResult.outcome, PRInstanceCommandOutcomeUnknownInstance);
    runCommand(PRInstanceCommandKindStop, @"rejected-instance");
    XCTAssertEqual(receivedResult.outcome, PRInstanceCommandOutcomeRejected);

    runCommand(PRInstanceCommandKindLaunch, @"   ");
    XCTAssertNil(receivedResult);
    XCTAssertNotNil(receivedError);
    XCTAssertEqual(receivedError.code, PRBridgeErrorCodeInvalidInput);

    XCTAssertTrue(commandRootMatches->load());
    XCTAssertEqual(launchCalls->size(), (NSUInteger)4);
    XCTAssertEqual(stopCalls->size(), (NSUInteger)4);
    XCTAssertEqualObjects([NSString stringWithUTF8String:launchCalls->front().c_str()], @"fixture.one");
    XCTAssertEqualObjects([NSString stringWithUTF8String:launchCalls->back().c_str()], @"rejected-instance");
}

- (void)testFacadeTaskSnapshotsAndCancellationConvertFoundationContracts
{
    auto taskRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto taskSnapshotCalls = std::make_shared<std::vector<std::string>>();
    auto taskCancellationCalls = std::make_shared<std::vector<std::string>>();
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadTaskSnapshot = [taskRootMatches, taskSnapshotCalls, fixtureRoot = self.fixtureRootURL.path.UTF8String](
                                       const std::filesystem::path& root,
                                       const std::string& identifier) -> std::optional<FrontendTaskSnapshot> {
        *taskRootMatches = *taskRootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        taskSnapshotCalls->push_back(identifier);
        if (identifier == "task.running") {
            return FrontendTaskSnapshot{ identifier,
                                         "Fixture Task",
                                         FrontendTaskState::Running,
                                         FrontendTaskProgressKind::Determinate,
                                         0.75,
                                         true,
                                         { { "subtask.fixture", "Download fixture", FrontendTaskState::Running,
                                             FrontendTaskProgressKind::Determinate, 0.25 } },
                                         std::nullopt };
        }
        if (identifier == "task.failed") {
            return FrontendTaskSnapshot{
                identifier,
                "Failed Fixture Task",
                FrontendTaskState::Failed,
                FrontendTaskProgressKind::Determinate,
                1.0,
                false,
                {},
                FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Failed,
                                            "task.failed",
                                            { { "taskIdentifier", identifier } },
                                            "fixture failure",
                                            true },
            };
        }
        return std::nullopt;
    };
    dependencies.cancelTask = [taskRootMatches, taskCancellationCalls, fixtureRoot = self.fixtureRootURL.path.UTF8String](
                                  const std::filesystem::path& root,
                                  const std::string& identifier) {
        *taskRootMatches = *taskRootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        taskCancellationCalls->push_back(identifier);
        if (identifier == "task.running") {
            return taskCancellationCalls->size() == 1 ? FrontendTaskCancellationResult::Requested
                                                      : FrontendTaskCancellationResult::AlreadyTerminal;
        }
        if (identifier == "unknown-task") {
            return FrontendTaskCancellationResult::UnknownTask;
        }
        return FrontendTaskCancellationResult::Rejected;
    };
    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *runningCompletion = [self expectationWithDescription:@"Running task loaded"];
    XCTestExpectation *failedCompletion = [self expectationWithDescription:@"Failed task loaded"];
    XCTestExpectation *unknownCompletion = [self expectationWithDescription:@"Unknown task rejected"];
    __block PRTaskStatus *runningStatus = nil;
    __block PRTaskStatus *failedStatus = nil;
    __block PRBridgeError *unknownError = nil;
    PRBridgeObservationToken *runningToken = [bridge loadTaskStatusWithIdentifier:@"task.running"
                                                                        completion:^(PRTaskStatus *status, PRBridgeError *error) {
        XCTAssertTrue([NSThread isMainThread]);
        runningStatus = status;
        XCTAssertNil(error);
        [runningCompletion fulfill];
    }];
    PRBridgeObservationToken *failedToken = [bridge loadTaskStatusWithIdentifier:@"task.failed"
                                                                       completion:^(PRTaskStatus *status, PRBridgeError *error) {
        XCTAssertTrue([NSThread isMainThread]);
        failedStatus = status;
        XCTAssertNil(error);
        [failedCompletion fulfill];
    }];
    PRBridgeObservationToken *unknownToken = [bridge loadTaskStatusWithIdentifier:@"unknown-task"
                                                                        completion:^(PRTaskStatus *status, PRBridgeError *error) {
        XCTAssertNil(status);
        unknownError = error;
        [unknownCompletion fulfill];
    }];
    XCTAssertNotNil(runningToken);
    XCTAssertNotNil(failedToken);
    XCTAssertNotNil(unknownToken);
    [self waitForExpectations:@[ runningCompletion, failedCompletion, unknownCompletion ] timeout:2.0];

    XCTAssertEqualObjects(runningStatus.identifier, @"task.running");
    XCTAssertEqualObjects(runningStatus.title, @"Fixture Task");
    XCTAssertEqual(runningStatus.state, PRTaskStateRunning);
    XCTAssertEqual(runningStatus.progressKind, PRTaskProgressKindDeterminate);
    XCTAssertEqual(runningStatus.progressFraction, 0.75);
    XCTAssertTrue(runningStatus.cancellationAllowed);
    XCTAssertEqual(runningStatus.subtasks.count, (NSUInteger)1);
    XCTAssertEqualObjects(runningStatus.subtasks.firstObject.identifier, @"subtask.fixture");
    XCTAssertEqualObjects(runningStatus.subtasks.firstObject.name, @"Download fixture");
    XCTAssertEqualObjects(failedStatus.terminalResult.localizationKey, @"task.failed");
    XCTAssertEqual(failedStatus.terminalResult.outcome, PRTaskTerminalOutcomeFailed);
    XCTAssertEqualObjects(failedStatus.terminalResult.substitutionValues, (@{ @"taskIdentifier": @"task.failed" }));
    XCTAssertTrue(failedStatus.terminalResult.partialChangesRolledBack);
    XCTAssertNotNil(unknownError);
    XCTAssertEqual(unknownError.code, PRBridgeErrorCodeDataUnavailable);
    XCTAssertEqual(unknownError.recoveryKind, PRBridgeErrorRecoveryKindRetry);
    XCTAssertEqualObjects(unknownError.substitutionValues, (@{ @"taskIdentifier": @"unknown-task" }));

    void (^runCancellation)(NSString *, PRTaskCancellationOutcome) = ^(NSString *identifier,
                                                                         PRTaskCancellationOutcome expectedOutcome) {
        XCTestExpectation *completion = [self expectationWithDescription:@"Task cancellation completed"];
        __block PRTaskCancellationResult *receivedResult = nil;
        __block PRBridgeError *receivedError = nil;
        PRBridgeObservationToken *token = [bridge cancelTaskWithIdentifier:identifier
                                                                   completion:^(PRTaskCancellationResult *result,
                                                                                PRBridgeError *error) {
            XCTAssertTrue([NSThread isMainThread]);
            receivedResult = result;
            receivedError = error;
            [completion fulfill];
        }];
        XCTAssertNotNil(token);
        [self waitForExpectations:@[ completion ] timeout:2.0];
        XCTAssertNil(receivedError);
        XCTAssertEqual(receivedResult.outcome, expectedOutcome);
        NSString *normalizedIdentifier = [identifier stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        XCTAssertEqualObjects(receivedResult.identifier, normalizedIdentifier);
    };

    NSMutableString *mutableTaskIdentifier = [NSMutableString stringWithString:@" task.running "];
    runCancellation(mutableTaskIdentifier, PRTaskCancellationOutcomeRequested);
    [mutableTaskIdentifier setString:@"task.mutated.after-call"];
    runCancellation(@"task.running", PRTaskCancellationOutcomeAlreadyTerminal);
    runCancellation(@"unknown-task", PRTaskCancellationOutcomeUnknownTask);
    runCancellation(@"task.failed", PRTaskCancellationOutcomeRejected);

    XCTestExpectation *invalidInputCompletion = [self expectationWithDescription:@"Invalid task identifier rejected"];
    __block PRTaskStatus *invalidStatus = nil;
    __block PRBridgeError *invalidError = nil;
    PRBridgeObservationToken *invalidToken = [bridge loadTaskStatusWithIdentifier:@"   "
                                                                        completion:^(PRTaskStatus *status, PRBridgeError *error) {
        invalidStatus = status;
        invalidError = error;
        [invalidInputCompletion fulfill];
    }];
    XCTAssertNotNil(invalidToken);
    [self waitForExpectations:@[ invalidInputCompletion ] timeout:2.0];
    XCTAssertNil(invalidStatus);
    XCTAssertEqual(invalidError.code, PRBridgeErrorCodeInvalidInput);
    XCTAssertTrue(taskRootMatches->load());
    XCTAssertTrue((*taskSnapshotCalls == std::vector<std::string>{ "task.running", "task.failed", "unknown-task" }));
    XCTAssertTrue((*taskCancellationCalls
                   == std::vector<std::string>{ "task.running", "task.running", "unknown-task", "task.failed" }));
}

- (void)testFacadeChangesAreConvertedAndPublishedInOrder
{
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadInstanceChanges = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceChange>{
            { FrontendInstanceChangeKind::Added, fixtureSnapshot("fixture.one", "Fixture One", "icon.one", "group.one") },
            { FrontendInstanceChangeKind::Updated, fixtureSnapshot("fixture.one", "Fixture One Updated", "icon.updated", "group.one") },
            { FrontendInstanceChangeKind::Removed, fixtureSnapshot("fixture.two", "", "", "") },
        };
    };
    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *observerDelivery = [self expectationWithDescription:@"Facade changes observed"];
    observerDelivery.expectedFulfillmentCount = 3;
    NSMutableArray<NSNumber *> *observedKinds = [NSMutableArray array];
    PRBridgeObservationToken *observerToken = [bridge observeInstanceChangesWithHandler:^(PRInstanceChange *change) {
        XCTAssertTrue([NSThread isMainThread]);
        [observedKinds addObject:@(change.kind)];
        [observerDelivery fulfill];
    }];
    XCTAssertNotNil(observerToken);

    XCTestExpectation *completion = [self expectationWithDescription:@"Facade changes completed"];
    __block NSArray<PRInstanceChange *> *receivedChanges = nil;
    __block PRBridgeError *receivedError = nil;
    PRBridgeObservationToken *requestToken = [bridge loadInstanceChangesWithCompletion:^(NSArray<PRInstanceChange *> *changes,
                                                                                            PRBridgeError *error) {
        XCTAssertTrue([NSThread isMainThread]);
        receivedChanges = changes;
        receivedError = error;
        [completion fulfill];
    }];

    XCTAssertNotNil(requestToken);
    [self waitForExpectations:@[ observerDelivery, completion ] timeout:2.0];
    XCTAssertNil(receivedError);
    XCTAssertEqual(receivedChanges.count, (NSUInteger)3);
    XCTAssertEqualObjects(observedKinds, (@[ @(PRInstanceChangeKindAdded),
                                              @(PRInstanceChangeKindUpdated),
                                              @(PRInstanceChangeKindRemoved) ]));
    XCTAssertEqual(receivedChanges[0].kind, PRInstanceChangeKindAdded);
    XCTAssertEqualObjects(receivedChanges[0].identifier, @"fixture.one");
    XCTAssertEqualObjects(receivedChanges[0].summary.name, @"Fixture One");
    XCTAssertEqual(receivedChanges[1].kind, PRInstanceChangeKindUpdated);
    XCTAssertEqualObjects(receivedChanges[1].summary.name, @"Fixture One Updated");
    XCTAssertEqual(receivedChanges[2].kind, PRInstanceChangeKindRemoved);
    XCTAssertEqualObjects(receivedChanges[2].identifier, @"fixture.two");
    XCTAssertNil(receivedChanges[2].summary);
    XCTAssertTrue(requestToken.isCancelled);
    XCTAssertTrue([observerToken cancel]);
}

- (void)testInvalidFacadeSnapshotBecomesStableBridgeError
{
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadInstanceSnapshots = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceSnapshot>{ fixtureSnapshot("", "Invalid", "", "") };
    };
    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *completion = [self expectationWithDescription:@"Invalid snapshot completed"];
    __block NSArray<PRInstanceSummary *> *receivedSummaries = nil;
    __block PRBridgeError *receivedError = nil;
    PRBridgeObservationToken *token = [bridge loadInstanceSummariesWithCompletion:^(NSArray<PRInstanceSummary *> *summaries,
                                                                                      PRBridgeError *error) {
        receivedSummaries = summaries;
        receivedError = error;
        [completion fulfill];
    }];

    XCTAssertNotNil(token);
    [self waitForExpectations:@[ completion ] timeout:2.0];
    XCTAssertEqual(receivedSummaries.count, (NSUInteger)0);
    XCTAssertNotNil(receivedError);
    XCTAssertEqual(receivedError.code, PRBridgeErrorCodeInvalidInput);
    XCTAssertEqualObjects(receivedError.foundationError.domain, PRBridgeErrorDomain);
    XCTAssertEqual(receivedError.foundationError.code, PRBridgeErrorCodeInvalidInput);
}

- (void)testCancellingQueuedFacadeRequestSuppressesCompletion
{
    auto enteredLoader = dispatch_semaphore_create(0);
    auto releaseLoader = dispatch_semaphore_create(0);
    auto loaderFinished = dispatch_semaphore_create(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadInstanceSnapshots = [enteredLoader, releaseLoader, loaderFinished](const std::filesystem::path&) {
        dispatch_semaphore_signal(enteredLoader);
        dispatch_semaphore_wait(releaseLoader, DISPATCH_TIME_FOREVER);
        dispatch_semaphore_signal(loaderFinished);
        return std::vector<FrontendInstanceSnapshot>{ fixtureSnapshot("fixture.cancelled", "Cancelled", "", "") };
    };
    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    __block NSUInteger completionCount = 0;
    PRBridgeObservationToken *token = [bridge loadInstanceSummariesWithCompletion:^(NSArray<PRInstanceSummary *> *, PRBridgeError *) {
        completionCount += 1;
    }];
    XCTAssertNotNil(token);
    XCTAssertEqual(dispatch_semaphore_wait(enteredLoader, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(releaseLoader);
    XCTAssertEqual(dispatch_semaphore_wait(loaderFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);

    XCTestExpectation *drained = [self expectationWithDescription:@"Cancelled request queue drained"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [drained fulfill];
    });
    [self waitForExpectations:@[ drained ] timeout:2.0];
    XCTAssertEqual(completionCount, (NSUInteger)0);
}

- (void)testShutdownStopsTheRealFacadeAndReleasesLifecycleCallbacks
{
    auto cancelCount = std::make_shared<std::atomic<int>>(0);
    auto facadeShutdownCount = std::make_shared<std::atomic<int>>(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.cancelPendingWork = [cancelCount] {
        cancelCount->fetch_add(1);
    };
    dependencies.shutdown = [facadeShutdownCount] {
        facadeShutdownCount->fetch_add(1);
    };

    __block NSMutableArray<NSString *> *lifecycleEvents = [NSMutableArray array];
    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:^{
                                           [lifecycleEvents addObject:@"cancel"];
                                       }
                                          shutdownHandler:^{
                                              [lifecycleEvents addObject:@"shutdown"];
                                          }];
    XCTAssertNotNil(bridge);
    XCTAssertEqual(bridge.lifecycleState, PRBridgeLifecycleStateRunning);
    XCTAssertTrue([bridge shutdown]);
    XCTAssertFalse([bridge shutdown]);
    XCTAssertEqual(bridge.lifecycleState, PRBridgeLifecycleStateStopped);
    XCTAssertEqual(cancelCount->load(), 1);
    XCTAssertEqual(facadeShutdownCount->load(), 1);
    XCTAssertEqualObjects(lifecycleEvents, (@[ @"cancel", @"shutdown" ]));
    XCTAssertNil([bridge loadInstanceSummariesWithCompletion:^(NSArray<PRInstanceSummary *> *, PRBridgeError *) {
    }]);
    XCTAssertNil([bridge loadTaskStatusWithIdentifier:@"task.fixture" completion:^(PRTaskStatus *, PRBridgeError *) {
    }]);
    XCTAssertNil([bridge cancelTaskWithIdentifier:@"task.fixture"
                                           completion:^(PRTaskCancellationResult *, PRBridgeError *) {
                                           }]);
    XCTAssertNil([bridge launchInstanceWithIdentifier:@"fixture.one" completion:^(PRInstanceCommandResult *, PRBridgeError *) {
    }]);
}

@end
