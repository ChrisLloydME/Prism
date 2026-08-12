// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"
#include "ProductionInstanceRuntime.h"
#include "ProductionUtilityRuntime.h"

#include <QByteArray>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using Bytes = ProductionUtilityRuntime::Bytes;

void require(bool condition, const char* message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

std::filesystem::path temporaryRoot()
{
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    return std::filesystem::temp_directory_path() / ("prism-native-utility-" + std::to_string(stamp));
}

Bytes bytes(const std::string& value)
{
    return { value.begin(), value.end() };
}

Bytes skinPNG()
{
    const auto value = QByteArray::fromBase64(
        "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAYklEQVR42u3QMREAAAgAoe9fWnN4MlCAqnlOgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAgQIuG4BWHzw4uJRQGoAAAAASUVORK5CYII=");
    return { reinterpret_cast<const std::uint8_t*>(value.constData()),
             reinterpret_cast<const std::uint8_t*>(value.constData()) + value.size() };
}

void writeBytes(const std::filesystem::path& path, const Bytes& value)
{
    std::filesystem::create_directories(path.parent_path());
    std::ofstream file(path, std::ios::binary);
    file.write(reinterpret_cast<const char*>(value.data()), static_cast<std::streamsize>(value.size()));
    require(file.good(), "synthetic binary fixture could not be written");
}

void writeText(const std::filesystem::path& path, const std::string& value)
{
    std::filesystem::create_directories(path.parent_path());
    std::ofstream file(path);
    file << value;
    require(file.good(), "synthetic text fixture could not be written");
}

FrontendRuntimeDependencies facadeDependencies(const std::shared_ptr<ProductionUtilityRuntime>& runtime)
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::now(); };
    dependencies.cancelPendingWork = [] {};
    dependencies.shutdown = [runtime] { runtime->shutdown(); };
    return productionUtilityRuntimeDependencies(runtime, std::move(dependencies));
}

}  // namespace

int main()
{
    const auto root = temporaryRoot();
    std::error_code cleanupError;
    try {
        std::filesystem::create_directories(root / "instances" / "utility.instance");
        writeText(root / "instances" / "utility.instance" / "instance.cfg",
                  "name=Utility Instance\nuuid=synthetic-launch-uuid\n");
        writeText(root / "Prism", "#!/bin/sh\nexit 0\n");
        writeText(root / "Prism.icns", "synthetic-icon");
        const auto png = skinPNG();
        const auto pickedSkin = root / "picked.png";
        writeBytes(pickedSkin, png);

        FrontendSkinAccountProfile accountProfile;
        accountProfile.accountIdentifier = "account.synthetic";
        accountProfile.profileName = "SyntheticPlayer";
        accountProfile.capes.push_back({ "cape.synthetic", "Synthetic Cape", png,
                                         "https://textures.example.invalid/cape.png" });

        std::vector<std::string> downloadURLs;
        std::vector<std::string> installerURLs;
        std::vector<ProductionUtilityRuntime::ShortcutDescriptor> shortcutDescriptors;
        std::size_t profileWrites = 0;
        std::size_t serviceCalls = 0;

        auto makeDependencies = [&] {
            auto dependencies = ProductionUtilityRuntime::defaultDependencies(root / "Prism", root / "Prism.icns");
            dependencies.download = [&](const std::string& url, const auto& cancellation) -> std::optional<Bytes> {
                downloadURLs.push_back(url);
                if (cancellation && cancellation()) {
                    return std::nullopt;
                }
                if (url.find("feed/feed.xml") != std::string::npos) {
                    return bytes(
                        R"XML(<feed><entry><id>news.synthetic.1</id><title>Native news</title><link href="https://example.invalid/news/1"/><content>Migration status</content><updated>2026-08-12</updated></entry><entry><id>news.synthetic.2</id><title>Second item</title><link href="https://example.invalid/news/2"/><summary>More status</summary></entry></feed>)XML");
                }
                if (url.find("appcast.xml") != std::string::npos) {
                    return bytes(
                        R"XML(<rss xmlns:sparkle="https://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><title>Prism 12.1</title><description>Native update notes</description><enclosure url="https://downloads.example.invalid/Prism-12.1.zip" sparkle:shortVersionString="12.1"/></item></channel></rss>)XML");
                }
                if (url.find("profile/lookup/name/SyntheticUser") != std::string::npos) {
                    return bytes(R"JSON({"id":"user-profile-id"})JSON");
                }
                if (url.find("session/minecraft/profile/user-profile-id") != std::string::npos) {
                    const QByteArray texture = QByteArray(
                        R"JSON({"textures":{"SKIN":{"url":"https://textures.example.invalid/user.png","metadata":{"model":"slim"}}}})JSON")
                                                   .toBase64();
                    return bytes("{\"properties\":[{\"name\":\"textures\",\"value\":\""
                                 + texture.toStdString() + "\"}]}");
                }
                if (url == "https://assets.example.invalid/imported.png"
                    || url == "https://textures.example.invalid/user.png"
                    || url == "https://textures.example.invalid/cape.png") {
                    return png;
                }
                return std::nullopt;
            };
            dependencies.updateInstaller = [&](const std::string& url) {
                installerURLs.push_back(url);
                return false;
            };
            dependencies.destinationResolver = [&](FrontendShortcutDestination destination)
                -> std::optional<std::filesystem::path> {
                if (destination == FrontendShortcutDestination::Desktop) {
                    return root / "Desktop";
                }
                if (destination == FrontendShortcutDestination::Applications) {
                    return root / "Applications";
                }
                return std::nullopt;
            };
            dependencies.shortcutWriter = [&](const ProductionUtilityRuntime::ShortcutDescriptor& descriptor)
                -> std::optional<std::filesystem::path> {
                shortcutDescriptors.push_back(descriptor);
                auto written = descriptor.destinationPath;
                written += ".app";
                return written;
            };
            dependencies.accountProfileLoader = [&](const std::string& identifier)
                -> std::optional<FrontendSkinAccountProfile> {
                return identifier == accountProfile.accountIdentifier
                    ? std::optional<FrontendSkinAccountProfile>(accountProfile)
                    : std::nullopt;
            };
            dependencies.accountCredentialProvider = [&](const std::string& identifier)
                -> std::optional<std::string> {
                return identifier == accountProfile.accountIdentifier
                    ? std::optional<std::string>("synthetic-short-lived-credential")
                    : std::nullopt;
            };
            dependencies.accountProfileWriter = [&](const FrontendSkinAccountProfile& profile) {
                ++profileWrites;
                accountProfile = profile;
                return true;
            };
            dependencies.skinService = [&](const ProductionUtilityRuntime::SkinServiceRequest& request) {
                ++serviceCalls;
                require(request.authorizationCredential == "synthetic-short-lived-credential",
                        "skin credential did not remain inside the C++ service port");
                ProductionUtilityRuntime::SkinServiceResult result;
                result.succeeded = true;
                result.profile = accountProfile;
                if (request.operation == ProductionUtilityRuntime::SkinServiceOperation::Upload) {
                    result.profile.currentSkinIdentifier = "service.skin.synthetic";
                    result.profile.currentSkinURL = "https://textures.example.invalid/current.png";
                    result.profile.currentSkinData = request.textureData;
                    result.profile.currentModel = request.model;
                    result.profile.currentCapeIdentifier = request.capeIdentifier;
                } else {
                    result.profile.currentSkinIdentifier.clear();
                    result.profile.currentSkinURL.clear();
                    result.profile.currentSkinData.clear();
                    result.profile.currentCapeIdentifier.clear();
                }
                return result;
            };
            return dependencies;
        };

        auto runtime = makeProductionUtilityRuntime(root, makeDependencies());
        FrontendFacade facade(root, facadeDependencies(runtime));

        const auto news = facade.news();
        require(news.outcome == FrontendNewsOutcome::Succeeded && news.entries.size() == 2
                    && news.entries.front().link == "https://example.invalid/news/1"
                    && news.entries.back().publishedDate.empty(),
                "production news adapter did not parse the synthetic Atom feed");
        const auto cancelledNews = facade.news([] { return true; });
        require(cancelledNews.outcome == FrontendNewsOutcome::Cancelled && cancelledNews.entries.empty(),
                "production news cancellation was not terminal and empty");

        const auto update = facade.checkForUpdates("12.0");
        require(update.outcome == FrontendUpdateCheckOutcome::Available && update.notice.has_value()
                    && update.notice->availableVersion == "12.1"
                    && update.notice->releaseNotes == "Native update notes",
                "production update adapter did not parse the synthetic appcast");
        const auto install = facade.applyUpdateDecision({ FrontendUpdateDecision::Install, "12.1" });
        require(install.outcome == FrontendUpdateDecisionOutcome::AuthorizationRequired
                    && installerURLs == std::vector<std::string>{ "https://downloads.example.invalid/Prism-12.1.zip" },
                "update installation did not preserve the separate authorization boundary");
        const auto skipped = facade.applyUpdateDecision({ FrontendUpdateDecision::SkipVersion, "12.1" });
        require(skipped.outcome == FrontendUpdateDecisionOutcome::Succeeded
                    && std::filesystem::is_regular_file(root / "native-updates.json"),
                "skipped update metadata was not persisted in the isolated root");

        FrontendShortcutCreationRequest shortcut;
        shortcut.instanceIdentifier = "utility.instance";
        shortcut.name = "Utility Instance";
        shortcut.launchTarget = FrontendShortcutLaunchTarget::World;
        shortcut.worldIdentifier = "Synthetic World";
        shortcut.profileName = "Synthetic Profile";
        shortcut.destination = FrontendShortcutDestination::Applications;
        shortcut.iconKey = "default";
        const auto shortcutResult = facade.createShortcut(shortcut);
        require(shortcutResult.outcome == FrontendShortcutCreationOutcome::Succeeded
                    && shortcutDescriptors.size() == 1,
                "production shortcut adapter did not invoke the injected writer");
        require(shortcutDescriptors.front().destinationPath
                        == root / "Applications" / "Prism Instances" / "Utility Instance"
                    && shortcutDescriptors.front().launcherIconPath == root / "Prism.icns"
                    && shortcutDescriptors.front().arguments
                        == std::vector<std::string>{ "--launch", "synthetic-launch-uuid", "--world",
                                                     "Synthetic World", "--profile", "Synthetic Profile" },
                "shortcut destination or launch arguments diverged from Prism semantics");
        FrontendShortcutCreationRequest unavailableIcon = shortcut;
        unavailableIcon.iconKey = "missing-icon";
        require(facade.createShortcut(unavailableIcon).outcome == FrontendShortcutCreationOutcome::Rejected
                    && shortcutDescriptors.size() == 1,
                "shortcut creation silently ignored an unavailable icon selection");
        writeText(root / "icons" / "custom.icns", "synthetic-custom-icon");
        FrontendShortcutCreationRequest customIcon = shortcut;
        customIcon.iconKey = "custom";
        require(facade.createShortcut(customIcon).outcome == FrontendShortcutCreationOutcome::Succeeded
                    && shortcutDescriptors.size() == 2
                    && shortcutDescriptors.back().launcherIconPath == root / "icons" / "custom.icns",
                "shortcut creation did not resolve an isolated custom ICNS asset");
        const auto cancelledShortcut = facade.createShortcut(shortcut, [] { return true; });
        require(cancelledShortcut.outcome == FrontendShortcutCreationOutcome::Cancelled
                    && shortcutDescriptors.size() == 2,
                "cancelled shortcut creation reached the external writer");

        const auto initialSkins = facade.skins("account.synthetic");
        require(initialSkins.outcome == FrontendSkinLoadOutcome::Succeeded && initialSkins.skins.empty()
                    && initialSkins.capes.size() == 1,
                "production skin adapter did not reconstruct account cape metadata");

        FrontendSkinActionRequest importFile;
        importFile.operation = FrontendSkinOperation::ImportFile;
        importFile.accountIdentifier = "account.synthetic";
        importFile.sourcePath = pickedSkin;
        const auto importedFile = facade.performSkinAction(importFile);
        if (importedFile.outcome != FrontendSkinActionOutcome::Succeeded) {
            std::cerr << importedFile.localizationKey << ": " << importedFile.diagnosticText << '\n';
        }
        require(importedFile.outcome == FrontendSkinActionOutcome::Succeeded
                    && importedFile.selectedSkinIdentifier == std::optional<std::string>("picked"),
                "local skin import did not persist and confirm its selection");

        const auto linkedSkin = root / "linked.png";
        std::error_code symlinkError;
        std::filesystem::create_symlink(pickedSkin, linkedSkin, symlinkError);
        require(!symlinkError, "synthetic skin symlink could not be created");
        FrontendSkinActionRequest importSymlink = importFile;
        importSymlink.sourcePath = linkedSkin;
        const auto rejectedSymlink = facade.performSkinAction(importSymlink);
        require(rejectedSymlink.outcome == FrontendSkinActionOutcome::Rejected,
                "local skin import accepted a symbolic-link source");

        FrontendSkinActionRequest rename;
        rename.operation = FrontendSkinOperation::Rename;
        rename.accountIdentifier = "account.synthetic";
        rename.skinIdentifier = "picked";
        rename.newName = "renamed";
        const auto renamed = facade.performSkinAction(rename);
        require(renamed.outcome == FrontendSkinActionOutcome::Succeeded
                    && renamed.selectedSkinIdentifier == std::optional<std::string>("renamed")
                    && std::filesystem::is_regular_file(root / "skins" / "renamed.png"),
                "skin rename did not atomically update file and index metadata");

        FrontendSkinActionRequest importURL;
        importURL.operation = FrontendSkinOperation::ImportURL;
        importURL.accountIdentifier = "account.synthetic";
        importURL.sourceURL = "https://assets.example.invalid/imported.png";
        const auto importedURL = facade.performSkinAction(importURL);
        require(importedURL.outcome == FrontendSkinActionOutcome::Succeeded
                    && importedURL.selectedSkinIdentifier == std::optional<std::string>("imported"),
                "URL skin import did not use the injected transport");

        FrontendSkinActionRequest importUser;
        importUser.operation = FrontendSkinOperation::ImportUser;
        importUser.accountIdentifier = "account.synthetic";
        importUser.username = "SyntheticUser";
        const auto importedUser = facade.performSkinAction(importUser);
        const auto userSkin = std::find_if(importedUser.skins.begin(), importedUser.skins.end(), [](const auto& skin) {
            return skin.id == "SyntheticUser";
        });
        require(importedUser.outcome == FrontendSkinActionOutcome::Succeeded
                    && userSkin != importedUser.skins.end() && userSkin->model == FrontendSkinModel::Slim,
                "username skin import did not preserve the Mojang texture model");

        FrontendSkinActionRequest upload;
        upload.operation = FrontendSkinOperation::Upload;
        upload.accountIdentifier = "account.synthetic";
        upload.skinIdentifier = "renamed";
        upload.model = FrontendSkinModel::Slim;
        upload.capeIdentifier = "cape.synthetic";
        const auto uploaded = facade.performSkinAction(upload);
        require(uploaded.outcome == FrontendSkinActionOutcome::Succeeded
                    && uploaded.currentSkinIdentifier == std::optional<std::string>("renamed")
                    && profileWrites == 1 && serviceCalls == 1,
                "authenticated skin upload was not persisted and confirmed");

        FrontendSkinActionRequest rejectCurrentDelete;
        rejectCurrentDelete.operation = FrontendSkinOperation::Delete;
        rejectCurrentDelete.accountIdentifier = "account.synthetic";
        rejectCurrentDelete.skinIdentifier = "renamed";
        rejectCurrentDelete.confirmed = true;
        const auto currentDelete = facade.performSkinAction(rejectCurrentDelete);
        require(currentDelete.outcome == FrontendSkinActionOutcome::Rejected,
                "the currently active skin was deletable");

        FrontendSkinActionRequest removeImported = rejectCurrentDelete;
        removeImported.skinIdentifier = "imported";
        const auto removed = facade.performSkinAction(removeImported);
        require(removed.outcome == FrontendSkinActionOutcome::Succeeded
                    && !std::filesystem::exists(root / "skins" / "imported.png")
                    && !std::filesystem::exists(root / "skins" / "imported.delete-stage"),
                "skin deletion did not commit both index and staged-file removal");

        FrontendSkinActionRequest reset;
        reset.operation = FrontendSkinOperation::Reset;
        reset.accountIdentifier = "account.synthetic";
        const auto resetResult = facade.performSkinAction(reset);
        require(resetResult.outcome == FrontendSkinActionOutcome::Succeeded
                    && !resetResult.currentSkinIdentifier.has_value() && profileWrites == 2 && serviceCalls == 2,
                "authenticated skin reset was not persisted and confirmed");
        facade.shutdown();

        auto reconstructedRuntime = makeProductionUtilityRuntime(root, makeDependencies());
        FrontendFacade reconstructed(root, facadeDependencies(reconstructedRuntime));
        const auto rebuiltUpdate = reconstructed.checkForUpdates("12.0");
        require(rebuiltUpdate.outcome == FrontendUpdateCheckOutcome::NoUpdate,
                "skipped update metadata did not survive runtime reconstruction");
        const auto rebuiltSkins = reconstructed.skins("account.synthetic");
        require(rebuiltSkins.outcome == FrontendSkinLoadOutcome::Succeeded && rebuiltSkins.skins.size() == 2
                    && std::any_of(rebuiltSkins.skins.begin(), rebuiltSkins.skins.end(), [](const auto& skin) {
                           return skin.id == "renamed";
                       }),
                "skin index did not survive runtime reconstruction");
        reconstructed.shutdown();

        auto bundleDependencies = ProductionUtilityRuntime::defaultDependencies(root / "Prism", root / "Prism.icns");
        bundleDependencies.destinationResolver = [&](FrontendShortcutDestination) {
            return std::optional<std::filesystem::path>(root / "Default Desktop");
        };
        auto bundleRuntime = makeProductionUtilityRuntime(root, std::move(bundleDependencies));
        FrontendShortcutCreationRequest missingShortcut = shortcut;
        missingShortcut.instanceIdentifier = "missing.instance";
        const auto missingShortcutResult = bundleRuntime->createShortcut(missingShortcut, {});
        require(missingShortcutResult.outcome == FrontendShortcutCreationOutcome::UnknownInstance,
                "shortcut creation did not preserve the unknown-instance recovery outcome");
        const auto bundleResult = bundleRuntime->createShortcut(shortcut, {});
        const auto bundlePath = root / "Default Desktop" / "Prism Instances" / "Utility Instance.app";
        require(bundleResult.outcome == FrontendShortcutCreationOutcome::Succeeded
                    && std::filesystem::is_regular_file(bundlePath / "Contents" / "Info.plist")
                    && std::filesystem::is_regular_file(bundlePath / "Contents" / "MacOS" / "Run.command"),
                "default macOS shortcut writer did not atomically create an application bundle");
        bundleRuntime->shutdown();
        require(bundleRuntime->news({}).outcome == FrontendNewsOutcome::Cancelled,
                "utility work remained available after runtime shutdown");

        auto failureDependencies = ProductionUtilityRuntime::defaultDependencies(root / "Prism", root / "Prism.icns");
        failureDependencies.download = [](const std::string&, const auto&) {
            return std::optional<Bytes>();
        };
        failureDependencies.destinationResolver = [&](FrontendShortcutDestination) {
            return std::optional<std::filesystem::path>(root / "Failed Desktop");
        };
        failureDependencies.shortcutWriter = [](const auto&) {
            return std::optional<std::filesystem::path>();
        };
        auto failureRuntime = makeProductionUtilityRuntime(root, std::move(failureDependencies));
        require(failureRuntime->news({}).outcome == FrontendNewsOutcome::Failed,
                "news transport failure did not produce a recoverable terminal result");
        const auto failedUpdate = failureRuntime->checkForUpdates("12.0", {});
        require(failedUpdate.outcome == FrontendUpdateCheckOutcome::Failed && failedUpdate.retryable,
                "update transport failure did not preserve retry metadata");
        require(failureRuntime->createShortcut(shortcut, {}).outcome == FrontendShortcutCreationOutcome::Failed,
                "shortcut writer failure did not produce a recoverable terminal result");
        const auto missingAccount = failureRuntime->skins("missing.account", {});
        require(missingAccount.outcome == FrontendSkinLoadOutcome::Failed && missingAccount.retryable,
                "missing skin-account metadata did not produce a recoverable terminal result");
        failureRuntime->shutdown();

        auto validationRuntime = makeProductionUtilityRuntime(
            root, ProductionUtilityRuntime::defaultDependencies(root / "Prism", root / "Prism.icns"));
        auto validationDependencies = facadeDependencies(validationRuntime);
        validationDependencies.loadNews = [](const std::filesystem::path&, const auto&) {
            return FrontendNewsResult{
                static_cast<FrontendNewsOutcome>(255), {}, "news.invalid", "Synthetic invalid outcome", false };
        };
        FrontendFacade validationFacade(root, std::move(validationDependencies));
        bool rejectedInvalidAdapter = false;
        try {
            (void)validationFacade.news();
        } catch (const std::invalid_argument&) {
            rejectedInvalidAdapter = true;
        }
        require(rejectedInvalidAdapter, "facade accepted an unknown utility adapter outcome");
        FrontendShortcutCreationRequest invalidShortcut = shortcut;
        invalidShortcut.launchTarget = static_cast<FrontendShortcutLaunchTarget>(255);
        bool rejectedInvalidRequest = false;
        try {
            (void)validationFacade.createShortcut(invalidShortcut);
        } catch (const std::invalid_argument&) {
            rejectedInvalidRequest = true;
        }
        require(rejectedInvalidRequest, "facade accepted an unknown shortcut request enum");
        validationFacade.shutdown();

        auto productionComposition = productionInstanceRuntimeDependencies(root, root / "Prism", root / "Prism.icns");
        require(productionComposition.loadNews && productionComposition.checkForUpdates
                    && productionComposition.applyUpdateDecision && productionComposition.createShortcut
                    && productionComposition.loadSkins && productionComposition.performSkinAction,
                "default production composition did not own every utility facade port");
        productionComposition.cancelPendingWork();
        productionComposition.shutdown();
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        std::filesystem::remove_all(root, cleanupError);
        return 1;
    }

    std::filesystem::remove_all(root, cleanupError);
    return cleanupError ? 1 : 0;
}
