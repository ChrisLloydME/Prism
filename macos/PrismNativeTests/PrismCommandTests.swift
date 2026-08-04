import Foundation
import XCTest

@MainActor
final class PrismCommandTests: XCTestCase {
    func testCommandManifestHasUniqueMenusLabelsAndIdentifiers() {
        let descriptors = PrismCommandDescriptor.all

        XCTAssertEqual(Set(descriptors.map(\.id)).count, descriptors.count)
        XCTAssertEqual(Set(descriptors.map(\.titleKey)).count, descriptors.count)

        for descriptor in descriptors {
            XCTAssertFalse(descriptor.titleKey.isEmpty)
            XCTAssertFalse(descriptor.accessibilityLabelKey.isEmpty)
            XCTAssertFalse(descriptor.helpKey.isEmpty)
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

    func testCommandSourceUsesSystemMenusAndAccessibilityMetadata() throws {
        let source = try commandSource()

        for requiredToken in [
            "CommandGroup(",
            "CommandMenu(",
            ".keyboardShortcut(",
            ".accessibilityLabel(",
            ".help("
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native command API: \(requiredToken)")
        }

        XCTAssertFalse(source.contains(".toolbar("))
        XCTAssertFalse(source.contains("Canvas("))
        XCTAssertFalse(source.contains("draw(") )
    }

    private func commandSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("PrismNative/App/PrismCommands.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
