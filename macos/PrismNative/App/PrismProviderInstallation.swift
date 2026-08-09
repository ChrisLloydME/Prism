import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum PrismProviderInstallKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case modrinth
    case curseForgeFlame
    case ftb
    case legacyFTB
    case ftbImport
    case atLauncher
    case technicZip
    case technicSolder
    case customArchive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .modrinth: return "Modrinth"
        case .curseForgeFlame: return "CurseForge / Flame"
        case .ftb: return "FTB"
        case .legacyFTB: return "Legacy FTB"
        case .ftbImport: return "FTB Import"
        case .atLauncher: return "ATLauncher"
        case .technicZip: return "Technic Archive"
        case .technicSolder: return "Technic Solder"
        case .customArchive: return "Custom Archive"
        }
    }

    var bridgeValue: PRProviderInstallKind {
        switch self {
        case .modrinth: return .modrinth
        case .curseForgeFlame: return .curseForgeFlame
        case .ftb: return .FTB
        case .legacyFTB: return .legacyFTB
        case .ftbImport: return .ftbImport
        case .atLauncher: return .atLauncher
        case .technicZip: return .technicZip
        case .technicSolder: return .technicSolder
        case .customArchive: return .customArchive
        }
    }
}

enum PrismProviderInstallRollbackOutcome: String, Equatable, Sendable {
    case notRequired
    case applied
    case failed

    init(bridgeValue: PRProviderInstallRollbackOutcome) {
        switch bridgeValue {
        case .notRequired: self = .notRequired
        case .applied: self = .applied
        case .failed: self = .failed
        @unknown default: self = .failed
        }
    }

    var displayText: String {
        switch self {
        case .notRequired: return "No rollback was required."
        case .applied: return "Partial installation work was rolled back."
        case .failed: return "Rollback could not be completed."
        }
    }
}

struct PrismProviderInstallationDraft: Equatable, Sendable {
    var kind: PrismProviderInstallKind
    var packIdentifier: String
    var versionIdentifier: String
    var sourceURL: URL?
    var name: String
    var groupID: String
    var iconKey: String

    var validationMessage: String? {
        if packIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a provider pack identifier."
        }
        if versionIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose a provider pack version."
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter an instance name."
        }
        if iconKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose an instance icon."
        }

        let requiresLocalSource = kind == .customArchive || kind == .ftbImport
        if requiresLocalSource {
            guard let sourceURL, sourceURL.isFileURL, !sourceURL.path.isEmpty else {
                return kind == .ftbImport
                    ? "Choose a local FTB App import directory."
                    : "Choose a local custom pack archive."
            }
        } else if sourceURL != nil {
            return "Only local provider installations may carry a source."
        }
        return nil
    }

    var normalized: Self {
        Self(
            kind: kind,
            packIdentifier: packIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            versionIdentifier: versionIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURL: sourceURL?.standardizedFileURL,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            groupID: groupID.trimmingCharacters(in: .whitespacesAndNewlines),
            iconKey: iconKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct PrismProviderInstallationFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let retryable: Bool
    let rollbackOutcome: PrismProviderInstallRollbackOutcome

    var isRetryAvailable: Bool { retryable }
}

enum PrismProviderInstallationState: Equatable, Sendable {
    case editing
    case installing(progress: PrismTaskPresentation?)
    case succeeded(PrismInstanceRow)
    case cancelled
    case failed(PrismProviderInstallationFailure)
}

@MainActor
final class PrismProviderInstallationModel: ObservableObject {
    @Published var draft: PrismProviderInstallationDraft
    @Published private(set) var state: PrismProviderInstallationState = .editing

    let kinds: [PrismProviderInstallKind]
    let icons: [String]

    private let onInstall: ((PRProviderInstallRequest, Int) -> Void)?
    private let onCancel: (() -> Void)?
    private var generation = 0

    init(
        kinds: [PrismProviderInstallKind] = PrismProviderInstallKind.allCases,
        icons: [String] = ["default", "grass", "stone"],
        initialDraft: PrismProviderInstallationDraft? = nil,
        onInstall: ((PRProviderInstallRequest, Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        let uniqueKinds = Self.unique(kinds)
        let normalizedKinds = uniqueKinds.isEmpty ? [.modrinth] : uniqueKinds
        var seenIcons = Set<String>()
        let uniqueIcons = icons.compactMap { icon -> String? in
            let normalized = icon.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seenIcons.insert(normalized).inserted else { return nil }
            return normalized
        }
        let normalizedIcons = uniqueIcons.isEmpty ? ["default"] : uniqueIcons

        self.kinds = normalizedKinds
        self.icons = normalizedIcons
        self.draft = initialDraft ?? PrismProviderInstallationDraft(
            kind: normalizedKinds[0],
            packIdentifier: "",
            versionIdentifier: "",
            sourceURL: nil,
            name: "",
            groupID: "",
            iconKey: normalizedIcons[0]
        )
        self.onInstall = onInstall
        self.onCancel = onCancel
    }

    var validationMessage: String? { draft.normalized.validationMessage }
    var canInstall: Bool { validationMessage == nil && !isInstalling }
    var isInstalling: Bool {
        if case .installing = state { return true }
        return false
    }
    var progress: PrismTaskPresentation? {
        guard case .installing(let progress) = state else { return nil }
        return progress
    }
    var failure: PrismProviderInstallationFailure? {
        guard case .failed(let failure) = state else { return nil }
        return failure
    }
    var installedInstance: PrismInstanceRow? {
        guard case .succeeded(let instance) = state else { return nil }
        return instance
    }

    func setKind(_ kind: PrismProviderInstallKind) {
        guard kinds.contains(kind) else { return }
        draft.kind = kind
        if kind != .customArchive && kind != .ftbImport {
            draft.sourceURL = nil
        }
    }

    func setSourceURL(_ url: URL?) {
        guard let url, url.isFileURL, !url.path.isEmpty else {
            draft.sourceURL = nil
            return
        }
        draft.sourceURL = url.standardizedFileURL
    }

    func setIcon(_ iconKey: String) {
        guard icons.contains(iconKey) else { return }
        draft.iconKey = iconKey
    }

    func makeBridgeRequest() -> PRProviderInstallRequest? {
        let normalized = draft.normalized
        guard normalized.validationMessage == nil else { return nil }
        return PRProviderInstallRequest(
            kind: normalized.kind.bridgeValue,
            packIdentifier: normalized.packIdentifier,
            versionIdentifier: normalized.versionIdentifier,
            sourceURL: (normalized.kind == .customArchive || normalized.kind == .ftbImport)
                ? normalized.sourceURL
                : nil,
            name: normalized.name,
            groupID: normalized.groupID.isEmpty ? nil : normalized.groupID,
            iconKey: normalized.iconKey
        )
    }

    @discardableResult
    func startInstall() -> Bool {
        guard let request = makeBridgeRequest(), !isInstalling else { return false }
        generation += 1
        let activeGeneration = generation
        draft = draft.normalized
        state = .installing(progress: nil)
        onInstall?(request, activeGeneration)
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard isInstalling else { return false }
        generation += 1
        onCancel?()
        state = .cancelled
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard let failure, failure.isRetryAvailable else { return false }
        state = .editing
        return startInstall()
    }

    @discardableResult
    func apply(progress bridgeProgress: PRTaskStatus, generation resultGeneration: Int? = nil) -> Bool {
        guard case .installing = state,
              (resultGeneration ?? generation) == generation,
              let progress = PrismTaskPresentation(bridgeStatus: bridgeProgress) else {
            return false
        }
        state = .installing(progress: progress)
        return true
    }

    @discardableResult
    func apply(result bridgeResult: PRProviderInstallResult, generation resultGeneration: Int? = nil) -> Bool {
        guard case .installing = state,
              (resultGeneration ?? generation) == generation,
              let outcome = PrismProviderInstallOutcome(bridgeValue: bridgeResult.outcome),
              bridgeResult.kind == draft.kind.bridgeValue,
              bridgeResult.packIdentifier == draft.packIdentifier,
              bridgeResult.versionIdentifier == draft.versionIdentifier else {
            return false
        }

        let localizationKey = bridgeResult.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localizationKey.isEmpty else { return false }
        switch outcome {
        case .succeeded:
            guard let bridgeInstance = bridgeResult.instance,
                  let instance = PrismInstanceRow(
                      id: bridgeInstance.identifier,
                      name: bridgeInstance.name,
                      group: bridgeInstance.groupID
                  ) else {
                state = .failed(
                    PrismProviderInstallationFailure(
                        localizationKey: "providers.install.invalidResult",
                        diagnosticText: nil,
                        retryable: true,
                        rollbackOutcome: .failed
                    )
                )
                return false
            }
            state = .succeeded(instance)
        case .failed, .rejected:
            state = .failed(
                PrismProviderInstallationFailure(
                    localizationKey: localizationKey,
                    diagnosticText: bridgeResult.diagnosticText,
                    retryable: bridgeResult.retryable,
                    rollbackOutcome: PrismProviderInstallRollbackOutcome(bridgeValue: bridgeResult.rollbackOutcome)
                )
            )
        case .cancelled:
            state = .cancelled
        }
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, generation resultGeneration: Int? = nil) -> Bool {
        guard case .installing = state,
              (resultGeneration ?? generation) == generation else {
            return false
        }
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localizationKey.isEmpty else { return false }
        state = .failed(
            PrismProviderInstallationFailure(
                localizationKey: localizationKey,
                diagnosticText: error.diagnosticText,
                retryable: error.recoveryKind == .retry,
                rollbackOutcome: error.partialChangesRolledBack ? .applied : .notRequired
            )
        )
        return true
    }

    func reset() {
        generation += 1
        state = .editing
    }

    private static func unique(_ values: [PrismProviderInstallKind]) -> [PrismProviderInstallKind] {
        var seen = Set<PrismProviderInstallKind>()
        return values.filter { seen.insert($0).inserted }
    }
}

enum PrismProviderInstallOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
    case rejected

    init?(bridgeValue: PRProviderInstallOutcome) {
        switch bridgeValue {
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        case .rejected: self = .rejected
        @unknown default: return nil
        }
    }
}

@MainActor
struct PrismProviderInstallationView: View {
    @ObservedObject var model: PrismProviderInstallationModel
    let onFinished: (() -> Void)?
    @State private var isFileImporterPresented = false

    init(model: PrismProviderInstallationModel, onFinished: (() -> Void)? = nil) {
        self.model = model
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            switch model.state {
            case .editing:
                editingForm
            case .installing(let progress):
                installingView(progress: progress)
            case .succeeded(let instance):
                ContentUnavailableView {
                    Label("Instance Installed", systemImage: "checkmark.circle")
                } description: {
                    Text(instance.name)
                } actions: {
                    Button("Done") { onFinished?() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("provider-install.done")
                }
            case .cancelled:
                ContentUnavailableView {
                    Label("Installation Cancelled", systemImage: "pause.circle")
                } description: {
                    Text("The instance was not committed.")
                } actions: {
                    Button("Start Again") { model.reset() }
                        .accessibilityIdentifier("provider-install.start-again")
                }
            case .failed(let failure):
                ContentUnavailableView {
                    Label("Unable to Install Provider Pack", systemImage: "exclamationmark.triangle")
                } description: {
                    VStack(spacing: 6) {
                        Text(LocalizedStringKey(failure.localizationKey))
                        Text(failure.rollbackOutcome.displayText)
                            .foregroundStyle(.secondary)
                    }
                } actions: {
                    if failure.isRetryAvailable {
                        Button("Retry") { _ = model.retry() }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("provider-install.retry")
                    }
                    Button("Edit", role: .cancel) { model.reset() }
                        .accessibilityIdentifier("provider-install.edit")
                }
            }
        }
        .frame(minWidth: 440, minHeight: 360)
        .accessibilityIdentifier("provider-install.surface")
    }

    private var editingForm: some View {
        Form {
            Section("Pack") {
                Picker(
                    "Provider Task",
                    selection: Binding(get: { model.draft.kind }, set: { model.setKind($0) })
                ) {
                    ForEach(model.kinds) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .accessibilityIdentifier("provider-install.kind")

                TextField(
                    "Pack Identifier",
                    text: Binding(get: { model.draft.packIdentifier }, set: { model.draft.packIdentifier = $0 })
                )
                .accessibilityIdentifier("provider-install.pack-id")

                TextField(
                    "Version Identifier",
                    text: Binding(get: { model.draft.versionIdentifier }, set: { model.draft.versionIdentifier = $0 })
                )
                .accessibilityIdentifier("provider-install.version-id")

                if model.draft.kind == .customArchive || model.draft.kind == .ftbImport {
                    Group {
                        if model.draft.kind == .ftbImport {
                            Button("Choose FTB Folder…") { isFileImporterPresented = true }
                        } else {
                            Button("Choose Archive…") { isFileImporterPresented = true }
                        }
                    }
                    .accessibilityIdentifier("provider-install.choose-archive")
                    if let sourceURL = model.draft.sourceURL {
                        Text(sourceURL.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("provider-install.selected-archive")
                    }
                }
            }

            Section("Instance") {
                TextField("Name", text: Binding(get: { model.draft.name }, set: { model.draft.name = $0 }))
                    .accessibilityIdentifier("provider-install.name")
                TextField("Group", text: Binding(get: { model.draft.groupID }, set: { model.draft.groupID = $0 }))
                    .accessibilityIdentifier("provider-install.group")
                Picker("Icon", selection: Binding(get: { model.draft.iconKey }, set: { model.setIcon($0) })) {
                    ForEach(model.icons, id: \.self) { icon in
                        Text(icon.capitalized).tag(icon)
                    }
                }
                .accessibilityIdentifier("provider-install.icon")
            }

            if let validationMessage = model.validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("provider-install.validation")
            }

            HStack {
                Spacer()
                Button("Install") { _ = model.startInstall() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canInstall)
                    .accessibilityIdentifier("provider-install.start")
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: model.draft.kind == .ftbImport ? [.folder] : [.zip, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                model.setSourceURL(urls.first)
            }
        }
    }

    @ViewBuilder
    private func installingView(progress: PrismTaskPresentation?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let progress {
                Label(progress.title, systemImage: progress.state.systemImage)
                    .accessibilityValue(Text(LocalizedStringKey(progress.state.accessibilityValueKey)))
                    .accessibilityIdentifier("provider-install.task")
                if let fraction = progress.progress.fraction {
                    ProgressView(value: fraction)
                        .accessibilityIdentifier("provider-install.progress")
                } else {
                    ProgressView()
                        .accessibilityIdentifier("provider-install.progress")
                }
            } else {
                ProgressView("Installing Provider Pack")
                    .accessibilityIdentifier("provider-install.progress")
            }
            Button("Cancel", role: .cancel) { _ = model.cancel() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("provider-install.cancel")
        }
        .padding()
    }
}

#Preview {
    PrismProviderInstallationView(model: PrismProviderInstallationModel())
}
