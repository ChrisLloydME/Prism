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

bool isKnownGlobalSettingsCatFit(const std::string& catFit) noexcept
{
    return catFit == "fit" || catFit == "fill" || catFit == "strech";
}

void validateGlobalSettingsSnapshot(const FrontendGlobalSettingsSnapshot& settings)
{
    if (settings.instanceDirectory.empty() || !settings.instanceDirectory.is_absolute()
        || !isKnownGlobalSettingsCatFit(settings.catFit) || settings.catOpacity < 0 || settings.catOpacity > 100
        || settings.numberOfConcurrentTasks < 1 || settings.numberOfConcurrentDownloads < 1
        || settings.numberOfManualRetries < 0 || settings.requestTimeoutSeconds < 0
        || settings.consoleFontSize < 5 || settings.consoleFontSize > 16
        || settings.consoleMaxLines < 10000 || settings.consoleMaxLines > 1000000) {
        throw std::invalid_argument("Global settings require valid directory, enum, and numeric values");
    }
}

bool isKnownJavaInstallationValidity(FrontendJavaInstallationValidity validity) noexcept
{
    switch (validity) {
        case FrontendJavaInstallationValidity::Valid:
        case FrontendJavaInstallationValidity::Incompatible:
        case FrontendJavaInstallationValidity::Unavailable:
            return true;
    }
    return false;
}

void validateJavaInstallationSnapshot(const FrontendJavaInstallationSnapshot& installation)
{
    if (!installation.hasStableIdentifier() || installation.executablePath.empty()
        || !isKnownJavaInstallationValidity(installation.validity)) {
        throw std::invalid_argument("Java installations require stable identifiers and executable paths");
    }
    if (installation.validity == FrontendJavaInstallationValidity::Valid
        && (installation.version.empty() || installation.architecture.empty())) {
        throw std::invalid_argument("Valid Java installations require version and architecture labels");
    }
}

bool isKnownJavaDiscoveryOutcome(FrontendJavaDiscoveryOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendJavaDiscoveryOutcome::Succeeded:
        case FrontendJavaDiscoveryOutcome::Failed:
        case FrontendJavaDiscoveryOutcome::Cancelled:
        case FrontendJavaDiscoveryOutcome::Rejected:
            return true;
    }
    return false;
}

void validateJavaDiscoveryResult(const FrontendJavaDiscoveryResult& result)
{
    if (!isKnownJavaDiscoveryOutcome(result.outcome)) {
        throw std::invalid_argument("Java discovery returned an unknown outcome");
    }

    std::set<std::string> identifiers;
    for (const auto& installation : result.installations) {
        validateJavaInstallationSnapshot(installation);
        if (!identifiers.insert(installation.id).second) {
            throw std::invalid_argument("Java discovery requires unique installation identifiers");
        }
    }

    if (result.outcome != FrontendJavaDiscoveryOutcome::Succeeded && result.localizationKey.empty()) {
        throw std::invalid_argument("Failed Java discovery requires a localization key");
    }
}

bool isKnownJavaSelectionOutcome(FrontendJavaSelectionOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendJavaSelectionOutcome::Succeeded:
        case FrontendJavaSelectionOutcome::UnknownInstallation:
        case FrontendJavaSelectionOutcome::Rejected:
            return true;
    }
    return false;
}

void validateJavaSelectionResult(
    const FrontendJavaSelectionResult& result,
    const std::string& requestedIdentifier)
{
    if (!isKnownJavaSelectionOutcome(result.outcome)) {
        throw std::invalid_argument("Java selection returned an unknown outcome");
    }
    if (result.outcome == FrontendJavaSelectionOutcome::Succeeded) {
        if (!result.installation.has_value() || result.installation->id != requestedIdentifier
            || result.installation->validity != FrontendJavaInstallationValidity::Valid) {
            throw std::invalid_argument("Successful Java selection requires the requested valid installation");
        }
        validateJavaInstallationSnapshot(*result.installation);
    } else {
        if (result.localizationKey.empty()) {
            throw std::invalid_argument("Rejected Java selection requires a localization key");
        }
        if (result.installation.has_value()) {
            validateJavaInstallationSnapshot(*result.installation);
        }
    }
}

bool isKnownAccountType(FrontendAccountType type) noexcept
{
    switch (type) {
        case FrontendAccountType::Microsoft:
        case FrontendAccountType::Offline:
            return true;
    }
    return false;
}

bool isKnownAccountState(FrontendAccountState state) noexcept
{
    switch (state) {
        case FrontendAccountState::Unchecked:
        case FrontendAccountState::Offline:
        case FrontendAccountState::Working:
        case FrontendAccountState::Online:
        case FrontendAccountState::Disabled:
        case FrontendAccountState::Errored:
        case FrontendAccountState::Expired:
        case FrontendAccountState::Gone:
            return true;
    }
    return false;
}

void validateAccountSnapshot(const FrontendAccountSnapshot& account)
{
    if (!account.hasStableIdentifier() || account.displayName.empty() || !isKnownAccountType(account.type)
        || !isKnownAccountState(account.state)) {
        throw std::invalid_argument("Account snapshots require stable identifiers, names, and known states");
    }
}

bool isKnownAccountSnapshotOutcome(FrontendAccountSnapshotOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendAccountSnapshotOutcome::Succeeded:
        case FrontendAccountSnapshotOutcome::Failed:
        case FrontendAccountSnapshotOutcome::Cancelled:
        case FrontendAccountSnapshotOutcome::Rejected:
            return true;
    }
    return false;
}

void validateAccountSnapshotResult(const FrontendAccountSnapshotResult& result)
{
    if (!isKnownAccountSnapshotOutcome(result.outcome)) {
        throw std::invalid_argument("Account snapshots returned an unknown outcome");
    }

    std::set<std::string> identifiers;
    for (const auto& account : result.accounts) {
        validateAccountSnapshot(account);
        if (!identifiers.insert(account.id).second) {
            throw std::invalid_argument("Account snapshots require unique stable identifiers");
        }
    }

    if (result.activeAccountIdentifier.has_value()) {
        if (result.activeAccountIdentifier->empty()
            || identifiers.find(*result.activeAccountIdentifier) == identifiers.end()) {
            throw std::invalid_argument("Active account must identify one returned account");
        }
    }

    if (result.outcome != FrontendAccountSnapshotOutcome::Succeeded && result.localizationKey.empty()) {
        throw std::invalid_argument("Failed account snapshots require a localization key");
    }
}

bool isKnownAccountSelectionOutcome(FrontendAccountSelectionOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendAccountSelectionOutcome::Succeeded:
        case FrontendAccountSelectionOutcome::UnknownAccount:
        case FrontendAccountSelectionOutcome::Rejected:
            return true;
    }
    return false;
}

void validateAccountSelectionResult(
    const FrontendAccountSelectionResult& result,
    const std::optional<std::string>& requestedIdentifier)
{
    if (!isKnownAccountSelectionOutcome(result.outcome)) {
        throw std::invalid_argument("Account selection returned an unknown outcome");
    }

    if (result.outcome == FrontendAccountSelectionOutcome::Succeeded) {
        if (requestedIdentifier.has_value()) {
            if (!result.account.has_value() || result.account->id != *requestedIdentifier
                || !result.account->canBeSelected || result.account->isBusy) {
                throw std::invalid_argument("Successful account selection requires the requested selectable account");
            }
            validateAccountSnapshot(*result.account);
        } else if (result.account.has_value()) {
            throw std::invalid_argument("Clearing the active account cannot return an account");
        }
    } else {
        if (result.localizationKey.empty()) {
            throw std::invalid_argument("Rejected account selection requires a localization key");
        }
        if (result.account.has_value()) {
            validateAccountSnapshot(*result.account);
        }
    }
}

bool isKnownAccountAuthenticationAction(FrontendAccountAuthenticationAction action) noexcept
{
    switch (action) {
        case FrontendAccountAuthenticationAction::Login:
        case FrontendAccountAuthenticationAction::Refresh:
            return true;
    }
    return false;
}

bool isKnownAccountAuthenticationPhase(FrontendAccountAuthenticationPhase phase) noexcept
{
    switch (phase) {
        case FrontendAccountAuthenticationPhase::Preparing:
        case FrontendAccountAuthenticationPhase::AwaitingUser:
        case FrontendAccountAuthenticationPhase::Authenticating:
        case FrontendAccountAuthenticationPhase::Succeeded:
        case FrontendAccountAuthenticationPhase::Failed:
        case FrontendAccountAuthenticationPhase::Cancelled:
            return true;
    }
    return false;
}

bool isKnownAccountAuthenticationOutcome(FrontendAccountAuthenticationOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendAccountAuthenticationOutcome::InProgress:
        case FrontendAccountAuthenticationOutcome::Succeeded:
        case FrontendAccountAuthenticationOutcome::Failed:
        case FrontendAccountAuthenticationOutcome::Cancelled:
        case FrontendAccountAuthenticationOutcome::Rejected:
            return true;
    }
    return false;
}

void validateAccountAuthenticationRequest(const FrontendAccountAuthenticationRequest& request)
{
    if (request.accountIdentifier.empty() || !isKnownAccountAuthenticationAction(request.action)) {
        throw std::invalid_argument("Account authentication requires a stable identifier and known action");
    }
}

void validateAccountAuthenticationProgress(
    const FrontendAccountAuthenticationProgress& progress,
    const FrontendAccountAuthenticationRequest& request)
{
    if (progress.accountIdentifier != request.accountIdentifier || progress.action != request.action
        || !isKnownAccountAuthenticationPhase(progress.phase) || !isKnownAccountAuthenticationOutcome(progress.outcome)
        || progress.providerLabel.empty() || progress.localizationKey.empty() || progress.expiresInSeconds < 0) {
        throw std::invalid_argument("Account authentication progress has invalid identity or metadata");
    }

    const bool awaitingUser = progress.phase == FrontendAccountAuthenticationPhase::AwaitingUser;
    if (awaitingUser) {
        if (progress.outcome != FrontendAccountAuthenticationOutcome::InProgress || !progress.requiresUserAction
            || progress.verificationURL.empty() || !progress.canCancel) {
            throw std::invalid_argument("Device-code progress requires a cancellable user-action state");
        }
    } else if (progress.requiresUserAction || !progress.verificationURL.empty()) {
        throw std::invalid_argument("Verification metadata is only valid while awaiting user action");
    }

    switch (progress.phase) {
        case FrontendAccountAuthenticationPhase::Preparing:
        case FrontendAccountAuthenticationPhase::Authenticating:
            if (progress.outcome != FrontendAccountAuthenticationOutcome::InProgress) {
                throw std::invalid_argument("Non-terminal authentication phases require an in-progress outcome");
            }
            break;
        case FrontendAccountAuthenticationPhase::Succeeded:
            if (progress.outcome != FrontendAccountAuthenticationOutcome::Succeeded || progress.canCancel
                || progress.retryable) {
                throw std::invalid_argument("Successful authentication progress has invalid terminal flags");
            }
            break;
        case FrontendAccountAuthenticationPhase::Failed:
            if (progress.outcome != FrontendAccountAuthenticationOutcome::Failed || progress.canCancel) {
                throw std::invalid_argument("Failed authentication progress has invalid terminal flags");
            }
            break;
        case FrontendAccountAuthenticationPhase::Cancelled:
            if (progress.outcome != FrontendAccountAuthenticationOutcome::Cancelled || progress.canCancel
                || progress.retryable) {
                throw std::invalid_argument("Cancelled authentication progress has invalid terminal flags");
            }
            break;
        case FrontendAccountAuthenticationPhase::AwaitingUser:
            break;
    }
}

void validateAccountAuthenticationResult(
    const FrontendAccountAuthenticationResult& result,
    const FrontendAccountAuthenticationRequest& request)
{
    if (!isKnownAccountAuthenticationOutcome(result.outcome) || result.outcome == FrontendAccountAuthenticationOutcome::InProgress
        || result.localizationKey.empty()) {
        throw std::invalid_argument("Account authentication result requires a terminal outcome and localization key");
    }

    if (result.account.has_value()) {
        validateAccountSnapshot(*result.account);
        if (result.account->id != request.accountIdentifier) {
            throw std::invalid_argument("Account authentication result must identify the requested account");
        }
    }

    if (result.outcome == FrontendAccountAuthenticationOutcome::Succeeded) {
        if (!result.account.has_value() || result.account->type != FrontendAccountType::Microsoft
            || result.account->state != FrontendAccountState::Online || result.account->isBusy
            || !result.account->canBeSelected) {
            throw std::invalid_argument("Successful account authentication requires an online selectable account");
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

std::optional<FrontendGlobalSettingsSnapshot> executeGlobalSettings(
    const FrontendRuntimeDependencies::GlobalSettingsLoader& loader,
    const std::filesystem::path& dataRoot)
{
    if (!loader) {
        return std::nullopt;
    }

    auto settings = loader(dataRoot);
    if (settings.has_value()) {
        validateGlobalSettingsSnapshot(*settings);
    }
    return settings;
}

FrontendGlobalSettingsUpdateResult executeGlobalSettingsUpdate(
    const FrontendRuntimeDependencies::GlobalSettingsUpdater& updater,
    const std::filesystem::path& dataRoot,
    const FrontendGlobalSettingsSnapshot& settings)
{
    validateGlobalSettingsSnapshot(settings);
    if (!updater) {
        return {};
    }

    auto result = updater(dataRoot, settings);
    switch (result.outcome) {
        case FrontendGlobalSettingsUpdateOutcome::Succeeded:
            if (!result.settings.has_value()) {
                throw std::invalid_argument("Successful global settings updates require confirmed settings");
            }
            validateGlobalSettingsSnapshot(*result.settings);
            break;
        case FrontendGlobalSettingsUpdateOutcome::Rejected:
            if (result.settings.has_value()) {
                validateGlobalSettingsSnapshot(*result.settings);
            }
            break;
        default:
            throw std::invalid_argument("Global settings update returned an unknown outcome");
    }
    return result;
}

FrontendJavaDiscoveryResult executeJavaDiscovery(
    const FrontendRuntimeDependencies::JavaDiscoveryLoader& loader,
    const std::filesystem::path& dataRoot)
{
    if (!loader) {
        return FrontendJavaDiscoveryResult{
            FrontendJavaDiscoveryOutcome::Rejected,
            {},
            "java.discovery.unavailable",
            "Java discovery is unavailable.",
            true,
        };
    }

    auto result = loader(dataRoot);
    validateJavaDiscoveryResult(result);
    return result;
}

FrontendJavaSelectionResult executeJavaSelection(
    const FrontendRuntimeDependencies::JavaSelectionUpdater& updater,
    const std::filesystem::path& dataRoot,
    const std::string& installationIdentifier)
{
    if (installationIdentifier.empty()) {
        throw std::invalid_argument("Java selection requires a stable installation identifier");
    }
    if (!updater) {
        return FrontendJavaSelectionResult{
            FrontendJavaSelectionOutcome::Rejected,
            std::nullopt,
            "java.selection.unavailable",
            "Java selection is unavailable.",
        };
    }

    auto result = updater(dataRoot, installationIdentifier);
    validateJavaSelectionResult(result, installationIdentifier);
    return result;
}

FrontendAccountSnapshotResult executeAccountSnapshots(
    const FrontendRuntimeDependencies::AccountSnapshotLoader& loader,
    const std::filesystem::path& dataRoot)
{
    if (!loader) {
        return FrontendAccountSnapshotResult{
            FrontendAccountSnapshotOutcome::Rejected,
            {},
            std::nullopt,
            "accounts.discovery.unavailable",
            "Account snapshots are unavailable.",
            true,
        };
    }

    auto result = loader(dataRoot);
    validateAccountSnapshotResult(result);
    return result;
}

FrontendAccountSelectionResult executeAccountSelection(
    const FrontendRuntimeDependencies::AccountSelectionUpdater& updater,
    const std::filesystem::path& dataRoot,
    const std::optional<std::string>& requestedIdentifier)
{
    if (requestedIdentifier.has_value() && requestedIdentifier->empty()) {
        throw std::invalid_argument("Account selection requires a non-empty stable identifier or no identifier");
    }
    if (!updater) {
        return FrontendAccountSelectionResult{
            FrontendAccountSelectionOutcome::Rejected,
            std::nullopt,
            "accounts.selection.unavailable",
            "Account selection is unavailable.",
        };
    }

    auto result = updater(dataRoot, requestedIdentifier);
    validateAccountSelectionResult(result, requestedIdentifier);
    return result;
}

FrontendAccountAuthenticationResult executeAccountAuthentication(
    const FrontendRuntimeDependencies::AccountAuthenticationRunner& runner,
    const std::filesystem::path& dataRoot,
    const FrontendAccountAuthenticationRequest& request,
    const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progressHandler)
{
    validateAccountAuthenticationRequest(request);
    if (!runner) {
        return FrontendAccountAuthenticationResult{
            FrontendAccountAuthenticationOutcome::Rejected,
            std::nullopt,
            "accounts.authentication.unavailable",
            "Account authentication is unavailable.",
            true,
        };
    }

    bool terminalProgressSeen = false;
    FrontendAccountAuthenticationOutcome terminalOutcome = FrontendAccountAuthenticationOutcome::InProgress;
    const auto progress = [&](const FrontendAccountAuthenticationProgress& event) {
        if (terminalProgressSeen) {
            throw std::invalid_argument("Account authentication cannot report progress after a terminal event");
        }
        validateAccountAuthenticationProgress(event, request);
        if (event.isTerminal()) {
            terminalProgressSeen = true;
            terminalOutcome = event.outcome;
        }
        if (progressHandler) {
            progressHandler(event);
        }
    };

    auto result = runner(dataRoot, request, progress);
    validateAccountAuthenticationResult(result, request);
    if (result.outcome == FrontendAccountAuthenticationOutcome::Rejected) {
        if (terminalProgressSeen) {
            throw std::invalid_argument("Rejected account authentication cannot report a terminal progress event");
        }
    } else if (!terminalProgressSeen || terminalOutcome != result.outcome) {
        throw std::invalid_argument("Account authentication result must match its terminal progress event");
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

std::optional<FrontendGlobalSettingsSnapshot> FrontendFacade::globalSettings() const
{
    ensureRunning(m_lifecycleState);
    return executeGlobalSettings(m_runtimeDependencies.loadGlobalSettings, m_dataRoot);
}

FrontendGlobalSettingsUpdateResult FrontendFacade::updateGlobalSettings(
    const FrontendGlobalSettingsSnapshot& settings) const
{
    ensureRunning(m_lifecycleState);
    return executeGlobalSettingsUpdate(m_runtimeDependencies.updateGlobalSettings, m_dataRoot, settings);
}

FrontendJavaDiscoveryResult FrontendFacade::javaInstallations() const
{
    ensureRunning(m_lifecycleState);
    return executeJavaDiscovery(m_runtimeDependencies.loadJavaInstallations, m_dataRoot);
}

FrontendJavaSelectionResult FrontendFacade::selectJavaInstallation(const std::string& installationIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeJavaSelection(m_runtimeDependencies.selectJavaInstallation, m_dataRoot, installationIdentifier);
}

FrontendAccountSnapshotResult FrontendFacade::accountSnapshots() const
{
    ensureRunning(m_lifecycleState);
    return executeAccountSnapshots(m_runtimeDependencies.loadAccountSnapshots, m_dataRoot);
}

FrontendAccountSelectionResult FrontendFacade::selectActiveAccount(
    const std::optional<std::string>& accountIdentifier) const
{
    ensureRunning(m_lifecycleState);
    return executeAccountSelection(m_runtimeDependencies.selectActiveAccount, m_dataRoot, accountIdentifier);
}

FrontendAccountAuthenticationResult FrontendFacade::authenticateAccount(
    const FrontendAccountAuthenticationRequest& request,
    const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progressHandler) const
{
    ensureRunning(m_lifecycleState);
    return executeAccountAuthentication(m_runtimeDependencies.authenticateAccount, m_dataRoot, request, progressHandler);
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
