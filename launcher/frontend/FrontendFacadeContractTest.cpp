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
               && rejectedPostShutdownJavaWork
               && rejectedEmptyRoot && rejectedRelativeRoot && rejectedIncompleteDependencies
               && lifecycleContract && callbacksRanExactlyOnce && destructorShutdownContract && !error
        ? 0
        : 4;
}
