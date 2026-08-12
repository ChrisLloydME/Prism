import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PrismAboutMetadata: Equatable, Sendable {
    let productName: String
    let version: String
    let buildPlatform: String?
    let commit: String?
    let buildDate: String?
    let channel: String?
    let repositoryURL: URL?
    let copyright: String
    let aboutText: String
    let creditsText: String
    let licenseText: String

    init(
        productName: String,
        version: String,
        buildPlatform: String? = nil,
        commit: String? = nil,
        buildDate: String? = nil,
        channel: String? = nil,
        repositoryURL: URL? = nil,
        copyright: String,
        aboutText: String,
        creditsText: String,
        licenseText: String
    ) {
        self.productName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        self.buildPlatform = buildPlatform?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.commit = commit?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.buildDate = buildDate?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.channel = channel?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.repositoryURL = repositoryURL.flatMap(Self.safeWebURL)
        self.copyright = copyright
        self.aboutText = aboutText
        self.creditsText = creditsText
        self.licenseText = licenseText
    }

    static func fromBundle(_ bundle: Bundle = .main) -> Self {
        let info = bundle.infoDictionary ?? [:]
        func value(_ key: String, fallback: String) -> String {
            guard let string = info[key] as? String,
                  !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return fallback
            }
            return string
        }

        let repositoryURL = URL(string: value("PrismRepositoryURL", fallback: "https://github.com/ChrisLloydME/Prism"))
        return Self(
            productName: value("CFBundleDisplayName", fallback: "Prism"),
            version: value("CFBundleShortVersionString", fallback: "Unavailable"),
            buildPlatform: value("PrismBuildPlatform", fallback: "macOS"),
            commit: (info["PrismGitCommit"] as? String),
            buildDate: (info["PrismBuildDate"] as? String),
            channel: (info["PrismVersionChannel"] as? String),
            repositoryURL: repositoryURL,
            copyright: value("NSHumanReadableCopyright", fallback: "Prism Launcher contributors"),
            aboutText: "A native macOS launcher for managing Minecraft instances.",
            creditsText: "Prism Launcher is built and maintained by its contributors and the open-source community.",
            licenseText: "Prism is distributed under the GNU General Public License, version 3."
        )
    }

    static let fixture = Self(
        productName: "Prism",
        version: "9.9.9-fixture",
        buildPlatform: "macOS arm64 fixture",
        commit: "fixture-commit",
        buildDate: "2026-08-09",
        channel: "fixture",
        repositoryURL: URL(string: "https://github.com/ChrisLloydME/Prism"),
        copyright: "Prism Launcher contributors",
        aboutText: "A native macOS launcher for managing Minecraft instances.",
        creditsText: "Fixture credits for non-launch native verification.",
        licenseText: "Fixture license text for non-launch native verification."
    )

    private static func safeWebURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}

struct PrismNewsEntry: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let link: URL
    let content: String
    let publishedDate: String?

    init?(id: String, title: String, link: URL, content: String, publishedDate: String? = nil) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty,
              !normalizedTitle.isEmpty,
              !normalizedContent.isEmpty,
              link.scheme?.lowercased() == "https",
              link.host?.isEmpty == false else {
            return nil
        }

        self.id = normalizedID
        self.title = normalizedTitle
        self.link = link
        self.content = normalizedContent
        self.publishedDate = publishedDate?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    static let fixture = Self(
        id: "news.fixture",
        title: "Fixture News",
        link: URL(string: "https://example.invalid/news/fixture")!,
        content: "Fixture news content for non-launch native verification.",
        publishedDate: "2026-08-09"
    )!
}

struct PrismNewsFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let retryable: Bool

    var isRetryAvailable: Bool { retryable }
}

enum PrismNewsState: Equatable, Sendable {
    case loading
    case empty
    case content([PrismNewsEntry])
    case failed(PrismNewsFailure)
    case cancelled
}

@MainActor
final class PrismNewsModel: ObservableObject {
    @Published private(set) var state: PrismNewsState
    @Published private(set) var selectedEntryID: String?
    @Published private(set) var isArticleListVisible = true

    private var generation = 0
    private let onLoad: ((Int) -> Void)?
    private let onCancel: (() -> Void)?
    private let bridge: PRPrismBridge?
    private var requestToken: PRBridgeObservationToken?

    init(
        initialState: PrismNewsState = .empty,
        bridge: PRPrismBridge? = nil,
        onLoad: ((Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.state = initialState
        self.bridge = bridge
        self.onLoad = onLoad
        self.onCancel = onCancel
        if case .content(let entries) = initialState {
            self.selectedEntryID = entries.first?.id
        }
    }

    var entries: [PrismNewsEntry] {
        guard case .content(let entries) = state else { return [] }
        return entries
    }

    var selectedEntry: PrismNewsEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    @discardableResult
    func load() -> Bool {
        guard !isLoading else { return false }
        generation += 1
        let activeGeneration = generation
        selectedEntryID = nil
        state = .loading
        requestToken?.cancel()
        if let bridge {
            requestToken = bridge.loadNews { [weak self] result, error in
                self?.requestToken = nil
                guard let self else { return }
                if let result {
                    _ = self.apply(bridgeResult: result, generation: activeGeneration)
                } else if let error {
                    _ = self.apply(
                        failure: PrismNewsFailure(
                            localizationKey: error.localizationKey,
                            diagnosticText: error.diagnosticText,
                            retryable: error.recoveryKind == .retry
                        ),
                        generation: activeGeneration
                    )
                }
            }
        } else if let onLoad {
            onLoad(generation)
        } else {
            state = .failed(PrismNewsFailure(
                localizationKey: "news.adapterUnavailable",
                diagnosticText: nil,
                retryable: false
            ))
        }
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard isLoading else { return false }
        generation += 1
        requestToken?.cancel()
        requestToken = nil
        onCancel?()
        state = .cancelled
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard case .failed(let failure) = state, failure.isRetryAvailable else { return false }
        return load()
    }

    @discardableResult
    func apply(entries: [PrismNewsEntry], generation resultGeneration: Int? = nil) -> Bool {
        guard (resultGeneration ?? generation) == generation,
              Self.isValid(entries) else { return false }
        state = entries.isEmpty ? .empty : .content(entries)
        selectedEntryID = entries.first?.id
        return true
    }

    @discardableResult
    func apply(failure: PrismNewsFailure, generation resultGeneration: Int? = nil) -> Bool {
        guard (resultGeneration ?? generation) == generation,
              !failure.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        state = .failed(failure)
        selectedEntryID = nil
        return true
    }

    @discardableResult
    func selectEntry(_ identifier: String?) -> Bool {
        guard let identifier,
              entries.contains(where: { $0.id == identifier }) else { return false }
        selectedEntryID = identifier
        return true
    }

    func toggleArticleList() {
        isArticleListVisible.toggle()
    }

    private static func isValid(_ entries: [PrismNewsEntry]) -> Bool {
        Set(entries.map(\.id)).count == entries.count && entries.allSatisfy { !$0.id.isEmpty }
    }

    private func apply(bridgeResult: PRNewsLoadResult, generation resultGeneration: Int) -> Bool {
        switch bridgeResult.outcome {
        case .succeeded:
            let entries = bridgeResult.entries.compactMap {
                PrismNewsEntry(
                    id: $0.identifier,
                    title: $0.title,
                    link: $0.link,
                    content: $0.content,
                    publishedDate: $0.publishedDate
                )
            }
            guard entries.count == bridgeResult.entries.count else { return false }
            return apply(entries: entries, generation: resultGeneration)
        case .cancelled:
            guard resultGeneration == generation else { return false }
            state = .cancelled
            selectedEntryID = nil
            return true
        case .failed, .rejected:
            return apply(
                failure: PrismNewsFailure(
                    localizationKey: bridgeResult.localizationKey,
                    diagnosticText: bridgeResult.diagnosticText,
                    retryable: bridgeResult.retryable
                ),
                generation: resultGeneration
            )
        @unknown default:
            return apply(
                failure: PrismNewsFailure(
                    localizationKey: "news.unknownOutcome",
                    diagnosticText: nil,
                    retryable: true
                ),
                generation: resultGeneration
            )
        }
    }
}

enum PrismUpdateDecision: Equatable, Sendable {
    case install
    case remindLater
    case skipVersion
}

struct PrismUpdateNotice: Equatable, Sendable {
    let currentVersion: String
    let availableVersion: String
    let releaseNotes: String

    init?(currentVersion: String, availableVersion: String, releaseNotes: String) {
        let current = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let available = availableVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty, !available.isEmpty, !notes.isEmpty else { return nil }
        self.currentVersion = current
        self.availableVersion = available
        self.releaseNotes = notes
    }

    static let fixture = Self(
        currentVersion: "9.0.0",
        availableVersion: "9.1.0",
        releaseNotes: "Fixture release notes for non-launch native verification."
    )!
}

struct PrismUpdateFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let retryable: Bool
}

enum PrismUpdateState: Equatable, Sendable {
    case idle
    case checking
    case noUpdate
    case available(PrismUpdateNotice)
    case failed(PrismUpdateFailure)
    case cancelled
    case decided(PrismUpdateDecision)
}

@MainActor
final class PrismUpdateModel: ObservableObject {
    @Published private(set) var state: PrismUpdateState = .idle
    private var generation = 0
    private let onCheck: ((Int) -> Void)?
    private let onDecision: ((PrismUpdateDecision, PrismUpdateNotice) -> Void)?
    private let bridge: PRPrismBridge?
    private let currentVersion: String
    private var requestToken: PRBridgeObservationToken?

    init(
        currentVersion: String = PrismAboutMetadata.fromBundle().version,
        bridge: PRPrismBridge? = nil,
        onCheck: ((Int) -> Void)? = nil,
        onDecision: ((PrismUpdateDecision, PrismUpdateNotice) -> Void)? = nil
    ) {
        self.currentVersion = currentVersion
        self.bridge = bridge
        self.onCheck = onCheck
        self.onDecision = onDecision
    }

    var notice: PrismUpdateNotice? {
        guard case .available(let notice) = state else { return nil }
        return notice
    }

    @discardableResult
    func check() -> Bool {
        guard state != .checking else { return false }
        generation += 1
        let activeGeneration = generation
        state = .checking
        requestToken?.cancel()
        if let bridge {
            requestToken = bridge.checkForUpdates(withCurrentVersion: currentVersion) { [weak self] result, error in
                self?.requestToken = nil
                guard let self else { return }
                if let result {
                    _ = self.apply(bridgeResult: result, generation: activeGeneration)
                } else if let error {
                    _ = self.apply(
                        failure: PrismUpdateFailure(
                            localizationKey: error.localizationKey,
                            diagnosticText: error.diagnosticText,
                            retryable: error.recoveryKind == .retry
                        ),
                        generation: activeGeneration
                    )
                }
            }
        } else if let onCheck {
            onCheck(generation)
        } else {
            state = .failed(PrismUpdateFailure(
                localizationKey: "updates.adapterUnavailable",
                diagnosticText: nil,
                retryable: false
            ))
        }
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard state == .checking else { return false }
        generation += 1
        requestToken?.cancel()
        requestToken = nil
        state = .cancelled
        return true
    }

    @discardableResult
    func apply(notice: PrismUpdateNotice, generation resultGeneration: Int? = nil) -> Bool {
        guard state == .checking, (resultGeneration ?? generation) == generation else { return false }
        state = .available(notice)
        return true
    }

    @discardableResult
    func applyNoUpdate(generation resultGeneration: Int? = nil) -> Bool {
        guard state == .checking, (resultGeneration ?? generation) == generation else { return false }
        state = .noUpdate
        return true
    }

    @discardableResult
    func apply(failure: PrismUpdateFailure, generation resultGeneration: Int? = nil) -> Bool {
        guard state == .checking,
              (resultGeneration ?? generation) == generation,
              !failure.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        state = .failed(failure)
        return true
    }

    @discardableResult
    func choose(_ decision: PrismUpdateDecision) -> Bool {
        guard let notice else { return false }
        generation += 1
        let activeGeneration = generation
        state = .decided(decision)
        requestToken?.cancel()
        if let bridge {
            requestToken = bridge.apply(
                decision.bridgeDecision,
                availableVersion: notice.availableVersion
            ) { [weak self] result, error in
                self?.requestToken = nil
                guard let self, activeGeneration == self.generation else { return }
                if let error {
                    self.state = .failed(PrismUpdateFailure(
                        localizationKey: error.localizationKey,
                        diagnosticText: error.diagnosticText,
                        retryable: error.recoveryKind == .retry
                    ))
                } else if let result,
                          result.outcome != .succeeded {
                    self.state = .failed(PrismUpdateFailure(
                        localizationKey: result.localizationKey,
                        diagnosticText: result.diagnosticText,
                        retryable: result.retryable
                    ))
                }
            }
        } else {
            onDecision?(decision, notice)
        }
        return true
    }

    private func apply(bridgeResult: PRUpdateCheckResult, generation resultGeneration: Int) -> Bool {
        switch bridgeResult.outcome {
        case .noUpdate:
            return applyNoUpdate(generation: resultGeneration)
        case .available:
            guard let value = bridgeResult.notice,
                  let notice = PrismUpdateNotice(
                      currentVersion: value.currentVersion,
                      availableVersion: value.availableVersion,
                      releaseNotes: value.releaseNotes
                  ) else { return false }
            return apply(notice: notice, generation: resultGeneration)
        case .cancelled:
            guard state == .checking, resultGeneration == generation else { return false }
            state = .cancelled
            return true
        case .failed, .rejected:
            return apply(
                failure: PrismUpdateFailure(
                    localizationKey: bridgeResult.localizationKey,
                    diagnosticText: bridgeResult.diagnosticText,
                    retryable: bridgeResult.retryable
                ),
                generation: resultGeneration
            )
        @unknown default:
            return apply(
                failure: PrismUpdateFailure(
                    localizationKey: "updates.unknownOutcome",
                    diagnosticText: nil,
                    retryable: true
                ),
                generation: resultGeneration
            )
        }
    }
}

private extension PrismUpdateDecision {
    var bridgeDecision: PRUpdateDecision {
        switch self {
        case .install: return .install
        case .remindLater: return .remindLater
        case .skipVersion: return .skipVersion
        }
    }
}

enum PrismProviderChoiceAction: Equatable, Sendable {
    case confirmOne
    case confirmAll
    case skipOne
    case skipAll
}

struct PrismProviderChoiceResponse: Equatable, Sendable {
    let action: PrismProviderChoiceAction
    let provider: PrismProvider?
    let tryOthers: Bool
}

enum PrismProviderChoiceState: Equatable, Sendable {
    case editing
    case completed(PrismProviderChoiceResponse)
}

@MainActor
final class PrismProviderChoiceModel: ObservableObject {
    @Published private(set) var state: PrismProviderChoiceState = .editing
    @Published private(set) var selectedProvider: PrismProvider
    @Published var tryOthers = false
    @Published var descriptionText: String
    let providers: [PrismProvider]
    let singleChoice: Bool
    let allowSkipping: Bool
    private let onDecision: ((PrismProviderChoiceResponse) -> Void)?

    init(
        providers: [PrismProvider] = PrismProvider.allCases,
        initialProvider: PrismProvider? = nil,
        singleChoice: Bool = false,
        allowSkipping: Bool = true,
        description: String = "Choose a provider for this resource.",
        onDecision: ((PrismProviderChoiceResponse) -> Void)? = nil
    ) {
        var uniqueProviders: [PrismProvider] = []
        for provider in providers where !uniqueProviders.contains(provider) {
            uniqueProviders.append(provider)
        }
        self.providers = uniqueProviders
        self.selectedProvider = initialProvider.flatMap { uniqueProviders.contains($0) ? $0 : nil } ?? uniqueProviders.first ?? .modrinth
        self.singleChoice = singleChoice
        self.allowSkipping = allowSkipping
        self.descriptionText = description
        self.onDecision = onDecision
    }

    var canConfirm: Bool {
        providers.contains(selectedProvider) && state == .editing
    }

    func setProvider(_ provider: PrismProvider) {
        guard providers.contains(provider), state == .editing else { return }
        selectedProvider = provider
    }

    @discardableResult
    func choose(_ action: PrismProviderChoiceAction) -> Bool {
        guard state == .editing else { return false }
        guard action == .confirmOne || action == .confirmAll || allowSkipping else { return false }
        if singleChoice && action == .confirmAll { return false }
        let response = PrismProviderChoiceResponse(
            action: action,
            provider: action == .skipOne || action == .skipAll ? nil : selectedProvider,
            tryOthers: tryOthers
        )
        state = .completed(response)
        onDecision?(response)
        return true
    }

    func reset() {
        state = .editing
    }
}

struct PrismRecoveryDetail: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String

    init?(id: String, label: String, value: String) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty, !normalizedLabel.isEmpty else { return nil }
        self.id = normalizedID
        self.label = normalizedLabel
        self.value = value
    }
}

struct PrismRecoveryMessage: Equatable, Sendable {
    let titleKey: String
    let messageKey: String
    let diagnosticText: String?
    let details: [PrismRecoveryDetail]
    let retryAvailable: Bool
    let editAvailable: Bool
    let partialChangesRolledBack: Bool

    init(
        titleKey: String,
        messageKey: String,
        diagnosticText: String? = nil,
        details: [PrismRecoveryDetail] = [],
        retryAvailable: Bool,
        editAvailable: Bool,
        partialChangesRolledBack: Bool
    ) {
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.diagnosticText = diagnosticText
        self.details = details
        self.retryAvailable = retryAvailable
        self.editAvailable = editAvailable
        self.partialChangesRolledBack = partialChangesRolledBack
    }
}

enum PrismRecoveryDecision: Equatable, Sendable {
    case retry
    case edit
    case cancel
}

enum PrismRecoveryMessageState: Equatable, Sendable {
    case idle
    case presented(PrismRecoveryMessage)
    case completed(PrismRecoveryDecision)
}

@MainActor
final class PrismRecoveryMessageModel: ObservableObject {
    @Published private(set) var state: PrismRecoveryMessageState = .idle
    private let onDecision: ((PrismRecoveryDecision) -> Void)?
    private let clipboardWriter: (String) -> Bool

    init(
        clipboardWriter: @escaping (String) -> Bool = { text in
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
        },
        onDecision: ((PrismRecoveryDecision) -> Void)? = nil
    ) {
        self.clipboardWriter = clipboardWriter
        self.onDecision = onDecision
    }

    var message: PrismRecoveryMessage? {
        guard case .presented(let message) = state else { return nil }
        return message
    }

    func present(_ message: PrismRecoveryMessage) {
        state = .presented(message)
    }

    @discardableResult
    func choose(_ decision: PrismRecoveryDecision) -> Bool {
        guard let message else { return false }
        guard decision != .retry || message.retryAvailable else { return false }
        guard decision != .edit || message.editAvailable else { return false }
        state = .completed(decision)
        onDecision?(decision)
        return true
    }

    @discardableResult
    func copyDetails() -> Bool {
        guard let message, !message.details.isEmpty else { return false }
        let text = message.details
            .map { "\($0.label): \($0.value)" }
            .joined(separator: "\n")
        return clipboardWriter(text)
    }

    func reset() {
        state = .idle
    }
}

enum PrismShortcutLaunchTarget: String, CaseIterable, Identifiable, Sendable {
    case instance
    case world
    case server

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .instance: return "Instance"
        case .world: return "World"
        case .server: return "Server"
        }
    }
}

enum PrismShortcutDestination: String, CaseIterable, Identifiable, Sendable {
    case desktop
    case applications
    case other

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .desktop: return "Desktop"
        case .applications: return "Applications"
        case .other: return "Other…"
        }
    }
}

struct PrismShortcutWorld: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
}

struct PrismShortcutProfile: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
}

struct PrismShortcutCreationDraft: Equatable, Sendable {
    var instanceIdentifier: String
    var instanceName: String
    var name: String
    var launchTarget: PrismShortcutLaunchTarget
    var worldID: String?
    var serverAddress: String
    var overrideAccount: Bool
    var profileID: String?
    var destination: PrismShortcutDestination
    var destinationURL: URL?
    var iconKey: String

    var effectiveName: String {
        let candidate = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? instanceName.trimmingCharacters(in: .whitespacesAndNewlines) : candidate
    }
}

struct PrismShortcutCreationRequest: Equatable, Sendable {
    let instanceIdentifier: String
    let name: String
    let launchTarget: PrismShortcutLaunchTarget
    let worldID: String?
    let serverAddress: String?
    let profileID: String?
    let destination: PrismShortcutDestination
    let destinationURL: URL?
    let iconKey: String
}

enum PrismShortcutCreationOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
}

struct PrismShortcutCreationResult: Equatable, Sendable {
    let instanceIdentifier: String
    let outcome: PrismShortcutCreationOutcome
    let localizationKey: String
    let diagnosticText: String?
    let retryable: Bool

    static func succeeded(for instanceIdentifier: String) -> Self {
        Self(instanceIdentifier: instanceIdentifier, outcome: .succeeded, localizationKey: "shortcuts.created", diagnosticText: nil, retryable: false)
    }
}

struct PrismShortcutCreationFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let retryable: Bool
}

enum PrismShortcutCreationState: Equatable, Sendable {
    case editing
    case creating
    case succeeded
    case failed(PrismShortcutCreationFailure)
    case cancelled
}

@MainActor
final class PrismShortcutCreationModel: ObservableObject {
    @Published var draft: PrismShortcutCreationDraft
    @Published private(set) var state: PrismShortcutCreationState = .editing
    @Published private(set) var worlds: [PrismShortcutWorld]
    @Published private(set) var profiles: [PrismShortcutProfile]
    let iconKeys: [String]

    private var generation = 0
    private var savePanelGeneration = 0
    private let onCreate: ((PrismShortcutCreationRequest, Int) -> Void)?
    private let onCancel: (() -> Void)?
    private let bridge: PRPrismBridge?
    private var createToken: PRBridgeObservationToken?
    private var contextTokens: [PRBridgeObservationToken] = []
    private var contextGeneration = 0

    init(
        instanceIdentifier: String,
        instanceName: String,
        worlds: [PrismShortcutWorld] = [],
        profiles: [PrismShortcutProfile] = [],
        iconKeys: [String] = ["default", "grass", "stone"],
        bridge: PRPrismBridge? = nil,
        onCreate: ((PrismShortcutCreationRequest, Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        let normalizedWorlds = Self.unique(worlds)
        let normalizedProfiles = Self.unique(profiles)
        let normalizedIconKeys = Self.unique(iconKeys)
        self.worlds = normalizedWorlds
        self.profiles = normalizedProfiles
        self.iconKeys = normalizedIconKeys
        self.bridge = bridge
        self.onCreate = onCreate
        self.onCancel = onCancel
        self.draft = PrismShortcutCreationDraft(
            instanceIdentifier: instanceIdentifier,
            instanceName: instanceName,
            name: "",
            launchTarget: .instance,
            worldID: nil,
            serverAddress: "",
            overrideAccount: false,
            profileID: normalizedProfiles.first?.id,
            destination: .desktop,
            destinationURL: nil,
            iconKey: normalizedIconKeys.first ?? "default"
        )
    }

    var isCreating: Bool { state == .creating }

    var validationMessage: String? {
        guard !draft.instanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Choose an instance before creating a shortcut."
        }
        guard !draft.effectiveName.isEmpty else {
            return "Enter a shortcut name."
        }
        switch draft.launchTarget {
        case .instance:
            break
        case .world:
            guard let worldID = draft.worldID, worlds.contains(where: { $0.id == worldID }) else {
                return "Choose a world for this shortcut."
            }
        case .server:
            guard !draft.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Enter a server address for this shortcut."
            }
        }
        if draft.overrideAccount {
            guard let profileID = draft.profileID, profiles.contains(where: { $0.id == profileID }) else {
                return "Choose an account profile for this shortcut."
            }
        }
        if draft.destination == .other {
            guard let destinationURL = draft.destinationURL,
                  destinationURL.isFileURL,
                  !destinationURL.path.isEmpty,
                  destinationURL.path.hasPrefix("/") else {
                return "Choose a destination for this shortcut."
            }
        }
        return nil
    }

    var canCreate: Bool { state == .editing && validationMessage == nil }

    func setInstanceContext(identifier: String, name: String) {
        guard state == .editing else { return }
        draft.instanceIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.instanceName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.name = ""
        draft.launchTarget = .instance
        draft.worldID = nil
        draft.serverAddress = ""
        draft.overrideAccount = false
        draft.destination = .desktop
        draft.destinationURL = nil
        savePanelGeneration += 1
        contextGeneration += 1
        let activeContextGeneration = contextGeneration
        contextTokens.forEach { $0.cancel() }
        contextTokens.removeAll()
        guard let bridge, !draft.instanceIdentifier.isEmpty else { return }
        worlds = []
        profiles = []
        let detailsToken = bridge.loadInstanceDetails(withIdentifier: draft.instanceIdentifier) { [weak self] details, _ in
            guard let self, activeContextGeneration == self.contextGeneration,
                  let details, details.identifier == self.draft.instanceIdentifier else { return }
            self.draft.instanceName = details.name
        }
        if let detailsToken {
            contextTokens.append(detailsToken)
        }
        let worldsToken = bridge.loadInstanceWorlds(withIdentifier: draft.instanceIdentifier) { [weak self] values, _ in
            guard let self, activeContextGeneration == self.contextGeneration, let values else { return }
            self.worlds = Self.unique(values.filter(\.canBeJoined).map {
                PrismShortcutWorld(id: $0.name, displayName: $0.name)
            })
        }
        if let worldsToken {
            contextTokens.append(worldsToken)
        }
        let profilesToken = bridge.loadAccountSnapshots { [weak self] result, _ in
            guard let self, activeContextGeneration == self.contextGeneration,
                  result?.outcome == .succeeded else { return }
            self.profiles = Self.unique(result?.accounts.compactMap { account in
                let name = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : PrismShortcutProfile(id: account.identifier, displayName: name)
            } ?? [])
            if self.draft.overrideAccount,
               !self.profiles.contains(where: { $0.id == self.draft.profileID }) {
                self.draft.profileID = self.profiles.first?.id
            }
        }
        if let profilesToken {
            contextTokens.append(profilesToken)
        }
    }

    func setLaunchTarget(_ target: PrismShortcutLaunchTarget) {
        guard state == .editing else { return }
        draft.launchTarget = target
        if target != .world { draft.worldID = nil }
        if target != .server { draft.serverAddress = "" }
    }

    func setWorldID(_ identifier: String?) {
        guard state == .editing,
              let identifier,
              worlds.contains(where: { $0.id == identifier }) else { return }
        draft.worldID = identifier
    }

    func setProfileID(_ identifier: String?) {
        guard state == .editing,
              let identifier,
              profiles.contains(where: { $0.id == identifier }) else { return }
        draft.profileID = identifier
    }

    func setDestination(_ destination: PrismShortcutDestination) {
        guard state == .editing else { return }
        savePanelGeneration += 1
        draft.destination = destination
        if destination != .other { draft.destinationURL = nil }
    }

    func beginOtherDestinationPanel() -> Int? {
        guard state == .editing, draft.destination == .other else { return nil }
        savePanelGeneration += 1
        return savePanelGeneration
    }

    @discardableResult
    func applyOtherDestinationPanelResult(_ url: URL?, token: Int) -> Bool {
        guard state == .editing, draft.destination == .other, token == savePanelGeneration else { return false }
        savePanelGeneration += 1
        guard let url else { return true }
        guard url.isFileURL, !url.path.isEmpty, url.path.hasPrefix("/") else { return false }
        draft.destinationURL = url.standardizedFileURL
        return true
    }

    func makeRequest() -> PrismShortcutCreationRequest? {
        guard canCreate else { return nil }
        let normalizedTarget = draft.launchTarget
        return PrismShortcutCreationRequest(
            instanceIdentifier: draft.instanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            name: draft.effectiveName,
            launchTarget: normalizedTarget,
            worldID: normalizedTarget == .world ? draft.worldID : nil,
            serverAddress: normalizedTarget == .server
                ? draft.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            profileID: draft.overrideAccount ? draft.profileID : nil,
            destination: draft.destination,
            destinationURL: draft.destination == .other ? draft.destinationURL?.standardizedFileURL : nil,
            iconKey: iconKeys.contains(draft.iconKey) ? draft.iconKey : (iconKeys.first ?? "default")
        )
    }

    @discardableResult
    func startCreate() -> Bool {
        guard let request = makeRequest(), !isCreating else { return false }
        generation += 1
        let activeGeneration = generation
        savePanelGeneration += 1
        state = .creating
        createToken?.cancel()
        if let bridge,
           let bridgeRequest = bridgeRequest(from: request) {
            createToken = bridge.createShortcut(with: bridgeRequest) { [weak self] result, error in
                self?.createToken = nil
                guard let self else { return }
                if let result {
                    _ = self.apply(bridgeResult: result, generation: activeGeneration)
                } else if let error {
                    _ = self.apply(
                        result: PrismShortcutCreationResult(
                            instanceIdentifier: request.instanceIdentifier,
                            outcome: .failed,
                            localizationKey: error.localizationKey,
                            diagnosticText: error.diagnosticText,
                            retryable: error.recoveryKind == .retry
                        ),
                        generation: activeGeneration
                    )
                }
            }
        } else if let onCreate {
            onCreate(request, generation)
        } else {
            state = .failed(PrismShortcutCreationFailure(
                localizationKey: "shortcuts.adapterUnavailable",
                diagnosticText: nil,
                retryable: false
            ))
            return false
        }
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard isCreating else { return false }
        generation += 1
        savePanelGeneration += 1
        createToken?.cancel()
        createToken = nil
        onCancel?()
        state = .cancelled
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard case .failed(let failure) = state, failure.retryable else { return false }
        state = .editing
        return startCreate()
    }

    @discardableResult
    func apply(result: PrismShortcutCreationResult, generation resultGeneration: Int? = nil) -> Bool {
        guard state == .creating,
              (resultGeneration ?? generation) == generation,
              result.instanceIdentifier == draft.instanceIdentifier else { return false }
        let key = result.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        switch result.outcome {
        case .succeeded:
            state = .succeeded
        case .failed:
            state = .failed(PrismShortcutCreationFailure(
                localizationKey: key,
                diagnosticText: result.diagnosticText,
                retryable: result.retryable
            ))
        case .cancelled:
            state = .cancelled
        }
        return true
    }

    func reset() {
        generation += 1
        savePanelGeneration += 1
        state = .editing
    }

    private func bridgeRequest(from request: PrismShortcutCreationRequest) -> PRShortcutCreationRequest? {
        let target: PRShortcutLaunchTarget
        switch request.launchTarget {
        case .instance: target = .instance
        case .world: target = .world
        case .server: target = .server
        }
        let destination: PRShortcutDestination
        switch request.destination {
        case .desktop: destination = .desktop
        case .applications: destination = .applications
        case .other: destination = .other
        }
        let profileName = request.profileID.flatMap { identifier in
            profiles.first { $0.id == identifier }?.displayName
        }
        return PRShortcutCreationRequest(
            instanceIdentifier: request.instanceIdentifier,
            name: request.name,
            launchTarget: target,
            worldIdentifier: request.worldID,
            serverAddress: request.serverAddress,
            profileName: profileName,
            destination: destination,
            destinationURL: request.destinationURL,
            iconKey: request.iconKey
        )
    }

    private func apply(bridgeResult: PRShortcutCreationResult, generation: Int) -> Bool {
        let outcome: PrismShortcutCreationOutcome
        switch bridgeResult.outcome {
        case .succeeded: outcome = .succeeded
        case .cancelled: outcome = .cancelled
        case .unknownInstance, .failed, .rejected: outcome = .failed
        @unknown default: outcome = .failed
        }
        return apply(
            result: PrismShortcutCreationResult(
                instanceIdentifier: bridgeResult.instanceIdentifier,
                outcome: outcome,
                localizationKey: bridgeResult.localizationKey,
                diagnosticText: bridgeResult.diagnosticText,
                retryable: bridgeResult.retryable
            ),
            generation: generation
        )
    }

    private static func unique(_ worlds: [PrismShortcutWorld]) -> [PrismShortcutWorld] {
        var seen = Set<String>()
        return worlds.filter { seen.insert($0.id).inserted && !$0.id.isEmpty }
    }

    private static func unique(_ profiles: [PrismShortcutProfile]) -> [PrismShortcutProfile] {
        var seen = Set<String>()
        return profiles.filter { seen.insert($0.id).inserted && !$0.id.isEmpty }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted && !$0.isEmpty }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

@MainActor
struct PrismAboutView: View {
    let metadata: PrismAboutMetadata

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 42))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.productName)
                        .font(.title)
                    Text(metadata.version)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("prism.about.identity")

            TabView {
                aboutTab
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .accessibilityIdentifier("prism.about.tab.about")
                scrollTab(title: "Credits", text: metadata.creditsText, identifier: "prism.about.credits")
                    .tabItem { Label("Credits", systemImage: "person.2") }
                    .accessibilityIdentifier("prism.about.tab.credits")
                scrollTab(title: "License", text: metadata.licenseText, identifier: "prism.about.license")
                    .tabItem { Label("License", systemImage: "doc.text") }
                    .accessibilityIdentifier("prism.about.tab.license")
            }
            .frame(minHeight: 250)
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 420)
        .accessibilityIdentifier("prism.about.surface")
    }

    private var aboutTab: some View {
        Form {
            Section("About Prism") {
                Text(metadata.aboutText)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("prism.about.description")
                if let repositoryURL = metadata.repositoryURL {
                    Link(destination: repositoryURL) {
                        Label("Project Repository", systemImage: "link")
                    }
                    .accessibilityIdentifier("prism.about.repository")
                }
            }
            Section("Build") {
                LabeledContent("Version", value: metadata.version)
                if let buildPlatform = metadata.buildPlatform {
                    LabeledContent("Platform", value: buildPlatform)
                }
                if let commit = metadata.commit {
                    LabeledContent("Commit", value: commit)
                }
                if let buildDate = metadata.buildDate {
                    LabeledContent("Build Date", value: buildDate)
                }
                if let channel = metadata.channel {
                    LabeledContent("Channel", value: channel)
                }
            }
            Section {
                Text(metadata.copyright)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("prism.about.copyright")
            }
        }
        .formStyle(.grouped)
    }

    private func scrollTab(title: String, text: String, identifier: String) -> some View {
        ScrollView {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityIdentifier(identifier)
    }
}

@MainActor
struct PrismNewsView: View {
    @ObservedObject var model: PrismNewsModel

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                VStack(spacing: 10) {
                    ProgressView("Loading News")
                    Button("Cancel", role: .cancel) { _ = model.cancel() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("prism.news.cancel")
                }
            case .failed(let failure):
                ContentUnavailableView {
                    Label("News Unavailable", systemImage: "newspaper")
                } description: {
                    VStack(spacing: 6) {
                        Text(LocalizedStringKey(failure.localizationKey))
                        if let diagnosticText = failure.diagnosticText, !diagnosticText.isEmpty {
                            Text(diagnosticText)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                } actions: {
                    if failure.isRetryAvailable {
                        Button("Retry") { _ = model.retry() }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("prism.news.retry")
                    }
                }
            case .cancelled:
                ContentUnavailableView("News Loading Cancelled", systemImage: "pause.circle", description: Text("News was not loaded."))
                    .overlay(alignment: .bottom) {
                        Button("Try Again") { _ = model.load() }
                            .keyboardShortcut(.defaultAction)
                            .padding(.bottom, 12)
                            .accessibilityIdentifier("prism.news.try-again")
                    }
            case .empty:
                ContentUnavailableView("No News", systemImage: "newspaper", description: Text("There are no news articles to display."))
                    .overlay(alignment: .bottom) {
                        Button("Refresh") { _ = model.load() }
                            .keyboardShortcut(.defaultAction)
                            .padding(.bottom, 12)
                            .accessibilityIdentifier("prism.news.refresh")
                    }
            case .content:
                contentView
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .accessibilityIdentifier("prism.news.surface")
    }

    private var contentView: some View {
        NavigationSplitView {
            if model.isArticleListVisible {
                List(
                    model.entries,
                    selection: Binding<String?>(
                        get: { model.selectedEntryID },
                        set: { _ = model.selectEntry($0) }
                    )
                ) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                        if let publishedDate = entry.publishedDate {
                            Text(publishedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(Optional(entry.id))
                    .accessibilityIdentifier("prism.news.article.\(entry.id)")
                }
                .listStyle(.sidebar)
                .navigationTitle("News")
                .navigationSplitViewColumnWidth(min: 190, ideal: 230)
            } else {
                ContentUnavailableView("Article List Hidden", systemImage: "sidebar.left", description: Text("Show the article list to choose another article."))
            }
        } detail: {
            if let entry = model.selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(entry.title)
                            .font(.title2)
                            .accessibilityAddTraits(.isHeader)
                        if let publishedDate = entry.publishedDate {
                            Text(publishedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Link(destination: entry.link) {
                            Label("Open Article", systemImage: "safari")
                        }
                        .accessibilityIdentifier("prism.news.article-link.\(entry.id)")
                        Divider()
                        Text(entry.content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(20)
                }
                .accessibilityIdentifier("prism.news.article-content.\(entry.id)")
            } else {
                ContentUnavailableView("Select an Article", systemImage: "newspaper", description: Text("Choose an article from the list."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    model.toggleArticleList()
                } label: {
                    Label(
                        model.isArticleListVisible ? "Hide Article List" : "Show Article List",
                        systemImage: model.isArticleListVisible ? "sidebar.left" : "sidebar.right"
                    )
                }
                .accessibilityIdentifier("prism.news.toggle-list")
                .help(Text("Show or hide the article list."))
            }
            ToolbarItem(placement: .automatic) {
                Button("Refresh") { _ = model.load() }
                    .accessibilityIdentifier("prism.news.refresh-toolbar")
            }
        }
    }
}

@MainActor
struct PrismUpdateView: View {
    @ObservedObject var model: PrismUpdateModel

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                ContentUnavailableView("Check for Updates", systemImage: "arrow.triangle.2.circlepath", description: Text("Check whether a newer Prism version is available."))
                    .overlay(alignment: .bottom) {
                        Button("Check for Updates") { _ = model.check() }
                            .keyboardShortcut(.defaultAction)
                            .padding(.bottom, 20)
                            .accessibilityIdentifier("prism.update.check")
                    }
            case .checking:
                VStack(spacing: 10) {
                    ProgressView("Checking for Updates")
                    Button("Cancel", role: .cancel) { _ = model.cancel() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("prism.update.cancel")
                }
            case .noUpdate:
                ContentUnavailableView("Prism Is Up to Date", systemImage: "checkmark.circle", description: Text("No newer version is available."))
                    .overlay(alignment: .bottom) {
                        Button("Check Again") { _ = model.check() }
                            .keyboardShortcut(.defaultAction)
                            .padding(.bottom, 20)
                            .accessibilityIdentifier("prism.update.check-again")
                    }
            case .available(let notice):
                availableView(notice)
            case .failed(let failure):
                ContentUnavailableView {
                    Label("Update Check Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    VStack(spacing: 6) {
                        Text(LocalizedStringKey(failure.localizationKey))
                        if let diagnosticText = failure.diagnosticText, !diagnosticText.isEmpty {
                            Text(diagnosticText)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                } actions: {
                    if failure.retryable {
                        Button("Retry") { _ = model.check() }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("prism.update.retry")
                    }
                }
            case .cancelled:
                ContentUnavailableView("Update Check Cancelled", systemImage: "xmark.circle", description: Text("No update action was performed."))
                    .overlay(alignment: .bottom) {
                        Button("Check Again") { _ = model.check() }
                            .keyboardShortcut(.defaultAction)
                            .padding(.bottom, 20)
                            .accessibilityIdentifier("prism.update.check-after-cancel")
                    }
            case .decided(let decision):
                ContentUnavailableView(
                    decision.titleKey,
                    systemImage: decision.systemImage,
                    description: Text(decision.messageKey)
                )
                .accessibilityIdentifier("prism.update.decided")
            }
        }
        .frame(minWidth: 560, minHeight: 380)
        .accessibilityIdentifier("prism.update.surface")
    }

    private func availableView(_ notice: PrismUpdateNotice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("A New Version Is Available", systemImage: "arrow.down.circle")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            Text("Version \(notice.availableVersion) is available. You have \(notice.currentVersion).")
            Text("Release Notes")
                .font(.headline)
            ScrollView {
                Text(notice.releaseNotes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
            HStack {
                Button("Skip This Version", role: .cancel) { _ = model.choose(.skipVersion) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("prism.update.skip")
                Spacer()
                Button("Remind Me Later") { _ = model.choose(.remindLater) }
                    .accessibilityIdentifier("prism.update.remind-later")
                Button("Install Update") { _ = model.choose(.install) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("prism.update.install")
            }
        }
        .padding(20)
    }
}

private extension PrismUpdateDecision {
    var titleKey: LocalizedStringKey {
        switch self {
        case .install: return "Update Requested"
        case .remindLater: return "Update Deferred"
        case .skipVersion: return "Version Skipped"
        }
    }

    var messageKey: LocalizedStringKey {
        switch self {
        case .install: return "The update request was sent to the updater."
        case .remindLater: return "Prism will remind you about this update later."
        case .skipVersion: return "Prism will not offer this version again."
        }
    }

    var systemImage: String {
        switch self {
        case .install: return "arrow.down.circle"
        case .remindLater: return "clock"
        case .skipVersion: return "nosign"
        }
    }
}

@MainActor
struct PrismProviderChoiceView: View {
    @ObservedObject var model: PrismProviderChoiceModel

    var body: some View {
        Group {
            switch model.state {
            case .editing:
                Form {
                    Section("Provider Choice") {
                        Text(model.descriptionText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("prism.provider-choice.description")
                        Picker("Provider", selection: Binding(
                            get: { model.selectedProvider },
                            set: { model.setProvider($0) }
                        )) {
                            ForEach(model.providers) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .accessibilityIdentifier("prism.provider-choice.provider")
                        Toggle("Try other providers if this one fails", isOn: $model.tryOthers)
                            .accessibilityIdentifier("prism.provider-choice.try-others")
                    }
                    Section {
                        HStack {
                            if model.allowSkipping {
                                Button("Skip This Mod", role: .cancel) { _ = model.choose(.skipOne) }
                                    .keyboardShortcut(.cancelAction)
                                    .accessibilityIdentifier("prism.provider-choice.skip-one")
                                if !model.singleChoice {
                                    Button("Skip All", role: .cancel) { _ = model.choose(.skipAll) }
                                        .accessibilityIdentifier("prism.provider-choice.skip-all")
                                }
                            }
                            Spacer()
                            if !model.singleChoice {
                                Button("Confirm for All") { _ = model.choose(.confirmAll) }
                                    .accessibilityIdentifier("prism.provider-choice.confirm-all")
                            }
                            Button(model.singleChoice ? "Confirm" : "Confirm") { _ = model.choose(.confirmOne) }
                                .keyboardShortcut(.defaultAction)
                                .disabled(!model.canConfirm)
                                .accessibilityIdentifier("prism.provider-choice.confirm-one")
                        }
                    }
                }
                .formStyle(.grouped)
            case .completed(let response):
                ContentUnavailableView {
                    Label(response.action.titleKey, systemImage: response.action.systemImage)
                } description: {
                    Text(response.provider?.displayName ?? "No provider was selected.")
                } actions: {
                    Button("Choose Again") { model.reset() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("prism.provider-choice.reset")
                }
            }
        }
        .frame(minWidth: 520, minHeight: 300)
        .accessibilityIdentifier("prism.provider-choice.surface")
    }
}

private extension PrismProviderChoiceAction {
    var titleKey: LocalizedStringKey {
        switch self {
        case .confirmOne: return "Provider Confirmed"
        case .confirmAll: return "Provider Confirmed for All"
        case .skipOne: return "Mod Skipped"
        case .skipAll: return "All Mods Skipped"
        }
    }

    var systemImage: String {
        switch self {
        case .confirmOne, .confirmAll: return "checkmark.circle"
        case .skipOne, .skipAll: return "forward.end"
        }
    }
}

@MainActor
struct PrismRecoveryMessageView: View {
    @ObservedObject var model: PrismRecoveryMessageModel

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                ContentUnavailableView("No Recovery Message", systemImage: "checkmark.circle", description: Text("There are no recovery actions to show."))
            case .completed(let decision):
                ContentUnavailableView {
                    Label(decision.titleKey, systemImage: decision.systemImage)
                } description: {
                    Text(decision.messageKey)
                } actions: {
                    Button("Done") { model.reset() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("prism.recovery.done")
                }
            case .presented(let message):
                presentedView(message)
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .accessibilityIdentifier("prism.recovery.surface")
    }

    private func presentedView(_ message: PrismRecoveryMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(LocalizedStringKey(message.titleKey), systemImage: "exclamationmark.triangle")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            Text(LocalizedStringKey(message.messageKey))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let diagnosticText = message.diagnosticText, !diagnosticText.isEmpty {
                Text(diagnosticText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("prism.recovery.diagnostic")
            }
            if !message.details.isEmpty {
                List(message.details) { detail in
                    LabeledContent(detail.label, value: detail.value)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("prism.recovery.detail.\(detail.id)")
                }
                .listStyle(.inset)
                HStack {
                    Spacer()
                    Button("Copy Details") { _ = model.copyDetails() }
                        .accessibilityIdentifier("prism.recovery.copy-details")
                }
            }
            if message.partialChangesRolledBack {
                Label("Partial changes were rolled back.", systemImage: "arrow.uturn.backward.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("prism.recovery.rollback")
            }
            HStack {
                Button("Cancel", role: .cancel) { _ = model.choose(.cancel) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("prism.recovery.cancel")
                Spacer()
                if message.editAvailable {
                    Button("Edit") { _ = model.choose(.edit) }
                        .accessibilityIdentifier("prism.recovery.edit")
                }
                if message.retryAvailable {
                    Button("Retry") { _ = model.choose(.retry) }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("prism.recovery.retry")
                }
            }
        }
        .padding(20)
    }
}

private extension PrismRecoveryDecision {
    var titleKey: LocalizedStringKey {
        switch self {
        case .retry: return "Retry Requested"
        case .edit: return "Edit Requested"
        case .cancel: return "Operation Cancelled"
        }
    }

    var messageKey: LocalizedStringKey {
        switch self {
        case .retry: return "The operation will be tried again."
        case .edit: return "Return to the editing form to change the request."
        case .cancel: return "No further recovery action was requested."
        }
    }

    var systemImage: String {
        switch self {
        case .retry: return "arrow.clockwise"
        case .edit: return "pencil"
        case .cancel: return "xmark.circle"
        }
    }
}

@MainActor
struct PrismShortcutCreationView: View {
    @ObservedObject var model: PrismShortcutCreationModel

    var body: some View {
        Group {
            switch model.state {
            case .editing:
                editingForm
            case .creating:
                VStack(spacing: 10) {
                    ProgressView("Creating Shortcut")
                    Button("Cancel", role: .cancel) { _ = model.cancel() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("prism.shortcut.cancel")
                }
            case .succeeded:
                ContentUnavailableView("Shortcut Created", systemImage: "checkmark.circle", description: Text("The shortcut was created successfully."))
                    .overlay(alignment: .bottom) {
                        Button("Create Another") { model.reset() }
                            .keyboardShortcut(.defaultAction)
                            .padding(.bottom, 20)
                            .accessibilityIdentifier("prism.shortcut.create-another")
                    }
            case .cancelled:
                ContentUnavailableView("Shortcut Creation Cancelled", systemImage: "pause.circle", description: Text("No shortcut was created."))
                    .overlay(alignment: .bottom) {
                        Button("Start Again") { model.reset() }
                            .keyboardShortcut(.defaultAction)
                            .padding(.bottom, 20)
                            .accessibilityIdentifier("prism.shortcut.start-again")
                    }
            case .failed(let failure):
                ContentUnavailableView {
                    Label("Unable to Create Shortcut", systemImage: "exclamationmark.triangle")
                } description: {
                    VStack(spacing: 6) {
                        Text(LocalizedStringKey(failure.localizationKey))
                        if let diagnosticText = failure.diagnosticText, !diagnosticText.isEmpty {
                            Text(diagnosticText)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                } actions: {
                    if failure.retryable {
                        Button("Retry") { _ = model.retry() }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("prism.shortcut.retry")
                    }
                    Button("Edit") { model.reset() }
                        .accessibilityIdentifier("prism.shortcut.edit")
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .accessibilityIdentifier("prism.shortcut.surface")
    }

    private var editingForm: some View {
        Form {
            Section("Shortcut") {
                TextField("Name", text: $model.draft.name)
                    .accessibilityIdentifier("prism.shortcut.name")
                Picker("Launch", selection: Binding(
                    get: { model.draft.launchTarget },
                    set: { model.setLaunchTarget($0) }
                )) {
                    ForEach(PrismShortcutLaunchTarget.allCases) { target in
                        Text(LocalizedStringKey(target.titleKey)).tag(target)
                    }
                }
                .accessibilityIdentifier("prism.shortcut.target")
                if model.draft.launchTarget == .world {
                    Picker("World", selection: Binding(
                        get: { model.draft.worldID ?? "" },
                        set: { model.setWorldID($0) }
                    )) {
                        Text("Choose a World").tag("")
                        ForEach(model.worlds) { world in
                            Text(world.displayName).tag(world.id)
                        }
                    }
                    .accessibilityIdentifier("prism.shortcut.world")
                }
                if model.draft.launchTarget == .server {
                    TextField("Server Address", text: $model.draft.serverAddress)
                        .accessibilityIdentifier("prism.shortcut.server")
                }
            }
            Section("Account") {
                Toggle("Use a specific account", isOn: $model.draft.overrideAccount)
                    .accessibilityIdentifier("prism.shortcut.override-account")
                if model.draft.overrideAccount {
                    Picker("Account", selection: Binding(
                        get: { model.draft.profileID ?? "" },
                        set: { model.setProfileID($0) }
                    )) {
                        Text("Choose an Account").tag("")
                        ForEach(model.profiles) { profile in
                            Text(profile.displayName).tag(profile.id)
                        }
                    }
                    .accessibilityIdentifier("prism.shortcut.account")
                }
            }
            Section("Destination") {
                Picker("Save In", selection: Binding(
                    get: { model.draft.destination },
                    set: { model.setDestination($0) }
                )) {
                    ForEach(PrismShortcutDestination.allCases) { destination in
                        Text(LocalizedStringKey(destination.titleKey)).tag(destination)
                    }
                }
                .accessibilityIdentifier("prism.shortcut.destination")
                if model.draft.destination == .other {
                    Button("Choose Destination…") {
                        guard let token = model.beginOtherDestinationPanel() else { return }
                        PrismSystemSavePanel.present(
                            defaultFilename: model.draft.effectiveName,
                            allowedContentTypes: [.item]
                        ) { url in
                            _ = model.applyOtherDestinationPanelResult(url, token: token)
                        }
                    }
                    .accessibilityIdentifier("prism.shortcut.choose-destination")
                    if let destinationURL = model.draft.destinationURL {
                        Text(destinationURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("prism.shortcut.selected-destination")
                    }
                }
            }
            Section("Appearance") {
                Picker("Icon", selection: $model.draft.iconKey) {
                    ForEach(model.iconKeys, id: \.self) { iconKey in
                        Text(iconKey.capitalized).tag(iconKey)
                    }
                }
                .accessibilityIdentifier("prism.shortcut.icon")
            }
            if let validationMessage = model.validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("prism.shortcut.validation")
            }
            HStack {
                Spacer()
                Button("Create Shortcut") { _ = model.startCreate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreate)
                    .accessibilityIdentifier("prism.shortcut.create")
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
struct PrismNewsWindow: View {
    @ObservedObject var model: PrismNewsModel

    var body: some View {
        PrismNewsView(model: model)
            .task {
                if case .empty = model.state {
                    _ = model.load()
                }
            }
    }
}

@MainActor
struct PrismUpdateWindow: View {
    @ObservedObject var model: PrismUpdateModel

    var body: some View {
        PrismUpdateView(model: model)
    }
}
