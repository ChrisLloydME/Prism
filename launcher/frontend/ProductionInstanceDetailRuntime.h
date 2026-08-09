// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "FrontendFacade.h"

#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <vector>

/// QWidget-free production owner for instance metadata and detail files.
///
/// The runtime keeps Prism's persisted formats at the backend boundary: INI
/// instance metadata, mmc-pack component patches, gzip/NBT world metadata,
/// and servers.dat. Swift receives only the immutable FrontendFacade values;
/// path validation, mutation, rollback, and bounded log reads stay here.
class ProductionInstanceDetailRuntime final {
   public:
    explicit ProductionInstanceDetailRuntime(std::filesystem::path dataRoot);

    std::optional<FrontendInstanceDetailsSnapshot> instanceDetails(const std::string& identifier) const;
    std::optional<std::vector<FrontendInstanceComponentSnapshot>> instanceComponents(
        const std::string& identifier) const;
    std::optional<std::vector<FrontendInstanceResourceSnapshot>> instanceResources(
        const std::string& identifier, FrontendInstanceResourceKind kind) const;
    FrontendInstanceResourceMutationResult mutateInstanceResource(
        const std::string& identifier,
        FrontendInstanceResourceKind kind,
        const FrontendInstanceResourceMutationRequest& request);

    std::optional<std::vector<FrontendInstanceWorldSnapshot>> instanceWorlds(const std::string& identifier) const;
    std::optional<std::vector<FrontendInstanceServerSnapshot>> instanceServers(const std::string& identifier) const;
    std::optional<std::vector<FrontendInstanceScreenshotSnapshot>> instanceScreenshots(
        const std::string& identifier) const;
    std::optional<std::vector<FrontendInstanceLogFileSnapshot>> instanceLogFiles(const std::string& identifier) const;
    std::optional<FrontendInstanceLogSnapshot> instanceLog(
        const std::string& identifier, const std::string& logIdentifier) const;
    FrontendInstanceDetailMutationResult mutateInstanceDetail(
        const std::string& identifier, const FrontendInstanceDetailMutationRequest& request);

    FrontendInstanceNotesUpdateResult updateInstanceNotes(
        const std::string& identifier, const std::string& notes);
    FrontendInstanceDeleteResult deleteInstance(const std::string& identifier, bool confirmed);

    FrontendInstanceCopyResult copyInstance(
        const FrontendInstanceCopyRequest& request,
        const FrontendRuntimeDependencies::InstanceCopyProgressHandler& progressHandler,
        const FrontendRuntimeDependencies::InstanceCopyCancellationCheck& cancellationCheck);
    FrontendInstanceExportResult exportInstance(
        const FrontendInstanceExportRequest& request,
        const FrontendRuntimeDependencies::InstanceExportProgressHandler& progressHandler,
        const FrontendRuntimeDependencies::InstanceExportCancellationCheck& cancellationCheck);

   private:
    std::optional<std::filesystem::path> instancePath(const std::string& identifier) const;
    std::optional<std::filesystem::path> gameRoot(const std::string& identifier) const;

    std::filesystem::path m_dataRoot;
    std::filesystem::path m_instancesRoot;
    mutable std::mutex m_mutationMutex;
};

std::shared_ptr<ProductionInstanceDetailRuntime> makeProductionInstanceDetailRuntime(
    std::filesystem::path dataRoot);
