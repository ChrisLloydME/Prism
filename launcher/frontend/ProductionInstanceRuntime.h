// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "FrontendFacade.h"

#include <condition_variable>
#include <filesystem>
#include <map>
#include <memory>
#include <mutex>
#include <thread>

/// QWidget-free production owner for the instance-library vertical slice.
///
/// The runtime deliberately reuses Prism's INIFile persistence format through
/// a small QtCore-only adapter. It owns the polling worker and all callbacks;
/// callers must stop it before destroying the composition root.
class ProductionInstanceRuntime final {
   public:
    using SnapshotMap = std::map<std::string, FrontendInstanceSnapshot>;

    explicit ProductionInstanceRuntime(std::filesystem::path dataRoot);
    ~ProductionInstanceRuntime() noexcept;

    ProductionInstanceRuntime(const ProductionInstanceRuntime&) = delete;
    ProductionInstanceRuntime& operator=(const ProductionInstanceRuntime&) = delete;

    std::vector<FrontendInstanceSnapshot> instanceSnapshots() const;
    std::vector<FrontendInstanceChange> takeInstanceChanges();
    FrontendMetadataInstanceResult createMetadataInstance(const FrontendMetadataInstanceRequest& request);
    bool startInstanceObservation(FrontendRuntimeDependencies::InstanceChangeHandler handler);
    void stopInstanceObservation() noexcept;
    void shutdown() noexcept;

   private:
    SnapshotMap scanInstances() const;
    void observeUntilStopped();

    std::filesystem::path m_dataRoot;
    std::filesystem::path m_instancesRoot;

    mutable std::mutex m_dataMutex;
    mutable std::mutex m_observationMutex;
    std::condition_variable m_observationCondition;
    SnapshotMap m_knownInstances;
    std::vector<FrontendInstanceChange> m_pendingChanges;
    FrontendRuntimeDependencies::InstanceChangeHandler m_changeHandler;
    std::thread m_observer;
    bool m_stopRequested = false;
    bool m_shutdown = false;
};

std::shared_ptr<ProductionInstanceRuntime> makeProductionInstanceRuntime(std::filesystem::path dataRoot);
FrontendRuntimeDependencies productionInstanceRuntimeDependencies(std::filesystem::path dataRoot);
