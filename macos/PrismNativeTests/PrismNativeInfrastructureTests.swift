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
}
