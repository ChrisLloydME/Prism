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

bool isKnownInstanceComponentProblemSeverity(FrontendInstanceComponentProblemSeverity severity) noexcept
{
    switch (severity) {
        case FrontendInstanceComponentProblemSeverity::None:
        case FrontendInstanceComponentProblemSeverity::Warning:
        case FrontendInstanceComponentProblemSeverity::Error:
            return true;
    }
    return false;
}

void validateInstanceComponents(const std::vector<FrontendInstanceComponentSnapshot>& components)
{
    std::set<std::string> identifiers;
    for (const auto& component : components) {
        if (!component.hasStableIdentifier() || component.name.empty()
            || !isKnownInstanceComponentProblemSeverity(component.problemSeverity)
            || (!component.canBeDisabled && !component.enabled) || !identifiers.insert(component.id).second) {
            throw std::invalid_argument("Instance components require unique identifiers and valid state");
        }
    }
}

bool isKnownInstanceResourceKind(FrontendInstanceResourceKind kind) noexcept
{
    switch (kind) {
        case FrontendInstanceResourceKind::Mods:
        case FrontendInstanceResourceKind::ResourcePacks:
        case FrontendInstanceResourceKind::ShaderPacks:
        case FrontendInstanceResourceKind::TexturePacks:
        case FrontendInstanceResourceKind::DataPacks:
            return true;
    }
    return false;
}

bool isKnownInstanceResourceAction(FrontendInstanceResourceAction action) noexcept
{
    switch (action) {
        case FrontendInstanceResourceAction::Enable:
        case FrontendInstanceResourceAction::Disable:
        case FrontendInstanceResourceAction::Delete:
        case FrontendInstanceResourceAction::Import:
        case FrontendInstanceResourceAction::Reveal:
            return true;
    }
    return false;
}

bool isKnownInstanceResourceMutationOutcome(FrontendInstanceResourceMutationOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendInstanceResourceMutationOutcome::Succeeded:
        case FrontendInstanceResourceMutationOutcome::UnknownInstance:
        case FrontendInstanceResourceMutationOutcome::UnknownResource:
        case FrontendInstanceResourceMutationOutcome::Rejected:
        case FrontendInstanceResourceMutationOutcome::Failed:
            return true;
    }
    return false;
}

void validateInstanceResources(const std::vector<FrontendInstanceResourceSnapshot>& resources)
{
    std::set<std::string> identifiers;
    for (const auto& resource : resources) {
        if (!resource.hasStableIdentifier() || resource.name.empty() || resource.fileName.empty()
            || !isKnownInstanceResourceKind(resource.kind) || (resource.isDirectory && resource.canBeToggled)
            || !identifiers.insert(resource.id).second) {
            throw std::invalid_argument("Instance resources require unique identifiers and valid state");
        }
    }
}

void validateInstanceResourceRequest(
    FrontendInstanceResourceKind kind,
    const FrontendInstanceResourceMutationRequest& request)
{
    if (!isKnownInstanceResourceKind(kind) || !isKnownInstanceResourceAction(request.action)
        || request.resourceIdentifier.empty()) {
        throw std::invalid_argument("Instance resource requests require a known kind, action, and identifier");
    }
    if (request.action == FrontendInstanceResourceAction::Delete && !request.confirmed) {
        throw std::invalid_argument("Deleting an instance resource requires explicit confirmation");
    }
    if (request.action == FrontendInstanceResourceAction::Import
        && (request.sourcePath.empty() || !request.sourcePath.is_absolute())) {
        throw std::invalid_argument("Importing an instance resource requires an absolute source path");
    }
    if (request.action != FrontendInstanceResourceAction::Import && !request.sourcePath.empty()) {
        throw std::invalid_argument("Only import requests may carry a source path");
    }
}

void validateInstanceResourceMutationResult(
    FrontendInstanceResourceKind kind,
    const FrontendInstanceResourceMutationRequest& request,
    const FrontendInstanceResourceMutationResult& result,
    const std::string& instanceIdentifier)
{
    if (!isKnownInstanceResourceKind(result.kind) || !isKnownInstanceResourceAction(result.action)
        || !isKnownInstanceResourceMutationOutcome(result.outcome) || result.kind != kind
        || result.action != request.action || result.instanceIdentifier != instanceIdentifier
        || result.resourceIdentifier != request.resourceIdentifier) {
        throw std::invalid_argument("Instance resource mutation returned an invalid confirmed result");
    }
}

bool isKnownInstanceDetailKind(FrontendInstanceDetailKind kind) noexcept
{
    switch (kind) {
        case FrontendInstanceDetailKind::Worlds:
        case FrontendInstanceDetailKind::Servers:
        case FrontendInstanceDetailKind::Screenshots:
        case FrontendInstanceDetailKind::Logs:
            return true;
    }
    return false;
}

bool isKnownInstanceDetailAction(FrontendInstanceDetailAction action) noexcept
{
    switch (action) {
        case FrontendInstanceDetailAction::Add:
        case FrontendInstanceDetailAction::Update:
        case FrontendInstanceDetailAction::Delete:
        case FrontendInstanceDetailAction::MoveUp:
        case FrontendInstanceDetailAction::MoveDown:
        case FrontendInstanceDetailAction::Import:
        case FrontendInstanceDetailAction::Copy:
        case FrontendInstanceDetailAction::Rename:
        case FrontendInstanceDetailAction::Reveal:
        case FrontendInstanceDetailAction::ResetIcon:
        case FrontendInstanceDetailAction::Join:
        case FrontendInstanceDetailAction::Refresh:
        case FrontendInstanceDetailAction::Open:
        case FrontendInstanceDetailAction::CopyImage:
        case FrontendInstanceDetailAction::CopyFiles:
            return true;
    }
    return false;
}

bool isKnownInstanceDetailMutationOutcome(FrontendInstanceDetailMutationOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendInstanceDetailMutationOutcome::Succeeded:
        case FrontendInstanceDetailMutationOutcome::UnknownInstance:
        case FrontendInstanceDetailMutationOutcome::UnknownItem:
        case FrontendInstanceDetailMutationOutcome::Rejected:
        case FrontendInstanceDetailMutationOutcome::Failed:
            return true;
    }
    return false;
}

bool isKnownServerResourcePolicy(FrontendServerResourcePolicy policy) noexcept
{
    switch (policy) {
        case FrontendServerResourcePolicy::Ask:
        case FrontendServerResourcePolicy::Always:
        case FrontendServerResourcePolicy::Never:
            return true;
    }
    return false;
}

bool isKnownServerStatus(FrontendServerStatus status) noexcept
{
    switch (status) {
        case FrontendServerStatus::Unknown:
        case FrontendServerStatus::Online:
        case FrontendServerStatus::Offline:
        case FrontendServerStatus::Failed:
            return true;
    }
    return false;
}

void validateWorlds(const std::vector<FrontendInstanceWorldSnapshot>& worlds)
{
    std::set<std::string> identifiers;
    for (const auto& world : worlds) {
        if (!world.hasStableIdentifier() || world.name.empty() || world.folderName.empty()
            || !identifiers.insert(world.id).second) {
            throw std::invalid_argument("World snapshots require unique identifiers, names, and folders");
        }
    }
}

void validateServers(const std::vector<FrontendInstanceServerSnapshot>& servers)
{
    std::set<std::string> identifiers;
    for (const auto& server : servers) {
        if (!server.hasStableIdentifier() || server.name.empty() || server.address.empty()
            || !isKnownServerResourcePolicy(server.resourcePolicy) || !isKnownServerStatus(server.status)
            || server.onlinePlayers < -1 || !identifiers.insert(server.id).second) {
            throw std::invalid_argument("Server snapshots require unique identifiers and valid status data");
        }
    }
}

void validateScreenshots(const std::vector<FrontendInstanceScreenshotSnapshot>& screenshots)
{
    std::set<std::string> identifiers;
    for (const auto& screenshot : screenshots) {
        if (!screenshot.hasStableIdentifier() || screenshot.fileName.empty() || screenshot.displayName.empty()
            || !identifiers.insert(screenshot.id).second) {
            throw std::invalid_argument("Screenshot snapshots require unique identifiers and file names");
        }
    }
}

void validateLogFiles(const std::vector<FrontendInstanceLogFileSnapshot>& logs)
{
    std::set<std::string> identifiers;
    for (const auto& log : logs) {
        if (!log.hasStableIdentifier() || log.fileName.empty() || log.displayName.empty()
            || !identifiers.insert(log.id).second) {
            throw std::invalid_argument("Log-file snapshots require unique identifiers and file names");
        }
    }
}

void validateInstanceDetailRequest(
    const std::string& instanceIdentifier,
    const FrontendInstanceDetailMutationRequest& request)
{
    if (instanceIdentifier.empty() || !isKnownInstanceDetailKind(request.kind)
        || !isKnownInstanceDetailAction(request.action)) {
        throw std::invalid_argument("Instance detail requests require a stable identifier and known kind/action");
    }

    const bool actionNeedsItem = request.action != FrontendInstanceDetailAction::Add
        && request.action != FrontendInstanceDetailAction::Refresh;
    if (actionNeedsItem && request.itemIdentifier.empty()) {
        throw std::invalid_argument("Instance detail requests require an item identifier");
    }
    if (request.action == FrontendInstanceDetailAction::Delete && !request.confirmed) {
        throw std::invalid_argument("Deleting instance detail data requires explicit confirmation");
    }
    if (request.action == FrontendInstanceDetailAction::Import
        && (request.kind != FrontendInstanceDetailKind::Worlds || request.sourcePath.empty()
            || !request.sourcePath.is_absolute())) {
        throw std::invalid_argument("World import requires an absolute source path");
    }
    if (request.action != FrontendInstanceDetailAction::Import && !request.sourcePath.empty()) {
        throw std::invalid_argument("Only world import requests may carry a source path");
    }
    if ((request.action == FrontendInstanceDetailAction::Copy || request.action == FrontendInstanceDetailAction::Rename)
        && request.targetName.empty()) {
        throw std::invalid_argument("Copy and rename requests require a target name");
    }
    if (request.action == FrontendInstanceDetailAction::Update
        && (request.kind != FrontendInstanceDetailKind::Servers || request.name.empty() || request.address.empty()
            || !isKnownServerResourcePolicy(request.resourcePolicy))) {
        throw std::invalid_argument("Server updates require name, address, and a known resource policy");
    }
    if (request.action == FrontendInstanceDetailAction::Add
        && (request.kind != FrontendInstanceDetailKind::Servers || request.name.empty() || request.address.empty()
            || !isKnownServerResourcePolicy(request.resourcePolicy))) {
        throw std::invalid_argument("Adding a server requires name, address, and a known resource policy");
    }
    if ((request.action == FrontendInstanceDetailAction::MoveUp || request.action == FrontendInstanceDetailAction::MoveDown)
        && (request.kind != FrontendInstanceDetailKind::Servers || request.position < 0)) {
        throw std::invalid_argument("Server move requests require a non-negative position");
    }
    if (request.action == FrontendInstanceDetailAction::CopyImage
        && request.kind != FrontendInstanceDetailKind::Screenshots) {
        throw std::invalid_argument("CopyImage is only valid for screenshots");
    }
    if (request.action == FrontendInstanceDetailAction::CopyFiles
        && request.kind != FrontendInstanceDetailKind::Screenshots) {
        throw std::invalid_argument("CopyFiles is only valid for screenshots");
    }
    if (request.kind == FrontendInstanceDetailKind::Logs
        && request.action != FrontendInstanceDetailAction::Delete
        && request.action != FrontendInstanceDetailAction::Reveal
        && request.action != FrontendInstanceDetailAction::Open
        && request.action != FrontendInstanceDetailAction::Refresh) {
        throw std::invalid_argument("Log requests only support open, reveal, refresh, and confirmed delete");
    }
}

void validateInstanceDetailMutationResult(
    const FrontendInstanceDetailMutationRequest& request,
    const FrontendInstanceDetailMutationResult& result,
    const std::string& instanceIdentifier)
{
    if (!isKnownInstanceDetailKind(result.kind) || !isKnownInstanceDetailAction(result.action)
        || !isKnownInstanceDetailMutationOutcome(result.outcome) || result.kind != request.kind
        || result.action != request.action || result.instanceIdentifier != instanceIdentifier
        || (!request.itemIdentifier.empty() && result.itemIdentifier != request.itemIdentifier)) {
        throw std::invalid_argument("Instance detail mutation returned an invalid confirmed result");
    }
    if (request.itemIdentifier.empty() && result.itemIdentifier.empty()
        && request.action == FrontendInstanceDetailAction::Add) {
        throw std::invalid_argument("Adding a server must return its stable identifier");
    }
}

bool isKnownInstanceJoinTarget(FrontendInstanceJoinTarget target) noexcept
{
    switch (target) {
        case FrontendInstanceJoinTarget::None:
        case FrontendInstanceJoinTarget::Server:
        case FrontendInstanceJoinTarget::World:
            return true;
    }
    return false;
}

void validateInstanceSettingsSnapshot(const FrontendInstanceSettingsSnapshot& settings)
{
    if (!settings.hasStableIdentifier() || !isKnownInstanceJoinTarget(settings.joinTarget)
        || settings.windowWidth < 1 || settings.windowWidth > 65536 || settings.windowHeight < 1
        || settings.windowHeight > 65536 || settings.minMemoryMiB < 8 || settings.minMemoryMiB > 1048576
        || settings.maxMemoryMiB < 8 || settings.maxMemoryMiB > 1048576 || settings.minMemoryMiB > settings.maxMemoryMiB
        || settings.permGenMiB < 4 || settings.permGenMiB > 1048576) {
        throw std::invalid_argument("Instance settings require valid dimensions, memory, and join values");
    }

    std::set<std::string> loaders;
    for (const auto& loader : settings.modDownloadLoaders) {
        if (loader.empty() || !loaders.insert(loader).second) {
            throw std::invalid_argument("Instance settings require unique non-empty mod loaders");
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

void validateInstanceLogSnapshot(const FrontendInstanceLogSnapshot& snapshot)
{
    if (snapshot.instanceIdentifier.empty() || snapshot.logIdentifier.empty()
        || snapshot.entries.size() > kFrontendLogMaxEntries || snapshot.totalByteCount > kFrontendLogMaxBytes) {
        throw std::invalid_argument("Instance log snapshots require stable identifiers and bounded contents");
    }

    std::set<std::uint64_t> sequences;
    std::uint64_t totalByteCount = 0;
    bool containsTruncatedEntry = false;
    for (const auto& entry : snapshot.entries) {
        if (!sequences.insert(entry.sequence).second || entry.text.size() > kFrontendLogMaxBytes) {
            throw std::invalid_argument("Instance log snapshots require unique sequences and bounded entries");
        }
        totalByteCount += static_cast<std::uint64_t>(entry.text.size());
        containsTruncatedEntry = containsTruncatedEntry || entry.truncated;
    }
    if (totalByteCount != snapshot.totalByteCount
        || (!snapshot.truncated && (snapshot.droppedEntryCount > 0 || containsTruncatedEntry))) {
        throw std::invalid_argument("Instance log snapshots require accurate truncation metadata");
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

std::optional<std::vector<FrontendInstanceComponentSnapshot>> executeInstanceComponents(
    const FrontendRuntimeDependencies::InstanceComponentsLoader& loader,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier)
{
    if (instanceIdentifier.empty()) {
        throw std::invalid_argument("Instance components require a stable identifier");
    }
    if (!loader) {
        return std::nullopt;
    }

    auto components = loader(dataRoot, instanceIdentifier);
    if (components.has_value()) {
        validateInstanceComponents(*components);
    }
    return components;
}

std::optional<std::vector<FrontendInstanceResourceSnapshot>> executeInstanceResources(
    const FrontendRuntimeDependencies::InstanceResourcesLoader& loader,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier,
    FrontendInstanceResourceKind kind)
{
    if (instanceIdentifier.empty() || !isKnownInstanceResourceKind(kind)) {
        throw std::invalid_argument("Instance resources require a stable identifier and known kind");
    }
    if (!loader) {
        return std::nullopt;
    }

    auto resources = loader(dataRoot, instanceIdentifier, kind);
    if (resources.has_value()) {
        validateInstanceResources(*resources);
    }
    return resources;
}

FrontendInstanceResourceMutationResult executeInstanceResourceMutation(
    const FrontendRuntimeDependencies::InstanceResourceMutator& mutator,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier,
    FrontendInstanceResourceKind kind,
    const FrontendInstanceResourceMutationRequest& request)
{
    if (instanceIdentifier.empty()) {
        throw std::invalid_argument("Instance resource mutations require a stable instance identifier");
    }
    validateInstanceResourceRequest(kind, request);
    if (!mutator) {
        FrontendInstanceResourceMutationResult rejected;
        rejected.kind = kind;
        rejected.action = request.action;
        rejected.instanceIdentifier = instanceIdentifier;
        rejected.resourceIdentifier = request.resourceIdentifier;
        rejected.localizationKey = "instance.resource.unavailable";
        rejected.diagnosticText = "Instance resource mutation adapter is unavailable";
        return rejected;
    }

    auto result = mutator(dataRoot, instanceIdentifier, kind, request);
    validateInstanceResourceMutationResult(kind, request, result, instanceIdentifier);
    return result;
}

std::optional<std::vector<FrontendInstanceWorldSnapshot>> executeInstanceWorlds(
    const FrontendRuntimeDependencies::InstanceWorldsLoader& loader,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier)
{
    if (instanceIdentifier.empty()) {
        throw std::invalid_argument("World operations require a stable instance identifier");
    }
    if (!loader) {
        return std::nullopt;
    }
    auto worlds = loader(dataRoot, instanceIdentifier);
    if (worlds.has_value()) {
        validateWorlds(*worlds);
    }
    return worlds;
}

std::optional<std::vector<FrontendInstanceServerSnapshot>> executeInstanceServers(
    const FrontendRuntimeDependencies::InstanceServersLoader& loader,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier)
{
    if (instanceIdentifier.empty()) {
        throw std::invalid_argument("Server operations require a stable instance identifier");
    }
    if (!loader) {
        return std::nullopt;
    }
    auto servers = loader(dataRoot, instanceIdentifier);
    if (servers.has_value()) {
        validateServers(*servers);
    }
    return servers;
}

std::optional<std::vector<FrontendInstanceScreenshotSnapshot>> executeInstanceScreenshots(
    const FrontendRuntimeDependencies::InstanceScreenshotsLoader& loader,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier)
{
    if (instanceIdentifier.empty()) {
        throw std::invalid_argument("Screenshot operations require a stable instance identifier");
    }
    if (!loader) {
        return std::nullopt;
    }
    auto screenshots = loader(dataRoot, instanceIdentifier);
    if (screenshots.has_value()) {
        validateScreenshots(*screenshots);
    }
    return screenshots;
}

std::optional<std::vector<FrontendInstanceLogFileSnapshot>> executeInstanceLogFiles(
    const FrontendRuntimeDependencies::InstanceLogFilesLoader& loader,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier)
{
    if (instanceIdentifier.empty()) {
        throw std::invalid_argument("Log operations require a stable instance identifier");
    }
    if (!loader) {
        return std::nullopt;
    }
    auto logs = loader(dataRoot, instanceIdentifier);
    if (logs.has_value()) {
        validateLogFiles(*logs);
    }
    return logs;
}

std::optional<FrontendInstanceLogSnapshot> executeInstanceLog(
    const FrontendRuntimeDependencies::InstanceLogLoader& loader,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier,
    const std::string& logIdentifier)
{
    if (instanceIdentifier.empty() || logIdentifier.empty()) {
        throw std::invalid_argument("Instance log content requires stable identifiers");
    }
    if (!loader) {
        return std::nullopt;
    }
    auto snapshot = loader(dataRoot, instanceIdentifier, logIdentifier);
    if (snapshot.has_value()) {
        validateInstanceLogSnapshot(*snapshot);
        if (snapshot->instanceIdentifier != instanceIdentifier || snapshot->logIdentifier != logIdentifier) {
            throw std::invalid_argument("Instance log content identifiers must match the request");
        }
    }
    return snapshot;
}

FrontendInstanceDetailMutationResult executeInstanceDetailMutation(
    const FrontendRuntimeDependencies::InstanceDetailMutator& mutator,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier,
    const FrontendInstanceDetailMutationRequest& request)
{
    validateInstanceDetailRequest(instanceIdentifier, request);
    if (!mutator) {
        FrontendInstanceDetailMutationResult rejected;
        rejected.kind = request.kind;
        rejected.action = request.action;
        rejected.instanceIdentifier = instanceIdentifier;
        rejected.itemIdentifier = request.itemIdentifier;
        rejected.localizationKey = "instance.detail.unavailable";
        rejected.diagnosticText = "Instance detail mutation adapter is unavailable";
        return rejected;
    }

    auto result = mutator(dataRoot, instanceIdentifier, request);
    validateInstanceDetailMutationResult(request, result, instanceIdentifier);
    return result;
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

std::optional<FrontendInstanceSettingsSnapshot> executeInstanceSettings(
    const FrontendRuntimeDependencies::InstanceSettingsLoader& loader,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier)
{
    if (instanceIdentifier.empty()) {
        throw std::invalid_argument("Instance settings require a stable identifier");
    }
    if (!loader) {
        return std::nullopt;
    }

    auto settings = loader(dataRoot, instanceIdentifier);
    if (settings.has_value()) {
        validateInstanceSettingsSnapshot(*settings);
        if (settings->id != instanceIdentifier) {
            throw std::invalid_argument("Instance settings identifier must match the requested instance");
        }
    }
    return settings;
}

FrontendInstanceSettingsUpdateResult executeInstanceSettingsUpdate(
    const FrontendRuntimeDependencies::InstanceSettingsUpdater& updater,
    const std::filesystem::path& dataRoot,
    const std::string& instanceIdentifier,
    const FrontendInstanceSettingsSnapshot& settings)
{
    if (instanceIdentifier.empty() || !settings.hasStableIdentifier() || settings.id != instanceIdentifier) {
        throw std::invalid_argument("Instance settings updates require matching stable identifiers");
    }
    validateInstanceSettingsSnapshot(settings);
    if (!updater) {
        return {};
    }

    auto result = updater(dataRoot, instanceIdentifier, settings);
    switch (result.outcome) {
        case FrontendInstanceSettingsUpdateOutcome::Succeeded:
            if (!result.settings.has_value()) {
                throw std::invalid_argument("Successful instance settings updates require confirmed settings");
            }
            validateInstanceSettingsSnapshot(*result.settings);
            if (result.settings->id != instanceIdentifier) {
                throw std::invalid_argument("Confirmed instance settings identifier must match the request");
            }
            break;
        case FrontendInstanceSettingsUpdateOutcome::UnknownInstance:
        case FrontendInstanceSettingsUpdateOutcome::Rejected:
            if (result.settings.has_value()) {
                validateInstanceSettingsSnapshot(*result.settings);
            }
            break;
        default:
            throw std::invalid_argument("Instance settings update returned an unknown outcome");
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

std::optional<std::vector<FrontendInstanceComponentSnapshot>> FrontendFacade::instanceComponents(
    const std::string& instanceIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceComponents(m_runtimeDependencies.loadInstanceComponents, m_dataRoot, instanceIdentifier);
}

std::optional<std::vector<FrontendInstanceResourceSnapshot>> FrontendFacade::instanceResources(
    const std::string& instanceIdentifier, FrontendInstanceResourceKind kind) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceResources(m_runtimeDependencies.loadInstanceResources, m_dataRoot, instanceIdentifier, kind);
}

FrontendInstanceResourceMutationResult FrontendFacade::mutateInstanceResource(
    const std::string& instanceIdentifier,
    FrontendInstanceResourceKind kind,
    const FrontendInstanceResourceMutationRequest& request) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceResourceMutation(
        m_runtimeDependencies.mutateInstanceResource, m_dataRoot, instanceIdentifier, kind, request);
}

std::optional<std::vector<FrontendInstanceWorldSnapshot>> FrontendFacade::instanceWorlds(
    const std::string& instanceIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceWorlds(m_runtimeDependencies.loadInstanceWorlds, m_dataRoot, instanceIdentifier);
}

std::optional<std::vector<FrontendInstanceServerSnapshot>> FrontendFacade::instanceServers(
    const std::string& instanceIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceServers(m_runtimeDependencies.loadInstanceServers, m_dataRoot, instanceIdentifier);
}

std::optional<std::vector<FrontendInstanceScreenshotSnapshot>> FrontendFacade::instanceScreenshots(
    const std::string& instanceIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceScreenshots(m_runtimeDependencies.loadInstanceScreenshots, m_dataRoot, instanceIdentifier);
}

std::optional<std::vector<FrontendInstanceLogFileSnapshot>> FrontendFacade::instanceLogFiles(
    const std::string& instanceIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceLogFiles(m_runtimeDependencies.loadInstanceLogFiles, m_dataRoot, instanceIdentifier);
}

std::optional<FrontendInstanceLogSnapshot> FrontendFacade::instanceLog(
    const std::string& instanceIdentifier, const std::string& logIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceLog(m_runtimeDependencies.loadInstanceLog, m_dataRoot, instanceIdentifier, logIdentifier);
}

FrontendInstanceDetailMutationResult FrontendFacade::mutateInstanceDetail(
    const std::string& instanceIdentifier, const FrontendInstanceDetailMutationRequest& request) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceDetailMutation(m_runtimeDependencies.mutateInstanceDetail, m_dataRoot, instanceIdentifier, request);
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

std::optional<FrontendInstanceSettingsSnapshot> FrontendFacade::instanceSettings(const std::string& instanceIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceSettings(m_runtimeDependencies.loadInstanceSettings, m_dataRoot, instanceIdentifier);
}

FrontendInstanceSettingsUpdateResult FrontendFacade::updateInstanceSettings(
    const std::string& instanceIdentifier, const FrontendInstanceSettingsSnapshot& settings) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceSettingsUpdate(
        m_runtimeDependencies.updateInstanceSettings, m_dataRoot, instanceIdentifier, settings);
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
