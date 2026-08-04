import SwiftUI

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

@MainActor
struct PrismCommands: Commands {
    @ObservedObject private var model: PrismCommandModel
    @Environment(\.openSettings) private var openSettings

    init(model: PrismCommandModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            commandButton(.newInstance)
            commandButton(.importInstance)
        }

        CommandMenu("Instance") {
            commandButton(.launchSelected)
            commandButton(.stopSelected)
            Divider()
            commandButton(.editSelected)
            commandButton(.deleteSelected)
        }

        CommandGroup(after: .undoRedo) {
            commandButton(.undoDelete)
        }

        CommandGroup(replacing: .appSettings) {
            commandButton(.settings) {
                openSettings()
            }
        }

        CommandGroup(replacing: .appInfo) {
            commandButton(.about)
        }

        CommandGroup(after: .windowArrangement) {
            commandButton(.closeWindow)
        }
    }

    @ViewBuilder
    private func commandButton(_ command: PrismCommandID, onInvoke: (() -> Void)? = nil) -> some View {
        let descriptor = PrismCommandDescriptor.descriptor(for: command)
        let button = Button {
            guard model.invoke(command) else {
                return
            }
            onInvoke?()
        } label: {
            Text(LocalizedStringKey(descriptor.titleKey))
        }
        .disabled(!model.isEnabled(command))
        .accessibilityLabel(Text(LocalizedStringKey(descriptor.accessibilityLabelKey)))
        .help(Text(LocalizedStringKey(descriptor.helpKey)))

        if let shortcut = descriptor.shortcut {
            button.keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
        } else {
            button
        }
    }
}
