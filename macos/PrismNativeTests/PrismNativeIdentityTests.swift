import Foundation
import XCTest

final class PrismNativeIdentityTests: XCTestCase {
    func testBuiltNativeBundleUsesStableProductIdentity() throws {
        let nativeBundle = try XCTUnwrap(builtNativeBundle())

        XCTAssertEqual(nativeBundle.bundleIdentifier, PRApplicationIdentity.requiredBundleIdentifier())
        XCTAssertEqual(
            nativeBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            PRApplicationIdentity.applicationName()
        )
    }

    func testFixtureDataRootUsesPrismNamespaceAndNotUpstreamNamespace() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let applicationSupportBase = try fixtureRoot.makeDirectory(relativePath: "Library/Application Support")
        let identity = try XCTUnwrap(PRApplicationIdentity(
            bundleIdentifier: PRApplicationIdentity.requiredBundleIdentifier(),
            applicationSupportBaseDirectory: applicationSupportBase
        ))

        let nativeRoot = identity.applicationSupportDirectory.standardizedFileURL
        let libraryRoot = nativeRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let upstreamRoot = applicationSupportBase
            .appendingPathComponent("PrismLauncher", isDirectory: true)
            .standardizedFileURL

        XCTAssertEqual(identity.applicationName, "Prism")
        XCTAssertEqual(identity.bundleIdentifier, PRApplicationIdentity.requiredBundleIdentifier())
        XCTAssertEqual(canonicalComparablePath(identity.applicationSupportDirectory), canonicalComparablePath(nativeRoot))
        XCTAssertEqual(
            canonicalComparablePath(identity.cacheDirectory),
            canonicalComparablePath(libraryRoot.appendingPathComponent("Caches/com.lloydME.Prism", isDirectory: true))
        )
        XCTAssertEqual(
            canonicalComparablePath(identity.logsDirectory),
            canonicalComparablePath(libraryRoot.appendingPathComponent("Logs/com.lloydME.Prism", isDirectory: true))
        )
        XCTAssertEqual(
            canonicalComparablePath(identity.savedApplicationStateDirectory),
            canonicalComparablePath(
                libraryRoot.appendingPathComponent("Saved Application State/com.lloydME.Prism", isDirectory: true)
            )
        )
        XCTAssertEqual(identity.preferencesSuiteName, "com.lloydME.Prism")
        XCTAssertEqual(identity.keychainServicePrefix, "com.lloydME.Prism")
        XCTAssertNotEqual(nativeRoot, upstreamRoot)
        XCTAssertFalse(nativeRoot.path.hasSuffix("/PrismLauncher"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nativeRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureRoot.url.path))
    }

    func testProductionBridgeReceivesOnlyTheBundleScopedRoot() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let applicationSupportBase = try fixtureRoot.makeDirectory(relativePath: "Library/Application Support")
        let identity = try XCTUnwrap(PRApplicationIdentity(
            bundleIdentifier: PRApplicationIdentity.requiredBundleIdentifier(),
            applicationSupportBaseDirectory: applicationSupportBase
        ))
        let bridge = try XCTUnwrap(
            PRPrismBridge(
                applicationIdentity: identity,
                cancellationHandler: nil,
                shutdownHandler: nil
            )
        )

        XCTAssertEqual(bridge.dataRootURL.standardizedFileURL, identity.applicationSupportDirectory.standardizedFileURL)
        XCTAssertTrue(bridge.shutdown())
    }

    func testIdentityRejectsWrongNamespaceAndUnsafeContainment() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let applicationSupportBase = try fixtureRoot.makeDirectory(relativePath: "Library/Application Support")
        let identity = try XCTUnwrap(PRApplicationIdentity(
            bundleIdentifier: PRApplicationIdentity.requiredBundleIdentifier(),
            applicationSupportBaseDirectory: applicationSupportBase
        ))

        XCTAssertNil(
            PRApplicationIdentity(
                bundleIdentifier: "org.prismlauncher.PrismLauncher",
                applicationSupportBaseDirectory: applicationSupportBase
            )
        )
        XCTAssertNil(
            PRApplicationIdentity(
                bundleIdentifier: PRApplicationIdentity.requiredBundleIdentifier(),
                applicationSupportBaseDirectory: URL(fileURLWithPath: applicationSupportBase.path + "/../Application Support")
            )
        )
        XCTAssertNil(
            PRApplicationIdentity(
                bundleIdentifier: PRApplicationIdentity.requiredBundleIdentifier(),
                applicationSupportBaseDirectory: applicationSupportBase.appendingPathComponent("Prism", isDirectory: true)
            )
        )
        XCTAssertNil(
            PRApplicationIdentity(
                bundleIdentifier: "com.lloydME.PrismLauncher",
                applicationSupportBaseDirectory: applicationSupportBase
            )
        )

        let nativeRoot = identity.applicationSupportDirectory
        XCTAssertTrue(identity.contains(nativeRoot))
        XCTAssertTrue(identity.contains(nativeRoot.appendingPathComponent("instances/fixture", isDirectory: true)))
        XCTAssertFalse(identity.contains(nativeRoot.appendingPathComponent("../PrismLauncher", isDirectory: true)))
        XCTAssertFalse(identity.contains(
            applicationSupportBase.appendingPathComponent("com.lloydME.Prism-other", isDirectory: true)
        ))
        XCTAssertFalse(identity.contains(URL(string: "https://example.invalid/outside")!))

        let outsideDirectory = try fixtureRoot.makeDirectory(relativePath: "outside")
        try FileManager.default.createDirectory(at: nativeRoot, withIntermediateDirectories: true)
        let symlinkURL = nativeRoot.appendingPathComponent("escape", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideDirectory)
        XCTAssertFalse(identity.contains(symlinkURL.appendingPathComponent("secret.json")))
    }

    func testProductionCompositionDoesNotUseDisplayNameOrUpstreamPersistence() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let appSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/PrismNativeApp.swift"),
            encoding: .utf8
        )
        let bridgeSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/Bridge/PrismBridge.mm"),
            encoding: .utf8
        )
        let appContentSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/ContentView.swift"),
            encoding: .utf8
        )
        let shellSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/PrismShellModel.swift"),
            encoding: .utf8
        )
        let commandSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/PrismCommandModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appSource.contains("PRApplicationIdentity()"))
        XCTAssertTrue(appSource.contains("applicationIdentity: identity"))
        XCTAssertTrue(appSource.contains("PrismCommandModel(bridge: runtime.bridge)"))
        XCTAssertTrue(appSource.contains("bridge: nativeRuntime.bridge"))
        XCTAssertFalse(appSource.contains("fixture.instance"))
        XCTAssertTrue(appContentSource.contains("PrismShellModel(bridge: bridge)"))
        XCTAssertTrue(shellSource.contains("observeInstanceChanges"))
        XCTAssertTrue(shellSource.contains("loadInstanceSummaries"))
        XCTAssertTrue(commandSource.contains("bridge.launchInstance"))
        XCTAssertTrue(commandSource.contains("bridge.stopInstance"))
        let forbiddenPersistenceTokens = [
            "PrismLauncher",
            "Application Support/Prism",
            "UserDefaults.standard",
            "UserDefaults(suiteName:",
            "ProcessInfo.processInfo.environment",
            "CommandLine.arguments",
            "QStandardPaths",
            "kSecAttrService",
            "SecItem",
        ]
        for token in forbiddenPersistenceTokens {
            XCTAssertFalse(appSource.contains(token), "App source unexpectedly contains \(token)")
            XCTAssertFalse(bridgeSource.contains(token), "Bridge source unexpectedly contains \(token)")
        }
        XCTAssertFalse(bridgeSource.contains("URLByAppendingPathComponent:kPrismApplicationName"))
        XCTAssertTrue(bridgeSource.contains("URLByAppendingPathComponent:kPrismBundleIdentifier"))
    }

    private func builtNativeBundle() -> Bundle? {
        let productsDirectory = Bundle(for: PrismNativeIdentityTests.self)
            .bundleURL
            .deletingLastPathComponent()
        let appURL = productsDirectory.appendingPathComponent("Prism.app", isDirectory: true)
        return Bundle(url: appURL)
    }

    private func canonicalComparablePath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
