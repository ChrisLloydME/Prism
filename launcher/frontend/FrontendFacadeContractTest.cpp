// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <utility>

namespace {

std::filesystem::path makeFixtureRoot(std::error_code& error)
{
    const auto temporaryRoot = std::filesystem::temp_directory_path(error);
    if (error) {
        return {};
    }

    const auto suffix = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto fixtureRoot = temporaryRoot / ("prism-frontend-contract-" + std::to_string(suffix));
    if (!std::filesystem::create_directory(fixtureRoot, error)) {
        return {};
    }
    return fixtureRoot;
}

}  // namespace

FrontendRuntimeDependencies makeFixtureDependencies()
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::time_point{}; };
    dependencies.cancelPendingWork = [] {};
    dependencies.shutdown = [] {};
    return dependencies;
}

template <typename Function>
bool throwsInvalidArgument(Function&& function)
{
    try {
        function();
    } catch (const std::invalid_argument&) {
        return true;
    }
    return false;
}

template <typename Function>
bool throwsLogicError(Function&& function)
{
    try {
        function();
    } catch (const std::logic_error&) {
        return true;
    }
    return false;
}

int main()
{
    std::error_code error;
    const auto fixtureRoot = makeFixtureRoot(error);
    if (error || fixtureRoot.empty()) {
        return 1;
    }

    const auto fixtureMarker = fixtureRoot / "fixture.marker";
    {
        std::ofstream marker(fixtureMarker);
        if (!marker) {
            std::filesystem::remove(fixtureRoot, error);
            return 2;
        }
        marker << "temporary fixture";
    }

    {
        FrontendFacade facade(fixtureRoot / "nested" / "..", makeFixtureDependencies());
        if (facade.dataRoot() != fixtureRoot.lexically_normal() || !facade.hasRuntimeDependencies()) {
            std::filesystem::remove(fixtureMarker, error);
            std::filesystem::remove(fixtureRoot, error);
            return 3;
        }
    }

    auto emptyDependencies = makeFixtureDependencies();
    emptyDependencies.loadInstanceSnapshots = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceSnapshot>{};
    };
    emptyDependencies.loadInstanceChanges = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceChange>{};
    };
    FrontendFacade emptyFacade(fixtureRoot, std::move(emptyDependencies));
    const bool emptyContract = emptyFacade.instanceSnapshots().empty() && emptyFacade.instanceChanges().empty();

    const FrontendInstanceSnapshot firstInstance{ "fixture-one", "Fixture One", "grass", "group-a" };
    const FrontendInstanceSnapshot secondInstance{ "fixture-two", "Fixture Two", "stone", "" };
    bool snapshotRootMatches = false;
    bool changeRootMatches = false;
    auto fixtureDependencies = makeFixtureDependencies();
    fixtureDependencies.loadInstanceSnapshots = [&](const std::filesystem::path& root) {
        snapshotRootMatches = root == fixtureRoot.lexically_normal();
        return std::vector<FrontendInstanceSnapshot>{ firstInstance, secondInstance };
    };
    fixtureDependencies.loadInstanceChanges = [&](const std::filesystem::path& root) {
        changeRootMatches = root == fixtureRoot.lexically_normal();
        return std::vector<FrontendInstanceChange>{
            { FrontendInstanceChangeKind::Added, firstInstance },
            { FrontendInstanceChangeKind::Updated, secondInstance },
            { FrontendInstanceChangeKind::Removed, { secondInstance.id, {}, {}, {} } },
        };
    };
    FrontendFacade fixtureFacade(fixtureRoot / "nested" / "..", std::move(fixtureDependencies));
    const auto snapshots = fixtureFacade.instanceSnapshots();
    const auto changes = fixtureFacade.instanceChanges();
    const bool fixtureSnapshotContract = snapshots.size() == 2 && snapshots[0].id == "fixture-one"
        && snapshots[1].groupId.empty() && snapshotRootMatches;
    const bool fixtureChangeContract = changes.size() == 3 && changes[0].kind == FrontendInstanceChangeKind::Added
        && changes[1].kind == FrontendInstanceChangeKind::Updated && changes[2].kind == FrontendInstanceChangeKind::Removed
        && changes[2].instance.id == "fixture-two" && changeRootMatches;

    std::vector<std::string> launchCalls;
    std::vector<std::string> stopCalls;
    bool commandRootMatches = true;
    auto commandDependencies = makeFixtureDependencies();
    commandDependencies.launchInstance = [&](const std::filesystem::path& root, const std::string& identifier) {
        commandRootMatches = commandRootMatches && root == fixtureRoot.lexically_normal();
        launchCalls.push_back(identifier);
        if (identifier == "fixture-one") {
            return FrontendInstanceCommandResult::Succeeded;
        }
        if (identifier == "unknown-instance") {
            return FrontendInstanceCommandResult::UnknownInstance;
        }
        return FrontendInstanceCommandResult::Rejected;
    };
    commandDependencies.stopInstance = [&](const std::filesystem::path& root, const std::string& identifier) {
        commandRootMatches = commandRootMatches && root == fixtureRoot.lexically_normal();
        stopCalls.push_back(identifier);
        if (identifier == "fixture-one") {
            return FrontendInstanceCommandResult::Succeeded;
        }
        if (identifier == "unknown-instance") {
            return FrontendInstanceCommandResult::UnknownInstance;
        }
        return FrontendInstanceCommandResult::Rejected;
    };
    FrontendFacade commandFacade(fixtureRoot / "nested" / "..", std::move(commandDependencies));
    const bool commandOutcomes = commandFacade.launchInstance("fixture-one") == FrontendInstanceCommandResult::Succeeded
        && commandFacade.launchInstance("fixture-one") == FrontendInstanceCommandResult::Succeeded
        && commandFacade.launchInstance("unknown-instance") == FrontendInstanceCommandResult::UnknownInstance
        && commandFacade.launchInstance("rejected-instance") == FrontendInstanceCommandResult::Rejected
        && commandFacade.stopInstance("fixture-one") == FrontendInstanceCommandResult::Succeeded
        && commandFacade.stopInstance("fixture-one") == FrontendInstanceCommandResult::Succeeded
        && commandFacade.stopInstance("unknown-instance") == FrontendInstanceCommandResult::UnknownInstance
        && commandFacade.stopInstance("rejected-instance") == FrontendInstanceCommandResult::Rejected;
    const bool repeatedCommandsAreForwarded = launchCalls == std::vector<std::string>{ "fixture-one", "fixture-one", "unknown-instance", "rejected-instance" }
        && stopCalls == std::vector<std::string>{ "fixture-one", "fixture-one", "unknown-instance", "rejected-instance" };
    const bool rejectedInvalidCommandIdentifiers = throwsInvalidArgument([&commandFacade] {
        (void) commandFacade.launchInstance("");
    }) && throwsInvalidArgument([&commandFacade] {
        (void) commandFacade.stopInstance("");
    });
    const bool commandRootContract = commandRootMatches && commandOutcomes && repeatedCommandsAreForwarded
        && rejectedInvalidCommandIdentifiers;
    const bool missingCommandPortsAreRejected = emptyFacade.launchInstance("fixture-one") == FrontendInstanceCommandResult::Rejected
        && emptyFacade.stopInstance("fixture-one") == FrontendInstanceCommandResult::Rejected;
    const bool rejectedPostShutdownCommands = commandFacade.shutdown()
        && throwsLogicError([&commandFacade] {
               (void) commandFacade.launchInstance("fixture-one");
           })
        && throwsLogicError([&commandFacade] {
               (void) commandFacade.stopInstance("fixture-one");
           });

    auto taskSuccess = FrontendTaskTerminalResult{
        FrontendTaskTerminalOutcome::Succeeded,
        "task.completed",
        { { "taskIdentifier", "task.success" } },
        "",
        false,
    };
    auto taskFailure = FrontendTaskTerminalResult{
        FrontendTaskTerminalOutcome::Failed,
        "task.failed",
        { { "taskIdentifier", "task.failed" } },
        "fixture failure",
        true,
    };
    auto taskCancelled = FrontendTaskTerminalResult{
        FrontendTaskTerminalOutcome::Cancelled,
        "task.cancelled",
        {},
        "fixture cancelled",
        false,
    };
    std::vector<std::string> taskSnapshotCalls;
    std::vector<std::string> taskCancellationCalls;
    bool taskRootMatches = true;
    auto taskDependencies = makeFixtureDependencies();
    taskDependencies.loadTaskSnapshot = [&](const std::filesystem::path& root, const std::string& identifier)
        -> std::optional<FrontendTaskSnapshot> {
        taskRootMatches = taskRootMatches && root == fixtureRoot.lexically_normal();
        taskSnapshotCalls.push_back(identifier);
        if (identifier == "task.queued") {
            return FrontendTaskSnapshot{ identifier, "Queued Task", FrontendTaskState::Queued,
                                         FrontendTaskProgressKind::None, 0.0, true, {}, std::nullopt };
        }
        if (identifier == "task.running") {
            return FrontendTaskSnapshot{ identifier,
                                         "Running Task",
                                         FrontendTaskState::Running,
                                         FrontendTaskProgressKind::Determinate,
                                         0.5,
                                         true,
                                         { { "subtask.download", "Download", FrontendTaskState::Running,
                                             FrontendTaskProgressKind::Determinate, 0.5 } },
                                         std::nullopt };
        }
        if (identifier == "task.cancelling") {
            return FrontendTaskSnapshot{ identifier, "Cancelling Task", FrontendTaskState::Cancelling,
                                         FrontendTaskProgressKind::Indeterminate, 0.0, false, {}, std::nullopt };
        }
        if (identifier == "task.success") {
            return FrontendTaskSnapshot{ identifier, "Succeeded Task", FrontendTaskState::Succeeded,
                                         FrontendTaskProgressKind::Determinate, 1.0, false, {}, taskSuccess };
        }
        if (identifier == "task.failed") {
            return FrontendTaskSnapshot{ identifier, "Failed Task", FrontendTaskState::Failed,
                                         FrontendTaskProgressKind::Determinate, 1.0, false, {}, taskFailure };
        }
        if (identifier == "task.cancelled") {
            return FrontendTaskSnapshot{ identifier, "Cancelled Task", FrontendTaskState::Cancelled,
                                         FrontendTaskProgressKind::Indeterminate, 0.0, false, {}, taskCancelled };
        }
        return std::nullopt;
    };
    taskDependencies.cancelTask = [&](const std::filesystem::path& root, const std::string& identifier) {
        taskRootMatches = taskRootMatches && root == fixtureRoot.lexically_normal();
        taskCancellationCalls.push_back(identifier);
        if (identifier == "task.running") {
            return taskCancellationCalls.size() == 1 ? FrontendTaskCancellationResult::Requested
                                                     : FrontendTaskCancellationResult::AlreadyTerminal;
        }
        if (identifier == "unknown-task") {
            return FrontendTaskCancellationResult::UnknownTask;
        }
        return FrontendTaskCancellationResult::Rejected;
    };
    FrontendFacade taskFacade(fixtureRoot / "nested" / "..", std::move(taskDependencies));
    const auto queuedTask = taskFacade.taskSnapshot("task.queued");
    const auto runningTask = taskFacade.taskSnapshot("task.running");
    const auto cancellingTask = taskFacade.taskSnapshot("task.cancelling");
    const auto succeededTask = taskFacade.taskSnapshot("task.success");
    const auto failedTask = taskFacade.taskSnapshot("task.failed");
    const auto cancelledTask = taskFacade.taskSnapshot("task.cancelled");
    const auto unknownTask = taskFacade.taskSnapshot("unknown-task");
    const bool taskStateContract = queuedTask.has_value() && queuedTask->state == FrontendTaskState::Queued
        && queuedTask->cancellationAllowed && runningTask.has_value()
        && runningTask->subtasks.size() == 1 && runningTask->subtasks[0].id == "subtask.download"
        && cancellingTask.has_value() && cancellingTask->state == FrontendTaskState::Cancelling
        && succeededTask.has_value() && succeededTask->terminalResult.has_value()
        && succeededTask->terminalResult->outcome == FrontendTaskTerminalOutcome::Succeeded
        && failedTask.has_value() && failedTask->terminalResult.has_value()
        && failedTask->terminalResult->outcome == FrontendTaskTerminalOutcome::Failed
        && failedTask->terminalResult->partialChangesRolledBack
        && cancelledTask.has_value() && cancelledTask->terminalResult.has_value()
        && cancelledTask->terminalResult->outcome == FrontendTaskTerminalOutcome::Cancelled && !unknownTask.has_value();
    const auto firstTaskCancellation = taskFacade.cancelTask("task.running");
    const auto repeatedTaskCancellation = taskFacade.cancelTask("task.running");
    const auto unknownTaskCancellation = taskFacade.cancelTask("unknown-task");
    const auto rejectedTaskCancellation = taskFacade.cancelTask("task.success");
    const bool taskCancellationContract = firstTaskCancellation == FrontendTaskCancellationResult::Requested
        && repeatedTaskCancellation == FrontendTaskCancellationResult::AlreadyTerminal
        && unknownTaskCancellation == FrontendTaskCancellationResult::UnknownTask
        && rejectedTaskCancellation == FrontendTaskCancellationResult::Rejected
        && taskCancellationCalls == std::vector<std::string>{ "task.running", "task.running", "unknown-task", "task.success" };
    const bool taskForwardingContract = taskRootMatches
        && taskSnapshotCalls == std::vector<std::string>{ "task.queued", "task.running", "task.cancelling", "task.success",
                                                           "task.failed", "task.cancelled", "unknown-task" };
    const bool rejectedInvalidTaskIdentifiers = throwsInvalidArgument([&taskFacade] {
        (void) taskFacade.taskSnapshot("");
    }) && throwsInvalidArgument([&taskFacade] {
        (void) taskFacade.cancelTask("");
    });
    const bool missingTaskPortsAreSafe = !emptyFacade.taskSnapshot("task.fixture").has_value()
        && emptyFacade.cancelTask("task.fixture") == FrontendTaskCancellationResult::Rejected;
    const bool rejectedPostShutdownTaskWork = taskFacade.shutdown()
        && throwsLogicError([&taskFacade] {
               (void) taskFacade.taskSnapshot("task.running");
           })
        && throwsLogicError([&taskFacade] {
               (void) taskFacade.cancelTask("task.running");
           });

    bool logRootMatches = true;
    auto logDependencies = makeFixtureDependencies();
    logDependencies.streamTaskLogs = [&logRootMatches, &fixtureRoot](
                                         const std::filesystem::path& root,
                                         const std::string& identifier,
                                         const FrontendRuntimeDependencies::LogEntryHandler& handler) {
        logRootMatches = logRootMatches && root == fixtureRoot.lexically_normal();
        if (identifier == "task.logs") {
            for (std::uint64_t sequence = 0; sequence < kFrontendLogMaxEntries + 8; ++sequence) {
                std::string text = "fixture log " + std::to_string(sequence);
                if (sequence == kFrontendLogMaxEntries + 7) {
                    text = "Authorization: Bearer fixture-secret access_token=fixture-token path="
                        + fixtureRoot.string() + "/instances/fixture username=fixture-user";
                }
                handler(FrontendLogEntry{ sequence, std::move(text), false });
            }
            return true;
        }
        if (identifier == "task.long-log") {
            handler(FrontendLogEntry{ 1, std::string(kFrontendLogMaxBytes + 32, 'x'), false });
            return true;
        }
        return false;
    };
    FrontendFacade logFacade(fixtureRoot / "nested" / "..", std::move(logDependencies));
    const auto logSnapshot = logFacade.taskLogSnapshot("task.logs");
    const auto longLogSnapshot = logFacade.taskLogSnapshot("task.long-log");
    const auto unknownLogSnapshot = logFacade.taskLogSnapshot("unknown-log");
    const bool logPrivacyAndBounds = logSnapshot.has_value() && logSnapshot->hasStableIdentifier()
        && logSnapshot->entries.size() == kFrontendLogMaxEntries
        && logSnapshot->droppedEntryCount == 8
        && logSnapshot->truncated
        && logSnapshot->entries.front().sequence == 8
        && logSnapshot->entries.back().text.find("fixture-secret") == std::string::npos
        && logSnapshot->entries.back().text.find("fixture-token") == std::string::npos
        && logSnapshot->entries.back().text.find("fixture-user") == std::string::npos
        && logSnapshot->entries.back().text.find(fixtureRoot.string()) == std::string::npos
        && logSnapshot->entries.back().text.find("<redacted>") != std::string::npos
        && logSnapshot->entries.back().text.find("<data-root>") != std::string::npos
        && logSnapshot->totalByteCount <= kFrontendLogMaxBytes && logRootMatches;
    const bool longLogIsTruncated = longLogSnapshot.has_value() && longLogSnapshot->entries.size() == 1
        && longLogSnapshot->entries.front().truncated
        && longLogSnapshot->entries.front().text.size() == kFrontendLogMaxBytes
        && longLogSnapshot->truncated && longLogSnapshot->totalByteCount == kFrontendLogMaxBytes;
    const bool missingLogPortIsSafe = !emptyFacade.taskLogSnapshot("task.logs").has_value()
        && throwsInvalidArgument([&logFacade] {
               (void) logFacade.taskLogSnapshot("");
           })
        && !unknownLogSnapshot.has_value()
        && logFacade.shutdown()
        && throwsLogicError([&logFacade] {
               (void) logFacade.taskLogSnapshot("task.logs");
           });

    auto invalidTaskProgressDependencies = makeFixtureDependencies();
    invalidTaskProgressDependencies.loadTaskSnapshot = [](const std::filesystem::path&, const std::string&)
        -> std::optional<FrontendTaskSnapshot> {
        return FrontendTaskSnapshot{ "invalid.task", "Invalid Task", FrontendTaskState::Running,
                                     FrontendTaskProgressKind::Determinate, 1.5, true, {}, std::nullopt };
    };
    FrontendFacade invalidTaskProgressFacade(fixtureRoot, std::move(invalidTaskProgressDependencies));
    const bool rejectedInvalidTaskProgress = throwsInvalidArgument([&invalidTaskProgressFacade] {
        (void) invalidTaskProgressFacade.taskSnapshot("invalid.task");
    });

    auto invalidTaskSubtasksDependencies = makeFixtureDependencies();
    invalidTaskSubtasksDependencies.loadTaskSnapshot = [](const std::filesystem::path&, const std::string&)
        -> std::optional<FrontendTaskSnapshot> {
        return FrontendTaskSnapshot{ "invalid.task", "Invalid Task", FrontendTaskState::Running,
                                     FrontendTaskProgressKind::Determinate, 0.5, true,
                                     { { "duplicate", "First", FrontendTaskState::Running,
                                         FrontendTaskProgressKind::Determinate, 0.5 },
                                       { "duplicate", "Second", FrontendTaskState::Running,
                                         FrontendTaskProgressKind::Determinate, 0.75 } },
                                     std::nullopt };
    };
    FrontendFacade invalidTaskSubtasksFacade(fixtureRoot, std::move(invalidTaskSubtasksDependencies));
    const bool rejectedInvalidTaskSubtasks = throwsInvalidArgument([&invalidTaskSubtasksFacade] {
        (void) invalidTaskSubtasksFacade.taskSnapshot("invalid.task");
    });

    auto invalidTaskTerminalDependencies = makeFixtureDependencies();
    invalidTaskTerminalDependencies.loadTaskSnapshot = [](const std::filesystem::path&, const std::string&)
        -> std::optional<FrontendTaskSnapshot> {
        return FrontendTaskSnapshot{ "invalid.task", "Invalid Task", FrontendTaskState::Failed,
                                     FrontendTaskProgressKind::Determinate, 1.0, false, {},
                                     FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Succeeded,
                                                                 "task.completed", {}, "", false } };
    };
    FrontendFacade invalidTaskTerminalFacade(fixtureRoot, std::move(invalidTaskTerminalDependencies));
    const bool rejectedInvalidTaskTerminalResult = throwsInvalidArgument([&invalidTaskTerminalFacade] {
        (void) invalidTaskTerminalFacade.taskSnapshot("invalid.task");
    });

    auto invalidSnapshotDependencies = makeFixtureDependencies();
    invalidSnapshotDependencies.loadInstanceSnapshots = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceSnapshot>{ { "", "Invalid", "", "" } };
    };
    FrontendFacade invalidSnapshotFacade(fixtureRoot, std::move(invalidSnapshotDependencies));
    const bool rejectedInvalidSnapshot = throwsInvalidArgument([&invalidSnapshotFacade] {
        (void) invalidSnapshotFacade.instanceSnapshots();
    });

    auto invalidChangeDependencies = makeFixtureDependencies();
    invalidChangeDependencies.loadInstanceChanges = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceChange>{
            { static_cast<FrontendInstanceChangeKind>(99), { "fixture-one", "", "", "" } },
        };
    };
    FrontendFacade invalidChangeFacade(fixtureRoot, std::move(invalidChangeDependencies));
    const bool rejectedInvalidChange = throwsInvalidArgument([&invalidChangeFacade] {
        (void) invalidChangeFacade.instanceChanges();
    });

    const bool fixtureWasPreserved = std::filesystem::exists(fixtureMarker);
    const bool rejectedEmptyRoot = throwsInvalidArgument([] {
        FrontendFacade facade({}, makeFixtureDependencies());
        (void) facade;
    });
    const bool rejectedRelativeRoot = throwsInvalidArgument([] {
        FrontendFacade facade(std::filesystem::path("relative-fixture-root"), makeFixtureDependencies());
        (void) facade;
    });
    const bool rejectedIncompleteDependencies = throwsInvalidArgument([&fixtureRoot] {
        FrontendFacade facade(fixtureRoot, {});
        (void) facade;
    });

    std::size_t cancelPendingWorkCount = 0;
    std::size_t shutdownCount = 0;
    std::size_t snapshotLoaderCount = 0;
    std::size_t changeLoaderCount = 0;
    FrontendLifecycleState shutdownCallbackState = FrontendLifecycleState::Running;
    FrontendFacade* lifecycleFacadePointer = nullptr;
    bool lifecycleContract = false;
    {
        auto lifecycleDependencies = makeFixtureDependencies();
        lifecycleDependencies.cancelPendingWork = [&cancelPendingWorkCount] { ++cancelPendingWorkCount; };
        lifecycleDependencies.shutdown = [&shutdownCount, &shutdownCallbackState, &lifecycleFacadePointer] {
            ++shutdownCount;
            if (lifecycleFacadePointer) {
                shutdownCallbackState = lifecycleFacadePointer->lifecycleState();
            }
        };
        lifecycleDependencies.loadInstanceSnapshots = [&snapshotLoaderCount](const std::filesystem::path&) {
            ++snapshotLoaderCount;
            return std::vector<FrontendInstanceSnapshot>{ { "post-shutdown-snapshot", "", "", "" } };
        };
        lifecycleDependencies.loadInstanceChanges = [&changeLoaderCount](const std::filesystem::path&) {
            ++changeLoaderCount;
            return std::vector<FrontendInstanceChange>{
                { FrontendInstanceChangeKind::Added, { "post-shutdown-change", "", "", "" } },
            };
        };

        FrontendFacade lifecycleFacade(fixtureRoot, std::move(lifecycleDependencies));
        lifecycleFacadePointer = &lifecycleFacade;
        const bool initiallyRunning = lifecycleFacade.lifecycleState() == FrontendLifecycleState::Running;
        const bool firstShutdown = lifecycleFacade.shutdown();
        const bool repeatedShutdown = !lifecycleFacade.shutdown();
        const bool stoppedAfterShutdown = lifecycleFacade.lifecycleState() == FrontendLifecycleState::Stopped;
        const bool releasedDependencies = !lifecycleFacade.hasRuntimeDependencies();
        const bool rejectedSnapshotWork = throwsLogicError([&lifecycleFacade] {
            (void) lifecycleFacade.instanceSnapshots();
        });
        const bool rejectedChangeWork = throwsLogicError([&lifecycleFacade] {
            (void) lifecycleFacade.instanceChanges();
        });
        lifecycleFacadePointer = nullptr;
        lifecycleContract = initiallyRunning && firstShutdown && repeatedShutdown && stoppedAfterShutdown
            && releasedDependencies && rejectedSnapshotWork && rejectedChangeWork;
    }
    const bool callbacksRanExactlyOnce = cancelPendingWorkCount == 1 && shutdownCount == 1
        && shutdownCallbackState == FrontendLifecycleState::ShuttingDown && snapshotLoaderCount == 0 && changeLoaderCount == 0;

    std::size_t implicitShutdownCount = 0;
    {
        auto implicitDependencies = makeFixtureDependencies();
        implicitDependencies.shutdown = [&implicitShutdownCount] { ++implicitShutdownCount; };
        FrontendFacade implicitFacade(fixtureRoot, std::move(implicitDependencies));
        if (implicitFacade.lifecycleState() != FrontendLifecycleState::Running) {
            std::filesystem::remove(fixtureMarker, error);
            std::filesystem::remove(fixtureRoot, error);
            return 4;
        }
    }
    const bool destructorShutdownContract = implicitShutdownCount == 1;

    std::filesystem::remove(fixtureMarker, error);
    std::filesystem::remove(fixtureRoot, error);
    return fixtureWasPreserved && emptyContract && fixtureSnapshotContract && fixtureChangeContract && commandRootContract
               && missingCommandPortsAreRejected && rejectedPostShutdownCommands && taskStateContract
               && taskCancellationContract && taskForwardingContract && rejectedInvalidTaskIdentifiers
               && missingTaskPortsAreSafe && rejectedPostShutdownTaskWork && rejectedInvalidTaskProgress
               && rejectedInvalidTaskSubtasks && rejectedInvalidTaskTerminalResult && rejectedInvalidSnapshot
               && rejectedInvalidChange && logPrivacyAndBounds && longLogIsTruncated && missingLogPortIsSafe
               && rejectedEmptyRoot && rejectedRelativeRoot && rejectedIncompleteDependencies
               && lifecycleContract && callbacksRanExactlyOnce && destructorShutdownContract && !error
        ? 0
        : 4;
}
