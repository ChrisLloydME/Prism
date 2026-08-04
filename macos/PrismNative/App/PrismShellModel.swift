import Foundation
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

enum PrismShellDetailState: Equatable, Sendable {
    case loading
    case empty
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
