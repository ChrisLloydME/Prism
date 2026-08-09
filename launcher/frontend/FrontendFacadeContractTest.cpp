// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <utility>

namespace {

std::filesystem::path makeFixtureRoot(std::error_code& error)
{
    const auto temporaryRoot = std::filesystem::temp_directory_path(error);
    if (error) {
        return {};
    }

    const auto suffix = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto fixtureRoot = temporaryRoot / ("prism-frontend-contract-" + std::to_string(suffix));
    if (!std::filesystem::create_directory(fixtureRoot, error)) {
        return {};
    }
    return fixtureRoot;
}

}  // namespace

FrontendRuntimeDependencies makeFixtureDependencies()
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::time_point{}; };
    dependencies.cancelPendingWork = [] {};
    dependencies.shutdown = [] {};
    return dependencies;
}

FrontendInstanceSettingsSnapshot fixtureSettings(const std::string& identifier)
{
    FrontendInstanceSettingsSnapshot settings;
    settings.id = identifier;
    settings.windowOverrideEnabled = true;
    settings.launchMaximized = true;
    settings.windowWidth = 1280;
    settings.windowHeight = 720;
    settings.closeAfterLaunch = true;
    settings.quitAfterGameStop = false;
    settings.consoleOverrideEnabled = true;
    settings.showConsole = true;
    settings.showConsoleOnError = true;
    settings.autoCloseConsole = false;
    settings.globalDataPacksEnabled = true;
    settings.globalDataPacksPath = "datapacks";
    settings.gameTimeOverrideEnabled = true;
    settings.showGameTime = true;
    settings.recordGameTime = true;
    settings.countGameTime = true;
    settings.joinServerOnLaunch = true;
    settings.joinTarget = FrontendInstanceJoinTarget::Server;
    settings.joinServerAddress = "fixture.example:25565";
    settings.overrideModDownloadLoaders = true;
    settings.modDownloadLoaders = { "Fabric", "Quilt" };
    settings.javaLocationOverrideEnabled = true;
    settings.javaPath = "/fixture/bin/java";
    settings.ignoreJavaCompatibility = true;
    settings.memoryOverrideEnabled = true;
    settings.minMemoryMiB = 512;
    settings.maxMemoryMiB = 4096;
    settings.permGenMiB = 128;
    settings.lowMemoryWarning = true;
    settings.javaArgumentsOverrideEnabled = true;
    settings.jvmArguments = "-Dfixture=true";
    settings.commandOverrideEnabled = true;
    settings.preLaunchCommand = "prepare-fixture";
    settings.wrapperCommand = "wrapper-fixture";
    settings.postExitCommand = "cleanup-fixture";
    settings.legacySettingsOverrideEnabled = true;
    settings.onlineFixes = false;
    settings.nativeWorkaroundsOverrideEnabled = true;
    settings.useNativeGLFW = true;
    settings.customGLFWPath = "/fixture/libglfw.dylib";
    settings.useNativeOpenAL = true;
    settings.customOpenALPath = "/fixture/libopenal.dylib";
    return settings;
}

FrontendGlobalSettingsSnapshot fixtureGlobalSettings(const std::filesystem::path& fixtureRoot)
{
    FrontendGlobalSettingsSnapshot settings;
    settings.instanceDirectory = fixtureRoot / "instances";
    settings.iconTheme = "fixture-icons";
    settings.applicationTheme = "fixture-theme";
    settings.backgroundCat = "fixture-cat";
    settings.catOpacity = 73;
    settings.catFit = "strech";
    settings.language = "en_US";
    settings.useSystemLocale = true;
    settings.menuBarInsteadOfToolBar = true;
    settings.statusBarVisible = false;
    settings.toolbarsLocked = true;
    settings.numberOfConcurrentTasks = 10;
    settings.numberOfConcurrentDownloads = 6;
    settings.numberOfManualRetries = 2;
    settings.requestTimeoutSeconds = 60;
    settings.consoleFont = "Menlo";
    settings.consoleFontSize = 12;
    settings.consoleMaxLines = 20000;
    settings.consoleOverflowStop = false;
    settings.showConsole = true;
    settings.autoCloseConsole = true;
    settings.showConsoleOnError = false;
    settings.logPrePostOutput = true;
    return settings;
}

FrontendJavaInstallationSnapshot fixtureJavaInstallation(
    const std::filesystem::path& fixtureRoot,
    const std::string& identifier,
    FrontendJavaInstallationValidity validity = FrontendJavaInstallationValidity::Valid)
{
    FrontendJavaInstallationSnapshot installation;
    installation.id = identifier;
    installation.version = validity == FrontendJavaInstallationValidity::Valid ? "21.0.2" : "8.0.392";
    installation.vendor = "Fixture JDK";
    installation.architecture = "aarch64";
    installation.executablePath = fixtureRoot / "java" / identifier / "bin" / "java";
    installation.is64Bit = true;
    installation.managed = identifier == "fixture-managed";
    installation.validity = validity;
    installation.diagnosticText = validity == FrontendJavaInstallationValidity::Valid
        ? ""
        : "Fixture Java installation is not usable.";
    return installation;
}

FrontendAccountSnapshot fixtureAccount(
    const std::string& identifier,
    const std::string& displayName,
    FrontendAccountType type = FrontendAccountType::Microsoft,
    FrontendAccountState state = FrontendAccountState::Online,
    bool ownsMinecraft = true,
    bool isBusy = false,
    bool canBeSelected = true)
{
    FrontendAccountSnapshot account;
    account.id = identifier;
    account.displayName = displayName;
    account.type = type;
    account.state = state;
    account.ownsMinecraft = ownsMinecraft;
    account.isBusy = isBusy;
    account.canBeSelected = canBeSelected;
    account.diagnosticText = state == FrontendAccountState::Online ? "" : "Fixture account is not ready.";
    return account;
}

template <typename Function>
bool throwsInvalidArgument(Function&& function)
{
    try {
        function();
    } catch (const std::invalid_argument&) {
        return true;
    }
    return false;
}

template <typename Function>
bool throwsLogicError(Function&& function)
{
    try {
        function();
    } catch (const std::logic_error&) {
        return true;
    }
    return false;
}

int main()
{
    std::error_code error;
    const auto fixtureRoot = makeFixtureRoot(error);
    if (error || fixtureRoot.empty()) {
        return 1;
    }

    const auto fixtureMarker = fixtureRoot / "fixture.marker";
    {
        std::ofstream marker(fixtureMarker);
        if (!marker) {
            std::filesystem::remove(fixtureRoot, error);
            return 2;
        }
        marker << "temporary fixture";
    }

    {
        FrontendFacade facade(fixtureRoot / "nested" / "..", makeFixtureDependencies());
        if (facade.dataRoot() != fixtureRoot.lexically_normal() || !facade.hasRuntimeDependencies()) {
            std::filesystem::remove(fixtureMarker, error);
            std::filesystem::remove(fixtureRoot, error);
            return 3;
        }
    }

    auto emptyDependencies = makeFixtureDependencies();
    emptyDependencies.loadInstanceSnapshots = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceSnapshot>{};
    };
    emptyDependencies.loadInstanceChanges = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceChange>{};
    };
    FrontendFacade emptyFacade(fixtureRoot, std::move(emptyDependencies));
    const bool emptyContract = emptyFacade.instanceSnapshots().empty() && emptyFacade.instanceChanges().empty();

    const FrontendInstanceSnapshot firstInstance{ "fixture-one", "Fixture One", "grass", "group-a" };
    const FrontendInstanceSnapshot secondInstance{ "fixture-two", "Fixture Two", "stone", "" };
    bool snapshotRootMatches = false;
    bool changeRootMatches = false;
    auto fixtureDependencies = makeFixtureDependencies();
    fixtureDependencies.loadInstanceSnapshots = [&](const std::filesystem::path& root) {
        snapshotRootMatches = root == fixtureRoot.lexically_normal();
        return std::vector<FrontendInstanceSnapshot>{ firstInstance, secondInstance };
    };
    fixtureDependencies.loadInstanceChanges = [&](const std::filesystem::path& root) {
        changeRootMatches = root == fixtureRoot.lexically_normal();
        return std::vector<FrontendInstanceChange>{
            { FrontendInstanceChangeKind::Added, firstInstance },
            { FrontendInstanceChangeKind::Updated, secondInstance },
            { FrontendInstanceChangeKind::Removed, { secondInstance.id, {}, {}, {} } },
        };
    };
    FrontendFacade fixtureFacade(fixtureRoot / "nested" / "..", std::move(fixtureDependencies));
    const auto snapshots = fixtureFacade.instanceSnapshots();
    const auto changes = fixtureFacade.instanceChanges();
    const bool fixtureSnapshotContract = snapshots.size() == 2 && snapshots[0].id == "fixture-one"
        && snapshots[1].groupId.empty() && snapshotRootMatches;
    const bool fixtureChangeContract = changes.size() == 3 && changes[0].kind == FrontendInstanceChangeKind::Added
        && changes[1].kind == FrontendInstanceChangeKind::Updated && changes[2].kind == FrontendInstanceChangeKind::Removed
        && changes[2].instance.id == "fixture-two" && changeRootMatches;

    std::vector<std::string> detailsCalls;
    std::vector<std::string> notesUpdateCalls;
    bool detailsRootMatches = true;
    bool notesRootMatches = true;
    auto detailsDependencies = makeFixtureDependencies();
    detailsDependencies.loadInstanceDetails = [&](const std::filesystem::path& root, const std::string& identifier)
        -> std::optional<FrontendInstanceDetailsSnapshot> {
        detailsRootMatches = detailsRootMatches && root == fixtureRoot.lexically_normal();
        detailsCalls.push_back(identifier);
        if (identifier == "fixture-one") {
            return FrontendInstanceDetailsSnapshot{ "fixture-one", "Fixture One", "grass", "group-a", "Minecraft",
                                                    "Keep this fixture offline.", true };
        }
        return std::nullopt;
    };
    detailsDependencies.updateInstanceNotes = [&](const std::filesystem::path& root,
                                                   const std::string& identifier,
                                                   const std::string& notes) {
        notesRootMatches = notesRootMatches && root == fixtureRoot.lexically_normal();
        notesUpdateCalls.push_back(identifier + ":" + notes);
        if (identifier == "fixture-one") {
            return FrontendInstanceNotesUpdateResult{ FrontendInstanceNotesUpdateOutcome::Succeeded, notes };
        }
        if (identifier == "unknown-instance") {
            return FrontendInstanceNotesUpdateResult{ FrontendInstanceNotesUpdateOutcome::UnknownInstance, {} };
        }
        return FrontendInstanceNotesUpdateResult{ FrontendInstanceNotesUpdateOutcome::Rejected, {} };
    };
    FrontendFacade detailsFacade(fixtureRoot / "nested" / "..", std::move(detailsDependencies));
    const auto loadedDetails = detailsFacade.instanceDetails("fixture-one");
    const auto missingDetails = detailsFacade.instanceDetails("unknown-instance");
    const auto savedNotes = detailsFacade.updateInstanceNotes("fixture-one", "Updated fixture notes");
    const auto unknownNotes = detailsFacade.updateInstanceNotes("unknown-instance", "Ignored notes");
    const auto rejectedNotes = detailsFacade.updateInstanceNotes("rejected-instance", "Rejected notes");
    const bool detailsContract = loadedDetails.has_value() && loadedDetails->name == "Fixture One"
        && loadedDetails->instanceType == "Minecraft" && loadedDetails->notes == "Keep this fixture offline."
        && loadedDetails->notesEditable && !missingDetails.has_value() && savedNotes.outcome == FrontendInstanceNotesUpdateOutcome::Succeeded
        && savedNotes.notes == "Updated fixture notes"
        && unknownNotes.outcome == FrontendInstanceNotesUpdateOutcome::UnknownInstance
        && rejectedNotes.outcome == FrontendInstanceNotesUpdateOutcome::Rejected && detailsRootMatches && notesRootMatches
        && detailsCalls == std::vector<std::string>{ "fixture-one", "unknown-instance" }
        && notesUpdateCalls == std::vector<std::string>{ "fixture-one:Updated fixture notes", "unknown-instance:Ignored notes",
                                                           "rejected-instance:Rejected notes" };
    const bool rejectedInvalidDetailsIdentifiers = throwsInvalidArgument([&detailsFacade] {
        (void) detailsFacade.instanceDetails("");
    }) && throwsInvalidArgument([&detailsFacade] {
        (void) detailsFacade.updateInstanceNotes("", "fixture notes");
    });
    const bool missingDetailsPortsAreSafe = !emptyFacade.instanceDetails("fixture-one").has_value()
        && emptyFacade.updateInstanceNotes("fixture-one", "fixture notes").outcome == FrontendInstanceNotesUpdateOutcome::Rejected;

    std::vector<std::string> componentCalls;
    bool componentRootMatches = true;
    auto componentDependencies = makeFixtureDependencies();
    componentDependencies.loadInstanceComponents = [&](const std::filesystem::path& root, const std::string& identifier)
        -> std::optional<std::vector<FrontendInstanceComponentSnapshot>> {
        componentRootMatches = componentRootMatches && root == fixtureRoot.lexically_normal();
        componentCalls.push_back(identifier);
        if (identifier == "empty-instance") {
            return std::vector<FrontendInstanceComponentSnapshot>{};
        }
        if (identifier != "fixture-one") {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceComponentSnapshot>{
            { "net.minecraft", "Minecraft", "1.20.1", true, false, false, true, false,
              FrontendInstanceComponentProblemSeverity::None, {} },
            { "net.fabricmc.fabric-loader", "Fabric Loader", "0.15.11", true, true, false, false, false,
              FrontendInstanceComponentProblemSeverity::Warning, { "Fixture metadata is stale." } },
            { "fixture.custom", "Custom Fixture", "1", false, true, false, false, true,
              FrontendInstanceComponentProblemSeverity::Error, { "Custom component is not loaded." } },
        };
    };
    FrontendFacade componentFacade(fixtureRoot / "nested" / "..", std::move(componentDependencies));
    const auto loadedComponents = componentFacade.instanceComponents("fixture-one");
    const auto emptyComponents = componentFacade.instanceComponents("empty-instance");
    const auto missingComponents = componentFacade.instanceComponents("unknown-instance");
    const bool componentContract = loadedComponents.has_value() && loadedComponents->size() == 3
        && (*loadedComponents)[0].id == "net.minecraft" && (*loadedComponents)[0].important
        && (*loadedComponents)[1].canBeDisabled && (*loadedComponents)[1].problemSeverity
            == FrontendInstanceComponentProblemSeverity::Warning
        && (*loadedComponents)[2].custom && !(*loadedComponents)[2].enabled
        && (*loadedComponents)[2].problemDescriptions.size() == 1 && emptyComponents.has_value()
        && emptyComponents->empty() && !missingComponents.has_value() && componentRootMatches
        && componentCalls == std::vector<std::string>{ "fixture-one", "empty-instance", "unknown-instance" };
    const bool rejectedInvalidComponentIdentifier = throwsInvalidArgument([&componentFacade] {
        (void) componentFacade.instanceComponents("");
    });
    const bool missingComponentPortIsSafe = !emptyFacade.instanceComponents("fixture-one").has_value();

    auto invalidComponentDependencies = makeFixtureDependencies();
    invalidComponentDependencies.loadInstanceComponents = [](const std::filesystem::path&, const std::string&)
        -> std::optional<std::vector<FrontendInstanceComponentSnapshot>> {
        return std::vector<FrontendInstanceComponentSnapshot>{
            { "duplicate", "First", "1", true, false, false, false, false,
              FrontendInstanceComponentProblemSeverity::None, {} },
            { "duplicate", "Second", "2", true, false, false, false, false,
              FrontendInstanceComponentProblemSeverity::None, {} },
        };
    };
    FrontendFacade invalidComponentFacade(fixtureRoot, std::move(invalidComponentDependencies));
    const bool rejectedInvalidComponents = throwsInvalidArgument([&invalidComponentFacade] {
        (void) invalidComponentFacade.instanceComponents("fixture-one");
    });

    std::vector<std::string> resourceCalls;
    std::vector<std::string> resourceMutationCalls;
    bool resourceRootMatches = true;
    auto resourceDependencies = makeFixtureDependencies();
    resourceDependencies.loadInstanceResources = [&](const std::filesystem::path& root,
                                                      const std::string& identifier,
                                                      FrontendInstanceResourceKind kind)
        -> std::optional<std::vector<FrontendInstanceResourceSnapshot>> {
        resourceRootMatches = resourceRootMatches && root == fixtureRoot.lexically_normal();
        resourceCalls.push_back(identifier + ":" + std::to_string(static_cast<int>(kind)));
        if (identifier == "empty-instance") {
            return std::vector<FrontendInstanceResourceSnapshot>{};
        }
        if (identifier != "fixture-one" || kind != FrontendInstanceResourceKind::Mods) {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceResourceSnapshot>{
            { "mod-one", "Fixture Mod", "1.0", "fixture-mod.jar", "Fixture", FrontendInstanceResourceKind::Mods,
              true, true, true, false, true, {} },
            { "folder-one", "Fixture Folder", "", "fixture-folder", "", FrontendInstanceResourceKind::Mods,
              true, false, true, true, false, { "Folder resources cannot be toggled." } },
        };
    };
    resourceDependencies.mutateInstanceResource = [&](const std::filesystem::path& root,
                                                       const std::string& identifier,
                                                       FrontendInstanceResourceKind kind,
                                                       const FrontendInstanceResourceMutationRequest& request) {
        resourceRootMatches = resourceRootMatches && root == fixtureRoot.lexically_normal();
        resourceMutationCalls.push_back(identifier + ":" + std::to_string(static_cast<int>(kind)) + ":"
                                      + std::to_string(static_cast<int>(request.action)) + ":"
                                      + request.resourceIdentifier + ":" + (request.confirmed ? "confirmed" : "unconfirmed")
                                      + ":" + request.sourcePath.generic_string());
        return FrontendInstanceResourceMutationResult{
            kind,
            request.action,
            FrontendInstanceResourceMutationOutcome::Succeeded,
            identifier,
            request.resourceIdentifier,
            "resource.mutation.succeeded",
            "fixture mutation succeeded",
            false,
        };
    };
    FrontendFacade resourceFacade(fixtureRoot, std::move(resourceDependencies));
    const auto loadedResources = resourceFacade.instanceResources("fixture-one", FrontendInstanceResourceKind::Mods);
    const auto emptyResources = resourceFacade.instanceResources("empty-instance", FrontendInstanceResourceKind::DataPacks);
    const auto missingResources = resourceFacade.instanceResources("unknown-instance", FrontendInstanceResourceKind::Mods);
    const bool resourceContract = loadedResources.has_value() && loadedResources->size() == 2
        && (*loadedResources)[0].id == "mod-one" && (*loadedResources)[0].hasMetadata
        && (*loadedResources)[1].isDirectory && !(*loadedResources)[1].canBeToggled
        && (*loadedResources)[1].problemDescriptions.size() == 1 && emptyResources.has_value()
        && emptyResources->empty() && !missingResources.has_value() && resourceRootMatches
        && resourceCalls == std::vector<std::string>{ "fixture-one:0", "empty-instance:4", "unknown-instance:0" };
    const bool rejectedInvalidResourceKind = throwsInvalidArgument([&resourceFacade] {
        (void) resourceFacade.instanceResources("fixture-one", static_cast<FrontendInstanceResourceKind>(99));
    });
    FrontendInstanceResourceMutationRequest deleteRequest;
    deleteRequest.action = FrontendInstanceResourceAction::Delete;
    deleteRequest.resourceIdentifier = "mod-one";
    const bool rejectedUnconfirmedDelete = throwsInvalidArgument([&resourceFacade, &deleteRequest] {
        (void) resourceFacade.mutateInstanceResource("fixture-one", FrontendInstanceResourceKind::Mods, deleteRequest);
    });
    deleteRequest.confirmed = true;
    const auto deletedResource = resourceFacade.mutateInstanceResource(
        "fixture-one", FrontendInstanceResourceKind::Mods, deleteRequest);
    FrontendInstanceResourceMutationRequest importRequest;
    importRequest.action = FrontendInstanceResourceAction::Import;
    importRequest.resourceIdentifier = "imported-resource";
    importRequest.sourcePath = fixtureRoot / "imported.zip";
    const auto importedResource = resourceFacade.mutateInstanceResource(
        "fixture-one", FrontendInstanceResourceKind::Mods, importRequest);
    FrontendInstanceResourceMutationRequest relativeImportRequest = importRequest;
    relativeImportRequest.sourcePath = "relative.zip";
    const bool rejectedRelativeResourceImport = throwsInvalidArgument([&resourceFacade, &relativeImportRequest] {
        (void) resourceFacade.mutateInstanceResource("fixture-one", FrontendInstanceResourceKind::Mods, relativeImportRequest);
    });
    const bool resourceMutationContract = deletedResource.outcome == FrontendInstanceResourceMutationOutcome::Succeeded
        && deletedResource.action == FrontendInstanceResourceAction::Delete
        && importedResource.outcome == FrontendInstanceResourceMutationOutcome::Succeeded
        && importedResource.resourceIdentifier == "imported-resource"
        && resourceMutationCalls.size() == 2 && resourceMutationCalls[0].ends_with(":mod-one:confirmed:")
        && resourceMutationCalls[1].ends_with(":imported-resource:unconfirmed:" + (fixtureRoot / "imported.zip").generic_string());
    const bool missingResourceMutatorIsSafe = emptyFacade
        .mutateInstanceResource("fixture-one", FrontendInstanceResourceKind::Mods, deleteRequest)
        .outcome == FrontendInstanceResourceMutationOutcome::Rejected;

    auto invalidResourceDependencies = makeFixtureDependencies();
    invalidResourceDependencies.loadInstanceResources = [](const std::filesystem::path&,
                                                           const std::string&,
                                                           FrontendInstanceResourceKind)
        -> std::optional<std::vector<FrontendInstanceResourceSnapshot>> {
        return std::vector<FrontendInstanceResourceSnapshot>{
            { "duplicate", "First", "1", "first.zip", "", FrontendInstanceResourceKind::Mods,
              true, true, true, false, false, {} },
            { "duplicate", "Second", "2", "second.zip", "", FrontendInstanceResourceKind::Mods,
              true, true, true, false, false, {} },
        };
    };
    FrontendFacade invalidResourceFacade(fixtureRoot, std::move(invalidResourceDependencies));
    const bool rejectedInvalidResources = throwsInvalidArgument([&invalidResourceFacade] {
        (void) invalidResourceFacade.instanceResources("fixture-one", FrontendInstanceResourceKind::Mods);
    });
    auto invalidMutationDependencies = makeFixtureDependencies();
    invalidMutationDependencies.mutateInstanceResource = [](const std::filesystem::path&,
                                                             const std::string& identifier,
                                                             FrontendInstanceResourceKind kind,
                                                             const FrontendInstanceResourceMutationRequest& request) {
        return FrontendInstanceResourceMutationResult{
            kind,
            request.action,
            FrontendInstanceResourceMutationOutcome::Succeeded,
            identifier,
            "wrong-resource",
            "resource.invalid",
            "fixture result mismatch",
            false,
        };
    };
    FrontendFacade invalidMutationFacade(fixtureRoot, std::move(invalidMutationDependencies));
    const bool rejectedInvalidMutationResult = throwsInvalidArgument([&invalidMutationFacade, &deleteRequest] {
        (void) invalidMutationFacade.mutateInstanceResource("fixture-one", FrontendInstanceResourceKind::Mods, deleteRequest);
    });

    std::vector<std::string> settingsLoadCalls;
    std::vector<std::string> settingsUpdateCalls;
    bool settingsRootMatches = true;
    auto settingsDependencies = makeFixtureDependencies();
    settingsDependencies.loadInstanceSettings = [&](const std::filesystem::path& root, const std::string& identifier)
        -> std::optional<FrontendInstanceSettingsSnapshot> {
        settingsRootMatches = settingsRootMatches && root == fixtureRoot.lexically_normal();
        settingsLoadCalls.push_back(identifier);
        if (identifier != "fixture-one") {
            return std::nullopt;
        }
        return fixtureSettings(identifier);
    };
    settingsDependencies.updateInstanceSettings = [&](const std::filesystem::path& root,
                                                       const std::string& identifier,
                                                       const FrontendInstanceSettingsSnapshot& requested) {
        settingsRootMatches = settingsRootMatches && root == fixtureRoot.lexically_normal();
        settingsUpdateCalls.push_back(identifier + ":" + std::to_string(requested.windowWidth));
        if (identifier == "fixture-one") {
            auto confirmed = requested;
            confirmed.windowWidth = 1440;
            return FrontendInstanceSettingsUpdateResult{
                FrontendInstanceSettingsUpdateOutcome::Succeeded,
                std::move(confirmed),
            };
        }
        if (identifier == "unknown-instance") {
            return FrontendInstanceSettingsUpdateResult{
                FrontendInstanceSettingsUpdateOutcome::UnknownInstance,
                std::nullopt,
            };
        }
        return FrontendInstanceSettingsUpdateResult{
            FrontendInstanceSettingsUpdateOutcome::Rejected,
            std::nullopt,
        };
    };
    FrontendFacade settingsFacade(fixtureRoot / "nested" / "..", std::move(settingsDependencies));
    const auto loadedSettings = settingsFacade.instanceSettings("fixture-one");
    auto requestedSettings = fixtureSettings("fixture-one");
    requestedSettings.windowWidth = 1366;
    const auto savedSettings = settingsFacade.updateInstanceSettings("fixture-one", requestedSettings);
    const auto unknownSettings = settingsFacade.updateInstanceSettings("unknown-instance", fixtureSettings("unknown-instance"));
    const auto rejectedSettings = settingsFacade.updateInstanceSettings("rejected-instance", fixtureSettings("rejected-instance"));
    const bool settingsContract = loadedSettings.has_value() && loadedSettings->windowWidth == 1280
        && loadedSettings->joinTarget == FrontendInstanceJoinTarget::Server
        && loadedSettings->modDownloadLoaders == std::vector<std::string>{ "Fabric", "Quilt" }
        && loadedSettings->javaPath == "/fixture/bin/java" && loadedSettings->jvmArguments == "-Dfixture=true"
        && savedSettings.outcome == FrontendInstanceSettingsUpdateOutcome::Succeeded && savedSettings.settings.has_value()
        && savedSettings.settings->windowWidth == 1440
        && unknownSettings.outcome == FrontendInstanceSettingsUpdateOutcome::UnknownInstance
        && rejectedSettings.outcome == FrontendInstanceSettingsUpdateOutcome::Rejected && settingsRootMatches
        && settingsLoadCalls == std::vector<std::string>{ "fixture-one" }
        && settingsUpdateCalls == std::vector<std::string>{ "fixture-one:1366", "unknown-instance:1280", "rejected-instance:1280" };
    auto invalidSettingsDependencies = makeFixtureDependencies();
    invalidSettingsDependencies.loadInstanceSettings = [](const std::filesystem::path&, const std::string&) {
        auto invalid = fixtureSettings("fixture-one");
        invalid.windowWidth = 0;
        return std::optional<FrontendInstanceSettingsSnapshot>(std::move(invalid));
    };
    FrontendFacade invalidSettingsFacade(fixtureRoot, std::move(invalidSettingsDependencies));
    const bool invalidSettingsRejected = throwsInvalidArgument([&invalidSettingsFacade] {
        (void) invalidSettingsFacade.instanceSettings("fixture-one");
    });
    auto invalidUpdateDependencies = makeFixtureDependencies();
    invalidUpdateDependencies.updateInstanceSettings = [](const std::filesystem::path&,
                                                           const std::string&,
                                                           const FrontendInstanceSettingsSnapshot&) {
        return FrontendInstanceSettingsUpdateResult{
            FrontendInstanceSettingsUpdateOutcome::Succeeded,
            std::nullopt,
        };
    };
    FrontendFacade invalidUpdateFacade(fixtureRoot, std::move(invalidUpdateDependencies));
    auto mismatchedSettings = fixtureSettings("other-instance");
    const bool invalidSettingsUpdateRejected = throwsInvalidArgument([&invalidUpdateFacade] {
        (void) invalidUpdateFacade.updateInstanceSettings("fixture-one", fixtureSettings("fixture-one"));
    }) && throwsInvalidArgument([&invalidUpdateFacade, &mismatchedSettings] {
        (void) invalidUpdateFacade.updateInstanceSettings("fixture-one", mismatchedSettings);
    });
    const bool missingSettingsPortsAreSafe = !emptyFacade.instanceSettings("fixture-one").has_value()
        && emptyFacade.updateInstanceSettings("fixture-one", fixtureSettings("fixture-one")).outcome
            == FrontendInstanceSettingsUpdateOutcome::Rejected;

    std::size_t globalSettingsLoadCalls = 0;
    std::size_t globalSettingsUpdateCalls = 0;
    bool globalSettingsRootMatches = true;
    auto globalSettingsDependencies = makeFixtureDependencies();
    globalSettingsDependencies.loadGlobalSettings = [&](const std::filesystem::path& root)
        -> std::optional<FrontendGlobalSettingsSnapshot> {
        globalSettingsRootMatches = globalSettingsRootMatches && root == fixtureRoot.lexically_normal();
        ++globalSettingsLoadCalls;
        return fixtureGlobalSettings(fixtureRoot);
    };
    globalSettingsDependencies.updateGlobalSettings = [&](const std::filesystem::path& root,
                                                          const FrontendGlobalSettingsSnapshot& requested) {
        globalSettingsRootMatches = globalSettingsRootMatches && root == fixtureRoot.lexically_normal();
        ++globalSettingsUpdateCalls;
        auto confirmed = requested;
        confirmed.catOpacity = 88;
        return FrontendGlobalSettingsUpdateResult{
            FrontendGlobalSettingsUpdateOutcome::Succeeded,
            std::move(confirmed),
        };
    };
    FrontendFacade globalSettingsFacade(fixtureRoot / "nested" / "..", std::move(globalSettingsDependencies));
    const auto loadedGlobalSettings = globalSettingsFacade.globalSettings();
    auto requestedGlobalSettings = fixtureGlobalSettings(fixtureRoot);
    requestedGlobalSettings.catOpacity = 81;
    const auto savedGlobalSettings = globalSettingsFacade.updateGlobalSettings(requestedGlobalSettings);
    const bool globalSettingsContract = loadedGlobalSettings.has_value()
        && loadedGlobalSettings->instanceDirectory == fixtureRoot / "instances"
        && loadedGlobalSettings->catFit == "strech" && loadedGlobalSettings->catOpacity == 73
        && savedGlobalSettings.outcome == FrontendGlobalSettingsUpdateOutcome::Succeeded
        && savedGlobalSettings.settings.has_value() && savedGlobalSettings.settings->catOpacity == 88
        && globalSettingsLoadCalls == 1 && globalSettingsUpdateCalls == 1 && globalSettingsRootMatches;
    auto invalidGlobalLoadDependencies = makeFixtureDependencies();
    invalidGlobalLoadDependencies.loadGlobalSettings = [&](const std::filesystem::path&) {
        auto invalid = fixtureGlobalSettings(fixtureRoot);
        invalid.catFit = "unknown-fit";
        return std::optional<FrontendGlobalSettingsSnapshot>(std::move(invalid));
    };
    FrontendFacade invalidGlobalLoadFacade(fixtureRoot, std::move(invalidGlobalLoadDependencies));
    const bool invalidGlobalSettingsRejected = throwsInvalidArgument([&invalidGlobalLoadFacade] {
        (void) invalidGlobalLoadFacade.globalSettings();
    });
    auto invalidGlobalUpdateDependencies = makeFixtureDependencies();
    invalidGlobalUpdateDependencies.updateGlobalSettings = [](const std::filesystem::path&,
                                                              const FrontendGlobalSettingsSnapshot&) {
        return FrontendGlobalSettingsUpdateResult{
            FrontendGlobalSettingsUpdateOutcome::Succeeded,
            std::nullopt,
        };
    };
    FrontendFacade invalidGlobalUpdateFacade(fixtureRoot, std::move(invalidGlobalUpdateDependencies));
    auto invalidGlobalRequest = fixtureGlobalSettings(fixtureRoot);
    invalidGlobalRequest.consoleMaxLines = 9999;
    const bool invalidGlobalSettingsUpdateRejected = throwsInvalidArgument([&invalidGlobalUpdateFacade,
                                                                              &invalidGlobalRequest] {
        (void) invalidGlobalUpdateFacade.updateGlobalSettings(invalidGlobalRequest);
    }) && throwsInvalidArgument([&invalidGlobalUpdateFacade, &requestedGlobalSettings] {
        (void) invalidGlobalUpdateFacade.updateGlobalSettings(requestedGlobalSettings);
    });
    const bool missingGlobalSettingsPortsAreSafe = !emptyFacade.globalSettings().has_value()
        && emptyFacade.updateGlobalSettings(fixtureGlobalSettings(fixtureRoot)).outcome
            == FrontendGlobalSettingsUpdateOutcome::Rejected;

    std::size_t javaDiscoveryCalls = 0;
    std::size_t javaSelectionCalls = 0;
    bool javaRootMatches = true;
    auto javaDependencies = makeFixtureDependencies();
    javaDependencies.loadJavaInstallations = [&](const std::filesystem::path& root) {
        javaRootMatches = javaRootMatches && root == fixtureRoot.lexically_normal();
        ++javaDiscoveryCalls;
        return FrontendJavaDiscoveryResult{
            FrontendJavaDiscoveryOutcome::Succeeded,
            { fixtureJavaInstallation(fixtureRoot, "fixture-managed"),
              fixtureJavaInstallation(fixtureRoot, "fixture-incompatible", FrontendJavaInstallationValidity::Incompatible),
              fixtureJavaInstallation(fixtureRoot, "fixture-missing", FrontendJavaInstallationValidity::Unavailable) },
            "",
            "",
            false,
        };
    };
    javaDependencies.selectJavaInstallation = [&](const std::filesystem::path& root, const std::string& identifier) {
        javaRootMatches = javaRootMatches && root == fixtureRoot.lexically_normal();
        ++javaSelectionCalls;
        if (identifier == "fixture-managed") {
            return FrontendJavaSelectionResult{
                FrontendJavaSelectionOutcome::Succeeded,
                fixtureJavaInstallation(fixtureRoot, identifier),
                "",
                "",
            };
        }
        if (identifier == "fixture-incompatible") {
            return FrontendJavaSelectionResult{
                FrontendJavaSelectionOutcome::UnknownInstallation,
                std::nullopt,
                "java.selection.incompatible",
                "The selected Java installation is incompatible.",
            };
        }
        return FrontendJavaSelectionResult{
            FrontendJavaSelectionOutcome::Rejected,
            std::nullopt,
            "java.selection.rejected",
            "Fixture selection was rejected.",
        };
    };
    FrontendFacade javaFacade(fixtureRoot / "nested" / "..", std::move(javaDependencies));
    const auto javaDiscovery = javaFacade.javaInstallations();
    const auto selectedJava = javaFacade.selectJavaInstallation("fixture-managed");
    const auto incompatibleJava = javaFacade.selectJavaInstallation("fixture-incompatible");
    const bool javaContract = javaDiscovery.outcome == FrontendJavaDiscoveryOutcome::Succeeded
        && javaDiscovery.installations.size() == 3 && javaDiscovery.installations[0].managed
        && javaDiscovery.installations[1].validity == FrontendJavaInstallationValidity::Incompatible
        && javaDiscovery.installations[2].validity == FrontendJavaInstallationValidity::Unavailable
        && selectedJava.outcome == FrontendJavaSelectionOutcome::Succeeded && selectedJava.installation.has_value()
        && selectedJava.installation->id == "fixture-managed"
        && incompatibleJava.outcome == FrontendJavaSelectionOutcome::UnknownInstallation
        && javaDiscoveryCalls == 1 && javaSelectionCalls == 2 && javaRootMatches;
    auto invalidJavaDiscoveryDependencies = makeFixtureDependencies();
    invalidJavaDiscoveryDependencies.loadJavaInstallations = [&](const std::filesystem::path&) {
        auto duplicate = fixtureJavaInstallation(fixtureRoot, "duplicate");
        return FrontendJavaDiscoveryResult{
            FrontendJavaDiscoveryOutcome::Succeeded,
            { duplicate, duplicate },
            "",
            "",
            false,
        };
    };
    FrontendFacade invalidJavaDiscoveryFacade(fixtureRoot, std::move(invalidJavaDiscoveryDependencies));
    const bool invalidJavaDiscoveryRejected = throwsInvalidArgument([&invalidJavaDiscoveryFacade] {
        (void) invalidJavaDiscoveryFacade.javaInstallations();
    });
    auto invalidJavaSelectionDependencies = makeFixtureDependencies();
    invalidJavaSelectionDependencies.selectJavaInstallation = [](const std::filesystem::path&, const std::string&) {
        return FrontendJavaSelectionResult{
            FrontendJavaSelectionOutcome::Succeeded,
            std::nullopt,
            "",
            "",
        };
    };
    FrontendFacade invalidJavaSelectionFacade(fixtureRoot, std::move(invalidJavaSelectionDependencies));
    const bool invalidJavaSelectionRejected = throwsInvalidArgument([&invalidJavaSelectionFacade] {
        (void) invalidJavaSelectionFacade.selectJavaInstallation("fixture-managed");
    });
    const bool missingJavaPortsAreSafe = emptyFacade.javaInstallations().outcome == FrontendJavaDiscoveryOutcome::Rejected
        && emptyFacade.selectJavaInstallation("fixture-managed").outcome == FrontendJavaSelectionOutcome::Rejected;

    std::size_t accountSnapshotCalls = 0;
    std::size_t accountSelectionCalls = 0;
    bool accountRootMatches = true;
    auto accountDependencies = makeFixtureDependencies();
    accountDependencies.loadAccountSnapshots = [&](const std::filesystem::path& root) {
        accountRootMatches = accountRootMatches && root == fixtureRoot.lexically_normal();
        ++accountSnapshotCalls;
        return FrontendAccountSnapshotResult{
            FrontendAccountSnapshotOutcome::Succeeded,
            { fixtureAccount("account.fixture.microsoft", "Fixture Microsoft Account"),
              fixtureAccount("account.fixture.offline", "Fixture Offline Profile", FrontendAccountType::Offline,
                             FrontendAccountState::Offline, false),
              fixtureAccount("account.fixture.busy", "Fixture Busy Account", FrontendAccountType::Microsoft,
                             FrontendAccountState::Working, true, true, false) },
            std::string("account.fixture.microsoft"),
            "",
            "",
            false,
        };
    };
    accountDependencies.selectActiveAccount = [&](const std::filesystem::path& root,
                                                   const std::optional<std::string>& identifier) {
        accountRootMatches = accountRootMatches && root == fixtureRoot.lexically_normal();
        ++accountSelectionCalls;
        if (!identifier.has_value()) {
            return FrontendAccountSelectionResult{
                FrontendAccountSelectionOutcome::Succeeded,
                std::nullopt,
                "",
                "",
            };
        }
        if (*identifier == "account.fixture.microsoft") {
            return FrontendAccountSelectionResult{
                FrontendAccountSelectionOutcome::Succeeded,
                fixtureAccount(*identifier, "Fixture Microsoft Account"),
                "",
                "",
            };
        }
        if (*identifier == "account.fixture.offline") {
            return FrontendAccountSelectionResult{
                FrontendAccountSelectionOutcome::Succeeded,
                fixtureAccount(*identifier, "Fixture Offline Profile", FrontendAccountType::Offline,
                               FrontendAccountState::Offline, false),
                "",
                "",
            };
        }
        return FrontendAccountSelectionResult{
            FrontendAccountSelectionOutcome::UnknownAccount,
            std::nullopt,
            "accounts.selection.unknownAccount",
            "Fixture account is no longer available.",
        };
    };
    FrontendFacade accountFacade(fixtureRoot / "nested" / "..", std::move(accountDependencies));
    const auto accountSnapshots = accountFacade.accountSnapshots();
    const auto selectedAccount = accountFacade.selectActiveAccount(std::string("account.fixture.offline"));
    const auto clearedAccount = accountFacade.selectActiveAccount(std::nullopt);
    const auto unknownAccount = accountFacade.selectActiveAccount(std::string("account.fixture.unknown"));
    const bool accountContract = accountSnapshots.outcome == FrontendAccountSnapshotOutcome::Succeeded
        && accountSnapshots.accounts.size() == 3
        && accountSnapshots.accounts[1].type == FrontendAccountType::Offline
        && !accountSnapshots.accounts[1].ownsMinecraft && accountSnapshots.activeAccountIdentifier.has_value()
        && *accountSnapshots.activeAccountIdentifier == "account.fixture.microsoft"
        && selectedAccount.outcome == FrontendAccountSelectionOutcome::Succeeded
        && selectedAccount.account.has_value() && selectedAccount.account->id == "account.fixture.offline"
        && !clearedAccount.account.has_value() && clearedAccount.outcome == FrontendAccountSelectionOutcome::Succeeded
        && unknownAccount.outcome == FrontendAccountSelectionOutcome::UnknownAccount
        && accountSnapshotCalls == 1 && accountSelectionCalls == 3 && accountRootMatches;
    auto invalidAccountSnapshotDependencies = makeFixtureDependencies();
    invalidAccountSnapshotDependencies.loadAccountSnapshots = [](const std::filesystem::path&) {
        const auto duplicate = fixtureAccount("duplicate-account", "Duplicate Fixture Account");
        return FrontendAccountSnapshotResult{
            FrontendAccountSnapshotOutcome::Succeeded,
            { duplicate, duplicate },
            std::nullopt,
            "",
            "",
            false,
        };
    };
    FrontendFacade invalidAccountSnapshotFacade(fixtureRoot, std::move(invalidAccountSnapshotDependencies));
    const bool invalidAccountSnapshotsRejected = throwsInvalidArgument([&invalidAccountSnapshotFacade] {
        (void) invalidAccountSnapshotFacade.accountSnapshots();
    });
    auto invalidAccountSelectionDependencies = makeFixtureDependencies();
    invalidAccountSelectionDependencies.selectActiveAccount = [](const std::filesystem::path&,
                                                                  const std::optional<std::string>& identifier) {
        return FrontendAccountSelectionResult{
            FrontendAccountSelectionOutcome::Succeeded,
            identifier.has_value() ? std::optional<FrontendAccountSnapshot>(
                                         fixtureAccount("different-account", "Different Fixture Account"))
                                   : std::nullopt,
            "",
            "",
        };
    };
    FrontendFacade invalidAccountSelectionFacade(fixtureRoot, std::move(invalidAccountSelectionDependencies));
    const bool invalidAccountSelectionRejected = throwsInvalidArgument([&invalidAccountSelectionFacade] {
        (void) invalidAccountSelectionFacade.selectActiveAccount(std::string("requested-account"));
    });
    const bool missingAccountPortsAreSafe = emptyFacade.accountSnapshots().outcome == FrontendAccountSnapshotOutcome::Rejected
        && emptyFacade.selectActiveAccount(std::string("fixture-account")).outcome
            == FrontendAccountSelectionOutcome::Rejected;

    std::size_t authenticationCalls = 0;
    bool authenticationRootMatches = true;
    std::vector<FrontendAccountAuthenticationProgress> authenticationProgressEvents;
    auto authenticationDependencies = makeFixtureDependencies();
    authenticationDependencies.authenticateAccount = [&](const std::filesystem::path& root,
                                                          const FrontendAccountAuthenticationRequest& request,
                                                          const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progress) {
        authenticationRootMatches = root == fixtureRoot.lexically_normal();
        ++authenticationCalls;
        auto emit = [&](FrontendAccountAuthenticationPhase phase,
                        FrontendAccountAuthenticationOutcome outcome,
                        const char* key,
                        bool canCancel,
                        bool retryable,
                        bool requiresUserAction,
                        const char* verificationURL = "") {
            FrontendAccountAuthenticationProgress event;
            event.accountIdentifier = request.accountIdentifier;
            event.action = request.action;
            event.phase = phase;
            event.outcome = outcome;
            event.providerLabel = "Fixture Provider";
            event.verificationURL = verificationURL;
            event.localizationKey = key;
            event.diagnosticText = "";
            event.expiresInSeconds = verificationURL[0] == '\0' ? 0 : 900;
            event.canCancel = canCancel;
            event.retryable = retryable;
            event.requiresUserAction = requiresUserAction;
            progress(event);
        };

        if (request.action == FrontendAccountAuthenticationAction::Refresh) {
            emit(FrontendAccountAuthenticationPhase::Preparing,
                 FrontendAccountAuthenticationOutcome::InProgress,
                 "accounts.authentication.refreshing",
                 true,
                 false,
                 false);
            emit(FrontendAccountAuthenticationPhase::Failed,
                 FrontendAccountAuthenticationOutcome::Failed,
                 "accounts.authentication.refreshFailed",
                 false,
                 true,
                 false);
            return FrontendAccountAuthenticationResult{
                FrontendAccountAuthenticationOutcome::Failed,
                std::nullopt,
                "accounts.authentication.refreshFailed",
                "Fixture refresh can be retried.",
                true,
            };
        }

        emit(FrontendAccountAuthenticationPhase::Preparing,
             FrontendAccountAuthenticationOutcome::InProgress,
             "accounts.authentication.preparing",
             true,
             false,
             false);
        emit(FrontendAccountAuthenticationPhase::AwaitingUser,
             FrontendAccountAuthenticationOutcome::InProgress,
             "accounts.authentication.awaitingUser",
             true,
             false,
             true,
             "https://login.example.invalid/device");
        emit(FrontendAccountAuthenticationPhase::Authenticating,
             FrontendAccountAuthenticationOutcome::InProgress,
             "accounts.authentication.authenticating",
             true,
             false,
             false);
        emit(FrontendAccountAuthenticationPhase::Succeeded,
             FrontendAccountAuthenticationOutcome::Succeeded,
             "accounts.authentication.succeeded",
             false,
             false,
             false);
        return FrontendAccountAuthenticationResult{
            FrontendAccountAuthenticationOutcome::Succeeded,
            fixtureAccount(request.accountIdentifier, "Fixture Microsoft Account"),
            "accounts.authentication.succeeded",
            "",
            false,
        };
    };
    FrontendFacade authenticationFacade(fixtureRoot / "nested" / "..", std::move(authenticationDependencies));
    FrontendAccountAuthenticationRequest loginRequest;
    loginRequest.accountIdentifier = "account.fixture.microsoft";
    loginRequest.action = FrontendAccountAuthenticationAction::Login;
    const auto loginAuthenticationResult = authenticationFacade.authenticateAccount(
        loginRequest,
        [&](const FrontendAccountAuthenticationProgress& event) { authenticationProgressEvents.push_back(event); });
    FrontendAccountAuthenticationRequest refreshRequest = loginRequest;
    refreshRequest.action = FrontendAccountAuthenticationAction::Refresh;
    const auto refreshAuthenticationResult = authenticationFacade.authenticateAccount(refreshRequest);
    const bool authenticationContract = authenticationProgressEvents.size() == 4
        && authenticationProgressEvents[1].phase == FrontendAccountAuthenticationPhase::AwaitingUser
        && authenticationProgressEvents[1].verificationURL == "https://login.example.invalid/device"
        && authenticationProgressEvents[1].requiresUserAction
        && loginAuthenticationResult.outcome == FrontendAccountAuthenticationOutcome::Succeeded
        && loginAuthenticationResult.account.has_value()
        && loginAuthenticationResult.account->id == "account.fixture.microsoft"
        && refreshAuthenticationResult.outcome == FrontendAccountAuthenticationOutcome::Failed
        && refreshAuthenticationResult.retryable && authenticationCalls == 2 && authenticationRootMatches;
    auto invalidAuthenticationProgressDependencies = makeFixtureDependencies();
    invalidAuthenticationProgressDependencies.authenticateAccount = [](
        const std::filesystem::path&,
        const FrontendAccountAuthenticationRequest& request,
        const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progress) {
        FrontendAccountAuthenticationProgress event;
        event.accountIdentifier = request.accountIdentifier;
        event.action = request.action;
        event.phase = FrontendAccountAuthenticationPhase::AwaitingUser;
        event.outcome = FrontendAccountAuthenticationOutcome::InProgress;
        event.providerLabel = "Fixture Provider";
        event.verificationURL = "https://login.example.invalid/device";
        event.localizationKey = "accounts.authentication.awaitingUser";
        event.expiresInSeconds = 900;
        event.canCancel = true;
        event.requiresUserAction = true;
        progress(event);
        return FrontendAccountAuthenticationResult{
            FrontendAccountAuthenticationOutcome::Succeeded,
            std::nullopt,
            "accounts.authentication.succeeded",
            "",
            false,
        };
    };
    FrontendFacade invalidAuthenticationProgressFacade(fixtureRoot, std::move(invalidAuthenticationProgressDependencies));
    const bool invalidAuthenticationRejected = throwsInvalidArgument([&invalidAuthenticationProgressFacade] {
        FrontendAccountAuthenticationRequest request;
        request.accountIdentifier = "account.fixture.microsoft";
        (void) invalidAuthenticationProgressFacade.authenticateAccount(request);
    });
    const bool missingAuthenticationPortIsSafe = emptyFacade.authenticateAccount(loginRequest).outcome
        == FrontendAccountAuthenticationOutcome::Rejected;

    std::size_t offlineIdentityLoadCalls = 0;
    std::size_t offlineIdentityUpdateCalls = 0;
    bool offlineIdentityRootMatches = true;
    std::string storedOfflineIdentityName = "Saved_Player";
    auto offlineIdentityDependencies = makeFixtureDependencies();
    offlineIdentityDependencies.loadOfflineLaunchIdentity = [&](const std::filesystem::path& root,
                                                                  const FrontendOfflineLaunchIdentityRequest& request) {
        offlineIdentityRootMatches = offlineIdentityRootMatches && root == fixtureRoot.lexically_normal();
        ++offlineIdentityLoadCalls;
        return FrontendOfflineLaunchIdentityLoadResult{
            FrontendOfflineLaunchIdentityLoadOutcome::Succeeded,
            FrontendOfflineLaunchIdentitySnapshot{ request.mode, request.accountIdentifier, storedOfflineIdentityName },
            "accounts.offlineIdentity.loaded",
            "",
            false,
        };
    };
    offlineIdentityDependencies.updateOfflineLaunchIdentity = [&](const std::filesystem::path& root,
                                                                    const FrontendOfflineLaunchIdentityUpdateRequest& request) {
        offlineIdentityRootMatches = offlineIdentityRootMatches && root == fixtureRoot.lexically_normal();
        ++offlineIdentityUpdateCalls;
        if (request.name == "Cancel_Name") {
            return FrontendOfflineLaunchIdentityUpdateResult{
                FrontendOfflineLaunchIdentityUpdateOutcome::Cancelled,
                std::nullopt,
                "accounts.offlineIdentity.cancelled",
                "Fixture identity update was cancelled.",
                false,
            };
        }
        storedOfflineIdentityName = request.name;
        return FrontendOfflineLaunchIdentityUpdateResult{
            FrontendOfflineLaunchIdentityUpdateOutcome::Succeeded,
            FrontendOfflineLaunchIdentitySnapshot{ request.mode, request.accountIdentifier, request.name },
            "accounts.offlineIdentity.saved",
            "",
            false,
        };
    };
    FrontendFacade offlineIdentityFacade(fixtureRoot / "nested" / "..", std::move(offlineIdentityDependencies));
    FrontendOfflineLaunchIdentityRequest offlineIdentityLoadRequest;
    offlineIdentityLoadRequest.mode = FrontendOfflineLaunchIdentityMode::Offline;
    offlineIdentityLoadRequest.accountIdentifier = "account.fixture.offline";
    offlineIdentityLoadRequest.fallbackName = "Player";
    const auto loadedOfflineIdentity = offlineIdentityFacade.loadOfflineLaunchIdentity(offlineIdentityLoadRequest);
    FrontendOfflineLaunchIdentityUpdateRequest invalidOfflineIdentityUpdate;
    invalidOfflineIdentityUpdate.mode = offlineIdentityLoadRequest.mode;
    invalidOfflineIdentityUpdate.accountIdentifier = offlineIdentityLoadRequest.accountIdentifier;
    invalidOfflineIdentityUpdate.name = "bad name";
    const auto invalidOfflineIdentity = offlineIdentityFacade.updateOfflineLaunchIdentity(invalidOfflineIdentityUpdate);
    FrontendOfflineLaunchIdentityUpdateRequest validOfflineIdentityUpdate = invalidOfflineIdentityUpdate;
    validOfflineIdentityUpdate.name = "Native_Player";
    const auto savedOfflineIdentity = offlineIdentityFacade.updateOfflineLaunchIdentity(validOfflineIdentityUpdate);
    FrontendOfflineLaunchIdentityUpdateRequest allowedInvalidOfflineIdentityUpdate = invalidOfflineIdentityUpdate;
    allowedInvalidOfflineIdentityUpdate.name = "Player name";
    allowedInvalidOfflineIdentityUpdate.allowInvalidName = true;
    const auto allowedInvalidOfflineIdentity = offlineIdentityFacade.updateOfflineLaunchIdentity(
        allowedInvalidOfflineIdentityUpdate);
    FrontendOfflineLaunchIdentityUpdateRequest cancelledOfflineIdentityUpdate = validOfflineIdentityUpdate;
    cancelledOfflineIdentityUpdate.name = "Cancel_Name";
    const auto cancelledOfflineIdentity = offlineIdentityFacade.updateOfflineLaunchIdentity(
        cancelledOfflineIdentityUpdate);
    const bool offlineIdentityContract = loadedOfflineIdentity.outcome
            == FrontendOfflineLaunchIdentityLoadOutcome::Succeeded
        && loadedOfflineIdentity.identity.has_value()
        && loadedOfflineIdentity.identity->name == "Saved_Player"
        && invalidOfflineIdentity.outcome == FrontendOfflineLaunchIdentityUpdateOutcome::InvalidName
        && savedOfflineIdentity.outcome == FrontendOfflineLaunchIdentityUpdateOutcome::Succeeded
        && savedOfflineIdentity.identity.has_value() && savedOfflineIdentity.identity->name == "Native_Player"
        && allowedInvalidOfflineIdentity.outcome == FrontendOfflineLaunchIdentityUpdateOutcome::Succeeded
        && allowedInvalidOfflineIdentity.identity.has_value() && allowedInvalidOfflineIdentity.identity->name == "Player name"
        && cancelledOfflineIdentity.outcome == FrontendOfflineLaunchIdentityUpdateOutcome::Cancelled
        && offlineIdentityLoadCalls == 1 && offlineIdentityUpdateCalls == 3 && offlineIdentityRootMatches;
    auto invalidOfflineLoadDependencies = makeFixtureDependencies();
    invalidOfflineLoadDependencies.loadOfflineLaunchIdentity = [](
        const std::filesystem::path&,
        const FrontendOfflineLaunchIdentityRequest&) {
        return FrontendOfflineLaunchIdentityLoadResult{
            FrontendOfflineLaunchIdentityLoadOutcome::Succeeded,
            std::nullopt,
            "accounts.offlineIdentity.loaded",
            "",
            false,
        };
    };
    FrontendFacade invalidOfflineLoadFacade(fixtureRoot, std::move(invalidOfflineLoadDependencies));
    const bool invalidOfflineLoadRejected = throwsInvalidArgument([&invalidOfflineLoadFacade, &offlineIdentityLoadRequest] {
        (void) invalidOfflineLoadFacade.loadOfflineLaunchIdentity(offlineIdentityLoadRequest);
    });
    auto invalidOfflineUpdateDependencies = makeFixtureDependencies();
    invalidOfflineUpdateDependencies.updateOfflineLaunchIdentity = [](
        const std::filesystem::path&,
        const FrontendOfflineLaunchIdentityUpdateRequest& request) {
        return FrontendOfflineLaunchIdentityUpdateResult{
            FrontendOfflineLaunchIdentityUpdateOutcome::Succeeded,
            FrontendOfflineLaunchIdentitySnapshot{
                FrontendOfflineLaunchIdentityMode::Demo, request.accountIdentifier, request.name },
            "accounts.offlineIdentity.saved",
            "",
            false,
        };
    };
    FrontendFacade invalidOfflineUpdateFacade(fixtureRoot, std::move(invalidOfflineUpdateDependencies));
    const bool invalidOfflineUpdateRejected = throwsInvalidArgument([&invalidOfflineUpdateFacade, &validOfflineIdentityUpdate] {
        (void) invalidOfflineUpdateFacade.updateOfflineLaunchIdentity(validOfflineIdentityUpdate);
    });
    const bool missingOfflineIdentityPortsAreSafe = emptyFacade.loadOfflineLaunchIdentity(offlineIdentityLoadRequest).outcome
            == FrontendOfflineLaunchIdentityLoadOutcome::Rejected
        && emptyFacade.updateOfflineLaunchIdentity(validOfflineIdentityUpdate).outcome
            == FrontendOfflineLaunchIdentityUpdateOutcome::Rejected;

    FrontendVanillaCreationRequest vanillaRequest;
    vanillaRequest.versionDescriptor = "1.21.1";
    vanillaRequest.versionName = "1.21.1 Release";
    vanillaRequest.loaderIdentifier = "net.fabricmc.fabric-loader";
    vanillaRequest.loaderVersionDescriptor = "0.16.10";
    vanillaRequest.name = "Fixture Vanilla";
    vanillaRequest.groupId = "fixture-group";
    vanillaRequest.iconKey = "default";
    std::size_t vanillaCreationCalls = 0;
    std::size_t vanillaProgressEvents = 0;
    bool vanillaRootMatches = true;
    bool vanillaCancellationCheckObserved = false;
    auto vanillaDependencies = makeFixtureDependencies();
    vanillaDependencies.createVanillaInstance = [&](
                                                 const std::filesystem::path& root,
                                                 const FrontendVanillaCreationRequest& request,
                                                 const FrontendRuntimeDependencies::VanillaCreationProgressHandler& progress,
                                                 const FrontendRuntimeDependencies::VanillaCreationCancellationCheck& isCancelled) {
        vanillaRootMatches = vanillaRootMatches && root == fixtureRoot.lexically_normal();
        ++vanillaCreationCalls;
        if (request.versionDescriptor != "1.21.1" || !request.loaderIdentifier.has_value()
            || *request.loaderIdentifier != "net.fabricmc.fabric-loader"
            || !request.loaderVersionDescriptor.has_value() || *request.loaderVersionDescriptor != "0.16.10") {
            return FrontendVanillaCreationResult{
                FrontendVanillaCreationOutcome::Rejected,
                std::nullopt,
                "instances.creation.vanilla.invalidRequest",
                "Fixture request did not preserve loader metadata.",
                false,
            };
        }

        progress(FrontendTaskSnapshot{ "creation.vanilla", "Create Vanilla", FrontendTaskState::Queued,
                                       FrontendTaskProgressKind::None, 0.0, true, {}, std::nullopt });
        ++vanillaProgressEvents;
        progress(FrontendTaskSnapshot{ "creation.vanilla", "Create Vanilla", FrontendTaskState::Running,
                                       FrontendTaskProgressKind::Determinate, 0.5, true, {}, std::nullopt });
        ++vanillaProgressEvents;
        if (isCancelled && isCancelled()) {
            vanillaCancellationCheckObserved = true;
            const FrontendTaskTerminalResult terminal{
                FrontendTaskTerminalOutcome::Cancelled, "instances.creation.vanilla.cancelled", {}, "Fixture cancelled", false };
            progress(FrontendTaskSnapshot{ "creation.vanilla", "Create Vanilla", FrontendTaskState::Cancelled,
                                           FrontendTaskProgressKind::Determinate, 0.5, false, {}, terminal });
            ++vanillaProgressEvents;
            return FrontendVanillaCreationResult{
                FrontendVanillaCreationOutcome::Cancelled,
                std::nullopt,
                "instances.creation.vanilla.cancelled",
                "Fixture cancelled",
                false,
            };
        }

        const FrontendTaskTerminalResult terminal{
            FrontendTaskTerminalOutcome::Succeeded, "instances.creation.vanilla.created", {}, "", false };
        progress(FrontendTaskSnapshot{ "creation.vanilla", "Create Vanilla", FrontendTaskState::Succeeded,
                                       FrontendTaskProgressKind::Determinate, 1.0, false, {}, terminal });
        ++vanillaProgressEvents;
        return FrontendVanillaCreationResult{
            FrontendVanillaCreationOutcome::Succeeded,
            FrontendInstanceSnapshot{ "fixture.vanilla", request.name, request.iconKey, request.groupId },
            "instances.creation.vanilla.created",
            "",
            false,
        };
    };
    FrontendFacade vanillaFacade(fixtureRoot / "nested" / "..", std::move(vanillaDependencies));
    const auto createdVanilla = vanillaFacade.createVanillaInstance(vanillaRequest);
    const auto cancelledVanilla = vanillaFacade.createVanillaInstance(
        vanillaRequest, {}, [] { return true; });
    const bool vanillaCreationContract = createdVanilla.outcome == FrontendVanillaCreationOutcome::Succeeded
        && createdVanilla.instance.has_value() && createdVanilla.instance->id == "fixture.vanilla"
        && createdVanilla.instance->name == "Fixture Vanilla"
        && cancelledVanilla.outcome == FrontendVanillaCreationOutcome::Cancelled
        && !cancelledVanilla.instance.has_value() && vanillaCreationCalls == 2 && vanillaProgressEvents == 6
        && vanillaRootMatches && vanillaCancellationCheckObserved;
    const bool rejectedInvalidVanillaRequest = throwsInvalidArgument([&vanillaFacade] {
        FrontendVanillaCreationRequest invalid;
        invalid.versionDescriptor = "1.21.1";
        invalid.versionName = "1.21.1 Release";
        invalid.iconKey = "default";
        (void) vanillaFacade.createVanillaInstance(invalid);
    });
    const bool missingVanillaCreationPortIsSafe = emptyFacade.createVanillaInstance(vanillaRequest).outcome
        == FrontendVanillaCreationOutcome::Rejected;
    const bool rejectedPostShutdownVanillaCreation = vanillaFacade.shutdown()
        && throwsLogicError([&vanillaFacade, &vanillaRequest] {
               (void) vanillaFacade.createVanillaInstance(vanillaRequest);
           });

    FrontendInstanceImportRequest instanceImportRequest;
    instanceImportRequest.sourceKind = FrontendInstanceImportSourceKind::LocalFile;
    instanceImportRequest.source = (fixtureRoot / "fixture-pack.zip").lexically_normal().string();
    instanceImportRequest.name = "Imported Fixture";
    instanceImportRequest.groupId = "fixture-imports";
    instanceImportRequest.iconKey = "default";
    std::size_t importCalls = 0;
    std::size_t importProgressEvents = 0;
    bool importRootMatches = true;
    bool importSourcePreserved = false;
    bool importCancellationCheckObserved = false;
    auto importDependencies = makeFixtureDependencies();
    importDependencies.importInstance = [&](
                                               const std::filesystem::path& root,
                                               const FrontendInstanceImportRequest& request,
                                               const FrontendRuntimeDependencies::InstanceImportProgressHandler& progress,
                                               const FrontendRuntimeDependencies::InstanceImportCancellationCheck& isCancelled) {
        importRootMatches = importRootMatches && root == fixtureRoot.lexically_normal();
        ++importCalls;
        const bool expectedSource = request.sourceKind == FrontendInstanceImportSourceKind::LocalFile
            ? request.source == instanceImportRequest.source
            : request.source == "https://downloads.example.invalid/fixture-pack.zip";
        importSourcePreserved = importSourcePreserved && expectedSource && request.name == instanceImportRequest.name
            && request.groupId == instanceImportRequest.groupId && request.iconKey == instanceImportRequest.iconKey;
        const std::string taskIdentifier = request.sourceKind == FrontendInstanceImportSourceKind::LocalFile
            ? "instance-import.local"
            : "instance-import.remote";
        progress(FrontendTaskSnapshot{ taskIdentifier, "Import Instance", FrontendTaskState::Queued,
                                       FrontendTaskProgressKind::None, 0.0, true, {}, std::nullopt });
        ++importProgressEvents;
        progress(FrontendTaskSnapshot{ taskIdentifier, "Import Instance", FrontendTaskState::Running,
                                       FrontendTaskProgressKind::Determinate, 0.5, true, {}, std::nullopt });
        ++importProgressEvents;
        if (isCancelled && isCancelled()) {
            importCancellationCheckObserved = true;
            const FrontendTaskTerminalResult terminal{
                FrontendTaskTerminalOutcome::Cancelled, "instances.import.cancelled", {}, "Fixture cancelled", false };
            progress(FrontendTaskSnapshot{ taskIdentifier, "Import Instance", FrontendTaskState::Cancelled,
                                           FrontendTaskProgressKind::Determinate, 0.5, false, {}, terminal });
            ++importProgressEvents;
            return FrontendInstanceImportResult{
                FrontendInstanceImportOutcome::Cancelled,
                std::nullopt,
                "instances.import.cancelled",
                "Fixture cancelled",
                false,
                true,
            };
        }

        const FrontendTaskTerminalResult terminal{
            FrontendTaskTerminalOutcome::Succeeded, "instances.import.completed", {}, "", false };
        progress(FrontendTaskSnapshot{ taskIdentifier, "Import Instance", FrontendTaskState::Succeeded,
                                       FrontendTaskProgressKind::Determinate, 1.0, false, {}, terminal });
        ++importProgressEvents;
        return FrontendInstanceImportResult{
            FrontendInstanceImportOutcome::Succeeded,
            FrontendInstanceSnapshot{ "fixture.imported", request.name, request.iconKey, request.groupId },
            "instances.import.completed",
            "",
            false,
            false,
        };
    };
    instanceImportRequest.source = (fixtureRoot / "fixture-pack.zip").lexically_normal().string();
    importSourcePreserved = true;
    FrontendFacade importFacade(fixtureRoot / "nested" / "..", std::move(importDependencies));
    const auto importedInstance = importFacade.importInstance(instanceImportRequest);
    FrontendInstanceImportRequest remoteImportRequest = instanceImportRequest;
    remoteImportRequest.sourceKind = FrontendInstanceImportSourceKind::RemoteURL;
    remoteImportRequest.source = "https://downloads.example.invalid/fixture-pack.zip";
    const auto cancelledImport = importFacade.importInstance(remoteImportRequest, {}, [] { return true; });
    const bool instanceImportContract = importedInstance.outcome == FrontendInstanceImportOutcome::Succeeded
        && importedInstance.instance.has_value() && importedInstance.instance->id == "fixture.imported"
        && importedInstance.instance->name == "Imported Fixture"
        && cancelledImport.outcome == FrontendInstanceImportOutcome::Cancelled && !cancelledImport.instance.has_value()
        && importCalls == 2 && importProgressEvents == 6 && importRootMatches && importSourcePreserved
        && importCancellationCheckObserved;
    const bool rejectedInvalidImportRequest = throwsInvalidArgument([&importFacade] {
        FrontendInstanceImportRequest invalid;
        invalid.sourceKind = FrontendInstanceImportSourceKind::LocalFile;
        invalid.source = "relative-fixture-pack.zip";
        invalid.name = "Imported Fixture";
        invalid.iconKey = "default";
        (void) importFacade.importInstance(invalid);
    }) && throwsInvalidArgument([&importFacade] {
        FrontendInstanceImportRequest invalid;
        invalid.sourceKind = FrontendInstanceImportSourceKind::RemoteURL;
        invalid.source = "ftp://downloads.example.invalid/fixture-pack.zip";
        invalid.name = "Imported Fixture";
        invalid.iconKey = "default";
        (void) importFacade.importInstance(invalid);
    });
    const bool missingInstanceImportPortIsSafe = emptyFacade.importInstance(instanceImportRequest).outcome
        == FrontendInstanceImportOutcome::Rejected;
    const bool rejectedPostShutdownInstanceImport = importFacade.shutdown()
        && throwsLogicError([&importFacade, &instanceImportRequest] {
               (void) importFacade.importInstance(instanceImportRequest);
           });

    std::vector<std::string> launchCalls;
    std::vector<std::string> stopCalls;
    bool commandRootMatches = true;
    auto commandDependencies = makeFixtureDependencies();
    commandDependencies.launchInstance = [&](const std::filesystem::path& root, const std::string& identifier) {
        commandRootMatches = commandRootMatches && root == fixtureRoot.lexically_normal();
        launchCalls.push_back(identifier);
        if (identifier == "fixture-one") {
            return FrontendInstanceCommandResult::Succeeded;
        }
        if (identifier == "unknown-instance") {
            return FrontendInstanceCommandResult::UnknownInstance;
        }
        return FrontendInstanceCommandResult::Rejected;
    };
    commandDependencies.stopInstance = [&](const std::filesystem::path& root, const std::string& identifier) {
        commandRootMatches = commandRootMatches && root == fixtureRoot.lexically_normal();
        stopCalls.push_back(identifier);
        if (identifier == "fixture-one") {
            return FrontendInstanceCommandResult::Succeeded;
        }
        if (identifier == "unknown-instance") {
            return FrontendInstanceCommandResult::UnknownInstance;
        }
        return FrontendInstanceCommandResult::Rejected;
    };
    FrontendFacade commandFacade(fixtureRoot / "nested" / "..", std::move(commandDependencies));
    const bool commandOutcomes = commandFacade.launchInstance("fixture-one") == FrontendInstanceCommandResult::Succeeded
        && commandFacade.launchInstance("fixture-one") == FrontendInstanceCommandResult::Succeeded
        && commandFacade.launchInstance("unknown-instance") == FrontendInstanceCommandResult::UnknownInstance
        && commandFacade.launchInstance("rejected-instance") == FrontendInstanceCommandResult::Rejected
        && commandFacade.stopInstance("fixture-one") == FrontendInstanceCommandResult::Succeeded
        && commandFacade.stopInstance("fixture-one") == FrontendInstanceCommandResult::Succeeded
        && commandFacade.stopInstance("unknown-instance") == FrontendInstanceCommandResult::UnknownInstance
        && commandFacade.stopInstance("rejected-instance") == FrontendInstanceCommandResult::Rejected;
    const bool repeatedCommandsAreForwarded = launchCalls == std::vector<std::string>{ "fixture-one", "fixture-one", "unknown-instance", "rejected-instance" }
        && stopCalls == std::vector<std::string>{ "fixture-one", "fixture-one", "unknown-instance", "rejected-instance" };
    const bool rejectedInvalidCommandIdentifiers = throwsInvalidArgument([&commandFacade] {
        (void) commandFacade.launchInstance("");
    }) && throwsInvalidArgument([&commandFacade] {
        (void) commandFacade.stopInstance("");
    });
    const bool commandRootContract = commandRootMatches && commandOutcomes && repeatedCommandsAreForwarded
        && rejectedInvalidCommandIdentifiers;
    const bool missingCommandPortsAreRejected = emptyFacade.launchInstance("fixture-one") == FrontendInstanceCommandResult::Rejected
        && emptyFacade.stopInstance("fixture-one") == FrontendInstanceCommandResult::Rejected;
    const bool rejectedPostShutdownCommands = commandFacade.shutdown()
        && throwsLogicError([&commandFacade] {
               (void) commandFacade.launchInstance("fixture-one");
           })
        && throwsLogicError([&commandFacade] {
               (void) commandFacade.stopInstance("fixture-one");
           });

    auto taskSuccess = FrontendTaskTerminalResult{
        FrontendTaskTerminalOutcome::Succeeded,
        "task.completed",
        { { "taskIdentifier", "task.success" } },
        "",
        false,
    };
    auto taskFailure = FrontendTaskTerminalResult{
        FrontendTaskTerminalOutcome::Failed,
        "task.failed",
        { { "taskIdentifier", "task.failed" } },
        "fixture failure",
        true,
    };
    auto taskCancelled = FrontendTaskTerminalResult{
        FrontendTaskTerminalOutcome::Cancelled,
        "task.cancelled",
        {},
        "fixture cancelled",
        false,
    };
    std::vector<std::string> taskSnapshotCalls;
    std::vector<std::string> taskCancellationCalls;
    bool taskRootMatches = true;
    auto taskDependencies = makeFixtureDependencies();
    taskDependencies.loadTaskSnapshot = [&](const std::filesystem::path& root, const std::string& identifier)
        -> std::optional<FrontendTaskSnapshot> {
        taskRootMatches = taskRootMatches && root == fixtureRoot.lexically_normal();
        taskSnapshotCalls.push_back(identifier);
        if (identifier == "task.queued") {
            return FrontendTaskSnapshot{ identifier, "Queued Task", FrontendTaskState::Queued,
                                         FrontendTaskProgressKind::None, 0.0, true, {}, std::nullopt };
        }
        if (identifier == "task.running") {
            return FrontendTaskSnapshot{ identifier,
                                         "Running Task",
                                         FrontendTaskState::Running,
                                         FrontendTaskProgressKind::Determinate,
                                         0.5,
                                         true,
                                         { { "subtask.download", "Download", FrontendTaskState::Running,
                                             FrontendTaskProgressKind::Determinate, 0.5 } },
                                         std::nullopt };
        }
        if (identifier == "task.cancelling") {
            return FrontendTaskSnapshot{ identifier, "Cancelling Task", FrontendTaskState::Cancelling,
                                         FrontendTaskProgressKind::Indeterminate, 0.0, false, {}, std::nullopt };
        }
        if (identifier == "task.success") {
            return FrontendTaskSnapshot{ identifier, "Succeeded Task", FrontendTaskState::Succeeded,
                                         FrontendTaskProgressKind::Determinate, 1.0, false, {}, taskSuccess };
        }
        if (identifier == "task.failed") {
            return FrontendTaskSnapshot{ identifier, "Failed Task", FrontendTaskState::Failed,
                                         FrontendTaskProgressKind::Determinate, 1.0, false, {}, taskFailure };
        }
        if (identifier == "task.cancelled") {
            return FrontendTaskSnapshot{ identifier, "Cancelled Task", FrontendTaskState::Cancelled,
                                         FrontendTaskProgressKind::Indeterminate, 0.0, false, {}, taskCancelled };
        }
        return std::nullopt;
    };
    taskDependencies.cancelTask = [&](const std::filesystem::path& root, const std::string& identifier) {
        taskRootMatches = taskRootMatches && root == fixtureRoot.lexically_normal();
        taskCancellationCalls.push_back(identifier);
        if (identifier == "task.running") {
            return taskCancellationCalls.size() == 1 ? FrontendTaskCancellationResult::Requested
                                                     : FrontendTaskCancellationResult::AlreadyTerminal;
        }
        if (identifier == "unknown-task") {
            return FrontendTaskCancellationResult::UnknownTask;
        }
        return FrontendTaskCancellationResult::Rejected;
    };
    FrontendFacade taskFacade(fixtureRoot / "nested" / "..", std::move(taskDependencies));
    const auto queuedTask = taskFacade.taskSnapshot("task.queued");
    const auto runningTask = taskFacade.taskSnapshot("task.running");
    const auto cancellingTask = taskFacade.taskSnapshot("task.cancelling");
    const auto succeededTask = taskFacade.taskSnapshot("task.success");
    const auto failedTask = taskFacade.taskSnapshot("task.failed");
    const auto cancelledTask = taskFacade.taskSnapshot("task.cancelled");
    const auto unknownTask = taskFacade.taskSnapshot("unknown-task");
    const bool taskStateContract = queuedTask.has_value() && queuedTask->state == FrontendTaskState::Queued
        && queuedTask->cancellationAllowed && runningTask.has_value()
        && runningTask->subtasks.size() == 1 && runningTask->subtasks[0].id == "subtask.download"
        && cancellingTask.has_value() && cancellingTask->state == FrontendTaskState::Cancelling
        && succeededTask.has_value() && succeededTask->terminalResult.has_value()
        && succeededTask->terminalResult->outcome == FrontendTaskTerminalOutcome::Succeeded
        && failedTask.has_value() && failedTask->terminalResult.has_value()
        && failedTask->terminalResult->outcome == FrontendTaskTerminalOutcome::Failed
        && failedTask->terminalResult->partialChangesRolledBack
        && cancelledTask.has_value() && cancelledTask->terminalResult.has_value()
        && cancelledTask->terminalResult->outcome == FrontendTaskTerminalOutcome::Cancelled && !unknownTask.has_value();
    const auto firstTaskCancellation = taskFacade.cancelTask("task.running");
    const auto repeatedTaskCancellation = taskFacade.cancelTask("task.running");
    const auto unknownTaskCancellation = taskFacade.cancelTask("unknown-task");
    const auto rejectedTaskCancellation = taskFacade.cancelTask("task.success");
    const bool taskCancellationContract = firstTaskCancellation == FrontendTaskCancellationResult::Requested
        && repeatedTaskCancellation == FrontendTaskCancellationResult::AlreadyTerminal
        && unknownTaskCancellation == FrontendTaskCancellationResult::UnknownTask
        && rejectedTaskCancellation == FrontendTaskCancellationResult::Rejected
        && taskCancellationCalls == std::vector<std::string>{ "task.running", "task.running", "unknown-task", "task.success" };
    const bool taskForwardingContract = taskRootMatches
        && taskSnapshotCalls == std::vector<std::string>{ "task.queued", "task.running", "task.cancelling", "task.success",
                                                           "task.failed", "task.cancelled", "unknown-task" };
    const bool rejectedInvalidTaskIdentifiers = throwsInvalidArgument([&taskFacade] {
        (void) taskFacade.taskSnapshot("");
    }) && throwsInvalidArgument([&taskFacade] {
        (void) taskFacade.cancelTask("");
    });
    const bool missingTaskPortsAreSafe = !emptyFacade.taskSnapshot("task.fixture").has_value()
        && emptyFacade.cancelTask("task.fixture") == FrontendTaskCancellationResult::Rejected;
    const bool rejectedPostShutdownTaskWork = taskFacade.shutdown()
        && throwsLogicError([&taskFacade] {
               (void) taskFacade.taskSnapshot("task.running");
           })
        && throwsLogicError([&taskFacade] {
               (void) taskFacade.cancelTask("task.running");
           });

    bool logRootMatches = true;
    auto logDependencies = makeFixtureDependencies();
    logDependencies.streamTaskLogs = [&logRootMatches, &fixtureRoot](
                                         const std::filesystem::path& root,
                                         const std::string& identifier,
                                         const FrontendRuntimeDependencies::LogEntryHandler& handler) {
        logRootMatches = logRootMatches && root == fixtureRoot.lexically_normal();
        if (identifier == "task.logs") {
            for (std::uint64_t sequence = 0; sequence < kFrontendLogMaxEntries + 8; ++sequence) {
                std::string text = "fixture log " + std::to_string(sequence);
                if (sequence == kFrontendLogMaxEntries + 7) {
                    text = "Authorization: Bearer fixture-secret access_token=fixture-token path="
                        + fixtureRoot.string() + "/instances/fixture username=fixture-user";
                }
                handler(FrontendLogEntry{ sequence, std::move(text), false });
            }
            return true;
        }
        if (identifier == "task.long-log") {
            handler(FrontendLogEntry{ 1, std::string(kFrontendLogMaxBytes + 32, 'x'), false });
            return true;
        }
        return false;
    };
    FrontendFacade logFacade(fixtureRoot / "nested" / "..", std::move(logDependencies));
    const auto logSnapshot = logFacade.taskLogSnapshot("task.logs");
    const auto longLogSnapshot = logFacade.taskLogSnapshot("task.long-log");
    const auto unknownLogSnapshot = logFacade.taskLogSnapshot("unknown-log");
    const bool logPrivacyAndBounds = logSnapshot.has_value() && logSnapshot->hasStableIdentifier()
        && logSnapshot->entries.size() == kFrontendLogMaxEntries
        && logSnapshot->droppedEntryCount == 8
        && logSnapshot->truncated
        && logSnapshot->entries.front().sequence == 8
        && logSnapshot->entries.back().text.find("fixture-secret") == std::string::npos
        && logSnapshot->entries.back().text.find("fixture-token") == std::string::npos
        && logSnapshot->entries.back().text.find("fixture-user") == std::string::npos
        && logSnapshot->entries.back().text.find(fixtureRoot.string()) == std::string::npos
        && logSnapshot->entries.back().text.find("<redacted>") != std::string::npos
        && logSnapshot->entries.back().text.find("<data-root>") != std::string::npos
        && logSnapshot->totalByteCount <= kFrontendLogMaxBytes && logRootMatches;
    const bool longLogIsTruncated = longLogSnapshot.has_value() && longLogSnapshot->entries.size() == 1
        && longLogSnapshot->entries.front().truncated
        && longLogSnapshot->entries.front().text.size() == kFrontendLogMaxBytes
        && longLogSnapshot->truncated && longLogSnapshot->totalByteCount == kFrontendLogMaxBytes;
    const bool missingLogPortIsSafe = !emptyFacade.taskLogSnapshot("task.logs").has_value()
        && throwsInvalidArgument([&logFacade] {
               (void) logFacade.taskLogSnapshot("");
           })
        && !unknownLogSnapshot.has_value()
        && logFacade.shutdown()
        && throwsLogicError([&logFacade] {
               (void) logFacade.taskLogSnapshot("task.logs");
           });

    auto invalidTaskProgressDependencies = makeFixtureDependencies();
    invalidTaskProgressDependencies.loadTaskSnapshot = [](const std::filesystem::path&, const std::string&)
        -> std::optional<FrontendTaskSnapshot> {
        return FrontendTaskSnapshot{ "invalid.task", "Invalid Task", FrontendTaskState::Running,
                                     FrontendTaskProgressKind::Determinate, 1.5, true, {}, std::nullopt };
    };
    FrontendFacade invalidTaskProgressFacade(fixtureRoot, std::move(invalidTaskProgressDependencies));
    const bool rejectedInvalidTaskProgress = throwsInvalidArgument([&invalidTaskProgressFacade] {
        (void) invalidTaskProgressFacade.taskSnapshot("invalid.task");
    });

    auto invalidTaskSubtasksDependencies = makeFixtureDependencies();
    invalidTaskSubtasksDependencies.loadTaskSnapshot = [](const std::filesystem::path&, const std::string&)
        -> std::optional<FrontendTaskSnapshot> {
        return FrontendTaskSnapshot{ "invalid.task", "Invalid Task", FrontendTaskState::Running,
                                     FrontendTaskProgressKind::Determinate, 0.5, true,
                                     { { "duplicate", "First", FrontendTaskState::Running,
                                         FrontendTaskProgressKind::Determinate, 0.5 },
                                       { "duplicate", "Second", FrontendTaskState::Running,
                                         FrontendTaskProgressKind::Determinate, 0.75 } },
                                     std::nullopt };
    };
    FrontendFacade invalidTaskSubtasksFacade(fixtureRoot, std::move(invalidTaskSubtasksDependencies));
    const bool rejectedInvalidTaskSubtasks = throwsInvalidArgument([&invalidTaskSubtasksFacade] {
        (void) invalidTaskSubtasksFacade.taskSnapshot("invalid.task");
    });

    auto invalidTaskTerminalDependencies = makeFixtureDependencies();
    invalidTaskTerminalDependencies.loadTaskSnapshot = [](const std::filesystem::path&, const std::string&)
        -> std::optional<FrontendTaskSnapshot> {
        return FrontendTaskSnapshot{ "invalid.task", "Invalid Task", FrontendTaskState::Failed,
                                     FrontendTaskProgressKind::Determinate, 1.0, false, {},
                                     FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Succeeded,
                                                                 "task.completed", {}, "", false } };
    };
    FrontendFacade invalidTaskTerminalFacade(fixtureRoot, std::move(invalidTaskTerminalDependencies));
    const bool rejectedInvalidTaskTerminalResult = throwsInvalidArgument([&invalidTaskTerminalFacade] {
        (void) invalidTaskTerminalFacade.taskSnapshot("invalid.task");
    });

    auto invalidSnapshotDependencies = makeFixtureDependencies();
    invalidSnapshotDependencies.loadInstanceSnapshots = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceSnapshot>{ { "", "Invalid", "", "" } };
    };
    FrontendFacade invalidSnapshotFacade(fixtureRoot, std::move(invalidSnapshotDependencies));
    const bool rejectedInvalidSnapshot = throwsInvalidArgument([&invalidSnapshotFacade] {
        (void) invalidSnapshotFacade.instanceSnapshots();
    });

    auto invalidDetailsDependencies = makeFixtureDependencies();
    invalidDetailsDependencies.loadInstanceDetails = [](const std::filesystem::path&, const std::string&)
        -> std::optional<FrontendInstanceDetailsSnapshot> {
        return FrontendInstanceDetailsSnapshot{ "fixture-one", "", "", "", "Minecraft", "", true };
    };
    FrontendFacade invalidDetailsFacade(fixtureRoot, std::move(invalidDetailsDependencies));
    const bool rejectedInvalidDetails = throwsInvalidArgument([&invalidDetailsFacade] {
        (void) invalidDetailsFacade.instanceDetails("fixture-one");
    });

    auto invalidChangeDependencies = makeFixtureDependencies();
    invalidChangeDependencies.loadInstanceChanges = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceChange>{
            { static_cast<FrontendInstanceChangeKind>(99), { "fixture-one", "", "", "" } },
        };
    };
    FrontendFacade invalidChangeFacade(fixtureRoot, std::move(invalidChangeDependencies));
    const bool rejectedInvalidChange = throwsInvalidArgument([&invalidChangeFacade] {
        (void) invalidChangeFacade.instanceChanges();
    });

    const bool fixtureWasPreserved = std::filesystem::exists(fixtureMarker);
    const bool rejectedEmptyRoot = throwsInvalidArgument([] {
        FrontendFacade facade({}, makeFixtureDependencies());
        (void) facade;
    });
    const bool rejectedRelativeRoot = throwsInvalidArgument([] {
        FrontendFacade facade(std::filesystem::path("relative-fixture-root"), makeFixtureDependencies());
        (void) facade;
    });
    const bool rejectedIncompleteDependencies = throwsInvalidArgument([&fixtureRoot] {
        FrontendFacade facade(fixtureRoot, {});
        (void) facade;
    });

    std::size_t cancelPendingWorkCount = 0;
    std::size_t shutdownCount = 0;
    std::size_t snapshotLoaderCount = 0;
    std::size_t changeLoaderCount = 0;
    FrontendLifecycleState shutdownCallbackState = FrontendLifecycleState::Running;
    FrontendFacade* lifecycleFacadePointer = nullptr;
    bool lifecycleContract = false;
    {
        auto lifecycleDependencies = makeFixtureDependencies();
        lifecycleDependencies.cancelPendingWork = [&cancelPendingWorkCount] { ++cancelPendingWorkCount; };
        lifecycleDependencies.shutdown = [&shutdownCount, &shutdownCallbackState, &lifecycleFacadePointer] {
            ++shutdownCount;
            if (lifecycleFacadePointer) {
                shutdownCallbackState = lifecycleFacadePointer->lifecycleState();
            }
        };
        lifecycleDependencies.loadInstanceSnapshots = [&snapshotLoaderCount](const std::filesystem::path&) {
            ++snapshotLoaderCount;
            return std::vector<FrontendInstanceSnapshot>{ { "post-shutdown-snapshot", "", "", "" } };
        };
        lifecycleDependencies.loadInstanceChanges = [&changeLoaderCount](const std::filesystem::path&) {
            ++changeLoaderCount;
            return std::vector<FrontendInstanceChange>{
                { FrontendInstanceChangeKind::Added, { "post-shutdown-change", "", "", "" } },
            };
        };

        FrontendFacade lifecycleFacade(fixtureRoot, std::move(lifecycleDependencies));
        lifecycleFacadePointer = &lifecycleFacade;
        const bool initiallyRunning = lifecycleFacade.lifecycleState() == FrontendLifecycleState::Running;
        const bool firstShutdown = lifecycleFacade.shutdown();
        const bool repeatedShutdown = !lifecycleFacade.shutdown();
        const bool stoppedAfterShutdown = lifecycleFacade.lifecycleState() == FrontendLifecycleState::Stopped;
        const bool releasedDependencies = !lifecycleFacade.hasRuntimeDependencies();
        const bool rejectedSnapshotWork = throwsLogicError([&lifecycleFacade] {
            (void) lifecycleFacade.instanceSnapshots();
        });
        const bool rejectedChangeWork = throwsLogicError([&lifecycleFacade] {
            (void) lifecycleFacade.instanceChanges();
        });
        lifecycleFacadePointer = nullptr;
        lifecycleContract = initiallyRunning && firstShutdown && repeatedShutdown && stoppedAfterShutdown
            && releasedDependencies && rejectedSnapshotWork && rejectedChangeWork;
    }
    const bool callbacksRanExactlyOnce = cancelPendingWorkCount == 1 && shutdownCount == 1
        && shutdownCallbackState == FrontendLifecycleState::ShuttingDown && snapshotLoaderCount == 0 && changeLoaderCount == 0;

    std::size_t implicitShutdownCount = 0;
    {
        auto implicitDependencies = makeFixtureDependencies();
        implicitDependencies.shutdown = [&implicitShutdownCount] { ++implicitShutdownCount; };
        FrontendFacade implicitFacade(fixtureRoot, std::move(implicitDependencies));
        if (implicitFacade.lifecycleState() != FrontendLifecycleState::Running) {
            std::filesystem::remove(fixtureMarker, error);
            std::filesystem::remove(fixtureRoot, error);
            return 4;
        }
    }
    const bool destructorShutdownContract = implicitShutdownCount == 1;

    const bool rejectedPostShutdownDetailsWork = detailsFacade.shutdown()
        && throwsLogicError([&detailsFacade] {
               (void) detailsFacade.instanceDetails("fixture-one");
           })
        && throwsLogicError([&detailsFacade] {
               (void) detailsFacade.updateInstanceNotes("fixture-one", "after shutdown");
           });
    const bool rejectedPostShutdownSettingsWork = settingsFacade.shutdown()
        && throwsLogicError([&settingsFacade] {
               (void) settingsFacade.instanceSettings("fixture-one");
           })
        && throwsLogicError([&settingsFacade, &requestedSettings] {
               (void) settingsFacade.updateInstanceSettings("fixture-one", requestedSettings);
           });
    const bool rejectedPostShutdownGlobalSettingsWork = globalSettingsFacade.shutdown()
        && throwsLogicError([&globalSettingsFacade] {
               (void) globalSettingsFacade.globalSettings();
           })
        && throwsLogicError([&globalSettingsFacade, &requestedGlobalSettings] {
               (void) globalSettingsFacade.updateGlobalSettings(requestedGlobalSettings);
           });
    const bool rejectedPostShutdownJavaWork = javaFacade.shutdown()
        && throwsLogicError([&javaFacade] {
               (void) javaFacade.javaInstallations();
           })
        && throwsLogicError([&javaFacade] {
               (void) javaFacade.selectJavaInstallation("fixture-managed");
           });
    const bool rejectedPostShutdownAccountWork = accountFacade.shutdown()
        && throwsLogicError([&accountFacade] {
               (void) accountFacade.accountSnapshots();
           })
        && throwsLogicError([&accountFacade] {
               (void) accountFacade.selectActiveAccount(std::string("fixture-account"));
           });
    const bool rejectedPostShutdownAuthenticationWork = authenticationFacade.shutdown()
        && throwsLogicError([&authenticationFacade, &loginRequest] {
               (void) authenticationFacade.authenticateAccount(loginRequest);
           });
    const bool rejectedPostShutdownOfflineIdentityWork = offlineIdentityFacade.shutdown()
        && throwsLogicError([&offlineIdentityFacade, &offlineIdentityLoadRequest] {
               (void) offlineIdentityFacade.loadOfflineLaunchIdentity(offlineIdentityLoadRequest);
           })
        && throwsLogicError([&offlineIdentityFacade, &validOfflineIdentityUpdate] {
               (void) offlineIdentityFacade.updateOfflineLaunchIdentity(validOfflineIdentityUpdate);
           });
    const bool rejectedPostShutdownComponentsWork = componentFacade.shutdown()
        && throwsLogicError([&componentFacade] {
               (void) componentFacade.instanceComponents("fixture-one");
           });
    const bool rejectedPostShutdownResourceWork = resourceFacade.shutdown()
        && throwsLogicError([&resourceFacade, &deleteRequest] {
               (void) resourceFacade.mutateInstanceResource("fixture-one", FrontendInstanceResourceKind::Mods, deleteRequest);
           });

    std::filesystem::remove(fixtureMarker, error);
    std::filesystem::remove(fixtureRoot, error);

    return fixtureWasPreserved && emptyContract && fixtureSnapshotContract && fixtureChangeContract && detailsContract
               && rejectedInvalidDetailsIdentifiers && missingDetailsPortsAreSafe && settingsContract
               && invalidSettingsRejected && invalidSettingsUpdateRejected && missingSettingsPortsAreSafe
               && rejectedPostShutdownSettingsWork && rejectedPostShutdownDetailsWork
               && commandRootContract && missingCommandPortsAreRejected && rejectedPostShutdownCommands && taskStateContract
               && taskCancellationContract && taskForwardingContract && rejectedInvalidTaskIdentifiers
               && missingTaskPortsAreSafe && rejectedPostShutdownTaskWork && rejectedInvalidTaskProgress
               && rejectedInvalidTaskSubtasks && rejectedInvalidTaskTerminalResult && rejectedInvalidSnapshot
               && rejectedInvalidDetails
               && rejectedInvalidChange && componentContract && rejectedInvalidComponentIdentifier
               && missingComponentPortIsSafe && rejectedInvalidComponents && rejectedPostShutdownComponentsWork
               && resourceContract && rejectedInvalidResourceKind && rejectedUnconfirmedDelete
               && resourceMutationContract && rejectedRelativeResourceImport && missingResourceMutatorIsSafe
               && rejectedInvalidResources && rejectedInvalidMutationResult
               && rejectedPostShutdownResourceWork
               && logPrivacyAndBounds && longLogIsTruncated && missingLogPortIsSafe
               && globalSettingsContract && invalidGlobalSettingsRejected && invalidGlobalSettingsUpdateRejected
               && missingGlobalSettingsPortsAreSafe && rejectedPostShutdownGlobalSettingsWork && javaContract
               && invalidJavaDiscoveryRejected && invalidJavaSelectionRejected && missingJavaPortsAreSafe
               && rejectedPostShutdownJavaWork && accountContract && invalidAccountSnapshotsRejected
               && invalidAccountSelectionRejected && missingAccountPortsAreSafe && rejectedPostShutdownAccountWork
               && authenticationContract && invalidAuthenticationRejected && missingAuthenticationPortIsSafe
               && rejectedPostShutdownAuthenticationWork && offlineIdentityContract && invalidOfflineLoadRejected
               && invalidOfflineUpdateRejected && missingOfflineIdentityPortsAreSafe
               && rejectedPostShutdownOfflineIdentityWork && instanceImportContract
               && rejectedInvalidImportRequest && missingInstanceImportPortIsSafe
               && rejectedPostShutdownInstanceImport
               && rejectedEmptyRoot && rejectedRelativeRoot && rejectedIncompleteDependencies
               && lifecycleContract && callbacksRanExactlyOnce && destructorShutdownContract && !error
        ? 0
        : 4;
}
