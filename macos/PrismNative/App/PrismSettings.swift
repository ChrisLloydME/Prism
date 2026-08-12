import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PrismGlobalSettings: Equatable, Sendable {
    var instanceDirectoryURL: URL
    var iconTheme: String
    var applicationTheme: String
    var backgroundCat: String
    var catOpacity: Int
    var catFit: String
    var language: String
    var useSystemLocale: Bool
    var menuBarInsteadOfToolBar: Bool
    var statusBarVisible: Bool
    var toolbarsLocked: Bool
    var numberOfConcurrentTasks: Int
    var numberOfConcurrentDownloads: Int
    var numberOfManualRetries: Int
    var requestTimeoutSeconds: Int
    var consoleFont: String
    var consoleFontSize: Int
    var consoleMaxLines: Int
    var consoleOverflowStop: Bool
    var showConsole: Bool
    var autoCloseConsole: Bool
    var showConsoleOnError: Bool
    var logPrePostOutput: Bool
    var pasteType: Int
    var pasteCustomAPIBase: String
    var metadataURLOverride: String
    var refreshMetadataOnLaunch: Bool
    var assetsURLOverride: String
    var legacyFMLLibrariesURLOverride: String
    var fallbackForBlockedModrinthProjects: Bool
    var userAgentOverride: String
    var microsoftClientIDOverride: String
    var curseForgeAPIKey: String
    var modrinthToken: String
    var technicClientID: String
    var proxyType: String
    var proxyAddress: String
    var proxyPort: Int
    var proxyUsername: String
    var proxyPassword: String

    init?(bridgeSettings: PRGlobalSettings) {
        self.init(
            instanceDirectoryURL: bridgeSettings.instanceDirectoryURL,
            iconTheme: bridgeSettings.iconTheme,
            applicationTheme: bridgeSettings.applicationTheme,
            backgroundCat: bridgeSettings.backgroundCat,
            catOpacity: bridgeSettings.catOpacity,
            catFit: bridgeSettings.catFit,
            language: bridgeSettings.language,
            useSystemLocale: bridgeSettings.useSystemLocale,
            menuBarInsteadOfToolBar: bridgeSettings.menuBarInsteadOfToolBar,
            statusBarVisible: bridgeSettings.statusBarVisible,
            toolbarsLocked: bridgeSettings.toolbarsLocked,
            numberOfConcurrentTasks: bridgeSettings.numberOfConcurrentTasks,
            numberOfConcurrentDownloads: bridgeSettings.numberOfConcurrentDownloads,
            numberOfManualRetries: bridgeSettings.numberOfManualRetries,
            requestTimeoutSeconds: bridgeSettings.requestTimeoutSeconds,
            consoleFont: bridgeSettings.consoleFont,
            consoleFontSize: bridgeSettings.consoleFontSize,
            consoleMaxLines: bridgeSettings.consoleMaxLines,
            consoleOverflowStop: bridgeSettings.consoleOverflowStop,
            showConsole: bridgeSettings.showConsole,
            autoCloseConsole: bridgeSettings.autoCloseConsole,
            showConsoleOnError: bridgeSettings.showConsoleOnError,
            logPrePostOutput: bridgeSettings.logPrePostOutput,
            pasteType: bridgeSettings.pasteType,
            pasteCustomAPIBase: bridgeSettings.pasteCustomAPIBase,
            metadataURLOverride: bridgeSettings.metadataURLOverride,
            refreshMetadataOnLaunch: bridgeSettings.refreshMetadataOnLaunch,
            assetsURLOverride: bridgeSettings.assetsURLOverride,
            legacyFMLLibrariesURLOverride: bridgeSettings.legacyFMLLibrariesURLOverride,
            fallbackForBlockedModrinthProjects: bridgeSettings.fallbackForBlockedModrinthProjects,
            userAgentOverride: bridgeSettings.userAgentOverride,
            microsoftClientIDOverride: bridgeSettings.microsoftClientIDOverride,
            curseForgeAPIKey: bridgeSettings.curseForgeAPIKey,
            modrinthToken: bridgeSettings.modrinthToken,
            technicClientID: bridgeSettings.technicClientID,
            proxyType: bridgeSettings.proxyType,
            proxyAddress: bridgeSettings.proxyAddress,
            proxyPort: bridgeSettings.proxyPort,
            proxyUsername: bridgeSettings.proxyUsername,
            proxyPassword: bridgeSettings.proxyPassword
        )
    }

    init?(
        instanceDirectoryURL: URL,
        iconTheme: String,
        applicationTheme: String,
        backgroundCat: String,
        catOpacity: Int,
        catFit: String,
        language: String,
        useSystemLocale: Bool,
        menuBarInsteadOfToolBar: Bool,
        statusBarVisible: Bool,
        toolbarsLocked: Bool,
        numberOfConcurrentTasks: Int,
        numberOfConcurrentDownloads: Int,
        numberOfManualRetries: Int,
        requestTimeoutSeconds: Int,
        consoleFont: String,
        consoleFontSize: Int,
        consoleMaxLines: Int,
        consoleOverflowStop: Bool,
        showConsole: Bool,
        autoCloseConsole: Bool,
        showConsoleOnError: Bool,
        logPrePostOutput: Bool,
        pasteType: Int = 3,
        pasteCustomAPIBase: String = "",
        metadataURLOverride: String = "",
        refreshMetadataOnLaunch: Bool = true,
        assetsURLOverride: String = "",
        legacyFMLLibrariesURLOverride: String = "",
        fallbackForBlockedModrinthProjects: Bool = true,
        userAgentOverride: String = "",
        microsoftClientIDOverride: String = "",
        curseForgeAPIKey: String = "",
        modrinthToken: String = "",
        technicClientID: String = "",
        proxyType: String = "None",
        proxyAddress: String = "127.0.0.1",
        proxyPort: Int = 8080,
        proxyUsername: String = "",
        proxyPassword: String = ""
    ) {
        guard instanceDirectoryURL.isFileURL,
              !instanceDirectoryURL.path.isEmpty,
              instanceDirectoryURL.path.hasPrefix("/"),
              ["fit", "fill", "strech"].contains(catFit),
              (0...100).contains(catOpacity),
              numberOfConcurrentTasks >= 1,
              numberOfConcurrentDownloads >= 1,
              numberOfManualRetries >= 0,
              requestTimeoutSeconds >= 0,
              (5...16).contains(consoleFontSize),
              (10_000...1_000_000).contains(consoleMaxLines),
              (0...3).contains(pasteType),
              ["Default", "None", "SOCKS5", "HTTP"].contains(proxyType),
              (1...65_535).contains(proxyPort),
              !(["SOCKS5", "HTTP"].contains(proxyType) && proxyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
              Self.isValidServiceURL(pasteCustomAPIBase),
              Self.isValidServiceURL(metadataURLOverride),
              Self.isValidServiceURL(assetsURLOverride),
              Self.isValidServiceURL(legacyFMLLibrariesURLOverride) else {
            return nil
        }

        self.instanceDirectoryURL = instanceDirectoryURL.standardizedFileURL
        self.iconTheme = iconTheme
        self.applicationTheme = applicationTheme
        self.backgroundCat = backgroundCat
        self.catOpacity = catOpacity
        self.catFit = catFit
        self.language = language
        self.useSystemLocale = useSystemLocale
        self.menuBarInsteadOfToolBar = menuBarInsteadOfToolBar
        self.statusBarVisible = statusBarVisible
        self.toolbarsLocked = toolbarsLocked
        self.numberOfConcurrentTasks = numberOfConcurrentTasks
        self.numberOfConcurrentDownloads = numberOfConcurrentDownloads
        self.numberOfManualRetries = numberOfManualRetries
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.consoleFont = consoleFont
        self.consoleFontSize = consoleFontSize
        self.consoleMaxLines = consoleMaxLines
        self.consoleOverflowStop = consoleOverflowStop
        self.showConsole = showConsole
        self.autoCloseConsole = autoCloseConsole
        self.showConsoleOnError = showConsoleOnError
        self.logPrePostOutput = logPrePostOutput
        self.pasteType = pasteType
        self.pasteCustomAPIBase = pasteCustomAPIBase
        self.metadataURLOverride = metadataURLOverride
        self.refreshMetadataOnLaunch = refreshMetadataOnLaunch
        self.assetsURLOverride = assetsURLOverride
        self.legacyFMLLibrariesURLOverride = legacyFMLLibrariesURLOverride
        self.fallbackForBlockedModrinthProjects = fallbackForBlockedModrinthProjects
        self.userAgentOverride = userAgentOverride
        self.microsoftClientIDOverride = microsoftClientIDOverride
        self.curseForgeAPIKey = curseForgeAPIKey
        self.modrinthToken = modrinthToken
        self.technicClientID = technicClientID
        self.proxyType = proxyType
        self.proxyAddress = proxyAddress
        self.proxyPort = proxyPort
        self.proxyUsername = proxyUsername
        self.proxyPassword = proxyPassword
    }

    private static func isValidServiceURL(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty else { return false }
        return scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host))
    }

    static func fixture() -> PrismGlobalSettings {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PrismNativeSettingsFixture", isDirectory: true)
        return PrismGlobalSettings(
            instanceDirectoryURL: root.appendingPathComponent("instances", isDirectory: true),
            iconTheme: "fixture-icons",
            applicationTheme: "fixture-theme",
            backgroundCat: "fixture-cat",
            catOpacity: 73,
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
        )!
    }

    func validationMessage() -> String? {
        guard instanceDirectoryURL.isFileURL, !instanceDirectoryURL.path.isEmpty else {
            return "Choose a valid instance directory."
        }
        guard ["fit", "fill", "strech"].contains(catFit) else {
            return "Choose a supported cat presentation."
        }
        guard (0...100).contains(catOpacity) else {
            return "Cat opacity must be between 0 and 100."
        }
        guard numberOfConcurrentTasks >= 1, numberOfConcurrentDownloads >= 1 else {
            return "Concurrent task and download counts must be at least 1."
        }
        guard numberOfManualRetries >= 0, requestTimeoutSeconds >= 0 else {
            return "Retry and timeout values cannot be negative."
        }
        guard (5...16).contains(consoleFontSize) else {
            return "Console font size must be between 5 and 16."
        }
        guard (10_000...1_000_000).contains(consoleMaxLines) else {
            return "Console lines must be between 10,000 and 1,000,000."
        }
        guard (0...3).contains(pasteType) else { return "Choose a supported paste service." }
        guard ["Default", "None", "SOCKS5", "HTTP"].contains(proxyType), (1...65_535).contains(proxyPort) else {
            return "Choose a valid proxy type and port."
        }
        guard !(["SOCKS5", "HTTP"].contains(proxyType)
                && proxyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else {
            return "Enter a proxy server address."
        }
        for value in [pasteCustomAPIBase, metadataURLOverride, assetsURLOverride, legacyFMLLibrariesURLOverride]
        where !Self.isValidServiceURL(value) {
            return "Service URLs must use HTTPS. HTTP is allowed only for local development servers."
        }
        return nil
    }

    func makeBridgeSettings() -> PRGlobalSettings? {
        PRGlobalSettings(
            instanceDirectoryURL: instanceDirectoryURL,
            iconTheme: iconTheme,
            applicationTheme: applicationTheme,
            backgroundCat: backgroundCat,
            catOpacity: catOpacity,
            catFit: catFit,
            language: language,
            useSystemLocale: useSystemLocale,
            menuBarInsteadOfToolBar: menuBarInsteadOfToolBar,
            statusBarVisible: statusBarVisible,
            toolbarsLocked: toolbarsLocked,
            numberOfConcurrentTasks: numberOfConcurrentTasks,
            numberOfConcurrentDownloads: numberOfConcurrentDownloads,
            numberOfManualRetries: numberOfManualRetries,
            requestTimeoutSeconds: requestTimeoutSeconds,
            consoleFont: consoleFont,
            consoleFontSize: consoleFontSize,
            consoleMaxLines: consoleMaxLines,
            consoleOverflowStop: consoleOverflowStop,
            showConsole: showConsole,
            autoCloseConsole: autoCloseConsole,
            showConsoleOnError: showConsoleOnError,
            logPrePostOutput: logPrePostOutput,
            pasteType: pasteType,
            pasteCustomAPIBase: pasteCustomAPIBase,
            metadataURLOverride: metadataURLOverride,
            refreshMetadataOnLaunch: refreshMetadataOnLaunch,
            assetsURLOverride: assetsURLOverride,
            legacyFMLLibrariesURLOverride: legacyFMLLibrariesURLOverride,
            fallbackForBlockedModrinthProjects: fallbackForBlockedModrinthProjects,
            userAgentOverride: userAgentOverride,
            microsoftClientIDOverride: microsoftClientIDOverride,
            curseForgeAPIKey: curseForgeAPIKey,
            modrinthToken: modrinthToken,
            technicClientID: technicClientID,
            proxyType: proxyType,
            proxyAddress: proxyAddress,
            proxyPort: proxyPort,
            proxyUsername: proxyUsername,
            proxyPassword: proxyPassword
        )
    }
}

struct PrismGlobalSettingsFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let recoveryAction: PrismInstanceDetailsRecoveryAction

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }
}

enum PrismGlobalSettingsState: Equatable, Sendable {
    case loading
    case empty
    case failed(PrismGlobalSettingsFailure)
    case content(PrismGlobalSettings)
}

enum PrismGlobalSettingsSaveState: Equatable, Sendable {
    case idle
    case saving(generation: Int)
    case failed(PrismGlobalSettingsFailure)
}

struct PrismDirectorySelectionState: Equatable, Sendable {
    private(set) var confirmedURL: URL?
    private(set) var draftURL: URL?

    init(confirmedURL: URL? = nil) {
        self.confirmedURL = confirmedURL
        self.draftURL = confirmedURL
    }

    @discardableResult
    mutating func apply(filePanelResult: Result<URL, Error>) -> Bool {
        guard case .success(let url) = filePanelResult,
              url.isFileURL,
              !url.path.isEmpty,
              url.path.hasPrefix("/"),
              Self.isDirectory(url) else {
            return false
        }

        draftURL = url.standardizedFileURL
        return true
    }

    mutating func confirm() {
        confirmedURL = draftURL
    }

    mutating func cancel() {
        draftURL = confirmedURL
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

@MainActor
final class PrismGlobalSettingsModel: ObservableObject {
    @Published private(set) var state: PrismGlobalSettingsState
    @Published private(set) var confirmed: PrismGlobalSettings?
    @Published private(set) var draft: PrismGlobalSettings?
    @Published private(set) var saveState: PrismGlobalSettingsSaveState = .idle
    @Published private(set) var directorySelectionError: String?

    private let bridge: PRPrismBridge?
    private let onLoad: (() -> Void)?
    private let onSave: ((PrismGlobalSettings, Int) -> Void)?
    private var saveGeneration = 0
    private var loadToken: PRBridgeObservationToken?
    private var saveToken: PRBridgeObservationToken?

    init(
        initialSettings: PrismGlobalSettings? = PrismGlobalSettings.fixture(),
        bridge: PRPrismBridge? = nil,
        onLoad: (() -> Void)? = nil,
        onSave: ((PrismGlobalSettings, Int) -> Void)? = nil
    ) {
        self.bridge = bridge
        if let initialSettings {
            self.state = .content(initialSettings)
            self.confirmed = initialSettings
            self.draft = initialSettings
        } else {
            self.state = .empty
            self.confirmed = nil
            self.draft = nil
        }
        self.onLoad = onLoad
        self.onSave = onSave
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    var hasChanges: Bool {
        confirmed != draft
    }

    var validationMessage: String? {
        draft?.validationMessage()
    }

    var isSaveAvailable: Bool {
        guard case .content = state, let draft, !isSaving else {
            return false
        }
        return hasChanges && draft.validationMessage() == nil
    }

    var isSaving: Bool {
        if case .saving = saveState {
            return true
        }
        return false
    }

    var saveFailure: PrismGlobalSettingsFailure? {
        guard case .failed(let failure) = saveState else {
            return nil
        }
        return failure
    }

    @discardableResult
    func beginLoading() -> Bool {
        saveGeneration += 1
        state = .loading
        confirmed = nil
        draft = nil
        saveState = .idle
        directorySelectionError = nil
        loadToken?.cancel()
        if let bridge {
            loadToken = bridge.loadGlobalSettings { [weak self] settings, error in
                self?.loadToken = nil
                if let settings {
                    _ = self?.apply(settings: settings)
                } else if let error {
                    _ = self?.apply(loadError: error)
                }
            }
        } else {
            onLoad?()
        }
        return true
    }

    @discardableResult
    func apply(settings bridgeSettings: PRGlobalSettings) -> Bool {
        guard let mapped = PrismGlobalSettings(bridgeSettings: bridgeSettings) else {
            return false
        }

        saveGeneration += 1
        state = .content(mapped)
        confirmed = mapped
        draft = mapped
        saveState = .idle
        directorySelectionError = nil
        return true
    }

    @discardableResult
    func apply(updateResult bridgeResult: PRGlobalSettingsUpdateResult, generation: Int? = nil) -> Bool {
        guard case .saving(let activeGeneration) = saveState,
              (generation ?? activeGeneration) == activeGeneration else {
            return false
        }

        switch bridgeResult.outcome {
        case .succeeded:
            guard let settings = bridgeResult.settings,
                  let mapped = PrismGlobalSettings(bridgeSettings: settings) else {
                return false
            }
            state = .content(mapped)
            confirmed = mapped
            draft = mapped
            saveState = .idle
            directorySelectionError = nil
        case .rejected:
            saveState = .failed(Self.failure(key: "global.settings.updateRejected", diagnostic: nil))
        @unknown default:
            return false
        }
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, generation: Int? = nil) -> Bool {
        guard case .saving(let activeGeneration) = saveState,
              (generation ?? activeGeneration) == activeGeneration,
              !error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        saveState = .failed(
            Self.failure(
                key: error.localizationKey,
                diagnostic: error.diagnosticText,
                recovery: error.recoveryKind == .retry ? .retry : .none
            )
        )
        return true
    }

    @discardableResult
    func apply(loadError error: PRBridgeError) -> Bool {
        guard isLoading, !error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        state = .failed(
            Self.failure(
                key: error.localizationKey,
                diagnostic: error.diagnosticText,
                recovery: error.recoveryKind == .retry ? .retry : .none
            )
        )
        confirmed = nil
        draft = nil
        return true
    }

    @discardableResult
    func applyDirectorySelection(filePanelResult: Result<URL, Error>) -> Bool {
        guard case .success(let url) = filePanelResult else {
            directorySelectionError = nil
            return false
        }
        guard url.isFileURL,
              !url.path.isEmpty,
              url.path.hasPrefix("/"),
              Self.isDirectory(url) else {
            directorySelectionError = "The selected location is not an accessible directory."
            return false
        }

        updateDraft { $0.instanceDirectoryURL = url.standardizedFileURL }
        directorySelectionError = nil
        return true
    }

    func updateDraft(_ update: (inout PrismGlobalSettings) -> Void) {
        guard !isSaving, var draft else {
            return
        }
        update(&draft)
        self.draft = draft
        directorySelectionError = nil
        if case .failed = saveState {
            saveState = .idle
        }
    }

    @discardableResult
    func save() -> Bool {
        guard let draft, isSaveAvailable else {
            return false
        }

        saveGeneration += 1
        let generation = saveGeneration
        saveState = .saving(generation: generation)
        if let bridge, let bridgeSettings = draft.makeBridgeSettings() {
            saveToken?.cancel()
            saveToken = bridge.update(bridgeSettings) { [weak self] result, error in
                self?.saveToken = nil
                if let result {
                    _ = self?.apply(updateResult: result, generation: generation)
                } else if let error {
                    _ = self?.apply(error: error, generation: generation)
                }
            }
        } else if let onSave {
            onSave(draft, generation)
        } else {
            confirmed = draft
            state = .content(draft)
            saveState = .idle
        }
        return true
    }

    @discardableResult
    func retrySave() -> Bool {
        guard case .failed(let failure) = saveState, failure.isRetryAvailable,
              let draft, draft.validationMessage() == nil else {
            return false
        }
        saveGeneration += 1
        let generation = saveGeneration
        saveState = .saving(generation: generation)
        if let bridge, let bridgeSettings = draft.makeBridgeSettings() {
            saveToken?.cancel()
            saveToken = bridge.update(bridgeSettings) { [weak self] result, error in
                self?.saveToken = nil
                if let result {
                    _ = self?.apply(updateResult: result, generation: generation)
                } else if let error {
                    _ = self?.apply(error: error, generation: generation)
                }
            }
        } else {
            onSave?(draft, generation)
        }
        return true
    }

    @discardableResult
    func cancelDraft() -> Bool {
        guard !isSaving, let confirmed else {
            return false
        }
        draft = confirmed
        saveState = .idle
        directorySelectionError = nil
        return true
    }

    func clear() {
        saveGeneration += 1
        loadToken?.cancel()
        saveToken?.cancel()
        state = .empty
        confirmed = nil
        draft = nil
        saveState = .idle
        directorySelectionError = nil
    }

    private static func failure(
        key: String,
        diagnostic: String?,
        recovery: PrismInstanceDetailsRecoveryAction = .none
    ) -> PrismGlobalSettingsFailure {
        PrismGlobalSettingsFailure(localizationKey: key, diagnosticText: diagnostic, recoveryAction: recovery)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

struct PrismSettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: PrismGlobalSettingsModel
    @ObservedObject var javaModel: PrismJavaDiscoveryModel
    @ObservedObject var accountModel: PrismAccountModel
    @ObservedObject var authenticationModel: PrismAccountAuthenticationModel
    @ObservedObject var offlineIdentityModel: PrismOfflineLaunchIdentityModel
    @ObservedObject var skinModel: PrismSkinManagementModel
    @State private var isDirectoryImporterPresented = false
    @State private var selectedTab: SettingsTab? = .general
    @State private var searchText = ""

    private enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
        case general
        case appearance
        case language
        case minecraft
        case java
        case accounts
        case services
        case proxy

        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .language: "Language"
            case .minecraft: "Minecraft"
            case .java: "Java"
            case .accounts: "Accounts"
            case .services: "Services"
            case .proxy: "Proxy"
            }
        }
        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintbrush"
            case .language: "globe"
            case .minecraft: "gamecontroller"
            case .java: "cup.and.saucer"
            case .accounts: "person.crop.circle"
            case .services: "network"
            case .proxy: "point.3.connected.trianglepath.dotted"
            }
        }
        var description: String {
            switch self {
            case .general: "Manage instance storage and download behavior."
            case .appearance: "Choose how Prism and its console are presented."
            case .language: "Set the language and regional behavior used by Prism."
            case .minecraft: "Configure the Minecraft console and its history."
            case .java: "Discover and select Java installations."
            case .accounts: "Manage Minecraft accounts and authentication."
            case .services: "Configure metadata, downloads, and service credentials."
            case .proxy: "Control how Prism's backend connects to the network."
            }
        }
        var usesGlobalDraft: Bool { self != .java && self != .accounts }
    }

    private var visibleTabs: [SettingsTab] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SettingsTab.allCases }
        return SettingsTab.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Loading Settings…")
                    .accessibilityIdentifier("prism.settings.loading")
            } else if case .failed(let failure) = model.state {
                ContentUnavailableView {
                    Label("Settings Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure.diagnosticText ?? "Global settings could not be loaded.")
                } actions: {
                    Button("Retry") {
                        _ = model.beginLoading()
                    }
                    .disabled(!failure.isRetryAvailable)
                    .accessibilityIdentifier("prism.settings.retry")
                }
                .accessibilityIdentifier("prism.settings.failed")
            } else if model.draft != nil {
                settingsTabs
            } else {
                ContentUnavailableView("No Settings", systemImage: "gear", description: Text("Settings are not available."))
                    .accessibilityIdentifier("prism.settings.empty")
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            if case .empty = model.state {
                _ = model.beginLoading()
            }
        }
    }

    private var settingsTabs: some View {
        NavigationSplitView {
            List(visibleTabs, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
                    .accessibilityIdentifier("prism.settings.sidebar.\(tab.id)")
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch selectedTab ?? .general {
                    case .general: generalForm
                    case .appearance: appearanceForm
                    case .language: languageForm
                    case .minecraft: minecraftForm
                    case .java: PrismJavaSettingsView(model: javaModel)
                    case .accounts:
                        PrismAccountSettingsView(
                            model: accountModel,
                            authenticationModel: authenticationModel,
                            offlineIdentityModel: offlineIdentityModel,
                            onManageSkins: { accountIdentifier in
                                skinModel.setAccountContext(identifier: accountIdentifier)
                                _ = skinModel.beginLoad()
                                openWindow(id: "prism.skin-management")
                            }
                        )
                    case .services: servicesForm
                    case .proxy: proxyForm
                    }
                }
                .navigationTitle((selectedTab ?? .general).title)

                if selectedTab?.usesGlobalDraft != false {
                    Divider()
                    HStack {
                        if let message = model.validationMessage ?? model.directorySelectionError {
                            Text(message)
                                .foregroundStyle(.secondary)
                                .accessibilityValue(Text(message))
                        } else if let failure = model.saveFailure {
                            Text(failure.diagnosticText ?? "Settings could not be saved.")
                                .foregroundStyle(.secondary)
                                .accessibilityValue(Text(failure.diagnosticText ?? "Settings could not be saved."))
                        }
                        Spacer()
                        Button("Revert") {
                            _ = model.cancelDraft()
                        }
                        .disabled(!model.hasChanges || model.isSaving)
                        .accessibilityIdentifier("prism.settings.revert")
                        Button("Save") {
                            _ = model.save()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.isSaveAvailable)
                        .accessibilityIdentifier("prism.settings.save")
                        if model.isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Saving Settings")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("prism.settings.form")
    }

    private var appearanceForm: some View {
        Form {
            Section("Launcher Appearance") {
                TextField("Icon theme identifier", text: binding(\.iconTheme, defaultValue: ""))
                    .help("The adapter validates discovered icon theme identifiers.")
                    .accessibilityIdentifier("prism.settings.icon-theme")
                TextField("Application theme identifier", text: binding(\.applicationTheme, defaultValue: ""))
                    .help("Theme changes apply to the native shell after a confirmed save.")
                    .accessibilityIdentifier("prism.settings.application-theme")
            }

            Section("Console Appearance") {
                TextField("Console font", text: binding(\.consoleFont, defaultValue: ""))
                    .accessibilityIdentifier("prism.settings.console-font")
                Stepper(value: intBinding(\.consoleFontSize, defaultValue: 11), in: 5...16) {
                    Text("Font size: \(model.draft?.consoleFontSize ?? 11)")
                }
                .accessibilityValue(Text("\(model.draft?.consoleFontSize ?? 11) points"))
                .accessibilityIdentifier("prism.settings.console-font-size")
            }
        }
        .formStyle(.grouped)
    }

    private var generalForm: some View {
        Form {
            Section("Instances") {
                LabeledContent("Instance directory") {
                    Text(model.draft?.instanceDirectoryURL.path ?? "Not selected")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Button("Choose…") { isDirectoryImporterPresented = true }
                    .fileImporter(
                        isPresented: $isDirectoryImporterPresented,
                        allowedContentTypes: [.folder],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let urls):
                            if let url = urls.first { _ = model.applyDirectorySelection(filePanelResult: .success(url)) }
                        case .failure(let error):
                            _ = model.applyDirectorySelection(filePanelResult: .failure(error))
                        }
                    }
                    .help("Choose an existing directory. Cancel leaves the current directory unchanged.")
                    .accessibilityIdentifier("prism.settings.instance-directory")
            }

            Section("Downloads") {
                TextField("Concurrent tasks", value: intBinding(\.numberOfConcurrentTasks, defaultValue: 10), format: .number)
                    .accessibilityIdentifier("prism.settings.concurrent-tasks")
                TextField("Concurrent downloads", value: intBinding(\.numberOfConcurrentDownloads, defaultValue: 6), format: .number)
                    .accessibilityIdentifier("prism.settings.concurrent-downloads")
                TextField("Manual retries", value: intBinding(\.numberOfManualRetries, defaultValue: 1), format: .number)
                    .accessibilityIdentifier("prism.settings.manual-retries")
                TextField("Request timeout (seconds)", value: intBinding(\.requestTimeoutSeconds, defaultValue: 60), format: .number)
                    .help("No undocumented upper bound is imposed; this applies to the next operation.")
                    .accessibilityIdentifier("prism.settings.request-timeout")
            }
        }
        .formStyle(.grouped)
    }

    private var languageForm: some View {
        Form {
            Section {
                Toggle("Use system language and region", isOn: binding(\.useSystemLocale, defaultValue: false))
                    .accessibilityIdentifier("prism.settings.system-locale")
                TextField("Language identifier", text: binding(\.language, defaultValue: ""))
                    .disabled(model.draft?.useSystemLocale == true)
                    .accessibilityIdentifier("prism.settings.language")
            } header: {
                Text("Language and Region")
            } footer: {
                Text("Restart Prism after changing the launcher language.")
            }
        }
        .formStyle(.grouped)
    }

    private var minecraftForm: some View {
        Form {
            Section("Console Window") {
                Toggle("Show console when Minecraft launches", isOn: binding(\.showConsole, defaultValue: false))
                Toggle("Show console when Minecraft exits with an error", isOn: binding(\.showConsoleOnError, defaultValue: true))
                Toggle("Hide console when Minecraft exits", isOn: binding(\.autoCloseConsole, defaultValue: false))
                Toggle("Include pre-launch and post-exit output", isOn: binding(\.logPrePostOutput, defaultValue: true))
            }
            Section {
                TextField("Maximum lines", value: intBinding(\.consoleMaxLines, defaultValue: 100_000), format: .number)
                    .accessibilityIdentifier("prism.settings.console-max-lines")
                Toggle("Stop Minecraft if the console limit is exceeded", isOn: binding(\.consoleOverflowStop, defaultValue: true))
            } header: {
                Text("Console History")
            } footer: {
                Text("These changes apply to the next Minecraft launch.")
            }
        }
        .formStyle(.grouped)
    }

    private var servicesForm: some View {
        Form {
            Section("Log Uploads") {
                Picker("Paste service", selection: intBinding(\.pasteType, defaultValue: 3)) {
                    Text("0x0.st").tag(0)
                    Text("Hastebin").tag(1)
                    Text("paste.gg").tag(2)
                    Text("mclo.gs").tag(3)
                }
                TextField("Custom API base URL", text: binding(\.pasteCustomAPIBase, defaultValue: ""))
                    .textContentType(.URL)
                    .accessibilityIdentifier("prism.settings.services.paste-url")
            }

            Section {
                TextField("Metadata server", text: binding(\.metadataURLOverride, defaultValue: ""))
                    .textContentType(.URL)
                Toggle("Refresh metadata when Prism launches", isOn: binding(\.refreshMetadataOnLaunch, defaultValue: true))
                TextField("Assets server", text: binding(\.assetsURLOverride, defaultValue: ""))
                    .textContentType(.URL)
                TextField("Legacy FML libraries server", text: binding(\.legacyFMLLibrariesURLOverride, defaultValue: ""))
                    .textContentType(.URL)
                Toggle("Use fallback downloads for blocked Modrinth projects", isOn: binding(\.fallbackForBlockedModrinthProjects, defaultValue: true))
            } header: {
                Text("Minecraft Services")
            } footer: {
                Text("Leave an address empty to use Prism's default service. Remote overrides must use HTTPS.")
            }

            Section {
                TextField("Microsoft client ID", text: binding(\.microsoftClientIDOverride, defaultValue: ""))
                SecureField("CurseForge API key", text: binding(\.curseForgeAPIKey, defaultValue: ""))
                SecureField("Modrinth token", text: binding(\.modrinthToken, defaultValue: ""))
                TextField("Technic client ID", text: binding(\.technicClientID, defaultValue: ""))
                TextField("Custom user agent", text: binding(\.userAgentOverride, defaultValue: ""))
            } header: {
                Text("Service Credentials")
            } footer: {
                Text("Credentials stay in the local Prism backend and are never included in UI logs. For Prism Launcher compatibility, they are stored in its local configuration file.")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("prism.settings.services")
    }

    private var proxyForm: some View {
        let proxyEnabled = model.draft?.proxyType == "HTTP" || model.draft?.proxyType == "SOCKS5"
        return Form {
            Section("Proxy") {
                Picker("Configuration", selection: binding(\.proxyType, defaultValue: "None")) {
                    Text("Use System Settings").tag("Default")
                    Text("No Proxy").tag("None")
                    Text("HTTP").tag("HTTP")
                    Text("SOCKS5").tag("SOCKS5")
                }
                .pickerStyle(.radioGroup)
            }

            Section("Server") {
                TextField("Address", text: binding(\.proxyAddress, defaultValue: "127.0.0.1"))
                TextField("Port", value: intBinding(\.proxyPort, defaultValue: 8080), format: .number)
            }
            .disabled(!proxyEnabled)

            Section {
                TextField("Username", text: binding(\.proxyUsername, defaultValue: ""))
                SecureField("Password", text: binding(\.proxyPassword, defaultValue: ""))
            } header: {
                Text("Authentication")
            } footer: {
                Text("Proxy settings apply to Prism's backend requests, not Minecraft. For Prism Launcher compatibility, credentials are stored in its local configuration file.")
            }
            .disabled(!proxyEnabled)
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("prism.settings.proxy")
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PrismGlobalSettings, Value>, defaultValue: Value) -> Binding<Value> {
        Binding(
            get: { model.draft?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                model.updateDraft { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func intBinding(
        _ keyPath: WritableKeyPath<PrismGlobalSettings, Int>,
        defaultValue: Int
    ) -> Binding<Int> {
        binding(keyPath, defaultValue: defaultValue)
    }

}
