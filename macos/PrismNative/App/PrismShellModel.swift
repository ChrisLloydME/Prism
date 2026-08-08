import Foundation
import AppKit
import SwiftUI

struct PrismInstanceRow: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let group: String?

    init?(id: String, name: String, group: String? = nil) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedGroup = group?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedID.isEmpty, !normalizedName.isEmpty else {
            return nil
        }

        self.id = normalizedID
        self.name = normalizedName
        self.group = normalizedGroup?.isEmpty == true ? nil : normalizedGroup
    }
}

@MainActor
final class PrismInstanceArtworkStore {
    static let defaultItemLimit = 32
    static let defaultTotalByteLimit = 8 * 1024 * 1024

    let itemLimit: Int
    let totalByteLimit: Int

    private struct Entry {
        let image: NSImage
        let byteCount: Int
    }

    private var entries: [String: Entry] = [:]
    private var accessOrder: [String] = []
    private(set) var cachedByteCount = 0

    var cachedIdentifiers: [String] {
        accessOrder
    }

    init?(
        maxItemCount: Int = PrismInstanceArtworkStore.defaultItemLimit,
        maxTotalBytes: Int = PrismInstanceArtworkStore.defaultTotalByteLimit
    ) {
        guard maxItemCount > 0, maxTotalBytes > 0 else {
            return nil
        }

        itemLimit = maxItemCount
        totalByteLimit = maxTotalBytes
    }

    func image(for instanceID: String, from url: URL) -> NSImage? {
        guard let normalizedID = Self.normalizedIdentifier(instanceID), url.isFileURL else {
            return nil
        }

        if let cachedEntry = entries[normalizedID] {
            touch(normalizedID)
            return cachedEntry.image
        }

        guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = resourceValues.fileSize,
              fileSize > 0,
              fileSize <= totalByteLimit,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              !data.isEmpty,
              data.count <= totalByteLimit,
              let image = NSImage(data: data) else {
            return nil
        }

        entries[normalizedID] = Entry(image: image, byteCount: data.count)
        cachedByteCount += data.count
        touch(normalizedID)
        trimToLimits()
        return image
    }

    func removeArtwork(for instanceID: String) {
        guard let normalizedID = Self.normalizedIdentifier(instanceID) else {
            return
        }

        guard let removedEntry = entries.removeValue(forKey: normalizedID) else {
            return
        }

        cachedByteCount -= removedEntry.byteCount
        accessOrder.removeAll { $0 == normalizedID }
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: true)
        accessOrder.removeAll(keepingCapacity: true)
        cachedByteCount = 0
    }

    private func touch(_ identifier: String) {
        accessOrder.removeAll { $0 == identifier }
        accessOrder.append(identifier)
    }

    private func trimToLimits() {
        while entries.count > itemLimit || cachedByteCount > totalByteLimit {
            guard let leastRecentlyUsed = accessOrder.first else {
                return
            }
            accessOrder.removeFirst()
            if let removedEntry = entries.removeValue(forKey: leastRecentlyUsed) {
                cachedByteCount -= removedEntry.byteCount
            }
        }
    }

    private static func normalizedIdentifier(_ identifier: String) -> String? {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum PrismTaskState: String, CaseIterable, Equatable, Sendable {
    case queued
    case running
    case cancelling
    case succeeded
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled:
            return true
        case .queued, .running, .cancelling:
            return false
        }
    }

    var titleKey: String {
        switch self {
        case .queued:
            return "Queued"
        case .running:
            return "In Progress"
        case .cancelling:
            return "Cancelling"
        case .succeeded:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var accessibilityValueKey: String {
        switch self {
        case .queued:
            return "Task is queued."
        case .running:
            return "Task is in progress."
        case .cancelling:
            return "Task cancellation is in progress."
        case .succeeded:
            return "Task completed successfully."
        case .failed:
            return "Task failed."
        case .cancelled:
            return "Task was cancelled."
        }
    }

    var systemImage: String {
        switch self {
        case .queued:
            return "clock"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .cancelling:
            return "xmark.circle"
        case .succeeded:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        case .cancelled:
            return "minus.circle"
        }
    }

    init?(bridgeState: PRTaskState) {
        switch bridgeState {
        case .queued:
            self = .queued
        case .running:
            self = .running
        case .cancelling:
            self = .cancelling
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        @unknown default:
            return nil
        }
    }
}

enum PrismTaskProgress: Equatable, Sendable {
    case none
    case indeterminate
    case determinate(Double)

    init?(bridgeKind: PRTaskProgressKind, fraction: Double) {
        guard fraction.isFinite else {
            return nil
        }

        switch bridgeKind {
        case .none:
            guard fraction == 0 else { return nil }
            self = .none
        case .indeterminate:
            guard fraction == 0 else { return nil }
            self = .indeterminate
        case .determinate:
            guard (0...1).contains(fraction) else { return nil }
            self = .determinate(fraction)
        @unknown default:
            return nil
        }
    }

    var fraction: Double? {
        if case let .determinate(value) = self {
            return value
        }
        return nil
    }

    var accessibilityValueKey: String {
        switch self {
        case .none:
            return "No progress is reported."
        case .indeterminate:
            return "Progress is indeterminate."
        case .determinate:
            return "Progress is determinate."
        }
    }
}

struct PrismTaskSubtaskPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let state: PrismTaskState
    let progress: PrismTaskProgress

    init?(bridgeStatus: PRTaskSubtaskStatus) {
        let identifier = bridgeStatus.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = bridgeStatus.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              !name.isEmpty,
              let state = PrismTaskState(bridgeState: bridgeStatus.state),
              let progress = PrismTaskProgress(
                  bridgeKind: bridgeStatus.progressKind,
                  fraction: bridgeStatus.progressFraction
              ) else {
            return nil
        }

        self.id = identifier
        self.name = name
        self.state = state
        self.progress = progress
    }
}

enum PrismTaskTerminalOutcome: String, Equatable, Sendable {
    case succeeded
    case failed
    case cancelled

    init?(bridgeOutcome: PRTaskTerminalOutcome) {
        switch bridgeOutcome {
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        @unknown default:
            return nil
        }
    }
}

struct PrismTaskTerminalPresentation: Equatable, Sendable {
    let outcome: PrismTaskTerminalOutcome
    let localizationKey: String
    let substitutionValues: [String: String]
    let diagnosticText: String?
    let partialChangesRolledBack: Bool

    init?(bridgeResult: PRTaskTerminalResult) {
        let localizationKey = bridgeResult.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localizationKey.isEmpty,
              let outcome = PrismTaskTerminalOutcome(bridgeOutcome: bridgeResult.outcome) else {
            return nil
        }

        self.outcome = outcome
        self.localizationKey = localizationKey
        self.substitutionValues = bridgeResult.substitutionValues
        self.diagnosticText = bridgeResult.diagnosticText
        self.partialChangesRolledBack = bridgeResult.partialChangesRolledBack
    }
}

struct PrismTaskPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let state: PrismTaskState
    let progress: PrismTaskProgress
    let cancellationAllowed: Bool
    let subtasks: [PrismTaskSubtaskPresentation]
    let terminalResult: PrismTaskTerminalPresentation?

    var canCancel: Bool {
        cancellationAllowed && (state == .queued || state == .running)
    }

    init?(bridgeStatus: PRTaskStatus) {
        let identifier = bridgeStatus.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              let state = PrismTaskState(bridgeState: bridgeStatus.state),
              let progress = PrismTaskProgress(
                  bridgeKind: bridgeStatus.progressKind,
                  fraction: bridgeStatus.progressFraction
              ) else {
            return nil
        }

        let subtasks = bridgeStatus.subtasks.compactMap(PrismTaskSubtaskPresentation.init(bridgeStatus:))
        guard subtasks.count == bridgeStatus.subtasks.count,
              Set(subtasks.map(\.id)).count == subtasks.count else {
            return nil
        }

        let terminalResult: PrismTaskTerminalPresentation?
        if let bridgeResult = bridgeStatus.terminalResult {
            guard let mappedResult = PrismTaskTerminalPresentation(bridgeResult: bridgeResult) else {
                return nil
            }
            terminalResult = mappedResult
        } else {
            terminalResult = nil
        }

        guard (terminalResult != nil) == state.isTerminal else {
            return nil
        }
        if let terminalResult {
            let matchesState = (state == .succeeded && terminalResult.outcome == .succeeded)
                || (state == .failed && terminalResult.outcome == .failed)
                || (state == .cancelled && terminalResult.outcome == .cancelled)
            guard matchesState else {
                return nil
            }
        }

        self.id = identifier
        self.title = bridgeStatus.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? bridgeStatus.title!
            : identifier
        self.state = state
        self.progress = progress
        self.cancellationAllowed = bridgeStatus.cancellationAllowed
        self.subtasks = subtasks
        self.terminalResult = terminalResult
    }
}

enum PrismTaskRecoveryAction: String, Equatable, Sendable {
    case retry
    case none
}

struct PrismTaskPresentationFailure: Equatable, Sendable {
    let taskIdentifier: String
    let localizationKey: String
    let substitutionValues: [String: String]
    let diagnosticText: String?
    let recoveryAction: PrismTaskRecoveryAction
    let partialChangesRolledBack: Bool

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }
}

@MainActor
final class PrismTaskPresentationModel: ObservableObject {
    @Published private(set) var task: PrismTaskPresentation?
    @Published private(set) var failure: PrismTaskPresentationFailure?
    private(set) var cancellationPending = false
    private let onTaskCommand: ((PrismTaskCommandIntent) -> Void)?

    init(onTaskCommand: ((PrismTaskCommandIntent) -> Void)? = nil) {
        self.onTaskCommand = onTaskCommand
    }

    var isCancellationAvailable: Bool {
        task?.canCancel == true && !cancellationPending
    }

    var isRetryAvailable: Bool {
        failure?.isRetryAvailable == true
    }

    @discardableResult
    func apply(status: PRTaskStatus) -> Bool {
        guard let presentation = PrismTaskPresentation(bridgeStatus: status) else {
            return false
        }

        if presentation.id != task?.id || presentation.state == .cancelling || presentation.state.isTerminal {
            cancellationPending = false
        }
        task = presentation
        failure = nil
        return true
    }

    @discardableResult
    func apply(error: PRBridgeError, taskIdentifier: String) -> Bool {
        let normalizedIdentifier = taskIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let localizationKey = error.localizationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty, !localizationKey.isEmpty else {
            return false
        }

        let recoveryAction: PrismTaskRecoveryAction = error.recoveryKind == .retry ? .retry : .none
        return apply(
            failure: PrismTaskPresentationFailure(
                taskIdentifier: normalizedIdentifier,
                localizationKey: localizationKey,
                substitutionValues: error.substitutionValues,
                diagnosticText: error.diagnosticText,
                recoveryAction: recoveryAction,
                partialChangesRolledBack: error.partialChangesRolledBack
            )
        )
    }

    @discardableResult
    func apply(failure: PrismTaskPresentationFailure) -> Bool {
        guard !failure.taskIdentifier.isEmpty, !failure.localizationKey.isEmpty else {
            return false
        }

        task = nil
        self.failure = failure
        cancellationPending = false
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard let task, isCancellationAvailable else {
            return false
        }

        cancellationPending = true
        onTaskCommand?(PrismTaskCommandIntent(action: .cancel, identifier: task.id))
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard let failure, failure.isRetryAvailable else {
            return false
        }

        self.failure = nil
        onTaskCommand?(PrismTaskCommandIntent(action: .retry, identifier: failure.taskIdentifier))
        return true
    }

    func clear() {
        task = nil
        failure = nil
        cancellationPending = false
    }
}

enum PrismInstanceGrouping: String, CaseIterable, Sendable {
    case none
    case group
}

enum PrismInstanceSortOrder: String, CaseIterable, Sendable {
    case nameAscending
    case nameDescending
}

struct PrismInstanceSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String?
    let instances: [PrismInstanceRow]
}

enum PrismShellSidebarItem: String, CaseIterable, Hashable, Identifiable, Sendable {
    case instances
    case discover

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .instances:
            return "Instances"
        case .discover:
            return "Discover"
        }
    }

    var accessibilityLabelKey: String {
        switch self {
        case .instances:
            return "Instance Library"
        case .discover:
            return "Discover Instances"
        }
    }

    var accessibilityHintKey: String {
        switch self {
        case .instances:
            return "Show your installed instances."
        case .discover:
            return "Show available instance sources."
        }
    }

    var systemImage: String {
        switch self {
        case .instances:
            return "square.grid.2x2"
        case .discover:
            return "safari"
        }
    }
}

enum PrismShellRecoveryAction: String, Equatable, Sendable {
    case retry

    var titleKey: String {
        switch self {
        case .retry:
            return "Retry"
        }
    }

    var accessibilityLabelKey: String {
        switch self {
        case .retry:
            return "Retry Loading Instances"
        }
    }

    var helpKey: String {
        switch self {
        case .retry:
            return "Try loading instances again."
        }
    }
}

struct PrismShellFailure: Equatable, Sendable {
    let titleKey: String
    let messageKey: String
    let recoveryAction: PrismShellRecoveryAction

    static let instanceLoad = Self(
        titleKey: "Unable to Load Instances",
        messageKey: "Try again to load your instances.",
        recoveryAction: .retry
    )
}

enum PrismShellDetailState: Equatable, Sendable {
    case loading
    case empty
    case failed(PrismShellFailure)
    case content
}

@MainActor
final class PrismShellModel: ObservableObject {
    @Published private(set) var selectedSidebarItem: PrismShellSidebarItem? = .instances
    @Published private(set) var detailState: PrismShellDetailState = .empty
    @Published private(set) var instances: [PrismInstanceRow] = []
    @Published private(set) var selectedInstanceID: String?
    @Published private(set) var searchText = ""
    @Published private(set) var grouping: PrismInstanceGrouping = .none
    @Published private(set) var sortOrder: PrismInstanceSortOrder = .nameAscending
    private let onRetry: (() -> Void)?

    init(onRetry: (() -> Void)? = nil) {
        self.onRetry = onRetry
    }

    var recoveryAction: PrismShellRecoveryAction? {
        guard case .failed(let failure) = detailState else {
            return nil
        }
        return failure.recoveryAction
    }

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }

    var visibleInstances: [PrismInstanceRow] {
        visibleInstanceSections.flatMap(\.instances)
    }

    var visibleInstanceSections: [PrismInstanceSection] {
        let matchingInstances = instances
            .filter(matchesSearch)
            .sorted(by: compareInstances)

        guard !matchingInstances.isEmpty else {
            return []
        }

        guard grouping == .group else {
            return [PrismInstanceSection(id: "all", title: nil, instances: matchingInstances)]
        }

        let groupedInstances = Dictionary(grouping: matchingInstances) { instance in
            instance.group ?? "Ungrouped"
        }

        return groupedInstances.keys
            .sorted(by: Self.compareGroupNames)
            .map { groupName in
                PrismInstanceSection(
                    id: "group:\(groupName)",
                    title: groupName,
                    instances: groupedInstances[groupName] ?? []
                )
            }
    }

    func selectSidebarItem(_ item: PrismShellSidebarItem?) {
        selectedSidebarItem = item
    }

    func setDetailState(_ state: PrismShellDetailState) {
        detailState = state
    }

    func retry() {
        guard isRetryAvailable else {
            return
        }
        onRetry?()
    }

    func setInstances(_ instances: [PrismInstanceRow]) {
        var uniqueInstances: [PrismInstanceRow] = []
        var seenIdentifiers = Set<String>()

        for instance in instances where seenIdentifiers.insert(instance.id).inserted {
            uniqueInstances.append(instance)
        }

        self.instances = uniqueInstances

        if let selectedInstanceID, !seenIdentifiers.contains(selectedInstanceID) {
            self.selectedInstanceID = nil
        }
    }

    func selectInstanceID(_ identifier: String?) {
        guard let identifier else {
            selectedInstanceID = nil
            return
        }

        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty,
              instances.contains(where: { $0.id == normalizedIdentifier }) else {
            selectedInstanceID = nil
            return
        }

        selectedInstanceID = normalizedIdentifier
    }

    func setSearchText(_ text: String) {
        searchText = text
    }

    func setGrouping(_ grouping: PrismInstanceGrouping) {
        self.grouping = grouping
    }

    func setSortOrder(_ sortOrder: PrismInstanceSortOrder) {
        self.sortOrder = sortOrder
    }

    private func matchesSearch(_ instance: PrismInstanceRow) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return true
        }

        return instance.name.localizedCaseInsensitiveContains(query)
            || instance.id.localizedCaseInsensitiveContains(query)
            || instance.group?.localizedCaseInsensitiveContains(query) == true
    }

    private func compareInstances(_ lhs: PrismInstanceRow, _ rhs: PrismInstanceRow) -> Bool {
        let lhsKey = Self.sortKey(lhs.name)
        let rhsKey = Self.sortKey(rhs.name)

        if lhsKey == rhsKey {
            return lhs.id < rhs.id
        }

        switch sortOrder {
        case .nameAscending:
            return lhsKey < rhsKey
        case .nameDescending:
            return lhsKey > rhsKey
        }
    }

    private static func compareGroupNames(_ lhs: String, _ rhs: String) -> Bool {
        let lhsKey = sortKey(lhs)
        let rhsKey = sortKey(rhs)
        return lhsKey == rhsKey ? lhs < rhs : lhsKey < rhsKey
    }

    private static func sortKey(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
