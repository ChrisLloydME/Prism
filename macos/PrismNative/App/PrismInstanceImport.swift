import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum PrismInstanceImportSource: String, CaseIterable, Identifiable, Sendable {
    case localFile
    case remoteURL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localFile: return "Local File"
        case .remoteURL: return "Download URL"
        }
    }
}

struct PrismInstanceImportDraft: Equatable, Sendable {
    var source: PrismInstanceImportSource
    var localFileURL: URL?
    var remoteURLText: String
    var name: String
    var groupID: String
    var iconKey: String

    var validationMessage: String? {
        switch source {
        case .localFile:
            guard let localFileURL, localFileURL.isFileURL, localFileURL.path.isEmpty == false else {
                return "Choose an instance archive."
            }
        case .remoteURL:
            let value = remoteURLText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  url.host?.isEmpty == false else {
                return "Enter an HTTP or HTTPS download URL."
            }
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter an instance name."
        }
        if iconKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose an instance icon."
        }
        return nil
    }

    var normalized: Self {
        Self(
            source: source,
            localFileURL: localFileURL?.standardizedFileURL,
            remoteURLText: remoteURLText.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            groupID: groupID.trimmingCharacters(in: .whitespacesAndNewlines),
            iconKey: iconKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var sourceURL: URL? {
        let value = normalized
        switch value.source {
        case .localFile:
            guard let url = value.localFileURL, url.isFileURL, !url.path.isEmpty else { return nil }
            return url
        case .remoteURL:
            return URL(string: value.remoteURLText)
        }
    }
}

struct PrismInstanceImportFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let retryable: Bool
    let partialChangesRolledBack: Bool

    var isRetryAvailable: Bool { retryable }
}

enum PrismInstanceImportState: Equatable, Sendable {
    case editing
    case importing(progress: PrismTaskPresentation?)
    case succeeded(PrismInstanceRow)
    case cancelled
    case failed(PrismInstanceImportFailure)
}

@MainActor
final class PrismInstanceImportModel: ObservableObject {
    @Published var draft: PrismInstanceImportDraft
    @Published private(set) var state: PrismInstanceImportState = .editing

    let icons: [String]

    private let onImport: ((PRInstanceImportRequest, Int) -> Void)?
    private let onCancel: (() -> Void)?
    private var generation = 0
    private var filePanelGeneration = 0

    init(
        icons: [String] = ["default", "grass", "stone"],
        initialDraft: PrismInstanceImportDraft? = nil,
        onImport: ((PRInstanceImportRequest, Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        var seenIcons = Set<String>()
        let uniqueIcons = icons.compactMap { icon -> String? in
            let normalized = icon.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seenIcons.insert(normalized).inserted else { return nil }
            return normalized
        }
        let normalizedIcons = uniqueIcons.isEmpty ? ["default"] : uniqueIcons
        self.icons = normalizedIcons
        self.draft = initialDraft ?? PrismInstanceImportDraft(
            source: .localFile,
            localFileURL: nil,
            remoteURLText: "",
            name: "Imported Instance",
            groupID: "",
            iconKey: normalizedIcons.first ?? "default"
        )
        self.onImport = onImport
        self.onCancel = onCancel
    }

    var validationMessage: String? { draft.normalized.validationMessage }
    var canImport: Bool { validationMessage == nil && !isImporting }
    var isImporting: Bool {
        if case .importing = state { return true }
        return false
    }
    var progress: PrismTaskPresentation? {
        guard case .importing(let progress) = state else { return nil }
        return progress
    }
    var failure: PrismInstanceImportFailure? {
        guard case .failed(let failure) = state else { return nil }
        return failure
    }
    var importedInstance: PrismInstanceRow? {
        guard case .succeeded(let instance) = state else { return nil }
        return instance
    }

    func setSource(_ source: PrismInstanceImportSource) {
        filePanelGeneration += 1
        draft.source = source
    }

    func setLocalFileURL(_ url: URL?) {
        filePanelGeneration += 1
        guard let url, url.isFileURL, !url.path.isEmpty else {
            draft.localFileURL = nil
            return
        }
        draft.localFileURL = url.standardizedFileURL
    }

    func beginLocalFilePanel() -> Int? {
        guard case .editing = state, draft.source == .localFile else { return nil }
        filePanelGeneration += 1
        return filePanelGeneration
    }

    @discardableResult
    func applyLocalFilePanelResult(_ url: URL?, token: Int) -> Bool {
        guard case .editing = state, token == filePanelGeneration else { return false }
        filePanelGeneration += 1
        guard let url else { return true }
        guard url.isFileURL, !url.path.isEmpty else { return false }
        draft.localFileURL = url.standardizedFileURL
        return true
    }

    func setIcon(_ iconKey: String) {
        guard icons.contains(iconKey) else { return }
        draft.iconKey = iconKey
    }

    func makeBridgeRequest() -> PRInstanceImportRequest? {
        let normalized = draft.normalized
        guard normalized.validationMessage == nil, let sourceURL = normalized.sourceURL else { return nil }
        let sourceKind: PRInstanceImportSourceKind = normalized.source == .localFile ? .localFile : .remoteURL
        return PRInstanceImportRequest(
            sourceURL: sourceURL,
            sourceKind: sourceKind,
            name: normalized.name,
            groupID: normalized.groupID.isEmpty ? nil : normalized.groupID,
            iconKey: normalized.iconKey
        )
    }

    @discardableResult
    func startImport() -> Bool {
        guard let request = makeBridgeRequest(), !isImporting else { return false }
        filePanelGeneration += 1
        generation += 1
        let activeGeneration = generation
        draft = draft.normalized
        state = .importing(progress: nil)
        onImport?(request, activeGeneration)
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard isImporting else { return false }
        filePanelGeneration += 1
        generation += 1
        onCancel?()
        state = .cancelled
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard let failure, failure.isRetryAvailable else { return false }
        state = .editing
        return startImport()
    }

    @discardableResult
    func apply(progress bridgeProgress: PRTaskStatus, generation resultGeneration: Int? = nil) -> Bool {
        guard case .importing = state,
              (resultGeneration ?? generation) == generation,
              let progress = PrismTaskPresentation(bridgeStatus: bridgeProgress) else {
            return false
        }
        state = .importing(progress: progress)
        return true
    }

    @discardableResult
    func apply(result bridgeResult: PRInstanceImportResult, generation resultGeneration: Int? = nil) -> Bool {
        guard case .importing = state,
              (resultGeneration ?? generation) == generation,
              let outcome = PrismInstanceImportOutcome(bridgeOutcome: bridgeResult.outcome) else {
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
                    PrismInstanceImportFailure(
                        localizationKey: "instances.import.invalidResult",
                        diagnosticText: nil,
                        retryable: true,
                        partialChangesRolledBack: bridgeResult.partialChangesRolledBack
                    )
                )
                return false
            }
            state = .succeeded(instance)
        case .failed, .rejected:
            state = .failed(
                PrismInstanceImportFailure(
                    localizationKey: localizationKey,
                    diagnosticText: bridgeResult.diagnosticText,
                    retryable: bridgeResult.retryable,
                    partialChangesRolledBack: bridgeResult.partialChangesRolledBack
                )
            )
        case .cancelled:
            state = .cancelled
        }
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, generation resultGeneration: Int? = nil) -> Bool {
        guard case .importing = state,
              (resultGeneration ?? generation) == generation else {
            return false
        }
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localizationKey.isEmpty else { return false }
        state = .failed(
            PrismInstanceImportFailure(
                localizationKey: localizationKey,
                diagnosticText: error.diagnosticText,
                retryable: error.recoveryKind == .retry,
                partialChangesRolledBack: error.partialChangesRolledBack
            )
        )
        return true
    }

    func reset() {
        filePanelGeneration += 1
        generation += 1
        state = .editing
    }
}

enum PrismInstanceImportOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
    case rejected

    init?(bridgeOutcome: PRInstanceImportOutcome) {
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
struct PrismInstanceImportView: View {
    @ObservedObject var model: PrismInstanceImportModel
    let onFinished: (() -> Void)?

    init(model: PrismInstanceImportModel, onFinished: (() -> Void)? = nil) {
        self.model = model
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            switch model.state {
            case .editing:
                editingForm
            case .importing(let progress):
                importingView(progress: progress)
            case .succeeded(let instance):
                ContentUnavailableView {
                    Label("Instance Imported", systemImage: "checkmark.circle")
                } description: {
                    Text(instance.name)
                } actions: {
                    Button("Done") { onFinished?() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("prism.instance-import.done")
                }
            case .cancelled:
                ContentUnavailableView {
                    Label("Import Cancelled", systemImage: "pause.circle")
                } description: {
                    Text("The instance was not committed.")
                } actions: {
                    Button("Start Again") { model.reset() }
                        .accessibilityIdentifier("prism.instance-import.start-again")
                }
            case .failed(let failure):
                ContentUnavailableView {
                    Label("Unable to Import Instance", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(LocalizedStringKey(failure.localizationKey))
                } actions: {
                    if failure.isRetryAvailable {
                        Button("Retry") { _ = model.retry() }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("prism.instance-import.retry")
                    }
                    Button("Edit", role: .cancel) { model.reset() }
                        .accessibilityIdentifier("prism.instance-import.edit")
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .accessibilityIdentifier("prism.instance-import")
    }

    private var editingForm: some View {
        Form {
            Section("Source") {
                Picker(
                    "Import From",
                    selection: Binding(
                        get: { model.draft.source },
                        set: { model.setSource($0) }
                    )
                ) {
                    ForEach(PrismInstanceImportSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .accessibilityIdentifier("prism.instance-import.source")

                switch model.draft.source {
                case .localFile:
                    Button("Choose Archive…") {
                        guard let token = model.beginLocalFilePanel() else { return }
                        PrismSystemOpenPanel.present(
                            defaultURL: model.draft.localFileURL,
                            allowedContentTypes: [.zip, .data],
                            canChooseFiles: true,
                            canChooseDirectories: false
                        ) { url in
                            _ = model.applyLocalFilePanelResult(url, token: token)
                        }
                    }
                        .accessibilityIdentifier("prism.instance-import.choose-file")
                    if let url = model.draft.localFileURL {
                        Text(url.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("prism.instance-import.selected-file")
                    }
                case .remoteURL:
                    TextField(
                        "Download URL",
                        text: Binding(get: { model.draft.remoteURLText }, set: { model.draft.remoteURLText = $0 })
                    )
                    .textContentType(.URL)
                    .accessibilityIdentifier("prism.instance-import.url")
                }
            }

            Section("Instance") {
                TextField("Name", text: Binding(get: { model.draft.name }, set: { model.draft.name = $0 }))
                    .accessibilityIdentifier("prism.instance-import.name")
                TextField("Group", text: Binding(get: { model.draft.groupID }, set: { model.draft.groupID = $0 }))
                    .accessibilityIdentifier("prism.instance-import.group")
                Picker(
                    "Icon",
                    selection: Binding(get: { model.draft.iconKey }, set: { model.setIcon($0) })
                ) {
                    ForEach(model.icons, id: \.self) { icon in
                        Text(icon.capitalized).tag(icon)
                    }
                }
                .accessibilityIdentifier("prism.instance-import.icon")
            }

            if let validationMessage = model.validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("prism.instance-import.validation")
            }

            HStack {
                Spacer()
                Button("Import") { _ = model.startImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canImport)
                    .accessibilityIdentifier("prism.instance-import.start")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func importingView(progress: PrismTaskPresentation?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let progress {
                Label(progress.title, systemImage: progress.state.systemImage)
                    .accessibilityValue(Text(LocalizedStringKey(progress.state.accessibilityValueKey)))
                    .accessibilityIdentifier("prism.instance-import.task")
                if let fraction = progress.progress.fraction {
                    ProgressView(value: fraction)
                        .accessibilityIdentifier("prism.instance-import.progress")
                } else {
                    ProgressView()
                        .accessibilityIdentifier("prism.instance-import.progress")
                }
            } else {
                ProgressView("Importing Instance")
                    .accessibilityIdentifier("prism.instance-import.progress")
            }
            Button("Cancel", role: .cancel) { _ = model.cancel() }
                .accessibilityIdentifier("prism.instance-import.cancel")
        }
        .padding()
    }
}

#Preview {
    PrismInstanceImportView(model: PrismInstanceImportModel())
}
