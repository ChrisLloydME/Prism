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
}
