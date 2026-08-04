import SwiftUI

struct ContentView: View {
    @StateObject private var shellModel = PrismShellModel()

    var body: some View {
        NavigationSplitView {
            List(
                PrismShellSidebarItem.allCases,
                selection: Binding<PrismShellSidebarItem?>(
                    get: { shellModel.selectedSidebarItem },
                    set: { shellModel.selectSidebarItem($0) }
                )
            ) { item in
                Label {
                    Text(LocalizedStringKey(item.titleKey))
                } icon: {
                    Image(systemName: item.systemImage)
                }
                .accessibilityLabel(Text(LocalizedStringKey(item.accessibilityLabelKey)))
                .accessibilityHint(Text(LocalizedStringKey(item.accessibilityHintKey)))
                .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("Prism")
            .accessibilityIdentifier("prism.instance-library.sidebar")
        } detail: {
            PrismShellDetailView(state: shellModel.detailState)
        }
        .searchable(
            text: Binding<String>(
                get: { shellModel.searchText },
                set: { shellModel.setSearchText($0) }
            ),
            prompt: Text("Search Instances")
        )
    }
}

private struct PrismShellDetailView: View {
    let state: PrismShellDetailState

    var body: some View {
        switch state {
        case .loading:
            ProgressView("Loading Instances")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Loading Instances"))
        case .empty:
            ContentUnavailableView(
                "No Instances",
                systemImage: "square.grid.2x2",
                description: Text("Create or import an instance to get started.")
            )
        case .content:
            ContentUnavailableView(
                "Instance Details",
                systemImage: "rectangle.portrait",
                description: Text("Select an instance to view its details.")
            )
        }
    }
}

#Preview {
    ContentView()
}
