import Foundation
import SwiftUI

enum PrismJavaInstallationValidity: Int, Equatable, Sendable {
    case valid
    case incompatible
    case unavailable

    init?(bridgeValidity: PRJavaInstallationValidity) {
        switch bridgeValidity {
        case .valid:
            self = .valid
        case .incompatible:
            self = .incompatible
        case .unavailable:
            self = .unavailable
        @unknown default:
            return nil
        }
    }

    var isSelectable: Bool {
        self == .valid
    }
}

struct PrismJavaInstallation: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let version: String
    let vendor: String
    let architecture: String
    let executablePath: String
    let is64Bit: Bool
    let managed: Bool
    let validity: PrismJavaInstallationValidity
    let diagnosticText: String?

    init?(bridgeInstallation: PRJavaInstallation) {
        let identifier = bridgeInstallation.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = bridgeInstallation.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, !path.isEmpty,
              let validity = PrismJavaInstallationValidity(bridgeValidity: bridgeInstallation.validity) else {
            return nil
        }

        self.id = identifier
        self.version = bridgeInstallation.version.trimmingCharacters(in: .whitespacesAndNewlines)
        self.vendor = bridgeInstallation.vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        self.architecture = bridgeInstallation.architecture.trimmingCharacters(in: .whitespacesAndNewlines)
        self.executablePath = path
        self.is64Bit = bridgeInstallation.is64Bit
        self.managed = bridgeInstallation.managed
        self.validity = validity
        self.diagnosticText = bridgeInstallation.diagnosticText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(
        id: String,
        version: String,
        vendor: String,
        architecture: String,
        executablePath: String,
        is64Bit: Bool,
        managed: Bool,
        validity: PrismJavaInstallationValidity,
        diagnosticText: String? = nil
    ) {
        self.id = id
        self.version = version
        self.vendor = vendor
        self.architecture = architecture
        self.executablePath = executablePath
        self.is64Bit = is64Bit
        self.managed = managed
        self.validity = validity
        self.diagnosticText = diagnosticText
    }

    var isSelectable: Bool {
        validity.isSelectable
    }

    var statusTitle: String {
        switch validity {
        case .valid:
            return managed ? "Managed runtime" : "Available"
        case .incompatible:
            return "Incompatible"
        case .unavailable:
            return "Unavailable"
        }
    }

    var accessibilitySummary: String {
        let versionLabel = version.isEmpty ? "Unknown version" : "Java \(version)"
        let architectureLabel = architecture.isEmpty ? "Unknown architecture" : architecture
        return "\(versionLabel), \(vendor.isEmpty ? "Unknown vendor" : vendor), \(architectureLabel), \(statusTitle)"
    }

    static func fixture() -> [PrismJavaInstallation] {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PrismNativeJavaFixture", isDirectory: true)

        func path(for identifier: String) -> String {
            root
                .appendingPathComponent("java", isDirectory: true)
                .appendingPathComponent(identifier, isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("java")
                .path
        }

        return [
            PrismJavaInstallation(
                id: "java.fixture.21",
                version: "21.0.2",
                vendor: "Fixture JDK",
                architecture: "aarch64",
                executablePath: path(for: "java.fixture.21"),
                is64Bit: true,
                managed: false,
                validity: .valid
            ),
            PrismJavaInstallation(
                id: "java.fixture.managed",
                version: "17.0.10",
                vendor: "Fixture Managed JDK",
                architecture: "aarch64",
                executablePath: path(for: "java.fixture.managed"),
                is64Bit: true,
                managed: true,
                validity: .valid
            ),
            PrismJavaInstallation(
                id: "java.fixture.incompatible",
                version: "8.0.392",
                vendor: "Fixture Legacy JDK",
                architecture: "aarch64",
                executablePath: path(for: "java.fixture.incompatible"),
                is64Bit: true,
                managed: false,
                validity: .incompatible,
                diagnosticText: "This Java runtime is incompatible with the selected launcher requirements."
            ),
            PrismJavaInstallation(
                id: "java.fixture.unavailable",
                version: "",
                vendor: "Fixture Missing JDK",
                architecture: "",
                executablePath: path(for: "java.fixture.unavailable"),
                is64Bit: true,
                managed: false,
                validity: .unavailable,
                diagnosticText: "The Java executable is not available."
            ),
        ]
    }
}

struct PrismJavaFailure: Equatable, Sendable {
    let localizationKey: String
    let diagnosticText: String?
    let recoveryAction: PrismInstanceDetailsRecoveryAction

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }
}

enum PrismJavaDiscoveryState: Equatable, Sendable {
    case idle
    case loading(generation: Int)
    case empty
    case failed(PrismJavaFailure)
    case content([PrismJavaInstallation])
    case cancelled
}

enum PrismJavaSelectionState: Equatable, Sendable {
    case idle
    case saving(generation: Int)
    case failed(PrismJavaFailure)
}

@MainActor
final class PrismJavaDiscoveryModel: ObservableObject {
    @Published private(set) var state: PrismJavaDiscoveryState
    @Published private(set) var confirmedSelectionID: String?
    @Published private(set) var draftSelectionID: String?
    @Published private(set) var selectionState: PrismJavaSelectionState = .idle

    private let onDiscover: ((Int) -> Void)?
    private let onSelect: ((String, Int) -> Void)?
    private let onCancel: (() -> Void)?
    private let bridge: PRPrismBridge?
    private var discoveryToken: PRBridgeObservationToken?
    private var selectionToken: PRBridgeObservationToken?
    private var generation = 0

    init(
        initialInstallations: [PrismJavaInstallation] = PrismJavaInstallation.fixture(),
        selectedInstallationID: String? = nil,
        bridge: PRPrismBridge? = nil,
        onDiscover: ((Int) -> Void)? = nil,
        onSelect: ((String, Int) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        let selectableIDs = Set(initialInstallations.filter(\.isSelectable).map(\.id))
        let confirmedID = selectedInstallationID.flatMap { selectableIDs.contains($0) ? $0 : nil }
        self.state = initialInstallations.isEmpty ? .empty : .content(initialInstallations)
        self.confirmedSelectionID = confirmedID
        self.draftSelectionID = confirmedID
        self.bridge = bridge
        self.onDiscover = onDiscover
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    var installations: [PrismJavaInstallation] {
        guard case .content(let installations) = state else {
            return []
        }
        return installations
    }

    var selectableInstallations: [PrismJavaInstallation] {
        installations.filter(\.isSelectable)
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

    var selectedInstallation: PrismJavaInstallation? {
        installations.first { $0.id == draftSelectionID }
    }

    var selectionFailure: PrismJavaFailure? {
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
        discoveryToken?.cancel()
        if let bridge {
            discoveryToken = bridge.loadJavaInstallations { [weak self] result, error in
                self?.discoveryToken = nil
                if let result {
                    _ = self?.apply(discoveryResult: result, generation: activeGeneration)
                } else if let error {
                    _ = self?.apply(error: error, generation: activeGeneration)
                }
            }
        } else {
            onDiscover?(activeGeneration)
        }
        return true
    }

    @discardableResult
    func cancelDiscovery() -> Bool {
        guard isLoading else {
            return false
        }
        generation += 1
        discoveryToken?.cancel()
        discoveryToken = nil
        onCancel?()
        state = .cancelled
        return true
    }

    @discardableResult
    func apply(discoveryResult: PRJavaDiscoveryResult, generation resultGeneration: Int? = nil) -> Bool {
        guard case .loading(let activeGeneration) = state,
              (resultGeneration ?? activeGeneration) == activeGeneration else {
            return false
        }

        switch discoveryResult.outcome {
        case .succeeded:
            let mapped = discoveryResult.installations.compactMap(PrismJavaInstallation.init(bridgeInstallation:))
            guard mapped.count == discoveryResult.installations.count else {
                state = .failed(Self.failure(key: "java.discovery.invalidResult", diagnostic: nil, recovery: .retry))
                return false
            }
            if let selectedIdentifier = discoveryResult.selectedInstallationIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
               !selectedIdentifier.isEmpty {
                guard let selected = mapped.first(where: { $0.id == selectedIdentifier }), selected.isSelectable else {
                    state = .failed(Self.failure(key: "java.discovery.invalidSelection", diagnostic: nil, recovery: .retry))
                    return false
                }
                confirmedSelectionID = selected.id
                draftSelectionID = selected.id
            } else {
                preserveSelection(in: mapped)
            }
            state = mapped.isEmpty ? .empty : .content(mapped)
        case .failed, .rejected:
            state = .failed(
                Self.failure(
                    key: discoveryResult.localizationKey,
                    diagnostic: discoveryResult.diagnosticText,
                    recovery: discoveryResult.retryable ? .retry : .none
                )
            )
        case .cancelled:
            state = .cancelled
        @unknown default:
            state = .failed(Self.failure(key: "java.discovery.unknownOutcome", diagnostic: nil, recovery: .retry))
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
    func select(id: String) -> Bool {
        guard !isLoading, !isSavingSelection,
              let installation = installations.first(where: { $0.id == id }),
              installation.isSelectable else {
            return false
        }

        draftSelectionID = id
        generation += 1
        let activeGeneration = generation
        selectionState = .saving(generation: activeGeneration)
        selectionToken?.cancel()
        if let bridge {
            selectionToken = bridge.selectJavaInstallation(withIdentifier: id) { [weak self] result, error in
                self?.selectionToken = nil
                if let result {
                    _ = self?.apply(selectionResult: result, generation: activeGeneration)
                } else if let error {
                    _ = self?.apply(error: error, toSelectionGeneration: activeGeneration)
                }
            }
        } else if let onSelect {
            onSelect(id, activeGeneration)
        } else {
            confirmedSelectionID = id
            selectionState = .idle
        }
        return true
    }

    @discardableResult
    func apply(selectionResult: PRJavaSelectionResult, generation resultGeneration: Int? = nil) -> Bool {
        guard case .saving(let activeGeneration) = selectionState,
              (resultGeneration ?? activeGeneration) == activeGeneration else {
            return false
        }

        switch selectionResult.outcome {
        case .succeeded:
            guard let bridgeInstallation = selectionResult.installation,
                  let installation = PrismJavaInstallation(bridgeInstallation: bridgeInstallation),
                  installation.isSelectable,
                  installation.id == draftSelectionID else {
                selectionState = .failed(Self.failure(key: "java.selection.invalidResult", diagnostic: nil, recovery: .retry))
                return false
            }
            confirmedSelectionID = installation.id
            draftSelectionID = installation.id
            selectionState = .idle
        case .unknownInstallation, .rejected:
            selectionState = .failed(
                Self.failure(
                    key: selectionResult.localizationKey,
                    diagnostic: selectionResult.diagnosticText,
                    recovery: .retry
                )
            )
        @unknown default:
            selectionState = .failed(Self.failure(key: "java.selection.unknownOutcome", diagnostic: nil, recovery: .retry))
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
              failure.isRetryAvailable,
              let draftSelectionID else {
            return false
        }
        guard let installation = installations.first(where: { $0.id == draftSelectionID }), installation.isSelectable else {
            return false
        }

        generation += 1
        let activeGeneration = generation
        selectionState = .saving(generation: activeGeneration)
        selectionToken?.cancel()
        if let bridge {
            selectionToken = bridge.selectJavaInstallation(withIdentifier: installation.id) { [weak self] result, error in
                self?.selectionToken = nil
                if let result {
                    _ = self?.apply(selectionResult: result, generation: activeGeneration)
                } else if let error {
                    _ = self?.apply(error: error, toSelectionGeneration: activeGeneration)
                }
            }
        } else if let onSelect {
            onSelect(installation.id, activeGeneration)
        } else {
            confirmedSelectionID = installation.id
            selectionState = .idle
        }
        return true
    }

    func clear() {
        generation += 1
        discoveryToken?.cancel()
        discoveryToken = nil
        selectionToken?.cancel()
        selectionToken = nil
        state = .empty
        confirmedSelectionID = nil
        draftSelectionID = nil
        selectionState = .idle
    }

    private func preserveSelection(in installations: [PrismJavaInstallation]) {
        let selectableIDs = Set(installations.filter(\.isSelectable).map(\.id))
        guard let confirmedSelectionID, selectableIDs.contains(confirmedSelectionID) else {
            self.confirmedSelectionID = nil
            self.draftSelectionID = nil
            return
        }
        draftSelectionID = confirmedSelectionID
    }

    private static func failure(
        key: String,
        diagnostic: String?,
        recovery: PrismInstanceDetailsRecoveryAction
    ) -> PrismJavaFailure {
        PrismJavaFailure(localizationKey: key, diagnosticText: diagnostic, recoveryAction: recovery)
    }
}

struct PrismJavaSettingsView: View {
    @ObservedObject var model: PrismJavaDiscoveryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.state {
            case .idle, .loading:
                loadingView
            case .empty:
                unavailableView(
                    title: "No Java Installations",
                    systemImage: "cup.and.saucer",
                    description: "No compatible Java installations are available for this launcher.",
                    actionTitle: "Refresh",
                    action: { _ = model.refresh() },
                    actionEnabled: true
                )
            case .failed(let failure):
                unavailableView(
                    title: "Java Discovery Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: failure.diagnosticText ?? failure.localizationKey,
                    actionTitle: "Retry",
                    action: { _ = model.retryDiscovery() },
                    actionEnabled: failure.isRetryAvailable
                )
            case .cancelled:
                unavailableView(
                    title: "Java Discovery Cancelled",
                    systemImage: "pause.circle",
                    description: "Java discovery was cancelled before a result was confirmed.",
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
        .accessibilityIdentifier("prism.settings.java")
        .onAppear {
            if case .empty = model.state {
                _ = model.refresh()
            }
        }
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView("Detecting Java installations…")
                .accessibilityIdentifier("prism.settings.java.progress")
            Button("Cancel") {
                _ = model.cancelDiscovery()
            }
            .disabled(!model.isLoading)
            .accessibilityIdentifier("prism.settings.java.cancel")
        }
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Java Installations")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    _ = model.refresh()
                }
                .accessibilityIdentifier("prism.settings.java.refresh")
            }

            List(selection: Binding<String?>(
                get: { model.draftSelectionID },
                set: { newValue in
                    if let newValue {
                        _ = model.select(id: newValue)
                    }
                }
            )) {
                ForEach(model.installations) { installation in
                    let statusTitle = installation.statusTitle
                    let statusColor: Color = installation.isSelectable ? .secondary : .orange
                    HStack(alignment: .top, spacing: 10) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(installation.version.isEmpty ? "Java version unavailable" : "Java \(installation.version)")
                                Text(installation.vendor.isEmpty ? "Unknown vendor" : installation.vendor)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(installation.executablePath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        } icon: {
                            Image(systemName: installation.isSelectable ? "checkmark.circle" : "exclamationmark.triangle")
                        }
                        Spacer()
                        Text(statusTitle)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    }
                    .tag(installation.id)
                    .disabled(!installation.isSelectable)
                    .help(installation.diagnosticText ?? installation.accessibilitySummary)
                    .accessibilityIdentifier("prism.settings.java.\(installation.id)")
                    .accessibilityValue(Text(installation.accessibilitySummary))
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 150)

            if let selectedInstallation = model.selectedInstallation {
                LabeledContent("Selected Java") {
                    Text(selectedInstallation.version.isEmpty ? "Unavailable" : selectedInstallation.version)
                }
                LabeledContent("Executable") {
                    Text(selectedInstallation.executablePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("Select a compatible Java installation to use for launches.")
                    .foregroundStyle(.secondary)
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
                .accessibilityIdentifier("prism.settings.java.selection-error")
            }

            if model.isSavingSelection {
                ProgressView("Confirming Java selection…")
                    .controlSize(.small)
                    .accessibilityIdentifier("prism.settings.java.selection-progress")
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
