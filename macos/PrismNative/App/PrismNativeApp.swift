import SwiftUI

@main
struct PrismNativeApp: App {
    @StateObject private var commandModel = PrismCommandModel()
    @StateObject private var taskModel = PrismTaskPresentationModel()

    var body: some Scene {
        WindowGroup {
            ContentView(commandModel: commandModel, taskModel: taskModel)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            PrismCommands(model: commandModel)
        }

        Settings {
            Text("Settings will move here as the native migration progresses.")
                .padding(24)
                .frame(width: 420)
        }
    }
}
