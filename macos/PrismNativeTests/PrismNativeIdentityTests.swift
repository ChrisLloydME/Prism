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
        let identity = PRApplicationIdentity(
            bundleIdentifier: PRApplicationIdentity.requiredBundleIdentifier(),
            applicationSupportBaseDirectory: fixtureRoot.url
        )

        let nativeRoot = fixtureRoot.url
            .appendingPathComponent(PRApplicationIdentity.applicationName(), isDirectory: true)
            .standardizedFileURL
        let upstreamRoot = fixtureRoot.url
            .appendingPathComponent("PrismLauncher", isDirectory: true)
            .standardizedFileURL

        XCTAssertEqual(identity.applicationName, "Prism")
        XCTAssertEqual(identity.applicationSupportDirectory.standardizedFileURL, nativeRoot)
        XCTAssertNotEqual(nativeRoot, upstreamRoot)
        XCTAssertFalse(nativeRoot.path.hasSuffix("/PrismLauncher"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nativeRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureRoot.url.path))
    }

    private func builtNativeBundle() -> Bundle? {
        let productsDirectory = Bundle(for: PrismNativeIdentityTests.self)
            .bundleURL
            .deletingLastPathComponent()
        let appURL = productsDirectory.appendingPathComponent("Prism.app", isDirectory: true)
        return Bundle(url: appURL)
    }
}
