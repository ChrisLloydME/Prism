import Foundation
import SwiftUI

enum PrismProvider: String, CaseIterable, Identifiable, Sendable {
    case modrinth
    case curseForge
    case ftb
    case atLauncher
    case technic
    case legacyFTB

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .modrinth: return "Modrinth"
        case .curseForge: return "CurseForge"
        case .ftb: return "FTB"
        case .atLauncher: return "ATLauncher"
        case .technic: return "Technic"
        case .legacyFTB: return "FTB Legacy"
        }
    }

    var bridgeValue: PRProviderKind {
        switch self {
        case .modrinth: return .modrinth
        case .curseForge: return .curseForge
        case .ftb: return .FTB
        case .atLauncher: return .atLauncher
        case .technic: return .technic
        case .legacyFTB: return .legacyFTB
        }
    }

    init?(bridgeValue: PRProviderKind) {
        switch bridgeValue {
        case .modrinth: self = .modrinth
        case .curseForge: self = .curseForge
        case .FTB: self = .ftb
        case .atLauncher: self = .atLauncher
        case .technic: self = .technic
        case .legacyFTB: self = .legacyFTB
        @unknown default: return nil
        }
    }
}

enum PrismProviderSort: String, CaseIterable, Identifiable, Sendable {
    case relevance
    case popularity
    case newest
    case updated
    case name
    case downloads
    case follows
    case gameVersion
    case plays
    case installs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relevance: return "Relevance"
        case .popularity: return "Popularity"
        case .newest: return "Newest"
        case .updated: return "Recently Updated"
        case .name: return "Name"
        case .downloads: return "Downloads"
        case .follows: return "Follows"
        case .gameVersion: return "Game Version"
        case .plays: return "Plays"
        case .installs: return "Installs"
        }
    }

    var bridgeValue: PRProviderSort {
        switch self {
        case .relevance: return .relevance
        case .popularity: return .popularity
        case .newest: return .newest
        case .updated: return .updated
        case .name: return .name
        case .downloads: return .downloads
        case .follows: return .follows
        case .gameVersion: return .gameVersion
        case .plays: return .plays
        case .installs: return .installs
        }
    }
}

enum PrismProviderReleaseType: String, CaseIterable, Identifiable, Sendable {
    case unknown
    case release
    case beta
    case alpha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .release: return "Release"
        case .beta: return "Beta"
        case .alpha: return "Alpha"
        }
    }

    var bridgeNumber: NSNumber {
        switch self {
        case .unknown: return NSNumber(value: 0)
        case .release: return NSNumber(value: 1)
        case .beta: return NSNumber(value: 2)
        case .alpha: return NSNumber(value: 3)
        }
    }

    init?(bridgeValue: PRProviderReleaseType) {
        switch bridgeValue {
        case .unknown: self = .unknown
        case .release: self = .release
        case .beta: self = .beta
        case .alpha: self = .alpha
        @unknown default: return nil
        }
    }
}

enum PrismProviderSide: String, CaseIterable, Identifiable, Sendable {
    case any
    case client
    case server
    case universal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any: return "Any Environment"
        case .client: return "Client"
        case .server: return "Server"
        case .universal: return "Client and Server"
        }
    }

    var bridgeValue: PRProviderSide {
        switch self {
        case .any: return .any
        case .client: return .client
        case .server: return .server
        case .universal: return .universal
        }
    }
}

struct PrismProviderFilter: Equatable, Sendable {
    var gameVersions: [String] = []
    var loaders: [String] = []
    var categories: [String] = []
    var releaseTypes: [PrismProviderReleaseType] = []
    var side: PrismProviderSide = .any
    var openSource = false
    var hideInstalled = false

    var normalized: Self {
        Self(
            gameVersions: Self.unique(gameVersions),
            loaders: Self.unique(loaders),
            categories: Self.unique(categories),
            releaseTypes: Self.unique(releaseTypes),
            side: side,
            openSource: openSource,
            hideInstalled: hideInstalled
        )
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.compactMap { value in
            seen.insert(value).inserted ? value : nil
        }
    }
}

struct PrismProviderPackRow: Identifiable, Equatable, Sendable {
    let id: String
    let provider: PrismProvider
    let name: String
    let slug: String?
    let summary: String?
    let author: String?
    let categories: [String]
    let versionsAvailable: Bool
    let supportsVersionSelection: Bool

    init?(bridgePack: PRProviderPack) {
        guard let provider = PrismProvider(bridgeValue: bridgePack.provider) else { return nil }
        let identifier = bridgePack.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = bridgePack.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, !name.isEmpty else { return nil }

        self.id = identifier
        self.provider = provider
        self.name = name
        self.slug = bridgePack.slug?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.summary = bridgePack.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.author = bridgePack.author?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.categories = bridgePack.categories
        self.versionsAvailable = bridgePack.versionsAvailable
        self.supportsVersionSelection = bridgePack.supportsVersionSelection
    }
}

struct PrismProviderVersionRow: Identifiable, Equatable, Sendable {
    let id: String
    let provider: PrismProvider
    let packIdentifier: String
    let name: String
    let version: String
    let gameVersions: [String]
    let loaders: [String]
    let releaseType: PrismProviderReleaseType
    let publishedUnixSeconds: Int
    let recommended: Bool

    init?(bridgeVersion: PRProviderVersion) {
        guard let provider = PrismProvider(bridgeValue: bridgeVersion.provider),
              let releaseType = PrismProviderReleaseType(bridgeValue: bridgeVersion.releaseType) else {
            return nil
        }
        let identifier = bridgeVersion.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let packIdentifier = bridgeVersion.packIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = bridgeVersion.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = bridgeVersion.version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, !packIdentifier.isEmpty, !name.isEmpty, !version.isEmpty else { return nil }

        self.id = identifier
        self.provider = provider
        self.packIdentifier = packIdentifier
        self.name = name
        self.version = version
        self.gameVersions = bridgeVersion.gameVersions
        self.loaders = bridgeVersion.loaders
        self.releaseType = releaseType
        self.publishedUnixSeconds = bridgeVersion.publishedUnixSeconds
        self.recommended = bridgeVersion.recommended
    }
}

struct PrismProviderFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let retryable: Bool

    var isRetryAvailable: Bool { retryable }
}

enum PrismProviderBrowseState: Equatable, Sendable {
    case idle
    case loading
    case loadingMore(rows: [PrismProviderPackRow], nextOffset: Int?)
    case loaded(rows: [PrismProviderPackRow], nextOffset: Int?)
    case empty
    case cancelled
    case failed(PrismProviderFailure)
}

enum PrismProviderVersionState: Equatable, Sendable {
    case idle
    case loading
    case loaded([PrismProviderVersionRow])
    case empty
    case cancelled
    case failed(PrismProviderFailure)
}

@MainActor
final class PrismProviderBrowserModel: ObservableObject {
    @Published var provider: PrismProvider
    @Published var query: String
    @Published var sort: PrismProviderSort
    @Published var filter: PrismProviderFilter
    @Published private(set) var browseState: PrismProviderBrowseState = .idle
    @Published private(set) var versionState: PrismProviderVersionState = .idle
    @Published private(set) var selectedPackIdentifier: String?
    @Published private(set) var selectedVersionIdentifier: String?
    @Published private(set) var browseProgress: PrismTaskPresentation?
    @Published private(set) var versionProgress: PrismTaskPresentation?

    let pageSize: Int
    let providers: [PrismProvider]
    private let onBrowse: ((PRProviderBrowseRequest, Int) -> Void)?
    private let onLoadVersions: ((PRProviderVersionRequest, Int) -> Void)?
    private let onCancel: (() -> Void)?
    private var browseGeneration = 0
    private var versionGeneration = 0

    init(
        providers: [PrismProvider] = PrismProvider.allCases,
        initialProvider: PrismProvider = .modrinth,
        pageSize: Int = 20,
        query: String = "",
        sort: PrismProviderSort = .relevance,
        filter: PrismProviderFilter = PrismProviderFilter(),
        onBrowse: ((PRProviderBrowseRequest, Int) -> Void)? = nil,
        onLoadVersions: ((PRProviderVersionRequest, Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        let uniqueProviders = Self.unique(providers)
        self.providers = uniqueProviders.isEmpty ? [.modrinth] : uniqueProviders
        self.provider = self.providers.contains(initialProvider) ? initialProvider : self.providers[0]
        self.pageSize = min(max(pageSize, 1), 100)
        self.query = query
        self.sort = sort
        self.filter = filter.normalized
        self.onBrowse = onBrowse
        self.onLoadVersions = onLoadVersions
        self.onCancel = onCancel
    }

    var rows: [PrismProviderPackRow] {
        switch browseState {
        case .loadingMore(let rows, _), .loaded(let rows, _): return rows
        default: return []
        }
    }

    var nextOffset: Int? {
        switch browseState {
        case .loadingMore(_, let nextOffset), .loaded(_, let nextOffset): return nextOffset
        default: return nil
        }
    }

    var selectedPack: PrismProviderPackRow? {
        guard let selectedPackIdentifier else { return nil }
        return rows.first(where: { $0.id == selectedPackIdentifier })
    }

    var versions: [PrismProviderVersionRow] {
        if case .loaded(let versions) = versionState { return versions }
        return []
    }

    var selectedVersion: PrismProviderVersionRow? {
        guard let selectedVersionIdentifier else { return nil }
        return versions.first(where: { $0.id == selectedVersionIdentifier })
    }

    var isBrowsing: Bool {
        switch browseState {
        case .loading, .loadingMore: return true
        default: return false
        }
    }

    var isLoadingVersions: Bool {
        if case .loading = versionState { return true }
        return false
    }

    @discardableResult
    func startBrowse() -> Bool {
        guard !isBrowsing else { return false }
        browseGeneration += 1
        browseProgress = nil
        browseState = .loading
        onBrowse?(makeBrowseRequest(offset: 0), browseGeneration)
        return true
    }

    @discardableResult
    func loadMore() -> Bool {
        guard !isBrowsing, let nextOffset else { return false }
        let currentRows = rows
        browseGeneration += 1
        browseProgress = nil
        browseState = .loadingMore(rows: currentRows, nextOffset: nextOffset)
        onBrowse?(makeBrowseRequest(offset: nextOffset), browseGeneration)
        return true
    }

    @discardableResult
    func cancelBrowse() -> Bool {
        guard isBrowsing else { return false }
        browseGeneration += 1
        browseProgress = nil
        onCancel?()
        browseState = .cancelled
        return true
    }

    @discardableResult
    func retryBrowse() -> Bool {
        guard case .failed(let failure) = browseState, failure.isRetryAvailable else { return false }
        return startBrowse()
    }

    @discardableResult
    func selectPack(_ identifier: String) -> Bool {
        guard let pack = rows.first(where: { $0.id == identifier }), pack.supportsVersionSelection else { return false }
        selectedPackIdentifier = pack.id
        selectedVersionIdentifier = nil
        versionProgress = nil
        versionState = .idle
        return true
    }

    @discardableResult
    func loadSelectedPackVersions() -> Bool {
        guard !isLoadingVersions, let pack = selectedPack else { return false }
        versionGeneration += 1
        versionProgress = nil
        versionState = .loading
        let normalizedFilter = filter.normalized
        guard let request = PRProviderVersionRequest(
                provider: provider.bridgeValue,
                packIdentifier: pack.id,
                gameVersions: normalizedFilter.gameVersions,
                loaders: normalizedFilter.loaders
        ) else {
            versionState = .failed(PrismProviderFailure(
                localizationKey: "providers.versions.invalidRequest", diagnosticText: nil, retryable: true))
            return false
        }
        onLoadVersions?(request, versionGeneration)
        return true
    }

    @discardableResult
    func cancelVersions() -> Bool {
        guard isLoadingVersions else { return false }
        versionGeneration += 1
        versionProgress = nil
        onCancel?()
        versionState = .cancelled
        return true
    }

    @discardableResult
    func retryVersions() -> Bool {
        guard case .failed(let failure) = versionState, failure.isRetryAvailable else { return false }
        return loadSelectedPackVersions()
    }

    @discardableResult
    func selectVersion(_ identifier: String) -> Bool {
        guard versions.contains(where: { $0.id == identifier }) else { return false }
        selectedVersionIdentifier = identifier
        return true
    }

    @discardableResult
    func apply(progress bridgeProgress: PRTaskStatus, generation: Int? = nil) -> Bool {
        guard isBrowsing, (generation ?? browseGeneration) == browseGeneration,
              let progress = PrismTaskPresentation(bridgeStatus: bridgeProgress) else { return false }
        browseProgress = progress
        return true
    }

    @discardableResult
    func apply(result bridgeResult: PRProviderBrowseResult, generation: Int? = nil) -> Bool {
        guard isBrowsing, (generation ?? browseGeneration) == browseGeneration,
              let outcome = PrismProviderBrowseOutcome(bridgeOutcome: bridgeResult.outcome) else { return false }
        browseProgress = nil

        switch outcome {
        case .succeeded:
            guard let page = bridgeResult.page,
                  let pageProvider = PrismProvider(bridgeValue: page.provider),
                  pageProvider == provider,
                  page.offset == (browseState.isLoadingMore ? nextOffset : 0),
                  page.pageSize == pageSize else {
                browseState = .failed(PrismProviderFailure(
                    localizationKey: "providers.browse.invalidResult", diagnosticText: nil, retryable: true))
                return false
            }
            let convertedRows = page.packs.compactMap(PrismProviderPackRow.init(bridgePack:))
            guard convertedRows.count == page.packs.count,
                  Set(convertedRows.map(\.id)).count == convertedRows.count else {
                browseState = .failed(PrismProviderFailure(
                    localizationKey: "providers.browse.invalidResult", diagnosticText: nil, retryable: true))
                return false
            }
            let mergedRows: [PrismProviderPackRow]
            if browseState.isLoadingMore {
                mergedRows = rows + convertedRows
            } else {
                mergedRows = convertedRows
            }
            guard Set(mergedRows.map(\.id)).count == mergedRows.count else {
                browseState = .failed(PrismProviderFailure(
                    localizationKey: "providers.browse.duplicateResult", diagnosticText: nil, retryable: true))
                return false
            }
            browseState = mergedRows.isEmpty ? .empty : .loaded(rows: mergedRows, nextOffset: page.nextOffset?.intValue)
        case .failed, .rejected:
            let key = bridgeResult.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return false }
            browseState = .failed(PrismProviderFailure(
                localizationKey: key, diagnosticText: bridgeResult.diagnosticText, retryable: bridgeResult.retryable))
        case .cancelled:
            browseState = .cancelled
        }
        return true
    }

    @discardableResult
    func apply(progress bridgeProgress: PRTaskStatus, generation: Int? = nil, toVersions: Bool) -> Bool {
        guard toVersions, isLoadingVersions, (generation ?? versionGeneration) == versionGeneration,
              let progress = PrismTaskPresentation(bridgeStatus: bridgeProgress) else { return false }
        versionProgress = progress
        return true
    }

    @discardableResult
    func apply(result bridgeResult: PRProviderVersionResult, generation: Int? = nil) -> Bool {
        guard isLoadingVersions, (generation ?? versionGeneration) == versionGeneration,
              let outcome = PrismProviderVersionOutcome(bridgeOutcome: bridgeResult.outcome),
              let selectedPackIdentifier,
              bridgeResult.packIdentifier == selectedPackIdentifier,
              PrismProvider(bridgeValue: bridgeResult.provider) == provider else { return false }
        versionProgress = nil

        switch outcome {
        case .succeeded:
            let converted = bridgeResult.versions.compactMap(PrismProviderVersionRow.init(bridgeVersion:))
            guard converted.count == bridgeResult.versions.count,
                  Set(converted.map(\.id)).count == converted.count else {
                versionState = .failed(PrismProviderFailure(
                    localizationKey: "providers.versions.invalidResult", diagnosticText: nil, retryable: true))
                return false
            }
            versionState = converted.isEmpty ? .empty : .loaded(converted)
        case .failed, .rejected:
            let key = bridgeResult.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return false }
            versionState = .failed(PrismProviderFailure(
                localizationKey: key, diagnosticText: bridgeResult.diagnosticText, retryable: bridgeResult.retryable))
        case .cancelled:
            versionState = .cancelled
        }
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, generation: Int? = nil) -> Bool {
        guard isBrowsing, (generation ?? browseGeneration) == browseGeneration else { return false }
        let key = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        browseProgress = nil
        browseState = .failed(PrismProviderFailure(
            localizationKey: key, diagnosticText: error.diagnosticText, retryable: error.recoveryKind == .retry))
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, generation: Int? = nil, toVersions: Bool) -> Bool {
        guard toVersions, isLoadingVersions, (generation ?? versionGeneration) == versionGeneration else { return false }
        let key = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        versionProgress = nil
        versionState = .failed(PrismProviderFailure(
            localizationKey: key, diagnosticText: error.diagnosticText, retryable: error.recoveryKind == .retry))
        return true
    }

    func resetSelection() {
        selectedPackIdentifier = nil
        selectedVersionIdentifier = nil
        versionProgress = nil
        versionState = .idle
    }

    private func makeBrowseRequest(offset: Int) -> PRProviderBrowseRequest {
        let normalizedFilter = filter.normalized
        return PRProviderBrowseRequest(
            provider: provider.bridgeValue,
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            offset: offset,
            pageSize: pageSize,
            sort: sort.bridgeValue,
            gameVersions: normalizedFilter.gameVersions,
            loaders: normalizedFilter.loaders,
            categories: normalizedFilter.categories,
            releaseTypes: normalizedFilter.releaseTypes.map(\.bridgeNumber),
            side: normalizedFilter.side.bridgeValue,
            openSource: normalizedFilter.openSource,
            hideInstalled: normalizedFilter.hideInstalled
        )!
    }

    private static func unique(_ providers: [PrismProvider]) -> [PrismProvider] {
        var seen = Set<PrismProvider>()
        return providers.filter { seen.insert($0).inserted }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension PrismProviderBrowseState {
    var isLoadingMore: Bool {
        if case .loadingMore = self { return true }
        return false
    }
}

enum PrismProviderBrowseOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
    case rejected

    init?(bridgeOutcome: PRProviderBrowseOutcome) {
        switch bridgeOutcome {
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        case .rejected: self = .rejected
        @unknown default: return nil
        }
    }
}

enum PrismProviderVersionOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
    case rejected

    init?(bridgeOutcome: PRProviderVersionOutcome) {
        switch bridgeOutcome {
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        case .rejected: self = .rejected
        @unknown default: return nil
        }
    }
}

@MainActor
struct PrismProviderBrowserView: View {
    @ObservedObject var model: PrismProviderBrowserModel

    private var gameVersionsText: Binding<String> {
        Binding(
            get: { model.filter.gameVersions.joined(separator: ", ") },
            set: { model.filter.gameVersions = Self.split($0) }
        )
    }

    private var loadersText: Binding<String> {
        Binding(
            get: { model.filter.loaders.joined(separator: ", ") },
            set: { model.filter.loaders = Self.split($0) }
        )
    }

    private var categoriesText: Binding<String> {
        Binding(
            get: { model.filter.categories.joined(separator: ", ") },
            set: { model.filter.categories = Self.split($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Provider") {
                    Picker("Provider", selection: $model.provider) {
                        ForEach(model.providers) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .accessibilityIdentifier("provider-browse.provider")
                }

                Section("Search") {
                    TextField("Search provider packs", text: $model.query)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("provider-browse.query")
                        .onSubmit { _ = model.startBrowse() }
                    Picker("Sort", selection: $model.sort) {
                        ForEach(PrismProviderSort.allCases) { sort in
                            Text(sort.displayName).tag(sort)
                        }
                    }
                    .accessibilityIdentifier("provider-browse.sort")
                    HStack {
                        Button("Search") { _ = model.startBrowse() }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("provider-browse.search")
                        if model.isBrowsing {
                            Button("Cancel") { _ = model.cancelBrowse() }
                                .keyboardShortcut(.cancelAction)
                                .accessibilityIdentifier("provider-browse.cancel")
                        }
                    }
                }

                Section("Filters") {
                    TextField("Game versions", text: gameVersionsText)
                        .accessibilityIdentifier("provider-browse.game-versions")
                    TextField("Loaders", text: loadersText)
                        .accessibilityIdentifier("provider-browse.loaders")
                    TextField("Categories", text: categoriesText)
                        .accessibilityIdentifier("provider-browse.categories")
                    Picker("Environment", selection: $model.filter.side) {
                        ForEach(PrismProviderSide.allCases) { side in
                            Text(side.displayName).tag(side)
                        }
                    }
                    .accessibilityIdentifier("provider-browse.environment")
                    ForEach(PrismProviderReleaseType.allCases) { releaseType in
                        Toggle(releaseType.displayName, isOn: Binding(
                            get: { model.filter.releaseTypes.contains(releaseType) },
                            set: { isSelected in
                                if isSelected {
                                    model.filter.releaseTypes.append(releaseType)
                                } else {
                                    model.filter.releaseTypes.removeAll { $0 == releaseType }
                                }
                            }
                        ))
                        .accessibilityIdentifier("provider-browse.release-\(releaseType.id)")
                    }
                    Toggle("Open source only", isOn: $model.filter.openSource)
                        .accessibilityIdentifier("provider-browse.open-source")
                    Toggle("Hide installed items", isOn: $model.filter.hideInstalled)
                        .accessibilityIdentifier("provider-browse.hide-installed")
                }
            }
            .formStyle(.grouped)

            Divider()
            browseContent
            versionContent
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("provider-browse.surface")
    }

    @ViewBuilder
    private var browseContent: some View {
        switch model.browseState {
        case .idle:
            ContentUnavailableView("Search Providers", systemImage: "magnifyingglass", description: Text("Choose filters and search for provider packs."))
        case .loading:
            VStack(spacing: 8) {
                ProgressView("Searching Providers")
                if model.browseProgress?.progress.fraction == nil {
                    Text("Loading provider results…")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        case .loadingMore, .loaded:
            List(model.rows) { pack in
                Button {
                    _ = model.selectPack(pack.id)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Label(pack.name, systemImage: pack.id == model.selectedPackIdentifier ? "checkmark.circle.fill" : "shippingbox")
                        Spacer()
                        if let author = pack.author {
                            Text(author).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(pack.name))
                .accessibilityValue(Text(pack.summary ?? "Provider pack"))
                .accessibilityIdentifier("provider-browse.pack-\(pack.id)")
            }
            .frame(minHeight: 150)
            if model.nextOffset != nil {
                Button("Load More") { _ = model.loadMore() }
                    .disabled(model.isBrowsing)
                    .accessibilityIdentifier("provider-browse.load-more")
                    .padding(.bottom, 8)
            }
        case .empty:
            ContentUnavailableView("No Provider Packs", systemImage: "shippingbox", description: Text("No packs match the current search and filters."))
        case .cancelled:
            ContentUnavailableView("Search Cancelled", systemImage: "pause.circle", description: Text("The provider search was cancelled."))
        case .failed(let failure):
            ContentUnavailableView {
                Label("Provider Search Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure.diagnosticText ?? failure.localizationKey)
            } actions: {
                if failure.isRetryAvailable {
                    Button("Retry") { _ = model.retryBrowse() }
                        .accessibilityIdentifier("provider-browse.retry")
                }
            }
        }
    }

    @ViewBuilder
    private var versionContent: some View {
        if let pack = model.selectedPack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Versions for \(pack.name)").font(.headline)
                    Spacer()
                    if model.isLoadingVersions {
                        Button("Cancel") { _ = model.cancelVersions() }
                            .keyboardShortcut(.cancelAction)
                            .accessibilityIdentifier("provider-browse.versions-cancel")
                    } else {
                        Button("Load Versions") { _ = model.loadSelectedPackVersions() }
                            .accessibilityIdentifier("provider-browse.versions-load")
                    }
                }
                switch model.versionState {
                case .idle:
                    Text("Select Load Versions to see available choices.").foregroundStyle(.secondary)
                case .loading:
                    ProgressView("Loading Versions")
                case .loaded(let versions):
                    List(versions) { version in
                        Button {
                            _ = model.selectVersion(version.id)
                        } label: {
                            HStack {
                                Label(version.name, systemImage: version.recommended ? "star.fill" : "circle")
                                Spacer()
                                if version.id == model.selectedVersionIdentifier {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(Text(version.version))
                        .accessibilityIdentifier("provider-browse.version-\(version.id)")
                    }
                    .frame(minHeight: 110)
                case .empty:
                    ContentUnavailableView("No Versions", systemImage: "list.bullet", description: Text("This pack has no compatible versions."))
                case .cancelled:
                    ContentUnavailableView("Version Loading Cancelled", systemImage: "pause.circle")
                case .failed(let failure):
                    ContentUnavailableView {
                        Label("Version Loading Failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(failure.diagnosticText ?? failure.localizationKey)
                    } actions: {
                        if failure.isRetryAvailable {
                            Button("Retry") { _ = model.retryVersions() }
                                .accessibilityIdentifier("provider-browse.versions-retry")
                        }
                    }
                }
            }
            .padding()
            .accessibilityIdentifier("provider-browse.versions")
        }
    }

    private static func split(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

#Preview {
    PrismProviderBrowserView(model: PrismProviderBrowserModel())
}
