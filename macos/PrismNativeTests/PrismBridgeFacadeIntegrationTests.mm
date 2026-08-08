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

FrontendInstanceSettingsSnapshot fixtureSettings(const std::string& identifier)
{
    FrontendInstanceSettingsSnapshot settings;
    settings.id = identifier;
    settings.windowOverrideEnabled = true;
    settings.launchMaximized = true;
    settings.windowWidth = 1280;
    settings.windowHeight = 720;
    settings.closeAfterLaunch = true;
    settings.consoleOverrideEnabled = true;
    settings.showConsole = true;
    settings.showConsoleOnError = true;
    settings.globalDataPacksEnabled = true;
    settings.globalDataPacksPath = "datapacks";
    settings.gameTimeOverrideEnabled = true;
    settings.showGameTime = true;
    settings.recordGameTime = true;
    settings.countGameTime = true;
    settings.joinServerOnLaunch = true;
    settings.joinTarget = FrontendInstanceJoinTarget::Server;
    settings.joinServerAddress = "fixture.example:25565";
    settings.overrideModDownloadLoaders = true;
    settings.modDownloadLoaders = { "Fabric", "Quilt" };
    settings.javaLocationOverrideEnabled = true;
    settings.javaPath = "/fixture/bin/java";
    settings.ignoreJavaCompatibility = true;
    settings.memoryOverrideEnabled = true;
    settings.minMemoryMiB = 512;
    settings.maxMemoryMiB = 4096;
    settings.permGenMiB = 128;
    settings.lowMemoryWarning = true;
    settings.javaArgumentsOverrideEnabled = true;
    settings.jvmArguments = "-Dfixture=true";
    settings.commandOverrideEnabled = true;
    settings.preLaunchCommand = "prepare-fixture";
    settings.wrapperCommand = "wrapper-fixture";
    settings.postExitCommand = "cleanup-fixture";
    settings.legacySettingsOverrideEnabled = true;
    settings.nativeWorkaroundsOverrideEnabled = true;
    settings.useNativeGLFW = true;
    settings.customGLFWPath = "/fixture/libglfw.dylib";
    settings.useNativeOpenAL = true;
    settings.customOpenALPath = "/fixture/libopenal.dylib";
    return settings;
}

FrontendGlobalSettingsSnapshot fixtureGlobalSettings(const std::filesystem::path& fixtureRoot)
{
    FrontendGlobalSettingsSnapshot settings;
    settings.instanceDirectory = fixtureRoot / "instances";
    settings.iconTheme = "fixture-icons";
    settings.applicationTheme = "fixture-theme";
    settings.backgroundCat = "fixture-cat";
    settings.catOpacity = 73;
    settings.catFit = "strech";
    settings.language = "en_US";
    settings.useSystemLocale = true;
    settings.menuBarInsteadOfToolBar = true;
    settings.statusBarVisible = false;
    settings.toolbarsLocked = true;
    settings.numberOfConcurrentTasks = 10;
    settings.numberOfConcurrentDownloads = 6;
    settings.numberOfManualRetries = 2;
    settings.requestTimeoutSeconds = 60;
    settings.consoleFont = "Menlo";
    settings.consoleFontSize = 12;
    settings.consoleMaxLines = 20000;
    settings.consoleOverflowStop = false;
    settings.showConsole = true;
    settings.autoCloseConsole = true;
    settings.showConsoleOnError = false;
    settings.logPrePostOutput = true;
    return settings;
}

FrontendJavaInstallationSnapshot fixtureJavaInstallation(
    const std::filesystem::path& fixtureRoot,
    const std::string& identifier,
    FrontendJavaInstallationValidity validity = FrontendJavaInstallationValidity::Valid)
{
    FrontendJavaInstallationSnapshot installation;
    installation.id = identifier;
    installation.version = validity == FrontendJavaInstallationValidity::Valid ? "21.0.2" : "8.0.392";
    installation.vendor = "Fixture JDK";
    installation.architecture = "aarch64";
    installation.executablePath = fixtureRoot / "java" / identifier / "bin" / "java";
    installation.is64Bit = true;
    installation.managed = identifier == "fixture-managed";
    installation.validity = validity;
    installation.diagnosticText = validity == FrontendJavaInstallationValidity::Valid
        ? ""
        : "Fixture Java installation is not usable.";
    return installation;
}

FrontendAccountSnapshot fixtureAccount(
    const std::string& identifier,
    const std::string& displayName,
    FrontendAccountType type = FrontendAccountType::Microsoft,
    FrontendAccountState state = FrontendAccountState::Online,
    bool ownsMinecraft = true,
    bool isBusy = false,
    bool canBeSelected = true)
{
    FrontendAccountSnapshot account;
    account.id = identifier;
    account.displayName = displayName;
    account.type = type;
    account.state = state;
    account.ownsMinecraft = ownsMinecraft;
    account.isBusy = isBusy;
    account.canBeSelected = canBeSelected;
    account.diagnosticText = state == FrontendAccountState::Online ? "" : "Fixture account is not ready.";
    return account;
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

- (void)testFacadeDetailsAndNotesAreConvertedAndConfirmedOnMainActor
{
    auto detailsCalls = std::make_shared<std::vector<std::string>>();
    auto notesCalls = std::make_shared<std::vector<std::string>>();
    auto detailsRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto notesRootMatches = std::make_shared<std::atomic<bool>>(true);
    const std::string fixtureRoot = self.fixtureRootURL.path.UTF8String;

    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadInstanceDetails = [detailsCalls, detailsRootMatches, fixtureRoot](
                                            const std::filesystem::path& root,
                                            const std::string& identifier)
        -> std::optional<FrontendInstanceDetailsSnapshot> {
        *detailsRootMatches = *detailsRootMatches
            && root == std::filesystem::path(fixtureRoot).lexically_normal();
        detailsCalls->push_back(identifier);
        if (identifier != "fixture.one") {
            return std::nullopt;
        }
        return FrontendInstanceDetailsSnapshot{
            "fixture.one",
            "Fixture One",
            "icon.one",
            "group.one",
            "Minecraft",
            "Existing\nfixture notes ",
            true,
        };
    };
    dependencies.updateInstanceNotes = [notesCalls, notesRootMatches, fixtureRoot](
                                            const std::filesystem::path& root,
                                            const std::string& identifier,
                                            const std::string& notes) {
        *notesRootMatches = *notesRootMatches
            && root == std::filesystem::path(fixtureRoot).lexically_normal();
        notesCalls->push_back(identifier + ":" + notes);
        if (identifier == "fixture.one") {
            return FrontendInstanceNotesUpdateResult{
                FrontendInstanceNotesUpdateOutcome::Succeeded,
                notes,
            };
        }
        if (identifier == "unknown-instance") {
            return FrontendInstanceNotesUpdateResult{
                FrontendInstanceNotesUpdateOutcome::UnknownInstance,
                {},
            };
        }
        return FrontendInstanceNotesUpdateResult{
            FrontendInstanceNotesUpdateOutcome::Rejected,
            {},
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *detailsCompletion = [self expectationWithDescription:@"Facade details completed"];
    __block PRInstanceDetails *receivedDetails = nil;
    __block PRBridgeError *receivedDetailsError = nil;
    __block BOOL detailsCallbackRanOnMainThread = NO;
    NSMutableString *mutableIdentifier = [NSMutableString stringWithString:@" fixture.one "];
    PRBridgeObservationToken *detailsToken = [bridge loadInstanceDetailsWithIdentifier:mutableIdentifier
                                                                                completion:^(PRInstanceDetails *details,
                                                                                              PRBridgeError *error) {
        detailsCallbackRanOnMainThread = [NSThread isMainThread];
        receivedDetails = details;
        receivedDetailsError = error;
        [detailsCompletion fulfill];
    }];
    [mutableIdentifier setString:@"fixture.changed.after-call"];

    XCTAssertNotNil(detailsToken);
    [self waitForExpectations:@[ detailsCompletion ] timeout:2.0];
    XCTAssertTrue(detailsCallbackRanOnMainThread);
    XCTAssertNil(receivedDetailsError);
    XCTAssertEqualObjects(receivedDetails.identifier, @"fixture.one");
    XCTAssertEqualObjects(receivedDetails.name, @"Fixture One");
    XCTAssertEqualObjects(receivedDetails.iconKey, @"icon.one");
    XCTAssertEqualObjects(receivedDetails.groupID, @"group.one");
    XCTAssertEqualObjects(receivedDetails.instanceType, @"Minecraft");
    XCTAssertEqualObjects(receivedDetails.notes, @"Existing\nfixture notes ");
    XCTAssertTrue(receivedDetails.notesEditable);
    XCTAssertTrue(detailsToken.isCancelled);

    XCTestExpectation *missingDetailsCompletion = [self expectationWithDescription:@"Missing details completed"];
    receivedDetails = nil;
    receivedDetailsError = nil;
    PRBridgeObservationToken *missingDetailsToken =
        [bridge loadInstanceDetailsWithIdentifier:@"unknown-instance"
                                         completion:^(PRInstanceDetails *details, PRBridgeError *error) {
        receivedDetails = details;
        receivedDetailsError = error;
        [missingDetailsCompletion fulfill];
    }];
    XCTAssertNotNil(missingDetailsToken);
    [self waitForExpectations:@[ missingDetailsCompletion ] timeout:2.0];
    XCTAssertNil(receivedDetails);
    XCTAssertEqual(receivedDetailsError.code, PRBridgeErrorCodeDataUnavailable);
    XCTAssertEqual(receivedDetailsError.recoveryKind, PRBridgeErrorRecoveryKindRetry);
    XCTAssertEqualObjects(receivedDetailsError.substitutionValues[@"instanceIdentifier"], @"unknown-instance");

    XCTestExpectation *invalidDetailsCompletion = [self expectationWithDescription:@"Invalid details completed"];
    receivedDetails = nil;
    receivedDetailsError = nil;
    PRBridgeObservationToken *invalidDetailsToken =
        [bridge loadInstanceDetailsWithIdentifier:@"   "
                                         completion:^(PRInstanceDetails *details, PRBridgeError *error) {
        receivedDetails = details;
        receivedDetailsError = error;
        [invalidDetailsCompletion fulfill];
    }];
    XCTAssertNotNil(invalidDetailsToken);
    [self waitForExpectations:@[ invalidDetailsCompletion ] timeout:2.0];
    XCTAssertNil(receivedDetails);
    XCTAssertEqual(receivedDetailsError.code, PRBridgeErrorCodeInvalidInput);

    __block PRInstanceNotesUpdateResult *receivedNotesResult = nil;
    __block PRBridgeError *receivedNotesError = nil;
    __block BOOL notesCallbackRanOnMainThread = NO;
    void (^runNotesUpdate)(NSString *, NSString *) = ^(NSString *identifier, NSString *notes) {
        receivedNotesResult = nil;
        receivedNotesError = nil;
        notesCallbackRanOnMainThread = NO;
        XCTestExpectation *completion = [self expectationWithDescription:@"Facade notes update completed"];
        PRBridgeObservationToken *token = [bridge updateInstanceNotesWithIdentifier:identifier
                                                                                  notes:notes
                                                                              completion:^(PRInstanceNotesUpdateResult *result,
                                                                                            PRBridgeError *error) {
            notesCallbackRanOnMainThread = [NSThread isMainThread];
            receivedNotesResult = result;
            receivedNotesError = error;
            [completion fulfill];
        }];
        XCTAssertNotNil(token);
        [self waitForExpectations:@[ completion ] timeout:2.0];
    };

    NSMutableString *mutableNotesIdentifier = [NSMutableString stringWithString:@" fixture.one "];
    NSMutableString *mutableNotes = [NSMutableString stringWithString:@"Updated\nfixture notes "];
    runNotesUpdate(mutableNotesIdentifier, mutableNotes);
    [mutableNotesIdentifier setString:@"fixture.changed.after-call"];
    [mutableNotes setString:@"fixture notes changed after call"];
    XCTAssertTrue(notesCallbackRanOnMainThread);
    XCTAssertNil(receivedNotesError);
    XCTAssertEqualObjects(receivedNotesResult.identifier, @"fixture.one");
    XCTAssertEqualObjects(receivedNotesResult.notes, @"Updated\nfixture notes ");
    XCTAssertEqual(receivedNotesResult.outcome, PRInstanceNotesUpdateOutcomeSucceeded);

    runNotesUpdate(@"unknown-instance", @"Ignored notes");
    XCTAssertTrue(notesCallbackRanOnMainThread);
    XCTAssertNil(receivedNotesError);
    XCTAssertEqual(receivedNotesResult.outcome, PRInstanceNotesUpdateOutcomeUnknownInstance);
    XCTAssertEqualObjects(receivedNotesResult.notes, @"");

    runNotesUpdate(@"rejected-instance", @"Rejected notes");
    XCTAssertTrue(notesCallbackRanOnMainThread);
    XCTAssertNil(receivedNotesError);
    XCTAssertEqual(receivedNotesResult.outcome, PRInstanceNotesUpdateOutcomeRejected);
    XCTAssertEqualObjects(receivedNotesResult.notes, @"");

    runNotesUpdate(@"   ", @"Invalid identifier");
    XCTAssertTrue(notesCallbackRanOnMainThread);
    XCTAssertNil(receivedNotesResult);
    XCTAssertEqual(receivedNotesError.code, PRBridgeErrorCodeInvalidInput);

    XCTAssertTrue(detailsRootMatches->load());
    XCTAssertTrue(notesRootMatches->load());
    XCTAssertEqual(*detailsCalls, (std::vector<std::string>{ "fixture.one", "unknown-instance" }));
    XCTAssertEqual(*notesCalls,
                   (std::vector<std::string>{ "fixture.one:Updated\nfixture notes ",
                                               "unknown-instance:Ignored notes",
                                               "rejected-instance:Rejected notes" }));
}

- (void)testFacadeComponentsPreservePackProfileOrderAndConvertProblemState
{
    auto loadedRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto componentCalls = std::make_shared<std::vector<std::string>>();
    const std::string fixtureRoot = self.fixtureRootURL.path.UTF8String;

    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadInstanceComponents = [loadedRootMatches, componentCalls, fixtureRoot](
                                               const std::filesystem::path& root,
                                               const std::string& identifier)
        -> std::optional<std::vector<FrontendInstanceComponentSnapshot>> {
        *loadedRootMatches = *loadedRootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        componentCalls->push_back(identifier);
        if (identifier == "empty-instance") {
            return std::vector<FrontendInstanceComponentSnapshot>{};
        }
        if (identifier != "fixture.one") {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceComponentSnapshot>{
            { "net.minecraft", "Minecraft", "1.20.1", true, false, false, true, false,
              FrontendInstanceComponentProblemSeverity::None, {} },
            { "net.fabricmc.fabric-loader", "Fabric Loader", "0.15.11", true, true, false, false, false,
              FrontendInstanceComponentProblemSeverity::Warning, { "Fixture metadata is stale." } },
            { "fixture.custom", "Custom Fixture", "1", false, true, false, false, true,
              FrontendInstanceComponentProblemSeverity::Error, { "Custom component is not loaded." } },
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *completion = [self expectationWithDescription:@"Facade components completed"];
    __block NSArray<PRInstanceComponent *> *receivedComponents = nil;
    __block PRBridgeError *receivedError = nil;
    __block BOOL callbackRanOnMainThread = NO;
    PRBridgeObservationToken *token = [bridge loadInstanceComponentsWithIdentifier:@" fixture.one "
                                                                              completion:^(NSArray<PRInstanceComponent *> *components,
                                                                                           PRBridgeError *error) {
        callbackRanOnMainThread = [NSThread isMainThread];
        receivedComponents = components;
        receivedError = error;
        [completion fulfill];
    }];
    XCTAssertNotNil(token);
    [self waitForExpectations:@[ completion ] timeout:2.0];
    XCTAssertTrue(callbackRanOnMainThread);
    XCTAssertNil(receivedError);
    XCTAssertTrue(token.isCancelled);
    XCTAssertEqual(receivedComponents.count, (NSUInteger)3);
    XCTAssertEqualObjects(receivedComponents[0].identifier, @"net.minecraft");
    XCTAssertEqualObjects(receivedComponents[0].version, @"1.20.1");
    XCTAssertTrue(receivedComponents[0].important);
    XCTAssertTrue(receivedComponents[1].canBeDisabled);
    XCTAssertEqual(receivedComponents[1].problemSeverity, PRInstanceComponentProblemSeverityWarning);
    XCTAssertEqualObjects(receivedComponents[1].problemDescriptions.firstObject, @"Fixture metadata is stale.");
    XCTAssertTrue(receivedComponents[2].custom);
    XCTAssertFalse(receivedComponents[2].enabled);
    XCTAssertEqual(receivedComponents[2].problemSeverity, PRInstanceComponentProblemSeverityError);

    XCTestExpectation *emptyCompletion = [self expectationWithDescription:@"Empty components completed"];
    receivedComponents = nil;
    receivedError = nil;
    PRBridgeObservationToken *emptyToken = [bridge loadInstanceComponentsWithIdentifier:@"empty-instance"
                                                                                completion:^(NSArray<PRInstanceComponent *> *components,
                                                                                             PRBridgeError *error) {
        receivedComponents = components;
        receivedError = error;
        [emptyCompletion fulfill];
    }];
    XCTAssertNotNil(emptyToken);
    [self waitForExpectations:@[ emptyCompletion ] timeout:2.0];
    XCTAssertNil(receivedError);
    XCTAssertNotNil(receivedComponents);
    XCTAssertEqual(receivedComponents.count, (NSUInteger)0);

    XCTestExpectation *missingCompletion = [self expectationWithDescription:@"Missing components completed"];
    receivedComponents = nil;
    receivedError = nil;
    PRBridgeObservationToken *missingToken = [bridge loadInstanceComponentsWithIdentifier:@"unknown-instance"
                                                                                  completion:^(NSArray<PRInstanceComponent *> *components,
                                                                                               PRBridgeError *error) {
        receivedComponents = components;
        receivedError = error;
        [missingCompletion fulfill];
    }];
    XCTAssertNotNil(missingToken);
    [self waitForExpectations:@[ missingCompletion ] timeout:2.0];
    XCTAssertNil(receivedComponents);
    XCTAssertEqual(receivedError.code, PRBridgeErrorCodeDataUnavailable);
    XCTAssertEqual(receivedError.recoveryKind, PRBridgeErrorRecoveryKindRetry);

    XCTestExpectation *invalidCompletion = [self expectationWithDescription:@"Invalid components completed"];
    receivedComponents = nil;
    receivedError = nil;
    PRBridgeObservationToken *invalidToken = [bridge loadInstanceComponentsWithIdentifier:@"   "
                                                                                   completion:^(NSArray<PRInstanceComponent *> *components,
                                                                                                PRBridgeError *error) {
        receivedComponents = components;
        receivedError = error;
        [invalidCompletion fulfill];
    }];
    XCTAssertNotNil(invalidToken);
    [self waitForExpectations:@[ invalidCompletion ] timeout:2.0];
    XCTAssertNil(receivedComponents);
    XCTAssertEqual(receivedError.code, PRBridgeErrorCodeInvalidInput);

    XCTAssertTrue(*loadedRootMatches);
    XCTAssertEqual(*componentCalls,
                   (std::vector<std::string>{ "fixture.one", "empty-instance", "unknown-instance" }));
}

- (void)testFacadeComponentLoadCancellationSuppressesQueuedCompletion
{
    dispatch_semaphore_t loaderEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseLoader = dispatch_semaphore_create(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadInstanceComponents = [loaderEntered, releaseLoader](
                                               const std::filesystem::path&,
                                               const std::string&)
        -> std::optional<std::vector<FrontendInstanceComponentSnapshot>> {
        dispatch_semaphore_signal(loaderEntered);
        dispatch_semaphore_wait(releaseLoader, DISPATCH_TIME_FOREVER);
        return std::vector<FrontendInstanceComponentSnapshot>{
            { "fixture.component", "Fixture Component", "1", true, false, false, true, false,
              FrontendInstanceComponentProblemSeverity::None, {} },
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *completion = [self expectationWithDescription:@"Cancelled component completion"];
    completion.inverted = YES;
    PRBridgeObservationToken *token = [bridge loadInstanceComponentsWithIdentifier:@"fixture.one"
                                                                              completion:^(__unused NSArray<PRInstanceComponent *> *components,
                                                                                           __unused PRBridgeError *error) {
        [completion fulfill];
    }];
    XCTAssertNotNil(token);
    XCTAssertEqual(dispatch_semaphore_wait(loaderEntered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(releaseLoader);
    [self waitForExpectations:@[ completion ] timeout:0.2];
}

- (void)testFacadeResourcesPreserveKindOrderAndRequireConfirmedMutations
{
    auto loadedRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto resourceCalls = std::make_shared<std::vector<std::string>>();
    auto mutationCalls = std::make_shared<std::vector<std::string>>();
    auto mutationRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto mutationFilesOk = std::make_shared<std::atomic<bool>>(true);
    const std::string fixtureRoot = self.fixtureRootURL.path.UTF8String;
    NSURL *sourceURL = [self.fixtureRootURL URLByAppendingPathComponent:@"import.zip"];
    NSURL *resourceDirectoryURL = [self.fixtureRootURL URLByAppendingPathComponent:@"resources" isDirectory:YES];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:resourceDirectoryURL
                                             withIntermediateDirectories:NO
                                                              attributes:nil
                                                                   error:nil]);
    XCTAssertTrue([[@"fixture mod" dataUsingEncoding:NSUTF8StringEncoding]
        writeToURL:[resourceDirectoryURL URLByAppendingPathComponent:@"mod.one"]
        atomically:YES]);
    XCTAssertTrue([[@"fixture import" dataUsingEncoding:NSUTF8StringEncoding]
        writeToURL:sourceURL
        atomically:YES]);

    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadInstanceResources = [loadedRootMatches, resourceCalls, fixtureRoot](
                                             const std::filesystem::path& root,
                                             const std::string& identifier,
                                             FrontendInstanceResourceKind kind)
        -> std::optional<std::vector<FrontendInstanceResourceSnapshot>> {
        *loadedRootMatches = *loadedRootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        resourceCalls->push_back(identifier + ":" + std::to_string(static_cast<int>(kind)));
        if (identifier == "empty-instance") {
            return std::vector<FrontendInstanceResourceSnapshot>{};
        }
        if (identifier != "fixture.one" || kind != FrontendInstanceResourceKind::Mods) {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceResourceSnapshot>{
            { "mod.one", "Fixture Mod", "1.0", "fixture-mod.jar", "Fixture", FrontendInstanceResourceKind::Mods,
              true, true, true, false, true, {} },
            { "mod.folder", "Fixture Folder", "", "fixture-folder", "", FrontendInstanceResourceKind::Mods,
              true, false, true, true, false, { "Folder resources cannot be toggled." } },
        };
    };
    dependencies.mutateInstanceResource = [mutationCalls, mutationRootMatches, mutationFilesOk, fixtureRoot](
                                             const std::filesystem::path& root,
                                             const std::string& identifier,
                                             FrontendInstanceResourceKind kind,
                                             const FrontendInstanceResourceMutationRequest& request) {
        *mutationRootMatches = *mutationRootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        mutationCalls->push_back(identifier + ":" + std::to_string(static_cast<int>(kind)) + ":"
                                  + std::to_string(static_cast<int>(request.action)) + ":"
                                  + request.resourceIdentifier + ":" + (request.confirmed ? "confirmed" : "unconfirmed")
                                  + ":" + request.sourcePath.generic_string());
        std::error_code fileError;
        if (request.action == FrontendInstanceResourceAction::Delete) {
            const bool removed = std::filesystem::remove(root / "resources" / request.resourceIdentifier, fileError);
            *mutationFilesOk = *mutationFilesOk && removed && !fileError;
        } else if (request.action == FrontendInstanceResourceAction::Import) {
            const bool copied = std::filesystem::copy_file(
                request.sourcePath,
                root / "resources" / request.resourceIdentifier,
                std::filesystem::copy_options::overwrite_existing,
                fileError);
            *mutationFilesOk = *mutationFilesOk && copied && !fileError;
        }
        if (request.resourceIdentifier == "missing-resource") {
            return FrontendInstanceResourceMutationResult{
                kind,
                request.action,
                FrontendInstanceResourceMutationOutcome::UnknownResource,
                identifier,
                request.resourceIdentifier,
                "instance.resource.missing",
                "fixture resource is missing",
                true,
            };
        }
        return FrontendInstanceResourceMutationResult{
            kind,
            request.action,
            FrontendInstanceResourceMutationOutcome::Succeeded,
            identifier,
            request.resourceIdentifier,
            "instance.resource.updated",
            "fixture resource mutation succeeded",
            false,
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *loadCompletion = [self expectationWithDescription:@"Facade resources completed"];
    __block NSArray<PRInstanceResource *> *receivedResources = nil;
    __block PRBridgeError *receivedError = nil;
    __block BOOL callbackRanOnMainThread = NO;
    PRBridgeObservationToken *loadToken = [bridge loadInstanceResourcesWithIdentifier:@" fixture.one "
                                                                                   kind:PRInstanceResourceKindMods
                                                                             completion:^(NSArray<PRInstanceResource *> *resources,
                                                                                          PRBridgeError *error) {
        callbackRanOnMainThread = [NSThread isMainThread];
        receivedResources = resources;
        receivedError = error;
        [loadCompletion fulfill];
    }];
    XCTAssertNotNil(loadToken);
    [self waitForExpectations:@[ loadCompletion ] timeout:2.0];
    XCTAssertTrue(callbackRanOnMainThread);
    XCTAssertNil(receivedError);
    XCTAssertEqual(receivedResources.count, (NSUInteger)2);
    XCTAssertEqualObjects(receivedResources[0].identifier, @"mod.one");
    XCTAssertEqualObjects(receivedResources[0].fileName, @"fixture-mod.jar");
    XCTAssertTrue(receivedResources[0].hasMetadata);
    XCTAssertEqualObjects(receivedResources[1].name, @"Fixture Folder");
    XCTAssertTrue(receivedResources[1].directory);
    XCTAssertFalse(receivedResources[1].canBeToggled);
    XCTAssertEqualObjects(receivedResources[1].problemDescriptions.firstObject, @"Folder resources cannot be toggled.");

    XCTestExpectation *emptyCompletion = [self expectationWithDescription:@"Empty resources completed"];
    receivedResources = nil;
    receivedError = nil;
    PRBridgeObservationToken *emptyToken = [bridge loadInstanceResourcesWithIdentifier:@"empty-instance"
                                                                                  kind:PRInstanceResourceKindDataPacks
                                                                            completion:^(NSArray<PRInstanceResource *> *resources,
                                                                                         PRBridgeError *error) {
        receivedResources = resources;
        receivedError = error;
        [emptyCompletion fulfill];
    }];
    XCTAssertNotNil(emptyToken);
    [self waitForExpectations:@[ emptyCompletion ] timeout:2.0];
    XCTAssertNil(receivedError);
    XCTAssertNotNil(receivedResources);
    XCTAssertEqual(receivedResources.count, (NSUInteger)0);

    XCTestExpectation *unconfirmedDeleteCompletion = [self expectationWithDescription:@"Unconfirmed delete rejected"];
    __block PRInstanceResourceMutationResult *unconfirmedResult = nil;
    receivedError = nil;
    PRBridgeObservationToken *unconfirmedDeleteToken = [bridge
        applyInstanceResourceActionWithIdentifier:@"fixture.one"
                                              kind:PRInstanceResourceKindMods
                                            action:PRInstanceResourceActionDelete
                                  resourceIdentifier:@"mod.one"
                                         sourceURL:nil
                                         confirmed:NO
                                         completion:^(PRInstanceResourceMutationResult *result, PRBridgeError *error) {
        unconfirmedResult = result;
        receivedError = error;
        [unconfirmedDeleteCompletion fulfill];
    }];
    XCTAssertNotNil(unconfirmedDeleteToken);
    [self waitForExpectations:@[ unconfirmedDeleteCompletion ] timeout:2.0];
    XCTAssertNil(unconfirmedResult);
    XCTAssertEqual(receivedError.code, PRBridgeErrorCodeInvalidInput);

    XCTestExpectation *deleteCompletion = [self expectationWithDescription:@"Confirmed delete completed"];
    __block PRInstanceResourceMutationResult *mutationResult = nil;
    receivedError = nil;
    PRBridgeObservationToken *deleteToken = [bridge
        applyInstanceResourceActionWithIdentifier:@"fixture.one"
                                              kind:PRInstanceResourceKindMods
                                            action:PRInstanceResourceActionDelete
                                  resourceIdentifier:@"mod.one"
                                         sourceURL:nil
                                         confirmed:YES
                                         completion:^(PRInstanceResourceMutationResult *result, PRBridgeError *error) {
        mutationResult = result;
        receivedError = error;
        [deleteCompletion fulfill];
    }];
    XCTAssertNotNil(deleteToken);
    [self waitForExpectations:@[ deleteCompletion ] timeout:2.0];
    XCTAssertNil(receivedError);
    XCTAssertEqual(mutationResult.outcome, PRInstanceResourceMutationOutcomeSucceeded);
    XCTAssertEqual(mutationResult.action, PRInstanceResourceActionDelete);
    XCTAssertTrue(mutationResult.partialChangesRolledBack == NO);

    XCTestExpectation *importCompletion = [self expectationWithDescription:@"Import completed"];
    mutationResult = nil;
    receivedError = nil;
    PRBridgeObservationToken *importToken = [bridge
        applyInstanceResourceActionWithIdentifier:@"fixture.one"
                                              kind:PRInstanceResourceKindMods
                                            action:PRInstanceResourceActionImport
                                  resourceIdentifier:@"import.zip"
                                         sourceURL:sourceURL
                                         confirmed:NO
                                         completion:^(PRInstanceResourceMutationResult *result, PRBridgeError *error) {
        mutationResult = result;
        receivedError = error;
        [importCompletion fulfill];
    }];
    XCTAssertNotNil(importToken);
    [self waitForExpectations:@[ importCompletion ] timeout:2.0];
    XCTAssertNil(receivedError);
    XCTAssertEqual(mutationResult.action, PRInstanceResourceActionImport);
    XCTAssertEqualObjects(mutationResult.resourceIdentifier, @"import.zip");

    XCTestExpectation *missingCompletion = [self expectationWithDescription:@"Missing resource mutation completed"];
    mutationResult = nil;
    receivedError = nil;
    PRBridgeObservationToken *missingToken = [bridge
        applyInstanceResourceActionWithIdentifier:@"fixture.one"
                                              kind:PRInstanceResourceKindMods
                                            action:PRInstanceResourceActionReveal
                                  resourceIdentifier:@"missing-resource"
                                         sourceURL:nil
                                         confirmed:NO
                                         completion:^(PRInstanceResourceMutationResult *result, PRBridgeError *error) {
        mutationResult = result;
        receivedError = error;
        [missingCompletion fulfill];
    }];
    XCTAssertNotNil(missingToken);
    [self waitForExpectations:@[ missingCompletion ] timeout:2.0];
    XCTAssertNil(receivedError);
    XCTAssertEqual(mutationResult.outcome, PRInstanceResourceMutationOutcomeUnknownResource);
    XCTAssertTrue(mutationResult.partialChangesRolledBack);

    XCTAssertTrue(*loadedRootMatches);
    XCTAssertTrue(*mutationRootMatches);
    XCTAssertTrue(*mutationFilesOk);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[resourceDirectoryURL URLByAppendingPathComponent:@"mod.one"].path]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[resourceDirectoryURL URLByAppendingPathComponent:@"import.zip"].path]);
    XCTAssertEqual(*resourceCalls,
                   (std::vector<std::string>{ "fixture.one:0", "empty-instance:4" }));
    XCTAssertEqual(mutationCalls->size(), (NSUInteger)3);
    XCTAssertTrue(mutationCalls->at(0).ends_with(":mod.one:confirmed:"));
    const std::string importMutationSuffix = std::string(":import.zip:unconfirmed:") + sourceURL.path.UTF8String;
    XCTAssertTrue(mutationCalls->at(1).ends_with(importMutationSuffix));
    XCTAssertTrue(mutationCalls->at(2).ends_with(":missing-resource:unconfirmed:"));
}

- (void)testFacadeResourceMutationCancellationSuppressesQueuedCompletion
{
    dispatch_semaphore_t mutatorEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseMutator = dispatch_semaphore_create(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.mutateInstanceResource = [mutatorEntered, releaseMutator](
                                             const std::filesystem::path&,
                                             const std::string& identifier,
                                             FrontendInstanceResourceKind kind,
                                             const FrontendInstanceResourceMutationRequest& request) {
        dispatch_semaphore_signal(mutatorEntered);
        dispatch_semaphore_wait(releaseMutator, DISPATCH_TIME_FOREVER);
        return FrontendInstanceResourceMutationResult{
            kind,
            request.action,
            FrontendInstanceResourceMutationOutcome::Succeeded,
            identifier,
            request.resourceIdentifier,
            "instance.resource.updated",
            "fixture resource mutation succeeded",
            false,
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *completion = [self expectationWithDescription:@"Cancelled resource completion"];
    completion.inverted = YES;
    PRBridgeObservationToken *token = [bridge
        applyInstanceResourceActionWithIdentifier:@"fixture.one"
                                              kind:PRInstanceResourceKindMods
                                            action:PRInstanceResourceActionReveal
                                  resourceIdentifier:@"mod.one"
                                         sourceURL:nil
                                         confirmed:NO
                                         completion:^(__unused PRInstanceResourceMutationResult *result,
                                                      __unused PRBridgeError *error) {
        [completion fulfill];
    }];
    XCTAssertNotNil(token);
    XCTAssertEqual(dispatch_semaphore_wait(mutatorEntered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(releaseMutator);
    [self waitForExpectations:@[ completion ] timeout:0.2];
}

- (void)testFacadeSettingsAreConvertedAndConfirmedOnMainActor
{
    auto loadedRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto updateRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto updateCalls = std::make_shared<std::vector<std::string>>();
    const std::string fixtureRoot = self.fixtureRootURL.path.UTF8String;

    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadInstanceSettings = [loadedRootMatches, fixtureRoot](
                                            const std::filesystem::path& root,
                                            const std::string& identifier)
        -> std::optional<FrontendInstanceSettingsSnapshot> {
        *loadedRootMatches = root == std::filesystem::path(fixtureRoot).lexically_normal();
        if (identifier != "fixture.one") {
            return std::nullopt;
        }
        return fixtureSettings(identifier);
    };
    dependencies.updateInstanceSettings = [updateRootMatches, updateCalls, fixtureRoot](
                                              const std::filesystem::path& root,
                                              const std::string& identifier,
                                              const FrontendInstanceSettingsSnapshot& requested) {
        *updateRootMatches = root == std::filesystem::path(fixtureRoot).lexically_normal();
        updateCalls->push_back(identifier + ":" + std::to_string(requested.windowWidth));
        if (identifier != "fixture.one") {
            return FrontendInstanceSettingsUpdateResult{
                FrontendInstanceSettingsUpdateOutcome::UnknownInstance,
                std::nullopt,
            };
        }
        auto confirmed = requested;
        confirmed.windowWidth = 1440;
        return FrontendInstanceSettingsUpdateResult{
            FrontendInstanceSettingsUpdateOutcome::Succeeded,
            std::move(confirmed),
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *loadCompletion = [self expectationWithDescription:@"Facade settings loaded"];
    __block PRInstanceSettings *receivedSettings = nil;
    __block PRBridgeError *receivedLoadError = nil;
    __block BOOL loadRanOnMainThread = NO;
    PRBridgeObservationToken *loadToken = [bridge loadInstanceSettingsWithIdentifier:@" fixture.one "
                                                                                completion:^(PRInstanceSettings *settings,
                                                                                              PRBridgeError *error) {
        loadRanOnMainThread = [NSThread isMainThread];
        receivedSettings = settings;
        receivedLoadError = error;
        [loadCompletion fulfill];
    }];
    XCTAssertNotNil(loadToken);
    [self waitForExpectations:@[ loadCompletion ] timeout:2.0];
    XCTAssertTrue(loadRanOnMainThread);
    XCTAssertNil(receivedLoadError);
    XCTAssertTrue(loadToken.isCancelled);
    XCTAssertEqualObjects(receivedSettings.identifier, @"fixture.one");
    XCTAssertTrue(receivedSettings.windowOverrideEnabled);
    XCTAssertEqual(receivedSettings.windowWidth, (NSInteger)1280);
    XCTAssertEqual(receivedSettings.windowHeight, (NSInteger)720);
    XCTAssertTrue(receivedSettings.globalDataPacksEnabled);
    XCTAssertEqualObjects(receivedSettings.globalDataPacksPath, @"datapacks");
    XCTAssertEqual(receivedSettings.joinTarget, PRInstanceJoinTargetServer);
    XCTAssertEqualObjects(receivedSettings.joinServerAddress, @"fixture.example:25565");
    XCTAssertEqualObjects(receivedSettings.modDownloadLoaders, (@[ @"Fabric", @"Quilt" ]));
    XCTAssertEqualObjects(receivedSettings.javaPath, @"/fixture/bin/java");
    XCTAssertEqual(receivedSettings.minMemoryMiB, (NSInteger)512);
    XCTAssertEqual(receivedSettings.maxMemoryMiB, (NSInteger)4096);
    XCTAssertEqualObjects(receivedSettings.jvmArguments, @"-Dfixture=true");
    XCTAssertEqualObjects(receivedSettings.preLaunchCommand, @"prepare-fixture");
    XCTAssertTrue(receivedSettings.useNativeGLFW);
    XCTAssertTrue(receivedSettings.useNativeOpenAL);

    XCTestExpectation *updateCompletion = [self expectationWithDescription:@"Facade settings update completed"];
    __block PRInstanceSettingsUpdateResult *receivedUpdate = nil;
    __block PRBridgeError *receivedUpdateError = nil;
    __block BOOL updateRanOnMainThread = NO;
    PRBridgeObservationToken *updateToken =
        [bridge updateInstanceSettingsWithIdentifier:@"fixture.one"
                                            settings:receivedSettings
                                          completion:^(PRInstanceSettingsUpdateResult *result,
                                                       PRBridgeError *error) {
        updateRanOnMainThread = [NSThread isMainThread];
        receivedUpdate = result;
        receivedUpdateError = error;
        [updateCompletion fulfill];
    }];
    XCTAssertNotNil(updateToken);
    [self waitForExpectations:@[ updateCompletion ] timeout:2.0];
    XCTAssertTrue(updateRanOnMainThread);
    XCTAssertNil(receivedUpdateError);
    XCTAssertTrue(updateToken.isCancelled);
    XCTAssertEqual(receivedUpdate.outcome, PRInstanceSettingsUpdateOutcomeSucceeded);
    XCTAssertEqualObjects(receivedUpdate.identifier, @"fixture.one");
    XCTAssertNotNil(receivedUpdate.settings);
    XCTAssertEqual(receivedUpdate.settings.windowWidth, (NSInteger)1440);
    XCTAssertTrue(*updateCalls == std::vector<std::string>{ "fixture.one:1280" });

    XCTestExpectation *missingCompletion = [self expectationWithDescription:@"Missing facade settings completed"];
    __block PRInstanceSettings *missingSettings = nil;
    __block PRBridgeError *missingError = nil;
    PRBridgeObservationToken *missingToken = [bridge loadInstanceSettingsWithIdentifier:@"unknown-instance"
                                                                                completion:^(PRInstanceSettings *settings,
                                                                                              PRBridgeError *error) {
        missingSettings = settings;
        missingError = error;
        [missingCompletion fulfill];
    }];
    XCTAssertNotNil(missingToken);
    [self waitForExpectations:@[ missingCompletion ] timeout:2.0];
    XCTAssertNil(missingSettings);
    XCTAssertEqual(missingError.code, PRBridgeErrorCodeDataUnavailable);
    XCTAssertEqual(missingError.recoveryKind, PRBridgeErrorRecoveryKindRetry);
    XCTAssertTrue(loadedRootMatches->load());
    XCTAssertTrue(updateRootMatches->load());
}

- (void)testFacadeGlobalSettingsAreConvertedAndConfirmedOnMainActor
{
    auto loadedRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto updateRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto updateCalls = std::make_shared<std::vector<int>>();
    const std::string fixtureRoot = self.fixtureRootURL.path.UTF8String;

    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadGlobalSettings = [loadedRootMatches, fixtureRoot](const std::filesystem::path& root)
        -> std::optional<FrontendGlobalSettingsSnapshot> {
        *loadedRootMatches = root == std::filesystem::path(fixtureRoot).lexically_normal();
        return fixtureGlobalSettings(std::filesystem::path(fixtureRoot));
    };
    dependencies.updateGlobalSettings = [updateRootMatches, updateCalls, fixtureRoot](
                                            const std::filesystem::path& root,
                                            const FrontendGlobalSettingsSnapshot& requested) {
        *updateRootMatches = root == std::filesystem::path(fixtureRoot).lexically_normal();
        updateCalls->push_back(requested.catOpacity);
        auto confirmed = requested;
        confirmed.catOpacity = 88;
        return FrontendGlobalSettingsUpdateResult{
            FrontendGlobalSettingsUpdateOutcome::Succeeded,
            std::move(confirmed),
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *loadCompletion = [self expectationWithDescription:@"Global settings loaded"];
    __block PRGlobalSettings *receivedSettings = nil;
    __block PRBridgeError *receivedLoadError = nil;
    __block BOOL loadRanOnMainThread = NO;
    PRBridgeObservationToken *loadToken = [bridge loadGlobalSettingsWithCompletion:^(PRGlobalSettings *settings,
                                                                                      PRBridgeError *error) {
        loadRanOnMainThread = [NSThread isMainThread];
        receivedSettings = settings;
        receivedLoadError = error;
        [loadCompletion fulfill];
    }];
    XCTAssertNotNil(loadToken);
    [self waitForExpectations:@[ loadCompletion ] timeout:2.0];
    XCTAssertTrue(loadRanOnMainThread);
    XCTAssertNil(receivedLoadError);
    XCTAssertTrue(loadToken.isCancelled);
    XCTAssertEqualObjects(receivedSettings.instanceDirectoryURL.path,
                          [self.fixtureRootURL URLByAppendingPathComponent:@"instances"].path);
    XCTAssertEqualObjects(receivedSettings.iconTheme, @"fixture-icons");
    XCTAssertEqualObjects(receivedSettings.catFit, @"strech");
    XCTAssertEqual(receivedSettings.catOpacity, (NSInteger)73);
    XCTAssertEqual(receivedSettings.numberOfConcurrentTasks, (NSInteger)10);
    XCTAssertEqual(receivedSettings.consoleMaxLines, (NSInteger)20000);

    PRGlobalSettings *requestedSettings = [[PRGlobalSettings alloc]
        initWithInstanceDirectoryURL:receivedSettings.instanceDirectoryURL
                            iconTheme:receivedSettings.iconTheme
                    applicationTheme:receivedSettings.applicationTheme
                      backgroundCat:receivedSettings.backgroundCat
                        catOpacity:81
                            catFit:receivedSettings.catFit
                          language:receivedSettings.language
                  useSystemLocale:receivedSettings.useSystemLocale
           menuBarInsteadOfToolBar:receivedSettings.menuBarInsteadOfToolBar
                 statusBarVisible:receivedSettings.statusBarVisible
                   toolbarsLocked:receivedSettings.toolbarsLocked
                numberOfConcurrentTasks:receivedSettings.numberOfConcurrentTasks
            numberOfConcurrentDownloads:receivedSettings.numberOfConcurrentDownloads
                  numberOfManualRetries:receivedSettings.numberOfManualRetries
                      requestTimeoutSeconds:receivedSettings.requestTimeoutSeconds
                               consoleFont:receivedSettings.consoleFont
                           consoleFontSize:receivedSettings.consoleFontSize
                            consoleMaxLines:receivedSettings.consoleMaxLines
                         consoleOverflowStop:receivedSettings.consoleOverflowStop
                                 showConsole:receivedSettings.showConsole
                              autoCloseConsole:receivedSettings.autoCloseConsole
                            showConsoleOnError:receivedSettings.showConsoleOnError
                             logPrePostOutput:receivedSettings.logPrePostOutput];
    XCTAssertNotNil(requestedSettings);

    XCTestExpectation *updateCompletion = [self expectationWithDescription:@"Global settings update completed"];
    __block PRGlobalSettingsUpdateResult *receivedUpdate = nil;
    __block PRBridgeError *receivedUpdateError = nil;
    PRBridgeObservationToken *updateToken = [bridge updateGlobalSettings:requestedSettings
                                                                  completion:^(PRGlobalSettingsUpdateResult *result,
                                                                               PRBridgeError *error) {
        XCTAssertTrue([NSThread isMainThread]);
        receivedUpdate = result;
        receivedUpdateError = error;
        [updateCompletion fulfill];
    }];
    XCTAssertNotNil(updateToken);
    [self waitForExpectations:@[ updateCompletion ] timeout:2.0];
    XCTAssertNil(receivedUpdateError);
    XCTAssertTrue(updateToken.isCancelled);
    XCTAssertEqual(receivedUpdate.outcome, PRGlobalSettingsUpdateOutcomeSucceeded);
    XCTAssertNotNil(receivedUpdate.settings);
    XCTAssertEqual(receivedUpdate.settings.catOpacity, (NSInteger)88);
    XCTAssertEqual(*updateCalls, (std::vector<int>{ 81 }));
    XCTAssertTrue(loadedRootMatches->load());
    XCTAssertTrue(updateRootMatches->load());
}

- (void)testFacadeGlobalSettingsCancellationSuppressesQueuedCompletion
{
    dispatch_semaphore_t loaderEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseLoader = dispatch_semaphore_create(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadGlobalSettings = [loaderEntered, releaseLoader, fixtureRoot = self.fixtureRootURL.path.UTF8String](
                                           const std::filesystem::path& root)
        -> std::optional<FrontendGlobalSettingsSnapshot> {
        XCTAssertTrue(root == std::filesystem::path(fixtureRoot).lexically_normal());
        dispatch_semaphore_signal(loaderEntered);
        dispatch_semaphore_wait(releaseLoader, DISPATCH_TIME_FOREVER);
        return fixtureGlobalSettings(std::filesystem::path(fixtureRoot));
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTestExpectation *completion = [self expectationWithDescription:@"Cancelled global settings completion"];
    completion.inverted = YES;
    PRBridgeObservationToken *token = [bridge loadGlobalSettingsWithCompletion:^(__unused PRGlobalSettings *settings,
                                                                                    __unused PRBridgeError *error) {
        [completion fulfill];
    }];
    XCTAssertNotNil(token);
    XCTAssertEqual(dispatch_semaphore_wait(loaderEntered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(releaseLoader);
    [self waitForExpectations:@[ completion ] timeout:0.2];
}

- (void)testFacadeJavaDiscoveryAndSelectionConvertFixtureContractsOnMainActor
{
    auto discoveryRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto selectionRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto selectionCalls = std::make_shared<std::vector<std::string>>();
    const std::filesystem::path fixtureRoot = std::filesystem::path(self.fixtureRootURL.path.UTF8String).lexically_normal();

    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadJavaInstallations = [discoveryRootMatches, fixtureRoot](const std::filesystem::path& root) {
        *discoveryRootMatches = root == fixtureRoot;
        return FrontendJavaDiscoveryResult{
            FrontendJavaDiscoveryOutcome::Succeeded,
            { fixtureJavaInstallation(fixtureRoot, "fixture-managed"),
              fixtureJavaInstallation(fixtureRoot, "fixture-incompatible", FrontendJavaInstallationValidity::Incompatible),
              fixtureJavaInstallation(fixtureRoot, "fixture-missing", FrontendJavaInstallationValidity::Unavailable) },
            "",
            "",
            false,
        };
    };
    dependencies.selectJavaInstallation = [selectionRootMatches, selectionCalls, fixtureRoot](
                                              const std::filesystem::path& root,
                                              const std::string& identifier) {
        *selectionRootMatches = root == fixtureRoot;
        selectionCalls->push_back(identifier);
        if (identifier == "fixture-managed") {
            return FrontendJavaSelectionResult{
                FrontendJavaSelectionOutcome::Succeeded,
                fixtureJavaInstallation(fixtureRoot, identifier),
                "",
                "",
            };
        }
        return FrontendJavaSelectionResult{
            FrontendJavaSelectionOutcome::UnknownInstallation,
            std::nullopt,
            "java.selection.unknownInstallation",
            "Fixture Java installation is no longer available.",
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *discoveryCompletion = [self expectationWithDescription:@"Java discovery completed"];
    __block NSArray<PRJavaInstallation *> *receivedInstallations = nil;
    __block PRBridgeError *receivedDiscoveryError = nil;
    __block BOOL discoveryRanOnMainThread = NO;
    PRBridgeObservationToken *discoveryToken = [bridge loadJavaInstallationsWithCompletion:^(PRJavaDiscoveryResult *result,
                                                                                               PRBridgeError *error) {
        discoveryRanOnMainThread = [NSThread isMainThread];
        receivedInstallations = result.installations;
        receivedDiscoveryError = error;
        XCTAssertEqual(result.outcome, PRJavaDiscoveryOutcomeSucceeded);
        [discoveryCompletion fulfill];
    }];
    XCTAssertNotNil(discoveryToken);
    [self waitForExpectations:@[ discoveryCompletion ] timeout:2.0];
    XCTAssertTrue(discoveryRanOnMainThread);
    XCTAssertNil(receivedDiscoveryError);
    XCTAssertTrue(discoveryToken.isCancelled);
    XCTAssertEqual(receivedInstallations.count, (NSUInteger)3);
    XCTAssertEqualObjects(receivedInstallations[0].identifier, @"fixture-managed");
    XCTAssertEqual(receivedInstallations[0].validity, PRJavaInstallationValidityValid);
    XCTAssertTrue(receivedInstallations[0].managed);
    XCTAssertEqualObjects(receivedInstallations[1].version, @"8.0.392");
    XCTAssertEqual(receivedInstallations[1].validity, PRJavaInstallationValidityIncompatible);
    XCTAssertEqual(receivedInstallations[2].validity, PRJavaInstallationValidityUnavailable);

    XCTestExpectation *selectionCompletion = [self expectationWithDescription:@"Java selection completed"];
    __block PRJavaSelectionResult *receivedSelection = nil;
    __block PRBridgeError *receivedSelectionError = nil;
    __block BOOL selectionRanOnMainThread = NO;
    PRBridgeObservationToken *selectionToken = [bridge selectJavaInstallationWithIdentifier:@" fixture-managed "
                                                                                      completion:^(PRJavaSelectionResult *result,
                                                                                                   PRBridgeError *error) {
        selectionRanOnMainThread = [NSThread isMainThread];
        receivedSelection = result;
        receivedSelectionError = error;
        [selectionCompletion fulfill];
    }];
    XCTAssertNotNil(selectionToken);
    [self waitForExpectations:@[ selectionCompletion ] timeout:2.0];
    XCTAssertTrue(selectionRanOnMainThread);
    XCTAssertNil(receivedSelectionError);
    XCTAssertTrue(selectionToken.isCancelled);
    XCTAssertEqual(receivedSelection.outcome, PRJavaSelectionOutcomeSucceeded);
    XCTAssertEqualObjects(receivedSelection.installation.identifier, @"fixture-managed");
    XCTAssertEqual(*selectionCalls, (std::vector<std::string>{ "fixture-managed" }));
    XCTAssertTrue(discoveryRootMatches->load());
    XCTAssertTrue(selectionRootMatches->load());
}

- (void)testFacadeJavaDiscoveryCancellationSuppressesQueuedCompletion
{
    dispatch_semaphore_t loaderEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseLoader = dispatch_semaphore_create(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadJavaInstallations = [loaderEntered, releaseLoader](const std::filesystem::path& root) {
        dispatch_semaphore_signal(loaderEntered);
        dispatch_semaphore_wait(releaseLoader, DISPATCH_TIME_FOREVER);
        return FrontendJavaDiscoveryResult{
            FrontendJavaDiscoveryOutcome::Succeeded,
            { fixtureJavaInstallation(root, "fixture-java") },
            "",
            "",
            false,
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTestExpectation *completion = [self expectationWithDescription:@"Cancelled Java discovery completion"];
    completion.inverted = YES;
    PRBridgeObservationToken *token = [bridge loadJavaInstallationsWithCompletion:^(__unused PRJavaDiscoveryResult *result,
                                                                                       __unused PRBridgeError *error) {
        [completion fulfill];
    }];
    XCTAssertNotNil(token);
    XCTAssertEqual(dispatch_semaphore_wait(loaderEntered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(releaseLoader);
    [self waitForExpectations:@[ completion ] timeout:0.2];
}

- (void)testFacadeAccountSnapshotsAndActiveSelectionConvertFixtureContractsOnMainActor
{
    auto discoveryRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto selectionRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto selectionCalls = std::make_shared<std::vector<std::string>>();
    const std::filesystem::path fixtureRoot = std::filesystem::path(self.fixtureRootURL.path.UTF8String).lexically_normal();

    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadAccountSnapshots = [discoveryRootMatches, fixtureRoot](const std::filesystem::path& root) {
        *discoveryRootMatches = root == fixtureRoot;
        return FrontendAccountSnapshotResult{
            FrontendAccountSnapshotOutcome::Succeeded,
            { fixtureAccount("account.fixture.microsoft", "Fixture Microsoft Account"),
              fixtureAccount("account.fixture.offline", "Fixture Offline Profile", FrontendAccountType::Offline,
                             FrontendAccountState::Offline, false),
              fixtureAccount("account.fixture.busy", "Fixture Busy Account", FrontendAccountType::Microsoft,
                             FrontendAccountState::Working, true, true, false) },
            std::string("account.fixture.microsoft"),
            "",
            "",
            false,
        };
    };
    dependencies.selectActiveAccount = [selectionRootMatches, selectionCalls, fixtureRoot](
                                           const std::filesystem::path& root,
                                           const std::optional<std::string>& identifier) {
        *selectionRootMatches = root == fixtureRoot;
        selectionCalls->push_back(identifier.value_or("<none>"));
        if (!identifier.has_value()) {
            return FrontendAccountSelectionResult{
                FrontendAccountSelectionOutcome::Succeeded,
                std::nullopt,
                "",
                "",
            };
        }
        if (*identifier == "account.fixture.offline") {
            return FrontendAccountSelectionResult{
                FrontendAccountSelectionOutcome::Succeeded,
                fixtureAccount(*identifier, "Fixture Offline Profile", FrontendAccountType::Offline,
                               FrontendAccountState::Offline, false),
                "",
                "",
            };
        }
        return FrontendAccountSelectionResult{
            FrontendAccountSelectionOutcome::UnknownAccount,
            std::nullopt,
            "accounts.selection.unknownAccount",
            "Fixture account is no longer available.",
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *snapshotCompletion = [self expectationWithDescription:@"Account snapshots completed"];
    __block PRAccountSnapshotResult *receivedSnapshots = nil;
    __block PRBridgeError *receivedSnapshotError = nil;
    __block BOOL snapshotRanOnMainThread = NO;
    PRBridgeObservationToken *snapshotToken = [bridge loadAccountSnapshotsWithCompletion:^(PRAccountSnapshotResult *result,
                                                                                              PRBridgeError *error) {
        snapshotRanOnMainThread = [NSThread isMainThread];
        receivedSnapshots = result;
        receivedSnapshotError = error;
        [snapshotCompletion fulfill];
    }];
    XCTAssertNotNil(snapshotToken);
    [self waitForExpectations:@[ snapshotCompletion ] timeout:2.0];
    XCTAssertTrue(snapshotRanOnMainThread);
    XCTAssertNil(receivedSnapshotError);
    XCTAssertTrue(snapshotToken.isCancelled);
    XCTAssertEqual(receivedSnapshots.outcome, PRAccountSnapshotOutcomeSucceeded);
    XCTAssertEqual(receivedSnapshots.accounts.count, (NSUInteger)3);
    XCTAssertEqualObjects(receivedSnapshots.activeAccountIdentifier, @"account.fixture.microsoft");
    XCTAssertEqual(receivedSnapshots.accounts[1].type, PRAccountTypeOffline);
    XCTAssertFalse(receivedSnapshots.accounts[1].ownsMinecraft);
    XCTAssertTrue(receivedSnapshots.accounts[2].isBusy);
    XCTAssertFalse(receivedSnapshots.accounts[2].canBeSelected);

    XCTestExpectation *selectionCompletion = [self expectationWithDescription:@"Account selection completed"];
    __block PRAccountSelectionResult *receivedSelection = nil;
    __block PRBridgeError *receivedSelectionError = nil;
    __block BOOL selectionRanOnMainThread = NO;
    PRBridgeObservationToken *selectionToken = [bridge selectActiveAccountWithIdentifier:@" account.fixture.offline "
                                                                                     completion:^(PRAccountSelectionResult *result,
                                                                                                  PRBridgeError *error) {
        selectionRanOnMainThread = [NSThread isMainThread];
        receivedSelection = result;
        receivedSelectionError = error;
        [selectionCompletion fulfill];
    }];
    XCTAssertNotNil(selectionToken);
    [self waitForExpectations:@[ selectionCompletion ] timeout:2.0];
    XCTAssertTrue(selectionRanOnMainThread);
    XCTAssertNil(receivedSelectionError);
    XCTAssertTrue(selectionToken.isCancelled);
    XCTAssertEqual(receivedSelection.outcome, PRAccountSelectionOutcomeSucceeded);
    XCTAssertEqualObjects(receivedSelection.account.identifier, @"account.fixture.offline");

    XCTestExpectation *clearCompletion = [self expectationWithDescription:@"Account clear completed"];
    __block PRAccountSelectionResult *receivedClear = nil;
    PRBridgeObservationToken *clearToken = [bridge selectActiveAccountWithIdentifier:nil
                                                                                 completion:^(PRAccountSelectionResult *result,
                                                                                              __unused PRBridgeError *error) {
        receivedClear = result;
        [clearCompletion fulfill];
    }];
    XCTAssertNotNil(clearToken);
    [self waitForExpectations:@[ clearCompletion ] timeout:2.0];
    XCTAssertTrue(clearToken.isCancelled);
    XCTAssertEqual(receivedClear.outcome, PRAccountSelectionOutcomeSucceeded);
    XCTAssertNil(receivedClear.account);
    XCTAssertEqual(*selectionCalls, (std::vector<std::string>{ "account.fixture.offline", "<none>" }));
    XCTAssertTrue(discoveryRootMatches->load());
    XCTAssertTrue(selectionRootMatches->load());
}

- (void)testFacadeAccountSnapshotCancellationSuppressesQueuedCompletion
{
    dispatch_semaphore_t loaderEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseLoader = dispatch_semaphore_create(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadAccountSnapshots = [loaderEntered, releaseLoader](const std::filesystem::path&) {
        dispatch_semaphore_signal(loaderEntered);
        dispatch_semaphore_wait(releaseLoader, DISPATCH_TIME_FOREVER);
        return FrontendAccountSnapshotResult{
            FrontendAccountSnapshotOutcome::Succeeded,
            { fixtureAccount("account.fixture.microsoft", "Fixture Microsoft Account") },
            std::string("account.fixture.microsoft"),
            "",
            "",
            false,
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTestExpectation *completion = [self expectationWithDescription:@"Cancelled account snapshot completion"];
    completion.inverted = YES;
    PRBridgeObservationToken *token = [bridge loadAccountSnapshotsWithCompletion:^(__unused PRAccountSnapshotResult *result,
                                                                                       __unused PRBridgeError *error) {
        [completion fulfill];
    }];
    XCTAssertNotNil(token);
    XCTAssertEqual(dispatch_semaphore_wait(loaderEntered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(releaseLoader);
    [self waitForExpectations:@[ completion ] timeout:0.2];
}

- (void)testFacadeAuthenticationProgressAndResultConvertSyntheticProviderOnMainActor
{
    auto authenticationRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto authenticationAction = std::make_shared<std::atomic<int>>(-1);
    const std::filesystem::path fixtureRoot = std::filesystem::path(self.fixtureRootURL.path.UTF8String).lexically_normal();
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.authenticateAccount = [authenticationRootMatches, authenticationAction, fixtureRoot](
                                           const std::filesystem::path& root,
                                           const FrontendAccountAuthenticationRequest& request,
                                           const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progress) {
        *authenticationRootMatches = root == fixtureRoot;
        *authenticationAction = static_cast<int>(request.action);
        auto emit = [&](FrontendAccountAuthenticationPhase phase,
                        FrontendAccountAuthenticationOutcome outcome,
                        const char* key,
                        bool canCancel,
                        bool retryable,
                        bool requiresUserAction,
                        const char* verificationURL = "") {
            FrontendAccountAuthenticationProgress event;
            event.accountIdentifier = request.accountIdentifier;
            event.action = request.action;
            event.phase = phase;
            event.outcome = outcome;
            event.providerLabel = "Fixture Provider";
            event.verificationURL = verificationURL;
            event.localizationKey = key;
            event.expiresInSeconds = verificationURL[0] == '\0' ? 0 : 900;
            event.canCancel = canCancel;
            event.retryable = retryable;
            event.requiresUserAction = requiresUserAction;
            progress(event);
        };
        emit(FrontendAccountAuthenticationPhase::Preparing,
             FrontendAccountAuthenticationOutcome::InProgress,
             "accounts.authentication.preparing",
             true,
             false,
             false);
        emit(FrontendAccountAuthenticationPhase::AwaitingUser,
             FrontendAccountAuthenticationOutcome::InProgress,
             "accounts.authentication.awaitingUser",
             true,
             false,
             true,
             "https://login.example.invalid/device");
        emit(FrontendAccountAuthenticationPhase::Authenticating,
             FrontendAccountAuthenticationOutcome::InProgress,
             "accounts.authentication.authenticating",
             true,
             false,
             false);
        emit(FrontendAccountAuthenticationPhase::Succeeded,
             FrontendAccountAuthenticationOutcome::Succeeded,
             "accounts.authentication.succeeded",
             false,
             false,
             false);
        return FrontendAccountAuthenticationResult{
            FrontendAccountAuthenticationOutcome::Succeeded,
            fixtureAccount(request.accountIdentifier, "Fixture Microsoft Account"),
            "accounts.authentication.succeeded",
            "",
            false,
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *progressExpectation = [self expectationWithDescription:@"Authentication progress delivered"];
    XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Authentication completed"];
    __block NSMutableArray<PRAccountAuthenticationProgress *> *receivedProgress = [NSMutableArray array];
    __block PRAccountAuthenticationResult *receivedResult = nil;
    __block PRBridgeError *receivedError = nil;
    __block BOOL progressRanOnMainThread = YES;
    __block BOOL completionRanOnMainThread = NO;
    PRBridgeObservationToken *token = [bridge authenticateAccountWithIdentifier:@" account.fixture.microsoft "
                                                                                action:PRAccountAuthenticationActionLogin
                                                                              progress:^(PRAccountAuthenticationProgress *progress) {
        progressRanOnMainThread = progressRanOnMainThread && [NSThread isMainThread];
        [receivedProgress addObject:progress];
        if (receivedProgress.count == 4) {
            [progressExpectation fulfill];
        }
    }
                                                                            completion:^(PRAccountAuthenticationResult *result,
                                                                                         PRBridgeError *error) {
        completionRanOnMainThread = [NSThread isMainThread];
        receivedResult = result;
        receivedError = error;
        [completionExpectation fulfill];
    }];
    XCTAssertNotNil(token);
    [self waitForExpectations:@[ progressExpectation, completionExpectation ] timeout:2.0];
    XCTAssertTrue(progressRanOnMainThread);
    XCTAssertTrue(completionRanOnMainThread);
    XCTAssertNil(receivedError);
    XCTAssertTrue(token.isCancelled);
    XCTAssertEqual(receivedProgress.count, (NSUInteger)4);
    XCTAssertEqual(receivedProgress[0].phase, PRAccountAuthenticationPhasePreparing);
    XCTAssertEqual(receivedProgress[1].phase, PRAccountAuthenticationPhaseAwaitingUser);
    XCTAssertEqualObjects(receivedProgress[1].verificationURL, @"https://login.example.invalid/device");
    XCTAssertTrue(receivedProgress[1].requiresUserAction);
    XCTAssertEqual(receivedProgress[1].expiresInSeconds, (NSInteger)900);
    XCTAssertNil(receivedProgress[1].diagnosticText);
    XCTAssertEqual(receivedResult.outcome, PRAccountAuthenticationOutcomeSucceeded);
    XCTAssertEqualObjects(receivedResult.account.identifier, @"account.fixture.microsoft");
    XCTAssertEqual(receivedResult.account.type, PRAccountTypeMicrosoft);
    XCTAssertTrue(authenticationRootMatches->load());
    XCTAssertEqual(authenticationAction->load(), static_cast<int>(FrontendAccountAuthenticationAction::Login));
}

- (void)testFacadeAuthenticationCancellationSuppressesQueuedProgressAndCompletion
{
    dispatch_semaphore_t runnerEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseRunner = dispatch_semaphore_create(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.authenticateAccount = [runnerEntered, releaseRunner](
                                           const std::filesystem::path&,
                                           const FrontendAccountAuthenticationRequest& request,
                                           const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progress) {
        FrontendAccountAuthenticationProgress preparing;
        preparing.accountIdentifier = request.accountIdentifier;
        preparing.action = request.action;
        preparing.phase = FrontendAccountAuthenticationPhase::Preparing;
        preparing.outcome = FrontendAccountAuthenticationOutcome::InProgress;
        preparing.providerLabel = "Fixture Provider";
        preparing.localizationKey = "accounts.authentication.preparing";
        preparing.canCancel = true;
        progress(preparing);
        dispatch_semaphore_signal(runnerEntered);
        dispatch_semaphore_wait(releaseRunner, DISPATCH_TIME_FOREVER);
        FrontendAccountAuthenticationProgress cancelled;
        cancelled.accountIdentifier = request.accountIdentifier;
        cancelled.action = request.action;
        cancelled.phase = FrontendAccountAuthenticationPhase::Cancelled;
        cancelled.outcome = FrontendAccountAuthenticationOutcome::Cancelled;
        cancelled.providerLabel = "Fixture Provider";
        cancelled.localizationKey = "accounts.authentication.cancelled";
        progress(cancelled);
        return FrontendAccountAuthenticationResult{
            FrontendAccountAuthenticationOutcome::Cancelled,
            std::nullopt,
            "accounts.authentication.cancelled",
            "Fixture authentication cancelled.",
            false,
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);
    XCTestExpectation *progressExpectation = [self expectationWithDescription:@"Cancelled authentication progress"];
    progressExpectation.inverted = YES;
    XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Cancelled authentication completion"];
    completionExpectation.inverted = YES;
    PRBridgeObservationToken *token = [bridge authenticateAccountWithIdentifier:@"account.fixture.microsoft"
                                                                                action:PRAccountAuthenticationActionLogin
                                                                              progress:^(__unused PRAccountAuthenticationProgress *progress) {
        [progressExpectation fulfill];
    }
                                                                            completion:^(__unused PRAccountAuthenticationResult *result,
                                                                                         __unused PRBridgeError *error) {
        [completionExpectation fulfill];
    }];
    XCTAssertNotNil(token);
    XCTAssertEqual(dispatch_semaphore_wait(runnerEntered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(releaseRunner);
    [self waitForExpectations:@[ progressExpectation, completionExpectation ] timeout:0.2];
}

- (void)testFacadeOfflineLaunchIdentityPreservesLegacyValidationWithoutSecrets
{
    auto loadCalls = std::make_shared<std::atomic<int>>(0);
    auto updateCalls = std::make_shared<std::atomic<int>>(0);
    auto rootMatches = std::make_shared<std::atomic<bool>>(true);
    const std::filesystem::path fixtureRoot = std::filesystem::path(self.fixtureRootURL.path.UTF8String).lexically_normal();
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadOfflineLaunchIdentity = [loadCalls, rootMatches, fixtureRoot](
                                                  const std::filesystem::path& root,
                                                  const FrontendOfflineLaunchIdentityRequest& request) {
        *rootMatches = *rootMatches && root == fixtureRoot;
        ++(*loadCalls);
        return FrontendOfflineLaunchIdentityLoadResult{
            FrontendOfflineLaunchIdentityLoadOutcome::Succeeded,
            FrontendOfflineLaunchIdentitySnapshot{ request.mode, request.accountIdentifier, "Saved_Player" },
            "accounts.offlineIdentity.loaded",
            "",
            false,
        };
    };
    dependencies.updateOfflineLaunchIdentity = [updateCalls, rootMatches, fixtureRoot](
                                                    const std::filesystem::path& root,
                                                    const FrontendOfflineLaunchIdentityUpdateRequest& request) {
        *rootMatches = *rootMatches && root == fixtureRoot;
        ++(*updateCalls);
        return FrontendOfflineLaunchIdentityUpdateResult{
            FrontendOfflineLaunchIdentityUpdateOutcome::Succeeded,
            FrontendOfflineLaunchIdentitySnapshot{ request.mode, request.accountIdentifier, request.name },
            "accounts.offlineIdentity.saved",
            "",
            false,
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *loadExpectation = [self expectationWithDescription:@"Offline identity loaded"];
    __block PROfflineLaunchIdentityLoadResult *loadResult = nil;
    __block PRBridgeError *loadError = nil;
    PRBridgeObservationToken *loadToken = [bridge loadOfflineLaunchIdentityWithMode:PROfflineLaunchIdentityModeOffline
                                                                     accountIdentifier:@" account.fixture.offline "
                                                                          fallbackName:@"Player"
                                                                           completion:^(PROfflineLaunchIdentityLoadResult *result,
                                                                                        PRBridgeError *error) {
        XCTAssertTrue([NSThread isMainThread]);
        loadResult = result;
        loadError = error;
        [loadExpectation fulfill];
    }];
    XCTAssertNotNil(loadToken);
    [self waitForExpectations:@[ loadExpectation ] timeout:2.0];
    XCTAssertNil(loadError);
    XCTAssertTrue(loadToken.isCancelled);
    XCTAssertEqual(loadResult.outcome, PROfflineLaunchIdentityLoadOutcomeSucceeded);
    XCTAssertEqualObjects(loadResult.identity.accountIdentifier, @"account.fixture.offline");
    XCTAssertEqualObjects(loadResult.identity.name, @"Saved_Player");

    XCTestExpectation *invalidExpectation = [self expectationWithDescription:@"Invalid offline identity rejected"];
    __block PROfflineLaunchIdentityUpdateResult *invalidResult = nil;
    PRBridgeObservationToken *invalidToken = [bridge updateOfflineLaunchIdentityWithMode:PROfflineLaunchIdentityModeOffline
                                                                         accountIdentifier:@"account.fixture.offline"
                                                                                      name:@"bad name"
                                                                         allowInvalidName:NO
                                                                               completion:^(PROfflineLaunchIdentityUpdateResult *result,
                                                                                            PRBridgeError *error) {
        XCTAssertNil(error);
        invalidResult = result;
        [invalidExpectation fulfill];
    }];
    XCTAssertNotNil(invalidToken);
    [self waitForExpectations:@[ invalidExpectation ] timeout:2.0];
    XCTAssertEqual(invalidResult.outcome, PROfflineLaunchIdentityUpdateOutcomeInvalidName);

    XCTestExpectation *saveExpectation = [self expectationWithDescription:@"Offline identity saved"];
    __block PROfflineLaunchIdentityUpdateResult *saveResult = nil;
    PRBridgeObservationToken *saveToken = [bridge updateOfflineLaunchIdentityWithMode:PROfflineLaunchIdentityModeOffline
                                                                       accountIdentifier:@"account.fixture.offline"
                                                                                    name:@"Native_Player"
                                                                       allowInvalidName:NO
                                                                             completion:^(PROfflineLaunchIdentityUpdateResult *result,
                                                                                          PRBridgeError *error) {
        XCTAssertTrue([NSThread isMainThread]);
        XCTAssertNil(error);
        saveResult = result;
        [saveExpectation fulfill];
    }];
    XCTAssertNotNil(saveToken);
    [self waitForExpectations:@[ saveExpectation ] timeout:2.0];
    XCTAssertEqual(saveResult.outcome, PROfflineLaunchIdentityUpdateOutcomeSucceeded);
    XCTAssertEqualObjects(saveResult.identity.name, @"Native_Player");
    XCTAssertEqual(loadCalls->load(), 1);
    XCTAssertEqual(updateCalls->load(), 1);
    XCTAssertTrue(rootMatches->load());
}

- (void)testFacadeOfflineLaunchIdentityCancellationSuppressesQueuedCompletion
{
    dispatch_semaphore_t updaterEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseUpdater = dispatch_semaphore_create(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.updateOfflineLaunchIdentity = [updaterEntered, releaseUpdater](
                                                    const std::filesystem::path&,
                                                    const FrontendOfflineLaunchIdentityUpdateRequest& request) {
        dispatch_semaphore_signal(updaterEntered);
        dispatch_semaphore_wait(releaseUpdater, DISPATCH_TIME_FOREVER);
        return FrontendOfflineLaunchIdentityUpdateResult{
            FrontendOfflineLaunchIdentityUpdateOutcome::Cancelled,
            std::nullopt,
            "accounts.offlineIdentity.cancelled",
            "Fixture identity update was cancelled.",
            false,
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);
    XCTestExpectation *completion = [self expectationWithDescription:@"Cancelled offline identity completion"];
    completion.inverted = YES;
    PRBridgeObservationToken *token = [bridge updateOfflineLaunchIdentityWithMode:PROfflineLaunchIdentityModeOffline
                                                                   accountIdentifier:@"account.fixture.offline"
                                                                                name:@"Native_Player"
                                                                   allowInvalidName:NO
                                                                         completion:^(__unused PROfflineLaunchIdentityUpdateResult *result,
                                                                                      __unused PRBridgeError *error) {
        [completion fulfill];
    }];
    XCTAssertNotNil(token);
    XCTAssertEqual(dispatch_semaphore_wait(updaterEntered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(releaseUpdater);
    [self waitForExpectations:@[ completion ] timeout:0.2];
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

- (void)testTaskScenarioMatrixCoversTerminalOutcomesCancellationAndRetryEligibility
{
    auto taskRootMatches = std::make_shared<std::atomic<bool>>(true);
    auto cancellationCalls = std::make_shared<std::vector<std::string>>();
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadTaskSnapshot = [taskRootMatches, fixtureRoot = self.fixtureRootURL.path.UTF8String](
                                       const std::filesystem::path& root,
                                       const std::string& identifier) -> std::optional<FrontendTaskSnapshot> {
        *taskRootMatches = *taskRootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        if (identifier == "task.success") {
            return FrontendTaskSnapshot{
                identifier,
                "Succeeded Fixture Task",
                FrontendTaskState::Succeeded,
                FrontendTaskProgressKind::Determinate,
                1.0,
                false,
                {},
                FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Succeeded,
                                            "task.succeeded",
                                            { { "taskIdentifier", identifier } },
                                            "",
                                            false },
            };
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
        if (identifier == "task.cancelled") {
            return FrontendTaskSnapshot{
                identifier,
                "Cancelled Fixture Task",
                FrontendTaskState::Cancelled,
                FrontendTaskProgressKind::Indeterminate,
                0.0,
                false,
                {},
                FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Cancelled,
                                            "task.cancelled",
                                            { { "taskIdentifier", identifier } },
                                            "fixture cancellation",
                                            false },
            };
        }
        if (identifier == "task.running") {
            return FrontendTaskSnapshot{ identifier,
                                         "Running Fixture Task",
                                         FrontendTaskState::Running,
                                         FrontendTaskProgressKind::Indeterminate,
                                         0.0,
                                         true,
                                         {},
                                         std::nullopt };
        }
        return std::nullopt;
    };
    dependencies.cancelTask = [taskRootMatches, cancellationCalls, fixtureRoot = self.fixtureRootURL.path.UTF8String](
                                  const std::filesystem::path& root,
                                  const std::string& identifier) {
        *taskRootMatches = *taskRootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        cancellationCalls->push_back(identifier);
        if (identifier == "task.running") {
            return FrontendTaskCancellationResult::Requested;
        }
        if (identifier == "task.success") {
            return FrontendTaskCancellationResult::AlreadyTerminal;
        }
        if (identifier == "task.failed") {
            return FrontendTaskCancellationResult::Rejected;
        }
        return FrontendTaskCancellationResult::UnknownTask;
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    NSArray<NSString *> *taskIdentifiers = @[ @"task.success", @"task.failed", @"task.cancelled", @"unknown-task" ];
    NSMutableDictionary<NSString *, PRTaskStatus *> *statuses = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, PRBridgeError *> *errors = [NSMutableDictionary dictionary];
    NSMutableArray<PRBridgeObservationToken *> *statusTokens = [NSMutableArray arrayWithCapacity:taskIdentifiers.count];
    XCTestExpectation *statusCompletions = [self expectationWithDescription:@"Task scenario matrix loaded"];
    statusCompletions.expectedFulfillmentCount = taskIdentifiers.count;
    for (NSString *identifier in taskIdentifiers) {
        NSString *identifierCopy = [identifier copy];
        PRBridgeObservationToken *token = [bridge loadTaskStatusWithIdentifier:identifierCopy
                                                                       completion:^(PRTaskStatus *status,
                                                                                    PRBridgeError *error) {
            XCTAssertTrue([NSThread isMainThread]);
            if (status) {
                statuses[identifierCopy] = status;
            }
            if (error) {
                errors[identifierCopy] = error;
            }
            [statusCompletions fulfill];
        }];
        XCTAssertNotNil(token);
        if (token) {
            [statusTokens addObject:token];
        }
    }
    [self waitForExpectations:@[ statusCompletions ] timeout:2.0];

    PRTaskStatus *succeededStatus = statuses[@"task.success"];
    XCTAssertEqual(succeededStatus.state, PRTaskStateSucceeded);
    XCTAssertEqual(succeededStatus.progressKind, PRTaskProgressKindDeterminate);
    XCTAssertEqual(succeededStatus.progressFraction, 1.0);
    XCTAssertEqual(succeededStatus.terminalResult.outcome, PRTaskTerminalOutcomeSucceeded);
    XCTAssertFalse(succeededStatus.cancellationAllowed);

    PRTaskStatus *failedStatus = statuses[@"task.failed"];
    XCTAssertEqual(failedStatus.state, PRTaskStateFailed);
    XCTAssertEqual(failedStatus.terminalResult.outcome, PRTaskTerminalOutcomeFailed);
    XCTAssertEqualObjects(failedStatus.terminalResult.diagnosticText, @"fixture failure");
    XCTAssertTrue(failedStatus.terminalResult.partialChangesRolledBack);

    PRTaskStatus *cancelledStatus = statuses[@"task.cancelled"];
    XCTAssertEqual(cancelledStatus.state, PRTaskStateCancelled);
    XCTAssertEqual(cancelledStatus.terminalResult.outcome, PRTaskTerminalOutcomeCancelled);
    XCTAssertEqualObjects(cancelledStatus.terminalResult.localizationKey, @"task.cancelled");
    XCTAssertFalse(cancelledStatus.cancellationAllowed);

    XCTAssertNil(statuses[@"unknown-task"]);
    XCTAssertEqual(errors[@"unknown-task"].code, PRBridgeErrorCodeDataUnavailable);
    XCTAssertEqual(errors[@"unknown-task"].recoveryKind, PRBridgeErrorRecoveryKindRetry);
    XCTAssertEqualObjects(errors[@"unknown-task"].substitutionValues,
                          (@{ @"taskIdentifier": @"unknown-task" }));

    void (^runCancellation)(NSString *, PRTaskCancellationOutcome) = ^(NSString *identifier,
                                                                         PRTaskCancellationOutcome expectedOutcome) {
        XCTestExpectation *completion = [self expectationWithDescription:@"Task scenario cancellation completed"];
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
        XCTAssertEqualObjects(
            receivedResult.identifier,
            [identifier stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        );
    };

    runCancellation(@" task.running ", PRTaskCancellationOutcomeRequested);
    runCancellation(@"task.success", PRTaskCancellationOutcomeAlreadyTerminal);
    runCancellation(@"task.failed", PRTaskCancellationOutcomeRejected);
    runCancellation(@"unknown-task", PRTaskCancellationOutcomeUnknownTask);

    XCTAssertTrue(taskRootMatches->load());
    XCTAssertTrue((*cancellationCalls
                   == std::vector<std::string>{ "task.running", "task.success", "task.failed", "unknown-task" }));
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

- (void)testFacadeTaskLogsArePrivacyFilteredBoundedAndDeliveredOnMainActor
{
    auto logRootMatches = std::make_shared<std::atomic<bool>>(true);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.streamTaskLogs = [logRootMatches, fixtureRoot = self.fixtureRootURL.path.UTF8String](
                                       const std::filesystem::path& root,
                                       const std::string& identifier,
                                       const FrontendRuntimeDependencies::LogEntryHandler& handler) {
        *logRootMatches = *logRootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        if (identifier != "task.logs") {
            return false;
        }

        for (std::uint64_t sequence = 0; sequence < kFrontendLogMaxEntries + 8; ++sequence) {
            std::string text = "fixture log " + std::to_string(sequence);
            if (sequence == kFrontendLogMaxEntries + 7) {
                text = "Authorization: Bearer fixture-secret access_token=fixture-token path="
                    + std::string(fixtureRoot) + "/instances/fixture";
            }
            handler(FrontendLogEntry{ sequence, std::move(text), false });
        }
        return true;
    };
    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *completion = [self expectationWithDescription:@"Facade logs completed"];
    __block PRTaskLogSnapshot *receivedSnapshot = nil;
    __block PRBridgeError *receivedError = nil;
    __block BOOL callbackRanOnMainThread = NO;
    PRBridgeObservationToken *token = [bridge loadTaskLogWithIdentifier:@" task.logs "
                                                             completion:^(PRTaskLogSnapshot *snapshot,
                                                                          PRBridgeError *error) {
        callbackRanOnMainThread = [NSThread isMainThread];
        receivedSnapshot = snapshot;
        receivedError = error;
        [completion fulfill];
    }];

    XCTAssertNotNil(token);
    [self waitForExpectations:@[ completion ] timeout:2.0];
    XCTAssertTrue(callbackRanOnMainThread);
    XCTAssertNil(receivedError);
    XCTAssertEqualObjects(receivedSnapshot.taskIdentifier, @"task.logs");
    XCTAssertEqual(receivedSnapshot.entries.count, (NSUInteger)kFrontendLogMaxEntries);
    XCTAssertEqual(receivedSnapshot.droppedEntryCount, (uint64_t)8);
    XCTAssertTrue(receivedSnapshot.truncated);
    XCTAssertEqual(receivedSnapshot.entries.firstObject.sequence, (uint64_t)8);
    XCTAssertFalse([receivedSnapshot.entries.lastObject.text containsString:@"fixture-secret"]);
    XCTAssertFalse([receivedSnapshot.entries.lastObject.text containsString:@"fixture-token"]);
    XCTAssertFalse([receivedSnapshot.entries.lastObject.text containsString:self.fixtureRootURL.path]);
    XCTAssertTrue([receivedSnapshot.entries.lastObject.text containsString:@"<redacted>"]);
    XCTAssertTrue([receivedSnapshot.entries.lastObject.text containsString:@"<data-root>"]);
    XCTAssertLessThanOrEqual(receivedSnapshot.totalByteCount, (uint64_t)kFrontendLogMaxBytes);
    XCTAssertTrue(logRootMatches->load());
    XCTAssertTrue(token.isCancelled);

    XCTestExpectation *unknownCompletion = [self expectationWithDescription:@"Unknown facade log rejected"];
    __block PRTaskLogSnapshot *unknownSnapshot = nil;
    __block PRBridgeError *unknownError = nil;
    PRBridgeObservationToken *unknownToken = [bridge loadTaskLogWithIdentifier:@"unknown-log"
                                                                    completion:^(PRTaskLogSnapshot *snapshot,
                                                                                 PRBridgeError *error) {
        unknownSnapshot = snapshot;
        unknownError = error;
        [unknownCompletion fulfill];
    }];
    XCTAssertNotNil(unknownToken);
    [self waitForExpectations:@[ unknownCompletion ] timeout:2.0];
    XCTAssertNil(unknownSnapshot);
    XCTAssertEqual(unknownError.code, PRBridgeErrorCodeDataUnavailable);
    XCTAssertEqual(unknownError.recoveryKind, PRBridgeErrorRecoveryKindRetry);
}

- (void)testTaskLogScenarioMatrixCoversOversizedLineTruncationAndRetry
{
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.streamTaskLogs = [](const std::filesystem::path&,
                                     const std::string& identifier,
                                     const FrontendRuntimeDependencies::LogEntryHandler& handler) {
        if (identifier == "task.long-log") {
            handler(FrontendLogEntry{ 42, std::string(kFrontendLogMaxBytes + 32, 'x'), false });
            return true;
        }
        return false;
    };
    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *completions = [self expectationWithDescription:@"Task log scenario matrix completed"];
    completions.expectedFulfillmentCount = 2;
    __block PRTaskLogSnapshot *longLogSnapshot = nil;
    __block PRTaskLogSnapshot *unknownLogSnapshot = nil;
    __block PRBridgeError *unknownLogError = nil;
    NSMutableArray<PRBridgeObservationToken *> *tokens = [NSMutableArray arrayWithCapacity:2];
    PRBridgeObservationToken *longLogToken = [bridge loadTaskLogWithIdentifier:@"task.long-log"
                                                                    completion:^(PRTaskLogSnapshot *snapshot,
                                                                                 PRBridgeError *error) {
        XCTAssertTrue([NSThread isMainThread]);
        longLogSnapshot = snapshot;
        XCTAssertNil(error);
        [completions fulfill];
    }];
    PRBridgeObservationToken *unknownLogToken = [bridge loadTaskLogWithIdentifier:@"unknown-log"
                                                                       completion:^(PRTaskLogSnapshot *snapshot,
                                                                                    PRBridgeError *error) {
        XCTAssertTrue([NSThread isMainThread]);
        unknownLogSnapshot = snapshot;
        unknownLogError = error;
        [completions fulfill];
    }];
    XCTAssertNotNil(longLogToken);
    XCTAssertNotNil(unknownLogToken);
    if (longLogToken) {
        [tokens addObject:longLogToken];
    }
    if (unknownLogToken) {
        [tokens addObject:unknownLogToken];
    }
    // The fixture intentionally exercises the facade's 256 KiB single-line
    // truncation path; keep the test budget above the measured C++ regex pass.
    [self waitForExpectations:@[ completions ] timeout:5.0];

    XCTAssertNotNil(longLogSnapshot);
    XCTAssertEqual(longLogSnapshot.entries.count, (NSUInteger)1);
    PRTaskLogEntry *entry = longLogSnapshot.entries.firstObject;
    XCTAssertNotNil(entry);
    if (entry) {
        XCTAssertEqual(entry.sequence, (uint64_t)42);
        XCTAssertTrue(entry.truncated);
        XCTAssertEqual(
            [entry.text lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
            (NSUInteger)kFrontendLogMaxBytes
        );
    }
    XCTAssertTrue(longLogSnapshot.truncated);
    XCTAssertEqual(longLogSnapshot.totalByteCount, (uint64_t)kFrontendLogMaxBytes);

    XCTAssertNil(unknownLogSnapshot);
    XCTAssertEqual(unknownLogError.code, PRBridgeErrorCodeDataUnavailable);
    XCTAssertEqual(unknownLogError.recoveryKind, PRBridgeErrorRecoveryKindRetry);
}

- (void)testCancellingQueuedFacadeLogRequestSuppressesCompletion
{
    auto enteredStreamer = dispatch_semaphore_create(0);
    auto releaseStreamer = dispatch_semaphore_create(0);
    auto streamerFinished = dispatch_semaphore_create(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.streamTaskLogs = [enteredStreamer, releaseStreamer, streamerFinished](
                                       const std::filesystem::path&,
                                       const std::string&,
                                       const FrontendRuntimeDependencies::LogEntryHandler& handler) {
        dispatch_semaphore_signal(enteredStreamer);
        dispatch_semaphore_wait(releaseStreamer, DISPATCH_TIME_FOREVER);
        handler(FrontendLogEntry{ 1, "fixture queued log", false });
        dispatch_semaphore_signal(streamerFinished);
        return true;
    };
    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    __block NSUInteger completionCount = 0;
    PRBridgeObservationToken *token = [bridge loadTaskLogWithIdentifier:@"task.logs"
                                                             completion:^(PRTaskLogSnapshot *, PRBridgeError *) {
        completionCount += 1;
    }];
    XCTAssertNotNil(token);
    XCTAssertEqual(dispatch_semaphore_wait(enteredStreamer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(releaseStreamer);
    XCTAssertEqual(dispatch_semaphore_wait(streamerFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);

    XCTestExpectation *drained = [self expectationWithDescription:@"Cancelled log request queue drained"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [drained fulfill];
    });
    [self waitForExpectations:@[ drained ] timeout:2.0];
    XCTAssertEqual(completionCount, (NSUInteger)0);
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
    XCTAssertNil([bridge loadTaskLogWithIdentifier:@"task.fixture" completion:^(PRTaskLogSnapshot *, PRBridgeError *) {
    }]);
    XCTAssertNil([bridge cancelTaskWithIdentifier:@"task.fixture"
                                           completion:^(PRTaskCancellationResult *, PRBridgeError *) {
                                           }]);
    XCTAssertNil([bridge launchInstanceWithIdentifier:@"fixture.one" completion:^(PRInstanceCommandResult *, PRBridgeError *) {
    }]);
}

- (void)testInstanceDetailListsLogsAndConfirmedActionsStayFoundationOnly
{
    const std::string fixtureRoot = self.fixtureRootURL.path.UTF8String;
    auto rootMatches = std::make_shared<std::atomic<bool>>(true);
    auto mutationCalls = std::make_shared<std::vector<std::string>>();

    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadInstanceWorlds = [rootMatches, fixtureRoot](const std::filesystem::path& root,
                                                                  const std::string& identifier)
        -> std::optional<std::vector<FrontendInstanceWorldSnapshot>> {
        *rootMatches = *rootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        if (identifier != "fixture.one") {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceWorldSnapshot>{
            { "world.one", "Fixture World", "world", "Survival", "grass", "Archive warning", 123, 2048,
              42, true, true, true, true, true, true, true },
            { "world.two", "Second World", "world-two", "Creative", "", "", 0, 512, 0, false, false, true,
              true, false, false },
        };
    };
    dependencies.loadInstanceServers = [rootMatches, fixtureRoot](const std::filesystem::path& root,
                                                                    const std::string& identifier)
        -> std::optional<std::vector<FrontendInstanceServerSnapshot>> {
        *rootMatches = *rootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        if (identifier != "fixture.one") {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceServerSnapshot>{
            { "server.one", "Fixture Server", "fixture.example:25565", FrontendServerResourcePolicy::Ask,
              FrontendServerStatus::Online, 4, true, true, true },
        };
    };
    dependencies.loadInstanceScreenshots = [rootMatches, fixtureRoot](const std::filesystem::path& root,
                                                                        const std::string& identifier)
        -> std::optional<std::vector<FrontendInstanceScreenshotSnapshot>> {
        *rootMatches = *rootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        if (identifier != "fixture.one") {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceScreenshotSnapshot>{
            { "shot.one", "2026-08-09.png", "2026-08-09", 456, 4096, true, true },
        };
    };
    dependencies.loadInstanceLogFiles = [rootMatches, fixtureRoot](const std::filesystem::path& root,
                                                                     const std::string& identifier)
        -> std::optional<std::vector<FrontendInstanceLogFileSnapshot>> {
        *rootMatches = *rootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        if (identifier != "fixture.one") {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceLogFileSnapshot>{
            { "latest", "latest.log", "Latest", 789, 35, false, true, true, false },
            { "previous", "previous.log.gz", "Previous", 700, 128, true, false, true, true },
        };
    };
    dependencies.loadInstanceLog = [rootMatches, fixtureRoot](const std::filesystem::path& root,
                                                               const std::string& identifier,
                                                               const std::string& logIdentifier)
        -> std::optional<FrontendInstanceLogSnapshot> {
        *rootMatches = *rootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        if (identifier != "fixture.one" || logIdentifier != "latest") {
            return std::nullopt;
        }
        return FrontendInstanceLogSnapshot{
            "fixture.one",
            "latest",
            { { 1, "first fixture line", false }, { 2, "second fixture line", false } },
            0,
            37,
            false,
        };
    };
    dependencies.mutateInstanceDetail = [rootMatches, mutationCalls, fixtureRoot](
                                           const std::filesystem::path& root,
                                           const std::string& identifier,
                                           const FrontendInstanceDetailMutationRequest& request) {
        *rootMatches = *rootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        mutationCalls->push_back(identifier + ":" + std::to_string(static_cast<int>(request.kind)) + ":"
                                 + std::to_string(static_cast<int>(request.action)) + ":" + request.itemIdentifier);
        return FrontendInstanceDetailMutationResult{
            request.kind,
            request.action,
            FrontendInstanceDetailMutationOutcome::Succeeded,
            identifier,
            request.itemIdentifier,
            "instance.detail.succeeded",
            {},
            false,
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    XCTestExpectation *worldsCompletion = [self expectationWithDescription:@"World list completed"];
    __block NSArray<PRInstanceWorld *> *worlds = nil;
    __block PRBridgeError *worldsError = nil;
    __block BOOL worldsOnMain = NO;
    PRBridgeObservationToken *worldsToken = [bridge loadInstanceWorldsWithIdentifier:@" fixture.one "
                                                                            completion:^(NSArray<PRInstanceWorld *> *received,
                                                                                         PRBridgeError *error) {
        worlds = received;
        worldsError = error;
        worldsOnMain = [NSThread isMainThread];
        [worldsCompletion fulfill];
    }];
    XCTAssertNotNil(worldsToken);
    [self waitForExpectations:@[ worldsCompletion ] timeout:2.0];
    XCTAssertTrue(worldsOnMain);
    XCTAssertNil(worldsError);
    XCTAssertEqual(worlds.count, (NSUInteger)2);
    XCTAssertEqualObjects(worlds[0].identifier, @"world.one");
    XCTAssertEqualObjects(worlds[0].folderName, @"world");
    XCTAssertEqualObjects(worlds[0].seed, @42);
    XCTAssertTrue(worlds[0].archive);
    XCTAssertEqualObjects(worlds[1].name, @"Second World");

    XCTestExpectation *serversCompletion = [self expectationWithDescription:@"Server list completed"];
    __block NSArray<PRInstanceServer *> *servers = nil;
    __block PRBridgeError *serversError = nil;
    PRBridgeObservationToken *serversToken = [bridge loadInstanceServersWithIdentifier:@"fixture.one"
                                                                              completion:^(NSArray<PRInstanceServer *> *received,
                                                                                           PRBridgeError *error) {
        servers = received;
        serversError = error;
        [serversCompletion fulfill];
    }];
    XCTAssertNotNil(serversToken);
    [self waitForExpectations:@[ serversCompletion ] timeout:2.0];
    XCTAssertNil(serversError);
    XCTAssertEqual(servers.count, (NSUInteger)1);
    XCTAssertEqual(servers[0].status, PRInstanceServerStatusOnline);
    XCTAssertEqual(servers[0].onlinePlayers, (NSInteger)4);

    XCTestExpectation *screenshotsCompletion = [self expectationWithDescription:@"Screenshot list completed"];
    __block NSArray<PRInstanceScreenshot *> *screenshots = nil;
    PRBridgeObservationToken *screenshotsToken =
        [bridge loadInstanceScreenshotsWithIdentifier:@"fixture.one"
                                            completion:^(NSArray<PRInstanceScreenshot *> *received, PRBridgeError *) {
        screenshots = received;
        [screenshotsCompletion fulfill];
    }];
    XCTAssertNotNil(screenshotsToken);
    [self waitForExpectations:@[ screenshotsCompletion ] timeout:2.0];
    XCTAssertEqual(screenshots.count, (NSUInteger)1);
    XCTAssertEqualObjects(screenshots[0].fileName, @"2026-08-09.png");
    XCTAssertTrue(screenshots[0].readable);

    XCTestExpectation *logFilesCompletion = [self expectationWithDescription:@"Log-file list completed"];
    __block NSArray<PRInstanceLogFile *> *logFiles = nil;
    PRBridgeObservationToken *logFilesToken =
        [bridge loadInstanceLogFilesWithIdentifier:@"fixture.one"
                                          completion:^(NSArray<PRInstanceLogFile *> *received, PRBridgeError *) {
        logFiles = received;
        [logFilesCompletion fulfill];
    }];
    XCTAssertNotNil(logFilesToken);
    [self waitForExpectations:@[ logFilesCompletion ] timeout:2.0];
    XCTAssertEqual(logFiles.count, (NSUInteger)2);
    XCTAssertTrue(logFiles[0].current);
    XCTAssertTrue(logFiles[1].compressed);
    XCTAssertTrue(logFiles[1].canBeDeleted);

    XCTestExpectation *logCompletion = [self expectationWithDescription:@"Log content completed"];
    __block PRInstanceLogSnapshot *logSnapshot = nil;
    __block PRBridgeError *logError = nil;
    PRBridgeObservationToken *logToken = [bridge loadInstanceLogWithIdentifier:@"fixture.one"
                                                                    logIdentifier:@"latest"
                                                                        completion:^(PRInstanceLogSnapshot *received,
                                                                                     PRBridgeError *error) {
        logSnapshot = received;
        logError = error;
        [logCompletion fulfill];
    }];
    XCTAssertNotNil(logToken);
    [self waitForExpectations:@[ logCompletion ] timeout:2.0];
    XCTAssertNil(logError);
    XCTAssertEqualObjects(logSnapshot.instanceIdentifier, @"fixture.one");
    XCTAssertEqualObjects(logSnapshot.logIdentifier, @"latest");
    XCTAssertEqual(logSnapshot.entries.count, (NSUInteger)2);
    XCTAssertEqualObjects(logSnapshot.entries[0].text, @"first fixture line");
    XCTAssertEqual(logSnapshot.totalByteCount, (uint64_t)37);

    PRInstanceDetailMutationRequest *unconfirmedDelete =
        [[PRInstanceDetailMutationRequest alloc] initWithKind:PRInstanceDetailKindWorlds
                                                        action:PRInstanceDetailActionDelete
                                               itemIdentifier:@"world.one"
                                                    sourceURL:nil
                                                   targetName:@""
                                                          name:@""
                                                       address:@""
                                                resourcePolicy:PRInstanceServerResourcePolicyAsk
                                                     confirmed:NO
                                                      position:-1];
    XCTestExpectation *rejectedCompletion = [self expectationWithDescription:@"Unconfirmed delete rejected"];
    __block PRBridgeError *rejectedError = nil;
    PRBridgeObservationToken *rejectedToken =
        [bridge applyInstanceDetailActionWithIdentifier:@"fixture.one"
                                                 request:unconfirmedDelete
                                             completion:^(__unused PRInstanceDetailMutationResult *result,
                                                         PRBridgeError *error) {
        rejectedError = error;
        [rejectedCompletion fulfill];
    }];
    XCTAssertNotNil(rejectedToken);
    [self waitForExpectations:@[ rejectedCompletion ] timeout:2.0];
    XCTAssertEqual(rejectedError.code, PRBridgeErrorCodeInvalidInput);
    XCTAssertEqual(mutationCalls->size(), (size_t)0);

    PRInstanceDetailMutationRequest *confirmedDelete =
        [[PRInstanceDetailMutationRequest alloc] initWithKind:PRInstanceDetailKindWorlds
                                                        action:PRInstanceDetailActionDelete
                                               itemIdentifier:@"world.one"
                                                    sourceURL:nil
                                                   targetName:@""
                                                          name:@""
                                                       address:@""
                                                resourcePolicy:PRInstanceServerResourcePolicyAsk
                                                     confirmed:YES
                                                      position:-1];
    XCTestExpectation *mutationCompletion = [self expectationWithDescription:@"Confirmed delete completed"];
    __block PRInstanceDetailMutationResult *mutationResult = nil;
    PRBridgeObservationToken *mutationToken =
        [bridge applyInstanceDetailActionWithIdentifier:@"fixture.one"
                                                 request:confirmedDelete
                                             completion:^(PRInstanceDetailMutationResult *result, PRBridgeError *) {
        mutationResult = result;
        [mutationCompletion fulfill];
    }];
    XCTAssertNotNil(mutationToken);
    [self waitForExpectations:@[ mutationCompletion ] timeout:2.0];
    XCTAssertEqual(mutationResult.outcome, PRInstanceDetailMutationOutcomeSucceeded);
    XCTAssertEqualObjects(mutationResult.itemIdentifier, @"world.one");
    XCTAssertEqual(mutationCalls->size(), (size_t)1);
    XCTAssertTrue(rootMatches->load());
}

- (void)testInstanceDetailFailureScenariosPreserveRecoveryMetadata
{
    auto rootMatches = std::make_shared<std::atomic<bool>>(true);
    auto mutationCalls = std::make_shared<std::vector<std::string>>();
    const std::string fixtureRoot = self.fixtureRootURL.path.UTF8String;
    NSURL *invalidArchiveURL = [self.fixtureRootURL URLByAppendingPathComponent:@"invalid-world.zip"];
    NSError *writeError = nil;
    XCTAssertTrue([@"not a valid zip archive" writeToURL:invalidArchiveURL
                                                atomically:YES
                                                  encoding:NSUTF8StringEncoding
                                                     error:&writeError]);
    XCTAssertNil(writeError);

    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.mutateInstanceDetail = [rootMatches, mutationCalls, fixtureRoot](
                                           const std::filesystem::path& root,
                                           const std::string& identifier,
                                           const FrontendInstanceDetailMutationRequest& request) {
        *rootMatches = *rootMatches && root == std::filesystem::path(fixtureRoot).lexically_normal();
        mutationCalls->push_back(request.itemIdentifier);
        if (request.itemIdentifier == "world.permission") {
            return FrontendInstanceDetailMutationResult{
                request.kind,
                request.action,
                FrontendInstanceDetailMutationOutcome::Rejected,
                identifier,
                request.itemIdentifier,
                "instance.world.deletePermissionDenied",
                "fixture permission denied",
                false,
            };
        }
        if (request.itemIdentifier == "screenshot.missing") {
            return FrontendInstanceDetailMutationResult{
                request.kind,
                request.action,
                FrontendInstanceDetailMutationOutcome::UnknownItem,
                identifier,
                request.itemIdentifier,
                "instance.screenshot.missing",
                "fixture screenshot is missing",
                false,
            };
        }
        if (request.itemIdentifier == "server.conflict") {
            return FrontendInstanceDetailMutationResult{
                request.kind,
                request.action,
                FrontendInstanceDetailMutationOutcome::Failed,
                identifier,
                request.itemIdentifier,
                "instance.server.updateConflict",
                "fixture server changed externally",
                true,
            };
        }
        return FrontendInstanceDetailMutationResult{
            request.kind,
            request.action,
            FrontendInstanceDetailMutationOutcome::Failed,
            identifier,
            request.itemIdentifier,
            "instance.world.importInvalidArchive",
            "fixture archive is not a valid world archive",
            false,
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    auto applyScenario = ^PRInstanceDetailMutationResult *(PRInstanceDetailMutationRequest *request) {
        XCTestExpectation *completion = [self expectationWithDescription:@"Instance detail scenario completed"];
        __block PRInstanceDetailMutationResult *result = nil;
        __block PRBridgeError *error = nil;
        PRBridgeObservationToken *token = [bridge
            applyInstanceDetailActionWithIdentifier:@"fixture.one"
                                             request:request
                                         completion:^(PRInstanceDetailMutationResult *received,
                                                     PRBridgeError *receivedError) {
            result = received;
            error = receivedError;
            [completion fulfill];
        }];
        XCTAssertNotNil(token);
        [self waitForExpectations:@[ completion ] timeout:2.0];
        XCTAssertNil(error);
        return result;
    };

    PRInstanceDetailMutationResult *permissionResult = applyScenario(
        [[PRInstanceDetailMutationRequest alloc] initWithKind:PRInstanceDetailKindWorlds
                                                        action:PRInstanceDetailActionDelete
                                               itemIdentifier:@"world.permission"
                                                    sourceURL:nil
                                                   targetName:@""
                                                          name:@""
                                                       address:@""
                                                resourcePolicy:PRInstanceServerResourcePolicyAsk
                                                     confirmed:YES
                                                      position:-1]);
    PRInstanceDetailMutationResult *missingResult = applyScenario(
        [[PRInstanceDetailMutationRequest alloc] initWithKind:PRInstanceDetailKindScreenshots
                                                        action:PRInstanceDetailActionDelete
                                               itemIdentifier:@"screenshot.missing"
                                                    sourceURL:nil
                                                   targetName:@""
                                                          name:@""
                                                       address:@""
                                                resourcePolicy:PRInstanceServerResourcePolicyAsk
                                                     confirmed:YES
                                                      position:-1]);
    PRInstanceDetailMutationResult *conflictResult = applyScenario(
        [[PRInstanceDetailMutationRequest alloc] initWithKind:PRInstanceDetailKindServers
                                                        action:PRInstanceDetailActionUpdate
                                               itemIdentifier:@"server.conflict"
                                                    sourceURL:nil
                                                   targetName:@""
                                                          name:@"Conflicting Server"
                                                       address:@"fixture.example:25565"
                                                resourcePolicy:PRInstanceServerResourcePolicyAsk
                                                     confirmed:NO
                                                      position:-1]);
    PRInstanceDetailMutationResult *invalidArchiveResult = applyScenario(
        [[PRInstanceDetailMutationRequest alloc] initWithKind:PRInstanceDetailKindWorlds
                                                        action:PRInstanceDetailActionImport
                                               itemIdentifier:@"invalid-world.zip"
                                                    sourceURL:invalidArchiveURL
                                                   targetName:@""
                                                          name:@""
                                                       address:@""
                                                resourcePolicy:PRInstanceServerResourcePolicyAsk
                                                     confirmed:NO
                                                      position:-1]);

    XCTAssertEqual(permissionResult.outcome, PRInstanceDetailMutationOutcomeRejected);
    XCTAssertEqualObjects(permissionResult.localizationKey, @"instance.world.deletePermissionDenied");
    XCTAssertEqualObjects(permissionResult.diagnosticText, @"fixture permission denied");
    XCTAssertFalse(permissionResult.partialChangesRolledBack);
    XCTAssertEqual(missingResult.outcome, PRInstanceDetailMutationOutcomeUnknownItem);
    XCTAssertEqualObjects(missingResult.localizationKey, @"instance.screenshot.missing");
    XCTAssertEqual(conflictResult.outcome, PRInstanceDetailMutationOutcomeFailed);
    XCTAssertEqualObjects(conflictResult.localizationKey, @"instance.server.updateConflict");
    XCTAssertEqualObjects(conflictResult.diagnosticText, @"fixture server changed externally");
    XCTAssertTrue(conflictResult.partialChangesRolledBack);
    XCTAssertEqual(invalidArchiveResult.outcome, PRInstanceDetailMutationOutcomeFailed);
    XCTAssertEqualObjects(invalidArchiveResult.localizationKey, @"instance.world.importInvalidArchive");
    XCTAssertFalse(invalidArchiveResult.partialChangesRolledBack);
    XCTAssertTrue(rootMatches->load());
    XCTAssertEqual(mutationCalls->size(), (size_t)4);
}

- (void)testInstanceDetailMutationCancellationSuppressesQueuedCompletion
{
    dispatch_semaphore_t mutatorEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseMutator = dispatch_semaphore_create(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.mutateInstanceDetail = [mutatorEntered, releaseMutator](
                                           const std::filesystem::path&,
                                           const std::string& identifier,
                                           const FrontendInstanceDetailMutationRequest& request) {
        dispatch_semaphore_signal(mutatorEntered);
        dispatch_semaphore_wait(releaseMutator, DISPATCH_TIME_FOREVER);
        return FrontendInstanceDetailMutationResult{
            request.kind,
            request.action,
            FrontendInstanceDetailMutationOutcome::Succeeded,
            identifier,
            request.itemIdentifier,
            "instance.detail.updated",
            "fixture detail mutation succeeded",
            false,
        };
    };

    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    PRInstanceDetailMutationRequest *request =
        [[PRInstanceDetailMutationRequest alloc] initWithKind:PRInstanceDetailKindWorlds
                                                        action:PRInstanceDetailActionDelete
                                               itemIdentifier:@"world.cancelled"
                                                    sourceURL:nil
                                                   targetName:@""
                                                          name:@""
                                                       address:@""
                                                resourcePolicy:PRInstanceServerResourcePolicyAsk
                                                     confirmed:YES
                                                      position:-1];
    __block NSUInteger completionCount = 0;
    PRBridgeObservationToken *token = [bridge
        applyInstanceDetailActionWithIdentifier:@"fixture.one"
                                         request:request
                                     completion:^(__unused PRInstanceDetailMutationResult *result,
                                                 __unused PRBridgeError *error) {
        completionCount += 1;
    }];
    XCTAssertNotNil(token);
    XCTAssertEqual(dispatch_semaphore_wait(mutatorEntered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(releaseMutator);

    XCTestExpectation *drained = [self expectationWithDescription:@"Cancelled detail mutation drained"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [drained fulfill];
    });
    [self waitForExpectations:@[ drained ] timeout:2.0];
    XCTAssertEqual(completionCount, (NSUInteger)0);
}

- (void)testInstanceWorldCancellationSuppressesQueuedCompletion
{
    dispatch_semaphore_t loaderEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseLoader = dispatch_semaphore_create(0);
    FrontendRuntimeDependencies dependencies = baseFixtureDependencies();
    dependencies.loadInstanceWorlds = [loaderEntered, releaseLoader](const std::filesystem::path&,
                                                                       const std::string&)
        -> std::optional<std::vector<FrontendInstanceWorldSnapshot>> {
        dispatch_semaphore_signal(loaderEntered);
        dispatch_semaphore_wait(releaseLoader, DISPATCH_TIME_FOREVER);
        return std::vector<FrontendInstanceWorldSnapshot>{
            { "world.cancelled", "Cancelled World", "world", "Survival", "", "", 0, 0, 0, false, true,
              true, true, false, false },
        };
    };
    PRPrismBridge *bridge = [self bridgeWithDependencies:std::move(dependencies)
                                       cancellationHandler:nil
                                          shutdownHandler:nil];
    XCTAssertNotNil(bridge);

    __block NSUInteger completionCount = 0;
    PRBridgeObservationToken *token = [bridge loadInstanceWorldsWithIdentifier:@"fixture.one"
                                                                     completion:^(NSArray<PRInstanceWorld *> *, PRBridgeError *) {
        completionCount += 1;
    }];
    XCTAssertNotNil(token);
    XCTAssertEqual(dispatch_semaphore_wait(loaderEntered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    XCTAssertTrue([token cancel]);
    dispatch_semaphore_signal(releaseLoader);

    XCTestExpectation *drained = [self expectationWithDescription:@"Cancelled world request drained"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [drained fulfill];
    });
    [self waitForExpectations:@[ drained ] timeout:2.0];
    XCTAssertEqual(completionCount, (NSUInteger)0);
}

@end
