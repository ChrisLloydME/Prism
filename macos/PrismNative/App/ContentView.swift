import SwiftUI

struct ContentView: View {
    @StateObject private var shellModel = PrismShellModel()
    @ObservedObject private var commandModel: PrismCommandModel

    init(commandModel: PrismCommandModel) {
        _commandModel = ObservedObject(wrappedValue: commandModel)
    }

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
            PrismShellDetailView(
                state: shellModel.detailState,
                onRetry: { shellModel.retry() }
            )
            .contextMenu {
                PrismInstanceContextMenu(model: commandModel)
            }
        }
        .searchable(
            text: Binding<String>(
                get: { shellModel.searchText },
                set: { shellModel.setSearchText($0) }
            ),
            prompt: Text("Search Instances")
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                PrismCommandButton(model: commandModel, command: .newInstance)
                PrismCommandButton(model: commandModel, command: .importInstance)
            }
            ToolbarItemGroup(placement: .automatic) {
                PrismCommandButton(model: commandModel, command: .launchSelected)
                PrismCommandButton(model: commandModel, command: .stopSelected)
            }
        }
    }
}

private struct PrismShellDetailView: View {
    let state: PrismShellDetailState
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .loading:
            ProgressView("Loading Instances")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Loading Instances"))
                .accessibilityIdentifier("prism.instance-library.loading-state")
        case .empty:
            ContentUnavailableView(
                "No Instances",
                systemImage: "square.grid.2x2",
                description: Text("Create or import an instance to get started.")
            )
            .accessibilityIdentifier("prism.instance-library.empty-state")
        case .failed(let failure):
            ContentUnavailableView {
                Label(LocalizedStringKey(failure.titleKey), systemImage: "exclamationmark.triangle")
            } description: {
                Text(LocalizedStringKey(failure.messageKey))
            } actions: {
                switch failure.recoveryAction {
                case .retry:
                    Button {
                        onRetry()
                    } label: {
                        Text(LocalizedStringKey(failure.recoveryAction.titleKey))
                    }
                    .accessibilityLabel(Text(LocalizedStringKey(failure.recoveryAction.accessibilityLabelKey)))
                    .help(Text(LocalizedStringKey(failure.recoveryAction.helpKey)))
                }
            }
            .accessibilityIdentifier("prism.instance-library.failed-state")
        case .content:
            ContentUnavailableView(
                "Instance Details",
                systemImage: "rectangle.portrait",
                description: Text("Select an instance to view its details.")
            )
            .accessibilityIdentifier("prism.instance-library.content-state")
        }
    }
}

#Preview {
    ContentView(commandModel: PrismCommandModel())
}
