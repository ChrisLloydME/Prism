// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

#include <algorithm>
#include <cmath>
#include <deque>
#include <regex>
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

void validateInstanceDetailsSnapshot(const FrontendInstanceDetailsSnapshot& snapshot)
{
    if (!snapshot.hasStableIdentifier() || snapshot.name.empty()) {
        throw std::invalid_argument("Instance details require a stable identifier and name");
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

std::string truncateUTF8(std::string value, std::size_t maxBytes)
{
    if (value.size() <= maxBytes) {
        return std::string(value);
    }

    value.resize(maxBytes);
    std::size_t boundary = value.size();
    while (boundary > 0 && (static_cast<unsigned char>(value[boundary - 1]) & 0xC0U) == 0x80U) {
        --boundary;
    }

    if (boundary < value.size() && boundary > 0) {
        const auto leadingByte = static_cast<unsigned char>(value[boundary - 1]);
        std::size_t expectedBytes = 1;
        if ((leadingByte & 0xE0U) == 0xC0U) {
            expectedBytes = 2;
        } else if ((leadingByte & 0xF0U) == 0xE0U) {
            expectedBytes = 3;
        } else if ((leadingByte & 0xF8U) == 0xF0U) {
            expectedBytes = 4;
        }

        const std::size_t leadingByteOffset = boundary - 1;
        if (expectedBytes != value.size() - leadingByteOffset) {
            boundary = leadingByteOffset;
        }
    }
    value.resize(boundary);
    return std::string(value);
}

void replaceAll(std::string& value, const std::string& search, const std::string& replacement)
{
    if (search.empty()) {
        return;
    }

    std::size_t offset = 0;
    while ((offset = value.find(search, offset)) != std::string::npos) {
        value.replace(offset, search.size(), replacement);
        offset += replacement.size();
    }
}

std::string privacyFilteredLogText(std::string value, const std::filesystem::path& dataRoot)
{
    const std::regex credentialPattern(
        R"(((--)?(access[_-]?token|refresh[_-]?token|client[_-]?secret|password|authorization|username|email|account|uuid|token)\s*([:=]|\s)\s*(Bearer\s+)?)([^\s,;]+))",
        std::regex_constants::icase);
    value = std::regex_replace(value, credentialPattern, "$1<redacted>");

    const std::string genericRoot = dataRoot.generic_string();
    const std::string nativeRoot = dataRoot.string();
    replaceAll(value, genericRoot, "<data-root>");
    if (nativeRoot != genericRoot) {
        replaceAll(value, nativeRoot, "<data-root>");
    }

    const std::regex homePathPattern(R"(((/Users|/home)/)[^/ \t\r\n]+)");
    value = std::regex_replace(value, homePathPattern, "$1<redacted>");
    return value;
}

class FrontendLogBuffer final {
   public:
    void append(FrontendLogEntry entry)
    {
        const bool lineWasTooLong = entry.text.size() > kFrontendLogMaxBytes;
        entry.text = truncateUTF8(std::move(entry.text), kFrontendLogMaxBytes);
        if (entry.truncated || lineWasTooLong) {
            entry.truncated = true;
            m_truncated = true;
        }

        m_totalByteCount += entry.text.size();
        m_entries.push_back(std::move(entry));
        while (m_entries.size() > kFrontendLogMaxEntries || m_totalByteCount > kFrontendLogMaxBytes) {
            m_totalByteCount -= m_entries.front().text.size();
            m_entries.pop_front();
            ++m_droppedEntryCount;
            m_truncated = true;
        }
    }

    FrontendLogSnapshot snapshot(std::string taskIdentifier) const
    {
        FrontendLogSnapshot result;
        result.taskId = std::move(taskIdentifier);
        result.entries.assign(m_entries.begin(), m_entries.end());
        result.droppedEntryCount = static_cast<std::uint64_t>(m_droppedEntryCount);
        result.totalByteCount = static_cast<std::uint64_t>(m_totalByteCount);
        result.truncated = m_truncated;
        return result;
    }

   private:
    std::deque<FrontendLogEntry> m_entries;
    std::size_t m_droppedEntryCount = 0;
    std::size_t m_totalByteCount = 0;
    bool m_truncated = false;
};

void validateLogSnapshot(const FrontendLogSnapshot& snapshot)
{
    if (!snapshot.hasStableIdentifier() || snapshot.entries.size() > kFrontendLogMaxEntries
        || snapshot.totalByteCount > kFrontendLogMaxBytes) {
        throw std::invalid_argument("Log snapshots require a stable identifier and bounded contents");
    }

    std::set<std::uint64_t> sequences;
    std::uint64_t totalByteCount = 0;
    for (const auto& entry : snapshot.entries) {
        if (!sequences.insert(entry.sequence).second || entry.text.size() > kFrontendLogMaxBytes) {
            throw std::invalid_argument("Log snapshots require unique sequences and bounded entries");
        }
        totalByteCount += static_cast<std::uint64_t>(entry.text.size());
    }
    if (totalByteCount != snapshot.totalByteCount) {
        throw std::invalid_argument("Log snapshots require an accurate byte count");
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

bool isKnownInstanceNotesUpdateOutcome(FrontendInstanceNotesUpdateOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendInstanceNotesUpdateOutcome::Succeeded:
        case FrontendInstanceNotesUpdateOutcome::UnknownInstance:
        case FrontendInstanceNotesUpdateOutcome::Rejected:
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

std::optional<FrontendInstanceDetailsSnapshot> executeInstanceDetails(
    const FrontendRuntimeDependencies::InstanceDetailsLoader& loader,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier)
{
    if (instanceIdentifier.empty()) {
        throw std::invalid_argument("Instance details require a stable identifier");
    }
    if (!loader) {
        return std::nullopt;
    }

    auto details = loader(dataRoot, instanceIdentifier);
    if (details.has_value()) {
        validateInstanceDetailsSnapshot(*details);
    }
    return details;
}

FrontendInstanceNotesUpdateResult executeInstanceNotesUpdate(
    const FrontendRuntimeDependencies::InstanceNotesUpdater& updater,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier,
    const std::string& notes)
{
    if (instanceIdentifier.empty()) {
        throw std::invalid_argument("Instance notes require a stable identifier");
    }
    if (!updater) {
        return {};
    }

    auto result = updater(dataRoot, instanceIdentifier, notes);
    if (!isKnownInstanceNotesUpdateOutcome(result.outcome)) {
        throw std::invalid_argument("Instance notes update returned an unknown outcome");
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

std::optional<FrontendInstanceDetailsSnapshot> FrontendFacade::instanceDetails(const std::string& instanceIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceDetails(m_runtimeDependencies.loadInstanceDetails, m_dataRoot, instanceIdentifier);
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

FrontendInstanceNotesUpdateResult FrontendFacade::updateInstanceNotes(
    const std::string& instanceIdentifier, const std::string& notes) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceNotesUpdate(m_runtimeDependencies.updateInstanceNotes, m_dataRoot, instanceIdentifier, notes);
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

std::optional<FrontendLogSnapshot> FrontendFacade::taskLogSnapshot(const std::string& taskIdentifier) const
{
    ensureRunning(m_lifecycleState);
    if (taskIdentifier.empty()) {
        throw std::invalid_argument("Log operations require a stable identifier");
    }
    if (!m_runtimeDependencies.streamTaskLogs) {
        return std::nullopt;
    }

    FrontendLogBuffer buffer;
    const bool available = m_runtimeDependencies.streamTaskLogs(
        m_dataRoot,
        taskIdentifier,
        [&](FrontendLogEntry entry) {
            entry.text = privacyFilteredLogText(std::move(entry.text), m_dataRoot);
            buffer.append(std::move(entry));
        });
    if (!available) {
        return std::nullopt;
    }

    auto snapshot = buffer.snapshot(taskIdentifier);
    validateLogSnapshot(snapshot);
    return snapshot;
}
