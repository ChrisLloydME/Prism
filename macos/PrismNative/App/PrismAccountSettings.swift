import Foundation
import SwiftUI

enum PrismAccountType: Int, Equatable, Sendable {
    case microsoft
    case offline

    init?(bridgeType: PRAccountType) {
        switch bridgeType {
        case .microsoft:
            self = .microsoft
        case .offline:
            self = .offline
        @unknown default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .microsoft:
            return "Microsoft"
        case .offline:
            return "Offline"
        }
    }
}

enum PrismAccountState: Int, Equatable, Sendable {
    case unchecked
    case offline
    case working
    case online
    case disabled
    case errored
    case expired
    case gone

    init?(bridgeState: PRAccountState) {
        switch bridgeState {
        case .unchecked:
            self = .unchecked
        case .offline:
            self = .offline
        case .working:
            self = .working
        case .online:
            self = .online
        case .disabled:
            self = .disabled
        case .errored:
            self = .errored
        case .expired:
            self = .expired
        case .gone:
            self = .gone
        @unknown default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .unchecked:
            return "Not checked"
        case .offline:
            return "Offline"
        case .working:
            return "Working"
        case .online:
            return "Ready"
        case .disabled:
            return "Disabled"
        case .errored:
            return "Error"
        case .expired:
            return "Expired"
        case .gone:
            return "Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .online:
            return "checkmark.circle"
        case .working:
            return "arrow.triangle.2.circlepath"
        case .offline:
            return "wifi.slash"
        case .unchecked:
            return "questionmark.circle"
        case .disabled, .errored, .expired, .gone:
            return "exclamationmark.triangle"
        }
    }
}

struct PrismAccount: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let displayName: String
    let type: PrismAccountType
    let state: PrismAccountState
    let ownsMinecraft: Bool
    let isBusy: Bool
    let canBeSelected: Bool
    let diagnosticText: String?

    init?(bridgeAccount: PRAccountSnapshot) {
        let identifier = bridgeAccount.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = bridgeAccount.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, !name.isEmpty,
              let type = PrismAccountType(bridgeType: bridgeAccount.type),
              let state = PrismAccountState(bridgeState: bridgeAccount.state) else {
            return nil
        }

        self.id = identifier
        self.displayName = name
        self.type = type
        self.state = state
        self.ownsMinecraft = bridgeAccount.ownsMinecraft
        self.isBusy = bridgeAccount.isBusy
        self.canBeSelected = bridgeAccount.canBeSelected
        let diagnostic = bridgeAccount.diagnosticText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.diagnosticText = diagnostic?.isEmpty == false ? diagnostic : nil
    }

    init(
        id: String,
        displayName: String,
        type: PrismAccountType,
        state: PrismAccountState,
        ownsMinecraft: Bool,
        isBusy: Bool = false,
        canBeSelected: Bool = true,
        diagnosticText: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.type = type
        self.state = state
        self.ownsMinecraft = ownsMinecraft
        self.isBusy = isBusy
        self.canBeSelected = canBeSelected
        self.diagnosticText = diagnosticText
    }

    var isSelectable: Bool {
        canBeSelected && !isBusy
    }

    var statusTitle: String {
        if isBusy {
            return "Busy"
        }
        return state.title
    }

    var accessibilitySummary: String {
        let ownership = ownsMinecraft ? "Minecraft entitlement confirmed" : "Minecraft entitlement not confirmed"
        return displayName + ", " + type.title + ", " + statusTitle + ", " + ownership
    }

    static func fixture() -> [PrismAccount] {
        [
            PrismAccount(
                id: "account.fixture.microsoft",
                displayName: "Fixture Microsoft Account",
                type: .microsoft,
                state: .online,
                ownsMinecraft: true
            ),
            PrismAccount(
                id: "account.fixture.offline",
                displayName: "Fixture Offline Profile",
                type: .offline,
                state: .offline,
                ownsMinecraft: false
            ),
            PrismAccount(
                id: "account.fixture.expired",
                displayName: "Fixture Expired Account",
                type: .microsoft,
                state: .expired,
                ownsMinecraft: false,
                canBeSelected: false,
                diagnosticText: "This fixture account requires recovery before it can be selected."
            ),
        ]
    }
}

struct PrismAccountFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let recoveryAction: PrismInstanceDetailsRecoveryAction

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }
}

enum PrismAccountSnapshotState: Equatable, Sendable {
    case idle
    case loading(generation: Int)
    case empty
    case content([PrismAccount])
    case failed(PrismAccountFailure)
    case cancelled
}

enum PrismAccountSelectionState: Equatable, Sendable {
    case idle
    case saving(generation: Int)
    case failed(PrismAccountFailure)
}

@MainActor
final class PrismAccountModel: ObservableObject {
    @Published private(set) var state: PrismAccountSnapshotState
    @Published private(set) var confirmedActiveAccountID: String?
    @Published private(set) var draftActiveAccountID: String?
    @Published private(set) var selectionState: PrismAccountSelectionState = .idle

    private let onDiscover: ((Int) -> Void)?
    private let onSelect: ((String?, Int) -> Void)?
    private let onCancel: (() -> Void)?
    private var generation = 0

    init(
        initialAccounts: [PrismAccount] = PrismAccount.fixture(),
        activeAccountID: String? = "account.fixture.microsoft",
        onDiscover: ((Int) -> Void)? = nil,
        onSelect: ((String?, Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        let knownIDs = Set(initialAccounts.map(\.id))
        let confirmedID = activeAccountID.flatMap { knownIDs.contains($0) ? $0 : nil }
        self.state = initialAccounts.isEmpty ? .empty : .content(initialAccounts)
        self.confirmedActiveAccountID = confirmedID
        self.draftActiveAccountID = confirmedID
        self.onDiscover = onDiscover
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    var accounts: [PrismAccount] {
        guard case .content(let accounts) = state else {
            return []
        }
        return accounts
    }

    var activeAccount: PrismAccount? {
        accounts.first { $0.id == draftActiveAccountID }
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    var isSavingSelection: Bool {
        if case .saving = selectionState {
            return true
        }
        return false
    }

    var selectionFailure: PrismAccountFailure? {
        guard case .failed(let failure) = selectionState else {
            return nil
        }
        return failure
    }

    @discardableResult
    func refresh() -> Bool {
        generation += 1
        let activeGeneration = generation
        state = .loading(generation: activeGeneration)
        selectionState = .idle
        onDiscover?(activeGeneration)
        return true
    }

    @discardableResult
    func cancelDiscovery() -> Bool {
        guard isLoading else {
            return false
        }
        generation += 1
        onCancel?()
        state = .cancelled
        return true
    }

    @discardableResult
    func apply(snapshotResult: PRAccountSnapshotResult, generation resultGeneration: Int? = nil) -> Bool {
        guard case .loading(let activeGeneration) = state,
              (resultGeneration ?? activeGeneration) == activeGeneration else {
            return false
        }

        switch snapshotResult.outcome {
        case .succeeded:
            let mapped = snapshotResult.accounts.compactMap(PrismAccount.init(bridgeAccount:))
            let identifiers = Set(mapped.map(\.id))
            guard mapped.count == snapshotResult.accounts.count, identifiers.count == mapped.count else {
                state = .failed(Self.failure(key: "accounts.discovery.invalidResult", diagnostic: nil, recovery: .retry))
                return false
            }
            let activeID = snapshotResult.activeAccountIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard activeID == nil || (activeID?.isEmpty == false && identifiers.contains(activeID!)) else {
                state = .failed(Self.failure(key: "accounts.discovery.invalidResult", diagnostic: nil, recovery: .retry))
                return false
            }
            state = mapped.isEmpty ? .empty : .content(mapped)
            confirmedActiveAccountID = activeID
            draftActiveAccountID = activeID
            selectionState = .idle
        case .failed, .rejected:
            state = .failed(
                Self.failure(
                    key: snapshotResult.localizationKey,
                    diagnostic: snapshotResult.diagnosticText,
                    recovery: snapshotResult.retryable ? .retry : .none
                )
            )
        case .cancelled:
            state = .cancelled
        @unknown default:
            state = .failed(Self.failure(key: "accounts.discovery.unknownOutcome", diagnostic: nil, recovery: .retry))
            return false
        }
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, generation resultGeneration: Int? = nil) -> Bool {
        guard case .loading(let activeGeneration) = state,
              (resultGeneration ?? activeGeneration) == activeGeneration,
              !error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        state = .failed(
            Self.failure(
                key: error.localizationKey,
                diagnostic: error.diagnosticText,
                recovery: error.recoveryKind == .retry ? .retry : .none
            )
        )
        return true
    }

    @discardableResult
    func select(id: String?) -> Bool {
        guard !isLoading, !isSavingSelection else {
            return false
        }
        if let id {
            guard let account = accounts.first(where: { $0.id == id }), account.isSelectable else {
                return false
            }
        }

        draftActiveAccountID = id
        generation += 1
        let activeGeneration = generation
        selectionState = .saving(generation: activeGeneration)
        if let onSelect {
            onSelect(id, activeGeneration)
        } else {
            confirmedActiveAccountID = id
            selectionState = .idle
        }
        return true
    }

    @discardableResult
    func apply(selectionResult: PRAccountSelectionResult, generation resultGeneration: Int? = nil) -> Bool {
        guard case .saving(let activeGeneration) = selectionState,
              (resultGeneration ?? activeGeneration) == activeGeneration else {
            return false
        }

        switch selectionResult.outcome {
        case .succeeded:
            let mappedAccount = selectionResult.account.flatMap(PrismAccount.init(bridgeAccount:))
            if let draftActiveAccountID {
                guard let mappedAccount, mappedAccount.id == draftActiveAccountID, mappedAccount.isSelectable else {
                    selectionState = .failed(Self.failure(key: "accounts.selection.invalidResult", diagnostic: nil, recovery: .retry))
                    return false
                }
            } else if mappedAccount != nil {
                selectionState = .failed(Self.failure(key: "accounts.selection.invalidResult", diagnostic: nil, recovery: .retry))
                return false
            }
            confirmedActiveAccountID = draftActiveAccountID
            selectionState = .idle
        case .unknownAccount, .rejected:
            selectionState = .failed(
                Self.failure(
                    key: selectionResult.localizationKey,
                    diagnostic: selectionResult.diagnosticText,
                    recovery: .retry
                )
            )
        @unknown default:
            selectionState = .failed(Self.failure(key: "accounts.selection.unknownOutcome", diagnostic: nil, recovery: .retry))
            return false
        }
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, toSelectionGeneration resultGeneration: Int? = nil) -> Bool {
        guard case .saving(let activeGeneration) = selectionState,
              (resultGeneration ?? activeGeneration) == activeGeneration,
              !error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        selectionState = .failed(
            Self.failure(
                key: error.localizationKey,
                diagnostic: error.diagnosticText,
                recovery: error.recoveryKind == .retry ? .retry : .none
            )
        )
        return true
    }

    @discardableResult
    func retryDiscovery() -> Bool {
        guard case .failed(let failure) = state, failure.isRetryAvailable else {
            return false
        }
        return refresh()
    }

    @discardableResult
    func retrySelection() -> Bool {
        guard case .failed(let failure) = selectionState,
              failure.isRetryAvailable else {
            return false
        }
        if let draftActiveAccountID {
            guard let account = accounts.first(where: { $0.id == draftActiveAccountID }), account.isSelectable else {
                return false
            }
        }

        generation += 1
        let activeGeneration = generation
        selectionState = .saving(generation: activeGeneration)
        if let onSelect {
            onSelect(draftActiveAccountID, activeGeneration)
        } else {
            confirmedActiveAccountID = draftActiveAccountID
            selectionState = .idle
        }
        return true
    }

    func clear() {
        generation += 1
        state = .empty
        confirmedActiveAccountID = nil
        draftActiveAccountID = nil
        selectionState = .idle
    }

    private static func failure(
        key: String,
        diagnostic: String?,
        recovery: PrismInstanceDetailsRecoveryAction
    ) -> PrismAccountFailure {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return PrismAccountFailure(
            localizationKey: normalizedKey.isEmpty ? "accounts.operation.failed" : normalizedKey,
            diagnosticText: diagnostic,
            recoveryAction: recovery
        )
    }
}

struct PrismAccountSettingsView: View {
    @ObservedObject var model: PrismAccountModel
    @ObservedObject var authenticationModel: PrismAccountAuthenticationModel
    @ObservedObject var offlineIdentityModel: PrismOfflineLaunchIdentityModel
    let onManageSkins: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.state {
            case .idle, .loading:
                loadingView
            case .empty:
                unavailableView(
                    title: "No Accounts",
                    systemImage: "person.crop.circle",
                    description: "No account snapshots are available for this launcher.",
                    actionTitle: "Refresh",
                    action: { _ = model.refresh() },
                    actionEnabled: true
                )
            case .failed(let failure):
                unavailableView(
                    title: "Accounts Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: failure.diagnosticText ?? failure.localizationKey,
                    actionTitle: "Retry",
                    action: { _ = model.retryDiscovery() },
                    actionEnabled: failure.isRetryAvailable
                )
            case .cancelled:
                unavailableView(
                    title: "Account Loading Cancelled",
                    systemImage: "pause.circle",
                    description: "Account loading was cancelled before a result was confirmed.",
                    actionTitle: "Refresh",
                    action: { _ = model.refresh() },
                    actionEnabled: true
                )
            case .content:
                contentView
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300)
        .accessibilityIdentifier("prism.settings.accounts")
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView("Loading account snapshots…")
                .accessibilityIdentifier("prism.settings.accounts.progress")
            Button("Cancel") {
                _ = model.cancelDiscovery()
            }
            .disabled(!model.isLoading)
            .accessibilityIdentifier("prism.settings.accounts.cancel")
        }
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accounts")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    _ = model.refresh()
                }
                .accessibilityIdentifier("prism.settings.accounts.refresh")
            }

            List(selection: Binding<String?>(
                get: { model.draftActiveAccountID },
                set: { newValue in
                    _ = model.select(id: newValue)
                }
            )) {
                ForEach(model.accounts) { account in
                    let statusTitle = account.statusTitle
                    let statusColor: Color = account.isSelectable ? .secondary : .orange
                    HStack(alignment: .top, spacing: 10) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.displayName)
                                Text(account.type.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let diagnosticText = account.diagnosticText {
                                    Text(diagnosticText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        } icon: {
                            Image(systemName: account.state.systemImage)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(statusTitle)
                                .font(.caption)
                                .foregroundStyle(statusColor)
                            if model.draftActiveAccountID == account.id {
                                Text("Active")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .tag(account.id)
                    .disabled(!account.isSelectable || model.isSavingSelection)
                    .help(account.diagnosticText ?? account.accessibilitySummary)
                    .accessibilityIdentifier("prism.settings.accounts.\(account.id)")
                    .accessibilityValue(Text(account.accessibilitySummary))
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 150)

            if let account = model.activeAccount,
               account.type == .microsoft,
               account.state == .online,
               account.ownsMinecraft {
                Button("Manage Skins…", systemImage: "person.crop.square") {
                    onManageSkins?(account.id)
                }
                .help(Text("Manage the selected Microsoft account's Minecraft skin."))
                .accessibilityIdentifier("prism.settings.accounts.manage-skins")
            }

            HStack {
                LabeledContent("Active Account") {
                    Text(model.activeAccount?.displayName ?? "None")
                }
                Spacer()
                Button("No Active Account") {
                    _ = model.select(id: nil)
                }
                .disabled(model.draftActiveAccountID == nil || model.isSavingSelection)
                .accessibilityIdentifier("prism.settings.accounts.clear")
            }

            if let failure = model.selectionFailure {
                HStack {
                    Text(failure.diagnosticText ?? failure.localizationKey)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry Selection") {
                        _ = model.retrySelection()
                    }
                    .disabled(!failure.isRetryAvailable || model.isSavingSelection)
                }
                .accessibilityIdentifier("prism.settings.accounts.selection-error")
            }

            if model.isSavingSelection {
                ProgressView("Confirming active account…")
                    .controlSize(.small)
                    .accessibilityIdentifier("prism.settings.accounts.selection-progress")
            }

            authenticationView
            offlineLaunchIdentityView
        }
    }

    private var authenticationAccount: PrismAccount? {
        model.activeAccount ?? model.accounts.first(where: { $0.type == .microsoft })
    }

    private var authenticationAction: PrismAccountAuthenticationAction {
        authenticationAccount?.state == .online ? .refresh : .login
    }

    private var authenticationView: some View {
        GroupBox("Authentication") {
            VStack(alignment: .leading, spacing: 8) {
                if let account = authenticationAccount {
                    LabeledContent("Account") {
                        Text(account.displayName)
                            .lineLimit(1)
                    }
                    .accessibilityIdentifier("prism.settings.accounts.authentication-account")
                } else {
                    Text("Select a Microsoft account to continue.")
                        .foregroundStyle(.secondary)
                }

                switch authenticationModel.state {
                case .idle:
                    authenticationActionButton
                case .starting:
                    ProgressView("Starting sign-in…")
                        .accessibilityIdentifier("prism.settings.accounts.authentication-progress")
                case .running(let progress):
                    ProgressView(progress.phase.title)
                        .accessibilityValue(Text(progress.localizationKey))
                        .accessibilityIdentifier("prism.settings.accounts.authentication-progress")
                    Text(progress.providerLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if progress.isAwaitingUser, let verificationURL = progress.verificationURL {
                        LabeledContent("Verification") {
                            Text(verificationURL)
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("prism.settings.accounts.authentication-verification")
                        PrismQRCodeContentView(payload: verificationURL)
                        if progress.expiresInSeconds > 0 {
                            Text("Verification instructions expire in \(progress.expiresInSeconds) seconds.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Cancel") {
                        _ = authenticationModel.cancel()
                    }
                    .disabled(!authenticationModel.isCancellable)
                    .accessibilityIdentifier("prism.settings.accounts.authentication-cancel")
                case .succeeded(let account):
                    Label("Sign-in complete", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("prism.settings.accounts.authentication-succeeded")
                    if let account {
                        Text(account.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    authenticationActionButton
                case .failed(let failure):
                    Text(failure.diagnosticText ?? failure.localizationKey)
                        .foregroundStyle(.secondary)
                        .accessibilityValue(Text(failure.localizationKey))
                        .accessibilityIdentifier("prism.settings.accounts.authentication-error")
                    HStack {
                        Button("Retry") {
                            _ = authenticationModel.retry()
                        }
                        .disabled(!authenticationModel.canRetry)
                        .accessibilityIdentifier("prism.settings.accounts.authentication-retry")
                        authenticationActionButton
                    }
                case .cancelled:
                    Text("The sign-in request was cancelled.")
                        .foregroundStyle(.secondary)
                    authenticationActionButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("prism.settings.accounts.authentication")
    }

    private var authenticationActionButton: some View {
        Button(authenticationAction.title) {
            guard let account = authenticationAccount else {
                return
            }
            _ = authenticationModel.start(accountIdentifier: account.id, action: authenticationAction)
        }
        .disabled(authenticationAccount == nil || authenticationModel.isRunning)
        .accessibilityIdentifier("prism.settings.accounts.authenticate")
    }

    private var offlineAccount: PrismAccount? {
        model.accounts.first(where: { $0.type == .offline })
    }

    private var offlineLaunchIdentityView: some View {
        GroupBox("Offline Launch Identity") {
            if let account = offlineAccount {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Account") {
                        Text(account.displayName)
                            .lineLimit(1)
                    }
                    .accessibilityIdentifier("prism.settings.accounts.offline-identity-account")

                    switch offlineIdentityModel.state {
                    case .idle:
                        Text("Choose the player name used by fixture-only offline or demo launches.")
                            .foregroundStyle(.secondary)
                        Button("Load Saved Name") {
                            _ = offlineIdentityModel.load(
                                mode: .offline,
                                accountIdentifier: account.id,
                                fallbackName: "Player"
                            )
                        }
                        .accessibilityIdentifier("prism.settings.accounts.offline-identity-load")
                    case .loading:
                        ProgressView("Loading saved name…")
                            .accessibilityIdentifier("prism.settings.accounts.offline-identity-progress")
                        Button("Cancel") {
                            _ = offlineIdentityModel.cancel()
                        }
                        .accessibilityIdentifier("prism.settings.accounts.offline-identity-cancel")
                    case .editing:
                        offlineIdentityEditor
                    case .saving:
                        ProgressView("Confirming player name…")
                            .accessibilityIdentifier("prism.settings.accounts.offline-identity-progress")
                        Button("Cancel") {
                            _ = offlineIdentityModel.cancel()
                        }
                        .accessibilityIdentifier("prism.settings.accounts.offline-identity-cancel")
                    case .succeeded(let identity):
                        Label("Player name confirmed", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("prism.settings.accounts.offline-identity-succeeded")
                        Text(identity.name)
                            .font(.caption)
                            .accessibilityValue(Text(identity.mode.title))
                        Button("Edit") {
                            _ = offlineIdentityModel.beginEditing()
                        }
                        .accessibilityIdentifier("prism.settings.accounts.offline-identity-edit")
                    case .failed(let failure, _, _, _):
                        Text(failure.diagnosticText ?? failure.localizationKey)
                            .foregroundStyle(.secondary)
                            .accessibilityValue(Text(failure.localizationKey))
                            .accessibilityIdentifier("prism.settings.accounts.offline-identity-error")
                        HStack {
                            Button("Retry") {
                                _ = offlineIdentityModel.retry()
                            }
                            .disabled(!failure.isRetryAvailable)
                            .accessibilityIdentifier("prism.settings.accounts.offline-identity-retry")
                            Button("Edit") {
                                _ = offlineIdentityModel.beginEditing()
                            }
                            .disabled(offlineIdentityModel.confirmedIdentity == nil)
                            .accessibilityIdentifier("prism.settings.accounts.offline-identity-edit")
                        }
                    case .cancelled:
                        Text("The offline player-name request was cancelled.")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Load Again") {
                                _ = offlineIdentityModel.load(
                                    mode: .offline,
                                    accountIdentifier: account.id,
                                    fallbackName: "Player"
                                )
                            }
                            .accessibilityIdentifier("prism.settings.accounts.offline-identity-load")
                            Button("Edit") {
                                _ = offlineIdentityModel.beginEditing()
                            }
                            .disabled(offlineIdentityModel.confirmedIdentity == nil)
                            .accessibilityIdentifier("prism.settings.accounts.offline-identity-edit")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView {
                    Label("No Offline Account", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("An offline account snapshot is required before choosing a player name.")
                }
                .accessibilityIdentifier("prism.settings.accounts.offline-identity-unavailable")
            }
        }
        .accessibilityIdentifier("prism.settings.accounts.offline-identity")
    }

    private var offlineIdentityEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "Player Name",
                text: Binding(
                    get: { offlineIdentityModel.draftName },
                    set: { _ = offlineIdentityModel.updateDraftName($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .disabled(offlineIdentityModel.isSaving)
            .accessibilityIdentifier("prism.settings.accounts.offline-identity-name")

            Toggle(
                "Allow invalid names",
                isOn: Binding(
                    get: { offlineIdentityModel.allowInvalidNames },
                    set: { _ = offlineIdentityModel.updateAllowInvalidNames($0) }
                )
            )
            .disabled(offlineIdentityModel.isSaving)
            .accessibilityIdentifier("prism.settings.accounts.offline-identity-allow-invalid")

            Text(PrismOfflineLaunchIdentityValidation.legacyRuleDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("prism.settings.accounts.offline-identity-rule")
            if !offlineIdentityModel.draftName.isEmpty && !offlineIdentityModel.nameIsValid
                && !offlineIdentityModel.allowInvalidNames {
                Text("This name is not valid unless the warning override is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("prism.settings.accounts.offline-identity-validation")
            }

            HStack {
                Button("Save") {
                    _ = offlineIdentityModel.save()
                }
                .disabled(!offlineIdentityModel.canSave)
                .accessibilityIdentifier("prism.settings.accounts.offline-identity-save")
                Button("Cancel") {
                    _ = offlineIdentityModel.cancel()
                }
                .disabled(offlineIdentityModel.isSaving)
                .accessibilityIdentifier("prism.settings.accounts.offline-identity-cancel")
            }
        }
    }

    private func unavailableView(
        title: String,
        systemImage: String,
        description: String,
        actionTitle: String,
        action: @escaping () -> Void,
        actionEnabled: Bool
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            Button(actionTitle, action: action)
                .disabled(!actionEnabled)
        }
    }
}
