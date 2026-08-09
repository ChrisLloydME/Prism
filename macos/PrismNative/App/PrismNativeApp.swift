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
    @StateObject private var commandModel: PrismCommandModel
    @StateObject private var taskModel = PrismTaskPresentationModel()
    @StateObject private var globalSettingsModel: PrismGlobalSettingsModel
    @StateObject private var javaDiscoveryModel: PrismJavaDiscoveryModel
    @StateObject private var accountModel: PrismAccountModel
    @StateObject private var authenticationModel: PrismAccountAuthenticationModel
    @StateObject private var offlineIdentityModel: PrismOfflineLaunchIdentityModel
    @StateObject private var skinModel = PrismSkinManagementModel()
    @StateObject private var shortcutModel = PrismShortcutCreationModel(
        instanceIdentifier: "",
        instanceName: "",
        worlds: [],
        profiles: []
    )

    init() {
        let runtime = PrismNativeRuntime()
        _nativeRuntime = StateObject(wrappedValue: runtime)
        _commandModel = StateObject(wrappedValue: PrismCommandModel(bridge: runtime.bridge))
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView(commandModel: commandModel, taskModel: taskModel, bridge: nativeRuntime.bridge)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            PrismCommands(model: commandModel) { identifier in
                shortcutModel.setInstanceContext(identifier: identifier, name: identifier)
            }
        }

        Settings {
            PrismSettingsView(
                model: globalSettingsModel,
                javaModel: javaDiscoveryModel,
                accountModel: accountModel,
                authenticationModel: authenticationModel,
                offlineIdentityModel: offlineIdentityModel,
                skinModel: skinModel
            )
        }

        Window("About Prism", id: "prism.about") {
            PrismAboutView(metadata: PrismAboutMetadata.fromBundle())
        }
        .defaultSize(width: 520, height: 460)

        Window("News", id: "prism.news") {
            PrismNewsWindow()
        }
        .defaultSize(width: 760, height: 520)

        Window("Check for Updates", id: "prism.updates") {
            PrismUpdateWindow()
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
