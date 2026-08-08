import Foundation
import AppKit
import SwiftUI

struct PrismInstanceRow: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let group: String?

    init?(id: String, name: String, group: String? = nil) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedGroup = group?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedID.isEmpty, !normalizedName.isEmpty else {
            return nil
        }

        self.id = normalizedID
        self.name = normalizedName
        self.group = normalizedGroup?.isEmpty == true ? nil : normalizedGroup
    }
}

struct PrismInstanceDetails: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let iconKey: String?
    let group: String?
    let instanceType: String?
    let notes: String
    let notesEditable: Bool

    init?(bridgeDetails: PRInstanceDetails) {
        let identifier = bridgeDetails.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = bridgeDetails.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, !name.isEmpty else {
            return nil
        }

        self.id = identifier
        self.name = name
        self.iconKey = Self.normalizedOptional(bridgeDetails.iconKey)
        self.group = Self.normalizedOptional(bridgeDetails.groupID)
        self.instanceType = Self.normalizedOptional(bridgeDetails.instanceType)
        self.notes = bridgeDetails.notes
        self.notesEditable = bridgeDetails.notesEditable
    }

    init(
        id: String,
        name: String,
        iconKey: String?,
        group: String?,
        instanceType: String?,
        notes: String,
        notesEditable: Bool
    ) {
        self.id = id
        self.name = name
        self.iconKey = iconKey
        self.group = group
        self.instanceType = instanceType
        self.notes = notes
        self.notesEditable = notesEditable
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum PrismInstanceComponentProblemSeverity: Int, Equatable, Sendable {
    case none
    case warning
    case error

    init?(bridgeSeverity: PRInstanceComponentProblemSeverity) {
        switch bridgeSeverity {
        case .none:
            self = .none
        case .warning:
            self = .warning
        case .error:
            self = .error
        @unknown default:
            return nil
        }
    }

    var systemImage: String? {
        switch self {
        case .none:
            return nil
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }

    var accessibilityLabelKey: String {
        switch self {
        case .none:
            return "No Component Problems"
        case .warning:
            return "Component Warning"
        case .error:
            return "Component Error"
        }
    }
}

struct PrismInstanceComponent: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let enabled: Bool
    let canBeDisabled: Bool
    let dependencyOnly: Bool
    let important: Bool
    let custom: Bool
    let problemSeverity: PrismInstanceComponentProblemSeverity
    let problemDescriptions: [String]

    init?(bridgeComponent: PRInstanceComponent) {
        let identifier = bridgeComponent.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = bridgeComponent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = bridgeComponent.version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              !name.isEmpty,
              let problemSeverity = PrismInstanceComponentProblemSeverity(
                bridgeSeverity: bridgeComponent.problemSeverity),
              bridgeComponent.canBeDisabled || bridgeComponent.enabled else {
            return nil
        }

        self.id = identifier
        self.name = name
        self.version = version
        self.enabled = bridgeComponent.enabled
        self.canBeDisabled = bridgeComponent.canBeDisabled
        self.dependencyOnly = bridgeComponent.dependencyOnly
        self.important = bridgeComponent.important
        self.custom = bridgeComponent.custom
        self.problemSeverity = problemSeverity
        self.problemDescriptions = bridgeComponent.problemDescriptions
    }

    var displayVersion: String {
        version.isEmpty ? "Not Available" : version
    }

    var stateKey: String {
        if !canBeDisabled || important || dependencyOnly {
            return custom ? "Custom Required" : "Required"
        }
        if custom {
            return enabled ? "Custom Enabled" : "Custom Disabled"
        }
        return enabled ? "Enabled" : "Disabled"
    }

    var accessibilityValueKey: String {
        switch problemSeverity {
        case .none:
            return stateKey
        case .warning:
            return "Component Has a Warning"
        case .error:
            return "Component Has an Error"
        }
    }
}

struct PrismInstanceComponentsFailure: Equatable, Sendable {
    let instanceIdentifier: String
    let localizationKey: String
    let substitutionValues: [String: String]
    let diagnosticText: String?
    let recoveryAction: PrismInstanceDetailsRecoveryAction
    let partialChangesRolledBack: Bool

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }
}

enum PrismInstanceComponentsState: Equatable, Sendable {
    case loading(identifier: String)
    case empty
    case failed(PrismInstanceComponentsFailure)
    case content([PrismInstanceComponent])
}

@MainActor
final class PrismInstanceComponentsModel: ObservableObject {
    @Published private(set) var state: PrismInstanceComponentsState = .empty
    @Published private(set) var searchText = ""
    @Published private(set) var selectedComponentID: String?

    private let onLoad: ((String) -> Void)?
    private var activeIdentifier: String?

    init(onLoad: ((String) -> Void)? = nil) {
        self.onLoad = onLoad
    }

    var components: [PrismInstanceComponent] {
        guard case .content(let components) = state else {
            return []
        }
        return components
    }

    var visibleComponents: [PrismInstanceComponent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return components
        }

        return components.filter { component in
            let searchableValues = [
                component.id,
                component.name,
                component.version,
                component.displayVersion,
                component.problemDescriptions.joined(separator: " "),
            ]
            return searchableValues.contains { $0.lowercased().contains(query) }
        }
    }

    var failure: PrismInstanceComponentsFailure? {
        guard case .failed(let failure) = state else {
            return nil
        }
        return failure
    }

    @discardableResult
    func beginLoading(identifier: String) -> Bool {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            return false
        }

        activeIdentifier = normalizedIdentifier
        state = .loading(identifier: normalizedIdentifier)
        searchText = ""
        selectedComponentID = nil
        onLoad?(normalizedIdentifier)
        return true
    }

    @discardableResult
    func apply(components bridgeComponents: [PRInstanceComponent]) -> Bool {
        guard activeIdentifier != nil else {
            return false
        }

        var converted: [PrismInstanceComponent] = []
        var identifiers = Set<String>()
        for bridgeComponent in bridgeComponents {
            guard let component = PrismInstanceComponent(bridgeComponent: bridgeComponent),
                  identifiers.insert(component.id).inserted else {
                return false
            }
            converted.append(component)
        }

        selectedComponentID = nil
        state = converted.isEmpty ? .empty : .content(converted)
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, instanceIdentifier: String) -> Bool {
        let normalizedIdentifier = instanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty,
              !localizationKey.isEmpty,
              activeIdentifier == nil || activeIdentifier == normalizedIdentifier else {
            return false
        }

        activeIdentifier = normalizedIdentifier
        selectedComponentID = nil
        state = .failed(
            PrismInstanceComponentsFailure(
                instanceIdentifier: normalizedIdentifier,
                localizationKey: localizationKey,
                substitutionValues: error.substitutionValues,
                diagnosticText: error.diagnosticText,
                recoveryAction: error.recoveryKind == .retry ? .retry : .none,
                partialChangesRolledBack: error.partialChangesRolledBack
            )
        )
        return true
    }

    func setSearchText(_ searchText: String) {
        self.searchText = searchText
        if let selectedComponentID, !visibleComponents.contains(where: { $0.id == selectedComponentID }) {
            self.selectedComponentID = nil
        }
    }

    func selectComponent(_ identifier: String?) {
        guard let identifier,
              visibleComponents.contains(where: { $0.id == identifier }) else {
            selectedComponentID = nil
            return
        }
        selectedComponentID = identifier
    }

    @discardableResult
    func retry() -> Bool {
        guard case .failed(let failure) = state, failure.isRetryAvailable else {
            return false
        }
        return beginLoading(identifier: failure.instanceIdentifier)
    }

    func clear() {
        activeIdentifier = nil
        state = .empty
        searchText = ""
        selectedComponentID = nil
    }
}

enum PrismInstanceResourceKind: Int, CaseIterable, Equatable, Sendable {
    case mods
    case resourcePacks
    case shaderPacks
    case texturePacks
    case dataPacks

    init?(bridgeKind: PRInstanceResourceKind) {
        switch bridgeKind {
        case .mods:
            self = .mods
        case .resourcePacks:
            self = .resourcePacks
        case .shaderPacks:
            self = .shaderPacks
        case .texturePacks:
            self = .texturePacks
        case .dataPacks:
            self = .dataPacks
        @unknown default:
            return nil
        }
    }

    var bridgeKind: PRInstanceResourceKind {
        switch self {
        case .mods:
            return .mods
        case .resourcePacks:
            return .resourcePacks
        case .shaderPacks:
            return .shaderPacks
        case .texturePacks:
            return .texturePacks
        case .dataPacks:
            return .dataPacks
        }
    }

    var titleKey: String {
        switch self {
        case .mods:
            return "Mods"
        case .resourcePacks:
            return "Resource Packs"
        case .shaderPacks:
            return "Shader Packs"
        case .texturePacks:
            return "Texture Packs"
        case .dataPacks:
            return "Data Packs"
        }
    }
}

enum PrismInstanceResourceAction: Int, Equatable, Sendable {
    case enable
    case disable
    case delete
    case `import`
    case reveal

    init?(bridgeAction: PRInstanceResourceAction) {
        switch bridgeAction {
        case .enable:
            self = .enable
        case .disable:
            self = .disable
        case .delete:
            self = .delete
        case .import:
            self = .import
        case .reveal:
            self = .reveal
        @unknown default:
            return nil
        }
    }

    var bridgeAction: PRInstanceResourceAction {
        switch self {
        case .enable:
            return .enable
        case .disable:
            return .disable
        case .delete:
            return .delete
        case .import:
            return .import
        case .reveal:
            return .reveal
        }
    }
}

enum PrismInstanceResourceMutationOutcome: Int, Equatable, Sendable {
    case succeeded
    case unknownInstance
    case unknownResource
    case rejected
    case failed

    init?(bridgeOutcome: PRInstanceResourceMutationOutcome) {
        switch bridgeOutcome {
        case .succeeded:
            self = .succeeded
        case .unknownInstance:
            self = .unknownInstance
        case .unknownResource:
            self = .unknownResource
        case .rejected:
            self = .rejected
        case .failed:
            self = .failed
        @unknown default:
            return nil
        }
    }
}

struct PrismInstanceResource: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let fileName: String
    let provider: String
    let kind: PrismInstanceResourceKind
    let enabled: Bool
    let canBeToggled: Bool
    let canBeDeleted: Bool
    let isDirectory: Bool
    let hasMetadata: Bool
    let problemDescriptions: [String]

    init?(bridgeResource: PRInstanceResource) {
        let identifier = bridgeResource.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = bridgeResource.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = bridgeResource.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              !name.isEmpty,
              !fileName.isEmpty,
              let kind = PrismInstanceResourceKind(bridgeKind: bridgeResource.kind),
              !(bridgeResource.directory && bridgeResource.canBeToggled) else {
            return nil
        }

        self.id = identifier
        self.name = name
        self.version = bridgeResource.version.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fileName = fileName
        self.provider = bridgeResource.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.enabled = bridgeResource.enabled
        self.canBeToggled = bridgeResource.canBeToggled
        self.canBeDeleted = bridgeResource.canBeDeleted
        self.isDirectory = bridgeResource.directory
        self.hasMetadata = bridgeResource.hasMetadata
        self.problemDescriptions = bridgeResource.problemDescriptions
    }

    var displayVersion: String {
        version.isEmpty ? "Not Available" : version
    }

    var stateKey: String {
        if isDirectory {
            return "Folder"
        }
        return enabled ? "Enabled" : "Disabled"
    }

    var accessibilityValueKey: String {
        if let problem = problemDescriptions.first, !problem.isEmpty {
            return "Resource Has a Problem"
        }
        return stateKey
    }
}

struct PrismInstanceResourceMutationIntent: Equatable, Sendable {
    let action: PrismInstanceResourceAction
    let resourceIdentifier: String
    let sourceURL: URL?
    let confirmed: Bool
}

struct PrismInstanceResourceFailure: Equatable, Sendable {
    let instanceIdentifier: String
    let kind: PrismInstanceResourceKind
    let action: PrismInstanceResourceAction
    let resourceIdentifier: String
    let localizationKey: String
    let diagnosticText: String?
    let partialChangesRolledBack: Bool
    let recoveryAction: PrismInstanceDetailsRecoveryAction

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }
}

struct PrismInstanceResourcesFailure: Equatable, Sendable {
    let instanceIdentifier: String
    let kind: PrismInstanceResourceKind
    let localizationKey: String
    let substitutionValues: [String: String]
    let diagnosticText: String?
    let recoveryAction: PrismInstanceDetailsRecoveryAction
    let partialChangesRolledBack: Bool

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }
}

enum PrismInstanceResourcesState: Equatable, Sendable {
    case loading(identifier: String, kind: PrismInstanceResourceKind)
    case empty
    case failed(PrismInstanceResourcesFailure)
    case content([PrismInstanceResource])
}

enum PrismInstanceResourcesMutationState: Equatable, Sendable {
    case idle
    case pending(PrismInstanceResourceMutationIntent)
    case failed(PrismInstanceResourceFailure)
}

@MainActor
final class PrismInstanceResourcesModel: ObservableObject {
    @Published private(set) var kind: PrismInstanceResourceKind = .mods
    @Published private(set) var state: PrismInstanceResourcesState = .empty
    @Published private(set) var searchText = ""
    @Published private(set) var selectedResourceID: String?
    @Published private(set) var pendingDeleteResourceID: String?
    @Published private(set) var mutationState: PrismInstanceResourcesMutationState = .idle

    private let onLoad: ((String, PrismInstanceResourceKind) -> Void)?
    private let onMutate: ((String, PrismInstanceResourceKind, PrismInstanceResourceMutationIntent) -> Void)?
    private var activeIdentifier: String?
    private var lastMutationIntent: PrismInstanceResourceMutationIntent?

    init(
        onLoad: ((String, PrismInstanceResourceKind) -> Void)? = nil,
        onMutate: ((String, PrismInstanceResourceKind, PrismInstanceResourceMutationIntent) -> Void)? = nil
    ) {
        self.onLoad = onLoad
        self.onMutate = onMutate
    }

    var resources: [PrismInstanceResource] {
        guard case .content(let resources) = state else {
            return []
        }
        return resources
    }

    var visibleResources: [PrismInstanceResource] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return resources
        }

        return resources.filter { resource in
            [resource.id, resource.name, resource.version, resource.fileName, resource.provider,
             resource.problemDescriptions.joined(separator: " ")]
                .contains { $0.lowercased().contains(query) }
        }
    }

    var loadFailure: PrismInstanceResourcesFailure? {
        guard case .failed(let failure) = state else {
            return nil
        }
        return failure
    }

    var mutationFailure: PrismInstanceResourceFailure? {
        guard case .failed(let failure) = mutationState else {
            return nil
        }
        return failure
    }

    @discardableResult
    func beginLoading(identifier: String, kind: PrismInstanceResourceKind = .mods) -> Bool {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            return false
        }

        activeIdentifier = normalizedIdentifier
        self.kind = kind
        state = .loading(identifier: normalizedIdentifier, kind: kind)
        searchText = ""
        selectedResourceID = nil
        pendingDeleteResourceID = nil
        mutationState = .idle
        lastMutationIntent = nil
        onLoad?(normalizedIdentifier, kind)
        return true
    }

    func selectKind(_ kind: PrismInstanceResourceKind) {
        guard self.kind != kind else {
            return
        }
        self.kind = kind
        if let activeIdentifier {
            _ = beginLoading(identifier: activeIdentifier, kind: kind)
        }
    }

    @discardableResult
    func apply(resources bridgeResources: [PRInstanceResource]) -> Bool {
        guard activeIdentifier != nil else {
            return false
        }

        var converted: [PrismInstanceResource] = []
        var identifiers = Set<String>()
        for bridgeResource in bridgeResources {
            guard let resource = PrismInstanceResource(bridgeResource: bridgeResource),
                  resource.kind == kind,
                  identifiers.insert(resource.id).inserted else {
                return false
            }
            converted.append(resource)
        }

        selectedResourceID = nil
        pendingDeleteResourceID = nil
        mutationState = .idle
        state = converted.isEmpty ? .empty : .content(converted)
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, instanceIdentifier: String, kind: PrismInstanceResourceKind) -> Bool {
        let normalizedIdentifier = instanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty,
              !localizationKey.isEmpty,
              activeIdentifier == nil || activeIdentifier == normalizedIdentifier,
              self.kind == kind else {
            return false
        }

        activeIdentifier = normalizedIdentifier
        self.kind = kind
        selectedResourceID = nil
        pendingDeleteResourceID = nil
        state = .failed(
            PrismInstanceResourcesFailure(
                instanceIdentifier: normalizedIdentifier,
                kind: kind,
                localizationKey: localizationKey,
                substitutionValues: error.substitutionValues,
                diagnosticText: error.diagnosticText,
                recoveryAction: error.recoveryKind == .retry ? .retry : .none,
                partialChangesRolledBack: error.partialChangesRolledBack
            )
        )
        return true
    }

    @discardableResult
    func apply(mutationResult bridgeResult: PRInstanceResourceMutationResult, instanceIdentifier: String) -> Bool {
        let normalizedIdentifier = instanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let activeIdentifier,
              activeIdentifier == normalizedIdentifier,
              bridgeResult.instanceIdentifier == normalizedIdentifier,
              bridgeResult.kind == kind.bridgeKind,
              let action = PrismInstanceResourceAction(bridgeAction: bridgeResult.action),
              let outcome = PrismInstanceResourceMutationOutcome(bridgeOutcome: bridgeResult.outcome) else {
            return false
        }

        guard let lastMutationIntent,
              lastMutationIntent.action == action,
              lastMutationIntent.resourceIdentifier == bridgeResult.resourceIdentifier else {
            return false
        }

        switch outcome {
        case .succeeded:
            mutationState = .idle
            self.lastMutationIntent = nil
            state = .loading(identifier: normalizedIdentifier, kind: kind)
            searchText = ""
            selectedResourceID = nil
            pendingDeleteResourceID = nil
            onLoad?(normalizedIdentifier, kind)
        case .unknownInstance, .unknownResource, .rejected, .failed:
            let localizationKey = bridgeResult.localizationKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !localizationKey.isEmpty else {
                return false
            }
            let failure = PrismInstanceResourceFailure(
                instanceIdentifier: normalizedIdentifier,
                kind: kind,
                action: action,
                resourceIdentifier: bridgeResult.resourceIdentifier,
                localizationKey: localizationKey,
                diagnosticText: bridgeResult.diagnosticText,
                partialChangesRolledBack: bridgeResult.partialChangesRolledBack,
                recoveryAction: .retry
            )
            mutationState = .failed(failure)
        }
        return true
    }

    func setSearchText(_ searchText: String) {
        self.searchText = searchText
        if let selectedResourceID, !visibleResources.contains(where: { $0.id == selectedResourceID }) {
            self.selectedResourceID = nil
        }
    }

    func selectResource(_ identifier: String?) {
        guard let identifier,
              visibleResources.contains(where: { $0.id == identifier }) else {
            selectedResourceID = nil
            return
        }
        selectedResourceID = identifier
    }

    @discardableResult
    func requestDelete(_ identifier: String) -> Bool {
        guard let resource = resources.first(where: { $0.id == identifier }), resource.canBeDeleted else {
            return false
        }
        pendingDeleteResourceID = identifier
        return true
    }

    func cancelDelete() {
        pendingDeleteResourceID = nil
    }

    @discardableResult
    func confirmDelete() -> Bool {
        guard let identifier = pendingDeleteResourceID else {
            return false
        }
        pendingDeleteResourceID = nil
        return sendMutation(
            PrismInstanceResourceMutationIntent(action: .delete, resourceIdentifier: identifier, sourceURL: nil, confirmed: true)
        )
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, for identifier: String) -> Bool {
        guard let resource = resources.first(where: { $0.id == identifier }),
              resource.canBeToggled,
              resource.enabled != enabled else {
            return false
        }
        return sendMutation(
            PrismInstanceResourceMutationIntent(
                action: enabled ? .enable : .disable,
                resourceIdentifier: identifier,
                sourceURL: nil,
                confirmed: false
            )
        )
    }

    @discardableResult
    func importResources(from urls: [URL]) -> Bool {
        guard let url = urls.first(where: { $0.isFileURL && !$0.path.isEmpty && $0.path.hasPrefix("/") }) else {
            return false
        }
        return sendMutation(
            PrismInstanceResourceMutationIntent(
                action: .import,
                resourceIdentifier: url.lastPathComponent,
                sourceURL: url,
                confirmed: false
            )
        )
    }

    @discardableResult
    func reveal(_ identifier: String) -> Bool {
        guard resources.contains(where: { $0.id == identifier }) else {
            return false
        }
        return sendMutation(
            PrismInstanceResourceMutationIntent(action: .reveal, resourceIdentifier: identifier, sourceURL: nil, confirmed: false)
        )
    }

    @discardableResult
    func retry() -> Bool {
        if case .failed(let failure) = state, failure.recoveryAction == .retry {
            return beginLoading(identifier: failure.instanceIdentifier, kind: failure.kind)
        }
        guard let failure = mutationFailure, failure.isRetryAvailable, let lastMutationIntent else {
            return false
        }
        mutationState = .pending(lastMutationIntent)
        guard let activeIdentifier else {
            return false
        }
        onMutate?(activeIdentifier, kind, lastMutationIntent)
        return true
    }

    func clear() {
        activeIdentifier = nil
        state = .empty
        searchText = ""
        selectedResourceID = nil
        pendingDeleteResourceID = nil
        mutationState = .idle
        lastMutationIntent = nil
    }

    func dismissMutationFailure() {
        if case .failed = mutationState {
            mutationState = .idle
            lastMutationIntent = nil
        }
    }

    @discardableResult
    private func sendMutation(_ intent: PrismInstanceResourceMutationIntent) -> Bool {
        guard let activeIdentifier else {
            return false
        }
        lastMutationIntent = intent
        mutationState = .pending(intent)
        onMutate?(activeIdentifier, kind, intent)
        return true
    }
}

enum PrismInstanceDetailsRecoveryAction: String, Equatable, Sendable {
    case retry
    case none

    var titleKey: String {
        switch self {
        case .retry:
            return "Retry"
        case .none:
            return "Dismiss"
        }
    }

    var accessibilityLabelKey: String {
        switch self {
        case .retry:
            return "Retry Loading Instance Details"
        case .none:
            return "Dismiss Instance Details Error"
        }
    }

    var helpKey: String {
        switch self {
        case .retry:
            return "Try loading this instance again."
        case .none:
            return "Review the instance details error."
        }
    }
}

struct PrismInstanceDetailsFailure: Equatable, Sendable {
    let instanceIdentifier: String
    let localizationKey: String
    let substitutionValues: [String: String]
    let diagnosticText: String?
    let recoveryAction: PrismInstanceDetailsRecoveryAction
    let partialChangesRolledBack: Bool

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }
}

enum PrismInstanceDetailsState: Equatable, Sendable {
    case loading(identifier: String)
    case empty
    case failed(PrismInstanceDetailsFailure)
    case content(PrismInstanceDetails)
}

enum PrismInstanceNotesSaveState: Equatable, Sendable {
    case idle
    case saving
    case failed(PrismInstanceDetailsFailure)
}

struct PrismInstanceNotesUpdatePresentation: Equatable, Sendable {
    let instanceIdentifier: String
    let notes: String
    let outcome: PRInstanceNotesUpdateOutcome

    init?(bridgeResult: PRInstanceNotesUpdateResult) {
        let identifier = bridgeResult.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            return nil
        }

        self.instanceIdentifier = identifier
        self.notes = bridgeResult.notes
        self.outcome = bridgeResult.outcome
    }
}

@MainActor
final class PrismInstanceDetailsModel: ObservableObject {
    @Published private(set) var state: PrismInstanceDetailsState = .empty
    @Published private(set) var draftNotes = ""
    @Published private(set) var notesSaveState: PrismInstanceNotesSaveState = .idle

    private let onLoad: ((String) -> Void)?
    private let onSaveNotes: ((String, String) -> Void)?
    private var activeIdentifier: String?

    init(
        onLoad: ((String) -> Void)? = nil,
        onSaveNotes: ((String, String) -> Void)? = nil
    ) {
        self.onLoad = onLoad
        self.onSaveNotes = onSaveNotes
    }

    var details: PrismInstanceDetails? {
        guard case .content(let details) = state else {
            return nil
        }
        return details
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    var isNotesSaveAvailable: Bool {
        guard let details, details.notesEditable, notesSaveState != .saving else {
            return false
        }
        return draftNotes != details.notes
    }

    var notesFailure: PrismInstanceDetailsFailure? {
        guard case .failed(let failure) = notesSaveState else {
            return nil
        }
        return failure
    }

    @discardableResult
    func beginLoading(identifier: String) -> Bool {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            return false
        }

        activeIdentifier = normalizedIdentifier
        state = .loading(identifier: normalizedIdentifier)
        draftNotes = ""
        notesSaveState = .idle
        onLoad?(normalizedIdentifier)
        return true
    }

    @discardableResult
    func apply(details bridgeDetails: PRInstanceDetails) -> Bool {
        guard let details = PrismInstanceDetails(bridgeDetails: bridgeDetails) else {
            return false
        }

        activeIdentifier = details.id
        state = .content(details)
        draftNotes = details.notes
        notesSaveState = .idle
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, instanceIdentifier: String) -> Bool {
        let normalizedIdentifier = instanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty, !localizationKey.isEmpty else {
            return false
        }

        let failure = PrismInstanceDetailsFailure(
            instanceIdentifier: normalizedIdentifier,
            localizationKey: localizationKey,
            substitutionValues: error.substitutionValues,
            diagnosticText: error.diagnosticText,
            recoveryAction: error.recoveryKind == .retry ? .retry : .none,
            partialChangesRolledBack: error.partialChangesRolledBack
        )

        if isLoading {
            state = .failed(failure)
            notesSaveState = .idle
        } else if activeIdentifier == normalizedIdentifier && details != nil && notesSaveState == .saving {
            notesSaveState = .failed(failure)
        } else {
            activeIdentifier = normalizedIdentifier
            state = .failed(failure)
            draftNotes = ""
            notesSaveState = .idle
        }
        return true
    }

    func setDraftNotes(_ notes: String) {
        guard details?.notesEditable == true, notesSaveState != .saving else {
            return
        }
        draftNotes = notes
        if case .failed = notesSaveState {
            notesSaveState = .idle
        }
    }

    @discardableResult
    func saveNotes() -> Bool {
        guard let details, details.notesEditable, isNotesSaveAvailable else {
            return false
        }

        notesSaveState = .saving
        onSaveNotes?(details.id, draftNotes)
        return true
    }

    @discardableResult
    func apply(notesResult bridgeResult: PRInstanceNotesUpdateResult) -> Bool {
        guard let result = PrismInstanceNotesUpdatePresentation(bridgeResult: bridgeResult),
              let details,
              details.id == result.instanceIdentifier,
              notesSaveState == .saving else {
            return false
        }

        switch result.outcome {
        case .succeeded:
            state = .content(
                PrismInstanceDetails(
                    id: details.id,
                    name: details.name,
                    iconKey: details.iconKey,
                    group: details.group,
                    instanceType: details.instanceType,
                    notes: result.notes,
                    notesEditable: details.notesEditable
                )
            )
            draftNotes = result.notes
            notesSaveState = .idle
        case .unknownInstance:
            notesSaveState = .failed(Self.notesFailure(for: result.instanceIdentifier, key: "instance.notes.instanceMissing"))
        case .rejected:
            notesSaveState = .failed(Self.notesFailure(for: result.instanceIdentifier, key: "instance.notes.updateRejected"))
        @unknown default:
            return false
        }
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard case .failed(let failure) = state,
              failure.isRetryAvailable else {
            return false
        }
        return beginLoading(identifier: failure.instanceIdentifier)
    }

    @discardableResult
    func retryNotes() -> Bool {
        guard case .failed(let failure) = notesSaveState,
              failure.isRetryAvailable,
              let details,
              details.id == failure.instanceIdentifier,
              details.notesEditable else {
            return false
        }

        notesSaveState = .saving
        onSaveNotes?(details.id, draftNotes)
        return true
    }

    func clear() {
        activeIdentifier = nil
        state = .empty
        draftNotes = ""
        notesSaveState = .idle
    }

    private static func notesFailure(for identifier: String, key: String) -> PrismInstanceDetailsFailure {
        PrismInstanceDetailsFailure(
            instanceIdentifier: identifier,
            localizationKey: key,
            substitutionValues: ["instanceIdentifier": identifier],
            diagnosticText: nil,
            recoveryAction: .none,
            partialChangesRolledBack: false
        )
    }
}

enum PrismInstanceJoinTarget: String, CaseIterable, Hashable, Equatable, Sendable {
    case none
    case server
    case world

    var titleKey: String {
        switch self {
        case .none:
            return "Do Not Join"
        case .server:
            return "Server Address"
        case .world:
            return "Singleplayer World"
        }
    }

    var accessibilityLabelKey: String {
        switch self {
        case .none:
            return "Do Not Join On Launch"
        case .server:
            return "Join Server On Launch"
        case .world:
            return "Join World On Launch"
        }
    }
}

struct PrismInstanceSettings: Identifiable, Equatable, Sendable {
    let id: String
    var windowOverrideEnabled: Bool
    var launchMaximized: Bool
    var windowWidth: Int
    var windowHeight: Int
    var closeAfterLaunch: Bool
    var quitAfterGameStop: Bool
    var consoleOverrideEnabled: Bool
    var showConsole: Bool
    var showConsoleOnError: Bool
    var autoCloseConsole: Bool
    var globalDataPacksEnabled: Bool
    var globalDataPacksPath: String
    var gameTimeOverrideEnabled: Bool
    var showGameTime: Bool
    var recordGameTime: Bool
    var countGameTime: Bool
    var joinServerOnLaunch: Bool
    var joinTarget: PrismInstanceJoinTarget
    var joinServerAddress: String
    var joinWorld: String
    var overrideModDownloadLoaders: Bool
    var modDownloadLoaders: [String]
    var javaLocationOverrideEnabled: Bool
    var javaPath: String
    var ignoreJavaCompatibility: Bool
    var memoryOverrideEnabled: Bool
    var minMemoryMiB: Int
    var maxMemoryMiB: Int
    var permGenMiB: Int
    var lowMemoryWarning: Bool
    var javaArgumentsOverrideEnabled: Bool
    var jvmArguments: String
    var commandOverrideEnabled: Bool
    var preLaunchCommand: String
    var wrapperCommand: String
    var postExitCommand: String
    var legacySettingsOverrideEnabled: Bool
    var onlineFixes: Bool
    var nativeWorkaroundsOverrideEnabled: Bool
    var useNativeGLFW: Bool
    var customGLFWPath: String
    var useNativeOpenAL: Bool
    var customOpenALPath: String

    init?(bridgeSettings: PRInstanceSettings) {
        let identifier = bridgeSettings.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let loaders = bridgeSettings.modDownloadLoaders.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !identifier.isEmpty,
              (1...65_536).contains(bridgeSettings.windowWidth),
              (1...65_536).contains(bridgeSettings.windowHeight),
              (8...1_048_576).contains(bridgeSettings.minMemoryMiB),
              (8...1_048_576).contains(bridgeSettings.maxMemoryMiB),
              bridgeSettings.minMemoryMiB <= bridgeSettings.maxMemoryMiB,
              (4...1_048_576).contains(bridgeSettings.permGenMiB),
              loaders.allSatisfy({ !$0.isEmpty }),
              Set(loaders).count == loaders.count,
              let joinTarget = Self.joinTarget(from: bridgeSettings.joinTarget) else {
            return nil
        }

        self.init(
            id: identifier,
            windowOverrideEnabled: bridgeSettings.windowOverrideEnabled,
            launchMaximized: bridgeSettings.launchMaximized,
            windowWidth: bridgeSettings.windowWidth,
            windowHeight: bridgeSettings.windowHeight,
            closeAfterLaunch: bridgeSettings.closeAfterLaunch,
            quitAfterGameStop: bridgeSettings.quitAfterGameStop,
            consoleOverrideEnabled: bridgeSettings.consoleOverrideEnabled,
            showConsole: bridgeSettings.showConsole,
            showConsoleOnError: bridgeSettings.showConsoleOnError,
            autoCloseConsole: bridgeSettings.autoCloseConsole,
            globalDataPacksEnabled: bridgeSettings.globalDataPacksEnabled,
            globalDataPacksPath: bridgeSettings.globalDataPacksPath,
            gameTimeOverrideEnabled: bridgeSettings.gameTimeOverrideEnabled,
            showGameTime: bridgeSettings.showGameTime,
            recordGameTime: bridgeSettings.recordGameTime,
            countGameTime: bridgeSettings.countGameTime,
            joinServerOnLaunch: bridgeSettings.joinServerOnLaunch,
            joinTarget: joinTarget,
            joinServerAddress: bridgeSettings.joinServerAddress,
            joinWorld: bridgeSettings.joinWorld,
            overrideModDownloadLoaders: bridgeSettings.overrideModDownloadLoaders,
            modDownloadLoaders: loaders,
            javaLocationOverrideEnabled: bridgeSettings.javaLocationOverrideEnabled,
            javaPath: bridgeSettings.javaPath,
            ignoreJavaCompatibility: bridgeSettings.ignoreJavaCompatibility,
            memoryOverrideEnabled: bridgeSettings.memoryOverrideEnabled,
            minMemoryMiB: bridgeSettings.minMemoryMiB,
            maxMemoryMiB: bridgeSettings.maxMemoryMiB,
            permGenMiB: bridgeSettings.permGenMiB,
            lowMemoryWarning: bridgeSettings.lowMemoryWarning,
            javaArgumentsOverrideEnabled: bridgeSettings.javaArgumentsOverrideEnabled,
            jvmArguments: bridgeSettings.jvmArguments,
            commandOverrideEnabled: bridgeSettings.commandOverrideEnabled,
            preLaunchCommand: bridgeSettings.preLaunchCommand,
            wrapperCommand: bridgeSettings.wrapperCommand,
            postExitCommand: bridgeSettings.postExitCommand,
            legacySettingsOverrideEnabled: bridgeSettings.legacySettingsOverrideEnabled,
            onlineFixes: bridgeSettings.onlineFixes,
            nativeWorkaroundsOverrideEnabled: bridgeSettings.nativeWorkaroundsOverrideEnabled,
            useNativeGLFW: bridgeSettings.useNativeGLFW,
            customGLFWPath: bridgeSettings.customGLFWPath,
            useNativeOpenAL: bridgeSettings.useNativeOpenAL,
            customOpenALPath: bridgeSettings.customOpenALPath
        )
    }

    init(
        id: String,
        windowOverrideEnabled: Bool,
        launchMaximized: Bool,
        windowWidth: Int,
        windowHeight: Int,
        closeAfterLaunch: Bool,
        quitAfterGameStop: Bool,
        consoleOverrideEnabled: Bool,
        showConsole: Bool,
        showConsoleOnError: Bool,
        autoCloseConsole: Bool,
        globalDataPacksEnabled: Bool,
        globalDataPacksPath: String,
        gameTimeOverrideEnabled: Bool,
        showGameTime: Bool,
        recordGameTime: Bool,
        countGameTime: Bool,
        joinServerOnLaunch: Bool,
        joinTarget: PrismInstanceJoinTarget,
        joinServerAddress: String,
        joinWorld: String,
        overrideModDownloadLoaders: Bool,
        modDownloadLoaders: [String],
        javaLocationOverrideEnabled: Bool,
        javaPath: String,
        ignoreJavaCompatibility: Bool,
        memoryOverrideEnabled: Bool,
        minMemoryMiB: Int,
        maxMemoryMiB: Int,
        permGenMiB: Int,
        lowMemoryWarning: Bool,
        javaArgumentsOverrideEnabled: Bool,
        jvmArguments: String,
        commandOverrideEnabled: Bool,
        preLaunchCommand: String,
        wrapperCommand: String,
        postExitCommand: String,
        legacySettingsOverrideEnabled: Bool,
        onlineFixes: Bool,
        nativeWorkaroundsOverrideEnabled: Bool,
        useNativeGLFW: Bool,
        customGLFWPath: String,
        useNativeOpenAL: Bool,
        customOpenALPath: String
    ) {
        self.id = id
        self.windowOverrideEnabled = windowOverrideEnabled
        self.launchMaximized = launchMaximized
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.closeAfterLaunch = closeAfterLaunch
        self.quitAfterGameStop = quitAfterGameStop
        self.consoleOverrideEnabled = consoleOverrideEnabled
        self.showConsole = showConsole
        self.showConsoleOnError = showConsoleOnError
        self.autoCloseConsole = autoCloseConsole
        self.globalDataPacksEnabled = globalDataPacksEnabled
        self.globalDataPacksPath = globalDataPacksPath
        self.gameTimeOverrideEnabled = gameTimeOverrideEnabled
        self.showGameTime = showGameTime
        self.recordGameTime = recordGameTime
        self.countGameTime = countGameTime
        self.joinServerOnLaunch = joinServerOnLaunch
        self.joinTarget = joinTarget
        self.joinServerAddress = joinServerAddress
        self.joinWorld = joinWorld
        self.overrideModDownloadLoaders = overrideModDownloadLoaders
        self.modDownloadLoaders = modDownloadLoaders
        self.javaLocationOverrideEnabled = javaLocationOverrideEnabled
        self.javaPath = javaPath
        self.ignoreJavaCompatibility = ignoreJavaCompatibility
        self.memoryOverrideEnabled = memoryOverrideEnabled
        self.minMemoryMiB = minMemoryMiB
        self.maxMemoryMiB = maxMemoryMiB
        self.permGenMiB = permGenMiB
        self.lowMemoryWarning = lowMemoryWarning
        self.javaArgumentsOverrideEnabled = javaArgumentsOverrideEnabled
        self.jvmArguments = jvmArguments
        self.commandOverrideEnabled = commandOverrideEnabled
        self.preLaunchCommand = preLaunchCommand
        self.wrapperCommand = wrapperCommand
        self.postExitCommand = postExitCommand
        self.legacySettingsOverrideEnabled = legacySettingsOverrideEnabled
        self.onlineFixes = onlineFixes
        self.nativeWorkaroundsOverrideEnabled = nativeWorkaroundsOverrideEnabled
        self.useNativeGLFW = useNativeGLFW
        self.customGLFWPath = customGLFWPath
        self.useNativeOpenAL = useNativeOpenAL
        self.customOpenALPath = customOpenALPath
    }

    private static func joinTarget(from value: PRInstanceJoinTarget) -> PrismInstanceJoinTarget? {
        switch value {
        case .none:
            return PrismInstanceJoinTarget.none
        case .server:
            return .server
        case .world:
            return .world
        @unknown default:
            return nil
        }
    }
}

enum PrismInstanceSettingsState: Equatable, Sendable {
    case loading(identifier: String)
    case empty
    case failed(PrismInstanceDetailsFailure)
    case content(PrismInstanceSettings)
}

enum PrismInstanceSettingsSaveState: Equatable, Sendable {
    case idle
    case saving
    case failed(PrismInstanceDetailsFailure)
}

@MainActor
final class PrismInstanceSettingsModel: ObservableObject {
    @Published private(set) var state: PrismInstanceSettingsState = .empty
    @Published private(set) var draft: PrismInstanceSettings?
    @Published private(set) var saveState: PrismInstanceSettingsSaveState = .idle

    private let onLoad: ((String) -> Void)?
    private let onSave: ((String, PrismInstanceSettings) -> Void)?
    private var activeIdentifier: String?

    init(
        onLoad: ((String) -> Void)? = nil,
        onSave: ((String, PrismInstanceSettings) -> Void)? = nil
    ) {
        self.onLoad = onLoad
        self.onSave = onSave
    }

    var settings: PrismInstanceSettings? {
        guard case .content(let settings) = state else {
            return nil
        }
        return settings
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    var isSaveAvailable: Bool {
        guard let settings, let draft, saveState != .saving else {
            return false
        }
        return settings != draft
    }

    var saveFailure: PrismInstanceDetailsFailure? {
        guard case .failed(let failure) = saveState else {
            return nil
        }
        return failure
    }

    @discardableResult
    func beginLoading(identifier: String) -> Bool {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            return false
        }

        activeIdentifier = normalizedIdentifier
        state = .loading(identifier: normalizedIdentifier)
        draft = nil
        saveState = .idle
        onLoad?(normalizedIdentifier)
        return true
    }

    @discardableResult
    func apply(settings bridgeSettings: PRInstanceSettings) -> Bool {
        guard let settings = PrismInstanceSettings(bridgeSettings: bridgeSettings) else {
            return false
        }

        activeIdentifier = settings.id
        state = .content(settings)
        draft = settings
        saveState = .idle
        return true
    }

    @discardableResult
    func apply(updateResult bridgeResult: PRInstanceSettingsUpdateResult) -> Bool {
        let identifier = bridgeResult.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              let settings,
              settings.id == identifier,
              saveState == .saving else {
            return false
        }

        switch bridgeResult.outcome {
        case .succeeded:
            guard let confirmed = bridgeResult.settings,
                  let mapped = PrismInstanceSettings(bridgeSettings: confirmed) else {
                return false
            }
            state = .content(mapped)
            draft = mapped
            saveState = .idle
        case .unknownInstance:
            saveState = .failed(Self.saveFailure(for: identifier, key: "instance.settings.instanceMissing"))
        case .rejected:
            saveState = .failed(Self.saveFailure(for: identifier, key: "instance.settings.updateRejected"))
        @unknown default:
            return false
        }
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, instanceIdentifier: String) -> Bool {
        let normalizedIdentifier = instanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty, !localizationKey.isEmpty else {
            return false
        }

        let failure = PrismInstanceDetailsFailure(
            instanceIdentifier: normalizedIdentifier,
            localizationKey: localizationKey,
            substitutionValues: error.substitutionValues,
            diagnosticText: error.diagnosticText,
            recoveryAction: error.recoveryKind == .retry ? .retry : .none,
            partialChangesRolledBack: error.partialChangesRolledBack
        )

        if isLoading {
            state = .failed(failure)
            draft = nil
            saveState = .idle
        } else if activeIdentifier == normalizedIdentifier && settings != nil && saveState == .saving {
            saveState = .failed(failure)
        } else {
            activeIdentifier = normalizedIdentifier
            state = .failed(failure)
            draft = nil
            saveState = .idle
        }
        return true
    }

    func updateDraft(_ update: (inout PrismInstanceSettings) -> Void) {
        guard saveState != .saving, var draft else {
            return
        }
        update(&draft)
        self.draft = draft
        if case .failed = saveState {
            saveState = .idle
        }
    }

    @discardableResult
    func save() -> Bool {
        guard let settings, let draft, isSaveAvailable else {
            return false
        }

        saveState = .saving
        onSave?(settings.id, draft)
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard case .failed(let failure) = state, failure.isRetryAvailable else {
            return false
        }
        return beginLoading(identifier: failure.instanceIdentifier)
    }

    @discardableResult
    func retrySave() -> Bool {
        guard case .failed(let failure) = saveState,
              failure.isRetryAvailable,
              let settings,
              let draft,
              settings.id == failure.instanceIdentifier else {
            return false
        }

        saveState = .saving
        onSave?(settings.id, draft)
        return true
    }

    func clear() {
        activeIdentifier = nil
        state = .empty
        draft = nil
        saveState = .idle
    }

    private static func saveFailure(for identifier: String, key: String) -> PrismInstanceDetailsFailure {
        PrismInstanceDetailsFailure(
            instanceIdentifier: identifier,
            localizationKey: key,
            substitutionValues: ["instanceIdentifier": identifier],
            diagnosticText: nil,
            recoveryAction: .none,
            partialChangesRolledBack: false
        )
    }
}

@MainActor
final class PrismInstanceArtworkStore {
    static let defaultItemLimit = 32
    static let defaultTotalByteLimit = 8 * 1024 * 1024

    let itemLimit: Int
    let totalByteLimit: Int

    private struct Entry {
        let image: NSImage
        let byteCount: Int
    }

    private var entries: [String: Entry] = [:]
    private var accessOrder: [String] = []
    private(set) var cachedByteCount = 0

    var cachedIdentifiers: [String] {
        accessOrder
    }

    init?(
        maxItemCount: Int = PrismInstanceArtworkStore.defaultItemLimit,
        maxTotalBytes: Int = PrismInstanceArtworkStore.defaultTotalByteLimit
    ) {
        guard maxItemCount > 0, maxTotalBytes > 0 else {
            return nil
        }

        itemLimit = maxItemCount
        totalByteLimit = maxTotalBytes
    }

    func image(for instanceID: String, from url: URL) -> NSImage? {
        guard let normalizedID = Self.normalizedIdentifier(instanceID), url.isFileURL else {
            return nil
        }

        if let cachedEntry = entries[normalizedID] {
            touch(normalizedID)
            return cachedEntry.image
        }

        guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = resourceValues.fileSize,
              fileSize > 0,
              fileSize <= totalByteLimit,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              !data.isEmpty,
              data.count <= totalByteLimit,
              let image = NSImage(data: data) else {
            return nil
        }

        entries[normalizedID] = Entry(image: image, byteCount: data.count)
        cachedByteCount += data.count
        touch(normalizedID)
        trimToLimits()
        return image
    }

    func removeArtwork(for instanceID: String) {
        guard let normalizedID = Self.normalizedIdentifier(instanceID) else {
            return
        }

        guard let removedEntry = entries.removeValue(forKey: normalizedID) else {
            return
        }

        cachedByteCount -= removedEntry.byteCount
        accessOrder.removeAll { $0 == normalizedID }
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: true)
        accessOrder.removeAll(keepingCapacity: true)
        cachedByteCount = 0
    }

    private func touch(_ identifier: String) {
        accessOrder.removeAll { $0 == identifier }
        accessOrder.append(identifier)
    }

    private func trimToLimits() {
        while entries.count > itemLimit || cachedByteCount > totalByteLimit {
            guard let leastRecentlyUsed = accessOrder.first else {
                return
            }
            accessOrder.removeFirst()
            if let removedEntry = entries.removeValue(forKey: leastRecentlyUsed) {
                cachedByteCount -= removedEntry.byteCount
            }
        }
    }

    private static func normalizedIdentifier(_ identifier: String) -> String? {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum PrismTaskState: String, CaseIterable, Equatable, Sendable {
    case queued
    case running
    case cancelling
    case succeeded
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled:
            return true
        case .queued, .running, .cancelling:
            return false
        }
    }

    var titleKey: String {
        switch self {
        case .queued:
            return "Queued"
        case .running:
            return "In Progress"
        case .cancelling:
            return "Cancelling"
        case .succeeded:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var accessibilityValueKey: String {
        switch self {
        case .queued:
            return "Task is queued."
        case .running:
            return "Task is in progress."
        case .cancelling:
            return "Task cancellation is in progress."
        case .succeeded:
            return "Task completed successfully."
        case .failed:
            return "Task failed."
        case .cancelled:
            return "Task was cancelled."
        }
    }

    var systemImage: String {
        switch self {
        case .queued:
            return "clock"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .cancelling:
            return "xmark.circle"
        case .succeeded:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        case .cancelled:
            return "minus.circle"
        }
    }

    init?(bridgeState: PRTaskState) {
        switch bridgeState {
        case .queued:
            self = .queued
        case .running:
            self = .running
        case .cancelling:
            self = .cancelling
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        @unknown default:
            return nil
        }
    }
}

enum PrismTaskProgress: Equatable, Sendable {
    case none
    case indeterminate
    case determinate(Double)

    init?(bridgeKind: PRTaskProgressKind, fraction: Double) {
        guard fraction.isFinite else {
            return nil
        }

        switch bridgeKind {
        case .none:
            guard fraction == 0 else { return nil }
            self = .none
        case .indeterminate:
            guard fraction == 0 else { return nil }
            self = .indeterminate
        case .determinate:
            guard (0...1).contains(fraction) else { return nil }
            self = .determinate(fraction)
        @unknown default:
            return nil
        }
    }

    var fraction: Double? {
        if case let .determinate(value) = self {
            return value
        }
        return nil
    }

    var accessibilityValueKey: String {
        switch self {
        case .none:
            return "No progress is reported."
        case .indeterminate:
            return "Progress is indeterminate."
        case .determinate:
            return "Progress is determinate."
        }
    }
}

struct PrismTaskSubtaskPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let state: PrismTaskState
    let progress: PrismTaskProgress

    init?(bridgeStatus: PRTaskSubtaskStatus) {
        let identifier = bridgeStatus.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = bridgeStatus.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              !name.isEmpty,
              let state = PrismTaskState(bridgeState: bridgeStatus.state),
              let progress = PrismTaskProgress(
                  bridgeKind: bridgeStatus.progressKind,
                  fraction: bridgeStatus.progressFraction
              ) else {
            return nil
        }

        self.id = identifier
        self.name = name
        self.state = state
        self.progress = progress
    }
}

enum PrismTaskTerminalOutcome: String, Equatable, Sendable {
    case succeeded
    case failed
    case cancelled

    init?(bridgeOutcome: PRTaskTerminalOutcome) {
        switch bridgeOutcome {
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        @unknown default:
            return nil
        }
    }
}

struct PrismTaskTerminalPresentation: Equatable, Sendable {
    let outcome: PrismTaskTerminalOutcome
    let localizationKey: String
    let substitutionValues: [String: String]
    let diagnosticText: String?
    let partialChangesRolledBack: Bool

    init?(bridgeResult: PRTaskTerminalResult) {
        let localizationKey = bridgeResult.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localizationKey.isEmpty,
              let outcome = PrismTaskTerminalOutcome(bridgeOutcome: bridgeResult.outcome) else {
            return nil
        }

        self.outcome = outcome
        self.localizationKey = localizationKey
        self.substitutionValues = bridgeResult.substitutionValues
        self.diagnosticText = bridgeResult.diagnosticText
        self.partialChangesRolledBack = bridgeResult.partialChangesRolledBack
    }
}

struct PrismTaskPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let state: PrismTaskState
    let progress: PrismTaskProgress
    let cancellationAllowed: Bool
    let subtasks: [PrismTaskSubtaskPresentation]
    let terminalResult: PrismTaskTerminalPresentation?

    var canCancel: Bool {
        cancellationAllowed && (state == .queued || state == .running)
    }

    init?(bridgeStatus: PRTaskStatus) {
        let identifier = bridgeStatus.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              let state = PrismTaskState(bridgeState: bridgeStatus.state),
              let progress = PrismTaskProgress(
                  bridgeKind: bridgeStatus.progressKind,
                  fraction: bridgeStatus.progressFraction
              ) else {
            return nil
        }

        let subtasks = bridgeStatus.subtasks.compactMap(PrismTaskSubtaskPresentation.init(bridgeStatus:))
        guard subtasks.count == bridgeStatus.subtasks.count,
              Set(subtasks.map(\.id)).count == subtasks.count else {
            return nil
        }

        let terminalResult: PrismTaskTerminalPresentation?
        if let bridgeResult = bridgeStatus.terminalResult {
            guard let mappedResult = PrismTaskTerminalPresentation(bridgeResult: bridgeResult) else {
                return nil
            }
            terminalResult = mappedResult
        } else {
            terminalResult = nil
        }

        guard (terminalResult != nil) == state.isTerminal else {
            return nil
        }
        if let terminalResult {
            let matchesState = (state == .succeeded && terminalResult.outcome == .succeeded)
                || (state == .failed && terminalResult.outcome == .failed)
                || (state == .cancelled && terminalResult.outcome == .cancelled)
            guard matchesState else {
                return nil
            }
        }

        self.id = identifier
        self.title = bridgeStatus.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? bridgeStatus.title!
            : identifier
        self.state = state
        self.progress = progress
        self.cancellationAllowed = bridgeStatus.cancellationAllowed
        self.subtasks = subtasks
        self.terminalResult = terminalResult
    }
}

enum PrismTaskRecoveryAction: String, Equatable, Sendable {
    case retry
    case none
}

struct PrismTaskPresentationFailure: Equatable, Sendable {
    let taskIdentifier: String
    let localizationKey: String
    let substitutionValues: [String: String]
    let diagnosticText: String?
    let recoveryAction: PrismTaskRecoveryAction
    let partialChangesRolledBack: Bool

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }
}

@MainActor
final class PrismTaskPresentationModel: ObservableObject {
    @Published private(set) var task: PrismTaskPresentation?
    @Published private(set) var failure: PrismTaskPresentationFailure?
    private(set) var cancellationPending = false
    private let onTaskCommand: ((PrismTaskCommandIntent) -> Void)?

    init(onTaskCommand: ((PrismTaskCommandIntent) -> Void)? = nil) {
        self.onTaskCommand = onTaskCommand
    }

    var isCancellationAvailable: Bool {
        task?.canCancel == true && !cancellationPending
    }

    var isRetryAvailable: Bool {
        failure?.isRetryAvailable == true
    }

    @discardableResult
    func apply(status: PRTaskStatus) -> Bool {
        guard let presentation = PrismTaskPresentation(bridgeStatus: status) else {
            return false
        }

        if presentation.id != task?.id || presentation.state == .cancelling || presentation.state.isTerminal {
            cancellationPending = false
        }
        task = presentation
        failure = nil
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, taskIdentifier: String) -> Bool {
        let normalizedIdentifier = taskIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty, !localizationKey.isEmpty else {
            return false
        }

        let recoveryAction: PrismTaskRecoveryAction = error.recoveryKind == .retry ? .retry : .none
        return apply(
            failure: PrismTaskPresentationFailure(
                taskIdentifier: normalizedIdentifier,
                localizationKey: localizationKey,
                substitutionValues: error.substitutionValues,
                diagnosticText: error.diagnosticText,
                recoveryAction: recoveryAction,
                partialChangesRolledBack: error.partialChangesRolledBack
            )
        )
    }

    @discardableResult
    func apply(failure: PrismTaskPresentationFailure) -> Bool {
        guard !failure.taskIdentifier.isEmpty, !failure.localizationKey.isEmpty else {
            return false
        }

        task = nil
        self.failure = failure
        cancellationPending = false
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard let task, isCancellationAvailable else {
            return false
        }

        cancellationPending = true
        onTaskCommand?(PrismTaskCommandIntent(action: .cancel, identifier: task.id))
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard let failure, failure.isRetryAvailable else {
            return false
        }

        self.failure = nil
        onTaskCommand?(PrismTaskCommandIntent(action: .retry, identifier: failure.taskIdentifier))
        return true
    }

    func clear() {
        task = nil
        failure = nil
        cancellationPending = false
    }
}

struct PrismTaskLogEntry: Identifiable, Equatable, Sendable {
    let id: UInt64
    let text: String
    let isTruncated: Bool

    init?(bridgeEntry: PRTaskLogEntry) {
        guard !bridgeEntry.text.contains("\u{0}") else {
            return nil
        }

        self.id = bridgeEntry.sequence
        self.text = bridgeEntry.text
        self.isTruncated = bridgeEntry.truncated
    }
}

struct PrismTaskLogPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let entries: [PrismTaskLogEntry]
    let droppedEntryCount: UInt64
    let totalByteCount: UInt64
    let isTruncated: Bool

    var renderedText: String {
        entries.map(\.text).joined(separator: "\n")
    }

    init?(bridgeSnapshot: PRTaskLogSnapshot) {
        let taskIdentifier = bridgeSnapshot.taskIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskIdentifier.isEmpty else {
            return nil
        }

        let entries = bridgeSnapshot.entries.compactMap(PrismTaskLogEntry.init(bridgeEntry:))
        let calculatedByteCount = entries.reduce(into: UInt64(0)) {
            $0 += UInt64($1.text.utf8.count)
        }
        guard entries.count == bridgeSnapshot.entries.count,
              Set(entries.map(\.id)).count == entries.count,
              bridgeSnapshot.totalByteCount == calculatedByteCount,
              bridgeSnapshot.truncated || (bridgeSnapshot.droppedEntryCount == 0 && entries.allSatisfy { !$0.isTruncated }) else {
            return nil
        }

        self.id = taskIdentifier
        self.entries = entries
        self.droppedEntryCount = bridgeSnapshot.droppedEntryCount
        self.totalByteCount = bridgeSnapshot.totalByteCount
        self.isTruncated = bridgeSnapshot.truncated
    }
}

struct PrismTaskLogFailure: Equatable, Sendable {
    let taskIdentifier: String
    let localizationKey: String
    let substitutionValues: [String: String]
    let diagnosticText: String?
    let isRetryAvailable: Bool
}

@MainActor
final class PrismTaskLogPresentationModel: ObservableObject {
    @Published private(set) var log: PrismTaskLogPresentation?
    @Published private(set) var failure: PrismTaskLogFailure?
    private let onRetry: ((String) -> Void)?

    init(onRetry: ((String) -> Void)? = nil) {
        self.onRetry = onRetry
    }

    @discardableResult
    func apply(snapshot: PRTaskLogSnapshot) -> Bool {
        guard let presentation = PrismTaskLogPresentation(bridgeSnapshot: snapshot) else {
            return false
        }

        log = presentation
        failure = nil
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, taskIdentifier: String) -> Bool {
        let normalizedIdentifier = taskIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty, !localizationKey.isEmpty else {
            return false
        }

        log = nil
        failure = PrismTaskLogFailure(
            taskIdentifier: normalizedIdentifier,
            localizationKey: localizationKey,
            substitutionValues: error.substitutionValues,
            diagnosticText: error.diagnosticText,
            isRetryAvailable: error.recoveryKind == .retry
        )
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard let failure, failure.isRetryAvailable else {
            return false
        }

        self.failure = nil
        onRetry?(failure.taskIdentifier)
        return true
    }

    func clear() {
        log = nil
        failure = nil
    }
}

enum PrismInstanceGrouping: String, CaseIterable, Sendable {
    case none
    case group
}

enum PrismInstanceSortOrder: String, CaseIterable, Sendable {
    case nameAscending
    case nameDescending
}

struct PrismInstanceSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String?
    let instances: [PrismInstanceRow]
}

enum PrismShellSidebarItem: String, CaseIterable, Hashable, Identifiable, Sendable {
    case instances
    case discover

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .instances:
            return "Instances"
        case .discover:
            return "Discover"
        }
    }

    var accessibilityLabelKey: String {
        switch self {
        case .instances:
            return "Instance Library"
        case .discover:
            return "Discover Instances"
        }
    }

    var accessibilityHintKey: String {
        switch self {
        case .instances:
            return "Show your installed instances."
        case .discover:
            return "Show available instance sources."
        }
    }

    var systemImage: String {
        switch self {
        case .instances:
            return "square.grid.2x2"
        case .discover:
            return "safari"
        }
    }
}

enum PrismShellRecoveryAction: String, Equatable, Sendable {
    case retry

    var titleKey: String {
        switch self {
        case .retry:
            return "Retry"
        }
    }

    var accessibilityLabelKey: String {
        switch self {
        case .retry:
            return "Retry Loading Instances"
        }
    }

    var helpKey: String {
        switch self {
        case .retry:
            return "Try loading instances again."
        }
    }
}

struct PrismShellFailure: Equatable, Sendable {
    let titleKey: String
    let messageKey: String
    let recoveryAction: PrismShellRecoveryAction

    static let instanceLoad = Self(
        titleKey: "Unable to Load Instances",
        messageKey: "Try again to load your instances.",
        recoveryAction: .retry
    )
}

enum PrismShellDetailState: Equatable, Sendable {
    case loading
    case empty
    case failed(PrismShellFailure)
    case content
}

@MainActor
final class PrismShellModel: ObservableObject {
    @Published private(set) var selectedSidebarItem: PrismShellSidebarItem? = .instances
    @Published private(set) var detailState: PrismShellDetailState = .empty
    @Published private(set) var instances: [PrismInstanceRow] = []
    @Published private(set) var selectedInstanceID: String?
    @Published private(set) var searchText = ""
    @Published private(set) var grouping: PrismInstanceGrouping = .none
    @Published private(set) var sortOrder: PrismInstanceSortOrder = .nameAscending
    private let onRetry: (() -> Void)?

    init(onRetry: (() -> Void)? = nil) {
        self.onRetry = onRetry
    }

    var recoveryAction: PrismShellRecoveryAction? {
        guard case .failed(let failure) = detailState else {
            return nil
        }
        return failure.recoveryAction
    }

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }

    var visibleInstances: [PrismInstanceRow] {
        visibleInstanceSections.flatMap(\.instances)
    }

    var visibleInstanceSections: [PrismInstanceSection] {
        let matchingInstances = instances
            .filter(matchesSearch)
            .sorted(by: compareInstances)

        guard !matchingInstances.isEmpty else {
            return []
        }

        guard grouping == .group else {
            return [PrismInstanceSection(id: "all", title: nil, instances: matchingInstances)]
        }

        let groupedInstances = Dictionary(grouping: matchingInstances) { instance in
            instance.group ?? "Ungrouped"
        }

        return groupedInstances.keys
            .sorted(by: Self.compareGroupNames)
            .map { groupName in
                PrismInstanceSection(
                    id: "group:\(groupName)",
                    title: groupName,
                    instances: groupedInstances[groupName] ?? []
                )
            }
    }

    func selectSidebarItem(_ item: PrismShellSidebarItem?) {
        selectedSidebarItem = item
    }

    func setDetailState(_ state: PrismShellDetailState) {
        detailState = state
    }

    func retry() {
        guard isRetryAvailable else {
            return
        }
        onRetry?()
    }

    func setInstances(_ instances: [PrismInstanceRow]) {
        var uniqueInstances: [PrismInstanceRow] = []
        var seenIdentifiers = Set<String>()

        for instance in instances where seenIdentifiers.insert(instance.id).inserted {
            uniqueInstances.append(instance)
        }

        self.instances = uniqueInstances

        if let selectedInstanceID, !seenIdentifiers.contains(selectedInstanceID) {
            self.selectedInstanceID = nil
        }
    }

    func selectInstanceID(_ identifier: String?) {
        guard let identifier else {
            selectedInstanceID = nil
            return
        }

        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty,
              instances.contains(where: { $0.id == normalizedIdentifier }) else {
            selectedInstanceID = nil
            return
        }

        selectedInstanceID = normalizedIdentifier
    }

    func setSearchText(_ text: String) {
        searchText = text
    }

    func setGrouping(_ grouping: PrismInstanceGrouping) {
        self.grouping = grouping
    }

    func setSortOrder(_ sortOrder: PrismInstanceSortOrder) {
        self.sortOrder = sortOrder
    }

    private func matchesSearch(_ instance: PrismInstanceRow) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return true
        }

        return instance.name.localizedCaseInsensitiveContains(query)
            || instance.id.localizedCaseInsensitiveContains(query)
            || instance.group?.localizedCaseInsensitiveContains(query) == true
    }

    private func compareInstances(_ lhs: PrismInstanceRow, _ rhs: PrismInstanceRow) -> Bool {
        let lhsKey = Self.sortKey(lhs.name)
        let rhsKey = Self.sortKey(rhs.name)

        if lhsKey == rhsKey {
            return lhs.id < rhs.id
        }

        switch sortOrder {
        case .nameAscending:
            return lhsKey < rhsKey
        case .nameDescending:
            return lhsKey > rhsKey
        }
    }

    private static func compareGroupNames(_ lhs: String, _ rhs: String) -> Bool {
        let lhsKey = sortKey(lhs)
        let rhsKey = sortKey(rhs)
        return lhsKey == rhsKey ? lhs < rhs : lhsKey < rhsKey
    }

    private static func sortKey(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
