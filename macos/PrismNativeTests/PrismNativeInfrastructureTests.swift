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
}
