import SwiftUI

@main
struct PrismNativeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1040, height: 680)

        Settings {
            Text("Settings will move here as the native migration progresses.")
                .padding(24)
                .frame(width: 420)
        }
    }
}
