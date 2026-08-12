import Foundation
import XCTest

final class PrismNativeInfrastructureTests: XCTestCase {
    func testPublicBridgeHeadersContainNoQtOrCppTypes() throws {
        let headers = try PrismBridgeHeaderScanner.publicHeaders(relativeTo: #filePath)

        for header in headers {
            XCTAssertEqual(
                try PrismBridgeHeaderScanner.forbiddenTokens(in: header),
                [],
                "Forbidden bridge type in \(header.path)"
            )
        }
    }

    func testBridgeHeaderScannerRejectsForbiddenTypes() {
        let fixtureHeader = """
        #import <Foundation/Foundation.h>
        class FakeFacade { QWidget *widget; std::vector<int> values; };
        """

        XCTAssertEqual(
            Set(PrismBridgeHeaderScanner.forbiddenTokens(in: fixtureHeader)),
            Set(["QWidget", "std::"])
        )
    }

    func testFixtureRootIsTemporaryAndOutsideUpstreamApplicationSupport() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()

        XCTAssertTrue(fixtureRoot.isInsideTemporaryDirectory)
        XCTAssertTrue(fixtureRoot.isOutsideUpstreamApplicationSupport)

        let fixtureFile = try fixtureRoot.makeFile(
            relativePath: "instances/fixture.json",
            contents: "{}"
        )
        XCTAssertEqual(try String(contentsOf: fixtureFile, encoding: .utf8), "{}")
    }

    func testCallbackRecorderSuppressesDeliveryAfterCancellation() {
        let cancellation = PrismTestCancellation()
        let recorder = PrismTestCallbackRecorder<String>()

        recorder.record("before", unlessCancelledBy: cancellation)
        cancellation.cancel()
        recorder.record("after", unlessCancelledBy: cancellation)

        XCTAssertEqual(recorder.values, ["before"])
    }

    func testBridgeRootRequiresAnExplicitFixtureRootAndOwnsLifecycle() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let fixtureMarker = try fixtureRoot.makeFile(relativePath: "bridge.marker", contents: "fixture")
        let callbackRecorder = PrismTestCallbackRecorder<String>()
        let stateRecorder = PrismTestCallbackRecorder<PRBridgeLifecycleState>()
        let bridgeReference = PrismWeakBridgeReference()
        weak var observer: NSObject?

        let bridge: PRPrismBridge = try XCTUnwrap(
            PRPrismBridge(
                dataRootURL: fixtureRoot.url,
                cancellationHandler: {
                    callbackRecorder.record("cancel")
                },
                shutdownHandler: {
                    callbackRecorder.record("shutdown")
                    if let bridge = bridgeReference.bridge {
                        stateRecorder.record(bridge.lifecycleState)
                    }
                }
            )
        )
        bridgeReference.bridge = bridge
        XCTAssertEqual(bridge.dataRootURL.standardizedFileURL, fixtureRoot.url.standardizedFileURL)
        XCTAssertEqual(bridge.lifecycleState, .running)
        XCTAssertTrue(fixtureRoot.isInsideTemporaryDirectory)
        XCTAssertTrue(fixtureRoot.isOutsideUpstreamApplicationSupport)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureMarker.path))

        do {
            let token = NSObject()
            observer = token
            let retainingBridge: PRPrismBridge? = PRPrismBridge(
                dataRootURL: fixtureRoot.url,
                cancellationHandler: { _ = token },
                shutdownHandler: { _ = token }
            )
            XCTAssertNotNil(observer)
            XCTAssertTrue(retainingBridge?.shutdown() == true)
        }
        XCTAssertNil(observer)

        XCTAssertTrue(bridge.shutdown())
        XCTAssertFalse(bridge.shutdown())
        XCTAssertEqual(bridge.lifecycleState, .stopped)
        XCTAssertEqual(callbackRecorder.values, ["cancel", "shutdown"])
        XCTAssertEqual(stateRecorder.values, [.shuttingDown])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureMarker.path))
    }

    func testBridgeRootRejectsImplicitOrNonFileRoots() {
        XCTAssertNil(
            PRPrismBridge(
                dataRootURL: URL(string: "file:relative-root")!,
                cancellationHandler: nil,
                shutdownHandler: nil
            )
        )
        XCTAssertNil(
            PRPrismBridge(
                dataRootURL: URL(string: "https://example.invalid/prism")!,
                cancellationHandler: nil,
                shutdownHandler: nil
            )
        )
    }

    func testBridgeRootDeinitializationShutsDownExactlyOnce() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let callbackRecorder = PrismTestCallbackRecorder<String>()

        do {
            let bridge: PRPrismBridge = try XCTUnwrap(
                PRPrismBridge(
                    dataRootURL: fixtureRoot.url,
                    cancellationHandler: {
                        callbackRecorder.record("cancel")
                    },
                    shutdownHandler: {
                        callbackRecorder.record("shutdown")
                    }
                )
            )
            XCTAssertEqual(bridge.lifecycleState, .running)
        }

        XCTAssertEqual(callbackRecorder.values, ["cancel", "shutdown"])
    }

    func testProductionBridgeCreatesLoadsObservesAndReconstructsMetadataOnlyInstance() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let bridge: PRPrismBridge = try XCTUnwrap(
            PRPrismBridge(dataRootURL: fixtureRoot.url, cancellationHandler: nil, shutdownHandler: nil)
        )
        let changeExpectation = expectation(description: "production instance change")
        let createExpectation = expectation(description: "metadata instance creation")
        let loadExpectation = expectation(description: "metadata instance load")
        var observedIdentifier: String?
        var createdSummary: PRInstanceSummary?
        var loadedSummaries: [PRInstanceSummary] = []
        var createToken: PRBridgeObservationToken?
        var loadToken: PRBridgeObservationToken?

        let observation = bridge.observeInstanceChanges { change in
            if change.kind == .added, change.identifier == "native.bridge" {
                observedIdentifier = change.identifier
                changeExpectation.fulfill()
            }
        }
        XCTAssertNotNil(observation)

        createToken = bridge.createMetadataOnlyInstance(
            withIdentifier: "native.bridge",
            name: "Native Bridge",
            iconKey: "default"
        ) { summary, error in
            XCTAssertNil(error)
            createdSummary = summary
            createExpectation.fulfill()
        }
        wait(for: [createExpectation, changeExpectation], timeout: 3)
        XCTAssertNotNil(createToken)
        XCTAssertEqual(createdSummary?.identifier, "native.bridge")
        XCTAssertEqual(observedIdentifier, "native.bridge")

        loadToken = bridge.loadInstanceSummaries { summaries, error in
            XCTAssertNil(error)
            loadedSummaries = summaries
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 3)
        XCTAssertEqual(loadedSummaries.map(\.identifier), ["native.bridge"])
        XCTAssertNotNil(loadToken)
        XCTAssertTrue(bridge.shutdown())
        XCTAssertTrue(observation?.isCancelled == true)

        let reconstructed: PRPrismBridge = try XCTUnwrap(
            PRPrismBridge(dataRootURL: fixtureRoot.url, cancellationHandler: nil, shutdownHandler: nil)
        )
        let reconstructionExpectation = expectation(description: "reconstructed metadata instance load")
        var reconstructedSummaries: [PRInstanceSummary] = []
        var reconstructionToken: PRBridgeObservationToken?
        reconstructionToken = reconstructed.loadInstanceSummaries { summaries, error in
            XCTAssertNil(error)
            reconstructedSummaries = summaries
            reconstructionExpectation.fulfill()
        }
        wait(for: [reconstructionExpectation], timeout: 3)
        XCTAssertEqual(reconstructedSummaries.map(\.name), ["Native Bridge"])
        XCTAssertNotNil(reconstructionToken)
        XCTAssertTrue(reconstructed.shutdown())
    }

    func testProductionCompositionInjectsBridgeIntoSettingsModels() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try readSource(at: macosRoot.appendingPathComponent("PrismNative/App/PrismNativeApp.swift"))
        let contentSource = try readSource(at: macosRoot.appendingPathComponent("PrismNative/App/ContentView.swift"))
        let repositoryRoot = macosRoot.deletingLastPathComponent()
        let accountRuntimeSource = try readSource(
            at: repositoryRoot.appendingPathComponent("launcher/frontend/ProductionAccountRuntime.cpp")
        )
        let accountRuntimeHeader = try readSource(
            at: repositoryRoot.appendingPathComponent("launcher/frontend/ProductionAccountRuntime.h")
        )

        XCTAssertTrue(appSource.contains("PrismGlobalSettingsModel(initialSettings: nil, bridge: runtime.bridge)"))
        XCTAssertFalse(appSource.contains("@StateObject private var globalSettingsModel = PrismGlobalSettingsModel()"))
        XCTAssertTrue(appSource.contains("PrismJavaDiscoveryModel(initialInstallations: [], bridge: runtime.bridge)"))
        XCTAssertFalse(appSource.contains("@StateObject private var javaDiscoveryModel = PrismJavaDiscoveryModel()"))
        XCTAssertTrue(appSource.contains("PrismAccountModel(initialAccounts: [], activeAccountID: nil, bridge: runtime.bridge)"))
        XCTAssertFalse(appSource.contains("@StateObject private var accountModel = PrismAccountModel()"))
        XCTAssertTrue(appSource.contains("PrismAccountAuthenticationModel(bridge: runtime.bridge)"))
        XCTAssertFalse(appSource.contains("@StateObject private var authenticationModel = PrismAccountAuthenticationModel()"))
        XCTAssertTrue(appSource.contains("PrismOfflineLaunchIdentityModel(bridge: runtime.bridge)"))
        XCTAssertFalse(appSource.contains("@StateObject private var offlineIdentityModel = PrismOfflineLaunchIdentityModel()"))
        XCTAssertTrue(contentSource.contains("PrismInstanceSettingsModel(bridge: bridge)"))
        XCTAssertTrue(contentSource.contains("loadIfNeeded(identifier: details.id)"))
        XCTAssertTrue(accountRuntimeSource.contains("AccountData"))
        XCTAssertTrue(accountRuntimeSource.contains("accounts.json"))
        XCTAssertTrue(accountRuntimeSource.contains("LastOfflinePlayerName"))
        XCTAssertTrue(accountRuntimeHeader.contains("KeychainPort"))
        XCTAssertTrue(accountRuntimeHeader.contains("BrowserExecutor"))
        XCTAssertFalse(accountRuntimeSource.contains("#include <QWidget>"))
        XCTAssertFalse(accountRuntimeSource.contains("#include <QDialog>"))
        XCTAssertFalse(accountRuntimeSource.contains("Application.h"))
    }

    func testProductionBridgeLoadsBundleScopedGlobalAndInstanceSettings() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let bridge: PRPrismBridge = try XCTUnwrap(
            PRPrismBridge(dataRootURL: fixtureRoot.url, cancellationHandler: nil, shutdownHandler: nil)
        )

        let globalExpectation = expectation(description: "production global settings")
        var globalSettings: PRGlobalSettings?
        var globalError: PRBridgeError?
        var globalToken: PRBridgeObservationToken?
        globalToken = bridge.loadGlobalSettings { settings, error in
            globalSettings = settings
            globalError = error
            globalExpectation.fulfill()
        }
        wait(for: [globalExpectation], timeout: 3)
        XCTAssertNotNil(globalToken)
        XCTAssertNil(globalError)
        XCTAssertEqual(globalSettings?.instanceDirectoryURL.standardizedFileURL,
                       fixtureRoot.url.appendingPathComponent("instances", isDirectory: true).standardizedFileURL)
        XCTAssertEqual(globalSettings?.catFit, "fit")
        XCTAssertEqual(globalSettings?.numberOfConcurrentTasks, 10)

        let createExpectation = expectation(description: "production settings instance")
        var createToken: PRBridgeObservationToken?
        createToken = bridge.createMetadataOnlyInstance(
            withIdentifier: "native.settings",
            name: "Native Settings",
            iconKey: "default"
        ) { summary, error in
            XCTAssertNil(error)
            XCTAssertEqual(summary?.identifier, "native.settings")
            createExpectation.fulfill()
        }
        wait(for: [createExpectation], timeout: 3)
        XCTAssertNotNil(createToken)

        let instanceExpectation = expectation(description: "production instance settings")
        var instanceSettings: PRInstanceSettings?
        var instanceError: PRBridgeError?
        var instanceToken: PRBridgeObservationToken?
        instanceToken = bridge.loadInstanceSettings(withIdentifier: "native.settings") { settings, error in
            instanceSettings = settings
            instanceError = error
            instanceExpectation.fulfill()
        }
        wait(for: [instanceExpectation], timeout: 3)
        XCTAssertNotNil(instanceToken)
        XCTAssertNil(instanceError)
        XCTAssertEqual(instanceSettings?.identifier, "native.settings")
        XCTAssertEqual(instanceSettings?.windowWidth, 854)
        XCTAssertEqual(instanceSettings?.minMemoryMiB, 512)
        XCTAssertTrue(bridge.shutdown())
    }

    func testNativeTargetOwnsBundleMetadataAndHardenedRuntimeEntitlements() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectSource = try readSource(
            at: macosRoot.appendingPathComponent("PrismNative.xcodeproj/project.pbxproj")
        )
        let debugTargetSection = try sourceSection(
            projectSource,
            from: "A90000000000000000000003 /* Debug */",
            through: "A90000000000000000000004 /* Release */"
        )
        let releaseTargetSection = try sourceSection(
            projectSource,
            from: "A90000000000000000000004 /* Release */",
            through: "A90000000000000000000005 /* Debug */"
        )

        XCTAssertTrue(debugTargetSection.contains("INFOPLIST_FILE = \"PrismNative/Resources/Info.plist\";"))
        XCTAssertTrue(debugTargetSection.contains("CODE_SIGN_ENTITLEMENTS = \"PrismNative/Resources/PrismNative.entitlements\";"))
        XCTAssertTrue(debugTargetSection.contains("ENABLE_HARDENED_RUNTIME = YES;"))
        XCTAssertTrue(releaseTargetSection.contains("INFOPLIST_FILE = \"PrismNative/Resources/Info.plist\";"))
        XCTAssertTrue(releaseTargetSection.contains("CODE_SIGN_ENTITLEMENTS = \"PrismNative/Resources/PrismNative.entitlements\";"))
        XCTAssertTrue(releaseTargetSection.contains("ENABLE_HARDENED_RUNTIME = YES;"))

        for nativeTargetSection in [debugTargetSection, releaseTargetSection] {
            XCTAssertTrue(nativeTargetSection.contains("MARKETING_VERSION = 12.0.0;"))
            XCTAssertTrue(nativeTargetSection.contains("CURRENT_PROJECT_VERSION = 12.0.0;"))
            XCTAssertFalse(nativeTargetSection.contains("GENERATE_INFOPLIST_FILE = YES;"))
            XCTAssertFalse(nativeTargetSection.contains("ASSETCATALOG_COMPILER_APPICON_NAME"))
        }

        let infoURL = macosRoot.appendingPathComponent("PrismNative/Resources/Info.plist")
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: infoURL),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "$(PRODUCT_BUNDLE_IDENTIFIER)")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "$(PRODUCT_NAME)")
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "$(MARKETING_VERSION)")
        XCTAssertEqual(info["CFBundleVersion"] as? String, "$(CURRENT_PROJECT_VERSION)")
        XCTAssertEqual(info["CFBundleIconFile"] as? String, "Prism.icns")
        XCTAssertEqual(info["SUFeedURL"] as? String, "https://prismlauncher.org/feed/appcast.xml")
        XCTAssertEqual(
            info["SUPublicEDKey"] as? String,
            "v55ZWWD6QlPoXGV6VLzOTZxZUggWeE51X8cRQyQh6vA="
        )

        let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let documentExtensions = try XCTUnwrap(documentTypes.first?["CFBundleTypeExtensions"] as? [String])
        XCTAssertEqual(documentExtensions, ["zip", "mrpack"])

        let urlTypes = try XCTUnwrap(info["CFBundleURLTypes"] as? [[String: Any]])
        let urlSchemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertEqual(Set(urlSchemes), Set(["curseforge", "prismlauncher"]))

        let entitlementsURL = macosRoot.appendingPathComponent(
            "PrismNative/Resources/PrismNative.entitlements"
        )
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: entitlementsURL),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        XCTAssertEqual(
            Set(entitlements.keys),
            Set([
                "com.apple.security.cs.disable-library-validation",
                "com.apple.security.device.audio-input",
                "com.apple.security.device.camera",
            ])
        )
        XCTAssertEqual(entitlements["com.apple.security.cs.disable-library-validation"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.device.audio-input"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.device.camera"] as? Bool, true)

        let cmakeSource = try readSource(
            at: macosRoot.deletingLastPathComponent().appendingPathComponent("CMakeLists.txt")
        )
        XCTAssertTrue(cmakeSource.contains("set(Launcher_VERSION_MAJOR 12)"))
        XCTAssertTrue(cmakeSource.contains("set(Launcher_VERSION_MINOR 0)"))
        XCTAssertTrue(cmakeSource.contains("set(Launcher_VERSION_PATCH 0)"))

        let iconURL = macosRoot.appendingPathComponent("PrismNative/Resources/Prism.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))
        XCTAssertGreaterThan(try Data(contentsOf: iconURL).count, 0)

        let nativeBundle = try XCTUnwrap(builtNativeBundle())
        XCTAssertEqual(nativeBundle.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String, "com.lloydME.Prism")
        XCTAssertEqual(nativeBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, "12.0.0")
        XCTAssertEqual(nativeBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String, "12.0.0")
        XCTAssertEqual(nativeBundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String, "Prism.icns")
        XCTAssertEqual(
            nativeBundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            "https://prismlauncher.org/feed/appcast.xml"
        )
        XCTAssertNotNil(nativeBundle.path(forResource: "Prism", ofType: "icns"))
    }

    func testNativeBuildOwnsQtStartupOrderingAndAClosedRuntimeBundle() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repositoryRoot = macosRoot.deletingLastPathComponent()
        let projectSource = try readSource(
            at: macosRoot.appendingPathComponent("PrismNative.xcodeproj/project.pbxproj")
        )
        let bridgeSource = try readSource(
            at: macosRoot.appendingPathComponent("PrismNative/Bridge/PrismBridge.mm")
        )
        let acquisitionSource = try readSource(
            at: repositoryRoot.appendingPathComponent("launcher/frontend/ProductionInstanceAcquisitionRuntime.cpp")
        )
        let providerSource = try readSource(
            at: repositoryRoot.appendingPathComponent("launcher/frontend/ProductionProviderRuntime.cpp")
        )
        let deployURL = macosRoot.appendingPathComponent("scripts/deploy-qt-runtime.sh")
        let verifyURL = macosRoot.appendingPathComponent("scripts/verify-qt-runtime.sh")
        let deploySource = try readSource(at: deployURL)

        XCTAssertTrue(projectSource.contains("Deploy Qt Runtime"))
        XCTAssertTrue(projectSource.contains("scripts/deploy-qt-runtime.sh"))
        XCTAssertTrue(projectSource.contains("@executable_path/../Frameworks"))
        XCTAssertTrue(projectSource.contains("ENABLE_HARDENED_RUNTIME = YES;"))
        XCTAssertTrue(projectSource.contains("PrismNative/Resources/PrismNative.entitlements"))
        XCTAssertFalse(projectSource.contains("PrismNativeDebug.entitlements"))
        XCTAssertTrue(deploySource.contains("macdeployqt"))
        XCTAssertTrue(deploySource.contains("-no-codesign"))
        XCTAssertTrue(deploySource.contains("CODE_SIGNING_ALLOWED"))
        XCTAssertTrue(deploySource.contains("signing_identity=\"${EXPANDED_CODE_SIGN_IDENTITY:--}\""))
        XCTAssertTrue(deploySource.contains("\"-codesign=${signing_identity}\""))
        XCTAssertFalse(deploySource.contains("/usr/bin/codesign"))

        XCTAssertTrue(bridgeSource.contains("[NSThread isMainThread]"))
        XCTAssertTrue(bridgeSource.contains("new QCoreApplication"))
        XCTAssertTrue(bridgeSource.contains("QtCore is process-scoped"))
        XCTAssertFalse(acquisitionSource.contains("make_unique<QCoreApplication>"))
        XCTAssertFalse(providerSource.contains("make_unique<QCoreApplication>"))

        let nativeBundle = try XCTUnwrap(builtNativeBundle())
        let verification = Process()
        verification.executableURL = verifyURL
        verification.arguments = [nativeBundle.bundleURL.path]
        let output = Pipe()
        verification.standardOutput = output
        verification.standardError = output
        try verification.run()
        verification.waitUntilExit()
        let diagnostic = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(verification.terminationStatus, 0, diagnostic)
    }

    func testQtRuntimeDeploymentPropagatesXcodeAdHocSigningWithoutLaunchingApp() throws {
        let macosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let deployURL = macosRoot.appendingPathComponent("scripts/deploy-qt-runtime.sh")
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrismNativeQtDeployment-\(UUID().uuidString)", isDirectory: true)
        let buildDirectory = fixtureRoot.appendingPathComponent("Build", isDirectory: true)
        let applicationURL = buildDirectory.appendingPathComponent("Prism.app", isDirectory: true)
        let executableDirectory = applicationURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("Source/macos", isDirectory: true)
        let backendBuildRoot = fixtureRoot.appendingPathComponent("Source/build-native", isDirectory: true)
        let backendExecutableDirectory = backendBuildRoot.appendingPathComponent("Debug", isDirectory: true)
        let backendJarDirectory = backendBuildRoot.appendingPathComponent("jars", isDirectory: true)
        let fakeDeployURL = fixtureRoot.appendingPathComponent("fake-macdeployqt.sh")
        let fakeCMakeURL = fixtureRoot.appendingPathComponent("fake-cmake.sh")
        let argumentLogURL = fixtureRoot.appendingPathComponent("arguments.txt")
        let cmakeArgumentLogURL = fixtureRoot.appendingPathComponent("cmake-arguments.txt")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backendExecutableDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backendJarDirectory, withIntermediateDirectories: true)
        try "".write(
            to: executableDirectory.appendingPathComponent("Prism"),
            atomically: true,
            encoding: .utf8
        )
        try "backend".write(
            to: backendExecutableDirectory.appendingPathComponent("prism_backend"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: backendExecutableDirectory.appendingPathComponent("prism_backend").path
        )
        try "jar".write(
            to: backendJarDirectory.appendingPathComponent("NewLaunch.jar"),
            atomically: true,
            encoding: .utf8
        )
        let fakeDeploySource = """
        #!/bin/sh
        set -eu
        printf '%s\\n' "$@" > "${PRISM_ARGUMENT_LOG:?}"
        mkdir -p "$1/Contents/Frameworks/QtCore.framework/Versions/A"
        mkdir -p "$1/Contents/Frameworks/QtNetwork.framework/Versions/A"
        : > "$1/Contents/Frameworks/QtCore.framework/Versions/A/QtCore"
        : > "$1/Contents/Frameworks/QtNetwork.framework/Versions/A/QtNetwork"
        """
        try fakeDeploySource.write(to: fakeDeployURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeDeployURL.path)
        let fakeCMakeSource = """
        #!/bin/sh
        set -eu
        printf '%s\\n' "$@" > "${PRISM_CMAKE_ARGUMENT_LOG:?}"
        """
        try fakeCMakeSource.write(to: fakeCMakeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCMakeURL.path)
        try "CMAKE_COMMAND:INTERNAL=\(fakeCMakeURL.path)\n".write(
            to: backendBuildRoot.appendingPathComponent("CMakeCache.txt"),
            atomically: true,
            encoding: .utf8
        )

        func runDeployment(codeSigningAllowed: String) throws -> [String] {
            let process = Process()
            process.executableURL = deployURL
            process.environment = [
                // Match the restricted PATH used by Xcode launched from Finder.
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "SRCROOT": sourceRoot.path,
                "CONFIGURATION": "Debug",
                "TARGET_BUILD_DIR": buildDirectory.path,
                "WRAPPER_NAME": "Prism.app",
                "PLATFORM_NAME": "macosx",
                "PRISM_MACDEPLOYQT": fakeDeployURL.path,
                "PRISM_ARGUMENT_LOG": argumentLogURL.path,
                "PRISM_CMAKE_ARGUMENT_LOG": cmakeArgumentLogURL.path,
                "CODE_SIGNING_ALLOWED": codeSigningAllowed,
                "EXPANDED_CODE_SIGN_IDENTITY": "-",
            ]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            let diagnostic = String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            XCTAssertEqual(process.terminationStatus, 0, diagnostic)
            return try String(contentsOf: argumentLogURL, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
        }

        let signedArguments = try runDeployment(codeSigningAllowed: "YES")
        XCTAssertTrue(signedArguments.contains("-codesign=-"))
        XCTAssertFalse(signedArguments.contains("-no-codesign"))
        let cmakeArguments = try String(contentsOf: cmakeArgumentLogURL, encoding: .utf8)
        XCTAssertTrue(cmakeArguments.contains("--build\n\(sourceRoot.path)/../build-native"))
        XCTAssertTrue(cmakeArguments.contains("--target\nPrismBackend\nNewLaunch\nNewLaunchLegacy\nJavaCheck"))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: applicationURL.appendingPathComponent("Contents/Resources/jars/NewLaunch.jar").path
            )
        )

        let unsignedArguments = try runDeployment(codeSigningAllowed: "NO")
        XCTAssertTrue(unsignedArguments.contains("-no-codesign"))
        XCTAssertFalse(unsignedArguments.contains("-codesign=-"))
    }

    func testInstanceSummaryDTOCopiesFixtureValuesAndNormalizesOptionalMetadata() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let fixtureDirectory = try fixtureRoot.makeDirectory(relativePath: "instances/fixture-instance")
        let fixtureMarker = try fixtureRoot.makeFile(relativePath: "instances/fixture-instance/metadata.json", contents: "{}")
        let mutableIdentifier = NSMutableString(string: fixtureDirectory.lastPathComponent)
        let mutableName = NSMutableString(string: "Fixture Instance")
        let mutableIconKey = NSMutableString(string: "icon.fixture")
        let mutableGroupID = NSMutableString(string: "group.fixture")

        let summary = try XCTUnwrap(
            PRInstanceSummary(
                identifier: mutableIdentifier as String,
                name: mutableName as String,
                iconKey: mutableIconKey as String,
                groupID: mutableGroupID as String
            )
        )

        mutableIdentifier.append(".mutated")
        mutableName.append(" Mutated")
        mutableIconKey.append(".mutated")
        mutableGroupID.append(".mutated")

        XCTAssertEqual(summary.identifier, "fixture-instance")
        XCTAssertEqual(summary.name, "Fixture Instance")
        XCTAssertEqual(summary.iconKey, "icon.fixture")
        XCTAssertEqual(summary.groupID, "group.fixture")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureMarker.path))

        let normalizedSummary = try XCTUnwrap(
            PRInstanceSummary(identifier: "fixture-instance", name: "Fixture Instance", iconKey: "", groupID: "")
        )
        XCTAssertNil(normalizedSummary.iconKey)
        XCTAssertNil(normalizedSummary.groupID)
        XCTAssertNil(PRInstanceSummary(identifier: "", name: "Fixture Instance", iconKey: nil, groupID: nil))
        XCTAssertNil(PRInstanceSummary(identifier: "fixture-instance", name: "", iconKey: nil, groupID: nil))
    }

    func testTaskStatusDTOValidatesProgressAndCancellationMetadata() throws {
        let running = try XCTUnwrap(
            PRTaskStatus(
                identifier: "task.fixture",
                state: .running,
                progressKind: .determinate,
                progressFraction: 0.5,
                cancellationAllowed: true
            )
        )
        XCTAssertEqual(running.identifier, "task.fixture")
        XCTAssertEqual(running.state, .running)
        XCTAssertEqual(running.progressKind, .determinate)
        XCTAssertEqual(running.progressFraction, 0.5)
        XCTAssertTrue(running.cancellationAllowed)

        let waiting = try XCTUnwrap(
            PRTaskStatus(
                identifier: "task.fixture.waiting",
                state: .cancelling,
                progressKind: .indeterminate,
                progressFraction: 0,
                cancellationAllowed: false
            )
        )
        XCTAssertEqual(waiting.state, .cancelling)
        XCTAssertEqual(waiting.progressKind, .indeterminate)
        XCTAssertEqual(waiting.progressFraction, 0)
        XCTAssertFalse(waiting.cancellationAllowed)

        XCTAssertNil(
            PRTaskStatus(
                identifier: "",
                state: .queued,
                progressKind: .none,
                progressFraction: 0,
                cancellationAllowed: false
            )
        )
        XCTAssertNil(
            PRTaskStatus(
                identifier: "task.fixture",
                state: PRTaskState(rawValue: 99)!,
                progressKind: .none,
                progressFraction: 0,
                cancellationAllowed: false
            )
        )
        XCTAssertNil(
            PRTaskStatus(
                identifier: "task.fixture",
                state: .running,
                progressKind: PRTaskProgressKind(rawValue: 99)!,
                progressFraction: 0,
                cancellationAllowed: false
            )
        )
        XCTAssertNil(
            PRTaskStatus(
                identifier: "task.fixture",
                state: .running,
                progressKind: .determinate,
                progressFraction: 1.1,
                cancellationAllowed: true
            )
        )
        XCTAssertNil(
            PRTaskStatus(
                identifier: "task.fixture",
                state: .running,
                progressKind: .determinate,
                progressFraction: -0.1,
                cancellationAllowed: true
            )
        )
        XCTAssertNil(
            PRTaskStatus(
                identifier: "task.fixture",
                state: .running,
                progressKind: .indeterminate,
                progressFraction: 0.25,
                cancellationAllowed: true
            )
        )
    }

    func testTaskDTOsCopySubtasksTerminalResultsAndCancellationOutcomes() throws {
        let mutableSubtaskIdentifier = NSMutableString(string: "subtask.fixture")
        let mutableSubtaskName = NSMutableString(string: "Download fixture")
        let subtask = try XCTUnwrap(
            PRTaskSubtaskStatus(
                identifier: mutableSubtaskIdentifier as String,
                name: mutableSubtaskName as String,
                state: .succeeded,
                progressKind: .determinate,
                progressFraction: 1
            )
        )

        let mutableLocalizationKey = NSMutableString(string: "task.failed")
        let terminalResult = try XCTUnwrap(
            PRTaskTerminalResult(
                outcome: .failed,
                localizationKey: mutableLocalizationKey as String,
                substitutionValues: ["taskIdentifier": "task.fixture"],
                diagnosticText: "fixture failure",
                partialChangesRolledBack: true
            )
        )
        mutableSubtaskIdentifier.append(".mutated")
        mutableSubtaskName.append(" Mutated")
        mutableLocalizationKey.append(".mutated")

        XCTAssertEqual(subtask.identifier, "subtask.fixture")
        XCTAssertEqual(subtask.name, "Download fixture")
        XCTAssertEqual(terminalResult.localizationKey, "task.failed")
        XCTAssertEqual(terminalResult.substitutionValues, ["taskIdentifier": "task.fixture"])
        XCTAssertEqual(terminalResult.diagnosticText, "fixture failure")
        XCTAssertTrue(terminalResult.partialChangesRolledBack)

        let failedStatus = try XCTUnwrap(
            PRTaskStatus(
                identifier: "task.fixture",
                title: "Fixture Task",
                state: .failed,
                progressKind: .determinate,
                progressFraction: 1,
                cancellationAllowed: false,
                subtasks: [subtask],
                terminalResult: terminalResult
            )
        )
        XCTAssertEqual(failedStatus.title, "Fixture Task")
        XCTAssertEqual(failedStatus.subtasks.map(\.identifier), ["subtask.fixture"])
        XCTAssertEqual(failedStatus.terminalResult?.outcome, .failed)

        let succeededResult = try XCTUnwrap(
            PRTaskTerminalResult(
                outcome: .succeeded,
                localizationKey: "task.completed",
                substitutionValues: [:],
                diagnosticText: nil,
                partialChangesRolledBack: false
            )
        )
        let cancelledResult = try XCTUnwrap(
            PRTaskTerminalResult(
                outcome: .cancelled,
                localizationKey: "task.cancelled",
                substitutionValues: [:],
                diagnosticText: nil,
                partialChangesRolledBack: false
            )
        )
        XCTAssertNotNil(
            PRTaskStatus(
                identifier: "task.succeeded",
                title: nil,
                state: .succeeded,
                progressKind: .determinate,
                progressFraction: 1,
                cancellationAllowed: false,
                subtasks: [],
                terminalResult: succeededResult
            )
        )
        XCTAssertNotNil(
            PRTaskStatus(
                identifier: "task.cancelled",
                title: nil,
                state: .cancelled,
                progressKind: .indeterminate,
                progressFraction: 0,
                cancellationAllowed: false,
                subtasks: [],
                terminalResult: cancelledResult
            )
        )

        XCTAssertEqual(
            PRTaskCancellationResult(identifier: "task.fixture", outcome: .requested)?.outcome,
            .requested
        )
        XCTAssertEqual(
            PRTaskCancellationResult(identifier: "task.fixture", outcome: .alreadyTerminal)?.outcome,
            .alreadyTerminal
        )
        XCTAssertEqual(
            PRTaskCancellationResult(identifier: "task.fixture", outcome: .unknownTask)?.outcome,
            .unknownTask
        )
        XCTAssertEqual(
            PRTaskCancellationResult(identifier: "task.fixture", outcome: .rejected)?.outcome,
            .rejected
        )

        XCTAssertNil(
            PRTaskSubtaskStatus(
                identifier: "",
                name: "Download fixture",
                state: .running,
                progressKind: .indeterminate,
                progressFraction: 0
            )
        )
        XCTAssertNil(
            PRTaskTerminalResult(
                outcome: .failed,
                localizationKey: "",
                substitutionValues: [:],
                diagnosticText: nil,
                partialChangesRolledBack: false
            )
        )
        XCTAssertNil(
            PRTaskStatus(
                identifier: "task.running-with-result",
                title: nil,
                state: .running,
                progressKind: .determinate,
                progressFraction: 0.5,
                cancellationAllowed: true,
                subtasks: [],
                terminalResult: terminalResult
            )
        )
        XCTAssertNil(
            PRTaskStatus(
                identifier: "task.failed-without-result",
                title: nil,
                state: .failed,
                progressKind: .determinate,
                progressFraction: 1,
                cancellationAllowed: false,
                subtasks: [],
                terminalResult: nil
            )
        )
        XCTAssertNil(
            PRTaskStatus(
                identifier: "task.duplicate-subtasks",
                title: nil,
                state: .running,
                progressKind: .determinate,
                progressFraction: 0.5,
                cancellationAllowed: true,
                subtasks: [subtask, subtask],
                terminalResult: nil
            )
        )
    }

    func testM7AccountBoundaryContainsOnlyNonSecretValueDeclarationsAndFixtures() throws {
        let repositoryRoot = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let facadeHeader = try readSource(
            at: repositoryRoot.appendingPathComponent("launcher/frontend/FrontendFacade.h")
        )
        let bridgeModelsHeader = try readSource(
            at: repositoryRoot.appendingPathComponent("macos/PrismNative/Bridge/PrismBridgeModels.h")
        )
        let accountSettingsSource = try readSource(
            at: repositoryRoot.appendingPathComponent("macos/PrismNative/App/PrismAccountSettings.swift")
        )
        let authenticationSource = try readSource(
            at: repositoryRoot.appendingPathComponent("macos/PrismNative/App/PrismAccountAuthentication.swift")
        )
        let identitySource = try readSource(
            at: repositoryRoot.appendingPathComponent("macos/PrismNative/App/PrismOfflineLaunchIdentity.swift")
        )

        let facadeAccountContracts = try sourceSection(
            facadeHeader,
            from: "struct FrontendAccountSnapshot",
            through: "enum class FrontendTaskState"
        )
        let bridgeAccountContracts = try sourceSection(
            bridgeModelsHeader,
            from: "@interface PRAccountSnapshot",
            through: "@interface PRTaskStatus"
        )
        let forbiddenValueTokens = [
            "accessToken", "access_token", "refreshToken", "refresh_token",
            "authorizationCode", "authorization_code", "clientSecret", "client_secret",
            "bearerToken", "bearer_token", "userCode", "user_code", "deviceCode", "device_code",
            "sessionToken", "session_token", "profilePayload", "keychainItem", "password", "secret"
        ]
        let declarationSources = [
            valueDeclarationLines(in: facadeAccountContracts).joined(separator: "\n"),
            valueDeclarationLines(in: bridgeAccountContracts).joined(separator: "\n"),
            declarationLines(in: accountSettingsSource).joined(separator: "\n"),
            declarationLines(in: authenticationSource).joined(separator: "\n"),
            declarationLines(in: identitySource).joined(separator: "\n"),
        ]
        for source in declarationSources {
            for forbiddenValueToken in forbiddenValueTokens {
                XCTAssertFalse(
                    source.contains(forbiddenValueToken),
                    "Secret-bearing value declaration crossed the M7 account boundary: \(forbiddenValueToken)"
                )
            }
        }

        let facadeSource = try readSource(
            at: repositoryRoot.appendingPathComponent("launcher/frontend/FrontendFacade.cpp")
        )
        XCTAssertTrue(facadeSource.contains("privacyFilteredLogText"))
        XCTAssertTrue(facadeSource.contains("credentialPattern"))
        XCTAssertTrue(facadeSource.contains("<redacted>"))
        XCTAssertTrue(facadeSource.contains("<data-root>"))

        let cppContractTests = try readSource(
            at: repositoryRoot.appendingPathComponent("launcher/frontend/FrontendFacadeContractTest.cpp")
        )
        let cppAuthenticationFixture = try sourceSection(
            cppContractTests,
            from: "std::size_t authenticationCalls",
            through: "std::size_t offlineIdentityLoadCalls"
        )
        for forbiddenFixtureToken in [
            "Bearer ", "access_token", "refresh_token", "authorizationCode", "device_code",
            "login.microsoftonline.com", "login.live.com"
        ] {
            XCTAssertFalse(
                cppAuthenticationFixture.contains(forbiddenFixtureToken),
                "Authentication fixture contains forbidden secret/provider material: \(forbiddenFixtureToken)"
            )
        }
        XCTAssertTrue(cppAuthenticationFixture.contains("https://login.example.invalid/device"))

        let objcContractTests = try readSource(
            at: repositoryRoot.appendingPathComponent("macos/PrismNativeTests/PrismBridgeFacadeIntegrationTests.mm")
        )
        let objcAuthenticationFixture = try sourceSection(
            objcContractTests,
            from: "- (void)testFacadeAuthenticationProgressAndResultConvertSyntheticProviderOnMainActor",
            through: "- (void)testFacadeAuthenticationCancellationSuppressesQueuedProgressAndCompletion"
        )
        for forbiddenFixtureToken in [
            "Bearer ", "access_token", "refresh_token", "authorizationCode", "device_code",
            "login.microsoftonline.com", "login.live.com"
        ] {
            XCTAssertFalse(
                objcAuthenticationFixture.contains(forbiddenFixtureToken),
                "Objective-C++ authentication fixture contains forbidden secret/provider material: \(forbiddenFixtureToken)"
            )
        }
        XCTAssertTrue(objcAuthenticationFixture.contains("https://login.example.invalid/device"))

        let cppLogFixture = try sourceSection(
            cppContractTests,
            from: "text = \"Authorization: Bearer fixture-secret",
            through: "const bool longLogIsTruncated"
        )
        XCTAssertTrue(cppLogFixture.contains("fixture-secret"))
        XCTAssertTrue(cppLogFixture.contains("fixture-token"))
        XCTAssertTrue(cppLogFixture.contains("<redacted>"))
        XCTAssertTrue(
            cppLogFixture.contains("find(\"fixture-token\") == std::string::npos")
        )

        let progressLedger = try readSource(
            at: repositoryRoot.appendingPathComponent("docs/macos-native-migration/PROGRESS.md")
        )
        let concreteCredentialPatterns = [
            "(?i)\\bBearer\\s+[A-Za-z0-9._~+/=-]{12,}\\b",
            "(?i)\\b(?:access|refresh)[_-]?token\\s*[:=]\\s*(?!<redacted>|fixture[-_])[A-Za-z0-9._~+/=-]{8,}",
            "(?i)\\b(?:client[_-]?secret|password)\\s*[:=]\\s*(?!<redacted>|fixture[-_])[A-Za-z0-9._~+/=-]{8,}",
            "\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b",
        ]
        for pattern in concreteCredentialPatterns {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(progressLedger.startIndex..<progressLedger.endIndex, in: progressLedger)
            XCTAssertNil(
                regex.firstMatch(in: progressLedger, range: range),
                "Progress ledger contains a concrete credential-shaped value for pattern \(pattern)"
            )
        }
    }

    private func readSource(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func builtNativeBundle() -> Bundle? {
        let productsDirectory = Bundle(for: PrismNativeInfrastructureTests.self)
            .bundleURL
            .deletingLastPathComponent()
        let appURL = productsDirectory.appendingPathComponent("Prism.app", isDirectory: true)
        return Bundle(url: appURL)
    }

    private func sourceSection(_ source: String, from startMarker: String, through endMarker: String) throws -> String {
        guard let startRange = source.range(of: startMarker),
              let endRange = source.range(of: endMarker, range: startRange.upperBound..<source.endIndex) else {
            throw NSError(
                domain: "PrismNativeInfrastructureTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing source audit marker \(startMarker) -> \(endMarker)"]
            )
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private func declarationLines(in source: String) -> [String] {
        source.split(whereSeparator: \.isNewline).map(String.init).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("@Published")
                || trimmed.hasPrefix("private let ")
                || trimmed.hasPrefix("private var ")
                || trimmed.hasPrefix("let ")
                || trimmed.hasPrefix("var ")
        }
    }

    private func valueDeclarationLines(in source: String) -> [String] {
        source.split(whereSeparator: \.isNewline).map(String.init).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("@property")
                || trimmed.hasPrefix("std::string ")
                || trimmed.hasPrefix("std::optional<")
                || trimmed.hasPrefix("std::vector<")
                || trimmed.hasPrefix("std::int32_t ")
                || trimmed.hasPrefix("bool ")
        }
    }
}
