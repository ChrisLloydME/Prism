// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "FrontendFacade.h"

#include <cstdint>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

/// QWidget-free production owner for news, update metadata, macOS shortcuts,
/// and Minecraft skin persistence/actions.
///
/// Network, update installation, destination discovery, shortcut writes, and
/// authenticated profile effects are explicit ports. Tests instantiate this
/// adapter with controlled ports and disposable roots; Swift never owns files,
/// Qt objects, C++ lifetimes, or account credentials.
class ProductionUtilityRuntime final {
   public:
    using Bytes = std::vector<std::uint8_t>;
    using CancellationCheck = FrontendRuntimeDependencies::UtilityCancellationCheck;
    using DownloadHandler = std::function<std::optional<Bytes>(const std::string&, const CancellationCheck&)>;
    using UpdateInstaller = std::function<bool(const std::string& trustedHTTPSURL)>;
    using DestinationResolver = std::function<std::optional<std::filesystem::path>(FrontendShortcutDestination)>;

    struct ShortcutDescriptor final {
        std::filesystem::path destinationPath;
        std::filesystem::path launcherExecutablePath;
        std::filesystem::path launcherIconPath;
        std::string name;
        std::vector<std::string> arguments;
    };
    using ShortcutWriter = std::function<std::optional<std::filesystem::path>(const ShortcutDescriptor&)>;

    using AccountProfileLoader =
        std::function<std::optional<FrontendSkinAccountProfile>(const std::string& accountIdentifier)>;
    using AccountCredentialProvider =
        std::function<std::optional<std::string>(const std::string& accountIdentifier)>;
    using AccountProfileWriter = std::function<bool(const FrontendSkinAccountProfile&)>;

    enum class SkinServiceOperation : std::uint8_t { Upload, Reset };

    /// Private C++ service request. `authorizationCredential` is consumed only
    /// by the injected/default backend effect and never enters facade results.
    struct SkinServiceRequest final {
        SkinServiceOperation operation = SkinServiceOperation::Upload;
        std::string accountIdentifier;
        std::string authorizationCredential;
        FrontendSkinModel model = FrontendSkinModel::Classic;
        std::string capeIdentifier;
        Bytes textureData;
        CancellationCheck cancellation;
    };

    struct SkinServiceResult final {
        bool succeeded = false;
        bool cancelled = false;
        bool retryable = false;
        FrontendSkinAccountProfile profile;
        std::string diagnosticText;
    };
    using SkinService = std::function<SkinServiceResult(const SkinServiceRequest&)>;

    struct Dependencies final {
        DownloadHandler download;
        UpdateInstaller updateInstaller;
        DestinationResolver destinationResolver;
        ShortcutWriter shortcutWriter;
        AccountProfileLoader accountProfileLoader;
        AccountCredentialProvider accountCredentialProvider;
        AccountProfileWriter accountProfileWriter;
        SkinService skinService;
        std::filesystem::path launcherExecutablePath;
        std::filesystem::path launcherIconPath;
    };

    static Dependencies defaultDependencies(
        std::filesystem::path launcherExecutablePath = {}, std::filesystem::path launcherIconPath = {});

    explicit ProductionUtilityRuntime(std::filesystem::path dataRoot, Dependencies dependencies = {});
    ~ProductionUtilityRuntime() noexcept;

    ProductionUtilityRuntime(const ProductionUtilityRuntime&) = delete;
    ProductionUtilityRuntime& operator=(const ProductionUtilityRuntime&) = delete;

    FrontendNewsResult news(const CancellationCheck& cancellation);
    FrontendUpdateCheckResult checkForUpdates(const std::string& currentVersion, const CancellationCheck& cancellation);
    FrontendUpdateDecisionResult applyUpdateDecision(
        const FrontendUpdateDecisionRequest& request, const CancellationCheck& cancellation);
    FrontendShortcutCreationResult createShortcut(
        const FrontendShortcutCreationRequest& request, const CancellationCheck& cancellation);
    FrontendSkinLoadResult skins(const std::string& accountIdentifier, const CancellationCheck& cancellation);
    FrontendSkinActionResult performSkinAction(
        const FrontendSkinActionRequest& request, const CancellationCheck& cancellation);

    void shutdown() noexcept;

   private:
    std::filesystem::path m_dataRoot;
    std::filesystem::path m_skinRoot;
    std::filesystem::path m_updateStatePath;
    Dependencies m_dependencies;
    std::mutex m_mutex;
    bool m_shutdown = false;
    std::string m_availableVersion;
    std::string m_availableDownloadURL;
};

std::shared_ptr<ProductionUtilityRuntime> makeProductionUtilityRuntime(
    std::filesystem::path dataRoot, ProductionUtilityRuntime::Dependencies dependencies = {});

FrontendRuntimeDependencies productionUtilityRuntimeDependencies(
    std::shared_ptr<ProductionUtilityRuntime> runtime,
    FrontendRuntimeDependencies dependencies = {});
