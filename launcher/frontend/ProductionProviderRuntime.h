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

/// QWidget-free production owner for provider discovery and pack installation.
///
/// Provider protocols, manifest parsing, bundle-scoped caching, downloads,
/// archive extraction, cancellation, recovery decisions, and atomic instance
/// commits remain in this adapter. The injected byte-only download port is the
/// sole test seam; it never carries Qt objects, Swift values, credentials, or
/// ownership across the facade boundary.
class ProductionProviderRuntime final {
   public:
    using DownloadBytes = std::vector<std::uint8_t>;
    using DownloadProgressHandler = std::function<void(std::uint64_t, std::uint64_t)>;
    using DownloadCancellationCheck = std::function<bool()>;
    using DownloadHandler = std::function<std::optional<DownloadBytes>(
        const std::string&, const DownloadProgressHandler&, const DownloadCancellationCheck&)>;

    explicit ProductionProviderRuntime(std::filesystem::path dataRoot, DownloadHandler download = {});
    ~ProductionProviderRuntime() noexcept;

    ProductionProviderRuntime(const ProductionProviderRuntime&) = delete;
    ProductionProviderRuntime& operator=(const ProductionProviderRuntime&) = delete;

    FrontendProviderBrowseResult browse(
        const FrontendProviderBrowseRequest& request,
        const FrontendRuntimeDependencies::ProviderBrowseProgressHandler& progress,
        const FrontendRuntimeDependencies::ProviderBrowseCancellationCheck& cancellation);

    FrontendProviderVersionResult versions(
        const FrontendProviderVersionRequest& request,
        const FrontendRuntimeDependencies::ProviderVersionProgressHandler& progress,
        const FrontendRuntimeDependencies::ProviderVersionCancellationCheck& cancellation);

    FrontendProviderInstallResult install(
        const FrontendProviderInstallRequest& request,
        const FrontendRuntimeDependencies::ProviderInstallProgressHandler& progress,
        const FrontendRuntimeDependencies::ProviderInstallCancellationCheck& cancellation);

    void shutdown() noexcept;

   private:
    std::filesystem::path m_dataRoot;
    std::filesystem::path m_instancesRoot;
    std::filesystem::path m_cacheRoot;
    std::filesystem::path m_stagingRoot;
    DownloadHandler m_download;
    std::mutex m_operationMutex;
    bool m_shutdown = false;
};

std::shared_ptr<ProductionProviderRuntime> makeProductionProviderRuntime(
    std::filesystem::path dataRoot, ProductionProviderRuntime::DownloadHandler download = {});
