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

/// QWidget-free production owner for instance creation and archive import.
///
/// The adapter keeps staging, archive inspection, Prism-format persistence,
/// download bytes, cancellation, rollback, and the final rename inside the
/// backend. Its download port is deliberately a byte-only seam so tests can
/// provide synthetic HTTP responses without crossing Qt or Foundation types.
class ProductionInstanceAcquisitionRuntime final {
   public:
    using DownloadBytes = std::vector<std::uint8_t>;
    using DownloadProgressHandler = std::function<void(std::uint64_t, std::uint64_t)>;
    using DownloadCancellationCheck = std::function<bool()>;
    using DownloadHandler = std::function<std::optional<DownloadBytes>(
        const std::string&, const DownloadProgressHandler&, const DownloadCancellationCheck&)>;

    explicit ProductionInstanceAcquisitionRuntime(std::filesystem::path dataRoot, DownloadHandler download = {});
    ~ProductionInstanceAcquisitionRuntime() noexcept;

    ProductionInstanceAcquisitionRuntime(const ProductionInstanceAcquisitionRuntime&) = delete;
    ProductionInstanceAcquisitionRuntime& operator=(const ProductionInstanceAcquisitionRuntime&) = delete;

    FrontendVanillaCreationResult createVanillaInstance(
        const FrontendVanillaCreationRequest& request,
        const FrontendRuntimeDependencies::VanillaCreationProgressHandler& progress,
        const FrontendRuntimeDependencies::VanillaCreationCancellationCheck& cancellation);

    FrontendInstanceImportResult importInstance(
        const FrontendInstanceImportRequest& request,
        const FrontendRuntimeDependencies::InstanceImportProgressHandler& progress,
        const FrontendRuntimeDependencies::InstanceImportCancellationCheck& cancellation);

    void shutdown() noexcept;

   private:
    std::filesystem::path makeStagingDirectory(const char* operation);

    std::filesystem::path m_dataRoot;
    std::filesystem::path m_instancesRoot;
    std::filesystem::path m_stagingRoot;
    DownloadHandler m_download;
    std::mutex m_operationMutex;
    bool m_shutdown = false;
};

std::shared_ptr<ProductionInstanceAcquisitionRuntime> makeProductionInstanceAcquisitionRuntime(
    std::filesystem::path dataRoot, ProductionInstanceAcquisitionRuntime::DownloadHandler download = {});
