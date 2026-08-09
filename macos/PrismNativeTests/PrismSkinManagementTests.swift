import Foundation
import XCTest

@MainActor
final class PrismSkinManagementTests: XCTestCase {
    func testSkinSelectionModelCapeAndFixtureDataRemainFoundationValues() throws {
        let model = PrismSkinManagementModel()

        XCTAssertEqual(model.skins.count, 2)
        XCTAssertEqual(model.selectedSkinIdentifier, PrismSkinFixture.currentSkinIdentifier)
        XCTAssertEqual(model.selectedCape?.id, "cape.fixture")
        XCTAssertTrue(model.canUpload)

        XCTAssertTrue(model.select(id: "skin.fixture.slim"))
        model.setModel(.slim)
        model.setCapeIdentifier(PrismSkinCape.noneIdentifier)
        XCTAssertEqual(model.draftModel, .slim)
        XCTAssertNil(model.selectedCape)
        XCTAssertFalse(model.select(id: "missing"))
        XCTAssertTrue(model.skins.allSatisfy { $0.sourceURL == nil })
    }

    func testLoadCancellationAndLateResultsAreGenerationGuarded() throws {
        var loadGenerations: [Int] = []
        var cancellations: [(PrismSkinOperation, Int)] = []
        let model = PrismSkinManagementModel(
            onLoad: { _, generation in loadGenerations.append(generation) },
            onCancel: { operation, generation in cancellations.append((operation, generation)) }
        )

        let first = model.beginLoad()
        XCTAssertEqual(model.listState, .loading(generation: first))
        let second = model.beginLoad()
        XCTAssertFalse(model.apply(
            loadResult: .success(
                accountIdentifier: "account.fixture.microsoft",
                skins: PrismSkinFixture.skins,
                capes: PrismSkinFixture.capes,
                currentSkinIdentifier: PrismSkinFixture.currentSkinIdentifier
            ),
            generation: first
        ))
        XCTAssertTrue(model.cancel())
        XCTAssertEqual(cancellations.count, 1)
        XCTAssertEqual(cancellations.first?.0, .load)
        XCTAssertEqual(cancellations.first?.1, second)
        XCTAssertFalse(model.apply(
            loadResult: .success(
                accountIdentifier: "account.fixture.microsoft",
                skins: PrismSkinFixture.skins,
                capes: PrismSkinFixture.capes,
                currentSkinIdentifier: PrismSkinFixture.currentSkinIdentifier
            ),
            generation: second
        ))
        XCTAssertEqual(loadGenerations, [first, second])
    }

    func testUploadResetDeleteRenameRequestsAndRecoveryAreTyped() throws {
        var uploads: [PrismSkinUploadRequest] = []
        var resets: [PrismSkinResetRequest] = []
        var deletes: [PrismSkinDeleteRequest] = []
        var renames: [PrismSkinRenameRequest] = []
        var generations: [Int] = []
        let model = PrismSkinManagementModel(
            onUpload: { request, generation in uploads.append(request); generations.append(generation) },
            onReset: { request, generation in resets.append(request); generations.append(generation) },
            onDelete: { request, generation in deletes.append(request); generations.append(generation) },
            onRename: { request, generation in renames.append(request); generations.append(generation) }
        )

        model.setModel(.slim)
        model.setCapeIdentifier(PrismSkinCape.noneIdentifier)
        XCTAssertTrue(model.upload())
        let uploadGeneration = try XCTUnwrap(generations.first)
        XCTAssertEqual(uploads.first?.skinIdentifier, PrismSkinFixture.currentSkinIdentifier)
        XCTAssertEqual(uploads.first?.model, .slim)
        XCTAssertEqual(uploads.first?.capeIdentifier, "")
        XCTAssertTrue(model.apply(
            actionResult: .success(operation: .upload),
            generation: uploadGeneration
        ))

        XCTAssertTrue(model.resetSkin())
        XCTAssertEqual(resets.first?.accountIdentifier, "account.fixture.microsoft")
        let resetGeneration = try XCTUnwrap(generations.dropFirst().first)
        let failure = PrismSkinFailure(
            localizationKey: "skins.reset.failed",
            diagnosticText: "fixture failure",
            recoveryAction: .retry
        )
        XCTAssertTrue(model.apply(
            actionResult: .failure(operation: .reset, failure: failure),
            generation: resetGeneration
        ))
        XCTAssertTrue(model.retry())
        XCTAssertEqual(resets.count, 2)
        XCTAssertTrue(model.cancel())

        XCTAssertFalse(model.deleteSelected())
        XCTAssertEqual(model.retryFailure?.localizationKey, "skins.delete.currentRejected")
        XCTAssertTrue(model.select(id: "skin.fixture.slim"))
        XCTAssertTrue(model.deleteSelected())
        XCTAssertEqual(deletes.first?.confirmed, true)
        let deleteGeneration = try XCTUnwrap(generations.last)
        XCTAssertTrue(model.apply(
            actionResult: .success(
                operation: .delete,
                skins: [PrismSkinFixture.skins[0]],
                selectedSkinIdentifier: PrismSkinFixture.currentSkinIdentifier
            ),
            generation: deleteGeneration
        ))

        XCTAssertTrue(model.renameSelected(to: "Renamed Fixture"))
        XCTAssertEqual(renames.first?.newName, "Renamed Fixture")
    }

    func testFileURLPanelImportURLUserValidationAndStaleFileResults() throws {
        var presentedGeneration: Int?
        var imports: [PrismSkinImportRequest] = []
        let model = PrismSkinManagementModel(
            onImport: { request, _ in imports.append(request) },
            onPresentImportPanel: { presentedGeneration = $0 }
        )
        let ticket = try XCTUnwrap(model.beginImportFile())
        XCTAssertEqual(presentedGeneration, ticket)
        let fileURL = URL(fileURLWithPath: "/private/tmp/prism-native-m9-w2-fixture/skin.png")
        XCTAssertTrue(model.submitImportFile(url: fileURL, generation: ticket))
        XCTAssertEqual(imports, [
            PrismSkinImportRequest(accountIdentifier: "account.fixture.microsoft", source: .file(fileURL.standardizedFileURL))
        ])
        XCTAssertTrue(model.cancel())

        let invalidURL = URL(fileURLWithPath: "/private/tmp/prism-native-m9-w2-fixture/not-a-url")
        XCTAssertFalse(model.submitImportFile(url: invalidURL, generation: ticket))
        XCTAssertFalse(model.importURL(text: "fixture.invalid/no-scheme"))
        XCTAssertTrue(model.importURL(text: "https://example.invalid/skin.png"))
        XCTAssertTrue(model.cancel())
        XCTAssertTrue(model.importUser(text: "FixtureUser"))
        XCTAssertFalse(model.importUser(text: String(repeating: "x", count: 17)))
    }

    func testPreviewImageStoreStaysBoundedAtTenTimesDefaultVolume() throws {
        let data = PrismSkinFixture.textureData
        let store = try XCTUnwrap(
            PrismSkinPreviewImageStore(maxItemCount: 2, maxTotalBytes: data.count * 2)
        )

        for index in 0..<20 {
            XCTAssertNotNil(store.image(for: "skin.\(index)", data: data))
        }
        XCTAssertLessThanOrEqual(store.cachedIdentifiers.count, 2)
        XCTAssertLessThanOrEqual(store.cachedByteCount, data.count * 2)
        XCTAssertNotNil(store.image(for: "skin.19", data: data))
        store.removeImage(for: "skin.19")
        store.removeAll()
        XCTAssertTrue(store.cachedIdentifiers.isEmpty)
        XCTAssertEqual(store.cachedByteCount, 0)
        XCTAssertNil(PrismSkinPreviewImageStore(maxItemCount: 0, maxTotalBytes: 1))
    }

    func testSceneKitDomainGeometryAndNonScreenshotAccessibilityContract() throws {
        let base = PrismSkinPreviewGeometry.parts(for: .classic, includeCape: false, includeElytra: false)
        let slim = PrismSkinPreviewGeometry.parts(for: .slim, includeCape: true, includeElytra: true)
        XCTAssertEqual(base.count, 12)
        XCTAssertEqual(slim.count, 15)
        XCTAssertTrue(slim.contains { $0.name == "cape" && $0.kind == .cape })
        XCTAssertEqual(slim.filter { $0.kind == .elytra }.count, 2)
        XCTAssertTrue(slim.filter { $0.kind == .box }.allSatisfy { $0.textureRect.width > 0 && $0.textureRect.height > 0 })

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: sourceRoot.appendingPathComponent("PrismNative/App/PrismSkinManagement.swift"),
            encoding: .utf8
        )
        for requiredToken in [
            "import SceneKit",
            "NSViewRepresentable",
            "SCNView",
            "PrismSkinPreviewGeometry",
            ".accessibilityLabel(Text(\"Skin Preview\"))",
            ".accessibilityValue(Text(accessibilitySummary))",
            ".keyboardShortcut(.defaultAction)",
            "PrismSystemOpenPanel.present",
            "UTType.png",
            "maxItemCount",
            "defaultTotalByteLimit"
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native skin contract: \(requiredToken)")
        }
        for forbiddenToken in ["Canvas(", "CGContext", "QOpenGL", "NSOpenGL", "QWidget", "QDialog", "URLSession", "Process("] {
            XCTAssertFalse(source.contains(forbiddenToken), "Forbidden skin implementation token: \(forbiddenToken)")
        }
    }

    func testSkinWindowAndAccountEntryUseNativeSceneAndSystemControls() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("PrismNative/App/PrismNativeApp.swift"),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("PrismNative/App/PrismSettings.swift"),
            encoding: .utf8
        )
        let accountSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("PrismNative/App/PrismAccountSettings.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appSource.contains("Window(\"Manage Skins\", id: \"prism.skin-management\")"))
        XCTAssertTrue(appSource.contains("PrismSkinManagementView(model: skinModel)"))
        XCTAssertTrue(settingsSource.contains("openWindow(id: \"prism.skin-management\")"))
        XCTAssertTrue(accountSource.contains("Manage Skins…"))
        XCTAssertTrue(accountSource.contains("account.type == .microsoft"))
        XCTAssertTrue(accountSource.contains("account.state == .online"))
        XCTAssertTrue(accountSource.contains("prism.settings.accounts.manage-skins"))
    }
}
