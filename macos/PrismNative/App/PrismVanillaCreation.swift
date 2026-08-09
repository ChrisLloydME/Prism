import Foundation
import SwiftUI

struct PrismVanillaVersionOption: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String

    init?(descriptor: String, name: String) {
        let normalizedDescriptor = descriptor.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDescriptor.isEmpty, !normalizedName.isEmpty else {
            return nil
        }

        self.id = normalizedDescriptor
        self.name = normalizedName
    }
}

struct PrismVanillaLoaderOption: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String

    init?(identifier: String, name: String) {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty, !normalizedName.isEmpty else {
            return nil
        }

        self.id = normalizedIdentifier
        self.name = normalizedName
    }
}

struct PrismVanillaCreationDraft: Equatable, Sendable {
    var versionDescriptor: String
    var versionName: String
    var loaderIdentifier: String?
    var loaderVersionDescriptor: String?
    var name: String
    var groupID: String
    var iconKey: String

    var validationMessage: String? {
        if versionDescriptor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || versionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose a Minecraft version."
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter an instance name."
        }
        if iconKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose an instance icon."
        }

        let hasLoader = loaderIdentifier != nil || loaderVersionDescriptor != nil
        if hasLoader {
            if loaderIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                || loaderVersionDescriptor?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                return "Choose a loader version or select No Loader."
            }
        }
        return nil
    }

    var normalized: Self {
        Self(
            versionDescriptor: versionDescriptor.trimmingCharacters(in: .whitespacesAndNewlines),
            versionName: versionName.trimmingCharacters(in: .whitespacesAndNewlines),
            loaderIdentifier: loaderIdentifier.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            loaderVersionDescriptor: loaderVersionDescriptor.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            groupID: groupID.trimmingCharacters(in: .whitespacesAndNewlines),
            iconKey: iconKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct PrismVanillaCreationFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let retryable: Bool
    let partialChangesRolledBack: Bool

    var isRetryAvailable: Bool { retryable }
}

enum PrismVanillaCreationState: Equatable, Sendable {
    case editing
    case creating(progress: PrismTaskPresentation?)
    case succeeded(PrismInstanceRow)
    case cancelled
    case failed(PrismVanillaCreationFailure)
}

@MainActor
final class PrismVanillaCreationModel: ObservableObject {
    @Published var draft: PrismVanillaCreationDraft
    @Published private(set) var state: PrismVanillaCreationState = .editing

    let versions: [PrismVanillaVersionOption]
    let loaders: [PrismVanillaLoaderOption]
    let icons: [String]

    private let onCreate: ((PRVanillaCreationRequest, Int) -> Void)?
    private let onCancel: (() -> Void)?
    private var generation = 0

    init(
        versions: [PrismVanillaVersionOption] = PrismVanillaCreationModel.fixtureVersions,
        loaders: [PrismVanillaLoaderOption] = PrismVanillaCreationModel.fixtureLoaders,
        icons: [String] = ["default", "grass", "stone"],
        initialDraft: PrismVanillaCreationDraft? = nil,
        onCreate: ((PRVanillaCreationRequest, Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        let uniqueVersions = Self.unique(versions)
        let uniqueLoaders = Self.unique(loaders)
        var seenIcons = Set<String>()
        let uniqueIcons = icons.compactMap { icon -> String? in
            let normalized = icon.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seenIcons.insert(normalized).inserted else { return nil }
            return normalized
        }
        let normalizedIcons = uniqueIcons.isEmpty ? ["default"] : uniqueIcons
        let firstVersion = uniqueVersions.first

        self.versions = uniqueVersions
        self.loaders = uniqueLoaders
        self.icons = normalizedIcons
        self.draft = initialDraft ?? PrismVanillaCreationDraft(
            versionDescriptor: firstVersion?.id ?? "",
            versionName: firstVersion?.name ?? "",
            loaderIdentifier: nil,
            loaderVersionDescriptor: nil,
            name: firstVersion?.name ?? "",
            groupID: "",
            iconKey: normalizedIcons.first ?? "default"
        )
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    var validationMessage: String? { draft.normalized.validationMessage }
    var canCreate: Bool { validationMessage == nil && !isCreating }
    var isCreating: Bool {
        if case .creating = state { return true }
        return false
    }
    var progress: PrismTaskPresentation? {
        guard case .creating(let progress) = state else { return nil }
        return progress
    }
    var failure: PrismVanillaCreationFailure? {
        guard case .failed(let failure) = state else { return nil }
        return failure
    }
    var createdInstance: PrismInstanceRow? {
        guard case .succeeded(let instance) = state else { return nil }
        return instance
    }

    func selectVersion(_ descriptor: String) {
        guard let version = versions.first(where: { $0.id == descriptor }) else { return }
        draft.versionDescriptor = version.id
        draft.versionName = version.name
    }

    func selectLoader(_ identifier: String?) {
        guard let identifier else {
            draft.loaderIdentifier = nil
            draft.loaderVersionDescriptor = nil
            return
        }
        guard loaders.contains(where: { $0.id == identifier }) else { return }
        draft.loaderIdentifier = identifier
        if draft.loaderVersionDescriptor?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            draft.loaderVersionDescriptor = ""
        }
    }

    func setLoaderIdentifier(_ identifier: String) {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.loaderIdentifier = normalized.isEmpty ? nil : normalized
        if normalized.isEmpty {
            draft.loaderVersionDescriptor = nil
        } else if draft.loaderVersionDescriptor == nil {
            draft.loaderVersionDescriptor = ""
        }
    }

    func setIcon(_ iconKey: String) {
        guard icons.contains(iconKey) else { return }
        draft.iconKey = iconKey
    }

    func makeBridgeRequest() -> PRVanillaCreationRequest? {
        let normalized = draft.normalized
        guard normalized.validationMessage == nil else { return nil }
        return PRVanillaCreationRequest(
            versionDescriptor: normalized.versionDescriptor,
            versionName: normalized.versionName,
            loaderIdentifier: normalized.loaderIdentifier,
            loaderVersionDescriptor: normalized.loaderVersionDescriptor,
            name: normalized.name,
            groupID: normalized.groupID.isEmpty ? nil : normalized.groupID,
            iconKey: normalized.iconKey
        )
    }

    @discardableResult
    func create() -> Bool {
        guard let request = makeBridgeRequest(), !isCreating else { return false }
        generation += 1
        let activeGeneration = generation
        draft = draft.normalized
        state = .creating(progress: nil)
        onCreate?(request, activeGeneration)
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard isCreating else { return false }
        generation += 1
        onCancel?()
        state = .cancelled
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard let failure, failure.isRetryAvailable else { return false }
        state = .editing
        return create()
    }

    @discardableResult
    func apply(progress bridgeProgress: PRTaskStatus, generation resultGeneration: Int? = nil) -> Bool {
        guard case .creating = state,
              (resultGeneration ?? generation) == generation,
              let progress = PrismTaskPresentation(bridgeStatus: bridgeProgress) else {
            return false
        }
        state = .creating(progress: progress)
        return true
    }

    @discardableResult
    func apply(result bridgeResult: PRVanillaCreationResult, generation resultGeneration: Int? = nil) -> Bool {
        guard case .creating = state,
              (resultGeneration ?? generation) == generation,
              let outcome = PrismVanillaCreationOutcome(bridgeOutcome: bridgeResult.outcome) else {
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
                    PrismVanillaCreationFailure(
                        localizationKey: "instances.creation.vanilla.invalidResult",
                        diagnosticText: nil,
                        retryable: true,
                        partialChangesRolledBack: false
                    )
                )
                return false
            }
            state = .succeeded(instance)
        case .failed, .rejected:
            state = .failed(
                PrismVanillaCreationFailure(
                    localizationKey: localizationKey,
                    diagnosticText: bridgeResult.diagnosticText,
                    retryable: bridgeResult.retryable,
                    partialChangesRolledBack: false
                )
            )
        case .cancelled:
            state = .cancelled
        }
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, generation resultGeneration: Int? = nil) -> Bool {
        guard case .creating = state,
              (resultGeneration ?? generation) == generation else {
            return false
        }
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localizationKey.isEmpty else { return false }
        state = .failed(
            PrismVanillaCreationFailure(
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

    private static func unique<T: Identifiable & Hashable>(_ values: [T]) -> [T] where T.ID: Hashable {
        var seen = Set<T.ID>()
        return values.filter { seen.insert($0.id).inserted }
    }

    static let fixtureVersions: [PrismVanillaVersionOption] = [
        PrismVanillaVersionOption(descriptor: "1.21.1", name: "1.21.1 Release"),
        PrismVanillaVersionOption(descriptor: "1.20.6", name: "1.20.6 Release"),
    ].compactMap { $0 }

    static let fixtureLoaders: [PrismVanillaLoaderOption] = [
        PrismVanillaLoaderOption(identifier: "net.fabricmc.fabric-loader", name: "Fabric"),
        PrismVanillaLoaderOption(identifier: "net.minecraftforge", name: "Forge"),
    ].compactMap { $0 }
}

enum PrismVanillaCreationOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
    case rejected

    init?(bridgeOutcome: PRVanillaCreationOutcome) {
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
struct PrismVanillaCreationView: View {
    @ObservedObject var model: PrismVanillaCreationModel
    let onFinished: (() -> Void)?

    init(model: PrismVanillaCreationModel, onFinished: (() -> Void)? = nil) {
        self.model = model
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            switch model.state {
            case .editing:
                editingForm
            case .creating(let progress):
                creatingView(progress: progress)
            case .succeeded(let instance):
                ContentUnavailableView {
                    Label("Instance Created", systemImage: "checkmark.circle")
                } description: {
                    Text(instance.name)
                } actions: {
                    Button("Done") { onFinished?() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("prism.vanilla-creation.done")
                }
            case .cancelled:
                ContentUnavailableView {
                    Label("Creation Cancelled", systemImage: "pause.circle")
                } description: {
                    Text("The instance was not committed.")
                } actions: {
                    Button("Start Again") { model.reset() }
                        .accessibilityIdentifier("prism.vanilla-creation.start-again")
                }
            case .failed(let failure):
                ContentUnavailableView {
                    Label("Unable to Create Instance", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(LocalizedStringKey(failure.localizationKey))
                } actions: {
                    if failure.isRetryAvailable {
                        Button("Retry") { _ = model.retry() }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("prism.vanilla-creation.retry")
                    }
                    Button("Edit", role: .cancel) { model.reset() }
                        .accessibilityIdentifier("prism.vanilla-creation.edit")
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .accessibilityIdentifier("prism.vanilla-creation")
    }

    private var editingForm: some View {
        Form {
            Section("Minecraft") {
                if model.versions.isEmpty {
                    TextField(
                        "Minecraft Version",
                        text: Binding(
                            get: { model.draft.versionDescriptor },
                            set: { model.draft.versionDescriptor = $0 }
                        )
                    )
                    .accessibilityIdentifier("prism.vanilla-creation.version")

                    TextField(
                        "Version Name",
                        text: Binding(
                            get: { model.draft.versionName },
                            set: { model.draft.versionName = $0 }
                        )
                    )
                    .accessibilityIdentifier("prism.vanilla-creation.version-name")
                } else {
                    Picker(
                        "Version",
                        selection: Binding(
                            get: { model.draft.versionDescriptor },
                            set: { model.selectVersion($0) }
                        )
                    ) {
                        ForEach(model.versions) { version in
                            Text(version.name).tag(version.id)
                        }
                    }
                    .accessibilityIdentifier("prism.vanilla-creation.version")
                }

                if model.loaders.isEmpty {
                    TextField(
                        "Loader Identifier (Optional)",
                        text: Binding(
                            get: { model.draft.loaderIdentifier ?? "" },
                            set: { model.setLoaderIdentifier($0) }
                        )
                    )
                    .accessibilityIdentifier("prism.vanilla-creation.loader")
                } else {
                    Picker(
                        "Mod Loader",
                        selection: Binding<String?>(
                            get: { model.draft.loaderIdentifier },
                            set: { model.selectLoader($0) }
                        )
                    ) {
                        Text("No Loader").tag(String?.none)
                        ForEach(model.loaders) { loader in
                            Text(loader.name).tag(Optional(loader.id))
                        }
                    }
                    .accessibilityIdentifier("prism.vanilla-creation.loader")
                }

                if model.draft.loaderIdentifier != nil {
                    TextField(
                        "Loader Version",
                        text: Binding(
                            get: { model.draft.loaderVersionDescriptor ?? "" },
                            set: { model.draft.loaderVersionDescriptor = $0 }
                        )
                    )
                    .accessibilityIdentifier("prism.vanilla-creation.loader-version")
                }
            }

            Section("Instance") {
                TextField(
                    "Name",
                    text: Binding(get: { model.draft.name }, set: { model.draft.name = $0 })
                )
                .accessibilityIdentifier("prism.vanilla-creation.name")

                TextField(
                    "Group",
                    text: Binding(get: { model.draft.groupID }, set: { model.draft.groupID = $0 })
                )
                .accessibilityIdentifier("prism.vanilla-creation.group")

                Picker(
                    "Icon",
                    selection: Binding(
                        get: { model.draft.iconKey },
                        set: { model.setIcon($0) }
                    )
                ) {
                    ForEach(model.icons, id: \.self) { icon in
                        Text(icon.capitalized).tag(icon)
                    }
                }
                .accessibilityIdentifier("prism.vanilla-creation.icon")
            }

            if let validationMessage = model.validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("prism.vanilla-creation.validation")
            }

            HStack {
                Spacer()
                Button("Create") { _ = model.create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreate)
                    .accessibilityIdentifier("prism.vanilla-creation.create")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func creatingView(progress: PrismTaskPresentation?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let progress {
                Label(progress.title, systemImage: progress.state.systemImage)
                    .accessibilityValue(Text(LocalizedStringKey(progress.state.accessibilityValueKey)))
                    .accessibilityIdentifier("prism.vanilla-creation.task")
                if let fraction = progress.progress.fraction {
                    ProgressView(value: fraction)
                        .accessibilityIdentifier("prism.vanilla-creation.progress")
                } else {
                    ProgressView()
                        .accessibilityIdentifier("prism.vanilla-creation.progress")
                }
            } else {
                ProgressView("Creating Instance")
                    .accessibilityIdentifier("prism.vanilla-creation.progress")
            }
            Button("Cancel", role: .cancel) { _ = model.cancel() }
                .accessibilityIdentifier("prism.vanilla-creation.cancel")
        }
        .padding()
    }
}

#Preview {
    PrismVanillaCreationView(model: PrismVanillaCreationModel())
}
