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
