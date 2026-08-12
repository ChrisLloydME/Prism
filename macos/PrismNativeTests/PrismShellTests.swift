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

    private func makeInstanceWorld(
        identifier: String,
        name: String,
        folderName: String,
        gameMode: String = "Survival",
        iconKey: String? = nil,
        warningDescription: String? = nil,
        lastPlayedUnixSeconds: Int = 0,
        sizeBytes: UInt64 = 0,
        seed: Int64? = nil,
        isArchive: Bool = false,
        canBeRenamed: Bool = true,
        canBeCopied: Bool = true,
        canBeDeleted: Bool = true,
        canBeJoined: Bool = true,
        hasIcon: Bool = false
    ) throws -> PRInstanceWorld {
        try XCTUnwrap(
            PRInstanceWorld(
                identifier: identifier,
                name: name,
                folderName: folderName,
                gameMode: gameMode,
                iconKey: iconKey,
                warningDescription: warningDescription,
                lastPlayedUnixSeconds: lastPlayedUnixSeconds,
                sizeBytes: sizeBytes,
                seed: seed.map(NSNumber.init(value:)),
                isArchive: isArchive,
                canBeRenamed: canBeRenamed,
                canBeCopied: canBeCopied,
                canBeDeleted: canBeDeleted,
                canBeJoined: canBeJoined,
                hasIcon: hasIcon
            )
        )
    }

    private func makeInstanceServer(
        identifier: String,
        name: String,
        address: String,
        resourcePolicy: PRInstanceServerResourcePolicy = .ask,
        status: PRInstanceServerStatus = .unknown,
        onlinePlayers: Int = -1,
        canBeEdited: Bool = true,
        canBeDeleted: Bool = true,
        canBeJoined: Bool = true
    ) throws -> PRInstanceServer {
        try XCTUnwrap(
            PRInstanceServer(
                identifier: identifier,
                name: name,
                address: address,
                resourcePolicy: resourcePolicy,
                status: status,
                onlinePlayers: onlinePlayers,
                canBeEdited: canBeEdited,
                canBeDeleted: canBeDeleted,
                canBeJoined: canBeJoined
            )
        )
    }

    private func makeInstanceScreenshot(
        identifier: String,
        fileName: String,
        displayName: String,
        modifiedUnixSeconds: Int = 0,
        sizeBytes: UInt64 = 0,
        readable: Bool = true,
        writable: Bool = true
    ) throws -> PRInstanceScreenshot {
        try XCTUnwrap(
            PRInstanceScreenshot(
                identifier: identifier,
                fileName: fileName,
                displayName: displayName,
                modifiedUnixSeconds: modifiedUnixSeconds,
                sizeBytes: sizeBytes,
                readable: readable,
                writable: writable
            )
        )
    }

    private func makeInstanceLogFile(
        identifier: String,
        fileName: String,
        displayName: String,
        compressed: Bool = false,
        current: Bool = false,
        readable: Bool = true,
        canBeDeleted: Bool = true
    ) throws -> PRInstanceLogFile {
        try XCTUnwrap(
            PRInstanceLogFile(
                identifier: identifier,
                fileName: fileName,
                displayName: displayName,
                modifiedUnixSeconds: 1,
                sizeBytes: 64,
                compressed: compressed,
                current: current,
                readable: readable,
                canBeDeleted: canBeDeleted
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

    func testShellModelLoadsProductionBridgeSnapshotsAndAppliesChanges() throws {
        let fixtureRoot = try PrismTemporaryFixtureRoot()
        let bridge: PRPrismBridge = try XCTUnwrap(
            PRPrismBridge(dataRootURL: fixtureRoot.url, cancellationHandler: nil, shutdownHandler: nil)
        )
        let model = PrismShellModel(bridge: bridge)
        let createExpectation = expectation(description: "production shell instance creation")

        var createToken: PRBridgeObservationToken?
        createToken = bridge.createMetadataOnlyInstance(
            withIdentifier: "native.shell",
            name: "Native Shell",
            iconKey: "default"
        ) { summary, error in
            XCTAssertNil(error)
            XCTAssertEqual(summary?.identifier, "native.shell")
            createExpectation.fulfill()
        }
        wait(for: [createExpectation], timeout: 3)
        XCTAssertNotNil(createToken)

        let deadline = Date().addingTimeInterval(3)
        while model.instances.first?.id != "native.shell" && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertEqual(model.instances.map(\.id), ["native.shell"])
        XCTAssertEqual(model.instances.first?.name, "Native Shell")
        XCTAssertEqual(model.detailState, .content)
        XCTAssertTrue(bridge.shutdown())
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

    func testDetailMutationBridgeErrorsPreserveRecoveryAndOptimisticRollback() throws {
        var resourceMutations: [PrismInstanceResourceMutationIntent] = []
        let resourcesModel = PrismInstanceResourcesModel(onMutate: { resourceMutations.append($2) })
        XCTAssertTrue(resourcesModel.beginLoading(identifier: "fixture.one", kind: .mods))
        let resource = try makeInstanceResource(
            identifier: "mod.one",
            name: "Fixture Mod",
            version: "1.0",
            fileName: "fixture-mod.jar"
        )
        XCTAssertTrue(resourcesModel.apply(resources: [resource]))
        XCTAssertTrue(resourcesModel.setEnabled(false, for: "mod.one"))
        let resourceError = try XCTUnwrap(
            PRBridgeError(
                code: .permissionDenied,
                localizationKey: "instance.resource.permissionDenied",
                substitutionValues: ["instanceIdentifier": "fixture.one"],
                diagnosticText: "fixture permission failure",
                recoveryKind: .retry,
                partialChangesRolledBack: true
            )
        )
        XCTAssertTrue(resourcesModel.apply(mutationError: resourceError, instanceIdentifier: "fixture.one"))
        XCTAssertEqual(resourcesModel.mutationFailure?.localizationKey, "instance.resource.permissionDenied")
        XCTAssertTrue(resourcesModel.mutationFailure?.partialChangesRolledBack == true)
        XCTAssertTrue(resourcesModel.retry())
        XCTAssertEqual(resourceMutations.count, 2)

        var serverMutations: [PrismInstanceDetailMutationIntent] = []
        let serversModel = PrismInstanceServersModel(onMutate: { serverMutations.append($1) })
        XCTAssertTrue(serversModel.beginLoading(identifier: "fixture.one"))
        let server = try makeInstanceServer(
            identifier: "server.one",
            name: "Original",
            address: "original.example:25565"
        )
        XCTAssertTrue(serversModel.apply(servers: [server]))
        serversModel.selectServer("server.one")
        serversModel.setDraftName("Optimistic")
        XCTAssertTrue(serversModel.updateSelected())
        XCTAssertEqual(serversModel.servers.first?.name, "Optimistic")
        let serverError = try XCTUnwrap(
            PRBridgeError(
                code: .dataUnavailable,
                localizationKey: "instance.server.unavailable",
                substitutionValues: ["instanceIdentifier": "fixture.one"],
                diagnosticText: "fixture server failure",
                recoveryKind: .retry,
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(serversModel.apply(mutationError: serverError, instanceIdentifier: "fixture.one"))
        XCTAssertEqual(serversModel.servers.first?.name, "Original")
        XCTAssertEqual(serversModel.mutationFailure?.localizationKey, "instance.server.unavailable")
        XCTAssertTrue(serversModel.retry())
        XCTAssertEqual(serverMutations.count, 2)
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

    func testInstanceWorldsAndServersModelsPreserveOrderAndRequireConfirmedActions() throws {
        var worldLoads: [String] = []
        var worldMutations: [(String, PrismInstanceDetailMutationIntent)] = []
        let worldsModel = PrismInstanceWorldsModel(
            onLoad: { worldLoads.append($0) },
            onMutate: { worldMutations.append(($0, $1)) }
        )

        XCTAssertTrue(worldsModel.beginLoading(identifier: " fixture.one "))
        XCTAssertEqual(worldLoads, ["fixture.one"])
        let worldZeta = try makeInstanceWorld(
            identifier: "world.zeta",
            name: "Zeta",
            folderName: "zeta",
            iconKey: " icon.zeta ",
            warningDescription: " Warning ",
            lastPlayedUnixSeconds: 100,
            sizeBytes: 4_096,
            seed: 123,
            hasIcon: true
        )
        let worldArchive = try makeInstanceWorld(
            identifier: "world.archive",
            name: "Archive",
            folderName: "archive.zip",
            gameMode: "",
            isArchive: true,
            canBeRenamed: false,
            canBeDeleted: false,
            canBeJoined: false
        )

        XCTAssertTrue(worldsModel.apply(worlds: [worldZeta, worldArchive]))
        XCTAssertEqual(worldsModel.worlds.map(\.id), ["world.zeta", "world.archive"])
        XCTAssertEqual(worldsModel.worlds[0].iconKey, "icon.zeta")
        XCTAssertEqual(worldsModel.worlds[0].warningDescription, "Warning")
        XCTAssertEqual(worldsModel.worlds[0].seed, 123)
        XCTAssertTrue(worldsModel.worlds[1].isArchive)
        worldsModel.selectWorld("world.zeta")
        worldsModel.setSearchText("warning")
        XCTAssertEqual(worldsModel.visibleWorlds.map(\.id), ["world.zeta"])
        worldsModel.setSearchText("archive")
        XCTAssertNil(worldsModel.selectedWorldID)
        worldsModel.setSearchText("")

        XCTAssertTrue(worldsModel.importWorld(from: URL(fileURLWithPath: "/tmp/world-import.zip")))
        XCTAssertEqual(worldMutations.last?.1.action, .import)
        XCTAssertEqual(worldMutations.last?.1.sourceURL?.path, "/tmp/world-import.zip")
        XCTAssertTrue(worldsModel.apply(worlds: [worldZeta, worldArchive]))

        XCTAssertTrue(worldsModel.requestDelete("world.zeta"))
        XCTAssertEqual(worldsModel.pendingDeleteWorldID, "world.zeta")
        XCTAssertTrue(worldsModel.confirmDelete())
        XCTAssertEqual(worldMutations.last?.1.action, .delete)
        XCTAssertTrue(worldMutations.last?.1.confirmed == true)
        XCTAssertEqual(worldsModel.worlds.map(\.id), ["world.zeta", "world.archive"])

        let rejectedDelete = try XCTUnwrap(
            PRInstanceDetailMutationResult(
                kind: .worlds,
                action: .delete,
                outcome: .rejected,
                instanceIdentifier: "fixture.one",
                itemIdentifier: "world.zeta",
                localizationKey: "instance.world.deleteRejected",
                diagnosticText: "fixture deletion rejected",
                partialChangesRolledBack: true
            )
        )
        XCTAssertTrue(worldsModel.apply(mutationResult: rejectedDelete, instanceIdentifier: "fixture.one"))
        XCTAssertEqual(worldsModel.mutationFailure?.localizationKey, "instance.world.deleteRejected")
        XCTAssertTrue(worldsModel.mutationFailure?.partialChangesRolledBack == true)
        XCTAssertTrue(worldsModel.retry())
        XCTAssertEqual(worldMutations.last?.1.action, .delete)

        var serverLoads: [String] = []
        var serverMutations: [(String, PrismInstanceDetailMutationIntent)] = []
        let serversModel = PrismInstanceServersModel(
            onLoad: { serverLoads.append($0) },
            onMutate: { serverMutations.append(($0, $1)) }
        )
        XCTAssertTrue(serversModel.beginLoading(identifier: "fixture.one"))
        let serverA = try makeInstanceServer(
            identifier: "server.a",
            name: "Alpha",
            address: "alpha.example:25565",
            resourcePolicy: .always,
            status: .online,
            onlinePlayers: 4
        )
        let serverB = try makeInstanceServer(
            identifier: "server.b",
            name: "Beta",
            address: "beta.example:25565",
            status: .offline,
            canBeDeleted: false
        )
        XCTAssertTrue(serversModel.apply(servers: [serverA, serverB]))
        XCTAssertEqual(serversModel.servers.map(\.id), ["server.a", "server.b"])
        XCTAssertEqual(serversModel.servers[0].resourcePolicy, .always)
        XCTAssertEqual(serversModel.servers[0].status, .online)
        XCTAssertEqual(serversModel.servers[1].onlinePlayers, -1)
        serversModel.selectServer("server.a")
        XCTAssertEqual(serversModel.draftName, "Alpha")
        serversModel.setDraftName("Alpha Updated")
        serversModel.setDraftAddress("updated.example:25565")
        serversModel.setDraftResourcePolicy(.never)
        XCTAssertTrue(serversModel.updateSelected())
        XCTAssertEqual(serverMutations.last?.1.action, .update)
        XCTAssertEqual(serverMutations.last?.1.itemIdentifier, "server.a")
        XCTAssertEqual(serverMutations.last?.1.name, "Alpha Updated")
        XCTAssertEqual(serverMutations.last?.1.resourcePolicy, .never)
        XCTAssertEqual(serversModel.servers[0].name, "Alpha Updated")
        XCTAssertEqual(serversModel.servers[0].address, "updated.example:25565")
        XCTAssertEqual(serversModel.servers[0].resourcePolicy, .never)
        XCTAssertEqual(serversModel.servers.map(\.id), ["server.a", "server.b"])

        let updated = try XCTUnwrap(
            PRInstanceDetailMutationResult(
                kind: .servers,
                action: .update,
                outcome: .succeeded,
                instanceIdentifier: "fixture.one",
                itemIdentifier: "server.a",
                localizationKey: "instance.server.updated",
                diagnosticText: nil,
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(serversModel.apply(mutationResult: updated, instanceIdentifier: "fixture.one"))
        XCTAssertEqual(serversModel.state, .loading(identifier: "fixture.one"))
        XCTAssertEqual(serverLoads, ["fixture.one", "fixture.one"])

        XCTAssertTrue(serversModel.apply(servers: [serverA, serverB]))
        XCTAssertTrue(serversModel.moveDown("server.a"))
        XCTAssertEqual(serverMutations.last?.1.action, .moveDown)
        XCTAssertEqual(serverMutations.last?.1.position, 0)
        XCTAssertEqual(serversModel.servers.map(\.id), ["server.b", "server.a"])
        let moved = try XCTUnwrap(
            PRInstanceDetailMutationResult(
                kind: .servers,
                action: .moveDown,
                outcome: .succeeded,
                instanceIdentifier: "fixture.one",
                itemIdentifier: "server.a",
                localizationKey: "instance.server.moved",
                diagnosticText: nil,
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(serversModel.apply(mutationResult: moved, instanceIdentifier: "fixture.one"))
        XCTAssertEqual(serversModel.state, .loading(identifier: "fixture.one"))
        XCTAssertTrue(serversModel.apply(servers: [serverA, serverB]))
        XCTAssertTrue(serversModel.requestDelete("server.a"))
        XCTAssertTrue(serversModel.confirmDelete())
        XCTAssertEqual(serverMutations.last?.1.action, .delete)
        XCTAssertTrue(serverMutations.last?.1.confirmed == true)
        XCTAssertFalse(serversModel.requestDelete("server.b"))
    }

    func testInstanceServersModelRollsBackSafeOptimisticEdits() throws {
        XCTAssertEqual(
            PrismInstanceDetailMutationPresentationPolicy.policy(for: .servers, action: .update),
            .optimisticServerEdit
        )
        XCTAssertEqual(
            PrismInstanceDetailMutationPresentationPolicy.policy(for: .servers, action: .moveUp),
            .optimisticServerEdit
        )
        XCTAssertEqual(
            PrismInstanceDetailMutationPresentationPolicy.policy(for: .servers, action: .moveDown),
            .optimisticServerEdit
        )
        XCTAssertEqual(
            PrismInstanceDetailMutationPresentationPolicy.policy(for: .servers, action: .delete),
            .confirmedBackendState
        )
        XCTAssertEqual(
            PrismInstanceDetailMutationPresentationPolicy.policy(for: .worlds, action: .delete),
            .confirmedBackendState
        )
        XCTAssertEqual(
            PrismInstanceDetailMutationPresentationPolicy.policy(for: .screenshots, action: .rename),
            .confirmedBackendState
        )

        var mutations: [PrismInstanceDetailMutationIntent] = []
        let model = PrismInstanceServersModel(onMutate: { mutations.append($1) })
        XCTAssertTrue(model.beginLoading(identifier: "fixture.one"))
        let serverA = try makeInstanceServer(
            identifier: "server.a",
            name: "Alpha",
            address: "alpha.example:25565",
            resourcePolicy: .always,
            status: .online,
            onlinePlayers: 4
        )
        let serverB = try makeInstanceServer(
            identifier: "server.b",
            name: "Beta",
            address: "beta.example:25565",
            status: .offline
        )
        XCTAssertTrue(model.apply(servers: [serverA, serverB]))
        model.selectServer("server.a")
        model.setDraftName("Alpha Updated")
        model.setDraftAddress("updated.example:25565")
        model.setDraftResourcePolicy(.never)

        XCTAssertTrue(model.updateSelected())
        XCTAssertEqual(model.servers[0].name, "Alpha Updated")
        XCTAssertEqual(model.servers[0].address, "updated.example:25565")
        XCTAssertEqual(model.servers[0].resourcePolicy, .never)
        XCTAssertFalse(model.updateSelected(), "A second edit must not replace the pending optimistic transaction")

        let rejectedUpdate = try XCTUnwrap(
            PRInstanceDetailMutationResult(
                kind: .servers,
                action: .update,
                outcome: .rejected,
                instanceIdentifier: "fixture.one",
                itemIdentifier: "server.a",
                localizationKey: "instance.server.updateRejected",
                diagnosticText: "fixture update rejected",
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(model.apply(mutationResult: rejectedUpdate, instanceIdentifier: "fixture.one"))
        XCTAssertEqual(model.servers.map(\.id), ["server.a", "server.b"])
        XCTAssertEqual(model.servers[0].name, "Alpha")
        XCTAssertEqual(model.servers[0].address, "alpha.example:25565")
        XCTAssertEqual(model.servers[0].resourcePolicy, .always)
        XCTAssertEqual(model.draftName, "Alpha Updated")
        XCTAssertEqual(model.draftAddress, "updated.example:25565")
        XCTAssertEqual(model.draftResourcePolicy, .never)
        XCTAssertEqual(model.mutationFailure?.localizationKey, "instance.server.updateRejected")
        XCTAssertFalse(model.mutationFailure?.partialChangesRolledBack == true)

        XCTAssertTrue(model.retry())
        XCTAssertEqual(model.servers[0].name, "Alpha Updated")
        XCTAssertEqual(mutations.map(\.action), [.update, .update])
        let updated = try XCTUnwrap(
            PRInstanceDetailMutationResult(
                kind: .servers,
                action: .update,
                outcome: .succeeded,
                instanceIdentifier: "fixture.one",
                itemIdentifier: "server.a",
                localizationKey: "instance.server.updated",
                diagnosticText: nil,
                partialChangesRolledBack: false
            )
        )
        XCTAssertTrue(model.apply(mutationResult: updated, instanceIdentifier: "fixture.one"))
        XCTAssertTrue(model.apply(servers: [serverA, serverB]))

        XCTAssertTrue(model.moveDown("server.a"))
        XCTAssertEqual(model.servers.map(\.id), ["server.b", "server.a"])
        XCTAssertFalse(model.moveUp("server.a"), "A concurrent reorder must wait for the pending result")
        let rejectedMove = try XCTUnwrap(
            PRInstanceDetailMutationResult(
                kind: .servers,
                action: .moveDown,
                outcome: .failed,
                instanceIdentifier: "fixture.one",
                itemIdentifier: "server.a",
                localizationKey: "instance.server.moveFailed",
                diagnosticText: "fixture reorder failed",
                partialChangesRolledBack: true
            )
        )
        XCTAssertTrue(model.apply(mutationResult: rejectedMove, instanceIdentifier: "fixture.one"))
        XCTAssertEqual(model.servers.map(\.id), ["server.a", "server.b"])
        XCTAssertTrue(model.mutationFailure?.partialChangesRolledBack == true)
        XCTAssertTrue(model.retry())
        XCTAssertEqual(model.servers.map(\.id), ["server.b", "server.a"])
    }

    func testInstanceServersModelTreatsExternalSnapshotAsAuthoritative() throws {
        var mutations: [PrismInstanceDetailMutationIntent] = []
        let model = PrismInstanceServersModel(onMutate: { mutations.append($1) })
        XCTAssertTrue(model.beginLoading(identifier: "fixture.one"))
        let serverA = try makeInstanceServer(
            identifier: "server.a",
            name: "Alpha",
            address: "alpha.example:25565"
        )
        let serverB = try makeInstanceServer(
            identifier: "server.b",
            name: "Beta",
            address: "beta.example:25565"
        )
        XCTAssertTrue(model.apply(servers: [serverA, serverB]))
        model.selectServer("server.a")
        model.setDraftName("Locally Edited")
        model.setDraftAddress("local.example:25565")
        XCTAssertTrue(model.updateSelected())
        XCTAssertEqual(model.servers[0].name, "Locally Edited")

        let externalServerA = try makeInstanceServer(
            identifier: "server.a",
            name: "Externally Updated",
            address: "external.example:25565",
            resourcePolicy: .never,
            status: .online,
            onlinePlayers: 8
        )
        XCTAssertTrue(model.apply(servers: [externalServerA, serverB]))
        XCTAssertEqual(model.servers[0].name, "Externally Updated")
        XCTAssertEqual(model.servers[0].address, "external.example:25565")
        XCTAssertEqual(model.servers[0].onlinePlayers, 8)
        XCTAssertNil(model.selectedServerID)
        XCTAssertNil(model.mutationFailure)
        XCTAssertEqual(model.mutationState, .idle)

        let staleResult = try XCTUnwrap(
            PRInstanceDetailMutationResult(
                kind: .servers,
                action: .update,
                outcome: .succeeded,
                instanceIdentifier: "fixture.one",
                itemIdentifier: "server.a",
                localizationKey: "instance.server.updated",
                diagnosticText: nil,
                partialChangesRolledBack: false
            )
        )
        XCTAssertFalse(model.apply(mutationResult: staleResult, instanceIdentifier: "fixture.one"))
        XCTAssertEqual(model.servers[0].name, "Externally Updated")
        XCTAssertEqual(mutations.map(\.action), [.update])
    }

    func testInstanceScreenshotsAndLogsModelsRouteSystemActionsAndBoundedContent() throws {
        var screenshotMutations: [PrismInstanceDetailMutationIntent] = []
        let screenshotsModel = PrismInstanceScreenshotsModel(
            onMutate: { screenshotMutations.append($1) }
        )
        XCTAssertTrue(screenshotsModel.beginLoading(identifier: "fixture.one"))
        let screenshotOne = try makeInstanceScreenshot(
            identifier: "shot.one",
            fileName: "shot-one.png",
            displayName: "Shot One",
            modifiedUnixSeconds: 10,
            sizeBytes: 128
        )
        let screenshotReadOnly = try makeInstanceScreenshot(
            identifier: "shot.readonly",
            fileName: "shot-readonly.png",
            displayName: "Read Only",
            readable: true,
            writable: false
        )
        XCTAssertTrue(screenshotsModel.apply(screenshots: [screenshotOne, screenshotReadOnly]))
        screenshotsModel.selectScreenshot("shot.one")
        screenshotsModel.setSearchText("shot-one")
        XCTAssertEqual(screenshotsModel.visibleScreenshots.map(\.id), ["shot.one"])
        XCTAssertTrue(screenshotsModel.copyImage("shot.one"))
        XCTAssertEqual(screenshotMutations.last?.action, .copyImage)
        XCTAssertTrue(screenshotsModel.copyFiles("shot.one"))
        XCTAssertEqual(screenshotMutations.last?.action, .copyFiles)
        XCTAssertTrue(screenshotsModel.open("shot.one"))
        XCTAssertEqual(screenshotMutations.last?.action, .open)
        XCTAssertFalse(screenshotsModel.requestDelete("shot.readonly"))
        screenshotsModel.setSearchText("")
        XCTAssertTrue(screenshotsModel.requestDelete("shot.one"))
        XCTAssertTrue(screenshotsModel.confirmDelete())
        XCTAssertEqual(screenshotMutations.last?.action, .delete)
        XCTAssertTrue(screenshotMutations.last?.confirmed == true)

        var logLoads: [String] = []
        var logContentLoads: [(String, String)] = []
        var logMutations: [PrismInstanceDetailMutationIntent] = []
        let logsModel = PrismInstanceLogsModel(
            onLoad: { logLoads.append($0) },
            onLoadContent: { logContentLoads.append(($0, $1)) },
            onMutate: { logMutations.append($1) }
        )
        XCTAssertTrue(logsModel.beginLoading(identifier: " fixture.one "))
        let currentLog = try makeInstanceLogFile(
            identifier: "log.current",
            fileName: "latest.log",
            displayName: "Latest",
            current: true,
            canBeDeleted: false
        )
        let historicalLog = try makeInstanceLogFile(
            identifier: "log.old",
            fileName: "2026-08-08.log.gz",
            displayName: "Previous",
            compressed: true
        )
        XCTAssertTrue(logsModel.apply(logFiles: [currentLog, historicalLog]))
        XCTAssertEqual(logsModel.logFiles.map(\.id), ["log.current", "log.old"])
        XCTAssertTrue(logsModel.selectLog("log.current"))
        XCTAssertEqual(logContentLoads.map { "\($0.0):\($0.1)" }, ["fixture.one:log.current"])
        let firstEntry = try XCTUnwrap(PRTaskLogEntry(sequence: 1, text: "first", truncated: false))
        let secondEntry = try XCTUnwrap(PRTaskLogEntry(sequence: 2, text: "second", truncated: true))
        let snapshot = try XCTUnwrap(
            PRInstanceLogSnapshot(
                instanceIdentifier: "fixture.one",
                logIdentifier: "log.current",
                entries: [firstEntry, secondEntry],
                droppedEntryCount: 1,
                totalByteCount: 11,
                truncated: true
            )
        )
        XCTAssertTrue(logsModel.apply(content: snapshot))
        if case .content(let log) = logsModel.contentState {
            XCTAssertEqual(log.renderedText, "first\nsecond")
            XCTAssertEqual(log.droppedEntryCount, 1)
            XCTAssertTrue(log.isTruncated)
        } else {
            XCTFail("Expected bounded log content")
        }
        XCTAssertFalse(
            logsModel.apply(
                content: try XCTUnwrap(
                    PRInstanceLogSnapshot(
                        instanceIdentifier: "fixture.one",
                        logIdentifier: "log.other",
                        entries: [firstEntry],
                        droppedEntryCount: 0,
                        totalByteCount: 5,
                        truncated: false
                    )
                )
            )
        )
        XCTAssertFalse(logsModel.requestDelete("log.current"))
        XCTAssertTrue(logsModel.selectLog("log.old"))
        XCTAssertTrue(logsModel.requestDelete("log.old"))
        XCTAssertTrue(logsModel.confirmDelete())
        XCTAssertEqual(logMutations.last?.action, .delete)
        XCTAssertTrue(logMutations.last?.confirmed == true)
        XCTAssertEqual(logLoads, ["fixture.one"])
    }

    func testInstanceDetailSourcesUseNativeTablesAccessibilityAndFoundationBoundary() throws {
        let contentSource = try contentSource()
        let shellModelSource = try shellModelSource()
        let bridgeHeaderSource = try bridgeHeaderSource()
        let bridgeModelsSource = try bridgeModelsSource()

        for requiredToken in [
            "PrismInstanceWorldsView",
            "PrismInstanceServersView",
            "PrismInstanceScreenshotsView",
            "PrismInstanceLogsView",
            "PrismInstanceCopyView",
            "PrismInstanceExportView",
            "prism.instance-details.delete-link",
            "Table(model.visibleWorlds, selection:",
            "Table(model.visibleServers, selection:",
            "Table(model.visibleScreenshots, selection:",
            "Table(model.visibleLogFiles, selection:",
            ".fileImporter(",
            ".dropDestination(for: URL.self)",
            ".confirmationDialog(",
            "role: .destructive",
            "PrismTaskLogTextView(text: log.renderedText)",
            "@StateObject private var detailCoordinator: PrismInstanceDetailCoordinator",
            "PrismInstanceDetailCoordinator(bridge: bridge)",
            "detailCoordinator.bind(",
            ".onChange(of: shellModel.selectedInstanceID)",
            "prism.instance-details.copy-link",
            "prism.instance-details.export-link",
            ".sheet(isPresented:",
            "prism.instance-worlds.table",
            "prism.instance-servers.table",
            "prism.instance-screenshots.table",
            "prism.instance-logs.table",
            ".accessibilityIdentifier("
        ] {
            XCTAssertTrue(contentSource.contains(requiredToken), "Missing native detail UI API: \(requiredToken)")
        }

        for requiredToken in [
            "PrismInstanceWorldsModel",
            "PrismInstanceServersModel",
            "PrismInstanceScreenshotsModel",
            "PrismInstanceLogsModel",
            "PrismInstanceDetailMutationIntent",
            "PrismInstanceDetailMutationFailure",
            "confirmed: true",
            "partialChangesRolledBack",
            "PRInstanceLogSnapshot",
            "totalByteCount",
            "func selectLog(_ identifier: String?)",
            "func retry() -> Bool",
            "final class PrismInstanceDetailCoordinator",
            "func loadDetails(identifier:",
            "func loadComponents(identifier:",
            "func loadResources(identifier: String, kind:",
            "func mutateResource(",
            "func loadLogContent(identifier: String, logIdentifier:",
            "func mutateDetail(identifier: String, intent:",
            "func copyInstance(request: PRInstanceCopyRequest",
            "func exportInstance(request: PRInstanceExportRequest",
            "copyModel?.apply(progress:",
            "exportModel?.apply(progress:",
            "func deleteInstance(identifier:",
            "deleteModel?.apply(result:",
            "deleteModel?.apply(error:",
            "selectionGeneration",
            "cancelAllRequests()",
            "apply(mutationError error: PRBridgeError"
        ] {
            XCTAssertTrue(shellModelSource.contains(requiredToken), "Missing detail state contract: \(requiredToken)")
        }

        for requiredToken in [
            "loadInstanceWorldsWithIdentifier",
            "loadInstanceServersWithIdentifier",
            "loadInstanceScreenshotsWithIdentifier",
            "loadInstanceLogFilesWithIdentifier",
            "loadInstanceLogWithIdentifier",
            "applyInstanceDetailActionWithIdentifier",
            "PRInstanceDetailMutationRequest",
            "deleteInstanceWithIdentifier",
            "PRInstanceDeleteResult"
        ] {
            XCTAssertTrue(bridgeHeaderSource.contains(requiredToken), "Missing bridge detail API: \(requiredToken)")
        }
        for requiredToken in [
            "PRInstanceDetailKind",
            "PRInstanceWorld",
            "PRInstanceServer",
            "PRInstanceScreenshot",
            "PRInstanceLogFile",
            "PRInstanceLogSnapshot",
            "PRInstanceDetailMutationResult",
            "PRTaskLogEntry",
            "PRInstanceDeleteResult"
        ] {
            XCTAssertTrue(bridgeModelsSource.contains(requiredToken), "Missing Foundation DTO: \(requiredToken)")
        }

        XCTAssertFalse(contentSource.contains("Canvas("))
        XCTAssertFalse(contentSource.contains("@StateObject private var instanceDetailsModel = PrismInstanceDetailsModel()"))
        XCTAssertFalse(contentSource.contains("@StateObject private var worldsModel = PrismInstanceWorldsModel()"))
        XCTAssertFalse(contentSource.contains("draw("))
        XCTAssertFalse(contentSource.contains("Path("))
        XCTAssertFalse(contentSource.contains("NSBezierPath"))
        XCTAssertFalse(shellModelSource.contains("QWidget"))
        XCTAssertFalse(shellModelSource.contains("QDialog"))
        XCTAssertFalse(shellModelSource.contains("Unmanaged"))
        XCTAssertFalse(shellModelSource.contains("UnsafeMutable"))
        XCTAssertFalse(bridgeHeaderSource.contains("QWidget"))
        XCTAssertFalse(bridgeHeaderSource.contains("QDialog"))
        XCTAssertFalse(bridgeModelsSource.contains("QWidget"))
        XCTAssertFalse(bridgeModelsSource.contains("QDialog"))
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
            "PrismTaskCommandIntent",
            "PrismLaunchCoordinator",
            "observeTaskStatus",
            "loadTaskStatus",
            "loadTaskLog",
            "cancelTask",
            "ProductionTaskIdentifier"
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
            "apply(error:",
            "func load(identifier: String) -> Bool"
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

    func testContentSourceConnectsProductionCreationAndImportForms() throws {
        let source = try contentSource()
        for requiredToken in [
            "PrismInstanceAcquisitionCoordinator",
            "versions: []",
            "loaders: []",
            "icons: [\"default\"]",
            "commandModel.onCommand",
            ".sheet(item:",
            "PrismVanillaCreationView(",
            "PrismInstanceImportView("
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing production acquisition composition: \(requiredToken)")
        }
        XCTAssertFalse(source.contains("fixtureVersions"))
        XCTAssertFalse(source.contains("fixtureLoaders"))
    }

    func testAcquisitionCoordinatorKeepsFoundationOnlyBridgeSelectors() throws {
        let source = try shellModelSource()
        for requiredToken in [
            "PrismInstanceAcquisitionCoordinator",
            "presentedSurface",
            "createVanillaInstance(",
            "importInstance(",
            "cancelCreation()",
            "cancelImport()"
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing acquisition coordinator contract: \(requiredToken)")
        }
        XCTAssertFalse(source.contains("QWidget"))
        XCTAssertFalse(source.contains("QDialog"))
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

    func testGlobalSettingsModelRoundTripsConfirmedValuesAndPreservesDraftAfterRejection() throws {
        let fixture = try PrismTemporaryFixtureRoot()
        let instanceDirectory = fixture.urlForRelativePath("instances")
        try FileManager.default.createDirectory(at: instanceDirectory, withIntermediateDirectories: true)
        let initialBridge = try makeGlobalSettings(instanceDirectoryURL: instanceDirectory, catOpacity: 73)
        let initial = try XCTUnwrap(PrismGlobalSettings(bridgeSettings: initialBridge))
        var generations: [Int] = []
        let model = PrismGlobalSettingsModel(
            initialSettings: initial,
            onSave: { _, generation in generations.append(generation) }
        )

        model.updateDraft { $0.catOpacity = 81 }
        XCTAssertTrue(model.isSaveAvailable)
        XCTAssertTrue(model.save())
        let rejected = try XCTUnwrap(
            PRGlobalSettingsUpdateResult(settings: nil, outcome: .rejected)
        )
        XCTAssertTrue(model.apply(updateResult: rejected, generation: try XCTUnwrap(generations.first)))
        XCTAssertEqual(model.confirmed?.catOpacity, 73)
        XCTAssertEqual(model.draft?.catOpacity, 81)
        XCTAssertEqual(model.saveFailure?.localizationKey, "global.settings.updateRejected")

        model.updateDraft { $0.catOpacity = 84 }
        XCTAssertTrue(model.save())
        let confirmedBridge = try makeGlobalSettings(instanceDirectoryURL: instanceDirectory, catOpacity: 88)
        let confirmedResult = try XCTUnwrap(
            PRGlobalSettingsUpdateResult(settings: confirmedBridge, outcome: .succeeded)
        )
        XCTAssertTrue(model.apply(updateResult: confirmedResult, generation: try XCTUnwrap(generations.last)))
        XCTAssertEqual(model.confirmed?.catOpacity, 88)
        XCTAssertEqual(model.draft?.catOpacity, 88)
        XCTAssertFalse(model.hasChanges)
    }

    func testGlobalSettingsModelRejectsStaleConfirmedWriteAndDirectoryCancellation() throws {
        let fixture = try PrismTemporaryFixtureRoot()
        let confirmedDirectory = fixture.urlForRelativePath("instances")
        let newerDirectory = fixture.urlForRelativePath("new-instances")
        let fileURL = fixture.urlForRelativePath("not-a-directory.txt")
        try FileManager.default.createDirectory(at: confirmedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newerDirectory, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: fileURL)

        var directoryState = PrismDirectorySelectionState(confirmedURL: confirmedDirectory)
        XCTAssertFalse(directoryState.apply(filePanelResult: .failure(NSError(domain: "cancel", code: 1))))
        XCTAssertEqual(directoryState.draftURL, confirmedDirectory)
        XCTAssertFalse(directoryState.apply(filePanelResult: .success(fileURL)))
        XCTAssertEqual(directoryState.draftURL, confirmedDirectory)
        XCTAssertTrue(directoryState.apply(filePanelResult: .success(newerDirectory)))
        XCTAssertEqual(directoryState.draftURL, newerDirectory.standardizedFileURL)
        directoryState.cancel()
        XCTAssertEqual(directoryState.draftURL, confirmedDirectory)

        let initial = try XCTUnwrap(
            PrismGlobalSettings(bridgeSettings: makeGlobalSettings(instanceDirectoryURL: confirmedDirectory, catOpacity: 73))
        )
        var generations: [Int] = []
        let model = PrismGlobalSettingsModel(
            initialSettings: initial,
            onSave: { _, generation in generations.append(generation) }
        )
        model.updateDraft { $0.catOpacity = 81 }
        XCTAssertTrue(model.save())
        let staleGeneration = try XCTUnwrap(generations.first)
        let newer = try XCTUnwrap(
            makeGlobalSettings(instanceDirectoryURL: newerDirectory, catOpacity: 91)
        )
        XCTAssertTrue(model.apply(settings: newer))
        let staleResult = try XCTUnwrap(
            PRGlobalSettingsUpdateResult(settings: makeGlobalSettings(instanceDirectoryURL: confirmedDirectory, catOpacity: 82), outcome: .succeeded)
        )
        XCTAssertFalse(model.apply(updateResult: staleResult, generation: staleGeneration))
        XCTAssertEqual(model.confirmed?.catOpacity, 91)
        XCTAssertEqual(model.confirmed?.instanceDirectoryURL, newerDirectory.standardizedFileURL)
    }

    func testSettingsSourceUsesStandardSceneControlsAndExplicitBoundaries() throws {
        let settingsSource = try settingsSource()
        let javaSource = try javaSource()
        let appSource = try appSource()
        for requiredToken in [
            "NavigationSplitView",
            ".listStyle(.sidebar)",
            ".searchable(text: $searchText, placement: .sidebar",
            ".toolbar(removing: .sidebarToggle)",
            "Form {",
            "Section(\"",
            "Picker(",
            "Toggle(",
            "Stepper(",
            "TextField(",
            "fileImporter(",
            "ProgressView(",
            "ContentUnavailableView",
            ".keyboardShortcut(.defaultAction)",
            ".accessibilityIdentifier(\"prism.settings",
            "Cancel leaves the current directory unchanged"
        ] {
            XCTAssertTrue(settingsSource.contains(requiredToken), "Missing Settings contract: \(requiredToken)")
        }
        XCTAssertTrue(appSource.contains("Window(\"Settings\", id: \"prism.settings\")"))
        XCTAssertTrue(appSource.contains(".windowStyle(.hiddenTitleBar)"))
        XCTAssertTrue(appSource.contains(".windowToolbarStyle(.unified(showsTitle: false))"))
        XCTAssertTrue(appSource.contains("PrismSettingsView("))
        XCTAssertTrue(appSource.contains("accountModel: accountModel"))
        XCTAssertTrue(appSource.contains("authenticationModel: authenticationModel"))
        XCTAssertTrue(settingsSource.contains("case services"))
        XCTAssertTrue(settingsSource.contains("case proxy"))
        XCTAssertTrue(settingsSource.contains("prism.settings.services"))
        XCTAssertTrue(settingsSource.contains("prism.settings.proxy"))
        XCTAssertFalse(settingsSource.contains("RoundedRectangle"))
        XCTAssertFalse(settingsSource.contains("settingsHeader"))
        XCTAssertFalse(settingsSource.contains("Background cat identifier"))
        XCTAssertFalse(settingsSource.contains("Cat presentation"))
        for forbiddenToken in [
            "QWidget", "QDialog", "Qt", "Unmanaged", "UnsafeMutable", "UnsafeRaw", "Canvas(",
            "draw(", "Path(", "CGContext", "NSBezierPath", "[String: Any]", "Keychain", "Process("
        ] {
            XCTAssertFalse(settingsSource.contains(forbiddenToken), "Forbidden Settings boundary: \(forbiddenToken)")
        }

        for requiredToken in [
            "PrismJavaDiscoveryModel",
            "List(selection:",
            "ProgressView(\"Detecting Java installations…\")",
            "ContentUnavailableView",
            ".disabled(!installation.isSelectable)",
            "accessibilityIdentifier(\"prism.settings.java",
            "cup.and.saucer",
            "selectedInstallationIdentifier",
            "discoveryToken",
            "selectionToken",
            "bridge.loadJavaInstallations",
            "bridge.selectJavaInstallation",
            "PrismJavaInstallation.fixture()"
        ] {
            XCTAssertTrue(javaSource.contains(requiredToken), "Missing Java Settings contract: \(requiredToken)")
        }
        for forbiddenToken in [
            "QWidget", "QDialog", "Qt", "Unmanaged", "UnsafeMutable", "UnsafeRaw", "Canvas(",
            "draw(", "Path(", "CGContext", "NSBezierPath", "FileManager", "URLSession", "Process("
        ] {
            XCTAssertFalse(javaSource.contains(forbiddenToken), "Forbidden Java Settings boundary: \(forbiddenToken)")
        }

        let accountSource = try accountSource()
        for requiredToken in [
            "PrismAccountModel",
            "PrismAccountSnapshotState",
            "PrismAccountSelectionState",
            "List(selection:",
            "Loading account snapshots…",
            "No Active Account",
            "authenticationView",
            "PrismAccountAuthenticationModel",
            "ProgressView(",
            "ContentUnavailableView",
            "accessibilityIdentifier(\"prism.settings.accounts",
            "PrismAccount.fixture()",
            "bridge.loadAccountSnapshots",
            "bridge.selectActiveAccount",
            "discoveryToken",
            "selectionToken"
        ] {
            XCTAssertTrue(accountSource.contains(requiredToken), "Missing Account Settings contract: \(requiredToken)")
        }
        for forbiddenToken in [
            "QWidget", "QDialog", "Qt", "Unmanaged", "UnsafeMutable", "UnsafeRaw", "Canvas(",
            "draw(", "Path(", "CGContext", "NSBezierPath", "FileManager", "URLSession", "Process(",
            "Keychain", "refresh_token"
        ] {
            XCTAssertFalse(accountSource.contains(forbiddenToken), "Forbidden Account Settings boundary: \(forbiddenToken)")
        }

        let authenticationSource = try authenticationSource()
        for requiredToken in [
            "@MainActor",
            "PrismAccountAuthenticationState",
            "verificationURL",
            "cancel()",
            "retry()",
            "generation",
            "PRAccountAuthenticationProgress",
            "PRAccountAuthenticationResult",
            "bridge.authenticateAccount",
            "authenticationToken"
        ] {
            XCTAssertTrue(authenticationSource.contains(requiredToken), "Missing Authentication contract: \(requiredToken)")
        }
        for forbiddenToken in [
            "QWidget", "QDialog", "Qt", "Unmanaged", "UnsafeMutable", "UnsafeRaw", "Canvas(",
            "draw(", "Path(", "CGContext", "NSBezierPath", "FileManager", "URLSession", "Process(",
            "Keychain", "refresh_token", "access_token", "authorizationCode", "device_code"
        ] {
            XCTAssertFalse(authenticationSource.contains(forbiddenToken), "Forbidden Authentication boundary: \(forbiddenToken)")
        }
    }

    func testJavaDiscoveryModelTracksFixtureStatesAndConfirmedSelection() throws {
        var discoveryGenerations: [Int] = []
        var selectionGenerations: [Int] = []
        var cancellationCount = 0
        let model = PrismJavaDiscoveryModel(
            initialInstallations: [],
            onDiscover: { discoveryGenerations.append($0) },
            onSelect: { _, generation in selectionGenerations.append(generation) },
            onCancel: { cancellationCount += 1 }
        )

        XCTAssertTrue(model.refresh())
        let firstDiscoveryGeneration = try XCTUnwrap(discoveryGenerations.first)
        let emptyResult = try XCTUnwrap(
            PRJavaDiscoveryResult(
                installations: [],
                outcome: .succeeded,
                localizationKey: "",
                diagnosticText: nil,
                retryable: false
            )
        )
        XCTAssertTrue(model.apply(discoveryResult: emptyResult, generation: firstDiscoveryGeneration))
        if case .empty = model.state {
        } else {
            XCTFail("Successful empty Java discovery should expose the empty state")
        }

        let savedInstallation = try XCTUnwrap(PrismJavaInstallation.fixture().first(where: { $0.isSelectable }))
        let savedBridgeInstallation = try XCTUnwrap(
            PRJavaInstallation(
                identifier: savedInstallation.id,
                version: savedInstallation.version,
                vendor: savedInstallation.vendor,
                architecture: savedInstallation.architecture,
                executablePath: savedInstallation.executablePath,
                is64Bit: savedInstallation.is64Bit,
                managed: savedInstallation.managed,
                validity: .valid,
                diagnosticText: nil
            )
        )
        let savedResult = try XCTUnwrap(
            PRJavaDiscoveryResult(
                installations: [savedBridgeInstallation],
                outcome: .succeeded,
                localizationKey: "",
                diagnosticText: nil,
                retryable: false,
                selectedInstallationIdentifier: savedInstallation.id
            )
        )
        XCTAssertTrue(model.refresh())
        let savedDiscoveryGeneration = try XCTUnwrap(discoveryGenerations.last)
        XCTAssertTrue(model.apply(discoveryResult: savedResult, generation: savedDiscoveryGeneration))
        XCTAssertEqual(model.confirmedSelectionID, savedInstallation.id)
        XCTAssertEqual(model.draftSelectionID, savedInstallation.id)

        XCTAssertTrue(model.refresh())
        let failedResult = try XCTUnwrap(
            PRJavaDiscoveryResult(
                installations: [],
                outcome: .failed,
                localizationKey: "java.discovery.filesystemUnavailable",
                diagnosticText: "Fixture discovery could not read the configured source.",
                retryable: true
            )
        )
        XCTAssertTrue(model.apply(discoveryResult: failedResult))
        XCTAssertEqual(model.state, .failed(
            PrismJavaFailure(
                localizationKey: "java.discovery.filesystemUnavailable",
                diagnosticText: "Fixture discovery could not read the configured source.",
                recoveryAction: .retry
            )
        ))
        XCTAssertTrue(model.retryDiscovery())
        XCTAssertTrue(model.cancelDiscovery())
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(model.state, .cancelled)

        let available = PrismJavaInstallation.fixture().first(where: { $0.isSelectable })!
        let selectionModel = PrismJavaDiscoveryModel(
            initialInstallations: PrismJavaInstallation.fixture(),
            onSelect: { _, generation in selectionGenerations.append(generation) }
        )
        XCTAssertTrue(selectionModel.select(id: available.id))
        let selectionGeneration = try XCTUnwrap(selectionGenerations.first)
        let rejectedSelection = try XCTUnwrap(
            PRJavaSelectionResult(
                installation: nil,
                outcome: .rejected,
                localizationKey: "java.selection.rejected",
                diagnosticText: "Fixture selection was rejected."
            )
        )
        XCTAssertTrue(selectionModel.apply(selectionResult: rejectedSelection, generation: selectionGeneration))
        XCTAssertNil(selectionModel.confirmedSelectionID)
        XCTAssertEqual(selectionModel.draftSelectionID, available.id)
        XCTAssertEqual(selectionModel.selectionFailure?.localizationKey, "java.selection.rejected")

        XCTAssertTrue(selectionModel.retrySelection())
        let retryGeneration = try XCTUnwrap(selectionGenerations.last)
        let bridgeInstallation = try XCTUnwrap(
            PRJavaInstallation(
                identifier: available.id,
                version: available.version,
                vendor: available.vendor,
                architecture: available.architecture,
                executablePath: available.executablePath,
                is64Bit: available.is64Bit,
                managed: available.managed,
                validity: .valid,
                diagnosticText: nil
            )
        )
        let staleSuccess = try XCTUnwrap(
            PRJavaSelectionResult(
                installation: bridgeInstallation,
                outcome: .succeeded,
                localizationKey: "",
                diagnosticText: nil
            )
        )
        XCTAssertFalse(selectionModel.apply(selectionResult: staleSuccess, generation: selectionGeneration))
        XCTAssertTrue(selectionModel.apply(selectionResult: staleSuccess, generation: retryGeneration))
        XCTAssertEqual(selectionModel.confirmedSelectionID, available.id)
        XCTAssertEqual(selectionModel.draftSelectionID, available.id)
        XCTAssertFalse(selectionModel.isSavingSelection)

        let fixtureModel = PrismJavaDiscoveryModel()
        XCTAssertEqual(fixtureModel.installations.count, 4)
        XCTAssertTrue(fixtureModel.selectableInstallations.allSatisfy(\.isSelectable))
        XCTAssertFalse(fixtureModel.installations.contains(where: { $0.validity != .valid && $0.isSelectable }))
    }

    func testAccountModelConfirmsSnapshotsSelectionAndClearWithGenerationGuards() throws {
        var discoveryGenerations: [Int] = []
        var selectionRequests: [(String?, Int)] = []
        var cancellationCount = 0
        let model = PrismAccountModel(
            initialAccounts: [],
            activeAccountID: nil,
            onDiscover: { discoveryGenerations.append($0) },
            onSelect: { identifier, generation in selectionRequests.append((identifier, generation)) },
            onCancel: { cancellationCount += 1 }
        )

        XCTAssertTrue(model.refresh())
        let discoveryGeneration = try XCTUnwrap(discoveryGenerations.first)
        let microsoftBridge = try XCTUnwrap(
            PRAccountSnapshot(
                identifier: "account.fixture.microsoft",
                displayName: "Fixture Microsoft Account",
                type: .microsoft,
                state: .online,
                ownsMinecraft: true,
                isBusy: false,
                canBeSelected: true,
                diagnosticText: nil
            )
        )
        let offlineBridge = try XCTUnwrap(
            PRAccountSnapshot(
                identifier: "account.fixture.offline",
                displayName: "Fixture Offline Profile",
                type: .offline,
                state: .offline,
                ownsMinecraft: false,
                isBusy: false,
                canBeSelected: true,
                diagnosticText: nil
            )
        )
        let snapshotResult = try XCTUnwrap(
            PRAccountSnapshotResult(
                accounts: [microsoftBridge, offlineBridge],
                activeAccountIdentifier: "account.fixture.microsoft",
                outcome: .succeeded,
                localizationKey: "",
                diagnosticText: nil,
                retryable: false
            )
        )
        XCTAssertTrue(model.apply(snapshotResult: snapshotResult, generation: discoveryGeneration))
        XCTAssertEqual(model.accounts.count, 2)
        XCTAssertEqual(model.confirmedActiveAccountID, "account.fixture.microsoft")
        XCTAssertEqual(model.draftActiveAccountID, "account.fixture.microsoft")
        XCTAssertFalse(model.select(id: "unknown.account"))

        XCTAssertTrue(model.select(id: "account.fixture.offline"))
        let firstSelectionGeneration = try XCTUnwrap(selectionRequests.first?.1)
        let rejectedSelection = try XCTUnwrap(
            PRAccountSelectionResult(
                account: nil,
                outcome: .rejected,
                localizationKey: "accounts.selection.rejected",
                diagnosticText: "Fixture selection was rejected."
            )
        )
        XCTAssertTrue(model.apply(selectionResult: rejectedSelection, generation: firstSelectionGeneration))
        XCTAssertEqual(model.confirmedActiveAccountID, "account.fixture.microsoft")
        XCTAssertEqual(model.draftActiveAccountID, "account.fixture.offline")
        XCTAssertEqual(model.selectionFailure?.localizationKey, "accounts.selection.rejected")

        XCTAssertTrue(model.retrySelection())
        let retryGeneration = try XCTUnwrap(selectionRequests.last?.1)
        let staleSuccess = try XCTUnwrap(
            PRAccountSelectionResult(
                account: microsoftBridge,
                outcome: .succeeded,
                localizationKey: "",
                diagnosticText: nil
            )
        )
        XCTAssertFalse(model.apply(selectionResult: staleSuccess, generation: firstSelectionGeneration))
        let confirmedOffline = try XCTUnwrap(
            PRAccountSelectionResult(
                account: offlineBridge,
                outcome: .succeeded,
                localizationKey: "",
                diagnosticText: nil
            )
        )
        XCTAssertTrue(model.apply(selectionResult: confirmedOffline, generation: retryGeneration))
        XCTAssertEqual(model.confirmedActiveAccountID, "account.fixture.offline")
        XCTAssertFalse(model.isSavingSelection)

        XCTAssertTrue(model.select(id: nil))
        let clearGeneration = try XCTUnwrap(selectionRequests.last?.1)
        let cleared = try XCTUnwrap(
            PRAccountSelectionResult(
                account: nil,
                outcome: .succeeded,
                localizationKey: "",
                diagnosticText: nil
            )
        )
        XCTAssertTrue(model.apply(selectionResult: cleared, generation: clearGeneration))
        XCTAssertNil(model.confirmedActiveAccountID)
        XCTAssertNil(model.draftActiveAccountID)

        XCTAssertTrue(model.refresh())
        XCTAssertTrue(model.cancelDiscovery())
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(model.state, .cancelled)
    }

    func testAccountAuthenticationModelTracksProgressCancellationRecoveryAndStaleResults() throws {
        var requests: [(String, PrismAccountAuthenticationAction, Int)] = []
        var cancellationCount = 0
        let model = PrismAccountAuthenticationModel(
            onAuthenticate: { identifier, action, generation in
                requests.append((identifier, action, generation))
            },
            onCancel: { cancellationCount += 1 }
        )

        XCTAssertTrue(model.start(accountIdentifier: " account.fixture.microsoft ", action: .login))
        let loginGeneration = try XCTUnwrap(requests.first?.2)
        let preparing = try XCTUnwrap(
            PRAccountAuthenticationProgress(
                accountIdentifier: "account.fixture.microsoft",
                action: .login,
                phase: .preparing,
                outcome: .inProgress,
                providerLabel: "Fixture Provider",
                verificationURL: nil,
                localizationKey: "accounts.authentication.preparing",
                diagnosticText: nil,
                expiresInSeconds: 0,
                canCancel: true,
                retryable: false,
                requiresUserAction: false
            )
        )
        XCTAssertTrue(model.apply(progress: preparing, generation: loginGeneration))
        XCTAssertTrue(model.isRunning)
        let awaitingUser = try XCTUnwrap(
            PRAccountAuthenticationProgress(
                accountIdentifier: "account.fixture.microsoft",
                action: .login,
                phase: .awaitingUser,
                outcome: .inProgress,
                providerLabel: "Fixture Provider",
                verificationURL: "https://login.example.invalid/device",
                localizationKey: "accounts.authentication.awaitingUser",
                diagnosticText: nil,
                expiresInSeconds: 900,
                canCancel: true,
                retryable: false,
                requiresUserAction: true
            )
        )
        XCTAssertTrue(model.apply(progress: awaitingUser, generation: loginGeneration))
        XCTAssertTrue(model.currentProgress?.isAwaitingUser == true)
        XCTAssertEqual(model.currentProgress?.verificationURL, "https://login.example.invalid/device")

        let authenticating = try XCTUnwrap(
            PRAccountAuthenticationProgress(
                accountIdentifier: "account.fixture.microsoft",
                action: .login,
                phase: .authenticating,
                outcome: .inProgress,
                providerLabel: "Fixture Provider",
                verificationURL: nil,
                localizationKey: "accounts.authentication.authenticating",
                diagnosticText: nil,
                expiresInSeconds: 0,
                canCancel: true,
                retryable: false,
                requiresUserAction: false
            )
        )
        XCTAssertTrue(model.apply(progress: authenticating, generation: loginGeneration))
        let succeededProgress = try XCTUnwrap(
            PRAccountAuthenticationProgress(
                accountIdentifier: "account.fixture.microsoft",
                action: .login,
                phase: .succeeded,
                outcome: .succeeded,
                providerLabel: "Fixture Provider",
                verificationURL: nil,
                localizationKey: "accounts.authentication.succeeded",
                diagnosticText: nil,
                expiresInSeconds: 0,
                canCancel: false,
                retryable: false,
                requiresUserAction: false
            )
        )
        XCTAssertTrue(model.apply(progress: succeededProgress, generation: loginGeneration))
        let authenticatedAccount = try XCTUnwrap(
            PRAccountSnapshot(
                identifier: "account.fixture.microsoft",
                displayName: "Fixture Microsoft Account",
                type: .microsoft,
                state: .online,
                ownsMinecraft: true,
                isBusy: false,
                canBeSelected: true,
                diagnosticText: nil
            )
        )
        let succeededResult = try XCTUnwrap(
            PRAccountAuthenticationResult(
                account: authenticatedAccount,
                outcome: .succeeded,
                localizationKey: "accounts.authentication.succeeded",
                diagnosticText: nil,
                retryable: false
            )
        )
        XCTAssertTrue(model.apply(result: succeededResult, generation: loginGeneration))
        if case .succeeded(let account) = model.state {
            XCTAssertEqual(account?.id, "account.fixture.microsoft")
        } else {
            XCTFail("Expected a confirmed authentication result")
        }

        XCTAssertTrue(model.start(accountIdentifier: "account.fixture.microsoft", action: .refresh))
        let refreshGeneration = try XCTUnwrap(requests.last?.2)
        XCTAssertTrue(model.cancel())
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(model.state, .cancelled)
        XCTAssertFalse(model.apply(result: succeededResult, generation: refreshGeneration))

        XCTAssertTrue(model.start(accountIdentifier: "account.fixture.microsoft", action: .refresh))
        let failedGeneration = try XCTUnwrap(requests.last?.2)
        let failedProgress = try XCTUnwrap(
            PRAccountAuthenticationProgress(
                accountIdentifier: "account.fixture.microsoft",
                action: .refresh,
                phase: .failed,
                outcome: .failed,
                providerLabel: "Fixture Provider",
                verificationURL: nil,
                localizationKey: "accounts.authentication.refreshFailed",
                diagnosticText: "Fixture refresh can be retried.",
                expiresInSeconds: 0,
                canCancel: false,
                retryable: true,
                requiresUserAction: false
            )
        )
        XCTAssertTrue(model.apply(progress: failedProgress, generation: failedGeneration))
        XCTAssertEqual(model.authenticationFailure?.localizationKey, "accounts.authentication.refreshFailed")
        XCTAssertTrue(model.canRetry)
        let failedResult = try XCTUnwrap(
            PRAccountAuthenticationResult(
                account: nil,
                outcome: .failed,
                localizationKey: "accounts.authentication.refreshFailed",
                diagnosticText: "Fixture refresh can be retried.",
                retryable: true
            )
        )
        XCTAssertTrue(model.apply(result: failedResult, generation: failedGeneration))
        XCTAssertTrue(model.retry())
        XCTAssertEqual(requests.last?.1, .refresh)

        let unavailableModel = PrismAccountAuthenticationModel()
        XCTAssertFalse(unavailableModel.start(accountIdentifier: "account.fixture.microsoft"))
        XCTAssertEqual(unavailableModel.authenticationFailure?.localizationKey, "accounts.authentication.unavailable")
        XCTAssertTrue(unavailableModel.canRetry)
    }

    func testOfflineLaunchIdentityModelPreservesValidationConfirmationCancellationAndRecovery() throws {
        XCTAssertTrue(PrismOfflineLaunchIdentityValidation.isValidLegacyName("abc"))
        XCTAssertTrue(PrismOfflineLaunchIdentityValidation.isValidLegacyName("Native_Player16"))
        XCTAssertFalse(PrismOfflineLaunchIdentityValidation.isValidLegacyName("ab"))
        XCTAssertFalse(PrismOfflineLaunchIdentityValidation.isValidLegacyName("bad name"))
        XCTAssertFalse(PrismOfflineLaunchIdentityValidation.isValidLegacyName("éclair"))

        var loadRequests: [(PrismOfflineLaunchIdentityMode, String?, String, Int)] = []
        var saveRequests: [(PrismOfflineLaunchIdentityMode, String?, String, Bool, Int)] = []
        var cancellationCount = 0
        let model = PrismOfflineLaunchIdentityModel(
            onLoad: { mode, accountIdentifier, fallbackName, generation in
                loadRequests.append((mode, accountIdentifier, fallbackName, generation))
            },
            onSave: { mode, accountIdentifier, name, allowInvalidNames, generation in
                saveRequests.append((mode, accountIdentifier, name, allowInvalidNames, generation))
            },
            onCancel: { cancellationCount += 1 }
        )

        XCTAssertTrue(
            model.load(
                mode: .offline,
                accountIdentifier: " account.fixture.offline ",
                fallbackName: "Player"
            )
        )
        let loadGeneration = try XCTUnwrap(loadRequests.first?.3)
        XCTAssertTrue(model.isLoading)
        let loadedIdentity = try XCTUnwrap(
            PROfflineLaunchIdentity(
                mode: .offline,
                accountIdentifier: "account.fixture.offline",
                name: "Saved_Player"
            )
        )
        let loadedResult = try XCTUnwrap(
            PROfflineLaunchIdentityLoadResult(
                identity: loadedIdentity,
                outcome: .succeeded,
                localizationKey: "accounts.offlineIdentity.loaded",
                diagnosticText: nil,
                retryable: false
            )
        )
        XCTAssertTrue(model.apply(loadResult: loadedResult, generation: loadGeneration))
        XCTAssertEqual(model.confirmedIdentity?.name, "Saved_Player")
        XCTAssertEqual(model.draftName, "Saved_Player")

        XCTAssertTrue(model.updateDraftName("bad name"))
        XCTAssertFalse(model.canSave)
        XCTAssertTrue(model.updateAllowInvalidNames(true))
        XCTAssertTrue(model.canSave)
        XCTAssertTrue(model.save())
        let saveGeneration = try XCTUnwrap(saveRequests.first?.4)
        XCTAssertEqual(saveRequests.first?.2, "bad name")
        XCTAssertEqual(saveRequests.first?.3, true)
        let invalidNameResult = try XCTUnwrap(
            PROfflineLaunchIdentityUpdateResult(
                identity: nil,
                outcome: .invalidName,
                localizationKey: "accounts.offlineIdentity.invalidName",
                diagnosticText: "Fixture name rejected.",
                retryable: false
            )
        )
        XCTAssertTrue(model.apply(updateResult: invalidNameResult, generation: saveGeneration))
        XCTAssertEqual(model.failure?.localizationKey, "accounts.offlineIdentity.invalidName")
        XCTAssertFalse(model.canRetry)

        XCTAssertTrue(model.beginEditing())
        XCTAssertTrue(model.updateDraftName("Native_Player"))
        XCTAssertTrue(model.updateAllowInvalidNames(false))
        XCTAssertTrue(model.save())
        let confirmedSaveGeneration = try XCTUnwrap(saveRequests.last?.4)
        let confirmedIdentity = try XCTUnwrap(
            PROfflineLaunchIdentity(
                mode: .offline,
                accountIdentifier: "account.fixture.offline",
                name: "Native_Player"
            )
        )
        let confirmedResult = try XCTUnwrap(
            PROfflineLaunchIdentityUpdateResult(
                identity: confirmedIdentity,
                outcome: .succeeded,
                localizationKey: "accounts.offlineIdentity.saved",
                diagnosticText: nil,
                retryable: false
            )
        )
        XCTAssertTrue(model.apply(updateResult: confirmedResult, generation: confirmedSaveGeneration))
        XCTAssertEqual(model.confirmedIdentity?.name, "Native_Player")
        if case .succeeded(let finalIdentity) = model.state {
            XCTAssertEqual(finalIdentity.name, "Native_Player")
        } else {
            XCTFail("Expected a confirmed offline launch identity")
        }

        XCTAssertTrue(model.load(accountIdentifier: "account.fixture.offline", fallbackName: "Player"))
        let staleGeneration = try XCTUnwrap(loadRequests.last?.3)
        XCTAssertTrue(model.cancel())
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertFalse(model.apply(loadResult: loadedResult, generation: staleGeneration))

        let unavailableModel = PrismOfflineLaunchIdentityModel()
        XCTAssertFalse(unavailableModel.load(accountIdentifier: "account.fixture.offline", fallbackName: "Player"))
        XCTAssertEqual(unavailableModel.failure?.localizationKey, "accounts.offlineIdentity.unavailable")
        XCTAssertTrue(unavailableModel.canRetry)
        XCTAssertFalse(unavailableModel.retry())
    }

    func testOfflineLaunchIdentitySourcesUseSystemControlsAndFoundationBoundary() throws {
        let accountSource = try accountSource()
        let appSource = try appSource()
        let identitySource = try offlineIdentitySource()
        let bridgeHeaderSource = try bridgeHeaderSource()
        let bridgeModelsSource = try bridgeModelsSource()

        for requiredToken in [
            "GroupBox(\"Offline Launch Identity\")",
            "TextField(",
            "Toggle(",
            "ContentUnavailableView",
            "ProgressView(",
            "prism.settings.accounts.offline-identity-name",
            "prism.settings.accounts.offline-identity-save",
            "prism.settings.accounts.offline-identity-cancel",
            "prism.settings.accounts.offline-identity-rule",
            "Allow invalid names"
        ] {
            XCTAssertTrue(accountSource.contains(requiredToken), "Missing native offline identity UI API: \(requiredToken)")
        }

        for requiredToken in [
            "PrismOfflineLaunchIdentity",
            "PrismOfflineLaunchIdentityModel",
            "PrismOfflineLaunchIdentityValidation",
            "PrismOfflineLaunchIdentityState",
            "apply(loadResult:",
            "apply(updateResult:",
            "func cancel()",
            "func retry()",
            "allowInvalidNames",
            "bridge.loadOfflineLaunchIdentity",
            "bridge.updateOfflineLaunchIdentity",
            "loadToken",
            "saveToken"
        ] {
            XCTAssertTrue(identitySource.contains(requiredToken), "Missing offline identity state contract: \(requiredToken)")
        }

        for requiredToken in [
            "loadOfflineLaunchIdentityWithMode",
            "updateOfflineLaunchIdentityWithMode",
            "PROfflineLaunchIdentityLoadCompletionHandler",
            "PROfflineLaunchIdentityUpdateCompletionHandler"
        ] {
            XCTAssertTrue(bridgeHeaderSource.contains(requiredToken), "Missing offline identity bridge API: \(requiredToken)")
        }
        for requiredToken in [
            "PROfflineLaunchIdentity",
            "PROfflineLaunchIdentityLoadResult",
            "PROfflineLaunchIdentityUpdateResult"
        ] {
            XCTAssertTrue(bridgeModelsSource.contains(requiredToken), "Missing offline identity DTO: \(requiredToken)")
        }
        XCTAssertTrue(appSource.contains("offlineIdentityModel"))
        XCTAssertFalse(accountSource.contains("Canvas("))
        XCTAssertFalse(accountSource.contains("draw("))
        XCTAssertFalse(identitySource.contains("QWidget"))
        XCTAssertFalse(identitySource.contains("QDialog"))
        XCTAssertFalse(identitySource.contains("URLSession"))
        XCTAssertFalse(identitySource.contains("Keychain"))
        XCTAssertFalse(identitySource.contains("refresh_token"))
        XCTAssertFalse(identitySource.contains("access_token"))
    }

    private func makeGlobalSettings(instanceDirectoryURL: URL, catOpacity: Int) throws -> PRGlobalSettings {
        try XCTUnwrap(
            PRGlobalSettings(
                instanceDirectoryURL: instanceDirectoryURL,
                iconTheme: "fixture-icons",
                applicationTheme: "fixture-theme",
                backgroundCat: "fixture-cat",
                catOpacity: catOpacity,
                catFit: "strech",
                language: "en_US",
                useSystemLocale: true,
                menuBarInsteadOfToolBar: true,
                statusBarVisible: false,
                toolbarsLocked: true,
                numberOfConcurrentTasks: 10,
                numberOfConcurrentDownloads: 6,
                numberOfManualRetries: 2,
                requestTimeoutSeconds: 60,
                consoleFont: "Menlo",
                consoleFontSize: 12,
                consoleMaxLines: 20_000,
                consoleOverflowStop: false,
                showConsole: true,
                autoCloseConsole: true,
                showConsoleOnError: false,
                logPrePostOutput: true
            )
        )
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

    private func settingsSource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("PrismNative/App/PrismSettings.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func javaSource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("PrismNative/App/PrismJavaSettings.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func accountSource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("PrismNative/App/PrismAccountSettings.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func authenticationSource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("PrismNative/App/PrismAccountAuthentication.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func offlineIdentitySource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("PrismNative/App/PrismOfflineLaunchIdentity.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func appSource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("PrismNative/App/PrismNativeApp.swift")
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

    private func bridgeHeaderSource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("PrismNative/Bridge/PrismBridge.h")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
