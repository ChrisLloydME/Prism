import SwiftUI

enum PrismCommandID: String, CaseIterable, Hashable, Sendable {
    case newInstance
    case importInstance
    case launchSelected
    case stopSelected
    case editSelected
    case deleteSelected
    case undoDelete
    case settings
    case closeWindow
    case about
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
            id: .settings,
            menu: .app,
            titleKey: "Settings…",
            accessibilityLabelKey: "Settings",
            helpKey: "Open Prism settings.",
            systemImage: "gearshape",
            shortcut: .command(","),
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
    ]

    var onCommand: ((PrismCommandID) -> Void)?

    init(onCommand: ((PrismCommandID) -> Void)? = nil) {
        self.onCommand = onCommand
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
        case .newInstance, .importInstance, .settings, .closeWindow, .about:
            return true
        case .launchSelected, .editSelected, .deleteSelected:
            return selectedInstanceID != nil
        case .stopSelected:
            return selectedInstanceID != nil && selectedInstanceID == runningInstanceID
        case .undoDelete:
            return canUndoDeletion
        }
    }

    @discardableResult
    func invoke(_ command: PrismCommandID) -> Bool {
        guard isEnabled(command) else {
            return false
        }

        lastInvokedCommand = command
        onCommand?(command)
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
