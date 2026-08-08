import SwiftUI

@main
struct PrismNativeApp: App {
    @StateObject private var commandModel = PrismCommandModel()
    @StateObject private var taskModel = PrismTaskPresentationModel()
    @StateObject private var globalSettingsModel = PrismGlobalSettingsModel()
    @StateObject private var javaDiscoveryModel = PrismJavaDiscoveryModel()

    var body: some Scene {
        WindowGroup {
            ContentView(commandModel: commandModel, taskModel: taskModel)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            PrismCommands(model: commandModel)
        }

        Settings {
            PrismSettingsView(model: globalSettingsModel, javaModel: javaDiscoveryModel)
        }
    }
}
