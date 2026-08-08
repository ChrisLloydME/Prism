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
            logPrePostOutput: bridgeSettings.logPrePostOutput
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
        logPrePostOutput: Bool
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
              (10_000...1_000_000).contains(consoleMaxLines) else {
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
            logPrePostOutput: logPrePostOutput
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

    private let onLoad: (() -> Void)?
    private let onSave: ((PrismGlobalSettings, Int) -> Void)?
    private var saveGeneration = 0

    init(
        initialSettings: PrismGlobalSettings = .fixture(),
        onLoad: (() -> Void)? = nil,
        onSave: ((PrismGlobalSettings, Int) -> Void)? = nil
    ) {
        self.state = .content(initialSettings)
        self.confirmed = initialSettings
        self.draft = initialSettings
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
        onLoad?()
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
        if let onSave {
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
        onSave?(draft, generation)
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
    @ObservedObject var model: PrismGlobalSettingsModel
    @ObservedObject var javaModel: PrismJavaDiscoveryModel
    @ObservedObject var accountModel: PrismAccountModel
    @ObservedObject var authenticationModel: PrismAccountAuthenticationModel
    @State private var isDirectoryImporterPresented = false
    @State private var selectedTab: SettingsTab = .appearance

    private enum SettingsTab: Hashable {
        case appearance
        case general
        case java
        case accounts
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
        .frame(minWidth: 560, minHeight: 460)
    }

    private var settingsTabs: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                appearanceForm
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }
                    .tag(SettingsTab.appearance)
                generalForm
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsTab.general)
                PrismJavaSettingsView(model: javaModel)
                    .tabItem { Label("Java", systemImage: "cup.and.saucer") }
                    .tag(SettingsTab.java)
                PrismAccountSettingsView(model: accountModel, authenticationModel: authenticationModel)
                    .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                    .tag(SettingsTab.accounts)
            }

            if selectedTab != .java && selectedTab != .accounts {
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
                .padding()
            }
        }
        .accessibilityIdentifier("prism.settings.form")
    }

    private var appearanceForm: some View {
        Form {
            Section("Directories") {
                HStack {
                    Text("Instance directory")
                    Spacer()
                    Text(model.draft?.instanceDirectoryURL.path ?? "Not selected")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Button("Choose Instance Directory…") {
                    isDirectoryImporterPresented = true
                }
                .fileImporter(
                    isPresented: $isDirectoryImporterPresented,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            _ = model.applyDirectorySelection(filePanelResult: .success(url))
                        }
                    case .failure(let error):
                        _ = model.applyDirectorySelection(filePanelResult: .failure(error))
                    }
                }
                .help("Choose an existing directory. Cancel leaves the current directory unchanged.")
                .accessibilityIdentifier("prism.settings.instance-directory")
            }

            Section("Themes and Language") {
                TextField("Icon theme identifier", text: binding(\.iconTheme, defaultValue: ""))
                    .help("The adapter validates discovered icon theme identifiers.")
                    .accessibilityIdentifier("prism.settings.icon-theme")
                TextField("Application theme identifier", text: binding(\.applicationTheme, defaultValue: ""))
                    .help("Theme changes apply to the native shell after a confirmed save.")
                    .accessibilityIdentifier("prism.settings.application-theme")
                TextField("Background cat identifier", text: binding(\.backgroundCat, defaultValue: ""))
                    .accessibilityIdentifier("prism.settings.background-cat")
                Picker("Cat presentation", selection: binding(\.catFit, defaultValue: "fit")) {
                    Text("Fit").tag("fit")
                    Text("Fill").tag("fill")
                    Text("Stretch (legacy)").tag("strech")
                }
                .accessibilityIdentifier("prism.settings.cat-fit")
                Slider(value: doubleBinding(\.catOpacity, defaultValue: 100), in: 0...100, step: 1) {
                    Text("Cat opacity")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("100")
                }
                .accessibilityValue(Text("\(model.draft?.catOpacity ?? 100) percent"))
                .accessibilityIdentifier("prism.settings.cat-opacity")
                TextField("Language identifier", text: binding(\.language, defaultValue: ""))
                    .accessibilityIdentifier("prism.settings.language")
                Toggle("Use system locale", isOn: binding(\.useSystemLocale, defaultValue: false))
                    .help("Use the system locale for native localization.")
                    .accessibilityIdentifier("prism.settings.system-locale")
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
        .padding()
    }

    private var generalForm: some View {
        Form {
            Section("Launcher") {
                TextField("Concurrent tasks", value: intBinding(\.numberOfConcurrentTasks, defaultValue: 10), format: .number)
                    .accessibilityIdentifier("prism.settings.concurrent-tasks")
                TextField("Concurrent downloads", value: intBinding(\.numberOfConcurrentDownloads, defaultValue: 6), format: .number)
                    .accessibilityIdentifier("prism.settings.concurrent-downloads")
                TextField("Manual retries", value: intBinding(\.numberOfManualRetries, defaultValue: 1), format: .number)
                    .accessibilityIdentifier("prism.settings.manual-retries")
                TextField("Request timeout (seconds)", value: intBinding(\.requestTimeoutSeconds, defaultValue: 60), format: .number)
                    .help("No undocumented upper bound is imposed; this applies to the next operation.")
                    .accessibilityIdentifier("prism.settings.request-timeout")
                Toggle("Menu bar instead of toolbar", isOn: binding(\.menuBarInsteadOfToolBar, defaultValue: false))
                    .help("Applies when the native shell is rebuilt.")
                Toggle("Show status bar", isOn: binding(\.statusBarVisible, defaultValue: true))
                Toggle("Lock toolbars", isOn: binding(\.toolbarsLocked, defaultValue: false))
            }

            Section("Console Behavior") {
                TextField("Maximum console lines", value: intBinding(\.consoleMaxLines, defaultValue: 100_000), format: .number)
                    .help("Allowed range: 10,000 to 1,000,000 lines; applies to the next log view or launch.")
                    .accessibilityIdentifier("prism.settings.console-max-lines")
                Toggle("Stop when console overflows", isOn: binding(\.consoleOverflowStop, defaultValue: true))
                Toggle("Show console", isOn: binding(\.showConsole, defaultValue: false))
                Toggle("Close console automatically", isOn: binding(\.autoCloseConsole, defaultValue: false))
                Toggle("Show console on error", isOn: binding(\.showConsoleOnError, defaultValue: true))
                Toggle("Log pre- and post-launch output", isOn: binding(\.logPrePostOutput, defaultValue: true))
                    .help("Applies to the next Minecraft launch or console flow.")
            }
        }
        .formStyle(.grouped)
        .padding()
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

    private func doubleBinding(
        _ keyPath: WritableKeyPath<PrismGlobalSettings, Int>,
        defaultValue: Int
    ) -> Binding<Double> {
        Binding(
            get: { Double(model.draft?[keyPath: keyPath] ?? defaultValue) },
            set: { newValue in
                model.updateDraft { $0[keyPath: keyPath] = Int(newValue.rounded()) }
            }
        )
    }
}
