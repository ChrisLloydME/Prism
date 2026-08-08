import Foundation
import XCTest

@MainActor
final class PrismShellTests: XCTestCase {
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
}
