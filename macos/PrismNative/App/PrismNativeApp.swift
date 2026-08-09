import SwiftUI

@main
struct PrismNativeApp: App {
    @StateObject private var commandModel = PrismCommandModel()
    @StateObject private var taskModel = PrismTaskPresentationModel()
    @StateObject private var globalSettingsModel = PrismGlobalSettingsModel()
    @StateObject private var javaDiscoveryModel = PrismJavaDiscoveryModel()
    @StateObject private var accountModel = PrismAccountModel()
    @StateObject private var authenticationModel = PrismAccountAuthenticationModel()
    @StateObject private var offlineIdentityModel = PrismOfflineLaunchIdentityModel()
    @StateObject private var shortcutModel = PrismShortcutCreationModel(
        instanceIdentifier: "fixture.instance",
        instanceName: "Fixture Instance",
        worlds: [PrismShortcutWorld(id: "fixture.world", displayName: "Fixture World")],
        profiles: [PrismShortcutProfile(id: "fixture.profile", displayName: "Fixture Profile")]
    )

    var body: some Scene {
        WindowGroup {
            ContentView(commandModel: commandModel, taskModel: taskModel)
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
                offlineIdentityModel: offlineIdentityModel
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
    }
}
