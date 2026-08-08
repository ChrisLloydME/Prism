import Foundation
import XCTest

@MainActor
final class PrismShellTests: XCTestCase {
    private func makeInstanceSettings(
        identifier: String = "fixture.one",
        windowWidth: Int = 1280
    ) throws -> PRInstanceSettings {
        try XCTUnwrap(
            PRInstanceSettings(
                identifier: identifier,
                windowOverrideEnabled: true,
                launchMaximized: true,
                windowWidth: windowWidth,
                windowHeight: 720,
                closeAfterLaunch: true,
                quitAfterGameStop: false,
                consoleOverrideEnabled: true,
                showConsole: true,
                showConsoleOnError: true,
                autoCloseConsole: false,
                globalDataPacksEnabled: true,
                globalDataPacksPath: "datapacks",
                gameTimeOverrideEnabled: true,
                showGameTime: true,
                recordGameTime: true,
                countGameTime: true,
                joinServerOnLaunch: true,
                joinTarget: .server,
                joinServerAddress: "fixture.example:25565",
                joinWorld: "",
                overrideModDownloadLoaders: true,
                modDownloadLoaders: ["Fabric", "Quilt"],
                javaLocationOverrideEnabled: true,
                javaPath: "/fixture/bin/java",
                ignoreJavaCompatibility: true,
                memoryOverrideEnabled: true,
                minMemoryMiB: 512,
                maxMemoryMiB: 4096,
                permGenMiB: 128,
                lowMemoryWarning: true,
                javaArgumentsOverrideEnabled: true,
                jvmArguments: "-Dfixture=true",
                commandOverrideEnabled: true,
                preLaunchCommand: "prepare-fixture",
                wrapperCommand: "wrapper-fixture",
                postExitCommand: "cleanup-fixture",
                legacySettingsOverrideEnabled: true,
                onlineFixes: false,
                nativeWorkaroundsOverrideEnabled: true,
                useNativeGLFW: true,
                customGLFWPath: "/fixture/libglfw.dylib",
                useNativeOpenAL: true,
                customOpenALPath: "/fixture/libopenal.dylib"
            )
        )
    }

    private func makeInstanceComponent(
        identifier: String,
        name: String,
        version: String,
        enabled: Bool = true,
        canBeDisabled: Bool = true,
        dependencyOnly: Bool = false,
        important: Bool = false,
        custom: Bool = false,
        problemSeverity: PRInstanceComponentProblemSeverity = .none,
        problemDescriptions: [String] = []
    ) throws -> PRInstanceComponent {
        try XCTUnwrap(
            PRInstanceComponent(
                identifier: identifier,
                name: name,
                version: version,
                enabled: enabled,
                canBeDisabled: canBeDisabled,
                dependencyOnly: dependencyOnly,
                important: important,
                custom: custom,
                problemSeverity: problemSeverity,
                problemDescriptions: problemDescriptions
            )
        )
    }

    private func makeInstanceResource(
        identifier: String,
        name: String,
        version: String,
        fileName: String,
        provider: String = "Fixture",
        kind: PRInstanceResourceKind = .mods,
        enabled: Bool = true,
        canBeToggled: Bool = true,
        canBeDeleted: Bool = true,
        isDirectory: Bool = false,
        hasMetadata: Bool = true,
        problemDescriptions: [String] = []
    ) throws -> PRInstanceResource {
        try XCTUnwrap(
            PRInstanceResource(
                identifier: identifier,
                name: name,
                version: version,
                fileName: fileName,
                provider: provider,
                kind: kind,
                enabled: enabled,
                canBeToggled: canBeToggled,
                canBeDeleted: canBeDeleted,
                isDirectory: isDirectory,
                hasMetadata: hasMetadata,
                problemDescriptions: problemDescriptions
            )
        )
    }

    func testSidebarManifestHasStableSelectionAndAccessibilityMetadata() {
        let items = PrismShellSidebarItem.allCases

        XCTAssertEqual(items, [.instances, .discover])
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)

        for item in items {
            XCTAssertFalse(item.titleKey.isEmpty)
            XCTAssertFalse(item.accessibilityLabelKey.isEmpty)
            XCTAssertFalse(item.accessibilityHintKey.isEmpty)
            XCTAssertFalse(item.systemImage.isEmpty)
        }
    }

    func testShellModelDefaultsToInstanceLibraryAndEmptyDetail() {
        let model = PrismShellModel()

        XCTAssertEqual(model.selectedSidebarItem, .instances)
        XCTAssertEqual(model.detailState, .empty)
    }

    func testShellModelTracksSidebarSelectionWithoutChangingDetailState() {
        let model = PrismShellModel()

        model.selectSidebarItem(.discover)
        XCTAssertEqual(model.selectedSidebarItem, .discover)

        model.selectSidebarItem(nil)
        XCTAssertNil(model.selectedSidebarItem)
        XCTAssertEqual(model.detailState, .empty)
    }

    func testShellModelRepresentsLoadingEmptyFailedAndContentStates() {
        let model = PrismShellModel()
        let failure = PrismShellFailure.instanceLoad

        let states: [PrismShellDetailState] = [
            PrismShellDetailState.loading,
            .empty,
            .failed(failure),
            .content,
        ]

        for state in states {
            model.setDetailState(state)
            XCTAssertEqual(model.detailState, state)
        }

        XCTAssertEqual(failure.titleKey, "Unable to Load Instances")
        XCTAssertEqual(failure.messageKey, "Try again to load your instances.")
        XCTAssertEqual(failure.recoveryAction, .retry)
        XCTAssertFalse(failure.recoveryAction.titleKey.isEmpty)
        XCTAssertFalse(failure.recoveryAction.accessibilityLabelKey.isEmpty)
        XCTAssertFalse(failure.recoveryAction.helpKey.isEmpty)
    }

    func testRetryIsEligibleOnlyForFailedStateAndDoesNotRouteStaleActions() {
        var retryCount = 0
        let model = PrismShellModel(onRetry: { retryCount += 1 })

        for state in [
            PrismShellDetailState.loading,
            .empty,
            .content,
        ] {
            model.setDetailState(state)
            XCTAssertNil(model.recoveryAction)
            XCTAssertFalse(model.isRetryAvailable)
            model.retry()
        }

        XCTAssertEqual(retryCount, 0)

        model.setDetailState(.failed(.instanceLoad))
        XCTAssertEqual(model.recoveryAction, .retry)
        XCTAssertTrue(model.isRetryAvailable)
        model.retry()
        XCTAssertEqual(retryCount, 1)

        model.setDetailState(.loading)
        model.retry()
        XCTAssertEqual(retryCount, 1)
    }

    func testInstanceDetailsMappingPreservesNotesAndNormalizesMetadata() throws {
        let bridgeDetails = try XCTUnwrap(
            PRInstanceDetails(
                identifier: " fixture.one ",
                name: " Fixture One ",
                iconKey: " icon.one ",
                groupID: " group.one ",
                instanceType: " Minecraft ",
                notes: "line one\nline two ",
                notesEditable: true
            )
        )
        let details = try XCTUnwrap(PrismInstanceDetails(bridgeDetails: bridgeDetails))

        XCTAssertEqual(details.id, "fixture.one")
        XCTAssertEqual(details.name, "Fixture One")
        XCTAssertEqual(details.iconKey, "icon.one")
        XCTAssertEqual(details.group, "group.one")
        XCTAssertEqual(details.instanceType, "Minecraft")
        XCTAssertEqual(details.notes, "line one\nline two ")
        XCTAssertTrue(details.notesEditable)
        XCTAssertNil(
            PrismInstanceDetails(
                bridgeDetails: try XCTUnwrap(
                    PRInstanceDetails(
                        identifier: "   ",
                        name: "Fixture One",
                        iconKey: nil,
                        groupID: nil,
                        instanceType: nil,
                        notes: "fixture notes",
                        notesEditable: false
                    )
                )
            )
        )
    }

    func testInstanceDetailsModelConfirmsNotesEditsAndPreservesDraftOnFailure() throws {
        var loadedIdentifiers: [String] = []
        var saveRequests: [(String, String)] = []
        let model = PrismInstanceDetailsModel(
            onLoad: { loadedIdentifiers.append($0) },
            onSaveNotes: { saveRequests.append(($0, $1)) }
        )

        XCTAssertTrue(model.beginLoading(identifier: " fixture.one "))
        XCTAssertEqual(model.state, .loading(identifier: "fixture.one"))
        XCTAssertEqual(loadedIdentifiers, ["fixture.one"])

        let bridgeDetails = try XCTUnwrap(
            PRInstanceDetails(
                identifier: "fixture.one",
                name: "Fixture One",
                iconKey: "icon.one",
                groupID: "group.one",
                instanceType: "Minecraft",
                notes: "confirmed\nnotes",
                notesEditable: true
            )
        )
        XCTAssertTrue(model.apply(details: bridgeDetails))
        XCTAssertEqual(model.draftNotes, "confirmed\nnotes")

        model.setDraftNotes("updated\nnotes")
        XCTAssertTrue(model.isNotesSaveAvailable)
        XCTAssertTrue(model.saveNotes())
        XCTAssertEqual(model.notesSaveState, .saving)
        XCTAssertEqual(saveRequests.count, 1)
        XCTAssertEqual(saveRequests[0].0, "fixture.one")
        XCTAssertEqual(saveRequests[0].1, "updated\nnotes")

        let confirmedResult = try XCTUnwrap(
            PRInstanceNotesUpdateResult(
                identifier: "fixture.one",
                notes: "confirmed by facade\nnotes ",
                outcome: .succeeded
            )
        )
        XCTAssertTrue(model.apply(notesResult: confirmedResult))
        XCTAssertEqual(model.details?.notes, "confirmed by facade\nnotes ")
        XCTAssertEqual(model.draftNotes, "confirmed by facade\nnotes ")
        XCTAssertEqual(model.notesSaveState, .idle)

        model.setDraftNotes("rejected draft")
        XCTAssertTrue(model.saveNotes())
        let rejectedResult = try XCTUnwrap(
            PRInstanceNotesUpdateResult(
                identifier: "fixture.one",
                notes: "",
                outcome: .rejected
            )
        )
        XCTAssertTrue(model.apply(notesResult: rejectedResult))
        XCTAssertEqual(model.details?.notes, "confirmed by facade\nnotes ")
        XCTAssertEqual(model.draftNotes, "rejected draft")
        XCTAssertEqual(model.notesFailure?.localizationKey, "instance.notes.updateRejected")
        XCTAssertFalse(model.retryNotes())

        model.setDraftNotes("retry draft")
        XCTAssertTrue(model.saveNotes())
        let bridgeError = try XCTUnwrap(
            PRBridgeError(
                code: .dataUnavailable,
                localizationKey: "instance.notes.unavailable",
                substitutionValues: ["instanceIdentifier": "fixture.one"],
                diagnosticText: "fixture notes unavailable",
                recoveryKind: .retry,
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(model.apply(error: bridgeError, instanceIdentifier: " fixture.one "))
        XCTAssertEqual(model.details?.notes, "confirmed by facade\nnotes ")
        XCTAssertEqual(model.draftNotes, "retry draft")
        XCTAssertEqual(model.notesFailure?.localizationKey, "instance.notes.unavailable")
        XCTAssertTrue(model.retryNotes())
        XCTAssertEqual(model.notesSaveState, .saving)
        XCTAssertEqual(saveRequests.count, 4)
        XCTAssertEqual(saveRequests[3].0, "fixture.one")
        XCTAssertEqual(saveRequests[3].1, "retry draft")

        XCTAssertFalse(
            model.apply(
                notesResult: try XCTUnwrap(
                    PRInstanceNotesUpdateResult(
                        identifier: "other.instance",
                        notes: "stale",
                        outcome: .succeeded
                    )
                )
            )
        )
    }

    func testInstanceComponentsModelPreservesOrderAndFiltersVersionFields() throws {
        var loadedIdentifiers: [String] = []
        let model = PrismInstanceComponentsModel(onLoad: { loadedIdentifiers.append($0) })

        XCTAssertTrue(model.beginLoading(identifier: " fixture.one "))
        XCTAssertEqual(model.state, .loading(identifier: "fixture.one"))
        XCTAssertEqual(loadedIdentifiers, ["fixture.one"])

        let minecraft = try makeInstanceComponent(
            identifier: "net.minecraft",
            name: "Minecraft",
            version: "1.20.1",
            canBeDisabled: false,
            important: true
        )
        let fabric = try makeInstanceComponent(
            identifier: "net.fabricmc.fabric-loader",
            name: "Fabric Loader",
            version: "0.15.11",
            problemSeverity: .warning,
            problemDescriptions: ["Fixture metadata is stale."]
        )
        let custom = try makeInstanceComponent(
            identifier: "fixture.custom",
            name: "Custom Fixture",
            version: "1",
            enabled: false,
            custom: true,
            problemSeverity: .error,
            problemDescriptions: ["Custom component is not loaded."]
        )

        XCTAssertTrue(model.apply(components: [minecraft, fabric, custom]))
        XCTAssertEqual(model.components.map(\.id), ["net.minecraft", "net.fabricmc.fabric-loader", "fixture.custom"])
        XCTAssertEqual(model.components[0].stateKey, "Required")
        XCTAssertEqual(model.components[1].accessibilityValueKey, "Component Has a Warning")
        XCTAssertEqual(model.components[2].displayVersion, "1")
        XCTAssertEqual(model.components[2].stateKey, "Custom Disabled")

        model.setSearchText("fabric")
        XCTAssertEqual(model.visibleComponents.map(\.id), ["net.fabricmc.fabric-loader"])
        model.setSearchText("stale")
        XCTAssertEqual(model.visibleComponents.map(\.id), ["net.fabricmc.fabric-loader"])
        model.selectComponent("net.fabricmc.fabric-loader")
        XCTAssertEqual(model.selectedComponentID, "net.fabricmc.fabric-loader")
        model.setSearchText("minecraft")
        XCTAssertNil(model.selectedComponentID)

        model.setSearchText("")
        XCTAssertTrue(model.apply(components: []))
        XCTAssertEqual(model.state, .empty)

        XCTAssertTrue(model.beginLoading(identifier: "fixture.one"))
        XCTAssertFalse(model.apply(components: [fabric, fabric]))
        XCTAssertEqual(model.state, .loading(identifier: "fixture.one"))
    }

    func testInstanceComponentsModelSupportsRetryAndRejectsStaleOrInvalidResults() throws {
        var loadRequests: [String] = []
        let model = PrismInstanceComponentsModel(onLoad: { loadRequests.append($0) })
        XCTAssertTrue(model.beginLoading(identifier: "fixture.one"))

        let error = try XCTUnwrap(
            PRBridgeError(
                code: .dataUnavailable,
                localizationKey: "instance.components.unavailable",
                substitutionValues: ["instanceIdentifier": "fixture.one"],
                diagnosticText: "fixture components unavailable",
                recoveryKind: .retry,
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(model.apply(error: error, instanceIdentifier: " fixture.one "))
        XCTAssertEqual(model.failure?.localizationKey, "instance.components.unavailable")
        XCTAssertTrue(model.failure?.isRetryAvailable == true)
        XCTAssertTrue(model.retry())
        XCTAssertEqual(model.state, .loading(identifier: "fixture.one"))
        XCTAssertEqual(loadRequests, ["fixture.one", "fixture.one"])

        let component = try makeInstanceComponent(
            identifier: "fixture.component",
            name: "Fixture Component",
            version: "1",
            canBeDisabled: false,
            important: true
        )
        XCTAssertTrue(model.apply(components: [component]))
        XCTAssertFalse(model.retry())
        let invalidComponent = try XCTUnwrap(
            PRInstanceComponent(
                identifier: " ",
                name: "Invalid",
                version: "1",
                enabled: true,
                canBeDisabled: true,
                dependencyOnly: false,
                important: false,
                custom: false,
                problemSeverity: .none,
                problemDescriptions: []
            )
        )
        XCTAssertFalse(model.apply(components: [invalidComponent]))
        XCTAssertEqual(model.components.map(\.id), ["fixture.component"])
        XCTAssertFalse(model.apply(error: error, instanceIdentifier: "other.instance"))
    }

    func testInstanceComponentsSourceUsesNativeTableSearchAndRecoveryAPIs() throws {
        let contentSource = try contentSource()
        let shellModelSource = try shellModelSource()

        for requiredToken in [
            "PrismInstanceComponentsView",
            "Table(model.visibleComponents)",
            "TableColumn(\"Name\")",
            "TableColumn(\"Version\")",
            "TableColumn(\"State\")",
            ".searchable(",
            "ContentUnavailableView",
            "ProgressView(\"Loading Versions and Components\")",
            "prism.instance-components.table",
            ".accessibilityLabel(",
            ".accessibilityValue(",
            ".help("
        ] {
            XCTAssertTrue(contentSource.contains(requiredToken), "Missing native component table API: \(requiredToken)")
        }

        for requiredToken in [
            "PrismInstanceComponent",
            "PrismInstanceComponentsModel",
            "PRInstanceComponent",
            "PrismInstanceComponentsState",
            "PrismInstanceComponentsFailure",
            "beginLoading(identifier:",
            "apply(components bridgeComponents:",
            "visibleComponents",
            "retry()",
            "problemSeverity",
            "problemDescriptions"
        ] {
            XCTAssertTrue(shellModelSource.contains(requiredToken), "Missing component state contract: \(requiredToken)")
        }

        XCTAssertTrue(contentSource.contains("Versions and Components"))
        XCTAssertTrue(contentSource.contains("prism.instance-details.components-link"))
        XCTAssertFalse(contentSource.contains("Canvas("))
        XCTAssertFalse(contentSource.contains("draw("))
        XCTAssertFalse(contentSource.contains("Path("))
        XCTAssertFalse(shellModelSource.contains("QWidget"))
        XCTAssertFalse(shellModelSource.contains("QDialog"))
        XCTAssertFalse(shellModelSource.contains("Unmanaged"))
        XCTAssertFalse(shellModelSource.contains("UnsafeMutable"))
    }

    func testInstanceResourcesModelPreservesOrderAndRequiresConfirmedActions() throws {
        var loadRequests: [(String, PrismInstanceResourceKind)] = []
        var mutationRequests: [(String, PrismInstanceResourceKind, PrismInstanceResourceMutationIntent)] = []
        let model = PrismInstanceResourcesModel(
            onLoad: { loadRequests.append(($0, $1)) },
            onMutate: { mutationRequests.append(($0, $1, $2)) }
        )

        XCTAssertTrue(model.beginLoading(identifier: " fixture.one ", kind: .mods))
        XCTAssertEqual(model.state, .loading(identifier: "fixture.one", kind: .mods))
        let mod = try makeInstanceResource(
            identifier: "mod.one",
            name: "Fixture Mod",
            version: "1.0",
            fileName: "fixture-mod.jar"
        )
        let folder = try makeInstanceResource(
            identifier: "mod.folder",
            name: "Fixture Folder",
            version: "",
            fileName: "fixture-folder",
            provider: "",
            canBeToggled: false,
            isDirectory: true,
            hasMetadata: false,
            problemDescriptions: ["Folder resources cannot be toggled."]
        )

        XCTAssertTrue(model.apply(resources: [mod, folder]))
        XCTAssertEqual(model.resources.map(\.id), ["mod.one", "mod.folder"])
        XCTAssertEqual(model.resources[1].displayVersion, "Not Available")
        XCTAssertEqual(model.resources[1].stateKey, "Folder")
        model.setSearchText("fixture-mod.jar")
        XCTAssertEqual(model.visibleResources.map(\.id), ["mod.one"])
        model.setSearchText("cannot be toggled")
        XCTAssertEqual(model.visibleResources.map(\.id), ["mod.folder"])
        model.selectResource("mod.folder")
        XCTAssertEqual(model.selectedResourceID, "mod.folder")
        model.setSearchText("mod.one")
        XCTAssertNil(model.selectedResourceID)

        model.setSearchText("")
        XCTAssertTrue(model.setEnabled(false, for: "mod.one"))
        XCTAssertEqual(mutationRequests.last?.2.action, .disable)
        XCTAssertFalse(mutationRequests.last?.2.confirmed == true)
        XCTAssertEqual(model.resources[0].enabled, true)

        let disableResult = try XCTUnwrap(
            PRInstanceResourceMutationResult(
                instanceIdentifier: "fixture.one",
                resourceIdentifier: "mod.one",
                kind: .mods,
                action: .disable,
                outcome: .succeeded,
                localizationKey: "instance.resource.updated",
                diagnosticText: "confirmed disable",
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(model.apply(mutationResult: disableResult, instanceIdentifier: "fixture.one"))
        XCTAssertEqual(model.state, .loading(identifier: "fixture.one", kind: .mods))
        XCTAssertEqual(loadRequests.count, 2)
        XCTAssertEqual(loadRequests.first?.0, "fixture.one")
        XCTAssertEqual(loadRequests.first?.1, .mods)

        XCTAssertTrue(model.apply(resources: [mod, folder]))
        XCTAssertTrue(model.requestDelete("mod.one"))
        XCTAssertEqual(model.pendingDeleteResourceID, "mod.one")
        XCTAssertTrue(model.confirmDelete())
        XCTAssertEqual(mutationRequests.last?.2.action, .delete)
        XCTAssertTrue(mutationRequests.last?.2.confirmed == true)

        let deleteFailure = try XCTUnwrap(
            PRInstanceResourceMutationResult(
                instanceIdentifier: "fixture.one",
                resourceIdentifier: "mod.one",
                kind: .mods,
                action: .delete,
                outcome: .unknownResource,
                localizationKey: "instance.resource.missing",
                diagnosticText: "fixture resource is missing",
                partialChangesRolledBack: true
            )
        )
        XCTAssertTrue(model.apply(mutationResult: deleteFailure, instanceIdentifier: "fixture.one"))
        XCTAssertEqual(model.resources.map(\.id), ["mod.one", "mod.folder"])
        XCTAssertEqual(model.mutationFailure?.localizationKey, "instance.resource.missing")
        XCTAssertTrue(model.retry())
        XCTAssertEqual(mutationRequests.last?.2.action, .delete)
        model.dismissMutationFailure()
        XCTAssertNil(model.mutationFailure)

        let importURL = URL(fileURLWithPath: "/tmp/fixture-import.zip")
        XCTAssertTrue(model.importResources(from: [importURL]))
        XCTAssertEqual(mutationRequests.last?.2.action, .import)
        XCTAssertEqual(mutationRequests.last?.2.sourceURL, importURL)
        XCTAssertTrue(model.reveal("mod.folder"))
        XCTAssertEqual(mutationRequests.last?.2.action, .reveal)
    }

    func testInstanceResourcesModelRejectsInvalidOrStaleResults() throws {
        var mutationRequests: [PrismInstanceResourceMutationIntent] = []
        let model = PrismInstanceResourcesModel(onMutate: { mutationRequests.append($2) })
        XCTAssertTrue(model.beginLoading(identifier: "fixture.one", kind: .resourcePacks))
        let resource = try makeInstanceResource(
            identifier: "pack.one",
            name: "Fixture Pack",
            version: "1",
            fileName: "fixture-pack.zip",
            kind: .resourcePacks
        )
        XCTAssertTrue(model.apply(resources: [resource]))

        let invalidIdentifier = try XCTUnwrap(
            PRInstanceResource(
                identifier: " ",
                name: "Invalid",
                version: "1",
                fileName: "invalid.zip",
                provider: "Fixture",
                kind: .resourcePacks,
                enabled: true,
                canBeToggled: true,
                canBeDeleted: true,
                isDirectory: false,
                hasMetadata: false,
                problemDescriptions: []
            )
        )
        XCTAssertFalse(model.apply(resources: [invalidIdentifier]))
        XCTAssertEqual(model.resources.map(\.id), ["pack.one"])
        XCTAssertFalse(model.requestDelete("missing"))
        XCTAssertFalse(model.setEnabled(false, for: "missing"))
        let staleError = try XCTUnwrap(
            PRBridgeError(
                code: .dataUnavailable,
                localizationKey: "instance.resource.unavailable",
                substitutionValues: ["instanceIdentifier": "other.instance"],
                diagnosticText: "fixture resource unavailable",
                recoveryKind: .retry,
                partialChangesRolledBack: false
            )
        )
        XCTAssertFalse(model.apply(error: staleError, instanceIdentifier: "other.instance", kind: .resourcePacks))

        let wrongKind = try XCTUnwrap(
            PRInstanceResource(
                identifier: "mod.one",
                name: "Wrong Kind",
                version: "1",
                fileName: "wrong.zip",
                provider: "Fixture",
                kind: .mods,
                enabled: true,
                canBeToggled: true,
                canBeDeleted: true,
                isDirectory: false,
                hasMetadata: false,
                problemDescriptions: []
            )
        )
        XCTAssertFalse(model.apply(resources: [wrongKind]))
        XCTAssertFalse(model.importResources(from: [URL(string: "https://example.com/resource.zip")!]))
        XCTAssertTrue(mutationRequests.isEmpty)
    }

    func testInstanceResourcesSourceUsesNativeMutationRecoveryAPIs() throws {
        let contentSource = try contentSource()
        let shellModelSource = try shellModelSource()
        let bridgeModelsSource = try bridgeModelsSource()

        for requiredToken in [
            "PrismInstanceResourcesView",
            "Table(model.visibleResources, selection:",
            "TableColumn(\"Name\")",
            "Toggle(",
            ".searchable(",
            ".fileImporter(",
            ".dropDestination(for: URL.self)",
            ".confirmationDialog(",
            ".alert(",
            "role: .destructive",
            "prism.instance-resources.import",
            "prism.instance-resources.reveal",
            "prism.instance-resources.delete",
            ".accessibilityLabel(",
            ".accessibilityValue(",
            ".help("
        ] {
            XCTAssertTrue(contentSource.contains(requiredToken), "Missing native resource API: \(requiredToken)")
        }

        for requiredToken in [
            "PrismInstanceResource",
            "PrismInstanceResourcesModel",
            "PrismInstanceResourcesState",
            "PrismInstanceResourceMutationIntent",
            "beginLoading(identifier: String, kind:",
            "apply(resources bridgeResources:",
            "setEnabled(_ enabled: Bool, for identifier:",
            "requestDelete(",
            "confirmDelete()",
            "importResources(from urls:",
            "reveal(",
            "retry()",
            "partialChangesRolledBack"
        ] {
            XCTAssertTrue(shellModelSource.contains(requiredToken), "Missing resource state contract: \(requiredToken)")
        }
        XCTAssertTrue(bridgeModelsSource.contains("PRInstanceResourceMutationResult"), "Missing bridge mutation result contract")

        XCTAssertFalse(contentSource.contains("Canvas("))
        XCTAssertFalse(contentSource.contains("draw("))
        XCTAssertFalse(shellModelSource.contains("QWidget"))
        XCTAssertFalse(shellModelSource.contains("QDialog"))
        XCTAssertFalse(shellModelSource.contains("Unmanaged"))
        XCTAssertFalse(shellModelSource.contains("UnsafeMutable"))
    }

    func testInstanceSettingsModelConfirmsEditsAndPreservesDraftOnRejectedOrFailedSave() throws {
        var loadedIdentifiers: [String] = []
        var saveRequests: [(String, PrismInstanceSettings)] = []
        let model = PrismInstanceSettingsModel(
            onLoad: { loadedIdentifiers.append($0) },
            onSave: { saveRequests.append(($0, $1)) }
        )

        XCTAssertTrue(model.beginLoading(identifier: " fixture.one "))
        XCTAssertEqual(model.state, .loading(identifier: "fixture.one"))
        XCTAssertEqual(loadedIdentifiers, ["fixture.one"])

        let initialBridgeSettings = try makeInstanceSettings()
        XCTAssertTrue(model.apply(settings: initialBridgeSettings))
        XCTAssertEqual(model.settings?.windowWidth, 1280)
        XCTAssertEqual(model.settings?.modDownloadLoaders, ["Fabric", "Quilt"])
        XCTAssertEqual(model.settings?.joinTarget, .server)

        model.updateDraft { draft in
            draft.windowWidth = 1366
            draft.joinTarget = .world
            draft.joinWorld = "Fixture World"
        }
        XCTAssertTrue(model.isSaveAvailable)
        XCTAssertTrue(model.save())
        XCTAssertEqual(model.saveState, .saving)
        XCTAssertEqual(saveRequests.count, 1)
        XCTAssertEqual(saveRequests[0].0, "fixture.one")
        XCTAssertEqual(saveRequests[0].1.windowWidth, 1366)
        XCTAssertEqual(saveRequests[0].1.joinTarget, .world)

        let confirmedSettings = try makeInstanceSettings(windowWidth: 1440)
        XCTAssertTrue(
            model.apply(
                updateResult: try XCTUnwrap(
                    PRInstanceSettingsUpdateResult(
                        identifier: "fixture.one",
                        settings: confirmedSettings,
                        outcome: .succeeded
                    )
                )
            )
        )
        XCTAssertEqual(model.settings?.windowWidth, 1440)
        XCTAssertEqual(model.draft?.windowWidth, 1440)
        XCTAssertEqual(model.saveState, .idle)
        XCTAssertFalse(model.isSaveAvailable)

        model.updateDraft { $0.windowWidth = 1500 }
        XCTAssertTrue(model.save())
        XCTAssertTrue(
            model.apply(
                updateResult: try XCTUnwrap(
                    PRInstanceSettingsUpdateResult(
                        identifier: "fixture.one",
                        settings: nil,
                        outcome: .rejected
                    )
                )
            )
        )
        XCTAssertEqual(model.settings?.windowWidth, 1440)
        XCTAssertEqual(model.draft?.windowWidth, 1500)
        XCTAssertEqual(model.saveFailure?.localizationKey, "instance.settings.updateRejected")
        XCTAssertFalse(model.retrySave())

        model.updateDraft { $0.windowWidth = 1510 }
        XCTAssertTrue(model.save())
        let bridgeError = try XCTUnwrap(
            PRBridgeError(
                code: .dataUnavailable,
                localizationKey: "instance.settings.unavailable",
                substitutionValues: ["instanceIdentifier": "fixture.one"],
                diagnosticText: "fixture settings unavailable",
                recoveryKind: .retry,
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(model.apply(error: bridgeError, instanceIdentifier: " fixture.one "))
        XCTAssertEqual(model.settings?.windowWidth, 1440)
        XCTAssertEqual(model.draft?.windowWidth, 1510)
        XCTAssertTrue(model.saveFailure?.isRetryAvailable == true)
        XCTAssertTrue(model.retrySave())
        XCTAssertEqual(model.saveState, .saving)
        XCTAssertEqual(saveRequests.count, 4)
        XCTAssertEqual(saveRequests[3].1.windowWidth, 1510)

        XCTAssertFalse(
            model.apply(
                updateResult: try XCTUnwrap(
                    PRInstanceSettingsUpdateResult(
                        identifier: "other.instance",
                        settings: confirmedSettings,
                        outcome: .succeeded
                    )
                )
            )
        )
    }

    func testInstanceSettingsSourceUsesNativeFormControlsAndSafeBoundary() throws {
        let contentSource = try contentSource()
        let shellModelSource = try shellModelSource()

        for requiredToken in [
            "PrismInstanceSettingsView",
            "Form {",
            "Section(\"Game Window\")",
            "Section(\"Java\")",
            "Toggle(",
            "Stepper(",
            "Picker(\"Destination\"",
            "TextEditor(",
            "Save Settings",
            ".keyboardShortcut(.defaultAction)",
            "ContentUnavailableView",
            "ProgressView()",
            "prism.instance-settings.save",
            ".accessibilityLabel(",
            ".accessibilityValue(",
            ".help("
        ] {
            XCTAssertTrue(contentSource.contains(requiredToken), "Missing native instance settings API: \(requiredToken)")
        }

        for requiredToken in [
            "PrismInstanceSettings",
            "PrismInstanceSettingsModel",
            "PRInstanceSettings",
            "PRInstanceSettingsUpdateResult",
            "PrismInstanceSettingsState",
            "PrismInstanceSettingsSaveState",
            "beginLoading(identifier:",
            "apply(updateResult bridgeResult:",
            "isSaveAvailable",
            "retrySave()",
            "updateDraft",
            "partialChangesRolledBack"
        ] {
            XCTAssertTrue(shellModelSource.contains(requiredToken), "Missing instance settings state contract: \(requiredToken)")
        }

        XCTAssertFalse(contentSource.contains("Canvas("))
        XCTAssertFalse(contentSource.contains("draw("))
        XCTAssertFalse(contentSource.contains("Path("))
        XCTAssertFalse(shellModelSource.contains("QWidget"))
        XCTAssertFalse(shellModelSource.contains("QDialog"))
        XCTAssertFalse(shellModelSource.contains("Unmanaged"))
        XCTAssertFalse(shellModelSource.contains("UnsafeMutable"))
        XCTAssertFalse(shellModelSource.contains("EnvironmentVariables"))
    }

    func testInstanceDetailsSourceUsesNativeFormTextEditorAndRecoveryAPIs() throws {
        let contentSource = try contentSource()
        let shellModelSource = try shellModelSource()

        for requiredToken in [
            "PrismInstanceDetailsView",
            "Form {",
            "Section(\"Metadata\")",
            "LabeledContent",
            "TextEditor",
            ".textSelection(.enabled)",
            "Save Notes",
            ".keyboardShortcut(.defaultAction)",
            "ContentUnavailableView",
            "ProgressView()",
            "prism.instance-details.notes-editor",
            "prism.instance-details.save-notes",
            ".accessibilityLabel(",
            ".accessibilityValue(",
            ".help("
        ] {
            XCTAssertTrue(contentSource.contains(requiredToken), "Missing native instance detail API: \(requiredToken)")
        }

        for requiredToken in [
            "PrismInstanceDetails",
            "PrismInstanceDetailsModel",
            "PRInstanceDetails",
            "PRInstanceNotesUpdateResult",
            "PrismInstanceDetailsState",
            "PrismInstanceNotesSaveState",
            "beginLoading(identifier:",
            "apply(notesResult bridgeResult:",
            "isNotesSaveAvailable",
            "retryNotes()",
            "notesEditable",
            "partialChangesRolledBack"
        ] {
            XCTAssertTrue(shellModelSource.contains(requiredToken), "Missing instance detail state contract: \(requiredToken)")
        }

        XCTAssertFalse(contentSource.contains("Canvas("))
        XCTAssertFalse(contentSource.contains("draw("))
        XCTAssertFalse(contentSource.contains("Path("))
        XCTAssertFalse(shellModelSource.contains("QWidget"))
        XCTAssertFalse(shellModelSource.contains("QDialog"))
        XCTAssertFalse(shellModelSource.contains("Unmanaged"))
        XCTAssertFalse(shellModelSource.contains("UnsafeMutable"))
    }

    func testTaskPresentationMapsAllStatesProgressSubtasksAndTerminalMetadata() throws {
        let subtask = try XCTUnwrap(
            PRTaskSubtaskStatus(
                identifier: "subtask.fixture",
                name: "Download fixture",
                state: .running,
                progressKind: .determinate,
                progressFraction: 0.25
            )
        )
        let succeededResult = try XCTUnwrap(
            PRTaskTerminalResult(
                outcome: .succeeded,
                localizationKey: "task.completed",
                substitutionValues: ["taskIdentifier": "task.succeeded"],
                diagnosticText: nil,
                partialChangesRolledBack: false
            )
        )
        let failedResult = try XCTUnwrap(
            PRTaskTerminalResult(
                outcome: .failed,
                localizationKey: "task.failed",
                substitutionValues: ["taskIdentifier": "task.failed"],
                diagnosticText: "fixture failure",
                partialChangesRolledBack: true
            )
        )
        let cancelledResult = try XCTUnwrap(
            PRTaskTerminalResult(
                outcome: .cancelled,
                localizationKey: "task.cancelled",
                substitutionValues: [:],
                diagnosticText: nil,
                partialChangesRolledBack: false
            )
        )

        let queued = try XCTUnwrap(
            PrismTaskPresentation(
                bridgeStatus: try XCTUnwrap(
                    PRTaskStatus(
                        identifier: "task.queued",
                        title: nil,
                        state: .queued,
                        progressKind: .none,
                        progressFraction: 0,
                        cancellationAllowed: true,
                        subtasks: [],
                        terminalResult: nil
                    )
                )
            )
        )
        let running = try XCTUnwrap(
            PrismTaskPresentation(
                bridgeStatus: try XCTUnwrap(
                    PRTaskStatus(
                        identifier: "task.running",
                        title: "Fixture Task",
                        state: .running,
                        progressKind: .determinate,
                        progressFraction: 0.5,
                        cancellationAllowed: true,
                        subtasks: [subtask],
                        terminalResult: nil
                    )
                )
            )
        )
        let cancelling = try XCTUnwrap(
            PrismTaskPresentation(
                bridgeStatus: try XCTUnwrap(
                    PRTaskStatus(
                        identifier: "task.cancelling",
                        title: "Cancelling Task",
                        state: .cancelling,
                        progressKind: .indeterminate,
                        progressFraction: 0,
                        cancellationAllowed: false,
                        subtasks: [],
                        terminalResult: nil
                    )
                )
            )
        )
        let succeeded = try XCTUnwrap(
            PrismTaskPresentation(
                bridgeStatus: try XCTUnwrap(
                    PRTaskStatus(
                        identifier: "task.succeeded",
                        title: "Succeeded Task",
                        state: .succeeded,
                        progressKind: .determinate,
                        progressFraction: 1,
                        cancellationAllowed: false,
                        subtasks: [],
                        terminalResult: succeededResult
                    )
                )
            )
        )
        let failed = try XCTUnwrap(
            PrismTaskPresentation(
                bridgeStatus: try XCTUnwrap(
                    PRTaskStatus(
                        identifier: "task.failed",
                        title: "Failed Task",
                        state: .failed,
                        progressKind: .determinate,
                        progressFraction: 1,
                        cancellationAllowed: false,
                        subtasks: [],
                        terminalResult: failedResult
                    )
                )
            )
        )
        let cancelled = try XCTUnwrap(
            PrismTaskPresentation(
                bridgeStatus: try XCTUnwrap(
                    PRTaskStatus(
                        identifier: "task.cancelled",
                        title: "Cancelled Task",
                        state: .cancelled,
                        progressKind: .indeterminate,
                        progressFraction: 0,
                        cancellationAllowed: false,
                        subtasks: [],
                        terminalResult: cancelledResult
                    )
                )
            )
        )

        XCTAssertEqual(queued.state, .queued)
        XCTAssertEqual(queued.progress, .none)
        XCTAssertEqual(queued.title, "task.queued")
        XCTAssertTrue(queued.canCancel)
        XCTAssertEqual(running.state, .running)
        XCTAssertEqual(running.progress, .determinate(0.5))
        XCTAssertEqual(running.subtasks.map(\.id), ["subtask.fixture"])
        XCTAssertTrue(running.canCancel)
        XCTAssertEqual(cancelling.state, .cancelling)
        XCTAssertEqual(cancelling.progress, .indeterminate)
        XCTAssertFalse(cancelling.canCancel)
        XCTAssertEqual(succeeded.terminalResult?.outcome, .succeeded)
        XCTAssertEqual(failed.terminalResult?.diagnosticText, "fixture failure")
        XCTAssertTrue(failed.terminalResult?.partialChangesRolledBack == true)
        XCTAssertEqual(cancelled.terminalResult?.outcome, .cancelled)
        XCTAssertFalse(succeeded.canCancel || failed.canCancel || cancelled.canCancel)
    }

    func testTaskPresentationModelRoutesCancellationAndRetryWithStableIntents() throws {
        var intents: [PrismTaskCommandIntent] = []
        let model = PrismTaskPresentationModel(onTaskCommand: { intents.append($0) })
        let runningStatus = try XCTUnwrap(
            PRTaskStatus(
                identifier: "task.running",
                title: "Fixture Task",
                state: .running,
                progressKind: .determinate,
                progressFraction: 0.5,
                cancellationAllowed: true,
                subtasks: [],
                terminalResult: nil
            )
        )

        XCTAssertTrue(model.apply(status: runningStatus))
        XCTAssertTrue(model.isCancellationAvailable)
        XCTAssertTrue(model.cancel())
        XCTAssertFalse(model.isCancellationAvailable)
        XCTAssertFalse(model.cancel())
        XCTAssertEqual(
            intents,
            [PrismTaskCommandIntent(action: .cancel, identifier: "task.running")]
        )

        let cancellingStatus = try XCTUnwrap(
            PRTaskStatus(
                identifier: "task.running",
                title: "Fixture Task",
                state: .cancelling,
                progressKind: .indeterminate,
                progressFraction: 0,
                cancellationAllowed: false,
                subtasks: [],
                terminalResult: nil
            )
        )
        XCTAssertTrue(model.apply(status: cancellingStatus))
        XCTAssertFalse(model.isCancellationAvailable)

        let bridgeError = try XCTUnwrap(
            PRBridgeError(
                code: .networkUnavailable,
                localizationKey: "task.failed",
                substitutionValues: ["taskIdentifier": "task.failed"],
                diagnosticText: "fixture failure",
                recoveryKind: .retry,
                partialChangesRolledBack: true
            )
        )
        XCTAssertTrue(model.apply(error: bridgeError, taskIdentifier: "task.failed"))
        XCTAssertNil(model.task)
        XCTAssertTrue(model.isRetryAvailable)
        XCTAssertEqual(model.failure?.substitutionValues, ["taskIdentifier": "task.failed"])
        XCTAssertTrue(model.failure?.partialChangesRolledBack == true)
        XCTAssertTrue(model.retry())
        XCTAssertFalse(model.isRetryAvailable)
        XCTAssertEqual(
            intents,
            [
                PrismTaskCommandIntent(action: .cancel, identifier: "task.running"),
                PrismTaskCommandIntent(action: .retry, identifier: "task.failed"),
            ]
        )
    }

    func testTaskLogPresentationMapsBoundedFixtureValuesAndRendersPlainText() throws {
        let firstEntry = try XCTUnwrap(
            PRTaskLogEntry(sequence: 8, text: "first fixture line", truncated: false)
        )
        let secondEntry = try XCTUnwrap(
            PRTaskLogEntry(sequence: 9, text: "second fixture line", truncated: true)
        )
        let snapshot = try XCTUnwrap(
            PRTaskLogSnapshot(
                taskIdentifier: " task.logs ",
                entries: [firstEntry, secondEntry],
                droppedEntryCount: 8,
                totalByteCount: UInt64(firstEntry.text.utf8.count + secondEntry.text.utf8.count),
                truncated: true
            )
        )

        let presentation = try XCTUnwrap(PrismTaskLogPresentation(bridgeSnapshot: snapshot))
        XCTAssertEqual(presentation.id, "task.logs")
        XCTAssertEqual(presentation.entries.map(\.id), [8, 9])
        XCTAssertEqual(presentation.renderedText, "first fixture line\nsecond fixture line")
        XCTAssertEqual(presentation.droppedEntryCount, 8)
        XCTAssertTrue(presentation.isTruncated)
        XCTAssertNil(
            PRTaskLogSnapshot(
                taskIdentifier: "task.duplicate",
                entries: [firstEntry, firstEntry],
                droppedEntryCount: 0,
                totalByteCount: UInt64(firstEntry.text.utf8.count * 2),
                truncated: false
            )
        )
    }

    func testTaskLogPresentationModelRoutesRetryAndRejectsInvalidSnapshots() throws {
        var retriedIdentifiers: [String] = []
        let model = PrismTaskLogPresentationModel(onRetry: { retriedIdentifiers.append($0) })
        let entry = try XCTUnwrap(PRTaskLogEntry(sequence: 1, text: "fixture output", truncated: false))
        let snapshot = try XCTUnwrap(
            PRTaskLogSnapshot(
                taskIdentifier: "task.logs",
                entries: [entry],
                droppedEntryCount: 0,
                totalByteCount: UInt64(entry.text.utf8.count),
                truncated: false
            )
        )

        XCTAssertTrue(model.apply(snapshot: snapshot))
        XCTAssertEqual(model.log?.id, "task.logs")
        XCTAssertNil(model.failure)

        let error = try XCTUnwrap(
            PRBridgeError(
                code: .dataUnavailable,
                localizationKey: "bridge.error.dataUnavailable",
                substitutionValues: ["taskIdentifier": "task.logs"],
                diagnosticText: "fixture log unavailable",
                recoveryKind: .retry,
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(model.apply(error: error, taskIdentifier: " task.logs "))
        XCTAssertNil(model.log)
        XCTAssertTrue(model.failure?.isRetryAvailable == true)
        XCTAssertTrue(model.retry())
        XCTAssertEqual(retriedIdentifiers, ["task.logs"])
        XCTAssertFalse(model.retry())
        XCTAssertFalse(model.apply(error: error, taskIdentifier: "   "))
    }

    func testTaskPresentationSourceUsesSystemProgressAndRecoveryAPIs() throws {
        let contentSource = try contentSource()
        let shellModelSource = try shellModelSource()

        for requiredToken in [
            "PrismTaskProgressView",
            "ProgressView(value:",
            "ProgressView()",
            "List(task.subtasks)",
            "ContentUnavailableView",
            "LocalizedStringKey(task.state.titleKey)",
            ".accessibilityValue(",
            ".accessibilityIdentifier(\"prism.task."
        ] {
            XCTAssertTrue(contentSource.contains(requiredToken), "Missing native task API: \(requiredToken)")
        }

        for requiredToken in [
            "PrismTaskPresentation",
            "PrismTaskPresentationModel",
            "PRTaskStatus",
            "PRBridgeError",
            "isCancellationAvailable",
            "apply(status:",
            "apply(error:",
            "PrismTaskCommandIntent"
        ] {
            XCTAssertTrue(shellModelSource.contains(requiredToken), "Missing task state contract: \(requiredToken)")
        }

        XCTAssertFalse(contentSource.contains("Canvas("))
        XCTAssertFalse(contentSource.contains("draw("))
        XCTAssertFalse(contentSource.contains("Path("))
        XCTAssertFalse(shellModelSource.contains("Unmanaged"))
        XCTAssertFalse(shellModelSource.contains("UnsafeMutable"))
    }

    func testTaskLogSourceUsesBoundedFoundationStateAndStandardTextPresentation() throws {
        let contentSource = try contentSource()
        let shellModelSource = try shellModelSource()

        for requiredToken in [
            "PrismTaskLogView",
            "PrismTaskLogTextView",
            "NSViewRepresentable",
            "NSTextView",
            "NSScrollView",
            "isEditable = false",
            "isSelectable = true",
            "usesFindBar = true",
            "ContentUnavailableView",
            "prism.task-log.",
            "Older log entries were omitted.",
            ".accessibilityLabel(Text(\"Task Log Output\"))",
            ".accessibilityValue(Text(log.accessibilityValueKey))"
        ] {
            XCTAssertTrue(contentSource.contains(requiredToken), "Missing native log API: \(requiredToken)")
        }

        for requiredToken in [
            "PrismTaskLogEntry",
            "PrismTaskLogPresentation",
            "PrismTaskLogPresentationModel",
            "PRTaskLogSnapshot",
            "droppedEntryCount",
            "totalByteCount",
            "apply(snapshot:",
            "apply(error:"
        ] {
            XCTAssertTrue(shellModelSource.contains(requiredToken), "Missing log state contract: \(requiredToken)")
        }

        XCTAssertFalse(contentSource.contains("ScrollView(.vertical)"))
        XCTAssertFalse(contentSource.contains("Text(log.renderedText)"))
        XCTAssertFalse(contentSource.contains("Canvas("))
        XCTAssertFalse(contentSource.contains("draw("))
        XCTAssertFalse(contentSource.contains("Path("))
        XCTAssertFalse(shellModelSource.contains("Unmanaged"))
        XCTAssertFalse(shellModelSource.contains("UnsafeMutable"))
    }

    func testSelectionUsesStableInstanceIdentifiersAcrossSortingAndSearch() {
        let model = PrismShellModel()
        model.setInstances(fixtureInstances())

        model.selectInstanceID(" fixture.zeta ")
        XCTAssertEqual(model.selectedInstanceID, "fixture.zeta")

        model.setSortOrder(.nameDescending)
        model.setSearchText("alpha")
        XCTAssertEqual(model.selectedInstanceID, "fixture.zeta")

        model.selectInstanceID("missing")
        XCTAssertNil(model.selectedInstanceID)
    }

    func testSortingIsCaseInsensitiveWithStableIdentifierTieBreakers() {
        let model = PrismShellModel()
        model.setInstances(fixtureInstances())

        XCTAssertEqual(
            model.visibleInstances.map(\.id),
            ["fixture.alpha", "fixture.alpha-lower", "fixture.moon", "fixture.zeta"]
        )

        model.setSortOrder(.nameDescending)
        XCTAssertEqual(
            model.visibleInstances.map(\.id),
            ["fixture.zeta", "fixture.moon", "fixture.alpha", "fixture.alpha-lower"]
        )
    }

    func testGroupingProducesDeterministicSectionsAndUngroupedBucket() {
        let model = PrismShellModel()
        model.setInstances(fixtureInstances())
        model.setGrouping(.group)

        XCTAssertEqual(
            model.visibleInstanceSections.map(\.title),
            ["Alpha", "Beta", "Ungrouped"]
        )
        XCTAssertEqual(
            model.visibleInstanceSections.map(\.id),
            ["group:Alpha", "group:Beta", "group:Ungrouped"]
        )
        XCTAssertEqual(
            model.visibleInstanceSections.flatMap { $0.instances }.map(\.id),
            ["fixture.alpha", "fixture.alpha-lower", "fixture.zeta", "fixture.moon"]
        )
    }

    func testSearchMatchesNameIdentifierAndGroupAndSupportsEmptyResults() {
        let model = PrismShellModel()
        model.setInstances(fixtureInstances())

        model.setSearchText("  MOON ")
        XCTAssertEqual(model.visibleInstances.map(\.id), ["fixture.moon"])

        model.setSearchText("fixture.alpha")
        XCTAssertEqual(
            model.visibleInstances.map(\.id),
            ["fixture.alpha", "fixture.alpha-lower"]
        )

        model.setSearchText("beta")
        XCTAssertEqual(model.visibleInstances.map(\.id), ["fixture.zeta"])

        model.setSearchText("does-not-exist")
        XCTAssertTrue(model.visibleInstances.isEmpty)
        XCTAssertTrue(model.visibleInstanceSections.isEmpty)
    }

    func testTenTimesFixtureVolumePreservesUniqueRowsAndSelectionIdentity() {
        let model = PrismShellModel()
        let instances = (0..<100).compactMap { index in
            PrismInstanceRow(
                id: String(format: "fixture.%03d", index),
                name: String(format: "Instance %03d", index),
                group: index.isMultiple(of: 2) ? "Even" : "Odd"
            )
        }
        model.setInstances(instances)
        model.setGrouping(.group)
        model.selectInstanceID("fixture.042")

        XCTAssertEqual(model.instances.count, 100)
        XCTAssertEqual(Set(model.visibleInstances.map(\.id)).count, 100)
        XCTAssertEqual(model.selectedInstanceID, "fixture.042")

        model.setSortOrder(.nameDescending)
        XCTAssertEqual(model.visibleInstances.count, 100)
        XCTAssertEqual(model.selectedInstanceID, "fixture.042")
    }

    func testArtworkStoreLoadsOnlyValidTemporaryFileArtwork() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let artworkURL = fixtureRoot.urlForRelativePath("artwork/fixture.png")
        try FileManager.default.createDirectory(
            at: artworkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fixturePNG().write(to: artworkURL, options: .atomic)

        let invalidURL = fixtureRoot.urlForRelativePath("artwork/invalid.png")
        try Data("not an image".utf8).write(to: invalidURL, options: .atomic)

        let store = try XCTUnwrap(
            PrismInstanceArtworkStore(maxItemCount: 2, maxTotalBytes: fixturePNG().count * 2)
        )

        XCTAssertNotNil(store.image(for: " fixture.one ", from: artworkURL))
        XCTAssertEqual(store.cachedIdentifiers, ["fixture.one"])
        XCTAssertNotNil(store.image(for: "fixture.one", from: artworkURL))
        XCTAssertNil(store.image(for: "", from: artworkURL))
        XCTAssertNil(store.image(for: "fixture.invalid", from: invalidURL))
        XCTAssertNil(store.image(for: "fixture.missing", from: fixtureRoot.urlForRelativePath("missing.png")))
        XCTAssertNil(
            store.image(
                for: "fixture.remote",
                from: URL(string: "https://example.invalid/fixture.png")!
            )
        )
        XCTAssertTrue(fixtureRoot.isInsideTemporaryDirectory)
        XCTAssertTrue(fixtureRoot.isOutsideUpstreamApplicationSupport)
    }

    func testArtworkStoreEvictsLeastRecentlyUsedEntriesWithinCountAndByteLimits() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let artworkURL = fixtureRoot.urlForRelativePath("artwork/fixture.png")
        try FileManager.default.createDirectory(
            at: artworkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let artworkData = fixturePNG()
        try artworkData.write(to: artworkURL, options: .atomic)

        let store = try XCTUnwrap(
            PrismInstanceArtworkStore(maxItemCount: 2, maxTotalBytes: artworkData.count * 2)
        )
        XCTAssertNotNil(store.image(for: "fixture.one", from: artworkURL))
        XCTAssertNotNil(store.image(for: "fixture.two", from: artworkURL))
        XCTAssertNotNil(store.image(for: "fixture.one", from: artworkURL))
        XCTAssertNotNil(store.image(for: "fixture.three", from: artworkURL))

        XCTAssertEqual(store.cachedIdentifiers, ["fixture.one", "fixture.three"])
        XCTAssertLessThanOrEqual(store.cachedIdentifiers.count, 2)
        XCTAssertLessThanOrEqual(store.cachedByteCount, artworkData.count * 2)

        store.removeArtwork(for: " fixture.one ")
        XCTAssertEqual(store.cachedIdentifiers, ["fixture.three"])
        store.removeAll()
        XCTAssertTrue(store.cachedIdentifiers.isEmpty)
        XCTAssertEqual(store.cachedByteCount, 0)
    }

    func testArtworkStoreStaysBoundedAtTenTimesDefaultFixtureVolume() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let artworkURL = fixtureRoot.urlForRelativePath("artwork/fixture.png")
        try FileManager.default.createDirectory(
            at: artworkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fixturePNG().write(to: artworkURL, options: .atomic)

        let store = try XCTUnwrap(PrismInstanceArtworkStore())
        for index in 0..<(PrismInstanceArtworkStore.defaultItemLimit * 10) {
            XCTAssertNotNil(store.image(for: "fixture.\(index)", from: artworkURL))
        }

        XCTAssertEqual(store.cachedIdentifiers.count, PrismInstanceArtworkStore.defaultItemLimit)
        XCTAssertLessThanOrEqual(store.cachedByteCount, PrismInstanceArtworkStore.defaultTotalByteLimit)
        XCTAssertEqual(
            store.cachedIdentifiers.first,
            "fixture.\(PrismInstanceArtworkStore.defaultItemLimit * 9)"
        )
    }

    func testArtworkStoreRejectsInvalidBoundsAndUsesSystemImageContentAPIs() throws {
        XCTAssertNil(PrismInstanceArtworkStore(maxItemCount: 0, maxTotalBytes: 1))
        XCTAssertNil(PrismInstanceArtworkStore(maxItemCount: 1, maxTotalBytes: 0))

        let contentSource = try contentSource()
        let shellModelSource = try shellModelSource()

        for requiredToken in [
            "PrismInstanceArtworkView",
            "Image(nsImage:",
            ".resizable()",
            ".scaledToFit()",
            ".accessibilityLabel(",
            "prism.instance-artwork"
        ] {
            XCTAssertTrue(contentSource.contains(requiredToken), "Missing native artwork API: \(requiredToken)")
        }

        for requiredToken in [
            "PrismInstanceArtworkStore",
            "NSImage(data:",
            ".fileSizeKey",
            "maxItemCount",
            "maxTotalBytes",
            "cachedByteCount",
            "trimToLimits()",
            "accessOrder"
        ] {
            XCTAssertTrue(shellModelSource.contains(requiredToken), "Missing bounded artwork contract: \(requiredToken)")
        }

        XCTAssertFalse(contentSource.contains("Canvas("))
        XCTAssertFalse(contentSource.contains("draw("))
        XCTAssertFalse(contentSource.contains("Path("))
    }

    func testContentSourceUsesSystemSidebarDetailAndContentStateAPIs() throws {
        let source = try contentSource()

        for requiredToken in [
            "NavigationSplitView",
            "List(",
            "selection:",
            ".tag(",
            ".listStyle(.sidebar)",
            ".searchable(",
            "ContentUnavailableView(",
            "ContentUnavailableView {",
            "ProgressView(",
            "Button {",
            ".accessibilityLabel(",
            ".accessibilityValue(",
            ".help(",
            ".accessibilityHint(",
            ".accessibilityIdentifier("
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native shell API: \(requiredToken)")
        }

        XCTAssertFalse(source.contains("Canvas("))
        XCTAssertFalse(source.contains("draw("))
        XCTAssertFalse(source.contains(".task("))
        XCTAssertFalse(source.contains("Task {"))
    }

    func testSidebarSelectionUsesSystemListFocusAndAccessibilityValueSemantics() throws {
        let source = try contentSource()

        for requiredToken in [
            "List(",
            "selection:",
            "Binding<PrismShellSidebarItem?>",
            ".tag(item)",
            ".listStyle(.sidebar)",
            ".accessibilityValue(Text(LocalizedStringKey(item.titleKey)))"
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native selection contract: \(requiredToken)")
        }

        XCTAssertFalse(source.contains("FocusState"))
        XCTAssertFalse(source.contains(".accessibilityElement("))
        XCTAssertFalse(source.contains("Canvas("))
        XCTAssertFalse(source.contains("draw("))
    }

    func testShellModelSourceDefinesSearchGroupingAndSortingState() throws {
        let source = try shellModelSource()

        for requiredToken in [
            "PrismInstanceGrouping",
            "PrismInstanceSortOrder",
            "PrismShellFailure",
            "PrismShellRecoveryAction",
            "visibleInstanceSections",
            "isRetryAvailable",
            "recoveryAction",
            "retry()",
            "setSearchText(",
            "setGrouping(",
            "setSortOrder("
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing instance state contract: \(requiredToken)")
        }
    }

    private func fixtureInstances() -> [PrismInstanceRow] {
        [
            PrismInstanceRow(id: "fixture.zeta", name: "Zeta", group: "Beta"),
            PrismInstanceRow(id: "fixture.alpha", name: "Alpha", group: "Alpha"),
            PrismInstanceRow(id: "fixture.alpha-lower", name: "alpha", group: "Alpha"),
            PrismInstanceRow(id: "fixture.moon", name: "Moon")
        ].compactMap { $0 }
    }

    private func fixturePNG() -> Data {
        Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
    }

    private func contentSource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("PrismNative/App/ContentView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func shellModelSource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("PrismNative/App/PrismShellModel.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func bridgeModelsSource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("PrismNative/Bridge/PrismBridgeModels.h")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
