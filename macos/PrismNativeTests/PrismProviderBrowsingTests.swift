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

        let version = try XCTUnwrap(
            PRProviderVersion(
                provider: .curseForge,
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
        if case .empty = model.browseState {} else { XCTFail("Expected empty browse state") }

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

    func testProviderSurfaceUsesSystemControlsAndKeepsBoundaryClean() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("PrismNative/App/PrismProviderBrowsing.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for requiredToken in [
            "PrismProviderBrowserModel",
            "Form {",
            "Section(\"Filters\")",
            "Picker(\"Provider\"",
            "TextField(\"Search provider packs\"",
            "Toggle(\"Open source only\"",
            "List(model.rows)",
            "ProgressView(",
            "ContentUnavailableView",
            ".keyboardShortcut(.defaultAction)",
            ".keyboardShortcut(.cancelAction)",
            ".accessibilityIdentifier(\"provider-browse.",
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
