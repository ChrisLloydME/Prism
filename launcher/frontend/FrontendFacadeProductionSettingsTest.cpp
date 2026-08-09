// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"
#include "ProductionInstanceRuntime.h"
#include "SysInfo.h"
#include "settings/INIFile.h"

#include <chrono>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

std::filesystem::path temporaryRoot()
{
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    return std::filesystem::temp_directory_path() / ("prism-native-settings-" + std::to_string(stamp));
}

void require(bool condition, const char* message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

void writeGlobalAliases(const std::filesystem::path& root)
{
    INIFile settings;
    settings.set("MCWindowWidth", 1366);
    settings.set("MCWindowHeight", 768);
    settings.set("MinMemoryAlloc", 640);
    settings.set("MaxMemoryAlloc", 3072);
    settings.set("CatFit", "unknown-legacy-value");
    settings.set("ShowConsole", true);
    settings.set("ConsoleMaxLines", 20000);
    settings.set("FutureGlobalSetting", "preserve-me");
    require(settings.saveFile(QString::fromStdString((root / "prismlauncher.cfg").string())),
            "global alias settings could not be written");
}

}  // namespace

int main()
{
    const auto root = temporaryRoot();
    std::error_code cleanupError;
    try {
        std::filesystem::create_directories(root);

        FrontendFacade facade(root, productionInstanceRuntimeDependencies(root));
        const auto defaults = facade.globalSettings();
        require(defaults.has_value(), "production global defaults were not available");
        require(defaults->instanceDirectory == root / "instances", "global defaults used the wrong instance root");
        require(defaults->backgroundCat == "kitteh" && defaults->catFit == "fit", "global defaults changed");
        require(defaults->numberOfConcurrentTasks == 10 && defaults->consoleMaxLines == 100000,
                "global numeric defaults changed");

        const auto defaultCreated = facade.createMetadataInstance({ "settings.default", "Settings Default", "default" });
        require(defaultCreated.outcome == FrontendMetadataInstanceOutcome::Succeeded,
                "default settings test instance could not be created");
        const auto defaultInstanceSettings = facade.instanceSettings("settings.default");
        require(defaultInstanceSettings.has_value()
                    && defaultInstanceSettings->maxMemoryMiB == SysInfo::defaultMaxJvmMem(),
                "instance settings did not use the existing system-info domain default");

        writeGlobalAliases(root);
        const auto aliasedGlobal = facade.globalSettings();
        require(aliasedGlobal.has_value() && aliasedGlobal->catFit == "strech"
                    && aliasedGlobal->showConsole && aliasedGlobal->consoleMaxLines == 20000,
                "global aliases or legacy cat-fit normalization were not preserved");

        auto requestedGlobal = *aliasedGlobal;
        requestedGlobal.catOpacity = 81;
        requestedGlobal.catFit = "fill";
        const auto globalUpdate = facade.updateGlobalSettings(requestedGlobal);
        require(globalUpdate.outcome == FrontendGlobalSettingsUpdateOutcome::Succeeded
                    && globalUpdate.settings.has_value() && globalUpdate.settings->catOpacity == 81
                    && globalUpdate.settings->catFit == "fill",
                "global settings update was not confirmed");

        INIFile persistedGlobal;
        require(persistedGlobal.loadFile(QString::fromStdString((root / "prismlauncher.cfg").string())),
                "persisted global settings could not be read");
        require(persistedGlobal.value("FutureGlobalSetting").toString() == "preserve-me",
                "unknown global settings were not preserved");
        const auto reloadedGlobal = facade.globalSettings();
        require(reloadedGlobal.has_value() && reloadedGlobal->catOpacity == 81 && reloadedGlobal->catFit == "fill",
                "global settings did not reload after a confirmed update");

        const auto created = facade.createMetadataInstance({ "settings.one", "Settings One", "default" });
        require(created.outcome == FrontendMetadataInstanceOutcome::Succeeded,
                "settings test instance could not be created");

        INIFile instanceSeed;
        require(instanceSeed.loadFile(QString::fromStdString(
                    (root / "instances" / "settings.one" / "instance.cfg").string())),
                "instance settings seed could not be read");
        instanceSeed.set("FutureInstanceSetting", "preserve-me");
        require(instanceSeed.saveFile(QString::fromStdString(
                    (root / "instances" / "settings.one" / "instance.cfg").string())),
                "instance settings seed could not be written");

        const auto inherited = facade.instanceSettings("settings.one");
        require(inherited.has_value() && inherited->windowWidth == 1366 && inherited->windowHeight == 768
                    && inherited->minMemoryMiB == 640 && inherited->maxMemoryMiB == 3072 && inherited->showConsole,
                "instance settings did not inherit global aliases");


        auto requested = *inherited;
        requested.windowOverrideEnabled = true;
        requested.windowWidth = 1440;
        requested.windowHeight = 900;
        requested.memoryOverrideEnabled = true;
        requested.minMemoryMiB = 768;
        requested.maxMemoryMiB = 4096;
        requested.consoleOverrideEnabled = true;
        requested.showConsole = false;
        requested.joinServerOnLaunch = true;
        requested.joinTarget = FrontendInstanceJoinTarget::Server;
        requested.joinServerAddress = "synthetic.example:25565";
        requested.joinWorld.clear();
        requested.overrideModDownloadLoaders = true;
        requested.modDownloadLoaders = { "Fabric", "Quilt" };
        const auto updated = facade.updateInstanceSettings("settings.one", requested);
        require(updated.outcome == FrontendInstanceSettingsUpdateOutcome::Succeeded && updated.settings.has_value()
                    && updated.settings->windowWidth == 1440 && updated.settings->showConsole == false
                    && updated.settings->joinTarget == FrontendInstanceJoinTarget::Server,
                "instance settings update was not confirmed");

        INIFile persistedInstance;
        require(persistedInstance.loadFile(QString::fromStdString(
                    (root / "instances" / "settings.one" / "instance.cfg").string())),
                "persisted instance settings could not be read");
        require(persistedInstance.contains("MinecraftWinWidth") && !persistedInstance.contains("MCWindowWidth")
                    && persistedInstance.contains("OverrideMemory") && persistedInstance.contains("ModDownloadLoaders")
                    && persistedInstance.value("FutureInstanceSetting").toString() == "preserve-me",
                "canonical instance keys, JSON loader settings, or unknown values were not persisted");

        auto inheritedAgain = requested;
        inheritedAgain.windowOverrideEnabled = false;
        inheritedAgain.memoryOverrideEnabled = false;
        inheritedAgain.consoleOverrideEnabled = false;
        const auto reverted = facade.updateInstanceSettings("settings.one", inheritedAgain);
        require(reverted.outcome == FrontendInstanceSettingsUpdateOutcome::Succeeded && reverted.settings.has_value(),
                "instance override removal was not confirmed");
        require(reverted.settings->windowWidth == 1366 && reverted.settings->minMemoryMiB == 640
                    && reverted.settings->showConsole,
                "instance settings did not reconstruct global values after override removal");

        bool invalidRejected = false;
        try {
            auto invalidSettings = *reverted.settings;
            invalidSettings.windowWidth = 0;
            static_cast<void>(facade.updateInstanceSettings("settings.one", invalidSettings));
        } catch (const std::invalid_argument&) {
            invalidRejected = true;
        }
        require(invalidRejected,
                "invalid settings were not rejected before persistence");

        auto concurrentA = *reverted.settings;
        auto concurrentB = *reverted.settings;
        concurrentA.windowOverrideEnabled = true;
        concurrentB.windowOverrideEnabled = true;
        concurrentA.windowWidth = 1200;
        concurrentB.windowWidth = 1300;
        FrontendInstanceSettingsUpdateResult resultA;
        FrontendInstanceSettingsUpdateResult resultB;
        std::thread first([&] { resultA = facade.updateInstanceSettings("settings.one", concurrentA); });
        std::thread second([&] { resultB = facade.updateInstanceSettings("settings.one", concurrentB); });
        first.join();
        second.join();
        require(resultA.outcome == FrontendInstanceSettingsUpdateOutcome::Succeeded
                    && resultB.outcome == FrontendInstanceSettingsUpdateOutcome::Succeeded,
                "concurrent settings updates were not serialized and confirmed");
        const auto concurrentReload = facade.instanceSettings("settings.one");
        require(concurrentReload.has_value() && (concurrentReload->windowWidth == 1200 || concurrentReload->windowWidth == 1300),
                "concurrent settings update left an invalid persisted file");

        facade.shutdown();
        FrontendFacade reconstructed(root, productionInstanceRuntimeDependencies(root));
        const auto reconstructedGlobal = reconstructed.globalSettings();
        const auto reconstructedInstance = reconstructed.instanceSettings("settings.one");
        require(reconstructedGlobal.has_value() && reconstructedGlobal->catFit == "fill"
                    && reconstructedGlobal->catOpacity == 81,
                "global settings did not survive runtime reconstruction");
        require(reconstructedInstance.has_value() && (reconstructedInstance->windowWidth == 1200
                                                       || reconstructedInstance->windowWidth == 1300),
                "instance settings did not survive runtime reconstruction");
        reconstructed.shutdown();
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        std::filesystem::remove_all(root, cleanupError);
        return 1;
    }

    std::filesystem::remove_all(root, cleanupError);
    return cleanupError ? 1 : 0;
}
