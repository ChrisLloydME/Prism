// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <string>
#include <vector>

struct FrontendInstanceSnapshot final {
    std::string id;
    std::string name;
    std::string iconKey;
    std::string groupId;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

enum class FrontendInstanceChangeKind : std::uint8_t { Added, Updated, Removed };

enum class FrontendLifecycleState : std::uint8_t { Running, ShuttingDown, Stopped };

struct FrontendInstanceChange final {
    FrontendInstanceChangeKind kind = FrontendInstanceChangeKind::Updated;
    FrontendInstanceSnapshot instance;
};

/// Runtime ports are supplied by the owning composition root so the facade
/// does not discover global application state or create hidden workers.
struct FrontendRuntimeDependencies final {
    using Work = std::function<void()>;
    using Dispatch = std::function<void(Work)>;
    using Clock = std::function<std::chrono::system_clock::time_point()>;
    using CancelPendingWork = std::function<void()>;
    using Shutdown = std::function<void()>;
    using InstanceSnapshotLoader = std::function<std::vector<FrontendInstanceSnapshot>(const std::filesystem::path&)>;
    using InstanceChangeLoader = std::function<std::vector<FrontendInstanceChange>(const std::filesystem::path&)>;

    Dispatch dispatch;
    Clock now;
    CancelPendingWork cancelPendingWork;
    Shutdown shutdown;
    InstanceSnapshotLoader loadInstanceSnapshots;
    InstanceChangeLoader loadInstanceChanges;

    bool isComplete() const noexcept
    {
        return static_cast<bool>(dispatch) && static_cast<bool>(now) && static_cast<bool>(cancelPendingWork)
            && static_cast<bool>(shutdown);
    }
};

/// UI-free entry point for native frontend use cases.
///
/// The facade owns the explicit root and injected runtime ports. Backend
/// services, snapshots, events, and lifecycle operations through explicit
/// value and callback contracts.
class FrontendFacade final {
   public:
    FrontendFacade(std::filesystem::path dataRoot, FrontendRuntimeDependencies runtimeDependencies);
    ~FrontendFacade() noexcept;

    FrontendFacade(const FrontendFacade&) = delete;
    FrontendFacade& operator=(const FrontendFacade&) = delete;
    FrontendFacade(FrontendFacade&&) = delete;
    FrontendFacade& operator=(FrontendFacade&&) = delete;

    const std::filesystem::path& dataRoot() const noexcept { return m_dataRoot; }
    bool hasRuntimeDependencies() const noexcept { return m_runtimeDependencies.isComplete(); }
    FrontendLifecycleState lifecycleState() const noexcept { return m_lifecycleState; }
    bool shutdown() noexcept;
    std::vector<FrontendInstanceSnapshot> instanceSnapshots() const;
    std::vector<FrontendInstanceChange> instanceChanges() const;

   private:
    std::filesystem::path m_dataRoot;
    FrontendRuntimeDependencies m_runtimeDependencies;
    FrontendLifecycleState m_lifecycleState = FrontendLifecycleState::Running;
};
