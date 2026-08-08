import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var shellModel = PrismShellModel()
    @StateObject private var logModel = PrismTaskLogPresentationModel()
    @ObservedObject private var commandModel: PrismCommandModel
    @ObservedObject private var taskModel: PrismTaskPresentationModel

    init(commandModel: PrismCommandModel, taskModel: PrismTaskPresentationModel) {
        _commandModel = ObservedObject(wrappedValue: commandModel)
        _taskModel = ObservedObject(wrappedValue: taskModel)
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
                .accessibilityValue(Text(LocalizedStringKey(item.titleKey)))
                .accessibilityHint(Text(LocalizedStringKey(item.accessibilityHintKey)))
                .accessibilityIdentifier("prism.sidebar.\(item.id)")
                .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("Prism")
            .accessibilityIdentifier("prism.instance-library.sidebar")
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                if let task = taskModel.task {
                    PrismTaskProgressView(
                        task: task,
                        cancellationEnabled: taskModel.isCancellationAvailable,
                        onCancel: { _ = taskModel.cancel() }
                    )
                }
                if let failure = taskModel.failure {
                    PrismTaskFailureView(
                        failure: failure,
                        onRetry: { _ = taskModel.retry() }
                    )
                }
                if let log = logModel.log {
                    PrismTaskLogView(log: log)
                }
                if let logFailure = logModel.failure {
                    PrismTaskLogFailureView(failure: logFailure, onRetry: { _ = logModel.retry() })
                }
                PrismShellDetailView(
                    state: shellModel.detailState,
                    onRetry: { shellModel.retry() }
                )
            }
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

@MainActor
struct PrismTaskLogView: View {
    let log: PrismTaskLogPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Task Log", systemImage: "text.alignleft")
                .accessibilityLabel(Text("Task Log"))
                .accessibilityValue(Text(log.accessibilityValueKey))
                .accessibilityIdentifier("prism.task-log.\(log.id).heading")

            if log.isTruncated {
                Label("Older log entries were omitted.", systemImage: "ellipsis")
                    .font(.caption)
                    .accessibilityIdentifier("prism.task-log.\(log.id).truncated")
            }

            if log.entries.isEmpty {
                ContentUnavailableView(
                    "No Log Entries",
                    systemImage: "text.alignleft",
                    description: Text("No output has been recorded for this task.")
                )
                .accessibilityIdentifier("prism.task-log.\(log.id).empty")
            } else {
                PrismTaskLogTextView(text: log.renderedText)
                    .frame(minHeight: 180, idealHeight: 280, maxHeight: 420)
                    .accessibilityLabel(Text("Task Log Output"))
                    .accessibilityValue(Text(log.accessibilityValueKey))
                    .accessibilityIdentifier("prism.task-log.\(log.id).output")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("prism.task-log.\(log.id)")
    }
}

@MainActor
private struct PrismTaskLogTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.string = text
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else {
            return
        }

        textView.string = text
    }
}

private extension PrismTaskLogPresentation {
    var accessibilityValueKey: String {
        if isTruncated {
            return "Task log is truncated."
        }
        return "Task log is complete."
    }
}

@MainActor
private struct PrismTaskLogFailureView: View {
    let failure: PrismTaskLogFailure
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Task Log Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(LocalizedStringKey(failure.localizationKey))
        } actions: {
            if failure.isRetryAvailable {
                Button {
                    onRetry()
                } label: {
                    Text("Retry Loading Log")
                }
                .accessibilityLabel(Text("Retry Loading Log"))
                .help(Text("Try loading this task log again."))
            }
        }
        .accessibilityIdentifier("prism.task-log.failed-state")
    }
}

@MainActor
struct PrismTaskProgressView: View {
    let task: PrismTaskPresentation
    let cancellationEnabled: Bool
    let onCancel: () -> Void

    init(
        task: PrismTaskPresentation,
        cancellationEnabled: Bool? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.task = task
        self.cancellationEnabled = cancellationEnabled ?? task.canCancel
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(task.title)
                } icon: {
                    Image(systemName: task.state.systemImage)
                }
                Spacer()
                if cancellationEnabled {
                    Button {
                        onCancel()
                    } label: {
                        Label("Cancel Task", systemImage: "xmark.circle")
                    }
                    .accessibilityLabel(Text(LocalizedStringKey("Cancel Task")))
                    .help(Text(LocalizedStringKey("Stop this task before it finishes.")))
                    .accessibilityIdentifier("prism.task.cancel")
                }
            }
            .accessibilityValue(Text(LocalizedStringKey(task.state.accessibilityValueKey)))

            Text(LocalizedStringKey(task.state.titleKey))
                .font(.subheadline)
                .accessibilityIdentifier("prism.task.state")

            PrismTaskProgressIndicator(
                progress: task.progress,
                identifier: "prism.task.progress.\(task.id)"
            )

            if !task.subtasks.isEmpty {
                List(task.subtasks) { subtask in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading) {
                            Text(subtask.name)
                            Text(LocalizedStringKey(subtask.state.titleKey))
                                .font(.caption)
                        }
                        Spacer()
                        PrismTaskProgressIndicator(
                            progress: subtask.progress,
                            identifier: "prism.task.progress.\(task.id).\(subtask.id)"
                        )
                    }
                    .accessibilityLabel(Text(subtask.name))
                    .accessibilityValue(Text(LocalizedStringKey(subtask.state.accessibilityValueKey)))
                    .accessibilityIdentifier("prism.task.subtask.\(subtask.id)")
                }
                .listStyle(.inset)
                .frame(minHeight: 0, maxHeight: 180)
            }

            if let terminalResult = task.terminalResult {
                Text(LocalizedStringKey(terminalResult.localizationKey))
                    .accessibilityIdentifier("prism.task.terminal-result")
                if terminalResult.partialChangesRolledBack {
                    Text(LocalizedStringKey("Partial Changes Rolled Back"))
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("prism.task.\(task.id)")
    }
}

@MainActor
private struct PrismTaskProgressIndicator: View {
    let progress: PrismTaskProgress
    let identifier: String

    var body: some View {
        Group {
            switch progress {
            case .none:
                EmptyView()
            case .indeterminate:
                ProgressView()
            case .determinate(let fraction):
                ProgressView(value: fraction)
            }
        }
        .accessibilityValue(Text(LocalizedStringKey(progress.accessibilityValueKey)))
        .accessibilityIdentifier(identifier)
    }
}

@MainActor
private struct PrismTaskFailureView: View {
    let failure: PrismTaskPresentationFailure
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Task Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(LocalizedStringKey(failure.localizationKey))
        } actions: {
            if failure.isRetryAvailable {
                Button {
                    onRetry()
                } label: {
                    Text(LocalizedStringKey("Retry Task"))
                }
                .accessibilityLabel(Text(LocalizedStringKey("Retry Task")))
                .help(Text(LocalizedStringKey("Try this task again.")))
            }
        }
        .accessibilityIdentifier("prism.task.failed-state")
    }
}

@MainActor
struct PrismInstanceArtworkView: View {
    let image: NSImage?
    let accessibilityLabelKey: String

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(Text(LocalizedStringKey(accessibilityLabelKey)))
            } else {
                Image(systemName: "square.grid.2x2")
                    .accessibilityLabel(Text(LocalizedStringKey("No Instance Artwork")))
            }
        }
        .accessibilityIdentifier("prism.instance-artwork")
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
    ContentView(
        commandModel: PrismCommandModel(),
        taskModel: PrismTaskPresentationModel()
    )
}
