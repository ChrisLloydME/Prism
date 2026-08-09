import Foundation
import XCTest

@MainActor
final class PrismVanillaCreationTests: XCTestCase {
    func testDraftValidationNormalizesAndBuildsFoundationRequest() throws {
        let model = PrismVanillaCreationModel(
            initialDraft: PrismVanillaCreationDraft(
                versionDescriptor: " 1.21.1 ",
                versionName: " 1.21.1 Release ",
                loaderIdentifier: " net.fabricmc.fabric-loader ",
                loaderVersionDescriptor: " 0.16.5 ",
                name: " Fixture Vanilla ",
                groupID: " fixture-group ",
                iconKey: " default "
            )
        )

        let request = try XCTUnwrap(model.makeBridgeRequest())
        XCTAssertEqual(request.versionDescriptor, "1.21.1")
        XCTAssertEqual(request.versionName, "1.21.1 Release")
        XCTAssertEqual(request.loaderIdentifier, "net.fabricmc.fabric-loader")
        XCTAssertEqual(request.loaderVersionDescriptor, "0.16.5")
        XCTAssertEqual(request.name, "Fixture Vanilla")
        XCTAssertEqual(request.groupID, "fixture-group")
        XCTAssertEqual(request.iconKey, "default")

        model.draft.name = "   "
        XCTAssertFalse(model.canCreate)
        XCTAssertNil(model.makeBridgeRequest())

        model.draft.name = "Fixture Vanilla"
        model.draft.loaderVersionDescriptor = nil
        XCTAssertFalse(model.canCreate)
        XCTAssertNil(model.makeBridgeRequest())

        model.selectLoader(nil)
        XCTAssertTrue(model.canCreate)
        XCTAssertNil(model.draft.loaderIdentifier)
        XCTAssertNil(model.draft.loaderVersionDescriptor)
    }

    func testProductionDraftAcceptsTypedMetadataWithoutFixtureOptions() throws {
        var receivedRequest: PRVanillaCreationRequest?
        let model = PrismVanillaCreationModel(
            versions: [],
            loaders: [],
            icons: ["default"],
            initialDraft: PrismVanillaCreationDraft(
                versionDescriptor: "",
                versionName: "",
                loaderIdentifier: nil,
                loaderVersionDescriptor: nil,
                name: "",
                groupID: "",
                iconKey: "default"
            ),
            onCreate: { request, _ in receivedRequest = request }
        )

        XCTAssertFalse(model.canCreate)
        model.draft.versionDescriptor = "1.20.1"
        model.draft.versionName = "Minecraft 1.20.1"
        model.draft.name = "Native Instance"
        XCTAssertTrue(model.canCreate)
        XCTAssertTrue(model.create())
        XCTAssertEqual(receivedRequest?.versionDescriptor, "1.20.1")
        XCTAssertEqual(receivedRequest?.versionName, "Minecraft 1.20.1")
        XCTAssertEqual(receivedRequest?.name, "Native Instance")
        XCTAssertNil(receivedRequest?.loaderIdentifier)
    }

    func testCreateForwardsCopiedRequestAndSerializesWhileCreating() throws {
        var receivedRequest: PRVanillaCreationRequest?
        var receivedGeneration: Int?
        let model = PrismVanillaCreationModel(onCreate: { request, generation in
            receivedRequest = request
            receivedGeneration = generation
        })

        XCTAssertTrue(model.create())
        XCTAssertTrue(model.isCreating)
        XCTAssertFalse(model.create())
        XCTAssertNotNil(receivedRequest)
        XCTAssertEqual(receivedRequest?.name, "1.21.1 Release")
        XCTAssertEqual(receivedRequest?.versionDescriptor, "1.21.1")
        XCTAssertNil(receivedRequest?.loaderIdentifier)
        XCTAssertNil(receivedRequest?.groupID)
        XCTAssertEqual(receivedRequest?.iconKey, "default")
        XCTAssertEqual(receivedGeneration, 1)
    }

    func testProgressAndSuccessProduceConfirmedInstanceRow() throws {
        var activeGeneration: Int?
        let model = PrismVanillaCreationModel(onCreate: { _, generation in
            activeGeneration = generation
        })
        XCTAssertTrue(model.create())

        let progress = try XCTUnwrap(
            PRTaskStatus(
                identifier: "task.vanilla.creation",
                title: "Creating Fixture Vanilla",
                state: .running,
                progressKind: .determinate,
                progressFraction: 0.5,
                cancellationAllowed: true,
                subtasks: [],
                terminalResult: nil
            )
        )
        XCTAssertTrue(model.apply(progress: progress, generation: activeGeneration))
        XCTAssertEqual(model.progress?.id, "task.vanilla.creation")
        XCTAssertEqual(model.progress?.progress.fraction, 0.5)

        let summary = try XCTUnwrap(
            PRInstanceSummary(
                identifier: "fixture.vanilla",
                name: "Fixture Vanilla",
                iconKey: "default",
                groupID: "fixture-group"
            )
        )
        let result = try XCTUnwrap(
            PRVanillaCreationResult(
                instance: summary,
                outcome: .succeeded,
                localizationKey: "instances.creation.vanilla.succeeded",
                diagnosticText: nil,
                retryable: false
            )
        )

        XCTAssertTrue(model.apply(result: result, generation: activeGeneration))
        XCTAssertEqual(model.createdInstance?.id, "fixture.vanilla")
        XCTAssertEqual(model.createdInstance?.name, "Fixture Vanilla")
        XCTAssertEqual(model.createdInstance?.group, "fixture-group")
        XCTAssertFalse(model.isCreating)
    }

    func testFailureRetryCancellationAndStaleGenerationAreSafe() throws {
        var generations: [Int] = []
        var cancellationCount = 0
        let model = PrismVanillaCreationModel(
            onCreate: { _, generation in generations.append(generation) },
            onCancel: { cancellationCount += 1 }
        )

        XCTAssertTrue(model.create())
        let firstGeneration = try XCTUnwrap(generations.first)
        let failure = try XCTUnwrap(
            PRVanillaCreationResult(
                instance: nil,
                outcome: .failed,
                localizationKey: "instances.creation.vanilla.failed",
                diagnosticText: "fixture creation failed",
                retryable: true
            )
        )
        XCTAssertTrue(model.apply(result: failure, generation: firstGeneration))
        XCTAssertEqual(model.failure?.localizationKey, "instances.creation.vanilla.failed")
        XCTAssertTrue(model.failure?.isRetryAvailable == true)
        XCTAssertTrue(model.retry())
        XCTAssertEqual(generations, [1, 2])

        let secondGeneration = try XCTUnwrap(generations.last)
        XCTAssertTrue(model.cancel())
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertFalse(model.isCreating)
        XCTAssertFalse(model.apply(result: failure, generation: secondGeneration))

        model.reset()
        XCTAssertTrue(model.create())
        let thirdGeneration = try XCTUnwrap(generations.last)
        XCTAssertNotEqual(thirdGeneration, firstGeneration)
        XCTAssertFalse(model.apply(result: failure, generation: firstGeneration))
        XCTAssertTrue(model.isCreating)
    }

    func testCreationSurfaceUsesSystemControlsAndNoForbiddenBoundary() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot.appendingPathComponent("PrismNative/App/PrismVanillaCreation.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for requiredToken in [
            "PrismVanillaCreationModel",
            "Form {",
            "Picker(",
            "TextField(",
            "ProgressView(",
            "ContentUnavailableView",
            ".keyboardShortcut(.defaultAction)",
            ".accessibilityIdentifier(",
            ".disabled(!model.canCreate)",
            ".formStyle(.grouped)"
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native vanilla creation API: \(requiredToken)")
        }

        for forbiddenToken in [
            "Canvas(",
            "draw(",
            "Path(",
            "CGContext",
            "NSBezierPath",
            "QWidget",
            "QDialog",
            "URLSession",
            "FileManager",
            "Process(",
            "Application Support",
            "PrismLauncher"
        ] {
            XCTAssertFalse(source.contains(forbiddenToken), "Forbidden vanilla creation token: \(forbiddenToken)")
        }
    }
}
