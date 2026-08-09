import AppKit
import Foundation
import UniformTypeIdentifiers

struct PrismSystemFilePanelConfiguration: Equatable, Sendable {
    let defaultURL: URL?
    let allowedContentTypeIdentifiers: [String]
    let canChooseFiles: Bool
    let canChooseDirectories: Bool
    let allowsMultipleSelection: Bool

    init(
        defaultURL: URL? = nil,
        allowedContentTypes: [UTType],
        canChooseFiles: Bool,
        canChooseDirectories: Bool,
        allowsMultipleSelection: Bool = false
    ) {
        self.defaultURL = defaultURL?.standardizedFileURL
        self.allowedContentTypeIdentifiers = allowedContentTypes.map(\.identifier)
        self.canChooseFiles = canChooseFiles
        self.canChooseDirectories = canChooseDirectories
        self.allowsMultipleSelection = allowsMultipleSelection
    }
}

@MainActor
enum PrismSystemOpenPanel {
    static func present(
        defaultURL: URL? = nil,
        allowedContentTypes: [UTType],
        canChooseFiles: Bool,
        canChooseDirectories: Bool,
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.canChooseFiles = canChooseFiles
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = false
        if let defaultURL {
            panel.directoryURL = defaultURL.hasDirectoryPath
                ? defaultURL
                : defaultURL.deletingLastPathComponent()
        }
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }
}

@MainActor
enum PrismSystemSavePanel {
    static func present(
        defaultFilename: String,
        defaultDirectoryURL: URL? = nil,
        allowedContentTypes: [UTType],
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFilename
        panel.allowedContentTypes = allowedContentTypes
        panel.canCreateDirectories = false
        if let defaultDirectoryURL {
            panel.directoryURL = defaultDirectoryURL
        }
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }
}
