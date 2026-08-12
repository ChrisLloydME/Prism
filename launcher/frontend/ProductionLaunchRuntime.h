// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "FrontendFacade.h"
#include "ProductionLaunchSession.h"

#include <atomic>
#include <filesystem>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

/// QWidget-free launch/process owner for the native frontend.
///
/// The legacy LaunchController path still owns the complete Qt Widgets launch
/// flow. This adapter is the narrow extraction seam for Native Prism: it reads
/// the persisted instance component/patch model through a QtCore-only domain
/// adapter, constructs the NewLaunch Java command and isolated environment,
/// then owns process lifetime, task state, logs, cancellation, and
/// persistence. Swift never reconstructs any of these values.
class ProductionLaunchRuntime final {
   public:
    struct ProcessSpec final {
        std::string program;
        std::vector<std::string> arguments;
        std::map<std::string, std::string> environment;
        std::filesystem::path workingDirectory;
        /// The script sent when the Java process reaches Running.
        std::string standardInput;
        /// The LauncherPartLaunch proceed() command sent after the script.
        std::string launchInput;
    };

    struct ProcessResult final {
        enum class Outcome : std::uint8_t { Succeeded, Failed, Cancelled };

        Outcome outcome = Outcome::Failed;
        int exitCode = -1;
        std::string diagnostic;
    };

    using ProcessLogHandler = std::function<void(std::string)>;
    using CancellationCheck = std::function<bool()>;
    using ProcessExecutor = std::function<ProcessResult(
        const ProcessSpec&, const ProcessLogHandler&, const CancellationCheck&)>;
    using LaunchSessionProvider = std::function<std::optional<ProductionLaunchSession>(const std::string&)>;

    explicit ProductionLaunchRuntime(
        std::filesystem::path dataRoot,
        ProcessExecutor executor = {},
        LaunchSessionProvider sessionProvider = {},
        std::filesystem::path backendExecutable = {});
    ~ProductionLaunchRuntime() noexcept;

    ProductionLaunchRuntime(const ProductionLaunchRuntime&) = delete;
    ProductionLaunchRuntime& operator=(const ProductionLaunchRuntime&) = delete;

    FrontendInstanceCommandResult launchInstance(const std::string& instanceIdentifier);
    FrontendInstanceCommandResult stopInstance(const std::string& instanceIdentifier);
    std::optional<FrontendTaskSnapshot> taskSnapshot(const std::string& taskIdentifier) const;
    FrontendTaskCancellationResult cancelTask(const std::string& taskIdentifier);
    bool streamTaskLogs(const std::string& taskIdentifier, const FrontendRuntimeDependencies::LogEntryHandler& handler) const;
    bool startTaskObservation(FrontendRuntimeDependencies::TaskObservationHandler handler);
    void stopTaskObservation() noexcept;
    void cancelPendingWork() noexcept;
    void shutdown() noexcept;

    static std::string taskIdentifierForInstance(const std::string& instanceIdentifier);

   private:
    struct TaskRecord;

    std::optional<ProcessSpec> readProcessSpec(
        const std::string& instanceIdentifier,
        const std::shared_ptr<TaskRecord>& record,
        std::string& diagnostic) const;
    std::shared_ptr<TaskRecord> makeTaskRecord(const std::string& instanceIdentifier);
    void runTask(const std::shared_ptr<TaskRecord>& record, ProcessSpec spec);
    void notifyTask(const std::shared_ptr<TaskRecord>& record);
    void appendLog(const std::shared_ptr<TaskRecord>& record, std::string text, bool truncated = false);
    void persistRecord(const std::shared_ptr<TaskRecord>& record) const;
    void loadPersistedRecords();

    std::filesystem::path m_dataRoot;
    std::filesystem::path m_instancesRoot;
    std::filesystem::path m_tasksRoot;
    ProcessExecutor m_executor;
    LaunchSessionProvider m_sessionProvider;
    std::filesystem::path m_backendExecutable;

    mutable std::mutex m_runtimeMutex;
    std::map<std::string, std::shared_ptr<TaskRecord>> m_records;
    FrontendRuntimeDependencies::TaskObservationHandler m_taskObserver;
    bool m_shutdown = false;
};

std::shared_ptr<ProductionLaunchRuntime> makeProductionLaunchRuntime(
    std::filesystem::path dataRoot,
    ProductionLaunchRuntime::ProcessExecutor executor = {},
    ProductionLaunchRuntime::LaunchSessionProvider sessionProvider = {},
    std::filesystem::path backendExecutable = {});

FrontendRuntimeDependencies productionLaunchRuntimeDependencies(
    std::shared_ptr<ProductionLaunchRuntime> runtime,
    FrontendRuntimeDependencies dependencies = {});
