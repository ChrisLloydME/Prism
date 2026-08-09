import Foundation
import XCTest

@MainActor
final class PrismInstanceCopyExportTests: XCTestCase {
    func testCopyDraftPreservesLegacyPolicyAndNormalizesFoundationRequest() throws {
        var options = PrismInstanceCopyOptions()
        options.copySaves = true
        options.useSymbolicLinks = true
        options.linkRecursively = true
        options.dontLinkSaves = true
        let model = PrismInstanceCopyModel(
            sourceInstanceIdentifier: " fixture.source ",
            initialDraft: PrismInstanceCopyDraft(
                sourceInstanceIdentifier: " fixture.source ",
                name: " Copied Fixture ",
                groupID: " fixture-copies ",
                iconKey: " default ",
                options: options
            )
        )

        let request = try XCTUnwrap(model.makeBridgeRequest())
        XCTAssertEqual(request.sourceInstanceIdentifier, "fixture.source")
        XCTAssertEqual(request.name, "Copied Fixture")
        XCTAssertEqual(request.groupID, "fixture-copies")
        XCTAssertTrue(request.copySaves)
        XCTAssertTrue(request.useSymbolicLinks)
        XCTAssertTrue(request.linkRecursively)
        XCTAssertTrue(request.dontLinkSaves)

        model.draft.options.useClone = true
        XCTAssertFalse(model.canCopy)
        XCTAssertNil(model.makeBridgeRequest())
    }

    func testCopyForwardsProgressSuccessFailureRetryCancellationAndStaleGeneration() throws {
        var generations: [Int] = []
        var cancellationCount = 0
        let model = PrismInstanceCopyModel(
            sourceInstanceIdentifier: "fixture.source",
            onCopy: { _, generation in generations.append(generation) },
            onCancel: { cancellationCount += 1 }
        )

        XCTAssertTrue(model.startCopy())
        let firstGeneration = try XCTUnwrap(generations.first)
        let progress = try XCTUnwrap(
            PRTaskStatus(
                identifier: "task.instance.copy",
                title: "Copying Fixture",
                state: .running,
                progressKind: .determinate,
                progressFraction: 0.5,
                cancellationAllowed: true,
                subtasks: [],
                terminalResult: nil
            )
        )
        XCTAssertTrue(model.apply(progress: progress, generation: firstGeneration))

        let summary = try XCTUnwrap(
            PRInstanceSummary(
                identifier: "fixture.copied",
                name: "Copied Instance",
                iconKey: "default",
                groupID: nil
            )
        )
        let success = try XCTUnwrap(
            PRInstanceCopyResult(
                instance: summary,
                outcome: .succeeded,
                localizationKey: "instances.copy.completed",
                diagnosticText: nil,
                retryable: false,
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(model.apply(result: success, generation: firstGeneration))
        XCTAssertEqual(model.copiedInstance?.id, "fixture.copied")

        model.reset()
        XCTAssertTrue(model.startCopy())
        let secondGeneration = try XCTUnwrap(generations.last)
        let failure = try XCTUnwrap(
            PRInstanceCopyResult(
                instance: nil,
                outcome: .failed,
                localizationKey: "instances.copy.failed",
                diagnosticText: "fixture copy failed",
                retryable: true,
                partialChangesRolledBack: true
            )
        )
        XCTAssertTrue(model.apply(result: failure, generation: secondGeneration))
        XCTAssertTrue(model.failure?.isRetryAvailable == true)
        XCTAssertTrue(model.retry())
        XCTAssertEqual(generations, [1, 3, 4])

        let thirdGeneration = try XCTUnwrap(generations.last)
        XCTAssertTrue(model.cancel())
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertFalse(model.apply(result: failure, generation: thirdGeneration))
        XCTAssertFalse(model.apply(result: failure, generation: firstGeneration))
    }

    func testExportDraftUsesSavePanelFileURLAndModListOptions() throws {
        let destinationURL = URL(fileURLWithPath: "/private/tmp/fixture-export/mods.csv")
        let model = PrismInstanceExportModel(
            sourceInstanceIdentifier: " fixture.source ",
            initialDraft: PrismInstanceExportDraft(
                sourceInstanceIdentifier: " fixture.source ",
                kind: .modList,
                destinationURL: destinationURL,
                modListFormat: .csv,
                includeAuthors: true,
                includeVersion: true,
                includeURL: false,
                includeFilename: true,
                customTemplate: ""
            )
        )

        let request = try XCTUnwrap(model.makeBridgeRequest())
        XCTAssertEqual(request.sourceInstanceIdentifier, "fixture.source")
        XCTAssertEqual(request.destinationURL.path, destinationURL.path)
        XCTAssertEqual(request.kind, .modList)
        XCTAssertEqual(request.modListFormat, .CSV)
        XCTAssertTrue(request.includeAuthors)
        XCTAssertTrue(request.includeVersion)
        XCTAssertTrue(request.includeFilename)
        XCTAssertFalse(request.includeURL)

        model.setDestinationURL(URL(string: "https://example.invalid/not-a-file"))
        XCTAssertFalse(model.canExport)
        XCTAssertNil(model.makeBridgeRequest())
    }

    func testExportForwardsProgressSuccessFailureRetryCancellationAndStaleGeneration() throws {
        var generations: [Int] = []
        var cancellationCount = 0
        let destinationURL = URL(fileURLWithPath: "/private/tmp/fixture-export/fixture.zip")
        let model = PrismInstanceExportModel(
            sourceInstanceIdentifier: "fixture.source",
            initialDraft: PrismInstanceExportDraft(
                sourceInstanceIdentifier: "fixture.source",
                kind: .zipArchive,
                destinationURL: destinationURL,
                modListFormat: .html,
                includeAuthors: false,
                includeVersion: false,
                includeURL: false,
                includeFilename: false,
                customTemplate: ""
            ),
            onExport: { _, generation in generations.append(generation) },
            onCancel: { cancellationCount += 1 }
        )

        XCTAssertTrue(model.startExport())
        let firstGeneration = try XCTUnwrap(generations.first)
        let progress = try XCTUnwrap(
            PRTaskStatus(
                identifier: "task.instance.export",
                title: "Exporting Fixture",
                state: .running,
                progressKind: .determinate,
                progressFraction: 0.5,
                cancellationAllowed: true,
                subtasks: [],
                terminalResult: nil
            )
        )
        XCTAssertTrue(model.apply(progress: progress, generation: firstGeneration))
        let success = try XCTUnwrap(
            PRInstanceExportResult(
                kind: .zipArchive,
                outcome: .succeeded,
                destinationURL: destinationURL,
                localizationKey: "instances.export.completed",
                diagnosticText: nil,
                retryable: false,
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(model.apply(result: success, generation: firstGeneration))
        if case .succeeded(let receivedURL) = model.state {
            XCTAssertEqual(receivedURL.path, destinationURL.path)
        } else {
            XCTFail("Expected export success")
        }

        model.reset()
        XCTAssertTrue(model.startExport())
        let secondGeneration = try XCTUnwrap(generations.last)
        let failure = try XCTUnwrap(
            PRInstanceExportResult(
                kind: .zipArchive,
                outcome: .failed,
                destinationURL: destinationURL,
                localizationKey: "instances.export.failed",
                diagnosticText: "fixture export failed",
                retryable: true,
                partialChangesRolledBack: true
            )
        )
        XCTAssertTrue(model.apply(result: failure, generation: secondGeneration))
        XCTAssertTrue(model.retry())
        XCTAssertEqual(generations, [1, 3, 4])

        let thirdGeneration = try XCTUnwrap(generations.last)
        XCTAssertTrue(model.cancel())
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertFalse(model.apply(result: failure, generation: thirdGeneration))
        XCTAssertFalse(model.apply(result: failure, generation: firstGeneration))
    }

    func testCopyAndExportSurfacesUseNativeControlsSavePanelAndNoForbiddenBoundary() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot.appendingPathComponent("PrismNative/App/PrismInstanceCopyExport.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for requiredToken in [
            "PrismInstanceCopyModel",
            "PrismInstanceExportModel",
            "Form {",
            "Toggle(",
            "Picker(",
            "TextField(",
            "NSSavePanel(",
            ".allowedContentTypes",
            "panel.begin",
            "ProgressView(",
            "ContentUnavailableView",
            ".keyboardShortcut(.defaultAction)",
            ".accessibilityIdentifier(",
            ".disabled(!model.canCopy)",
            ".disabled(!model.canExport)",
            ".formStyle(.grouped)"
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native copy/export API: \(requiredToken)")
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
            XCTAssertFalse(source.contains(forbiddenToken), "Forbidden copy/export token: \(forbiddenToken)")
        }
    }
}
