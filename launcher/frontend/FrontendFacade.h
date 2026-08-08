// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <optional>
#include <string>
#include <utility>
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

enum class FrontendInstanceCommandResult : std::uint8_t { Succeeded, UnknownInstance, Rejected };

enum class FrontendTaskState : std::uint8_t { Queued, Running, Cancelling, Succeeded, Failed, Cancelled };

enum class FrontendTaskProgressKind : std::uint8_t { None, Indeterminate, Determinate };

enum class FrontendTaskTerminalOutcome : std::uint8_t { Succeeded, Failed, Cancelled };

enum class FrontendTaskCancellationResult : std::uint8_t { Requested, AlreadyTerminal, UnknownTask, Rejected };

struct FrontendInstanceChange final {
    FrontendInstanceChangeKind kind = FrontendInstanceChangeKind::Updated;
    FrontendInstanceSnapshot instance;
};

struct FrontendTaskTerminalResult final {
    FrontendTaskTerminalOutcome outcome = FrontendTaskTerminalOutcome::Succeeded;
    std::string localizationKey;
    std::vector<std::pair<std::string, std::string>> substitutionValues;
    std::string diagnosticText;
    bool partialChangesRolledBack = false;
};

struct FrontendTaskSubtaskSnapshot final {
    std::string id;
    std::string name;
    FrontendTaskState state = FrontendTaskState::Queued;
    FrontendTaskProgressKind progressKind = FrontendTaskProgressKind::None;
    double progressFraction = 0.0;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

struct FrontendTaskSnapshot final {
    std::string id;
    std::string title;
    FrontendTaskState state = FrontendTaskState::Queued;
    FrontendTaskProgressKind progressKind = FrontendTaskProgressKind::None;
    double progressFraction = 0.0;
    bool cancellationAllowed = false;
    std::vector<FrontendTaskSubtaskSnapshot> subtasks;
    std::optional<FrontendTaskTerminalResult> terminalResult;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

inline constexpr std::size_t kFrontendLogMaxEntries = 512;
inline constexpr std::size_t kFrontendLogMaxBytes = 256 * 1024;

struct FrontendLogEntry final {
    std::uint64_t sequence = 0;
    std::string text;
    bool truncated = false;
};

struct FrontendLogSnapshot final {
    std::string taskId;
    std::vector<FrontendLogEntry> entries;
    std::uint64_t droppedEntryCount = 0;
    std::uint64_t totalByteCount = 0;
    bool truncated = false;

    bool hasStableIdentifier() const noexcept { return !taskId.empty(); }
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
    using InstanceCommand = std::function<FrontendInstanceCommandResult(const std::filesystem::path&, const std::string&)>;
    using TaskSnapshotLoader = std::function<std::optional<FrontendTaskSnapshot>(const std::filesystem::path&, const std::string&)>;
    using TaskCancellation = std::function<FrontendTaskCancellationResult(const std::filesystem::path&, const std::string&)>;
    using LogEntryHandler = std::function<void(FrontendLogEntry)>;
    using TaskLogStreamer = std::function<bool(const std::filesystem::path&, const std::string&, const LogEntryHandler&)>;

    Dispatch dispatch;
    Clock now;
    CancelPendingWork cancelPendingWork;
    Shutdown shutdown;
    InstanceSnapshotLoader loadInstanceSnapshots;
    InstanceChangeLoader loadInstanceChanges;
    InstanceCommand launchInstance;
    InstanceCommand stopInstance;
    TaskSnapshotLoader loadTaskSnapshot;
    TaskCancellation cancelTask;
    TaskLogStreamer streamTaskLogs;

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
    FrontendInstanceCommandResult launchInstance(const std::string& instanceIdentifier) const;
    FrontendInstanceCommandResult stopInstance(const std::string& instanceIdentifier) const;
    std::optional<FrontendTaskSnapshot> taskSnapshot(const std::string& taskIdentifier) const;
    FrontendTaskCancellationResult cancelTask(const std::string& taskIdentifier) const;
    std::optional<FrontendLogSnapshot> taskLogSnapshot(const std::string& taskIdentifier) const;

   private:
    std::filesystem::path m_dataRoot;
    FrontendRuntimeDependencies m_runtimeDependencies;
    FrontendLifecycleState m_lifecycleState = FrontendLifecycleState::Running;
};
