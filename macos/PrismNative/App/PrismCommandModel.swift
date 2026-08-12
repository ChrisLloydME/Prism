import SwiftUI

enum PrismCommandID: String, CaseIterable, Hashable, Sendable {
    case newInstance
    case importInstance
    case launchSelected
    case stopSelected
    case editSelected
    case deleteSelected
    case undoDelete
    case closeWindow
    case about
    case checkForUpdates
    case createShortcut
}

enum PrismCommandMenu: String, Sendable {
    case file
    case instance
    case edit
    case app
    case window
}

struct PrismCommandModifiers: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let command = Self(rawValue: 1 << 0)
    static let shift = Self(rawValue: 1 << 1)
    static let option = Self(rawValue: 1 << 2)
    static let control = Self(rawValue: 1 << 3)
}

enum PrismCommandKey: Equatable, Sendable {
    case character(Character)
    case delete
}

enum PrismInstanceCommandAction: Equatable, Sendable {
    case launch
    case stop
}

struct PrismInstanceCommandIntent: Equatable, Sendable {
    let action: PrismInstanceCommandAction
    let identifier: String
}

enum PrismTaskCommandAction: Equatable, Sendable {
    case cancel
    case retry
}

struct PrismTaskCommandIntent: Equatable, Sendable {
    let action: PrismTaskCommandAction
    let identifier: String
}

struct PrismCommandShortcut: Equatable, Sendable {
    let key: PrismCommandKey
    let modifiers: PrismCommandModifiers

    static func command(_ key: Character) -> Self {
        Self(key: .character(key), modifiers: [.command])
    }

    static let delete = Self(key: .delete, modifiers: [])
}

extension PrismCommandShortcut {
    var keyEquivalent: KeyEquivalent {
        switch key {
        case let .character(character):
            return KeyEquivalent(character)
        case .delete:
            return .delete
        }
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) {
            result.insert(.command)
        }
        if modifiers.contains(.shift) {
            result.insert(.shift)
        }
        if modifiers.contains(.option) {
            result.insert(.option)
        }
        if modifiers.contains(.control) {
            result.insert(.control)
        }
        return result
    }
}

struct PrismCommandDescriptor: Identifiable, Equatable, Sendable {
    let id: PrismCommandID
    let menu: PrismCommandMenu
    let titleKey: String
    let accessibilityLabelKey: String
    let helpKey: String
    let systemImage: String
    let shortcut: PrismCommandShortcut?
    let requiresSelection: Bool

    var accessibilityIdentifier: String {
        "prism.command.\(id.rawValue)"
    }

    static let all: [Self] = [
        Self(
            id: .newInstance,
            menu: .file,
            titleKey: "New Instance…",
            accessibilityLabelKey: "New Instance",
            helpKey: "Create a new instance.",
            systemImage: "plus",
            shortcut: .command("n"),
            requiresSelection: false
        ),
        Self(
            id: .importInstance,
            menu: .file,
            titleKey: "Import Instance…",
            accessibilityLabelKey: "Import Instance",
            helpKey: "Import an instance from a file or supported source.",
            systemImage: "square.and.arrow.down",
            shortcut: nil,
            requiresSelection: false
        ),
        Self(
            id: .launchSelected,
            menu: .instance,
            titleKey: "Launch",
            accessibilityLabelKey: "Launch Selected Instance",
            helpKey: "Launch the selected instance.",
            systemImage: "play.fill",
            shortcut: nil,
            requiresSelection: true
        ),
        Self(
            id: .stopSelected,
            menu: .instance,
            titleKey: "Stop",
            accessibilityLabelKey: "Stop Selected Instance",
            helpKey: "Stop the selected running instance.",
            systemImage: "stop.fill",
            shortcut: nil,
            requiresSelection: true
        ),
        Self(
            id: .editSelected,
            menu: .instance,
            titleKey: "Edit Instance…",
            accessibilityLabelKey: "Edit Selected Instance",
            helpKey: "Edit the selected instance.",
            systemImage: "pencil",
            shortcut: nil,
            requiresSelection: true
        ),
        Self(
            id: .deleteSelected,
            menu: .instance,
            titleKey: "Delete Instance",
            accessibilityLabelKey: "Delete Selected Instance",
            helpKey: "Delete the selected instance.",
            systemImage: "trash",
            shortcut: .delete,
            requiresSelection: true
        ),
        Self(
            id: .undoDelete,
            menu: .edit,
            titleKey: "Undo Last Instance Deletion",
            accessibilityLabelKey: "Undo Last Instance Deletion",
            helpKey: "Restore the most recently deleted instance when recovery is available.",
            systemImage: "arrow.uturn.backward",
            shortcut: nil,
            requiresSelection: false
        ),
        Self(
            id: .closeWindow,
            menu: .window,
            titleKey: "Close Window",
            accessibilityLabelKey: "Close Window",
            helpKey: "Close the current Prism window.",
            systemImage: "xmark",
            shortcut: .command("w"),
            requiresSelection: false
        ),
        Self(
            id: .about,
            menu: .app,
            titleKey: "About Prism",
            accessibilityLabelKey: "About Prism",
            helpKey: "Show information about Prism.",
            systemImage: "info.circle",
            shortcut: nil,
            requiresSelection: false
        ),
        Self(
            id: .checkForUpdates,
            menu: .app,
            titleKey: "Check for Updates…",
            accessibilityLabelKey: "Check for Updates",
            helpKey: "Check whether a newer Prism version is available.",
            systemImage: "arrow.triangle.2.circlepath",
            shortcut: nil,
            requiresSelection: false
        ),
        Self(
            id: .createShortcut,
            menu: .instance,
            titleKey: "Create Shortcut…",
            accessibilityLabelKey: "Create Shortcut for Selected Instance",
            helpKey: "Create a shortcut for the selected instance.",
            systemImage: "link",
            shortcut: nil,
            requiresSelection: true
        ),
    ]

    static func descriptor(for id: PrismCommandID) -> Self {
        guard let descriptor = all.first(where: { $0.id == id }) else {
            preconditionFailure("Missing command descriptor for \(id.rawValue)")
        }
        return descriptor
    }
}

@MainActor
final class PrismCommandModel: ObservableObject {
    @Published private(set) var selectedInstanceID: String?
    @Published private(set) var runningInstanceID: String?
    @Published private(set) var canUndoDeletion = false
    private(set) var lastInvokedCommand: PrismCommandID?
    private let bridge: PRPrismBridge?

    static let toolbarCommandIDs: [PrismCommandID] = [
        .newInstance,
        .importInstance,
        .launchSelected,
        .stopSelected,
    ]

    static let contextMenuCommandIDs: [PrismCommandID] = [
        .launchSelected,
        .stopSelected,
        .editSelected,
        .deleteSelected,
        .createShortcut,
    ]

    var onCommand: ((PrismCommandID) -> Void)?
    var onInstanceCommand: ((PrismInstanceCommandIntent) -> Void)?
    var onDeleteRequest: ((String) -> Void)?

    init(
        onCommand: ((PrismCommandID) -> Void)? = nil,
        onInstanceCommand: ((PrismInstanceCommandIntent) -> Void)? = nil,
        onDeleteRequest: ((String) -> Void)? = nil,
        bridge: PRPrismBridge? = nil
    ) {
        self.bridge = bridge
        self.onCommand = onCommand
        self.onInstanceCommand = onInstanceCommand
        self.onDeleteRequest = onDeleteRequest
    }

    func setSelectedInstanceID(_ identifier: String?) {
        selectedInstanceID = Self.normalizedIdentifier(identifier)
    }

    func setRunningInstanceID(_ identifier: String?) {
        runningInstanceID = Self.normalizedIdentifier(identifier)
    }

    func setCanUndoDeletion(_ canUndo: Bool) {
        canUndoDeletion = canUndo
    }

    func isEnabled(_ command: PrismCommandID) -> Bool {
        switch command {
        case .newInstance, .importInstance, .closeWindow, .about, .checkForUpdates:
            return true
        case .launchSelected, .editSelected, .deleteSelected, .createShortcut:
            return selectedInstanceID != nil
        case .stopSelected:
            return selectedInstanceID != nil && selectedInstanceID == runningInstanceID
        case .undoDelete:
            return canUndoDeletion
        }
    }

    func instanceCommandIntent(for command: PrismCommandID) -> PrismInstanceCommandIntent? {
        guard let identifier = selectedInstanceID else {
            return nil
        }

        switch command {
        case .launchSelected:
            return PrismInstanceCommandIntent(action: .launch, identifier: identifier)
        case .stopSelected:
            return PrismInstanceCommandIntent(action: .stop, identifier: identifier)
        default:
            return nil
        }
    }

    @discardableResult
    func invoke(_ command: PrismCommandID) -> Bool {
        guard isEnabled(command) else {
            return false
        }

        lastInvokedCommand = command
        if command == .deleteSelected, let identifier = selectedInstanceID {
            onDeleteRequest?(identifier)
            if onDeleteRequest == nil {
                onCommand?(command)
            }
            return true
        }
        if let intent = instanceCommandIntent(for: command) {
            if let onInstanceCommand {
                onInstanceCommand(intent)
            } else if let bridge {
                switch intent.action {
                case .launch:
                    _ = bridge.launchInstance(withIdentifier: intent.identifier, completion: { _, _ in })
                case .stop:
                    _ = bridge.stopInstance(withIdentifier: intent.identifier, completion: { _, _ in })
                }
            } else {
                onCommand?(command)
            }
        } else {
            onCommand?(command)
        }
        return true
    }

    private static func normalizedIdentifier(_ identifier: String?) -> String? {
        guard let identifier else {
            return nil
        }
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

struct PrismInstanceDeleteFailure: Equatable, Sendable {
    let instanceIdentifier: String
    let localizationKey: String
    let diagnosticText: String?
    let retryable: Bool
    let partialChangesRolledBack: Bool
}

enum PrismInstanceDeleteState: Equatable, Sendable {
    case idle
    case confirming(identifier: String)
    case deleting(identifier: String)
    case succeeded(identifier: String)
    case failed(PrismInstanceDeleteFailure)
}

@MainActor
final class PrismInstanceDeleteModel: ObservableObject {
    @Published private(set) var state: PrismInstanceDeleteState = .idle

    private let onDelete: ((String) -> Void)?
    private let onCancel: (() -> Void)?

    init(onDelete: ((String) -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var pendingIdentifier: String? {
        guard case .confirming(let identifier) = state else { return nil }
        return identifier
    }

    var isConfirmationPending: Bool { pendingIdentifier != nil }
    var isDeleting: Bool {
        if case .deleting = state { return true }
        return false
    }
    var failure: PrismInstanceDeleteFailure? {
        guard case .failed(let failure) = state else { return nil }
        return failure
    }

    @discardableResult
    func request(identifier: String) -> Bool {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isDeleting else { return false }
        state = .confirming(identifier: normalized)
        return true
    }

    @discardableResult
    func confirm() -> Bool {
        guard case .confirming(let identifier) = state else { return false }
        state = .deleting(identifier: identifier)
        onDelete?(identifier)
        return true
    }

    func cancel() {
        if isDeleting {
            onCancel?()
        }
        state = .idle
    }

    @discardableResult
    func apply(result: PRInstanceDeleteResult) -> Bool {
        guard case .deleting(let identifier) = state,
              result.identifier == identifier else { return false }
        let localizationKey = result.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localizationKey.isEmpty else { return false }
        switch result.outcome {
        case .succeeded:
            state = .succeeded(identifier: identifier)
        case .unknownInstance, .rejected, .failed:
            state = .failed(
                PrismInstanceDeleteFailure(
                    instanceIdentifier: identifier,
                    localizationKey: localizationKey,
                    diagnosticText: result.diagnosticText,
                    retryable: result.retryable,
                    partialChangesRolledBack: result.partialChangesRolledBack
                )
            )
        @unknown default:
            return false
        }
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError) -> Bool {
        guard case .deleting(let identifier) = state else { return false }
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localizationKey.isEmpty else { return false }
        state = .failed(
            PrismInstanceDeleteFailure(
                instanceIdentifier: identifier,
                localizationKey: localizationKey,
                diagnosticText: error.diagnosticText,
                retryable: error.recoveryKind == .retry,
                partialChangesRolledBack: error.partialChangesRolledBack
            )
        )
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard case .failed(let failure) = state, failure.retryable else { return false }
        state = .deleting(identifier: failure.instanceIdentifier)
        onDelete?(failure.instanceIdentifier)
        return true
    }

    func reset() {
        if isDeleting {
            onCancel?()
        }
        state = .idle
    }
}

@MainActor
struct PrismCommandButton: View {
    @ObservedObject private var model: PrismCommandModel
    let command: PrismCommandID
    let usesKeyboardShortcut: Bool
    let onInvoke: (() -> Void)?

    init(
        model: PrismCommandModel,
        command: PrismCommandID,
        usesKeyboardShortcut: Bool = false,
        onInvoke: (() -> Void)? = nil
    ) {
        _model = ObservedObject(wrappedValue: model)
        self.command = command
        self.usesKeyboardShortcut = usesKeyboardShortcut
        self.onInvoke = onInvoke
    }

    @ViewBuilder
    var body: some View {
        let descriptor = PrismCommandDescriptor.descriptor(for: command)
        let button = Button {
            guard model.invoke(command) else {
                return
            }
            onInvoke?()
        } label: {
            Label {
                Text(LocalizedStringKey(descriptor.titleKey))
            } icon: {
                Image(systemName: descriptor.systemImage)
            }
        }
        .disabled(!model.isEnabled(command))
        .accessibilityLabel(Text(LocalizedStringKey(descriptor.accessibilityLabelKey)))
        .accessibilityIdentifier(descriptor.accessibilityIdentifier)
        .help(Text(LocalizedStringKey(descriptor.helpKey)))

        if usesKeyboardShortcut, let shortcut = descriptor.shortcut {
            button.keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
        } else {
            button
        }
    }
}
