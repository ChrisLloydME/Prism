import SwiftUI

@MainActor
final class PrismNativeRuntime: ObservableObject {
    let applicationIdentity: PRApplicationIdentity?
    let bridge: PRPrismBridge?

    init() {
        guard let identity = PRApplicationIdentity(),
              let bridge = PRPrismBridge(
                  applicationIdentity: identity,
                  cancellationHandler: nil,
                  shutdownHandler: nil
              ) else {
            applicationIdentity = nil
            bridge = nil
            return
        }

        applicationIdentity = identity
        self.bridge = bridge
    }
}

@main
struct PrismNativeApp: App {
    @StateObject private var nativeRuntime: PrismNativeRuntime
    @StateObject private var launchCoordinator: PrismLaunchCoordinator
    @StateObject private var commandModel: PrismCommandModel
    @StateObject private var globalSettingsModel: PrismGlobalSettingsModel
    @StateObject private var javaDiscoveryModel: PrismJavaDiscoveryModel
    @StateObject private var accountModel: PrismAccountModel
    @StateObject private var authenticationModel: PrismAccountAuthenticationModel
    @StateObject private var offlineIdentityModel: PrismOfflineLaunchIdentityModel
    @StateObject private var updateModel: PrismUpdateModel
    @StateObject private var skinModel: PrismSkinManagementModel
    @StateObject private var shortcutModel: PrismShortcutCreationModel

    init() {
        let runtime = PrismNativeRuntime()
        let coordinator = PrismLaunchCoordinator(bridge: runtime.bridge)
        _nativeRuntime = StateObject(wrappedValue: runtime)
        _launchCoordinator = StateObject(wrappedValue: coordinator)
        _commandModel = StateObject(
            wrappedValue: PrismCommandModel(
                onInstanceCommand: { [weak coordinator] intent in
                    coordinator?.handleInstanceCommand(intent)
                },
                bridge: runtime.bridge
            )
        )
        _globalSettingsModel = StateObject(
            wrappedValue: PrismGlobalSettingsModel(initialSettings: nil, bridge: runtime.bridge)
        )
        _javaDiscoveryModel = StateObject(
            wrappedValue: PrismJavaDiscoveryModel(initialInstallations: [], bridge: runtime.bridge)
        )
        _accountModel = StateObject(
            wrappedValue: PrismAccountModel(initialAccounts: [], activeAccountID: nil, bridge: runtime.bridge)
        )
        _authenticationModel = StateObject(
            wrappedValue: PrismAccountAuthenticationModel(bridge: runtime.bridge)
        )
        _offlineIdentityModel = StateObject(
            wrappedValue: PrismOfflineLaunchIdentityModel(bridge: runtime.bridge)
        )
        _updateModel = StateObject(wrappedValue: PrismUpdateModel(bridge: runtime.bridge))
        _skinModel = StateObject(
            wrappedValue: PrismSkinManagementModel(
                accountIdentifier: "",
                initialSkins: [],
                initialCapes: [],
                currentSkinIdentifier: nil,
                bridge: runtime.bridge
            )
        )
        _shortcutModel = StateObject(
            wrappedValue: PrismShortcutCreationModel(
                instanceIdentifier: "",
                instanceName: "",
                worlds: [],
                profiles: [],
                iconKeys: ["default"],
                bridge: runtime.bridge
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                commandModel: commandModel,
                taskModel: launchCoordinator.taskModel,
                logModel: launchCoordinator.logModel,
                bridge: nativeRuntime.bridge
            )
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            PrismCommands(model: commandModel) { identifier in
                shortcutModel.setInstanceContext(identifier: identifier, name: identifier)
            }
        }

        Window("Settings", id: "prism.settings") {
            PrismSettingsView(
                model: globalSettingsModel,
                javaModel: javaDiscoveryModel,
                accountModel: accountModel,
                authenticationModel: authenticationModel,
                offlineIdentityModel: offlineIdentityModel,
                skinModel: skinModel
            )
        }
        .defaultSize(width: 920, height: 640)
        .windowToolbarStyle(.unified(showsTitle: true))

        Window("About Prism", id: "prism.about") {
            PrismAboutView(metadata: PrismAboutMetadata.fromBundle())
        }
        .defaultSize(width: 520, height: 460)

        Window("Check for Updates", id: "prism.updates") {
            PrismUpdateWindow(model: updateModel)
        }
        .defaultSize(width: 600, height: 420)

        Window("Create Shortcut", id: "prism.create-shortcut") {
            PrismShortcutCreationView(model: shortcutModel)
        }
        .defaultSize(width: 600, height: 500)

        Window("Manage Skins", id: "prism.skin-management") {
            PrismSkinManagementView(model: skinModel)
        }
        .defaultSize(width: 980, height: 660)
    }
}
