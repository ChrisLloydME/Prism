import SwiftUI

@MainActor
struct PrismCommands: Commands {
    @ObservedObject private var model: PrismCommandModel
    @Environment(\.openWindow) private var openWindow
    private let onPrepareShortcut: ((String) -> Void)?

    init(model: PrismCommandModel, onPrepareShortcut: ((String) -> Void)? = nil) {
        _model = ObservedObject(wrappedValue: model)
        self.onPrepareShortcut = onPrepareShortcut
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            PrismCommandButton(model: model, command: .newInstance, usesKeyboardShortcut: true)
            PrismCommandButton(model: model, command: .importInstance, usesKeyboardShortcut: true)
        }

        CommandMenu("Instance") {
            PrismCommandButton(model: model, command: .launchSelected, usesKeyboardShortcut: true)
            PrismCommandButton(model: model, command: .stopSelected, usesKeyboardShortcut: true)
            Divider()
            PrismCommandButton(model: model, command: .editSelected, usesKeyboardShortcut: true)
            PrismCommandButton(model: model, command: .deleteSelected, usesKeyboardShortcut: true)
            PrismCommandButton(model: model, command: .createShortcut, usesKeyboardShortcut: true) {
                if let identifier = model.selectedInstanceID {
                    onPrepareShortcut?(identifier)
                    openWindow(id: "prism.create-shortcut")
                }
            }
        }

        CommandGroup(after: .undoRedo) {
            PrismCommandButton(model: model, command: .undoDelete, usesKeyboardShortcut: true)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: "prism.settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .appInfo) {
            PrismCommandButton(model: model, command: .about, usesKeyboardShortcut: true) {
                openWindow(id: "prism.about")
            }
        }

        CommandGroup(after: .appInfo) {
            PrismCommandButton(model: model, command: .checkForUpdates, usesKeyboardShortcut: true) {
                openWindow(id: "prism.updates")
            }
        }

        CommandGroup(after: .windowArrangement) {
            PrismCommandButton(model: model, command: .closeWindow, usesKeyboardShortcut: true)
        }
    }
}

@MainActor
struct PrismInstanceContextMenu: View {
    @ObservedObject private var model: PrismCommandModel

    init(model: PrismCommandModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        PrismCommandButton(model: model, command: .launchSelected)
        PrismCommandButton(model: model, command: .stopSelected)
        Divider()
        PrismCommandButton(model: model, command: .editSelected)
        PrismCommandButton(model: model, command: .deleteSelected)
    }
}
