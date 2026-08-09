import Foundation
import XCTest

@MainActor
final class PrismProviderInstallationTests: XCTestCase {
    private let fixtureArchiveURL = URL(fileURLWithPath: "/private/tmp/prism-native-m8-w5-fixture/custom-pack.fixture.zip")
    private let fixtureFTBDirectoryURL = URL(fileURLWithPath: "/private/tmp/prism-native-m8-w5-fixture/ftb-app.fixture", isDirectory: true)

    private func draft(for kind: PrismProviderInstallKind) -> PrismProviderInstallationDraft {
        PrismProviderInstallationDraft(
            kind: kind,
            packIdentifier: " pack.fixture ",
            versionIdentifier: " version.fixture ",
            sourceURL: kind == .customArchive
                ? fixtureArchiveURL
                : (kind == .ftbImport ? fixtureFTBDirectoryURL : nil),
            name: " Fixture Pack ",
            groupID: " fixture-group ",
            iconKey: " default "
        )
    }

    private func progressStatus(state: PRTaskState, terminalResult: PRTaskTerminalResult? = nil) throws -> PRTaskStatus {
        try XCTUnwrap(
            PRTaskStatus(
                identifier: "provider-install.fixture",
                title: "Installing Fixture Pack",
                state: state,
                progressKind: state == .queued ? .none : .determinate,
                progressFraction: state == .queued ? 0 : (state == .succeeded ? 1 : 0.5),
                cancellationAllowed: state == .queued || state == .running,
                subtasks: [],
                terminalResult: terminalResult
            )
        )
    }

    func testInstallationRequestCoversEveryProviderTaskFamilyAndCustomSourceBoundary() throws {
        XCTAssertEqual(PrismProviderInstallKind.allCases.count, 9)
        var receivedRequests: [PRProviderInstallRequest] = []

        for kind in PrismProviderInstallKind.allCases {
            let model = PrismProviderInstallationModel(
                initialDraft: draft(for: kind),
                onInstall: { request, _ in receivedRequests.append(request) }
            )

            XCTAssertTrue(model.canInstall, "Fixture draft should be valid for (kind.rawValue)")
            XCTAssertTrue(model.startInstall())
            let request = try XCTUnwrap(receivedRequests.last)
            XCTAssertEqual(request.kind, kind.bridgeValue)
            XCTAssertEqual(request.packIdentifier, "pack.fixture")
            XCTAssertEqual(request.versionIdentifier, "version.fixture")
            XCTAssertEqual(request.name, "Fixture Pack")
            XCTAssertEqual(request.groupID, "fixture-group")
            XCTAssertEqual(request.iconKey, "default")

            if kind == .customArchive {
                XCTAssertEqual(request.sourceURL?.standardizedFileURL, fixtureArchiveURL.standardizedFileURL)
            } else if kind == .ftbImport {
                XCTAssertEqual(request.sourceURL?.standardizedFileURL, fixtureFTBDirectoryURL.standardizedFileURL)
            } else {
                XCTAssertNil(request.sourceURL)
            }
            XCTAssertTrue(model.cancel())
        }

        XCTAssertEqual(receivedRequests.count, PrismProviderInstallKind.allCases.count)
    }

    func testInstallationStatesCoverProgressSuccessFailureRetryCancellationRollbackAndStaleResults() throws {
        var generations: [Int] = []
        var cancellationCount = 0
        let model = PrismProviderInstallationModel(
            initialDraft: draft(for: .modrinth),
            onInstall: { _, generation in generations.append(generation) },
            onCancel: { cancellationCount += 1 }
        )

        XCTAssertTrue(model.startInstall())
        let firstGeneration = try XCTUnwrap(generations.first)
        XCTAssertTrue(model.apply(progress: try progressStatus(state: .running), generation: firstGeneration))
        XCTAssertEqual(model.progress?.id, "provider-install.fixture")
        XCTAssertEqual(model.progress?.progress.fraction, 0.5)

        let instance = try XCTUnwrap(
            PRInstanceSummary(
                identifier: "instance.provider.fixture",
                name: "Fixture Provider Pack",
                iconKey: "default",
                groupID: "fixture-group"
            )
        )
        let success = try XCTUnwrap(
            PRProviderInstallResult(
                kind: .modrinth,
                packIdentifier: "pack.fixture",
                versionIdentifier: "version.fixture",
                instance: instance,
                outcome: .succeeded,
                rollbackOutcome: .notRequired,
                localizationKey: "providers.install.completed",
                diagnosticText: nil,
                retryable: false
            )
        )
        XCTAssertTrue(model.apply(result: success, generation: firstGeneration))
        XCTAssertEqual(model.installedInstance?.id, "instance.provider.fixture")
        XCTAssertFalse(model.isInstalling)

        model.reset()
        XCTAssertTrue(model.startInstall())
        let failureGeneration = try XCTUnwrap(generations.last)
        let failure = try XCTUnwrap(
            PRProviderInstallResult(
                kind: .modrinth,
                packIdentifier: "pack.fixture",
                versionIdentifier: "version.fixture",
                instance: nil,
                outcome: .failed,
                rollbackOutcome: .applied,
                localizationKey: "providers.install.failed",
                diagnosticText: "fixture provider task failed",
                retryable: true
            )
        )
        XCTAssertTrue(model.apply(result: failure, generation: failureGeneration))
        XCTAssertEqual(model.failure?.rollbackOutcome, .applied)
        XCTAssertEqual(model.failure?.diagnosticText, "fixture provider task failed")
        XCTAssertTrue(model.retry())
        XCTAssertEqual(generations.count, 3)

        let retryGeneration = try XCTUnwrap(generations.last)
        XCTAssertTrue(model.cancel())
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertFalse(model.isInstalling)
        XCTAssertFalse(model.apply(result: failure, generation: retryGeneration))
        XCTAssertFalse(model.apply(progress: try progressStatus(state: .running), generation: retryGeneration))

        model.reset()
        XCTAssertTrue(model.startInstall())
        let currentGeneration = try XCTUnwrap(generations.last)
        XCTAssertNotEqual(currentGeneration, firstGeneration)
        XCTAssertFalse(model.apply(result: failure, generation: firstGeneration))
        XCTAssertTrue(model.isInstalling)
    }

    func testInstallationSurfaceUsesSystemControlsLocalizationKeysAndKeepsBoundaryClean() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("PrismNative/App/PrismProviderInstallation.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for requiredToken in [
            "PrismProviderInstallationModel",
            "Form {",
            "Section(\"Pack\")",
            "Picker(",
            "TextField(",
            "Button(\"Choose Archive",
            "ProgressView(",
            "ContentUnavailableView",
            ".keyboardShortcut(.defaultAction)",
            ".keyboardShortcut(.cancelAction)",
            ".fileImporter(",
            ".accessibilityIdentifier(\"provider-install.",
            "providers.install."
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native provider installation API: \(requiredToken)")
        }

        for forbiddenToken in [
            "Canvas(",
            "draw(",
            "Path(",
            "CGContext",
            "NSBezierPath",
            "QWidget",
            "QDialog",
            "Qt",
            "C++",
            "URLSession",
            "FileManager",
            "Process(",
            "Application Support",
            "PrismLauncher",
            "accessToken"
        ] {
            XCTAssertFalse(source.contains(forbiddenToken), "Forbidden provider installation token: \(forbiddenToken)")
        }
    }
}
