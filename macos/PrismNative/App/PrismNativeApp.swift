import SwiftUI

@main
struct PrismNativeApp: App {
    @StateObject private var commandModel = PrismCommandModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
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
