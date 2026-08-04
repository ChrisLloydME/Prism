import SwiftUI

struct ContentView: View {
    private let identity = PRApplicationIdentity()

    var body: some View {
        NavigationSplitView {
            List {
                Label("Instances", systemImage: "square.grid.2x2")
                Label("Discover", systemImage: "safari")
            }
            .navigationTitle("Prism")
        } detail: {
            ContentUnavailableView(
                "Native UI Ready",
                systemImage: "apple.logo",
                description: Text(identity.applicationSupportDirectory.path)
            )
        }
    }
}

#Preview {
    ContentView()
}
