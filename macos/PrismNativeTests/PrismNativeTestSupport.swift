import Foundation

final class PrismTemporaryFixtureRoot {
    let url: URL

    init() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        url = temporaryDirectory
            .appendingPathComponent("PrismNativeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    @discardableResult
    func makeDirectory(relativePath: String) throws -> URL {
        let directoryURL = urlForRelativePath(relativePath)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    @discardableResult
    func makeFile(relativePath: String, contents: String) throws -> URL {
        let fileURL = urlForRelativePath(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fileURL, options: .atomic)
        return fileURL
    }

    func urlForRelativePath(_ relativePath: String) -> URL {
        let candidateURL = url.appendingPathComponent(relativePath)
        let rootPath = url.standardizedFileURL.path
        let candidatePath = candidateURL.standardizedFileURL.path
        precondition(candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/"))
        return candidateURL
    }

    var isInsideTemporaryDirectory: Bool {
        let temporaryPath = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let fixturePath = url.standardizedFileURL.path
        return fixturePath.hasPrefix(temporaryPath + "/")
    }

    var isOutsideUpstreamApplicationSupport: Bool {
        let upstreamURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PrismLauncher", isDirectory: true)
            .standardizedFileURL
        let fixturePath = url.standardizedFileURL.path
        let upstreamPath = upstreamURL.path
        return fixturePath != upstreamPath && !fixturePath.hasPrefix(upstreamPath + "/")
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

final class PrismTestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

final class PrismTestCallbackRecorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Value] = []

    func record(_ value: Value, unlessCancelledBy cancellation: PrismTestCancellation? = nil) {
        guard cancellation?.isCancelled != true else { return }

        lock.lock()
        recordedValues.append(value)
        lock.unlock()
    }

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }
}

struct PrismBridgeHeaderScanner {
    static let forbiddenTokens = [
        "QWidget",
        "QDialog",
        "QObject",
        "QString",
        "QVariant",
        "QModelIndex",
        "QList",
        "QMap",
        "QHash",
        "QUrl",
        "QAbstractItemModel",
        "QAbstractListModel",
        "QAbstractTableModel",
        "Q_OBJECT",
        "std::",
        "shared_ptr",
        "unique_ptr",
        "reinterpret_cast",
        "static_cast",
        "dynamic_cast",
        "template<",
        "namespace ",
    ]

    static func forbiddenTokens(in source: String) -> [String] {
        forbiddenTokens.filter { source.contains($0) }
    }

    static func publicHeaders(relativeTo testFile: StaticString) throws -> [URL] {
        let testFileURL = URL(fileURLWithPath: "\(testFile)")
        let bridgeDirectory = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PrismNative/Bridge", isDirectory: true)

        let enumerator = FileManager.default.enumerator(
            at: bridgeDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let headers = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "h" }
            .sorted { $0.path < $1.path }

        guard !headers.isEmpty else {
            throw NSError(
                domain: "PrismBridgeHeaderScanner",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No public bridge headers found at \(bridgeDirectory.path)"]
            )
        }
        return headers
    }

    static func forbiddenTokens(in headerURL: URL) throws -> [String] {
        let source = try String(contentsOf: headerURL, encoding: .utf8)
        return forbiddenTokens(in: source)
    }
}
