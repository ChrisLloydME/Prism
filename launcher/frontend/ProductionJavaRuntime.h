// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "FrontendFacade.h"
#include "settings/INIFile.h"

#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

/// QWidget-free production owner for Java discovery and selection.
///
/// The adapter has two deliberately separate source classes: managed
/// runtimes under the Native Prism data root and fixed macOS system JVM
/// locations. It never imports another launcher's Java settings or runtime
/// metadata. Process probing and filesystem operations are ports so tests can
/// exercise the production adapter without executing a host Java binary.
class ProductionJavaRuntime final {
   public:
    struct ProcessResult final {
        bool started = false;
        bool timedOut = false;
        int exitCode = -1;
        std::string standardOutput;
        std::string standardError;
    };

    using ProcessExecutor = std::function<ProcessResult(const std::filesystem::path&)>;

    struct FilesystemExecutor final {
        std::function<bool(const std::filesystem::path&)> isDirectory;
        std::function<bool(const std::filesystem::path&)> isRegularFile;
        std::function<bool(const std::filesystem::path&)> isSymlink;
        std::function<std::vector<std::filesystem::path>(const std::filesystem::path&)> childDirectories;
        std::function<std::filesystem::path(const std::filesystem::path&)> canonicalPath;
        std::function<bool(const std::filesystem::path&)> createDirectories;
        std::function<bool(const std::filesystem::path&, INIFile&)> loadINIFile;
        std::function<bool(const std::filesystem::path&, INIFile&)> saveINIFile;
    };

    struct Dependencies final {
        FilesystemExecutor filesystem;
        ProcessExecutor process;
    };

    static Dependencies defaultDependencies();

    explicit ProductionJavaRuntime(std::filesystem::path dataRoot, Dependencies dependencies = {});
    ~ProductionJavaRuntime() noexcept;

    ProductionJavaRuntime(const ProductionJavaRuntime&) = delete;
    ProductionJavaRuntime& operator=(const ProductionJavaRuntime&) = delete;

    FrontendJavaDiscoveryResult discover();
    FrontendJavaSelectionResult select(const std::string& installationIdentifier);
    void shutdown() noexcept;

    const std::filesystem::path& dataRoot() const noexcept { return m_dataRoot; }

   private:
    struct Candidate final {
        std::filesystem::path executablePath;
        std::string managedIdentifier;
        bool managed = false;
    };

    std::vector<Candidate> candidates() const;
    FrontendJavaInstallationSnapshot probe(const Candidate& candidate) const;
    std::string savedJavaPath() const;
    bool persistSelection(const FrontendJavaInstallationSnapshot& installation) const;

    std::filesystem::path m_dataRoot;
    std::filesystem::path m_managedRoot;
    std::filesystem::path m_globalSettingsPath;
    Dependencies m_dependencies;

    mutable std::mutex m_mutex;
    std::vector<FrontendJavaInstallationSnapshot> m_lastInstallations;
    bool m_shutdown = false;
};

std::shared_ptr<ProductionJavaRuntime> makeProductionJavaRuntime(
    std::filesystem::path dataRoot,
    ProductionJavaRuntime::Dependencies dependencies = {});

FrontendRuntimeDependencies productionJavaRuntimeDependencies(
    std::shared_ptr<ProductionJavaRuntime> runtime,
    FrontendRuntimeDependencies dependencies = {});
