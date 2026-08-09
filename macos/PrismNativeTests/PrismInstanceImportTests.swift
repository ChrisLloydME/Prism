import Foundation
import XCTest

@MainActor
final class PrismInstanceImportTests: XCTestCase {
    func testLocalDraftValidationNormalizesAndBuildsFoundationRequest() throws {
        let sourceURL = URL(fileURLWithPath: "/private/tmp/fixture-import/pack.zip")
        let model = PrismInstanceImportModel(
            initialDraft: PrismInstanceImportDraft(
                source: .localFile,
                localFileURL: sourceURL,
                remoteURLText: "",
                name: " Imported Fixture ",
                groupID: " fixture-imports ",
                iconKey: " default "
            )
        )

        let request = try XCTUnwrap(model.makeBridgeRequest())
        XCTAssertEqual(request.sourceURL.path, sourceURL.path)
        XCTAssertEqual(request.sourceKind, .localFile)
        XCTAssertEqual(request.name, "Imported Fixture")
        XCTAssertEqual(request.groupID, "fixture-imports")
        XCTAssertEqual(request.iconKey, "default")

        model.setLocalFileURL(nil)
        XCTAssertFalse(model.canImport)
        XCTAssertNil(model.makeBridgeRequest())
    }

    func testOpenPanelTicketPreservesCancellationAndRejectsStaleSelection() throws {
        let originalURL = URL(fileURLWithPath: "/private/tmp/fixture-import/original.zip")
        let replacementURL = URL(fileURLWithPath: "/private/tmp/fixture-import/replacement.zip")
        let model = PrismInstanceImportModel(
            initialDraft: PrismInstanceImportDraft(
                source: .localFile,
                localFileURL: originalURL,
                remoteURLText: "",
                name: "Imported Fixture",
                groupID: "",
                iconKey: "default"
            )
        )

        let cancelledToken = try XCTUnwrap(model.beginLocalFilePanel())
        XCTAssertTrue(model.applyLocalFilePanelResult(nil, token: cancelledToken))
        XCTAssertEqual(model.draft.localFileURL, originalURL.standardizedFileURL)

        let staleToken = try XCTUnwrap(model.beginLocalFilePanel())
        model.setSource(.remoteURL)
        XCTAssertFalse(model.applyLocalFilePanelResult(replacementURL, token: staleToken))
        XCTAssertEqual(model.draft.localFileURL, originalURL.standardizedFileURL)
    }

    func testRemoteURLValidationAndSourceSwitch() throws {
        let model = PrismInstanceImportModel(
            initialDraft: PrismInstanceImportDraft(
                source: .remoteURL,
                localFileURL: nil,
                remoteURLText: " https://downloads.example.invalid/pack.zip ",
                name: "Imported Fixture",
                groupID: "",
                iconKey: "default"
            )
        )

        let request = try XCTUnwrap(model.makeBridgeRequest())
        XCTAssertEqual(request.sourceKind, .remoteURL)
        XCTAssertEqual(request.sourceURL.absoluteString, "https://downloads.example.invalid/pack.zip")
        XCTAssertTrue(model.canImport)

        model.draft.remoteURLText = "ftp://downloads.example.invalid/pack.zip"
        XCTAssertFalse(model.canImport)
        model.setSource(.localFile)
        XCTAssertFalse(model.canImport)
    }

    func testImportForwardsRequestAndProgressToActiveGeneration() throws {
        var receivedRequest: PRInstanceImportRequest?
        var receivedGeneration: Int?
        let sourceURL = URL(fileURLWithPath: "/private/tmp/fixture-import/pack.zip")
        let model = PrismInstanceImportModel(
            initialDraft: PrismInstanceImportDraft(
                source: .localFile,
                localFileURL: sourceURL,
                remoteURLText: "",
                name: "Imported Fixture",
                groupID: "fixture-imports",
                iconKey: "default"
            ),
            onImport: { request, generation in
                receivedRequest = request
                receivedGeneration = generation
            }
        )

        XCTAssertTrue(model.startImport())
        XCTAssertTrue(model.isImporting)
        XCTAssertFalse(model.startImport())
        XCTAssertEqual(receivedRequest?.sourceURL.path, sourceURL.path)
        XCTAssertEqual(receivedRequest?.sourceKind, .localFile)
        XCTAssertEqual(receivedGeneration, 1)

        let progress = try XCTUnwrap(
            PRTaskStatus(
                identifier: "task.instance.import",
                title: "Importing Fixture",
                state: .running,
                progressKind: .determinate,
                progressFraction: 0.5,
                cancellationAllowed: true,
                subtasks: [],
                terminalResult: nil
            )
        )
        XCTAssertTrue(model.apply(progress: progress, generation: receivedGeneration))
        XCTAssertEqual(model.progress?.id, "task.instance.import")
        XCTAssertEqual(model.progress?.progress.fraction, 0.5)

        let summary = try XCTUnwrap(
            PRInstanceSummary(
                identifier: "fixture.imported",
                name: "Imported Fixture",
                iconKey: "default",
                groupID: "fixture-imports"
            )
        )
        let result = try XCTUnwrap(
            PRInstanceImportResult(
                instance: summary,
                outcome: .succeeded,
                localizationKey: "instances.import.completed",
                diagnosticText: nil,
                retryable: false,
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(model.apply(result: result, generation: receivedGeneration))
        XCTAssertEqual(model.importedInstance?.id, "fixture.imported")
        XCTAssertEqual(model.importedInstance?.name, "Imported Fixture")
        XCTAssertEqual(model.importedInstance?.group, "fixture-imports")
        XCTAssertFalse(model.isImporting)
    }

    func testFailureRetryCancellationAndStaleGenerationAreSafe() throws {
        var generations: [Int] = []
        var cancellationCount = 0
        let model = PrismInstanceImportModel(
            initialDraft: PrismInstanceImportDraft(
                source: .remoteURL,
                localFileURL: nil,
                remoteURLText: "https://downloads.example.invalid/pack.zip",
                name: "Imported Fixture",
                groupID: "",
                iconKey: "default"
            ),
            onImport: { _, generation in generations.append(generation) },
            onCancel: { cancellationCount += 1 }
        )

        XCTAssertTrue(model.startImport())
        let firstGeneration = try XCTUnwrap(generations.first)
        let failure = try XCTUnwrap(
            PRInstanceImportResult(
                instance: nil,
                outcome: .failed,
                localizationKey: "instances.import.failed",
                diagnosticText: "fixture import failed",
                retryable: true,
                partialChangesRolledBack: true
            )
        )
        XCTAssertTrue(model.apply(result: failure, generation: firstGeneration))
        XCTAssertEqual(model.failure?.localizationKey, "instances.import.failed")
        XCTAssertTrue(model.failure?.isRetryAvailable == true)
        XCTAssertTrue(model.failure?.partialChangesRolledBack == true)
        XCTAssertTrue(model.retry())
        XCTAssertEqual(generations, [1, 2])

        let secondGeneration = try XCTUnwrap(generations.last)
        XCTAssertTrue(model.cancel())
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertFalse(model.isImporting)
        XCTAssertFalse(model.apply(result: failure, generation: secondGeneration))

        model.reset()
        XCTAssertTrue(model.startImport())
        let thirdGeneration = try XCTUnwrap(generations.last)
        XCTAssertFalse(model.apply(result: failure, generation: firstGeneration))
        XCTAssertNotEqual(thirdGeneration, firstGeneration)
        XCTAssertTrue(model.isImporting)
    }

    func testImportSurfaceUsesSystemControlsAndNoForbiddenBoundary() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot.appendingPathComponent("PrismNative/App/PrismInstanceImport.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for requiredToken in [
            "PrismInstanceImportModel",
            "Form {",
            "Picker(",
            "TextField(",
            "PrismSystemOpenPanel.present",
            "beginLocalFilePanel",
            "applyLocalFilePanelResult",
            ".zip",
            ".data",
            "ProgressView(",
            "ContentUnavailableView",
            ".keyboardShortcut(.defaultAction)",
            ".accessibilityIdentifier(",
            ".disabled(!model.canImport)",
            ".formStyle(.grouped)"
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native instance import API: \(requiredToken)")
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
            "PrismLauncher"
        ] {
            XCTAssertFalse(source.contains(forbiddenToken), "Forbidden instance import token: \(forbiddenToken)")
        }
    }
}
