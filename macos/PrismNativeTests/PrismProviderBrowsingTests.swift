import Foundation
import XCTest

@MainActor
final class PrismProviderBrowsingTests: XCTestCase {
    func testBrowseRequestPreservesSharedFiltersPaginationAndVersionSelection() throws {
        var requests: [PRProviderBrowseRequest] = []
        var versionRequests: [PRProviderVersionRequest] = []
        let filter = PrismProviderFilter(
            gameVersions: ["1.21.1", "1.21.1"],
            loaders: ["fabric"],
            categories: ["adventure"],
            releaseTypes: [.release, .beta],
            side: .client,
            openSource: true,
            hideInstalled: true
        )
        let model = PrismProviderBrowserModel(
            initialProvider: .curseForge,
            filter: filter,
            onBrowse: { request, _ in requests.append(request) },
            onLoadVersions: { request, _ in versionRequests.append(request) }
        )

        XCTAssertTrue(model.startBrowse())
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.provider, .curseForge)
        XCTAssertEqual(request.query, "")
        XCTAssertEqual(request.offset, 0)
        XCTAssertEqual(request.pageSize, 20)
        XCTAssertEqual(request.gameVersions, ["1.21.1"])
        XCTAssertEqual(request.releaseTypes.map(\.intValue), [1, 2])
        XCTAssertEqual(request.side, .client)
        XCTAssertTrue(request.openSource)
        XCTAssertTrue(request.hideInstalled)

        let pack = try XCTUnwrap(
            PRProviderPack(
                provider: .curseForge,
                identifier: "pack.fixture",
                name: "Fixture Pack",
                slug: "fixture-pack",
                summary: "Fixture summary",
                author: "Fixture Author",
                categories: ["adventure"],
                versionsAvailable: true,
                supportsVersionSelection: true
            )
        )
        let page = try XCTUnwrap(
            PRProviderBrowsePage(
                provider: .curseForge,
                offset: 0,
                pageSize: 20,
                nextOffset: NSNumber(value: 20),
                packs: [pack]
            )
        )
        let browseResult = try XCTUnwrap(
            PRProviderBrowseResult(
                page: page,
                outcome: .succeeded,
                localizationKey: "providers.browse.completed",
                diagnosticText: nil,
                retryable: false
            )
        )
        let generation = 1
        XCTAssertTrue(model.apply(result: browseResult, generation: generation))
        XCTAssertEqual(model.rows.map(\.id), ["pack.fixture"])
        XCTAssertEqual(model.nextOffset, 20)
        XCTAssertTrue(model.selectPack("pack.fixture"))
        XCTAssertTrue(model.loadSelectedPackVersions())

        let versionRequest = try XCTUnwrap(versionRequests.first)
        XCTAssertEqual(versionRequest.provider, .curseForge)
        XCTAssertEqual(versionRequest.packIdentifier, "pack.fixture")
        XCTAssertEqual(versionRequest.gameVersions, ["1.21.1"])
        XCTAssertEqual(versionRequest.loaders, ["fabric"])
        XCTAssertEqual(versionRequest.releaseTypes.map(\.intValue), [1, 2])

        let version = try XCTUnwrap(
            PRProviderVersion(
                provider: .curseForge,
                installKind: .curseForgeFlame,
                identifier: "version.fixture",
                packIdentifier: "pack.fixture",
                name: "1.0.0 Fabric",
                version: "1.0.0",
                gameVersions: ["1.21.1"],
                loaders: ["fabric"],
                releaseType: .release,
                publishedUnixSeconds: 123,
                recommended: true
            )
        )
        let versionResult = try XCTUnwrap(
            PRProviderVersionResult(
                provider: .curseForge,
                packIdentifier: "pack.fixture",
                versions: [version],
                outcome: .succeeded,
                localizationKey: "providers.versions.completed",
                diagnosticText: nil,
                retryable: false
            )
        )
        XCTAssertTrue(model.apply(result: versionResult, generation: 1))
        XCTAssertTrue(model.selectVersion("version.fixture"))
        XCTAssertTrue(model.selectedVersion?.recommended == true)

        XCTAssertTrue(model.loadMore())
        let secondPage = try XCTUnwrap(
            PRProviderBrowsePage(
                provider: .curseForge,
                offset: 20,
                pageSize: 20,
                nextOffset: nil,
                packs: []
            )
        )
        let secondResult = try XCTUnwrap(
            PRProviderBrowseResult(
                page: secondPage,
                outcome: .succeeded,
                localizationKey: "providers.browse.completed",
                diagnosticText: nil,
                retryable: false
            )
        )
        XCTAssertTrue(model.apply(result: secondResult, generation: 2))
        XCTAssertEqual(model.rows.map(\.id), ["pack.fixture"])
        XCTAssertNil(model.nextOffset)
    }

    func testBrowseAndVersionStatesCoverEmptyFailureRetryCancellationAndStaleResults() throws {
        var browseGenerations: [Int] = []
        var versionGenerations: [Int] = []
        var cancellationCount = 0
        let model = PrismProviderBrowserModel(
            onBrowse: { _, generation in browseGenerations.append(generation) },
            onLoadVersions: { _, generation in versionGenerations.append(generation) },
            onCancel: { cancellationCount += 1 }
        )

        XCTAssertTrue(model.startBrowse())
        XCTAssertFalse(model.startBrowse())
        let emptyPage = try XCTUnwrap(
            PRProviderBrowsePage(provider: .modrinth, offset: 0, pageSize: 20, nextOffset: nil, packs: [])
        )
        let emptyResult = try XCTUnwrap(
            PRProviderBrowseResult(
                page: emptyPage,
                outcome: .succeeded,
                localizationKey: "providers.browse.completed",
                diagnosticText: nil,
                retryable: false
            )
        )
        XCTAssertTrue(model.apply(result: emptyResult, generation: browseGenerations[0]))
        if case .empty(let nextOffset) = model.browseState {
            XCTAssertNil(nextOffset)
        } else {
            XCTFail("Expected empty browse state")
        }

        XCTAssertTrue(model.startBrowse())
        let failure = try XCTUnwrap(
            PRProviderBrowseResult(
                page: nil,
                outcome: .failed,
                localizationKey: "providers.browse.failed",
                diagnosticText: "fixture browse failed",
                retryable: true
            )
        )
        XCTAssertTrue(model.apply(result: failure, generation: browseGenerations[1]))
        XCTAssertTrue(model.retryBrowse())
        XCTAssertEqual(browseGenerations, [1, 2, 3])

        XCTAssertTrue(model.cancelBrowse())
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertFalse(model.apply(result: failure, generation: browseGenerations.last))

        let pack = try XCTUnwrap(
            PRProviderPack(
                provider: .modrinth,
                identifier: "pack.fixture",
                name: "Fixture Pack",
                slug: nil,
                summary: nil,
                author: nil,
                categories: [],
                versionsAvailable: true,
                supportsVersionSelection: true
            )
        )
        let page = try XCTUnwrap(
            PRProviderBrowsePage(provider: .modrinth, offset: 0, pageSize: 20, nextOffset: nil, packs: [pack])
        )
        XCTAssertTrue(model.startBrowse())
        XCTAssertTrue(model.apply(
            result: try XCTUnwrap(PRProviderBrowseResult(
                page: page,
                outcome: .succeeded,
                localizationKey: "providers.browse.completed",
                diagnosticText: nil,
                retryable: false
            )),
            generation: browseGenerations.last
        ))
        XCTAssertTrue(model.selectPack("pack.fixture"))
        XCTAssertTrue(model.loadSelectedPackVersions())
        let versionFailure = try XCTUnwrap(
            PRProviderVersionResult(
                provider: .modrinth,
                packIdentifier: "pack.fixture",
                versions: [],
                outcome: .failed,
                localizationKey: "providers.versions.failed",
                diagnosticText: "fixture versions failed",
                retryable: true
            )
        )
        XCTAssertTrue(model.apply(result: versionFailure, generation: versionGenerations[0]))
        XCTAssertTrue(model.retryVersions())
        XCTAssertEqual(versionGenerations, [1, 2])
        XCTAssertTrue(model.cancelVersions())
        XCTAssertEqual(cancellationCount, 2)
        XCTAssertFalse(model.apply(result: versionFailure, generation: versionGenerations.last))
    }

    func testCoordinatorMapsSelectedProviderVersionIntoInstallationDraft() throws {
        let coordinator = PrismProviderCoordinator(bridge: nil)
        let browserModel = PrismProviderBrowserModel()
        let installationModel = PrismProviderInstallationModel(icons: ["default"])
        coordinator.bind(browserModel: browserModel, installationModel: installationModel)

        let expectedKinds: [(PrismProvider, PRProviderInstallKind, PrismProviderInstallKind)] = [
            (.modrinth, .modrinth, .modrinth),
            (.curseForge, .curseForgeFlame, .curseForgeFlame),
            (.ftb, .FTB, .ftb),
            (.atLauncher, .atLauncher, .atLauncher),
            (.technic, .technicZip, .technicZip),
            (.technic, .technicSolder, .technicSolder),
            (.legacyFTB, .legacyFTB, .legacyFTB),
        ]
        for (provider, bridgeInstallKind, expectedKind) in expectedKinds {
            let packID = "\(provider.rawValue).pack"
            let versionID = "\(provider.rawValue).version"
            let pack = try XCTUnwrap(PrismProviderPackRow(bridgePack: try XCTUnwrap(PRProviderPack(
                provider: provider.bridgeValue,
                identifier: packID,
                name: "\(provider.displayName) Pack",
                slug: nil,
                summary: nil,
                author: nil,
                categories: [],
                versionsAvailable: true,
                supportsVersionSelection: true
            ))))
            let version = try XCTUnwrap(PrismProviderVersionRow(bridgeVersion: try XCTUnwrap(PRProviderVersion(
                provider: provider.bridgeValue,
                installKind: bridgeInstallKind,
                identifier: versionID,
                packIdentifier: packID,
                name: "Version 1",
                version: "1.0",
                gameVersions: ["1.21.1"],
                loaders: [],
                releaseType: .release,
                publishedUnixSeconds: 1,
                recommended: true
            ))))

            XCTAssertTrue(coordinator.prepareInstallation(pack: pack, version: version))
            XCTAssertEqual(coordinator.presentedInstallation, .selectedPack)
            XCTAssertEqual(installationModel.draft.kind, expectedKind)
            XCTAssertEqual(installationModel.draft.packIdentifier, packID)
            XCTAssertEqual(installationModel.draft.versionIdentifier, versionID)
            XCTAssertEqual(installationModel.draft.name, "\(provider.displayName) Pack")
            XCTAssertTrue(installationModel.canInstall)
            coordinator.dismissInstallation()
            XCTAssertNil(coordinator.presentedInstallation)
        }

        XCTAssertNil(PRProviderVersion(
            provider: .technic,
            installKind: .modrinth,
            identifier: "invalid.version",
            packIdentifier: "invalid.pack",
            name: "Invalid Version",
            version: "1.0",
            gameVersions: [],
            loaders: [],
            releaseType: .release,
            publishedUnixSeconds: 1,
            recommended: false
        ))
    }

    func testEmptyFilteredPageRetainsServerPagination() throws {
        var requests: [PRProviderBrowseRequest] = []
        let model = PrismProviderBrowserModel(onBrowse: { request, _ in requests.append(request) })

        XCTAssertTrue(model.startBrowse())
        let emptyPage = try XCTUnwrap(PRProviderBrowsePage(
            provider: .modrinth,
            offset: 0,
            pageSize: 20,
            nextOffset: NSNumber(value: 20),
            packs: []
        ))
        let result = try XCTUnwrap(PRProviderBrowseResult(
            page: emptyPage,
            outcome: .succeeded,
            localizationKey: "providers.browse.completed",
            diagnosticText: nil,
            retryable: false
        ))
        XCTAssertTrue(model.apply(result: result, generation: 1))
        XCTAssertEqual(model.nextOffset, 20)
        XCTAssertTrue(model.loadMore())
        XCTAssertEqual(requests.map(\.offset), [0, 20])
    }

    func testProviderChangeCancelsWorkAndRejectsThePreviousProviderResult() throws {
        var generations: [Int] = []
        var cancellations = 0
        let model = PrismProviderBrowserModel(
            onBrowse: { _, generation in generations.append(generation) },
            onCancel: { cancellations += 1 }
        )
        XCTAssertTrue(model.startBrowse())
        model.setProvider(.curseForge)
        XCTAssertEqual(model.provider, .curseForge)
        XCTAssertEqual(model.browseState, .idle)
        XCTAssertEqual(cancellations, 1)

        let stalePage = try XCTUnwrap(PRProviderBrowsePage(
            provider: .modrinth,
            offset: 0,
            pageSize: 20,
            nextOffset: nil,
            packs: []
        ))
        let staleResult = try XCTUnwrap(PRProviderBrowseResult(
            page: stalePage,
            outcome: .succeeded,
            localizationKey: "providers.browse.completed",
            diagnosticText: nil,
            retryable: false
        ))
        XCTAssertFalse(model.apply(result: staleResult, generation: generations[0]))
        XCTAssertEqual(model.browseState, .idle)
    }

    func testProductionCompositionRoutesDiscoverSelectionThroughBridgeOwnedCoordinator() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let browserSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/PrismProviderBrowsing.swift"),
            encoding: .utf8
        )
        let contentSource = try String(
            contentsOf: root.appendingPathComponent("PrismNative/App/ContentView.swift"),
            encoding: .utf8
        )

        for requiredToken in [
            "final class PrismProviderCoordinator",
            "bridge.browseProvider(",
            "bridge.loadProviderVersions(",
            "bridge.installProviderPack(",
            "cancelBrowsing()",
            "cancelInstallation()",
            "Install Selected Version…",
        ] {
            XCTAssertTrue(browserSource.contains(requiredToken), "Missing production provider wiring: \(requiredToken)")
        }
        for requiredToken in [
            "PrismProviderCoordinator(bridge: bridge)",
            "providerCoordinator.bind(",
            "shellModel.selectedSidebarItem == .discover",
            "PrismProviderBrowserView(model: providerBrowserModel)",
            "$providerCoordinator.presentedInstallation",
            "PrismProviderInstallationView(",
            ".interactiveDismissDisabled(providerInstallationModel.isInstalling)",
        ] {
            XCTAssertTrue(contentSource.contains(requiredToken), "Missing provider composition: \(requiredToken)")
        }
    }

    func testProviderSurfaceUsesSystemControlsAndKeepsBoundaryClean() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("PrismNative/App/PrismProviderBrowsing.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for requiredToken in [
            "PrismProviderBrowserModel",
            "PrismProviderCoordinator",
            "Form {",
            "Section(\"Filters\")",
            "\"Provider\",",
            "selection: Binding(get: { model.provider }, set: { model.setProvider($0) })",
            "TextField(\"Search provider packs\"",
            "Toggle(\"Open source only\"",
            "List(model.rows)",
            "ProgressView(",
            "ContentUnavailableView",
            ".keyboardShortcut(.defaultAction)",
            ".keyboardShortcut(.cancelAction)",
            ".accessibilityIdentifier(\"provider-browse.",
            ".accessibilityHint",
            ".formStyle(.grouped)"
        ] {
            XCTAssertTrue(source.contains(requiredToken), "Missing native provider API: \(requiredToken)")
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
            "PrismLauncher",
            "downloadURL",
            "accessToken"
        ] {
            XCTAssertFalse(source.contains(forbiddenToken), "Forbidden provider token: \(forbiddenToken)")
        }
    }
}
