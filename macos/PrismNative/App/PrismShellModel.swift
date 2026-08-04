import SwiftUI

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

    func selectSidebarItem(_ item: PrismShellSidebarItem?) {
        selectedSidebarItem = item
    }

    func setDetailState(_ state: PrismShellDetailState) {
        detailState = state
    }
}
