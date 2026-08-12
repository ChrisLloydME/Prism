import AppKit
import Foundation
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

enum PrismSkinModelVariant: String, CaseIterable, Hashable, Identifiable {
    case classic = "CLASSIC"
    case slim = "SLIM"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .classic: return "Classic"
        case .slim: return "Slim"
        }
    }
}

struct PrismSkinCape: Identifiable, Equatable {
    let id: String
    let displayName: String
    let imageData: Data?

    init?(id: String, displayName: String, imageData: Data? = nil) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty, !normalizedName.isEmpty else { return nil }
        self.id = normalizedID
        self.displayName = normalizedName
        self.imageData = imageData
    }

    static let noneIdentifier = ""
}

struct PrismSkinSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let model: PrismSkinModelVariant
    let capeIdentifier: String
    let textureData: Data?
    let previewData: Data?
    let sourceURL: URL?

    init(
        id: String,
        name: String,
        model: PrismSkinModelVariant,
        capeIdentifier: String = PrismSkinCape.noneIdentifier,
        textureData: Data? = nil,
        previewData: Data? = nil,
        sourceURL: URL? = nil
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
        self.capeIdentifier = capeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.textureData = textureData
        self.previewData = previewData
        self.sourceURL = sourceURL?.standardizedFileURL
    }

    var isUsable: Bool {
        !id.isEmpty && !name.isEmpty
    }
}

enum PrismSkinRecoveryAction: String, Equatable {
    case retry
    case edit
    case cancel

    var titleKey: String {
        switch self {
        case .retry: return "Retry"
        case .edit: return "Edit"
        case .cancel: return "Cancel"
        }
    }
}

struct PrismSkinFailure: Equatable {
    let localizationKey: String
    let diagnosticText: String?
    let recoveryAction: PrismSkinRecoveryAction

    var isRetryAvailable: Bool {
        recoveryAction == .retry
    }
}

enum PrismSkinListState: Equatable {
    case loading(generation: Int)
    case empty
    case content([PrismSkinSnapshot])
    case failed(PrismSkinFailure)
    case cancelled
}

enum PrismSkinOperation: String, Equatable {
    case load
    case importFile
    case importURL
    case importUser
    case upload
    case reset
    case delete
    case rename

    var progressTitleKey: String {
        switch self {
        case .load: return "Loading Skins…"
        case .importFile: return "Importing Skin…"
        case .importURL: return "Downloading Skin…"
        case .importUser: return "Finding User Skin…"
        case .upload: return "Uploading Skin…"
        case .reset: return "Resetting Skin…"
        case .delete: return "Deleting Skin…"
        case .rename: return "Renaming Skin…"
        }
    }
}

enum PrismSkinOperationState: Equatable {
    case idle
    case running(operation: PrismSkinOperation, generation: Int)
    case succeeded(PrismSkinOperation)
    case failed(PrismSkinFailure)
    case cancelled
}

enum PrismSkinImportSource: Equatable {
    case file(URL)
    case remoteURL(URL)
    case username(String)
}

struct PrismSkinImportRequest: Equatable {
    let accountIdentifier: String
    let source: PrismSkinImportSource
}

struct PrismSkinUploadRequest: Equatable {
    let accountIdentifier: String
    let skinIdentifier: String
    let model: PrismSkinModelVariant
    let capeIdentifier: String
}

struct PrismSkinResetRequest: Equatable {
    let accountIdentifier: String
}

struct PrismSkinDeleteRequest: Equatable {
    let accountIdentifier: String
    let skinIdentifier: String
    let confirmed: Bool
}

struct PrismSkinRenameRequest: Equatable {
    let accountIdentifier: String
    let skinIdentifier: String
    let newName: String
}

struct PrismSkinLoadResult: Equatable {
    let accountIdentifier: String
    let skins: [PrismSkinSnapshot]
    let capes: [PrismSkinCape]
    let currentSkinIdentifier: String?
    let failure: PrismSkinFailure?

    static func success(
        accountIdentifier: String,
        skins: [PrismSkinSnapshot],
        capes: [PrismSkinCape],
        currentSkinIdentifier: String?
    ) -> Self {
        Self(
            accountIdentifier: accountIdentifier,
            skins: skins,
            capes: capes,
            currentSkinIdentifier: currentSkinIdentifier,
            failure: nil
        )
    }
}

struct PrismSkinActionResult: Equatable {
    let operation: PrismSkinOperation
    let skins: [PrismSkinSnapshot]?
    let capes: [PrismSkinCape]?
    let selectedSkinIdentifier: String?
    let currentSkinIdentifier: String?
    let failure: PrismSkinFailure?
    let cancelled: Bool

    static func success(
        operation: PrismSkinOperation,
        skins: [PrismSkinSnapshot]? = nil,
        capes: [PrismSkinCape]? = nil,
        selectedSkinIdentifier: String? = nil,
        currentSkinIdentifier: String? = nil
    ) -> Self {
        Self(
            operation: operation,
            skins: skins,
            capes: capes,
            selectedSkinIdentifier: selectedSkinIdentifier,
            currentSkinIdentifier: currentSkinIdentifier,
            failure: nil,
            cancelled: false
        )
    }

    static func failure(operation: PrismSkinOperation, failure: PrismSkinFailure) -> Self {
        Self(
            operation: operation,
            skins: nil,
            capes: nil,
            selectedSkinIdentifier: nil,
            currentSkinIdentifier: nil,
            failure: failure,
            cancelled: false
        )
    }

    static func cancelled(operation: PrismSkinOperation) -> Self {
        Self(
            operation: operation,
            skins: nil,
            capes: nil,
            selectedSkinIdentifier: nil,
            currentSkinIdentifier: nil,
            failure: nil,
            cancelled: true
        )
    }
}

@MainActor
final class PrismSkinPreviewImageStore: ObservableObject {
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

    var cachedIdentifiers: [String] { accessOrder }

    init?(
        maxItemCount: Int = PrismSkinPreviewImageStore.defaultItemLimit,
        maxTotalBytes: Int = PrismSkinPreviewImageStore.defaultTotalByteLimit
    ) {
        guard maxItemCount > 0, maxTotalBytes > 0 else { return nil }
        itemLimit = maxItemCount
        totalByteLimit = maxTotalBytes
    }

    func image(for identifier: String, data: Data?) -> NSImage? {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty,
              let data,
              !data.isEmpty,
              data.count <= totalByteLimit,
              let image = entries[normalizedIdentifier]?.image ?? NSImage(data: data) else {
            return nil
        }

        if entries[normalizedIdentifier] == nil {
            entries[normalizedIdentifier] = Entry(image: image, byteCount: data.count)
            cachedByteCount += data.count
        }
        touch(normalizedIdentifier)
        trimToLimits()
        return image
    }

    func removeImage(for identifier: String) {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let removed = entries.removeValue(forKey: normalizedIdentifier) else { return }
        cachedByteCount -= removed.byteCount
        accessOrder.removeAll { $0 == normalizedIdentifier }
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
            guard let identifier = accessOrder.first,
                  let removed = entries.removeValue(forKey: identifier) else {
                break
            }
            accessOrder.removeFirst()
            cachedByteCount -= removed.byteCount
        }
    }
}

struct PrismSkinPreviewVector: Equatable {
    let x: Float
    let y: Float
    let z: Float
}

struct PrismSkinPreviewUVRect: Equatable {
    let x: Float
    let y: Float
    let width: Float
    let height: Float
}

struct PrismSkinPreviewPart: Equatable {
    enum Kind: String, Equatable {
        case box
        case cape
        case elytra
    }

    let name: String
    let kind: Kind
    let size: PrismSkinPreviewVector
    let position: PrismSkinPreviewVector
    let textureRect: PrismSkinPreviewUVRect
    let textureDepth: Float
    let overlay: Bool
}

enum PrismSkinPreviewGeometry {
    static func parts(
        for model: PrismSkinModelVariant,
        includeCape: Bool,
        includeElytra: Bool
    ) -> [PrismSkinPreviewPart] {
        let base: [PrismSkinPreviewPart] = [
            box("head", PrismSkinPreviewVector(x: 8, y: 8, z: 8), PrismSkinPreviewVector(x: 0, y: 4, z: 0), PrismSkinPreviewUVRect(x: 0, y: 0, width: 8, height: 8)),
            box("body", PrismSkinPreviewVector(x: 8, y: 12, z: 4), PrismSkinPreviewVector(x: 0, y: -6, z: 0), PrismSkinPreviewUVRect(x: 16, y: 16, width: 8, height: 12)),
            box("right-leg", PrismSkinPreviewVector(x: 4, y: 12, z: 4), PrismSkinPreviewVector(x: -1.9, y: -18, z: -0.1), PrismSkinPreviewUVRect(x: 0, y: 16, width: 4, height: 12)),
            box("left-leg", PrismSkinPreviewVector(x: 4, y: 12, z: 4), PrismSkinPreviewVector(x: 1.9, y: -18, z: -0.1), PrismSkinPreviewUVRect(x: 16, y: 48, width: 4, height: 12)),
        ]

        let armWidth: Float = model == .slim ? 3 : 4
        let armX: Float = model == .slim ? 5.5 : 6
        let armTextureX: Float = 40
        let armParts = [
            box("right-arm", PrismSkinPreviewVector(x: armWidth, y: 12, z: 4), PrismSkinPreviewVector(x: -armX, y: -6, z: 0), PrismSkinPreviewUVRect(x: armTextureX, y: 16, width: armWidth, height: 12)),
            box("left-arm", PrismSkinPreviewVector(x: armWidth, y: 12, z: 4), PrismSkinPreviewVector(x: armX, y: -6, z: 0), PrismSkinPreviewUVRect(x: 32, y: 48, width: armWidth, height: 12)),
        ]

        let overlays = [
            box("head-overlay", PrismSkinPreviewVector(x: 9, y: 9, z: 9), PrismSkinPreviewVector(x: 0, y: 4, z: 0), PrismSkinPreviewUVRect(x: 32, y: 0, width: 8, height: 8), textureDepth: 8, overlay: true),
            box("body-overlay", PrismSkinPreviewVector(x: 8.5, y: 12.5, z: 4.5), PrismSkinPreviewVector(x: 0, y: -6, z: 0), PrismSkinPreviewUVRect(x: 16, y: 32, width: 8, height: 12), textureDepth: 4, overlay: true),
            box("right-leg-overlay", PrismSkinPreviewVector(x: 4.5, y: 12.5, z: 4.5), PrismSkinPreviewVector(x: -1.9, y: -18, z: -0.1), PrismSkinPreviewUVRect(x: 0, y: 32, width: 4, height: 12), textureDepth: 4, overlay: true),
            box("left-leg-overlay", PrismSkinPreviewVector(x: 4.5, y: 12.5, z: 4.5), PrismSkinPreviewVector(x: 1.9, y: -18, z: -0.1), PrismSkinPreviewUVRect(x: 0, y: 48, width: 4, height: 12), textureDepth: 4, overlay: true),
            box("right-arm-overlay", PrismSkinPreviewVector(x: armWidth + 0.5, y: 12.5, z: 4.5), PrismSkinPreviewVector(x: -armX, y: -6, z: 0), PrismSkinPreviewUVRect(x: 40, y: 32, width: armWidth, height: 12), textureDepth: 4, overlay: true),
            box("left-arm-overlay", PrismSkinPreviewVector(x: armWidth + 0.5, y: 12.5, z: 4.5), PrismSkinPreviewVector(x: armX, y: -6, z: 0), PrismSkinPreviewUVRect(x: 48, y: 48, width: armWidth, height: 12), textureDepth: 4, overlay: true),
        ]

        var result = base + armParts + overlays
        if includeCape {
            result.append(
                PrismSkinPreviewPart(
                    name: "cape",
                    kind: .cape,
                    size: PrismSkinPreviewVector(x: 10, y: 16, z: 1),
                    position: PrismSkinPreviewVector(x: 0, y: -8, z: 2.5),
                    textureRect: PrismSkinPreviewUVRect(x: 1, y: 1, width: 10, height: 16),
                    textureDepth: 0,
                    overlay: false
                )
            )
        }
        if includeElytra {
            for side in [-1 as Float, 1 as Float] {
                result.append(
                    PrismSkinPreviewPart(
                        name: side < 0 ? "left-elytra" : "right-elytra",
                        kind: .elytra,
                        size: PrismSkinPreviewVector(x: 10, y: 20, z: 1),
                        position: PrismSkinPreviewVector(x: side * 6, y: -10, z: 1),
                        textureRect: PrismSkinPreviewUVRect(x: 22, y: 0, width: 10, height: 20),
                        textureDepth: 0,
                        overlay: false
                    )
                )
            }
        }
        return result
    }

    private static func box(
        _ name: String,
        _ size: PrismSkinPreviewVector,
        _ position: PrismSkinPreviewVector,
        _ textureRect: PrismSkinPreviewUVRect,
        textureDepth: Float? = nil,
        overlay: Bool = false
    ) -> PrismSkinPreviewPart {
        PrismSkinPreviewPart(
            name: name,
            kind: .box,
            size: size,
            position: position,
            textureRect: textureRect,
            textureDepth: textureDepth ?? size.z,
            overlay: overlay
        )
    }
}

struct PrismSkinPreviewConfiguration: Equatable {
    let textureData: Data?
    let capeData: Data?
    let model: PrismSkinModelVariant
    let showCape: Bool
    let showElytra: Bool
    let yaw: Double
    let pitch: Double
    let distance: Double
}

struct PrismSkinSceneView: NSViewRepresentable {
    let configuration: PrismSkinPreviewConfiguration

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = true
        view.rendersContinuously = false
        view.backgroundColor = .windowBackgroundColor
        context.coordinator.apply(configuration, to: view)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.apply(configuration, to: view)
    }

    @MainActor
    final class Coordinator {
        private let imageStore = PrismSkinPreviewImageStore()!
        private var lastConfiguration: PrismSkinPreviewConfiguration?
        private weak var modelRoot: SCNNode?
        private weak var cameraNode: SCNNode?

        func apply(_ configuration: PrismSkinPreviewConfiguration, to view: SCNView) {
            if lastConfiguration?.textureData != configuration.textureData
                || lastConfiguration?.capeData != configuration.capeData
                || lastConfiguration?.model != configuration.model
                || lastConfiguration?.showCape != configuration.showCape
                || lastConfiguration?.showElytra != configuration.showElytra {
                rebuildScene(configuration, in: view)
            }

            modelRoot?.eulerAngles = SCNVector3(
                Float(configuration.pitch * .pi / 180),
                Float(configuration.yaw * .pi / 180),
                0
            )
            cameraNode?.position.z = CGFloat(max(18.0, min(64.0, configuration.distance)))
            lastConfiguration = configuration
        }

        private func rebuildScene(_ configuration: PrismSkinPreviewConfiguration, in view: SCNView) {
            let scene = SCNScene()
            scene.background.contents = NSColor.windowBackgroundColor

            let root = SCNNode()
            scene.rootNode.addChildNode(root)
            modelRoot = root

            let camera = SCNCamera()
            camera.zNear = 1
            camera.zFar = 200
            let cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, -6, CGFloat(configuration.distance))
            scene.rootNode.addChildNode(cameraNode)
            self.cameraNode = cameraNode

            let parts = PrismSkinPreviewGeometry.parts(
                for: configuration.model,
                includeCape: configuration.showCape,
                includeElytra: configuration.showElytra
            )
            let skinImage = imageStore.image(for: "skin", data: configuration.textureData)
            let capeImage = imageStore.image(for: "cape", data: configuration.capeData)

            for part in parts {
                switch part.kind {
                case .box:
                    let geometry = SCNBox(
                        width: CGFloat(part.size.x),
                        height: CGFloat(part.size.y),
                        length: CGFloat(part.size.z),
                        chamferRadius: 0
                    )
                    geometry.materials = materials(
                        image: skinImage,
                        textureOrigin: part.textureRect,
                        textureDepth: part.textureDepth
                    )
                    let node = SCNNode(geometry: geometry)
                    node.position = SCNVector3(part.position.x, part.position.y, part.position.z)
                    root.addChildNode(node)
                case .cape, .elytra:
                    let geometry = SCNPlane(width: CGFloat(part.size.x), height: CGFloat(part.size.y))
                    geometry.materials = [
                        material(
                            image: capeImage,
                            textureRect: part.textureRect,
                            textureWidth: 64,
                            textureHeight: 32
                        )
                    ]
                    let node = SCNNode(geometry: geometry)
                    node.position = SCNVector3(part.position.x, part.position.y, part.position.z)
                    if part.kind == .cape {
                        node.eulerAngles = SCNVector3(Float(10.8 * .pi / 180), .pi, 0)
                    } else {
                        node.eulerAngles = SCNVector3(Float(15 * Float.pi / 180), part.position.x < 0 ? -0.25 : 0.25, 0)
                    }
                    root.addChildNode(node)
                }
            }

            let light = SCNLight()
            light.type = .omni
            light.intensity = 900
            let lightNode = SCNNode()
            lightNode.light = light
            lightNode.position = SCNVector3(20, 20, 40)
            scene.rootNode.addChildNode(lightNode)

            view.scene = scene
        }

        private func materials(
            image: NSImage?,
            textureOrigin: PrismSkinPreviewUVRect,
            textureDepth: Float
        ) -> [SCNMaterial] {
            let u = textureOrigin.x
            let v = textureOrigin.y
            let width = textureOrigin.width
            let height = textureOrigin.height
            let rects = [
                PrismSkinPreviewUVRect(x: u + textureDepth, y: v + textureDepth, width: width, height: height),
                PrismSkinPreviewUVRect(x: u + textureDepth + width, y: v + textureDepth, width: textureDepth, height: height),
                PrismSkinPreviewUVRect(x: u + width + textureDepth * 2, y: v + textureDepth, width: width, height: height),
                PrismSkinPreviewUVRect(x: u, y: v + textureDepth, width: textureDepth, height: height),
                PrismSkinPreviewUVRect(x: u + textureDepth, y: v, width: width, height: textureDepth),
                PrismSkinPreviewUVRect(x: u + width + textureDepth, y: v, width: width, height: textureDepth),
            ]
            return rects.map {
                material(image: image, textureRect: $0, textureWidth: 64, textureHeight: 64)
            }
        }

        private func material(
            image: NSImage?,
            textureRect: PrismSkinPreviewUVRect,
            textureWidth: Float,
            textureHeight: Float
        ) -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = image ?? NSColor.systemGray
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.transparencyMode = .aOne

            var transform = SCNMatrix4MakeScale(
                CGFloat(textureRect.width / textureWidth),
                CGFloat(textureRect.height / textureHeight),
                1
            )
            transform.m41 = CGFloat(textureRect.x / textureWidth)
            transform.m42 = CGFloat(1 - ((textureRect.y + textureRect.height) / textureHeight))
            material.diffuse.contentsTransform = transform
            material.diffuse.wrapS = .clamp
            material.diffuse.wrapT = .clamp
            return material
        }
    }
}

struct PrismSkinPreviewView: View {
    let snapshot: PrismSkinSnapshot?
    let model: PrismSkinModelVariant
    let cape: PrismSkinCape?
    let showElytra: Bool

    @State private var yaw = 90.0
    @State private var pitch = 0.0
    @State private var distance = 48.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot {
                PrismSkinSceneView(
                    configuration: PrismSkinPreviewConfiguration(
                        textureData: snapshot.textureData,
                        capeData: cape?.imageData,
                        model: model,
                        showCape: cape != nil,
                        showElytra: showElytra,
                        yaw: yaw,
                        pitch: pitch,
                        distance: distance
                    )
                )
                .frame(minHeight: 280)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Skin Preview"))
                .accessibilityValue(Text(accessibilitySummary))
                .accessibilityIdentifier("prism.skins.preview")

                HStack(spacing: 12) {
                    Slider(value: $yaw, in: -180...180) {
                        Text("Rotation")
                    }
                    .accessibilityLabel(Text("Preview Rotation"))
                    .accessibilityIdentifier("prism.skins.preview.rotation")

                    Slider(value: $pitch, in: -35...35) {
                        Text("Tilt")
                    }
                    .accessibilityLabel(Text("Preview Tilt"))
                    .accessibilityIdentifier("prism.skins.preview.tilt")

                    Slider(value: $distance, in: 18...64) {
                        Text("Zoom")
                    }
                    .accessibilityLabel(Text("Preview Zoom"))
                    .accessibilityIdentifier("prism.skins.preview.zoom")
                }
            } else {
                ContentUnavailableView(
                    "Preview Unavailable",
                    systemImage: "person.crop.square",
                    description: Text("Select a valid skin to preview it.")
                )
                .accessibilityIdentifier("prism.skins.preview.empty")
            }
        }
    }

    private var accessibilitySummary: String {
        let capeName = cape?.displayName ?? "No Cape"
        return "\(model.titleKey), \(capeName)"
    }
}

struct PrismSkinThumbnail: View {
    let identifier: String
    let data: Data?
    @ObservedObject var imageStore: PrismSkinPreviewImageStore

    var body: some View {
        if let image = imageStore.image(for: identifier, data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityLabel(Text("Skin Thumbnail"))
        } else {
            Image(systemName: "person.crop.square")
                .frame(width: 48, height: 48)
                .accessibilityLabel(Text("Skin Thumbnail Unavailable"))
        }
    }
}

@MainActor
final class PrismSkinManagementModel: ObservableObject {
    @Published private(set) var accountIdentifier: String
    @Published private(set) var listState: PrismSkinListState
    @Published private(set) var capes: [PrismSkinCape]
    @Published private(set) var currentSkinIdentifier: String?
    @Published private(set) var selectedSkinIdentifier: String?
    @Published private(set) var draftModel: PrismSkinModelVariant
    @Published private(set) var draftCapeIdentifier: String
    @Published var previewElytra = false
    @Published var importText = ""
    @Published private(set) var operationState: PrismSkinOperationState = .idle

    private var generation = 0
    private var retryRequest: PrismSkinRetryRequest?
    private let bridge: PRPrismBridge?
    private var requestToken: PRBridgeObservationToken?

    let onLoad: ((String, Int) -> Void)?
    let onImport: ((PrismSkinImportRequest, Int) -> Void)?
    let onUpload: ((PrismSkinUploadRequest, Int) -> Void)?
    let onReset: ((PrismSkinResetRequest, Int) -> Void)?
    let onDelete: ((PrismSkinDeleteRequest, Int) -> Void)?
    let onRename: ((PrismSkinRenameRequest, Int) -> Void)?
    let onCancel: ((PrismSkinOperation, Int) -> Void)?
    let onPresentImportPanel: ((Int) -> Void)?

    private enum PrismSkinRetryRequest {
        case load
        case importSkin(PrismSkinImportRequest)
        case upload(PrismSkinUploadRequest)
        case reset(PrismSkinResetRequest)
        case delete(PrismSkinDeleteRequest)
        case rename(PrismSkinRenameRequest)
    }

    init(
        accountIdentifier: String = "",
        initialSkins: [PrismSkinSnapshot] = [],
        initialCapes: [PrismSkinCape] = [],
        currentSkinIdentifier: String? = nil,
        bridge: PRPrismBridge? = nil,
        onLoad: ((String, Int) -> Void)? = nil,
        onImport: ((PrismSkinImportRequest, Int) -> Void)? = nil,
        onUpload: ((PrismSkinUploadRequest, Int) -> Void)? = nil,
        onReset: ((PrismSkinResetRequest, Int) -> Void)? = nil,
        onDelete: ((PrismSkinDeleteRequest, Int) -> Void)? = nil,
        onRename: ((PrismSkinRenameRequest, Int) -> Void)? = nil,
        onCancel: ((PrismSkinOperation, Int) -> Void)? = nil,
        onPresentImportPanel: ((Int) -> Void)? = nil
    ) {
        let normalizedAccount = accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountIdentifier = normalizedAccount
        let validSkins = initialSkins.filter(\.isUsable)
        self.listState = validSkins.isEmpty ? .empty : .content(validSkins)
        self.capes = initialCapes
        self.currentSkinIdentifier = currentSkinIdentifier
        let selectedIdentifier = currentSkinIdentifier.flatMap { id in validSkins.contains { $0.id == id } ? id : nil }
            ?? validSkins.first?.id
        self.selectedSkinIdentifier = selectedIdentifier
        let selected = validSkins.first { $0.id == selectedIdentifier }
        self.draftModel = selected?.model ?? .classic
        self.draftCapeIdentifier = selected?.capeIdentifier ?? PrismSkinCape.noneIdentifier
        self.bridge = bridge
        self.onLoad = onLoad
        self.onImport = onImport
        self.onUpload = onUpload
        self.onReset = onReset
        self.onDelete = onDelete
        self.onRename = onRename
        self.onCancel = onCancel
        self.onPresentImportPanel = onPresentImportPanel
    }

    var skins: [PrismSkinSnapshot] {
        guard case .content(let skins) = listState else { return [] }
        return skins
    }

    var selectedSkin: PrismSkinSnapshot? {
        guard let selectedSkinIdentifier else { return nil }
        return skins.first { $0.id == selectedSkinIdentifier }
    }

    var selectedCape: PrismSkinCape? {
        guard !draftCapeIdentifier.isEmpty else { return nil }
        return capes.first { $0.id == draftCapeIdentifier }
    }

    var canUpload: Bool {
        selectedSkin?.textureData?.isEmpty == false && !isRunning
    }

    var canDelete: Bool {
        selectedSkin != nil && selectedSkinIdentifier != currentSkinIdentifier && !isRunning
    }

    var canRename: Bool {
        selectedSkin != nil && !isRunning
    }

    var canReset: Bool {
        !accountIdentifier.isEmpty && !isRunning
    }

    var isRunning: Bool {
        if case .running = operationState { return true }
        return false
    }

    var retryFailure: PrismSkinFailure? {
        guard case .failed(let failure) = operationState else { return nil }
        return failure
    }

    @discardableResult
    func select(id: String?) -> Bool {
        guard let id, skins.contains(where: { $0.id == id }) else { return false }
        selectedSkinIdentifier = id
        syncDraft()
        return true
    }

    func setAccountContext(identifier: String) {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        invalidateCurrentOperation()
        requestToken?.cancel()
        requestToken = nil
        accountIdentifier = normalized
        listState = .empty
        capes = []
        currentSkinIdentifier = nil
        selectedSkinIdentifier = nil
        syncDraft()
    }

    func setModel(_ model: PrismSkinModelVariant) {
        guard selectedSkin != nil else { return }
        draftModel = model
    }

    func setCapeIdentifier(_ identifier: String) {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty || capes.contains(where: { $0.id == normalized }) else { return }
        draftCapeIdentifier = normalized
    }

    @discardableResult
    func beginLoad() -> Int {
        let ticket = begin(operation: .load, retry: .load)
        listState = .loading(generation: ticket)
        requestToken?.cancel()
        if let bridge {
            requestToken = bridge.loadSkins(withAccountIdentifier: accountIdentifier) { [weak self] result, error in
                self?.requestToken = nil
                guard let self else { return }
                if let result {
                    _ = self.apply(bridgeLoadResult: result, generation: ticket)
                } else if let error {
                    _ = self.apply(
                        loadResult: PrismSkinLoadResult(
                            accountIdentifier: self.accountIdentifier,
                            skins: [],
                            capes: [],
                            currentSkinIdentifier: nil,
                            failure: Self.failure(from: error)
                        ),
                        generation: ticket
                    )
                }
            }
        } else if let onLoad {
            onLoad(accountIdentifier, ticket)
        } else {
            failUnavailable(operation: .load, generation: ticket)
        }
        return ticket
    }

    @discardableResult
    func apply(loadResult: PrismSkinLoadResult, generation resultGeneration: Int) -> Bool {
        guard isCurrent(operation: .load, generation: resultGeneration),
              loadResult.accountIdentifier == accountIdentifier else { return false }
        if let failure = loadResult.failure {
            listState = .failed(failure)
            operationState = .failed(failure)
            return true
        }

        capes = loadResult.capes
        currentSkinIdentifier = loadResult.currentSkinIdentifier
        let validSkins = loadResult.skins.filter(\.isUsable)
        listState = validSkins.isEmpty ? .empty : .content(validSkins)
        selectedSkinIdentifier = loadResult.currentSkinIdentifier.flatMap { id in validSkins.contains { $0.id == id } ? id : nil }
            ?? validSkins.first?.id
        syncDraft()
        operationState = .succeeded(.load)
        retryRequest = nil
        return true
    }

    @discardableResult
    func beginImportFile(defaultDirectoryURL: URL? = nil) -> Int? {
        guard !isRunning else { return nil }
        let ticket = begin(operation: .importFile, retry: nil)
        if let onPresentImportPanel {
            onPresentImportPanel(ticket)
            return ticket
        }
        PrismSystemOpenPanel.present(
            defaultURL: defaultDirectoryURL,
            allowedContentTypes: [UTType.png],
            canChooseFiles: true,
            canChooseDirectories: false
        ) { [weak self] url in
            guard let self else { return }
            guard self.isCurrent(operation: .importFile, generation: ticket) else { return }
            guard let url else {
                self.cancelPanel(generation: ticket)
                return
            }
            _ = self.submitImportFile(url: url, generation: ticket)
        }
        return ticket
    }

    @discardableResult
    func submitImportFile(url: URL, generation resultGeneration: Int? = nil) -> Bool {
        guard url.isFileURL, !url.path.isEmpty, url.pathExtension.lowercased() == "png" else {
            setLocalFailure(key: "skins.import.invalidFile", diagnostic: "Choose a local PNG skin file.")
            return false
        }
        let ticket: Int
        if let resultGeneration {
            guard isCurrent(operation: .importFile, generation: resultGeneration) else { return false }
            ticket = resultGeneration
        } else {
            ticket = begin(operation: .importFile, retry: nil)
        }
        let request = PrismSkinImportRequest(accountIdentifier: accountIdentifier, source: .file(url.standardizedFileURL))
        retryRequest = .importSkin(request)
        dispatch(request: .importSkin(request), operation: .importFile, generation: ticket)
        return true
    }

    @discardableResult
    func importURL(text: String) -> Bool {
        guard !isRunning else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            setLocalFailure(key: "skins.import.invalidURL", diagnostic: "Enter a valid HTTP or HTTPS skin URL.")
            return false
        }
        let request = PrismSkinImportRequest(accountIdentifier: accountIdentifier, source: .remoteURL(url))
        let ticket = begin(operation: .importURL, retry: .importSkin(request))
        dispatch(request: .importSkin(request), operation: .importURL, generation: ticket)
        return true
    }

    @discardableResult
    func importUser(text: String) -> Bool {
        guard !isRunning else { return false }
        let username = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, username.count <= 16 else {
            setLocalFailure(key: "skins.import.invalidUsername", diagnostic: "Enter a Minecraft username with at most 16 characters.")
            return false
        }
        let request = PrismSkinImportRequest(accountIdentifier: accountIdentifier, source: .username(username))
        let ticket = begin(operation: .importUser, retry: .importSkin(request))
        dispatch(request: .importSkin(request), operation: .importUser, generation: ticket)
        return true
    }

    @discardableResult
    func upload() -> Bool {
        guard let selectedSkin, let _ = selectedSkin.textureData, !isRunning else { return false }
        let request = PrismSkinUploadRequest(
            accountIdentifier: accountIdentifier,
            skinIdentifier: selectedSkin.id,
            model: draftModel,
            capeIdentifier: draftCapeIdentifier
        )
        let ticket = begin(operation: .upload, retry: .upload(request))
        dispatch(request: .upload(request), operation: .upload, generation: ticket)
        return true
    }

    @discardableResult
    func resetSkin() -> Bool {
        guard canReset else { return false }
        let request = PrismSkinResetRequest(accountIdentifier: accountIdentifier)
        let ticket = begin(operation: .reset, retry: .reset(request))
        dispatch(request: .reset(request), operation: .reset, generation: ticket)
        return true
    }

    @discardableResult
    func deleteSelected() -> Bool {
        guard !isRunning else { return false }
        guard let selectedSkinIdentifier else { return false }
        guard selectedSkinIdentifier != currentSkinIdentifier else {
            setLocalFailure(key: "skins.delete.currentRejected", diagnostic: "The skin currently in use cannot be deleted.")
            return false
        }
        let request = PrismSkinDeleteRequest(accountIdentifier: accountIdentifier, skinIdentifier: selectedSkinIdentifier, confirmed: true)
        let ticket = begin(operation: .delete, retry: .delete(request))
        dispatch(request: .delete(request), operation: .delete, generation: ticket)
        return true
    }

    @discardableResult
    func renameSelected(to name: String) -> Bool {
        guard !isRunning else { return false }
        guard let selectedSkinIdentifier else { return false }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 64 else {
            setLocalFailure(key: "skins.rename.invalidName", diagnostic: "Enter a skin name from 1 to 64 characters.")
            return false
        }
        let request = PrismSkinRenameRequest(accountIdentifier: accountIdentifier, skinIdentifier: selectedSkinIdentifier, newName: normalized)
        let ticket = begin(operation: .rename, retry: .rename(request))
        dispatch(request: .rename(request), operation: .rename, generation: ticket)
        return true
    }

    @discardableResult
    func apply(actionResult: PrismSkinActionResult, generation resultGeneration: Int) -> Bool {
        guard isCurrent(operation: actionResult.operation, generation: resultGeneration) else { return false }
        if actionResult.cancelled {
            operationState = .cancelled
            return true
        }
        if let failure = actionResult.failure {
            operationState = .failed(failure)
            return true
        }
        if let capes = actionResult.capes { self.capes = capes }
        if let skins = actionResult.skins {
            let validSkins = skins.filter(\.isUsable)
            listState = validSkins.isEmpty ? .empty : .content(validSkins)
        }
        if actionResult.operation == .reset {
            currentSkinIdentifier = nil
        } else if let currentSkinIdentifier = actionResult.currentSkinIdentifier {
            self.currentSkinIdentifier = currentSkinIdentifier
        }
        if let selectedSkinIdentifier = actionResult.selectedSkinIdentifier {
            _ = select(id: selectedSkinIdentifier)
        } else {
            syncDraft()
        }
        operationState = .succeeded(actionResult.operation)
        retryRequest = nil
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard let retryRequest else { return false }
        switch retryRequest {
        case .load:
            _ = beginLoad()
        case .importSkin(let request):
            let operation: PrismSkinOperation
            switch request.source {
            case .file: operation = .importFile
            case .remoteURL: operation = .importURL
            case .username: operation = .importUser
            }
            let ticket = begin(operation: operation, retry: .importSkin(request))
            dispatch(request: .importSkin(request), operation: operation, generation: ticket)
        case .upload(let request):
            let ticket = begin(operation: .upload, retry: .upload(request))
            dispatch(request: .upload(request), operation: .upload, generation: ticket)
        case .reset(let request):
            let ticket = begin(operation: .reset, retry: .reset(request))
            dispatch(request: .reset(request), operation: .reset, generation: ticket)
        case .delete(let request):
            let ticket = begin(operation: .delete, retry: .delete(request))
            dispatch(request: .delete(request), operation: .delete, generation: ticket)
        case .rename(let request):
            let ticket = begin(operation: .rename, retry: .rename(request))
            dispatch(request: .rename(request), operation: .rename, generation: ticket)
        }
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard case .running(let operation, let ticket) = operationState else { return false }
        onCancel?(operation, ticket)
        requestToken?.cancel()
        requestToken = nil
        invalidateCurrentOperation()
        operationState = .cancelled
        if operation == .load { listState = .cancelled }
        return true
    }

    func resetPresentation() {
        invalidateCurrentOperation()
        operationState = .idle
        retryRequest = nil
        if skins.isEmpty {
            listState = .empty
        }
    }

    private func dispatch(
        request: PrismSkinRetryRequest,
        operation: PrismSkinOperation,
        generation ticket: Int
    ) {
        requestToken?.cancel()
        if let bridge {
            guard let bridgeRequest = bridgeRequest(from: request) else {
                setLocalFailure(key: "skins.action.invalidRequest", diagnostic: "The skin request is incomplete.")
                return
            }
            requestToken = bridge.performSkinAction(with: bridgeRequest) { [weak self] result, error in
                self?.requestToken = nil
                guard let self else { return }
                if let result {
                    _ = self.apply(bridgeActionResult: result, generation: ticket)
                } else if let error {
                    _ = self.apply(
                        actionResult: .failure(operation: operation, failure: Self.failure(from: error)),
                        generation: ticket
                    )
                }
            }
            return
        }

        switch request {
        case .load:
            onLoad?(accountIdentifier, ticket)
        case .importSkin(let value):
            onImport?(value, ticket)
        case .upload(let value):
            onUpload?(value, ticket)
        case .reset(let value):
            onReset?(value, ticket)
        case .delete(let value):
            onDelete?(value, ticket)
        case .rename(let value):
            onRename?(value, ticket)
        }
        let hasCallback: Bool
        switch request {
        case .load: hasCallback = onLoad != nil
        case .importSkin: hasCallback = onImport != nil
        case .upload: hasCallback = onUpload != nil
        case .reset: hasCallback = onReset != nil
        case .delete: hasCallback = onDelete != nil
        case .rename: hasCallback = onRename != nil
        }
        if !hasCallback { failUnavailable(operation: operation, generation: ticket) }
    }

    private func bridgeRequest(from retry: PrismSkinRetryRequest) -> PRSkinActionRequest? {
        let operation: PRSkinOperation
        var account = accountIdentifier
        var skinIdentifier: String?
        var model: PRSkinModel = .classic
        var capeIdentifier: String?
        var sourceURL: URL?
        var remoteURL: String?
        var username: String?
        var replacementName: String?
        var confirmed = false

        switch retry {
        case .load:
            return nil
        case .importSkin(let request):
            account = request.accountIdentifier
            switch request.source {
            case .file(let url):
                operation = .importFile
                sourceURL = url
            case .remoteURL(let url):
                operation = .importURL
                remoteURL = url.absoluteString
            case .username(let value):
                operation = .importUser
                username = value
            }
        case .upload(let request):
            operation = .upload
            account = request.accountIdentifier
            skinIdentifier = request.skinIdentifier
            model = request.model == .slim ? .slim : .classic
            capeIdentifier = request.capeIdentifier.isEmpty ? nil : request.capeIdentifier
        case .reset(let request):
            operation = .reset
            account = request.accountIdentifier
        case .delete(let request):
            operation = .delete
            account = request.accountIdentifier
            skinIdentifier = request.skinIdentifier
            confirmed = request.confirmed
        case .rename(let request):
            operation = .rename
            account = request.accountIdentifier
            skinIdentifier = request.skinIdentifier
            replacementName = request.newName
        }
        return PRSkinActionRequest(
            operation: operation,
            accountIdentifier: account,
            skinIdentifier: skinIdentifier,
            model: model,
            capeIdentifier: capeIdentifier,
            sourceURL: sourceURL,
            remoteURLString: remoteURL,
            username: username,
            replacementName: replacementName,
            confirmed: confirmed
        )
    }

    private func apply(bridgeLoadResult: PRSkinLoadResult, generation: Int) -> Bool {
        switch bridgeLoadResult.outcome {
        case .succeeded:
            guard let mapped = Self.map(
                skins: bridgeLoadResult.skins,
                capes: bridgeLoadResult.capes
            ) else { return false }
            return apply(
                loadResult: .success(
                    accountIdentifier: bridgeLoadResult.accountIdentifier,
                    skins: mapped.skins,
                    capes: mapped.capes,
                    currentSkinIdentifier: bridgeLoadResult.currentSkinIdentifier
                ),
                generation: generation
            )
        case .cancelled:
            guard isCurrent(operation: .load, generation: generation) else { return false }
            operationState = .cancelled
            listState = .cancelled
            return true
        case .failed, .rejected:
            return apply(
                loadResult: PrismSkinLoadResult(
                    accountIdentifier: bridgeLoadResult.accountIdentifier,
                    skins: [],
                    capes: [],
                    currentSkinIdentifier: nil,
                    failure: Self.failure(
                        key: bridgeLoadResult.localizationKey,
                        diagnostic: bridgeLoadResult.diagnosticText,
                        retryable: bridgeLoadResult.retryable,
                        rejected: bridgeLoadResult.outcome == .rejected
                    )
                ),
                generation: generation
            )
        @unknown default:
            return false
        }
    }

    private func apply(bridgeActionResult: PRSkinActionResult, generation: Int) -> Bool {
        let operation = Self.operation(from: bridgeActionResult.operation)
        switch bridgeActionResult.outcome {
        case .succeeded:
            guard let mapped = Self.map(
                skins: bridgeActionResult.skins,
                capes: bridgeActionResult.capes
            ) else { return false }
            return apply(
                actionResult: .success(
                    operation: operation,
                    skins: mapped.skins,
                    capes: mapped.capes,
                    selectedSkinIdentifier: bridgeActionResult.selectedSkinIdentifier,
                    currentSkinIdentifier: bridgeActionResult.currentSkinIdentifier
                ),
                generation: generation
            )
        case .cancelled:
            return apply(actionResult: .cancelled(operation: operation), generation: generation)
        case .failed, .rejected:
            return apply(
                actionResult: .failure(
                    operation: operation,
                    failure: Self.failure(
                        key: bridgeActionResult.localizationKey,
                        diagnostic: bridgeActionResult.diagnosticText,
                        retryable: bridgeActionResult.retryable,
                        rejected: bridgeActionResult.outcome == .rejected
                    )
                ),
                generation: generation
            )
        @unknown default:
            return false
        }
    }

    private static func map(
        skins: [PRSkinSnapshot],
        capes: [PRSkinCape]
    ) -> (skins: [PrismSkinSnapshot], capes: [PrismSkinCape])? {
        let mappedSkins = skins.map {
            PrismSkinSnapshot(
                id: $0.identifier,
                name: $0.name,
                model: $0.model == .slim ? .slim : .classic,
                capeIdentifier: $0.capeIdentifier ?? PrismSkinCape.noneIdentifier,
                textureData: $0.textureData,
                previewData: $0.previewData,
                sourceURL: $0.sourceURL
            )
        }
        let mappedCapes = capes.compactMap {
            PrismSkinCape(id: $0.identifier, displayName: $0.displayName, imageData: $0.imageData)
        }
        guard mappedSkins.allSatisfy(\.isUsable), mappedCapes.count == capes.count else { return nil }
        return (mappedSkins, mappedCapes)
    }

    private static func operation(from operation: PRSkinOperation) -> PrismSkinOperation {
        switch operation {
        case .importFile: return .importFile
        case .importURL: return .importURL
        case .importUser: return .importUser
        case .upload: return .upload
        case .reset: return .reset
        case .delete: return .delete
        case .rename: return .rename
        @unknown default: return .load
        }
    }

    private static func failure(from error: PRBridgeError) -> PrismSkinFailure {
        PrismSkinFailure(
            localizationKey: error.localizationKey,
            diagnosticText: error.diagnosticText,
            recoveryAction: error.recoveryKind == .retry ? .retry : .cancel
        )
    }

    private static func failure(
        key: String,
        diagnostic: String?,
        retryable: Bool,
        rejected: Bool
    ) -> PrismSkinFailure {
        PrismSkinFailure(
            localizationKey: key,
            diagnosticText: diagnostic,
            recoveryAction: retryable ? .retry : (rejected ? .edit : .cancel)
        )
    }

    private func begin(operation: PrismSkinOperation, retry: PrismSkinRetryRequest?) -> Int {
        generation &+= 1
        let ticket = generation
        operationState = .running(operation: operation, generation: ticket)
        retryRequest = retry
        return ticket
    }

    private func isCurrent(operation: PrismSkinOperation, generation resultGeneration: Int) -> Bool {
        guard case .running(let currentOperation, let currentGeneration) = operationState else { return false }
        return currentOperation == operation && currentGeneration == resultGeneration && generation == resultGeneration
    }

    private func cancelPanel(generation resultGeneration: Int) {
        guard isCurrent(operation: .importFile, generation: resultGeneration) else { return }
        invalidateCurrentOperation()
        operationState = .cancelled
    }

    private func invalidateCurrentOperation() {
        generation &+= 1
    }

    private func syncDraft() {
        guard let selectedSkin else {
            draftModel = .classic
            draftCapeIdentifier = PrismSkinCape.noneIdentifier
            return
        }
        draftModel = selectedSkin.model
        draftCapeIdentifier = selectedSkin.capeIdentifier
    }

    private func setLocalFailure(key: String, diagnostic: String) {
        operationState = .failed(
            PrismSkinFailure(localizationKey: key, diagnosticText: diagnostic, recoveryAction: .edit)
        )
    }

    private func failUnavailable(operation: PrismSkinOperation, generation resultGeneration: Int) {
        guard isCurrent(operation: operation, generation: resultGeneration) else { return }
        operationState = .failed(
            PrismSkinFailure(
                localizationKey: "skins.adapter.unavailable",
                diagnosticText: "The native skin adapter is not connected in this fixture composition.",
                recoveryAction: .cancel
            )
        )
    }
}

struct PrismSkinManagementView: View {
    @ObservedObject var model: PrismSkinManagementModel
    @StateObject private var imageStore: PrismSkinPreviewImageStore
    @State private var renameText = ""
    @State private var confirmsDelete = false
    @State private var confirmsReset = false

    init(model: PrismSkinManagementModel) {
        self.model = model
        _imageStore = StateObject(wrappedValue: PrismSkinPreviewImageStore()!)
    }

    var body: some View {
        NavigationSplitView {
            skinList
                .navigationTitle("Skins")
                .toolbar {
                    ToolbarItemGroup {
                        Button("Import File", systemImage: "square.and.arrow.down") {
                            _ = model.beginImportFile()
                        }
                        .accessibilityIdentifier("prism.skins.import-file")
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            _ = model.beginLoad()
                        }
                        .disabled(model.isRunning)
                        .accessibilityIdentifier("prism.skins.refresh")
                    }
                }
        } detail: {
            detailView
        }
        .frame(minWidth: 980, minHeight: 660)
        .confirmationDialog(
            "Delete Skin",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                _ = model.deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected skin will be removed from the native skin list.")
        }
        .confirmationDialog(
            "Reset Skin",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                _ = model.resetSkin()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The active Minecraft skin will be removed from the account profile.")
        }
        .accessibilityIdentifier("prism.skins")
    }

    @ViewBuilder
    private var skinList: some View {
        switch model.listState {
        case .loading:
            ProgressView("Loading Skins…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("prism.skins.loading")
        case .empty:
            ContentUnavailableView(
                "No Saved Skins",
                systemImage: "person.crop.square",
                description: Text("Import a PNG skin or add one from a URL or username.")
            )
            .accessibilityIdentifier("prism.skins.empty")
        case .cancelled:
            ContentUnavailableView {
                Label("Skin Loading Cancelled", systemImage: "pause.circle")
            } description: {
                Text("Skin loading was cancelled before a list was confirmed.")
            } actions: {
                Button("Retry") { _ = model.beginLoad() }
                    .accessibilityIdentifier("prism.skins.retry-cancelled")
            }
            .accessibilityIdentifier("prism.skins.cancelled")
        case .failed(let failure):
            ContentUnavailableView {
                Label("Skins Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure.diagnosticText ?? failure.localizationKey)
            } actions: {
                Button("Retry") { _ = model.retry() }
                    .disabled(!failure.isRetryAvailable)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("prism.skins.retry")
            }
            .accessibilityIdentifier("prism.skins.failed")
        case .content:
            if model.skins.isEmpty {
                ContentUnavailableView("No Saved Skins", systemImage: "person.crop.square")
                    .accessibilityIdentifier("prism.skins.empty")
            } else {
                List(
                    model.skins,
                    selection: Binding<String?>(
                        get: { model.selectedSkinIdentifier },
                        set: { _ = model.select(id: $0) }
                    )
                ) { skin in
                    HStack(spacing: 8) {
                        PrismSkinThumbnail(
                            identifier: skin.id,
                            data: skin.previewData ?? skin.textureData,
                            imageStore: imageStore
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skin.name)
                            Text(LocalizedStringKey(skin.model.titleKey))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(skin.id)
                    .help(Text("Select this skin for editing and preview."))
                    .accessibilityIdentifier("prism.skins.\(skin.id)")
                    .accessibilityValue(Text(LocalizedStringKey(skin.model.titleKey)))
                    .contextMenu {
                        Button("Rename") { renameText = skin.name }
                            .accessibilityIdentifier("prism.skins.rename.\(skin.id)")
                        Button("Delete", role: .destructive) { confirmsDelete = true }
                            .disabled(skin.id == model.currentSkinIdentifier)
                            .accessibilityIdentifier("prism.skins.delete.\(skin.id)")
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("prism.skins.list")
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let selectedSkin = model.selectedSkin {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PrismSkinPreviewView(
                        snapshot: selectedSkin,
                        model: model.draftModel,
                        cape: model.selectedCape,
                        showElytra: model.previewElytra
                    )

                    Form {
                        Section("Model") {
                            Picker(
                                "Model",
                                selection: Binding(
                                    get: { model.draftModel },
                                    set: { model.setModel($0) }
                                )
                            ) {
                                ForEach(PrismSkinModelVariant.allCases) { variant in
                                    Text(LocalizedStringKey(variant.titleKey)).tag(variant)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("prism.skins.model")
                        }

                        Section("Cape") {
                            Toggle("Preview Elytra", isOn: $model.previewElytra)
                                .accessibilityIdentifier("prism.skins.elytra")
                            Picker(
                                "Cape",
                                selection: Binding(
                                    get: { model.draftCapeIdentifier },
                                    set: { model.setCapeIdentifier($0) }
                                )
                            ) {
                                Text("No Cape").tag(PrismSkinCape.noneIdentifier)
                                ForEach(model.capes) { cape in
                                    Text(cape.displayName).tag(cape.id)
                                }
                            }
                            .accessibilityIdentifier("prism.skins.cape")
                        }

                        Section("Rename") {
                            TextField("New Skin Name", text: $renameText)
                                .accessibilityIdentifier("prism.skins.rename-field")
                            Button("Rename Selected") {
                                _ = model.renameSelected(to: renameText.isEmpty ? selectedSkin.name : renameText)
                            }
                            .disabled(!model.canRename)
                            .accessibilityIdentifier("prism.skins.rename-submit")
                        }

                        Section("Import") {
                            TextField("URL or Username", text: $model.importText)
                                .textContentType(.URL)
                                .accessibilityIdentifier("prism.skins.import-text")
                            HStack {
                                Button("Import URL") { _ = model.importURL(text: model.importText) }
                                Button("Import User") { _ = model.importUser(text: model.importText) }
                                Button("Import File") { _ = model.beginImportFile() }
                            }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("prism.skins.import-actions")
                        }
                    }
                    .formStyle(.grouped)

                    HStack {
                        Button("Reset Skin", role: .destructive) { confirmsReset = true }
                            .disabled(!model.canReset)
                            .accessibilityIdentifier("prism.skins.reset")
                        Spacer()
                        Button("Delete Skin", role: .destructive) { confirmsDelete = true }
                            .disabled(!model.canDelete)
                            .accessibilityIdentifier("prism.skins.delete")
                        Button("Use This Skin") { _ = model.upload() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!model.canUpload)
                            .accessibilityIdentifier("prism.skins.upload")
                    }

                    operationStatus
                }
                .padding()
            }
            .navigationTitle(selectedSkin.name)
            .accessibilityIdentifier("prism.skins.detail")
        } else {
            ContentUnavailableView(
                "Select a Skin",
                systemImage: "person.crop.square",
                description: Text("Choose a skin from the list to edit and preview it.")
            )
            .accessibilityIdentifier("prism.skins.detail.empty")
        }
    }

    @ViewBuilder
    private var operationStatus: some View {
        switch model.operationState {
        case .idle, .succeeded:
            EmptyView()
        case .running(let operation, _):
            HStack {
                ProgressView(LocalizedStringKey(operation.progressTitleKey))
                Spacer()
                Button("Cancel") { _ = model.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("prism.skins.cancel")
            }
            .accessibilityIdentifier("prism.skins.progress")
        case .cancelled:
            Text("The skin operation was cancelled.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("prism.skins.operation-cancelled")
        case .failed(let failure):
            HStack(alignment: .firstTextBaseline) {
                Text(failure.diagnosticText ?? failure.localizationKey)
                    .foregroundStyle(.secondary)
                Spacer()
                if failure.isRetryAvailable {
                    Button("Retry") { _ = model.retry() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("prism.skins.operation-retry")
                }
            }
            .accessibilityIdentifier("prism.skins.operation-failed")
        }
    }
}

enum PrismSkinFixture {
    static let textureData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    static let skins: [PrismSkinSnapshot] = [
        PrismSkinSnapshot(
            id: "skin.fixture.classic",
            name: "Fixture Classic",
            model: .classic,
            capeIdentifier: "cape.fixture",
            textureData: textureData,
            previewData: textureData
        ),
        PrismSkinSnapshot(
            id: "skin.fixture.slim",
            name: "Fixture Slim",
            model: .slim,
            textureData: textureData,
            previewData: textureData
        ),
    ]

    static let capes: [PrismSkinCape] = [
        PrismSkinCape(id: "cape.fixture", displayName: "Fixture Cape", imageData: textureData)!
    ]

    static let currentSkinIdentifier = "skin.fixture.classic"
}
