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

    func testShellModelTracksSidebarSelectionWithoutApplyingGroupingPolicy() {
        let model = PrismShellModel()

        model.selectSidebarItem(.discover)
        XCTAssertEqual(model.selectedSidebarItem, .discover)

        model.selectSidebarItem(nil)
        XCTAssertNil(model.selectedSidebarItem)
        XCTAssertEqual(model.detailState, .empty)
    }

    func testShellModelRepresentsLoadingEmptyAndContentStates() {
        let model = PrismShellModel()

        for state in [
            PrismShellDetailState.loading,
            .empty,
            .content,
        ] {
            model.setDetailState(state)
            XCTAssertEqual(model.detailState, state)
        }
    }

    func testContentSourceUsesSystemSidebarDetailAndContentStateAPIs() throws {
        let source = try contentSource()

        for requiredToken in [
            "NavigationSplitView",
            "List(",
            "selection:",
            ".tag(",
            ".listStyle(.sidebar)",
            "ContentUnavailableView(",
            "ProgressView(",
            ".accessibilityLabel(",
            ".accessibilityHint(",
            ".accessibilityIdentifier("
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native shell API: \(requiredToken)")
        }

        XCTAssertFalse(source.contains(".toolbar("))
        XCTAssertFalse(source.contains("Canvas("))
        XCTAssertFalse(source.contains("draw("))
    }

    private func contentSource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot
            .appendingPathComponent("PrismNative/App/ContentView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
