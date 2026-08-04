import Foundation
import XCTest

@MainActor
final class PrismCommandTests: XCTestCase {
    func testCommandManifestHasUniqueMenusLabelsAndIdentifiers() {
        let descriptors = PrismCommandDescriptor.all

        XCTAssertEqual(Set(descriptors.map(\.id)).count, descriptors.count)
        XCTAssertEqual(Set(descriptors.map(\.titleKey)).count, descriptors.count)
        XCTAssertEqual(
            Set(descriptors.map(\.accessibilityIdentifier)).count,
            descriptors.count
        )

        for descriptor in descriptors {
            XCTAssertFalse(descriptor.titleKey.isEmpty)
            XCTAssertFalse(descriptor.accessibilityLabelKey.isEmpty)
            XCTAssertFalse(descriptor.helpKey.isEmpty)
            XCTAssertFalse(descriptor.systemImage.isEmpty)
            XCTAssertEqual(
                descriptor.accessibilityIdentifier,
                "prism.command.\(descriptor.id.rawValue)"
            )
        }
    }

    func testCommandManifestPreservesNativeShortcutDecisions() {
        XCTAssertEqual(
            PrismCommandDescriptor.descriptor(for: .newInstance).shortcut,
            .command("n")
        )
        XCTAssertEqual(
            PrismCommandDescriptor.descriptor(for: .settings).shortcut,
            .command(",")
        )
        XCTAssertEqual(
            PrismCommandDescriptor.descriptor(for: .closeWindow).shortcut,
            .command("w")
        )
        XCTAssertEqual(
            PrismCommandDescriptor.descriptor(for: .deleteSelected).shortcut,
            .delete
        )
        XCTAssertNil(PrismCommandDescriptor.descriptor(for: .undoDelete).shortcut)
    }

    func testCommandModelEnablesOnlyCommandsAllowedBySelectionAndTaskState() {
        let model = PrismCommandModel()

        XCTAssertTrue(model.isEnabled(.newInstance))
        XCTAssertTrue(model.isEnabled(.settings))
        XCTAssertFalse(model.isEnabled(.launchSelected))
        XCTAssertFalse(model.isEnabled(.deleteSelected))
        XCTAssertFalse(model.isEnabled(.stopSelected))
        XCTAssertFalse(model.isEnabled(.undoDelete))

        model.setSelectedInstanceID(" fixture.one ")
        XCTAssertEqual(model.selectedInstanceID, "fixture.one")
        XCTAssertTrue(model.isEnabled(.launchSelected))
        XCTAssertTrue(model.isEnabled(.editSelected))
        XCTAssertTrue(model.isEnabled(.deleteSelected))
        XCTAssertFalse(model.isEnabled(.stopSelected))

        model.setRunningInstanceID("fixture.other")
        XCTAssertFalse(model.isEnabled(.stopSelected))
        model.setRunningInstanceID("fixture.one")
        XCTAssertTrue(model.isEnabled(.stopSelected))

        model.setCanUndoDeletion(true)
        XCTAssertTrue(model.isEnabled(.undoDelete))

        model.setSelectedInstanceID("   ")
        XCTAssertNil(model.selectedInstanceID)
        XCTAssertFalse(model.isEnabled(.launchSelected))
    }

    func testCommandModelRoutesOnlyEnabledCommands() {
        var invoked: [PrismCommandID] = []
        let model = PrismCommandModel { invoked.append($0) }

        XCTAssertFalse(model.invoke(.launchSelected))
        XCTAssertNil(model.lastInvokedCommand)
        XCTAssertTrue(invoked.isEmpty)

        model.setSelectedInstanceID("fixture.one")
        XCTAssertTrue(model.invoke(.launchSelected))
        XCTAssertEqual(model.lastInvokedCommand, .launchSelected)
        XCTAssertEqual(invoked, [.launchSelected])

        XCTAssertTrue(model.invoke(.settings))
        XCTAssertEqual(invoked, [.launchSelected, .settings])
    }

    func testToolbarAndContextMenuUseStableSharedCommandSets() {
        XCTAssertEqual(
            PrismCommandModel.toolbarCommandIDs,
            [.newInstance, .importInstance, .launchSelected, .stopSelected]
        )
        XCTAssertEqual(
            PrismCommandModel.contextMenuCommandIDs,
            [.launchSelected, .stopSelected, .editSelected, .deleteSelected]
        )

        for command in PrismCommandModel.toolbarCommandIDs + PrismCommandModel.contextMenuCommandIDs {
            let descriptor = PrismCommandDescriptor.descriptor(for: command)
            XCTAssertFalse(descriptor.titleKey.isEmpty)
            XCTAssertFalse(descriptor.accessibilityIdentifier.isEmpty)
        }
    }

    func testCommandSurfacesPreserveEnabledStateAcrossSelectionAndRunningIdentity() {
        let model = PrismCommandModel()
        let surfaceCommands = PrismCommandModel.toolbarCommandIDs
            + PrismCommandModel.contextMenuCommandIDs

        for command in surfaceCommands {
            let descriptor = PrismCommandDescriptor.descriptor(for: command)
            XCTAssertEqual(
                model.isEnabled(command),
                !descriptor.requiresSelection,
                "Unexpected initial enabled state for \(command.rawValue)"
            )
        }

        model.setSelectedInstanceID("fixture.one")
        for command in surfaceCommands {
            let descriptor = PrismCommandDescriptor.descriptor(for: command)
            if descriptor.requiresSelection && command != .stopSelected {
                XCTAssertTrue(model.isEnabled(command), "Selection should enable \(command.rawValue)")
            }
        }
        XCTAssertFalse(model.isEnabled(.stopSelected))

        model.setRunningInstanceID("fixture.one")
        XCTAssertTrue(model.isEnabled(.stopSelected))

        model.setSelectedInstanceID(nil)
        XCTAssertFalse(model.isEnabled(.launchSelected))
        XCTAssertFalse(model.isEnabled(.stopSelected))
        XCTAssertFalse(model.isEnabled(.editSelected))
        XCTAssertFalse(model.isEnabled(.deleteSelected))
    }

    func testCommandSourceUsesSystemMenusAndAccessibilityMetadata() throws {
        let source = try commandSource()

        for requiredToken in [
            "CommandGroup(",
            "CommandMenu(",
            "Button {",
            "Label {",
            "PrismCommandButton(",
            "PrismInstanceContextMenu",
            ".keyboardShortcut(",
            ".accessibilityLabel(",
            ".accessibilityIdentifier(descriptor.accessibilityIdentifier)",
            ".help("
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native command API: \(requiredToken)")
        }

        XCTAssertFalse(source.contains(".toolbar("))
        XCTAssertFalse(source.contains("Canvas("))
        XCTAssertFalse(source.contains("draw(") )
    }

    func testContentViewUsesSystemToolbarAndContextMenuWithSharedCommandModel() throws {
        let source = try contentSource()

        for requiredToken in [
            ".toolbar {",
            "ToolbarItemGroup(",
            ".contextMenu {",
            "PrismCommandButton(model: commandModel",
            "PrismInstanceContextMenu(model: commandModel)",
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native command surface API: \(requiredToken)")
        }

        XCTAssertFalse(source.contains("commandModel.invoke("))
        XCTAssertFalse(source.contains("Canvas("))
        XCTAssertFalse(source.contains("draw("))
    }

    private func commandSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURLs = [
            repositoryRoot.appendingPathComponent("PrismNative/App/PrismCommands.swift"),
            repositoryRoot.appendingPathComponent("PrismNative/App/PrismCommandModel.swift"),
        ]
        return try sourceURLs
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    private func contentSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("PrismNative/App/ContentView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
