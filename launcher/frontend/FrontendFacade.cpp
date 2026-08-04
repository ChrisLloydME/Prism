// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

#include <cmath>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>

namespace {

std::filesystem::path normalizeDataRoot(std::filesystem::path dataRoot)
{
    auto normalized = std::move(dataRoot).lexically_normal();
    auto normalizedString = normalized.generic_string();
    const auto rootString = normalized.root_path().generic_string();
    while (normalizedString.size() > rootString.size() && normalizedString.ends_with('/')) {
        normalizedString.pop_back();
    }
    return std::filesystem::path(normalizedString);
}

void validateInstanceSnapshots(const std::vector<FrontendInstanceSnapshot>& snapshots)
{
    std::set<std::string> identifiers;
    for (const auto& snapshot : snapshots) {
        if (!snapshot.hasStableIdentifier() || !identifiers.insert(snapshot.id).second) {
            throw std::invalid_argument("Instance snapshots require unique stable identifiers");
        }
    }
}

void validateInstanceChanges(const std::vector<FrontendInstanceChange>& changes)
{
    for (const auto& change : changes) {
        if (!change.instance.hasStableIdentifier()) {
            throw std::invalid_argument("Instance changes require stable identifiers");
        }
        switch (change.kind) {
            case FrontendInstanceChangeKind::Added:
            case FrontendInstanceChangeKind::Updated:
            case FrontendInstanceChangeKind::Removed:
                break;
            default:
                throw std::invalid_argument("Instance changes require a known change kind");
        }
    }
}

bool isKnownTaskState(FrontendTaskState state) noexcept
{
    switch (state) {
        case FrontendTaskState::Queued:
        case FrontendTaskState::Running:
        case FrontendTaskState::Cancelling:
        case FrontendTaskState::Succeeded:
        case FrontendTaskState::Failed:
        case FrontendTaskState::Cancelled:
            return true;
    }
    return false;
}

bool isKnownTaskProgressKind(FrontendTaskProgressKind progressKind) noexcept
{
    switch (progressKind) {
        case FrontendTaskProgressKind::None:
        case FrontendTaskProgressKind::Indeterminate:
        case FrontendTaskProgressKind::Determinate:
            return true;
    }
    return false;
}

bool isValidTaskProgress(FrontendTaskProgressKind progressKind, double progressFraction) noexcept
{
    if (!std::isfinite(progressFraction) || !isKnownTaskProgressKind(progressKind)) {
        return false;
    }

    if (progressKind == FrontendTaskProgressKind::Determinate) {
        return progressFraction >= 0.0 && progressFraction <= 1.0;
    }
    return progressFraction == 0.0;
}

bool isTerminalTaskState(FrontendTaskState state) noexcept
{
    return state == FrontendTaskState::Succeeded || state == FrontendTaskState::Failed
        || state == FrontendTaskState::Cancelled;
}

bool isKnownTaskTerminalOutcome(FrontendTaskTerminalOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendTaskTerminalOutcome::Succeeded:
        case FrontendTaskTerminalOutcome::Failed:
        case FrontendTaskTerminalOutcome::Cancelled:
            return true;
    }
    return false;
}

bool isKnownTaskCancellationResult(FrontendTaskCancellationResult result) noexcept
{
    switch (result) {
        case FrontendTaskCancellationResult::Requested:
        case FrontendTaskCancellationResult::AlreadyTerminal:
        case FrontendTaskCancellationResult::UnknownTask:
        case FrontendTaskCancellationResult::Rejected:
            return true;
    }
    return false;
}

void validateTaskTerminalResult(const FrontendTaskTerminalResult& result)
{
    if (!isKnownTaskTerminalOutcome(result.outcome) || result.localizationKey.empty()) {
        throw std::invalid_argument("Task terminal results require a known outcome and localization key");
    }

    for (const auto& [key, value] : result.substitutionValues) {
        if (key.empty()) {
            throw std::invalid_argument("Task terminal substitutions require non-empty keys");
        }
        (void)value;
    }
}

void validateTaskSubtask(const FrontendTaskSubtaskSnapshot& subtask)
{
    if (!subtask.hasStableIdentifier() || subtask.name.empty() || !isKnownTaskState(subtask.state)
        || !isValidTaskProgress(subtask.progressKind, subtask.progressFraction)) {
        throw std::invalid_argument("Task subtasks require valid identifiers, names, states, and progress");
    }
}

void validateTaskSnapshot(const FrontendTaskSnapshot& snapshot)
{
    if (!snapshot.hasStableIdentifier() || !isKnownTaskState(snapshot.state)
        || !isValidTaskProgress(snapshot.progressKind, snapshot.progressFraction)) {
        throw std::invalid_argument("Task snapshots require a valid identifier, state, and progress");
    }

    if ((snapshot.state == FrontendTaskState::Cancelling || isTerminalTaskState(snapshot.state))
        && snapshot.cancellationAllowed) {
        throw std::invalid_argument("Task cancellation is not allowed after cancellation or termination");
    }

    std::set<std::string> identifiers;
    for (const auto& subtask : snapshot.subtasks) {
        validateTaskSubtask(subtask);
        if (!identifiers.insert(subtask.id).second) {
            throw std::invalid_argument("Task subtasks require unique stable identifiers");
        }
    }

    if (!snapshot.terminalResult.has_value()) {
        if (isTerminalTaskState(snapshot.state)) {
            throw std::invalid_argument("Terminal task snapshots require a terminal result");
        }
        return;
    }

    const auto& terminalResult = *snapshot.terminalResult;
    validateTaskTerminalResult(terminalResult);
    const bool matchingOutcome = (snapshot.state == FrontendTaskState::Succeeded
                                     && terminalResult.outcome == FrontendTaskTerminalOutcome::Succeeded)
        || (snapshot.state == FrontendTaskState::Failed && terminalResult.outcome == FrontendTaskTerminalOutcome::Failed)
        || (snapshot.state == FrontendTaskState::Cancelled
            && terminalResult.outcome == FrontendTaskTerminalOutcome::Cancelled);
    if (!matchingOutcome) {
        throw std::invalid_argument("Task terminal results must match the task state");
    }
}

void ensureRunning(FrontendLifecycleState state)
{
    if (state != FrontendLifecycleState::Running) {
        throw std::logic_error("FrontendFacade is not running");
    }
}

bool isKnownInstanceCommandResult(FrontendInstanceCommandResult result) noexcept
{
    switch (result) {
        case FrontendInstanceCommandResult::Succeeded:
        case FrontendInstanceCommandResult::UnknownInstance:
        case FrontendInstanceCommandResult::Rejected:
            return true;
    }
    return false;
}

FrontendInstanceCommandResult executeInstanceCommand(
    const FrontendRuntimeDependencies::InstanceCommand& command,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier)
{
    if (instanceIdentifier.empty()) {
        throw std::invalid_argument("Instance commands require a stable identifier");
    }
    if (!command) {
        return FrontendInstanceCommandResult::Rejected;
    }

    const auto result = command(dataRoot, instanceIdentifier);
    if (!isKnownInstanceCommandResult(result)) {
        throw std::invalid_argument("Instance command returned an unknown result");
    }
    return result;
}

std::optional<FrontendTaskSnapshot> executeTaskSnapshot(
    const FrontendRuntimeDependencies::TaskSnapshotLoader& loader,
    const std::filesystem::path& dataRoot,
    const std::string& taskIdentifier)
{
    if (taskIdentifier.empty()) {
        throw std::invalid_argument("Task operations require a stable identifier");
    }
    if (!loader) {
        return std::nullopt;
    }

    auto snapshot = loader(dataRoot, taskIdentifier);
    if (snapshot.has_value()) {
        validateTaskSnapshot(*snapshot);
    }
    return snapshot;
}

FrontendTaskCancellationResult executeTaskCancellation(
    const FrontendRuntimeDependencies::TaskCancellation& cancellation,
    const std::filesystem::path& dataRoot,
    const std::string& taskIdentifier)
{
    if (taskIdentifier.empty()) {
        throw std::invalid_argument("Task operations require a stable identifier");
    }
    if (!cancellation) {
        return FrontendTaskCancellationResult::Rejected;
    }

    const auto result = cancellation(dataRoot, taskIdentifier);
    if (!isKnownTaskCancellationResult(result)) {
        throw std::invalid_argument("Task cancellation returned an unknown result");
    }
    return result;
}

}  // namespace

FrontendFacade::FrontendFacade(std::filesystem::path dataRoot, FrontendRuntimeDependencies runtimeDependencies)
    : m_dataRoot(normalizeDataRoot(std::move(dataRoot))), m_runtimeDependencies(std::move(runtimeDependencies))
{
    if (m_dataRoot.empty() || !m_dataRoot.is_absolute()) {
        throw std::invalid_argument("FrontendFacade requires an absolute data root");
    }
    if (!m_runtimeDependencies.isComplete()) {
        throw std::invalid_argument("FrontendFacade requires complete runtime dependencies");
    }
}

FrontendFacade::~FrontendFacade() noexcept
{
    shutdown();
}

bool FrontendFacade::shutdown() noexcept
{
    if (m_lifecycleState != FrontendLifecycleState::Running) {
        return false;
    }

    m_lifecycleState = FrontendLifecycleState::ShuttingDown;
    try {
        if (m_runtimeDependencies.cancelPendingWork) {
            m_runtimeDependencies.cancelPendingWork();
        }
    } catch (...) {
    }

    try {
        if (m_runtimeDependencies.shutdown) {
            m_runtimeDependencies.shutdown();
        }
    } catch (...) {
    }

    m_runtimeDependencies = {};
    m_lifecycleState = FrontendLifecycleState::Stopped;
    return true;
}

std::vector<FrontendInstanceSnapshot> FrontendFacade::instanceSnapshots() const
{
    ensureRunning(m_lifecycleState);
    if (!m_runtimeDependencies.loadInstanceSnapshots) {
        return {};
    }

    auto snapshots = m_runtimeDependencies.loadInstanceSnapshots(m_dataRoot);
    validateInstanceSnapshots(snapshots);
    return snapshots;
}

std::vector<FrontendInstanceChange> FrontendFacade::instanceChanges() const
{
    ensureRunning(m_lifecycleState);
    if (!m_runtimeDependencies.loadInstanceChanges) {
        return {};
    }

    auto changes = m_runtimeDependencies.loadInstanceChanges(m_dataRoot);
    validateInstanceChanges(changes);
    return changes;
}

FrontendInstanceCommandResult FrontendFacade::launchInstance(const std::string& instanceIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceCommand(m_runtimeDependencies.launchInstance, m_dataRoot, instanceIdentifier);
}

FrontendInstanceCommandResult FrontendFacade::stopInstance(const std::string& instanceIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceCommand(m_runtimeDependencies.stopInstance, m_dataRoot, instanceIdentifier);
}

std::optional<FrontendTaskSnapshot> FrontendFacade::taskSnapshot(const std::string& taskIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeTaskSnapshot(m_runtimeDependencies.loadTaskSnapshot, m_dataRoot, taskIdentifier);
}

FrontendTaskCancellationResult FrontendFacade::cancelTask(const std::string& taskIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeTaskCancellation(m_runtimeDependencies.cancelTask, m_dataRoot, taskIdentifier);
}
