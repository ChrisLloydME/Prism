import SwiftUI

@MainActor
struct PrismCommands: Commands {
    @ObservedObject private var model: PrismCommandModel
    @Environment(\.openSettings) private var openSettings

    init(model: PrismCommandModel) {
        _model = ObservedObject(wrappedValue: model)
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
        }

        CommandGroup(after: .undoRedo) {
            PrismCommandButton(model: model, command: .undoDelete, usesKeyboardShortcut: true)
        }

        CommandGroup(replacing: .appSettings) {
            PrismCommandButton(model: model, command: .settings, usesKeyboardShortcut: true) {
                openSettings()
            }
        }

        CommandGroup(replacing: .appInfo) {
            PrismCommandButton(model: model, command: .about, usesKeyboardShortcut: true)
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
