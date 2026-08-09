import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PrismInstanceCopyOptions: Equatable, Sendable {
    var copySaves = true
    var keepPlaytime = true
    var copyGameOptions = true
    var copyResourcePacks = true
    var copyShaderPacks = true
    var copyServers = true
    var copyMods = true
    var copyScreenshots = true
    var useSymbolicLinks = false
    var linkRecursively = false
    var useHardLinks = false
    var dontLinkSaves = false
    var useClone = false

    var validationMessage: String? {
        let usesLinks = useSymbolicLinks || useHardLinks
        if useClone && usesLinks {
            return "Clone cannot be combined with symbolic or hard links."
        }
        if useHardLinks && !linkRecursively {
            return "Hard links require recursive linking."
        }
        if dontLinkSaves && (!usesLinks || !copySaves) {
            return "Do not link saves requires linked save data."
        }
        return nil
    }
}

struct PrismInstanceCopyDraft: Equatable, Sendable {
    var sourceInstanceIdentifier: String
    var name: String
    var groupID: String
    var iconKey: String
    var options: PrismInstanceCopyOptions

    var validationMessage: String? {
        if sourceInstanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose a source instance."
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter an instance name."
        }
        if iconKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose an instance icon."
        }
        return options.validationMessage
    }

    var normalized: Self {
        Self(
            sourceInstanceIdentifier: sourceInstanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            groupID: groupID.trimmingCharacters(in: .whitespacesAndNewlines),
            iconKey: iconKey.trimmingCharacters(in: .whitespacesAndNewlines),
            options: options
        )
    }
}

struct PrismInstanceCopyFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let retryable: Bool
    let partialChangesRolledBack: Bool

    var isRetryAvailable: Bool { retryable }
}

enum PrismInstanceCopyState: Equatable, Sendable {
    case editing
    case copying(progress: PrismTaskPresentation?)
    case succeeded(PrismInstanceRow)
    case cancelled
    case failed(PrismInstanceCopyFailure)
}

@MainActor
final class PrismInstanceCopyModel: ObservableObject {
    @Published var draft: PrismInstanceCopyDraft
    @Published private(set) var state: PrismInstanceCopyState = .editing

    let icons: [String]

    private let onCopy: ((PRInstanceCopyRequest, Int) -> Void)?
    private let onCancel: (() -> Void)?
    private var generation = 0

    init(
        sourceInstanceIdentifier: String,
        icons: [String] = ["default", "grass", "stone"],
        initialDraft: PrismInstanceCopyDraft? = nil,
        onCopy: ((PRInstanceCopyRequest, Int) -> Void)? = nil,
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
        self.draft = initialDraft ?? PrismInstanceCopyDraft(
            sourceInstanceIdentifier: sourceInstanceIdentifier,
            name: "Copied Instance",
            groupID: "",
            iconKey: normalizedIcons.first ?? "default",
            options: PrismInstanceCopyOptions()
        )
        self.onCopy = onCopy
        self.onCancel = onCancel
    }

    var validationMessage: String? { draft.normalized.validationMessage }
    var canCopy: Bool { validationMessage == nil && !isCopying }
    var isCopying: Bool {
        if case .copying = state { return true }
        return false
    }
    var progress: PrismTaskPresentation? {
        guard case .copying(let progress) = state else { return nil }
        return progress
    }
    var failure: PrismInstanceCopyFailure? {
        guard case .failed(let failure) = state else { return nil }
        return failure
    }
    var copiedInstance: PrismInstanceRow? {
        guard case .succeeded(let instance) = state else { return nil }
        return instance
    }

    func setIcon(_ iconKey: String) {
        guard icons.contains(iconKey) else { return }
        draft.iconKey = iconKey
    }

    func makeBridgeRequest() -> PRInstanceCopyRequest? {
        let normalized = draft.normalized
        guard normalized.validationMessage == nil else { return nil }
        let options = normalized.options
        return PRInstanceCopyRequest(
            sourceInstanceIdentifier: normalized.sourceInstanceIdentifier,
            name: normalized.name,
            groupID: normalized.groupID.isEmpty ? nil : normalized.groupID,
            iconKey: normalized.iconKey,
            copySaves: options.copySaves,
            keepPlaytime: options.keepPlaytime,
            copyGameOptions: options.copyGameOptions,
            copyResourcePacks: options.copyResourcePacks,
            copyShaderPacks: options.copyShaderPacks,
            copyServers: options.copyServers,
            copyMods: options.copyMods,
            copyScreenshots: options.copyScreenshots,
            useSymbolicLinks: options.useSymbolicLinks,
            linkRecursively: options.linkRecursively,
            useHardLinks: options.useHardLinks,
            dontLinkSaves: options.dontLinkSaves,
            useClone: options.useClone
        )
    }

    @discardableResult
    func startCopy() -> Bool {
        guard let request = makeBridgeRequest(), !isCopying else { return false }
        generation += 1
        let activeGeneration = generation
        draft = draft.normalized
        state = .copying(progress: nil)
        onCopy?(request, activeGeneration)
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard isCopying else { return false }
        generation += 1
        onCancel?()
        state = .cancelled
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard let failure, failure.isRetryAvailable else { return false }
        state = .editing
        return startCopy()
    }

    @discardableResult
    func apply(progress bridgeProgress: PRTaskStatus, generation resultGeneration: Int? = nil) -> Bool {
        guard case .copying = state,
              (resultGeneration ?? generation) == generation,
              let progress = PrismTaskPresentation(bridgeStatus: bridgeProgress) else {
            return false
        }
        state = .copying(progress: progress)
        return true
    }

    @discardableResult
    func apply(result bridgeResult: PRInstanceCopyResult, generation resultGeneration: Int? = nil) -> Bool {
        guard case .copying = state,
              (resultGeneration ?? generation) == generation,
              let outcome = PrismInstanceCopyOutcome(bridgeOutcome: bridgeResult.outcome) else {
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
                    PrismInstanceCopyFailure(
                        localizationKey: "instances.copy.invalidResult",
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
                PrismInstanceCopyFailure(
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
        guard case .copying = state,
              (resultGeneration ?? generation) == generation else {
            return false
        }
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localizationKey.isEmpty else { return false }
        state = .failed(
            PrismInstanceCopyFailure(
                localizationKey: localizationKey,
                diagnosticText: error.diagnosticText,
                retryable: error.recoveryKind == .retry,
                partialChangesRolledBack: error.partialChangesRolledBack
            )
        )
        return true
    }

    func reset() {
        generation += 1
        state = .editing
    }
}

enum PrismInstanceCopyOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
    case rejected

    init?(bridgeOutcome: PRInstanceCopyOutcome) {
        switch bridgeOutcome {
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        case .rejected: self = .rejected
        @unknown default: return nil
        }
    }
}

enum PrismInstanceExportKind: String, CaseIterable, Identifiable, Sendable {
    case zipArchive
    case modList

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zipArchive: return "ZIP Archive"
        case .modList: return "Mod List"
        }
    }
}

enum PrismModListExportFormat: String, CaseIterable, Identifiable, Sendable {
    case html
    case markdown
    case plainText
    case json
    case csv
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .html: return "HTML"
        case .markdown: return "Markdown"
        case .plainText: return "Plain Text"
        case .json: return "JSON"
        case .csv: return "CSV"
        case .custom: return "Custom Template"
        }
    }
}

struct PrismInstanceExportDraft: Equatable, Sendable {
    var sourceInstanceIdentifier: String
    var kind: PrismInstanceExportKind
    var destinationURL: URL?
    var modListFormat: PrismModListExportFormat
    var includeAuthors: Bool
    var includeVersion: Bool
    var includeURL: Bool
    var includeFilename: Bool
    var customTemplate: String

    var validationMessage: String? {
        if sourceInstanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose a source instance."
        }
        guard let destinationURL, destinationURL.isFileURL, destinationURL.path.isEmpty == false,
              destinationURL.path.hasPrefix("/") else {
            return "Choose a destination file."
        }
        switch kind {
        case .zipArchive:
            if includeAuthors || includeVersion || includeURL || includeFilename || !customTemplate.isEmpty {
                return "ZIP exports do not use mod-list options."
            }
        case .modList:
            if modListFormat == .custom {
                if customTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "Enter a custom mod-list template."
                }
            } else if !customTemplate.isEmpty {
                return "Custom text is only used with the custom format."
            }
        }
        return nil
    }

    var normalized: Self {
        Self(
            sourceInstanceIdentifier: sourceInstanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            destinationURL: destinationURL?.standardizedFileURL,
            modListFormat: modListFormat,
            includeAuthors: includeAuthors,
            includeVersion: includeVersion,
            includeURL: includeURL,
            includeFilename: includeFilename,
            customTemplate: customTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct PrismInstanceExportFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let retryable: Bool
    let partialChangesRolledBack: Bool

    var isRetryAvailable: Bool { retryable }
}

enum PrismInstanceExportState: Equatable, Sendable {
    case editing
    case exporting(progress: PrismTaskPresentation?)
    case succeeded(URL)
    case cancelled
    case failed(PrismInstanceExportFailure)
}

@MainActor
final class PrismInstanceExportModel: ObservableObject {
    @Published var draft: PrismInstanceExportDraft
    @Published private(set) var state: PrismInstanceExportState = .editing

    private let instanceName: String
    private let onExport: ((PRInstanceExportRequest, Int) -> Void)?
    private let onCancel: (() -> Void)?
    private var generation = 0

    init(
        sourceInstanceIdentifier: String,
        instanceName: String = "Instance",
        initialDraft: PrismInstanceExportDraft? = nil,
        onExport: ((PRInstanceExportRequest, Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.instanceName = instanceName
        self.draft = initialDraft ?? PrismInstanceExportDraft(
            sourceInstanceIdentifier: sourceInstanceIdentifier,
            kind: .zipArchive,
            destinationURL: nil,
            modListFormat: .html,
            includeAuthors: false,
            includeVersion: false,
            includeURL: false,
            includeFilename: false,
            customTemplate: ""
        )
        self.onExport = onExport
        self.onCancel = onCancel
    }

    var validationMessage: String? { draft.normalized.validationMessage }
    var canExport: Bool { validationMessage == nil && !isExporting }
    var isExporting: Bool {
        if case .exporting = state { return true }
        return false
    }
    var progress: PrismTaskPresentation? {
        guard case .exporting(let progress) = state else { return nil }
        return progress
    }
    var failure: PrismInstanceExportFailure? {
        guard case .failed(let failure) = state else { return nil }
        return failure
    }
    var defaultFilename: String {
        let baseName = instanceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Instance" : instanceName
        switch draft.kind {
        case .zipArchive:
            return baseName + ".zip"
        case .modList:
            let suffix = draft.modListFormat == .html ? "html" : "txt"
            return baseName + "." + suffix
        }
    }

    func setKind(_ kind: PrismInstanceExportKind) {
        draft.kind = kind
        if kind == .zipArchive {
            draft.includeAuthors = false
            draft.includeVersion = false
            draft.includeURL = false
            draft.includeFilename = false
            draft.customTemplate = ""
        }
    }

    func setDestinationURL(_ url: URL?) {
        guard let url, url.isFileURL, !url.path.isEmpty, url.path.hasPrefix("/") else {
            draft.destinationURL = nil
            return
        }
        draft.destinationURL = url.standardizedFileURL
    }

    func makeBridgeRequest() -> PRInstanceExportRequest? {
        let normalized = draft.normalized
        guard normalized.validationMessage == nil, let destinationURL = normalized.destinationURL else { return nil }
        let kind: PRInstanceExportKind = normalized.kind == .zipArchive ? .zipArchive : .modList
        let format: PRModListExportFormat
        switch normalized.modListFormat {
        case .html: format = .HTML
        case .markdown: format = .markdown
        case .plainText: format = .plainText
        case .json: format = .JSON
        case .csv: format = .CSV
        case .custom: format = .custom
        }
        return PRInstanceExportRequest(
            sourceInstanceIdentifier: normalized.sourceInstanceIdentifier,
            destinationURL: destinationURL,
            kind: kind,
            modListFormat: format,
            includeAuthors: normalized.includeAuthors,
            includeVersion: normalized.includeVersion,
            includeURL: normalized.includeURL,
            includeFilename: normalized.includeFilename,
            customTemplate: normalized.customTemplate
        )
    }

    @discardableResult
    func startExport() -> Bool {
        guard let request = makeBridgeRequest(), !isExporting else { return false }
        generation += 1
        let activeGeneration = generation
        draft = draft.normalized
        state = .exporting(progress: nil)
        onExport?(request, activeGeneration)
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard isExporting else { return false }
        generation += 1
        onCancel?()
        state = .cancelled
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard let failure, failure.isRetryAvailable else { return false }
        state = .editing
        return startExport()
    }

    @discardableResult
    func apply(progress bridgeProgress: PRTaskStatus, generation resultGeneration: Int? = nil) -> Bool {
        guard case .exporting = state,
              (resultGeneration ?? generation) == generation,
              let progress = PrismTaskPresentation(bridgeStatus: bridgeProgress) else {
            return false
        }
        state = .exporting(progress: progress)
        return true
    }

    @discardableResult
    func apply(result bridgeResult: PRInstanceExportResult, generation resultGeneration: Int? = nil) -> Bool {
        guard case .exporting = state,
              (resultGeneration ?? generation) == generation,
              let outcome = PrismInstanceExportOutcome(bridgeOutcome: bridgeResult.outcome) else {
            return false
        }
        let localizationKey = bridgeResult.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localizationKey.isEmpty else { return false }
        switch outcome {
        case .succeeded:
            guard let requestedURL = draft.normalized.destinationURL,
                  bridgeResult.destinationURL.standardizedFileURL == requestedURL else {
                state = .failed(
                    PrismInstanceExportFailure(
                        localizationKey: "instances.export.invalidResult",
                        diagnosticText: nil,
                        retryable: true,
                        partialChangesRolledBack: bridgeResult.partialChangesRolledBack
                    )
                )
                return false
            }
            state = .succeeded(bridgeResult.destinationURL.standardizedFileURL)
        case .failed, .rejected:
            state = .failed(
                PrismInstanceExportFailure(
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
        guard case .exporting = state,
              (resultGeneration ?? generation) == generation else {
            return false
        }
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localizationKey.isEmpty else { return false }
        state = .failed(
            PrismInstanceExportFailure(
                localizationKey: localizationKey,
                diagnosticText: error.diagnosticText,
                retryable: error.recoveryKind == .retry,
                partialChangesRolledBack: error.partialChangesRolledBack
            )
        )
        return true
    }

    func reset() {
        generation += 1
        state = .editing
    }
}

enum PrismInstanceExportOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
    case rejected

    init?(bridgeOutcome: PRInstanceExportOutcome) {
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
enum PrismSystemSavePanel {
    static func present(
        defaultFilename: String,
        allowedContentTypes: [UTType],
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFilename
        panel.allowedContentTypes = allowedContentTypes
        panel.canCreateDirectories = false
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }
}

@MainActor
struct PrismInstanceCopyView: View {
    @ObservedObject var model: PrismInstanceCopyModel
    let onFinished: (() -> Void)?

    init(model: PrismInstanceCopyModel, onFinished: (() -> Void)? = nil) {
        self.model = model
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            switch model.state {
            case .editing:
                editingForm
            case .copying(let progress):
                taskView(progress: progress)
            case .succeeded(let instance):
                ContentUnavailableView {
                    Label("Instance Copied", systemImage: "checkmark.circle")
                } description: {
                    Text(instance.name)
                } actions: {
                    Button("Done") { onFinished?() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("prism.instance-copy.done")
                }
            case .cancelled:
                ContentUnavailableView {
                    Label("Copy Cancelled", systemImage: "pause.circle")
                } description: {
                    Text("The new instance was not committed.")
                } actions: {
                    Button("Start Again") { model.reset() }
                        .accessibilityIdentifier("prism.instance-copy.start-again")
                }
            case .failed(let failure):
                ContentUnavailableView {
                    Label("Unable to Copy Instance", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(LocalizedStringKey(failure.localizationKey))
                } actions: {
                    if failure.isRetryAvailable {
                        Button("Retry") { _ = model.retry() }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("prism.instance-copy.retry")
                    }
                    Button("Edit", role: .cancel) { model.reset() }
                        .accessibilityIdentifier("prism.instance-copy.edit")
                }
            }
        }
        .frame(minWidth: 440, minHeight: 420)
        .accessibilityIdentifier("prism.instance-copy")
    }

    private var editingForm: some View {
        Form {
            Section("Instance") {
                Text(model.draft.sourceInstanceIdentifier)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("prism.instance-copy.source")
                TextField("Name", text: Binding(get: { model.draft.name }, set: { model.draft.name = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.name")
                TextField("Group", text: Binding(get: { model.draft.groupID }, set: { model.draft.groupID = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.group")
                Picker("Icon", selection: Binding(get: { model.draft.iconKey }, set: { model.setIcon($0) })) {
                    ForEach(model.icons, id: \.self) { icon in
                        Text(icon.capitalized).tag(icon)
                    }
                }
                .accessibilityIdentifier("prism.instance-copy.icon")
            }

            Section("Content") {
                Toggle("Saves", isOn: Binding(get: { model.draft.options.copySaves }, set: { model.draft.options.copySaves = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.copy-saves")
                Toggle("Keep Playtime", isOn: Binding(get: { model.draft.options.keepPlaytime }, set: { model.draft.options.keepPlaytime = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.keep-playtime")
                Toggle("Game Options", isOn: Binding(get: { model.draft.options.copyGameOptions }, set: { model.draft.options.copyGameOptions = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.copy-options")
                Toggle("Resource Packs", isOn: Binding(get: { model.draft.options.copyResourcePacks }, set: { model.draft.options.copyResourcePacks = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.copy-resource-packs")
                Toggle("Shader Packs", isOn: Binding(get: { model.draft.options.copyShaderPacks }, set: { model.draft.options.copyShaderPacks = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.copy-shader-packs")
                Toggle("Servers", isOn: Binding(get: { model.draft.options.copyServers }, set: { model.draft.options.copyServers = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.copy-servers")
                Toggle("Mods", isOn: Binding(get: { model.draft.options.copyMods }, set: { model.draft.options.copyMods = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.copy-mods")
                Toggle("Screenshots", isOn: Binding(get: { model.draft.options.copyScreenshots }, set: { model.draft.options.copyScreenshots = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.copy-screenshots")
            }

            Section("Advanced") {
                Toggle("Use Symbolic Links", isOn: Binding(get: { model.draft.options.useSymbolicLinks }, set: { model.draft.options.useSymbolicLinks = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.symbolic-links")
                Toggle("Link Recursively", isOn: Binding(get: { model.draft.options.linkRecursively }, set: { model.draft.options.linkRecursively = $0 }))
                    .disabled(!model.draft.options.useSymbolicLinks && !model.draft.options.useHardLinks)
                    .accessibilityIdentifier("prism.instance-copy.recursive-links")
                Toggle("Use Hard Links", isOn: Binding(get: { model.draft.options.useHardLinks }, set: { model.draft.options.useHardLinks = $0 }))
                    .accessibilityIdentifier("prism.instance-copy.hard-links")
                Toggle("Do Not Link Saves", isOn: Binding(get: { model.draft.options.dontLinkSaves }, set: { model.draft.options.dontLinkSaves = $0 }))
                    .disabled((!model.draft.options.useSymbolicLinks && !model.draft.options.useHardLinks) || !model.draft.options.copySaves)
                    .accessibilityIdentifier("prism.instance-copy.dont-link-saves")
                Toggle("Use Clone", isOn: Binding(get: { model.draft.options.useClone }, set: { model.draft.options.useClone = $0 }))
                    .disabled(model.draft.options.useSymbolicLinks || model.draft.options.useHardLinks)
                    .accessibilityIdentifier("prism.instance-copy.clone")
            }

            if let validationMessage = model.validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("prism.instance-copy.validation")
            }

            HStack {
                Spacer()
                Button("Copy") { _ = model.startCopy() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCopy)
                    .accessibilityIdentifier("prism.instance-copy.start")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func taskView(progress: PrismTaskPresentation?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let progress {
                Label(progress.title, systemImage: progress.state.systemImage)
                    .accessibilityValue(Text(LocalizedStringKey(progress.state.accessibilityValueKey)))
                    .accessibilityIdentifier("prism.instance-copy.task")
                if let fraction = progress.progress.fraction {
                    ProgressView(value: fraction)
                        .accessibilityIdentifier("prism.instance-copy.progress")
                } else {
                    ProgressView()
                        .accessibilityIdentifier("prism.instance-copy.progress")
                }
            } else {
                ProgressView("Copying Instance")
                    .accessibilityIdentifier("prism.instance-copy.progress")
            }
            Button("Cancel", role: .cancel) { _ = model.cancel() }
                .accessibilityIdentifier("prism.instance-copy.cancel")
        }
        .padding()
    }
}

@MainActor
struct PrismInstanceExportView: View {
    @ObservedObject var model: PrismInstanceExportModel
    let onFinished: (() -> Void)?

    init(model: PrismInstanceExportModel, onFinished: (() -> Void)? = nil) {
        self.model = model
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            switch model.state {
            case .editing:
                editingForm
            case .exporting(let progress):
                taskView(progress: progress)
            case .succeeded(let destinationURL):
                ContentUnavailableView {
                    Label("Export Complete", systemImage: "checkmark.circle")
                } description: {
                    Text(destinationURL.lastPathComponent)
                } actions: {
                    Button("Done") { onFinished?() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("prism.instance-export.done")
                }
            case .cancelled:
                ContentUnavailableView {
                    Label("Export Cancelled", systemImage: "pause.circle")
                } description: {
                    Text("No export was committed.")
                } actions: {
                    Button("Start Again") { model.reset() }
                        .accessibilityIdentifier("prism.instance-export.start-again")
                }
            case .failed(let failure):
                ContentUnavailableView {
                    Label("Unable to Export Instance", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(LocalizedStringKey(failure.localizationKey))
                } actions: {
                    if failure.isRetryAvailable {
                        Button("Retry") { _ = model.retry() }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("prism.instance-export.retry")
                    }
                    Button("Edit", role: .cancel) { model.reset() }
                        .accessibilityIdentifier("prism.instance-export.edit")
                }
            }
        }
        .frame(minWidth: 440, minHeight: 360)
        .accessibilityIdentifier("prism.instance-export")
    }

    private var editingForm: some View {
        Form {
            Section("Export") {
                Text(model.draft.sourceInstanceIdentifier)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("prism.instance-export.source")
                Picker("Format", selection: Binding(get: { model.draft.kind }, set: { model.setKind($0) })) {
                    ForEach(PrismInstanceExportKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .accessibilityIdentifier("prism.instance-export.kind")
                Button("Choose Destination…") {
                    let types: [UTType] = model.draft.kind == .zipArchive ? [.zip] : [.plainText, .html, .json]
                    PrismSystemSavePanel.present(defaultFilename: model.defaultFilename, allowedContentTypes: types) {
                        model.setDestinationURL($0)
                    }
                }
                .accessibilityIdentifier("prism.instance-export.choose-destination")
                if let destinationURL = model.draft.destinationURL {
                    Text(destinationURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("prism.instance-export.destination")
                }
            }

            if model.draft.kind == .modList {
                Section("Mod List") {
                    Picker("Format", selection: Binding(get: { model.draft.modListFormat }, set: { model.draft.modListFormat = $0 })) {
                        ForEach(PrismModListExportFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .accessibilityIdentifier("prism.instance-export.mod-list-format")
                    Toggle("Authors", isOn: Binding(get: { model.draft.includeAuthors }, set: { model.draft.includeAuthors = $0 }))
                        .accessibilityIdentifier("prism.instance-export.include-authors")
                    Toggle("Version", isOn: Binding(get: { model.draft.includeVersion }, set: { model.draft.includeVersion = $0 }))
                        .accessibilityIdentifier("prism.instance-export.include-version")
                    Toggle("URL", isOn: Binding(get: { model.draft.includeURL }, set: { model.draft.includeURL = $0 }))
                        .accessibilityIdentifier("prism.instance-export.include-url")
                    Toggle("Filename", isOn: Binding(get: { model.draft.includeFilename }, set: { model.draft.includeFilename = $0 }))
                        .accessibilityIdentifier("prism.instance-export.include-filename")
                    if model.draft.modListFormat == .custom {
                        TextField("Template", text: Binding(get: { model.draft.customTemplate }, set: { model.draft.customTemplate = $0 }))
                            .accessibilityIdentifier("prism.instance-export.custom-template")
                    }
                }
            }

            if let validationMessage = model.validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("prism.instance-export.validation")
            }

            HStack {
                Spacer()
                Button("Export") { _ = model.startExport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canExport)
                    .accessibilityIdentifier("prism.instance-export.start")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func taskView(progress: PrismTaskPresentation?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let progress {
                Label(progress.title, systemImage: progress.state.systemImage)
                    .accessibilityValue(Text(LocalizedStringKey(progress.state.accessibilityValueKey)))
                    .accessibilityIdentifier("prism.instance-export.task")
                if let fraction = progress.progress.fraction {
                    ProgressView(value: fraction)
                        .accessibilityIdentifier("prism.instance-export.progress")
                } else {
                    ProgressView()
                        .accessibilityIdentifier("prism.instance-export.progress")
                }
            } else {
                ProgressView("Exporting Instance")
                    .accessibilityIdentifier("prism.instance-export.progress")
            }
            Button("Cancel", role: .cancel) { _ = model.cancel() }
                .accessibilityIdentifier("prism.instance-export.cancel")
        }
        .padding()
    }
}
