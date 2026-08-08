import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var shellModel = PrismShellModel()
    @StateObject private var instanceDetailsModel = PrismInstanceDetailsModel()
    @StateObject private var instanceSettingsModel = PrismInstanceSettingsModel()
    @StateObject private var instanceComponentsModel = PrismInstanceComponentsModel()
    @StateObject private var instanceResourcesModel = PrismInstanceResourcesModel()
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
                if instanceDetailsModel.showsDetail {
                    PrismInstanceDetailsView(
                        model: instanceDetailsModel,
                        settingsModel: instanceSettingsModel,
                        componentsModel: instanceComponentsModel,
                        resourcesModel: instanceResourcesModel
                    )
                } else {
                    PrismShellDetailView(
                        state: shellModel.detailState,
                        onRetry: { shellModel.retry() }
                    )
                }
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

private extension PrismInstanceDetailsModel {
    var showsDetail: Bool {
        switch state {
        case .empty:
            return false
        case .loading, .failed, .content:
            return true
        }
    }
}

@MainActor
private struct PrismInstanceDetailsView: View {
    @ObservedObject var model: PrismInstanceDetailsModel
    @ObservedObject var settingsModel: PrismInstanceSettingsModel
    @ObservedObject var componentsModel: PrismInstanceComponentsModel
    @ObservedObject var resourcesModel: PrismInstanceResourcesModel

    var body: some View {
        switch model.state {
        case .loading:
            ProgressView("Loading Instance Details")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Loading Instance Details"))
                .accessibilityIdentifier("prism.instance-details.loading-state")
        case .empty:
            ContentUnavailableView(
                "No Instance Selected",
                systemImage: "rectangle.portrait",
                description: Text("Select an instance to view its metadata and notes.")
            )
            .accessibilityIdentifier("prism.instance-details.empty-state")
        case .failed(let failure):
            ContentUnavailableView {
                Label(LocalizedStringKey(failure.localizationKey), systemImage: "exclamationmark.triangle")
            } description: {
                Text(LocalizedStringKey(failure.localizationKey))
            } actions: {
                if failure.isRetryAvailable {
                    Button {
                        _ = model.retry()
                    } label: {
                        Text(LocalizedStringKey(failure.recoveryAction.titleKey))
                    }
                    .accessibilityLabel(Text(LocalizedStringKey(failure.recoveryAction.accessibilityLabelKey)))
                    .help(Text(LocalizedStringKey(failure.recoveryAction.helpKey)))
                }
            }
            .accessibilityIdentifier("prism.instance-details.failed-state")
        case .content(let details):
            Form {
                Section("Metadata") {
                    LabeledContent("Name") {
                        Text(details.name)
                            .accessibilityIdentifier("prism.instance-details.name")
                    }
                    if let instanceType = details.instanceType {
                        LabeledContent("Type") {
                            Text(instanceType)
                                .accessibilityIdentifier("prism.instance-details.type")
                        }
                    }
                    if let group = details.group {
                        LabeledContent("Group") {
                            Text(group)
                                .accessibilityIdentifier("prism.instance-details.group")
                        }
                    }
                    LabeledContent("Identifier") {
                        Text(details.id)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("prism.instance-details.identifier")
                    }
                    NavigationLink {
                        PrismInstanceSettingsView(model: settingsModel)
                    } label: {
                        Label("Instance Settings", systemImage: "gearshape")
                    }
                    .accessibilityLabel(Text("Open Instance Settings"))
                    .help(Text("Edit standard settings for this instance."))
                    .accessibilityIdentifier("prism.instance-details.settings-link")
                    NavigationLink {
                        PrismInstanceComponentsView(model: componentsModel)
                    } label: {
                        Label("Versions and Components", systemImage: "shippingbox")
                    }
                    .accessibilityLabel(Text("Open Versions and Components"))
                    .help(Text("Review the ordered versions and components for this instance."))
                    .accessibilityIdentifier("prism.instance-details.components-link")
                    NavigationLink {
                        PrismInstanceResourcesView(model: resourcesModel)
                    } label: {
                        Label("Mods and Pack Resources", systemImage: "archivebox")
                    }
                    .accessibilityLabel(Text("Open Mods and Pack Resources"))
                    .help(Text("Manage mods and pack resources with confirmed actions."))
                    .accessibilityIdentifier("prism.instance-details.resources-link")
                }

                Section("Notes") {
                    TextEditor(
                        text: Binding(
                            get: { model.draftNotes },
                            set: { model.setDraftNotes($0) }
                        )
                    )
                    .frame(minHeight: 180)
                    .disabled(!details.notesEditable || model.notesSaveState == .saving)
                    .accessibilityLabel(Text("Instance Notes"))
                    .accessibilityValue(Text("Editable notes for this instance."))
                    .accessibilityIdentifier("prism.instance-details.notes-editor")

                    HStack {
                        if model.notesSaveState == .saving {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel(Text("Saving Notes"))
                        }
                        Spacer()
                        Button("Save Notes") {
                            _ = model.saveNotes()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.isNotesSaveAvailable)
                        .accessibilityLabel(Text("Save Instance Notes"))
                        .help(Text("Save the edited notes for this instance."))
                        .accessibilityIdentifier("prism.instance-details.save-notes")
                    }

                    if let failure = model.notesFailure {
                        Label {
                            Text(LocalizedStringKey(failure.localizationKey))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .accessibilityValue(Text(failure.diagnosticText ?? "Notes could not be saved."))
                        .accessibilityIdentifier("prism.instance-details.notes-error")
                        if failure.isRetryAvailable {
                            Button {
                                _ = model.retryNotes()
                            } label: {
                                Text(LocalizedStringKey(failure.recoveryAction.titleKey))
                            }
                            .accessibilityLabel(Text(LocalizedStringKey(failure.recoveryAction.accessibilityLabelKey)))
                            .help(Text(LocalizedStringKey(failure.recoveryAction.helpKey)))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(details.name)
            .accessibilityIdentifier("prism.instance-details.form")
        }
    }
}

@MainActor
struct PrismInstanceComponentsView: View {
    @ObservedObject var model: PrismInstanceComponentsModel

    var body: some View {
        switch model.state {
        case .loading:
            ProgressView("Loading Versions and Components")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Loading Versions and Components"))
                .accessibilityIdentifier("prism.instance-components.loading-state")
        case .empty:
            ContentUnavailableView(
                "No Versions or Components",
                systemImage: "shippingbox",
                description: Text("This instance has no version or component entries to display.")
            )
            .accessibilityIdentifier("prism.instance-components.empty-state")
        case .failed(let failure):
            ContentUnavailableView {
                Label(LocalizedStringKey(failure.localizationKey), systemImage: "exclamationmark.triangle")
            } description: {
                Text(LocalizedStringKey(failure.localizationKey))
            } actions: {
                if failure.isRetryAvailable {
                    Button {
                        _ = model.retry()
                    } label: {
                        Text(LocalizedStringKey(failure.recoveryAction.titleKey))
                    }
                    .accessibilityLabel(Text(LocalizedStringKey(failure.recoveryAction.accessibilityLabelKey)))
                    .help(Text(LocalizedStringKey(failure.recoveryAction.helpKey)))
                }
            }
            .accessibilityIdentifier("prism.instance-components.failed-state")
        case .content:
            Table(model.visibleComponents) {
                TableColumn("Name") { component in
                    HStack(spacing: 6) {
                        if let systemImage = component.problemSeverity.systemImage {
                            Image(systemName: systemImage)
                                .accessibilityLabel(Text(LocalizedStringKey(component.problemSeverity.accessibilityLabelKey)))
                        }
                        Text(component.name)
                    }
                    .accessibilityLabel(Text(component.name))
                    .accessibilityValue(Text(LocalizedStringKey(component.accessibilityValueKey)))
                    .accessibilityIdentifier("prism.instance-component.\(component.id).name")
                }
                TableColumn("Version") { component in
                    Text(component.displayVersion)
                        .textSelection(.enabled)
                        .accessibilityLabel(Text("Version"))
                        .accessibilityValue(Text(component.displayVersion))
                        .accessibilityIdentifier("prism.instance-component.\(component.id).version")
                }
                TableColumn("State") { component in
                    Text(LocalizedStringKey(component.stateKey))
                        .accessibilityLabel(Text("Component State"))
                        .accessibilityValue(Text(LocalizedStringKey(component.stateKey)))
                        .accessibilityIdentifier("prism.instance-component.\(component.id).state")
                }
            }
            .searchable(
                text: Binding(
                    get: { model.searchText },
                    set: { model.setSearchText($0) }
                ),
                prompt: Text("Search Versions and Components")
            )
            .navigationTitle("Versions and Components")
            .accessibilityIdentifier("prism.instance-components.table")
        }
    }
}

@MainActor
struct PrismInstanceResourcesView: View {
    @ObservedObject var model: PrismInstanceResourcesModel
    @State private var isImporterPresented = false

    private var tableSelection: Binding<Set<String>> {
        Binding(
            get: {
                guard let selectedResourceID = model.selectedResourceID else {
                    return Set<String>()
                }
                return [selectedResourceID]
            },
            set: { model.selectResource($0.first) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker(
                "Resource Type",
                selection: Binding(
                    get: { model.kind },
                    set: { model.selectKind($0) }
                )
            ) {
                ForEach(PrismInstanceResourceKind.allCases, id: \.self) { kind in
                    Text(LocalizedStringKey(kind.titleKey)).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityLabel(Text("Resource Type"))
            .accessibilityIdentifier("prism.instance-resources.kind-picker")

            switch model.state {
            case .loading:
                ProgressView("Loading Resources")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text("Loading Resources"))
                    .accessibilityIdentifier("prism.instance-resources.loading-state")
            case .empty:
                ContentUnavailableView(
                    "No Resources",
                    systemImage: "archivebox",
                    description: Text("This resource category has no installed entries.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("prism.instance-resources.empty-state")
            case .failed(let failure):
                ContentUnavailableView {
                    Label(LocalizedStringKey(failure.localizationKey), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(LocalizedStringKey(failure.localizationKey))
                } actions: {
                    if failure.recoveryAction == .retry {
                        Button {
                            _ = model.retry()
                        } label: {
                            Text(LocalizedStringKey(failure.recoveryAction.titleKey))
                        }
                        .accessibilityLabel(Text(LocalizedStringKey(failure.recoveryAction.accessibilityLabelKey)))
                        .help(Text(LocalizedStringKey(failure.recoveryAction.helpKey)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("prism.instance-resources.failed-state")
            case .content:
                Table(model.visibleResources, selection: tableSelection) {
                    TableColumn("Name") { resource in
                        HStack(spacing: 6) {
                            if !resource.problemDescriptions.isEmpty {
                                Image(systemName: "exclamationmark.triangle")
                                    .accessibilityLabel(Text("Resource Problem"))
                            }
                            Text(resource.name)
                        }
                        .accessibilityLabel(Text(resource.name))
                        .accessibilityValue(Text(LocalizedStringKey(resource.accessibilityValueKey)))
                        .accessibilityIdentifier("prism.instance-resource.\(resource.id).name")
                    }
                    TableColumn("Version") { resource in
                        Text(resource.displayVersion)
                            .textSelection(.enabled)
                            .accessibilityLabel(Text("Version"))
                            .accessibilityValue(Text(resource.displayVersion))
                            .accessibilityIdentifier("prism.instance-resource.\(resource.id).version")
                    }
                    TableColumn("Provider") { resource in
                        Text(resource.provider.isEmpty ? "Not Available" : resource.provider)
                            .accessibilityLabel(Text("Provider"))
                            .accessibilityIdentifier("prism.instance-resource.\(resource.id).provider")
                    }
                    TableColumn("State") { resource in
                        Toggle(
                            "Enabled",
                            isOn: Binding(
                                get: { resource.enabled },
                                set: { _ = model.setEnabled($0, for: resource.id) }
                            )
                        )
                        .labelsHidden()
                        .disabled(!resource.canBeToggled)
                        .accessibilityLabel(Text("Resource Enabled State"))
                        .accessibilityValue(Text(LocalizedStringKey(resource.stateKey)))
                        .help(Text("Enable or disable this resource after backend confirmation."))
                        .accessibilityIdentifier("prism.instance-resource.\(resource.id).enabled")
                    }
                    TableColumn("File Name") { resource in
                        Text(resource.fileName)
                            .textSelection(.enabled)
                            .accessibilityLabel(Text("File Name"))
                            .accessibilityValue(Text(resource.fileName))
                            .accessibilityIdentifier("prism.instance-resource.\(resource.id).file-name")
                    }
                }
                .searchable(
                    text: Binding(
                        get: { model.searchText },
                        set: { model.setSearchText($0) }
                    ),
                    prompt: Text("Search Resources")
                )
                .accessibilityIdentifier("prism.instance-resources.table")
            }
        }
        .navigationTitle(LocalizedStringKey(model.kind.titleKey))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Import Resource", systemImage: "plus")
                }
                .help(Text("Import one resource through the system file panel."))
                .accessibilityIdentifier("prism.instance-resources.import")

                if let selectedResourceID = model.selectedResourceID {
                    Button {
                        _ = model.reveal(selectedResourceID)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .help(Text("Reveal the selected resource after backend confirmation."))
                    .accessibilityIdentifier("prism.instance-resources.reveal")

                    Button(role: .destructive) {
                        _ = model.requestDelete(selectedResourceID)
                    } label: {
                        Label("Delete Resource", systemImage: "trash")
                    }
                    .help(Text("Request deletion after explicit confirmation."))
                    .accessibilityIdentifier("prism.instance-resources.delete")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                _ = model.importResources(from: urls)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importResources(from: urls)
        }
        .confirmationDialog(
            "Confirm Resource Removal",
            isPresented: Binding(
                get: { model.pendingDeleteResourceID != nil },
                set: { isPresented in
                    if !isPresented {
                        model.cancelDelete()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                _ = model.confirmDelete()
            }
            Button("Cancel", role: .cancel) {
                model.cancelDelete()
            }
        } message: {
            Text("This may permanently remove the selected resource from the instance folder.")
        }
        .alert(
            "Resource Action Failed",
            isPresented: Binding(
                get: { model.mutationFailure != nil },
                set: { isPresented in
                    if !isPresented {
                        model.dismissMutationFailure()
                    }
                }
            )
        ) {
            if model.mutationFailure?.isRetryAvailable == true {
                Button("Retry") {
                    _ = model.retry()
                }
            }
            Button("Dismiss", role: .cancel) {
                model.dismissMutationFailure()
            }
        } message: {
            if let failure = model.mutationFailure {
                Text(LocalizedStringKey(failure.localizationKey))
            }
        }
    }
}

@MainActor
struct PrismInstanceSettingsView: View {
    @ObservedObject var model: PrismInstanceSettingsModel

    private static let modLoaderOptions = [
        "NeoForge",
        "Forge",
        "Fabric",
        "Quilt",
        "LiteLoader",
        "Babric",
        "BTA",
        "LegacyFabric",
        "Ornithe",
        "Rift",
    ]

    var body: some View {
        switch model.state {
        case .loading:
            ProgressView("Loading Instance Settings")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Loading Instance Settings"))
                .accessibilityIdentifier("prism.instance-settings.loading-state")
        case .empty:
            ContentUnavailableView(
                "No Instance Settings",
                systemImage: "gearshape",
                description: Text("Select an instance to load its settings.")
            )
            .accessibilityIdentifier("prism.instance-settings.empty-state")
        case .failed(let failure):
            ContentUnavailableView {
                Label(LocalizedStringKey(failure.localizationKey), systemImage: "exclamationmark.triangle")
            } description: {
                Text(LocalizedStringKey(failure.localizationKey))
            } actions: {
                if failure.isRetryAvailable {
                    Button {
                        _ = model.retry()
                    } label: {
                        Text(LocalizedStringKey(failure.recoveryAction.titleKey))
                    }
                    .accessibilityLabel(Text(LocalizedStringKey(failure.recoveryAction.accessibilityLabelKey)))
                    .help(Text(LocalizedStringKey(failure.recoveryAction.helpKey)))
                }
            }
            .accessibilityIdentifier("prism.instance-settings.failed-state")
        case .content:
            settingsForm
        }
    }

    @ViewBuilder
    private var settingsForm: some View {
        Form {
            Section("Game Window") {
                Toggle("Override global window settings", isOn: boolBinding(\.windowOverrideEnabled))
                    .help(Text("Use these window settings for this instance."))
                Toggle("Start Minecraft maximized", isOn: boolBinding(\.launchMaximized))
                    .disabled(!isEnabled(\.windowOverrideEnabled))
                Stepper(value: intBinding(\.windowWidth, defaultValue: 854), in: 1...65_536) {
                    LabeledContent("Window Width") {
                        Text("\(model.draft?.windowWidth ?? 854) px")
                    }
                }
                .disabled(!isEnabled(\.windowOverrideEnabled))
                Stepper(value: intBinding(\.windowHeight, defaultValue: 480), in: 1...65_536) {
                    LabeledContent("Window Height") {
                        Text("\(model.draft?.windowHeight ?? 480) px")
                    }
                }
                .disabled(!isEnabled(\.windowOverrideEnabled))
                Toggle("Hide the launcher when the game opens", isOn: boolBinding(\.closeAfterLaunch))
                    .disabled(!isEnabled(\.windowOverrideEnabled))
                Toggle("Quit the launcher when the game closes", isOn: boolBinding(\.quitAfterGameStop))
                    .disabled(!isEnabled(\.windowOverrideEnabled))
            }

            Section("Console Window") {
                Toggle("Override global console settings", isOn: boolBinding(\.consoleOverrideEnabled))
                    .help(Text("Use these console settings for this instance."))
                Toggle("Show the console when the game launches", isOn: boolBinding(\.showConsole))
                    .disabled(!isEnabled(\.consoleOverrideEnabled))
                Toggle("Show the console when the game fails", isOn: boolBinding(\.showConsoleOnError))
                    .disabled(!isEnabled(\.consoleOverrideEnabled))
                Toggle("Hide the console when the game quits", isOn: boolBinding(\.autoCloseConsole))
                    .disabled(!isEnabled(\.consoleOverrideEnabled))
            }

            Section("Global Data Packs") {
                Toggle("Enable global data packs", isOn: boolBinding(\.globalDataPacksEnabled))
                TextField("Folder Path", text: stringBinding(\.globalDataPacksPath))
                    .disabled(!isEnabled(\.globalDataPacksEnabled))
                    .accessibilityLabel(Text("Global Data Packs Folder Path"))
            }

            Section("Game Time") {
                Toggle("Override global game-time settings", isOn: boolBinding(\.gameTimeOverrideEnabled))
                Toggle("Show time spent playing instances", isOn: boolBinding(\.showGameTime))
                    .disabled(!isEnabled(\.gameTimeOverrideEnabled))
                Toggle("Record time spent playing instances", isOn: boolBinding(\.recordGameTime))
                    .disabled(!isEnabled(\.gameTimeOverrideEnabled))
                Toggle("Count this instance in total time", isOn: boolBinding(\.countGameTime))
                    .disabled(!isEnabled(\.gameTimeOverrideEnabled))
            }

            Section("Auto-Join") {
                Toggle("Join a destination when the game launches", isOn: boolBinding(\.joinServerOnLaunch))
                Picker("Destination", selection: joinTargetBinding) {
                    ForEach(PrismInstanceJoinTarget.allCases, id: \.self) { target in
                        Text(LocalizedStringKey(target.titleKey)).tag(target)
                    }
                }
                .disabled(!isEnabled(\.joinServerOnLaunch))
                switch model.draft?.joinTarget {
                case .some(.server):
                    TextField("Server Address", text: stringBinding(\.joinServerAddress))
                        .disabled(!isEnabled(\.joinServerOnLaunch))
                case .some(.world):
                    TextField("Singleplayer World", text: stringBinding(\.joinWorld))
                        .disabled(!isEnabled(\.joinServerOnLaunch))
                case .some(.none), nil:
                    EmptyView()
                }
            }

            Section("Mod Download Loaders") {
                Toggle("Override supported loaders", isOn: boolBinding(\.overrideModDownloadLoaders))
                ForEach(Self.modLoaderOptions, id: \.self) { loader in
                    Toggle(loader, isOn: loaderBinding(loader))
                        .disabled(!isEnabled(\.overrideModDownloadLoaders))
                }
            }

            Section("Java") {
                Toggle("Override Java installation", isOn: boolBinding(\.javaLocationOverrideEnabled))
                TextField("Java Executable", text: stringBinding(\.javaPath))
                    .disabled(!isEnabled(\.javaLocationOverrideEnabled))
                Toggle("Skip Java compatibility checks", isOn: boolBinding(\.ignoreJavaCompatibility))
                    .disabled(!isEnabled(\.javaLocationOverrideEnabled))

                Toggle("Override memory settings", isOn: boolBinding(\.memoryOverrideEnabled))
                Stepper(value: intBinding(\.minMemoryMiB, defaultValue: 512), in: 8...1_048_576, step: 128) {
                    LabeledContent("Minimum Memory") {
                        Text("\(model.draft?.minMemoryMiB ?? 512) MiB")
                    }
                }
                .disabled(!isEnabled(\.memoryOverrideEnabled))
                Stepper(value: intBinding(\.maxMemoryMiB, defaultValue: 1024), in: 8...1_048_576, step: 128) {
                    LabeledContent("Maximum Memory") {
                        Text("\(model.draft?.maxMemoryMiB ?? 1024) MiB")
                    }
                }
                .disabled(!isEnabled(\.memoryOverrideEnabled))
                Stepper(value: intBinding(\.permGenMiB, defaultValue: 128), in: 4...1_048_576, step: 8) {
                    LabeledContent("PermGen Memory") {
                        Text("\(model.draft?.permGenMiB ?? 128) MiB")
                    }
                }
                .disabled(!isEnabled(\.memoryOverrideEnabled))
                Toggle("Warn when memory is unavailable", isOn: boolBinding(\.lowMemoryWarning))
                    .disabled(!isEnabled(\.memoryOverrideEnabled))

                Toggle("Override Java arguments", isOn: boolBinding(\.javaArgumentsOverrideEnabled))
                TextEditor(text: stringBinding(\.jvmArguments))
                    .frame(minHeight: 80)
                    .disabled(!isEnabled(\.javaArgumentsOverrideEnabled))
                    .accessibilityLabel(Text("Java Arguments"))
                    .accessibilityValue(Text("Arguments passed to the Java virtual machine."))
            }

            Section("Custom Commands") {
                Toggle("Override custom commands", isOn: boolBinding(\.commandOverrideEnabled))
                TextField("Pre-Launch Command", text: stringBinding(\.preLaunchCommand))
                    .disabled(!isEnabled(\.commandOverrideEnabled))
                TextField("Wrapper Command", text: stringBinding(\.wrapperCommand))
                    .disabled(!isEnabled(\.commandOverrideEnabled))
                TextField("Post-Exit Command", text: stringBinding(\.postExitCommand))
                    .disabled(!isEnabled(\.commandOverrideEnabled))
            }

            Section("Tweaks") {
                Toggle("Override legacy settings", isOn: boolBinding(\.legacySettingsOverrideEnabled))
                Toggle("Enable online fixes (experimental)", isOn: boolBinding(\.onlineFixes))
                    .disabled(!isEnabled(\.legacySettingsOverrideEnabled))
            }

            Section("Native Libraries") {
                Toggle("Override native library settings", isOn: boolBinding(\.nativeWorkaroundsOverrideEnabled))
                Toggle("Use the system GLFW installation", isOn: boolBinding(\.useNativeGLFW))
                    .disabled(!isEnabled(\.nativeWorkaroundsOverrideEnabled))
                TextField("GLFW Library Path", text: stringBinding(\.customGLFWPath))
                    .disabled(!isEnabled(\.nativeWorkaroundsOverrideEnabled))
                Toggle("Use the system OpenAL installation", isOn: boolBinding(\.useNativeOpenAL))
                    .disabled(!isEnabled(\.nativeWorkaroundsOverrideEnabled))
                TextField("OpenAL Library Path", text: stringBinding(\.customOpenALPath))
                    .disabled(!isEnabled(\.nativeWorkaroundsOverrideEnabled))
            }

            Section {
                HStack {
                    if model.saveState == .saving {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(Text("Saving Instance Settings"))
                    }
                    Spacer()
                    Button("Save Settings") {
                        _ = model.save()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isSaveAvailable)
                    .accessibilityLabel(Text("Save Instance Settings"))
                    .help(Text("Save the edited settings for this instance."))
                    .accessibilityIdentifier("prism.instance-settings.save")
                }

                if let failure = model.saveFailure {
                    Label {
                        Text(LocalizedStringKey(failure.localizationKey))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .accessibilityValue(Text(failure.diagnosticText ?? "Instance settings could not be saved."))
                    .accessibilityIdentifier("prism.instance-settings.error")
                    if failure.isRetryAvailable {
                        Button {
                            _ = model.retrySave()
                        } label: {
                            Text(LocalizedStringKey(failure.recoveryAction.titleKey))
                        }
                        .accessibilityLabel(Text(LocalizedStringKey(failure.recoveryAction.accessibilityLabelKey)))
                        .help(Text(LocalizedStringKey(failure.recoveryAction.helpKey)))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Instance Settings")
        .accessibilityIdentifier("prism.instance-settings.form")
    }

    private var joinTargetBinding: Binding<PrismInstanceJoinTarget> {
        Binding(
            get: { model.draft?.joinTarget ?? .none },
            set: { target in model.updateDraft { $0.joinTarget = target } }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<PrismInstanceSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.draft?[keyPath: keyPath] ?? false },
            set: { value in model.updateDraft { $0[keyPath: keyPath] = value } }
        )
    }

    private func intBinding(
        _ keyPath: WritableKeyPath<PrismInstanceSettings, Int>,
        defaultValue: Int
    ) -> Binding<Int> {
        Binding(
            get: { model.draft?[keyPath: keyPath] ?? defaultValue },
            set: { value in model.updateDraft { $0[keyPath: keyPath] = value } }
        )
    }

    private func stringBinding(_ keyPath: WritableKeyPath<PrismInstanceSettings, String>) -> Binding<String> {
        Binding(
            get: { model.draft?[keyPath: keyPath] ?? "" },
            set: { value in model.updateDraft { $0[keyPath: keyPath] = value } }
        )
    }

    private func loaderBinding(_ loader: String) -> Binding<Bool> {
        Binding(
            get: { model.draft?.modDownloadLoaders.contains(loader) == true },
            set: { enabled in
                model.updateDraft { draft in
                    if enabled {
                        if !draft.modDownloadLoaders.contains(loader) {
                            draft.modDownloadLoaders.append(loader)
                        }
                    } else {
                        draft.modDownloadLoaders.removeAll { $0 == loader }
                    }
                }
            }
        )
    }

    private func isEnabled(_ keyPath: KeyPath<PrismInstanceSettings, Bool>) -> Bool {
        model.draft?[keyPath: keyPath] == true
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
