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

bool isKnownOfflineLaunchIdentityMode(FrontendOfflineLaunchIdentityMode mode) noexcept
{
    switch (mode) {
        case FrontendOfflineLaunchIdentityMode::Offline:
        case FrontendOfflineLaunchIdentityMode::Demo:
            return true;
    }
    return false;
}

bool isKnownOfflineLaunchIdentityLoadOutcome(FrontendOfflineLaunchIdentityLoadOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendOfflineLaunchIdentityLoadOutcome::Succeeded:
        case FrontendOfflineLaunchIdentityLoadOutcome::Failed:
        case FrontendOfflineLaunchIdentityLoadOutcome::Cancelled:
        case FrontendOfflineLaunchIdentityLoadOutcome::Rejected:
            return true;
    }
    return false;
}

bool isKnownOfflineLaunchIdentityUpdateOutcome(FrontendOfflineLaunchIdentityUpdateOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendOfflineLaunchIdentityUpdateOutcome::Succeeded:
        case FrontendOfflineLaunchIdentityUpdateOutcome::InvalidName:
        case FrontendOfflineLaunchIdentityUpdateOutcome::Failed:
        case FrontendOfflineLaunchIdentityUpdateOutcome::Cancelled:
        case FrontendOfflineLaunchIdentityUpdateOutcome::Rejected:
            return true;
    }
    return false;
}

bool isValidOfflineLaunchIdentityName(const std::string& name) noexcept
{
    if (name.size() < 3 || name.size() > 16) {
        return false;
    }
    for (const unsigned char character : name) {
        if (!((character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z')
              || (character >= '0' && character <= '9') || character == '_')) {
            return false;
        }
    }
    return true;
}

void validateOfflineLaunchIdentityContext(
    FrontendOfflineLaunchIdentityMode mode,
    const std::optional<std::string>& accountIdentifier)
{
    if (!isKnownOfflineLaunchIdentityMode(mode)
        || (accountIdentifier.has_value() && accountIdentifier->empty())) {
        throw std::invalid_argument("Offline launch identity requires a known mode and non-empty account identifier");
    }
}

void validateOfflineLaunchIdentitySnapshot(
    const FrontendOfflineLaunchIdentitySnapshot& identity,
    FrontendOfflineLaunchIdentityMode expectedMode,
    const std::optional<std::string>& expectedAccountIdentifier)
{
    validateOfflineLaunchIdentityContext(expectedMode, expectedAccountIdentifier);
    validateOfflineLaunchIdentityContext(identity.mode, identity.accountIdentifier);
    if (identity.mode != expectedMode || identity.accountIdentifier != expectedAccountIdentifier || identity.name.empty()) {
        throw std::invalid_argument("Offline launch identity snapshot does not match its request");
    }
}

void validateOfflineLaunchIdentityLoadRequest(const FrontendOfflineLaunchIdentityRequest& request)
{
    validateOfflineLaunchIdentityContext(request.mode, request.accountIdentifier);
    if (request.fallbackName.empty()) {
        throw std::invalid_argument("Offline launch identity loading requires a fallback name");
    }
}

void validateOfflineLaunchIdentityLoadResult(
    const FrontendOfflineLaunchIdentityLoadResult& result,
    const FrontendOfflineLaunchIdentityRequest& request)
{
    if (!isKnownOfflineLaunchIdentityLoadOutcome(result.outcome) || result.localizationKey.empty()) {
        throw std::invalid_argument("Offline launch identity load result requires a known outcome and localization key");
    }
    if (result.identity.has_value()) {
        validateOfflineLaunchIdentitySnapshot(*result.identity, request.mode, request.accountIdentifier);
    }
    if (result.outcome == FrontendOfflineLaunchIdentityLoadOutcome::Succeeded) {
        if (!result.identity.has_value()) {
            throw std::invalid_argument("Successful offline launch identity loading requires an identity");
        }
    } else if (result.identity.has_value()) {
        throw std::invalid_argument("Non-successful offline launch identity loading cannot carry an identity");
    }
}

void validateOfflineLaunchIdentityUpdateRequest(const FrontendOfflineLaunchIdentityUpdateRequest& request)
{
    validateOfflineLaunchIdentityContext(request.mode, request.accountIdentifier);
}

void validateOfflineLaunchIdentityUpdateResult(
    const FrontendOfflineLaunchIdentityUpdateResult& result,
    const FrontendOfflineLaunchIdentityUpdateRequest& request)
{
    if (!isKnownOfflineLaunchIdentityUpdateOutcome(result.outcome) || result.localizationKey.empty()) {
        throw std::invalid_argument("Offline launch identity update result requires a known outcome and localization key");
    }
    if (result.identity.has_value()) {
        validateOfflineLaunchIdentitySnapshot(*result.identity, request.mode, request.accountIdentifier);
    }
    if (result.outcome == FrontendOfflineLaunchIdentityUpdateOutcome::Succeeded) {
        if (!result.identity.has_value() || result.identity->name != request.name) {
            throw std::invalid_argument("Successful offline launch identity update must confirm the requested name");
        }
    } else if (result.identity.has_value()) {
        throw std::invalid_argument("Non-successful offline launch identity update cannot carry an identity");
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

bool isKnownVanillaCreationOutcome(FrontendVanillaCreationOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendVanillaCreationOutcome::Succeeded:
        case FrontendVanillaCreationOutcome::Failed:
        case FrontendVanillaCreationOutcome::Cancelled:
        case FrontendVanillaCreationOutcome::Rejected:
            return true;
    }
    return false;
}

void validateVanillaCreationRequest(const FrontendVanillaCreationRequest& request)
{
    if (request.versionDescriptor.empty() || request.versionName.empty() || request.name.empty()
        || request.iconKey.empty()) {
        throw std::invalid_argument("Vanilla creation requires version metadata, a name, and an icon key");
    }

    const bool hasLoader = request.loaderIdentifier.has_value() || request.loaderVersionDescriptor.has_value();
    if (hasLoader
        && (!request.loaderIdentifier.has_value() || !request.loaderVersionDescriptor.has_value()
            || request.loaderIdentifier->empty() || request.loaderVersionDescriptor->empty())) {
        throw std::invalid_argument("Vanilla loader selection requires an identifier and version descriptor");
    }
}

void validateVanillaCreationResult(
    const FrontendVanillaCreationResult& result,
    const FrontendVanillaCreationRequest& request)
{
    if (!isKnownVanillaCreationOutcome(result.outcome) || result.localizationKey.empty()) {
        throw std::invalid_argument("Vanilla creation results require a known outcome and localization key");
    }

    if (result.outcome == FrontendVanillaCreationOutcome::Succeeded) {
        if (!result.instance.has_value() || !result.instance->hasStableIdentifier()
            || result.instance->name.empty() || result.instance->name != request.name
            || result.instance->groupId != request.groupId || result.instance->iconKey != request.iconKey) {
            throw std::invalid_argument("Successful vanilla creation must confirm the requested instance values");
        }
    } else if (result.instance.has_value()) {
        throw std::invalid_argument("Non-successful vanilla creation cannot carry an instance summary");
    }
}

bool isKnownInstanceImportSourceKind(FrontendInstanceImportSourceKind kind) noexcept
{
    switch (kind) {
        case FrontendInstanceImportSourceKind::LocalFile:
        case FrontendInstanceImportSourceKind::RemoteURL:
            return true;
    }
    return false;
}

bool isKnownInstanceImportOutcome(FrontendInstanceImportOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendInstanceImportOutcome::Succeeded:
        case FrontendInstanceImportOutcome::Failed:
        case FrontendInstanceImportOutcome::Cancelled:
        case FrontendInstanceImportOutcome::Rejected:
            return true;
    }
    return false;
}

bool hasNoWhitespace(const std::string& value) noexcept
{
    return value.find_first_of(" \t\r\n") == std::string::npos;
}

bool isValidRemoteInstanceImportSource(const std::string& source) noexcept
{
    const bool hasHTTPSScheme = source.rfind("https://", 0) == 0;
    const bool hasHTTPScheme = source.rfind("http://", 0) == 0;
    if ((!hasHTTPSScheme && !hasHTTPScheme) || !hasNoWhitespace(source)) {
        return false;
    }

    const auto authorityOffset = hasHTTPSScheme ? std::string("https://").size() : std::string("http://").size();
    const auto authorityEnd = source.find_first_of("/?#", authorityOffset);
    const auto authority = source.substr(
        authorityOffset,
        authorityEnd == std::string::npos ? std::string::npos : authorityEnd - authorityOffset);
    return !authority.empty();
}

void validateInstanceImportRequest(const FrontendInstanceImportRequest& request)
{
    if (!isKnownInstanceImportSourceKind(request.sourceKind) || request.source.empty() || request.name.empty()
        || request.iconKey.empty()) {
        throw std::invalid_argument("Instance import requires a known source, name, and icon key");
    }

    if (request.sourceKind == FrontendInstanceImportSourceKind::LocalFile) {
        if (!std::filesystem::path(request.source).is_absolute()) {
            throw std::invalid_argument("Local instance imports require an absolute source path");
        }
        return;
    }

    if (!isValidRemoteInstanceImportSource(request.source)) {
        throw std::invalid_argument("Remote instance imports require an HTTP(S) URL with an authority");
    }
}

void validateInstanceImportResult(
    const FrontendInstanceImportResult& result,
    const FrontendInstanceImportRequest& request)
{
    if (!isKnownInstanceImportOutcome(result.outcome) || result.localizationKey.empty()) {
        throw std::invalid_argument("Instance import results require a known outcome and localization key");
    }

    if (result.outcome == FrontendInstanceImportOutcome::Succeeded) {
        if (!result.instance.has_value() || !result.instance->hasStableIdentifier() || result.instance->name.empty()
            || result.instance->name != request.name || result.instance->groupId != request.groupId
            || result.instance->iconKey != request.iconKey) {
            throw std::invalid_argument("Successful instance import must confirm the requested instance values");
        }
    } else if (result.instance.has_value()) {
        throw std::invalid_argument("Non-successful instance import cannot carry an instance summary");
    }
}

bool isKnownInstanceCopyOutcome(FrontendInstanceCopyOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendInstanceCopyOutcome::Succeeded:
        case FrontendInstanceCopyOutcome::Failed:
        case FrontendInstanceCopyOutcome::Cancelled:
        case FrontendInstanceCopyOutcome::Rejected:
            return true;
    }
    return false;
}

void validateInstanceCopyRequest(const FrontendInstanceCopyRequest& request)
{
    if (request.sourceInstanceIdentifier.empty() || request.name.empty() || request.iconKey.empty()) {
        throw std::invalid_argument("Instance copy requires a source identifier, name, and icon key");
    }

    const auto& options = request.options;
    const bool usesLinks = options.useSymbolicLinks || options.useHardLinks;
    if (options.useClone && usesLinks) {
        throw std::invalid_argument("Instance clone cannot be combined with symbolic or hard links");
    }
    if (options.useHardLinks && !options.linkRecursively) {
        throw std::invalid_argument("Hard-link copies require recursive linking");
    }
    if (options.dontLinkSaves && (!usesLinks || !options.copySaves)) {
        throw std::invalid_argument("Do-not-link-saves requires linked save data");
    }
}

void validateInstanceCopyResult(
    const FrontendInstanceCopyResult& result,
    const FrontendInstanceCopyRequest& request)
{
    if (!isKnownInstanceCopyOutcome(result.outcome) || result.localizationKey.empty()) {
        throw std::invalid_argument("Instance copy results require a known outcome and localization key");
    }

    if (result.outcome == FrontendInstanceCopyOutcome::Succeeded) {
        if (!result.instance.has_value() || !result.instance->hasStableIdentifier() || result.instance->name.empty()
            || result.instance->name != request.name || result.instance->groupId != request.groupId
            || result.instance->iconKey != request.iconKey) {
            throw std::invalid_argument("Successful instance copy must confirm the requested instance values");
        }
    } else if (result.instance.has_value()) {
        throw std::invalid_argument("Non-successful instance copy cannot carry an instance summary");
    }
}

bool isKnownInstanceExportKind(FrontendInstanceExportKind kind) noexcept
{
    switch (kind) {
        case FrontendInstanceExportKind::ZipArchive:
        case FrontendInstanceExportKind::ModList:
            return true;
    }
    return false;
}

bool isKnownModListExportFormat(FrontendModListExportFormat format) noexcept
{
    switch (format) {
        case FrontendModListExportFormat::HTML:
        case FrontendModListExportFormat::Markdown:
        case FrontendModListExportFormat::PlainText:
        case FrontendModListExportFormat::JSON:
        case FrontendModListExportFormat::CSV:
        case FrontendModListExportFormat::Custom:
            return true;
    }
    return false;
}

bool isKnownInstanceExportOutcome(FrontendInstanceExportOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendInstanceExportOutcome::Succeeded:
        case FrontendInstanceExportOutcome::Failed:
        case FrontendInstanceExportOutcome::Cancelled:
        case FrontendInstanceExportOutcome::Rejected:
            return true;
    }
    return false;
}

void validateInstanceExportRequest(const FrontendInstanceExportRequest& request)
{
    if (!isKnownInstanceExportKind(request.kind) || request.sourceInstanceIdentifier.empty()
        || request.destinationPath.empty() || !request.destinationPath.is_absolute()) {
        throw std::invalid_argument("Instance exports require a known kind, source identifier, and absolute destination");
    }

    if (request.kind == FrontendInstanceExportKind::ZipArchive) {
        if (request.modListFieldMask != 0 || !request.customTemplate.empty()) {
            throw std::invalid_argument("ZIP exports cannot carry mod-list formatting options");
        }
        return;
    }

    if (!isKnownModListExportFormat(request.modListFormat)
        || (request.modListFieldMask & ~kFrontendModListFieldAll) != 0) {
        throw std::invalid_argument("Mod-list exports require a known format and field mask");
    }
    if (request.modListFormat == FrontendModListExportFormat::Custom && request.customTemplate.empty()) {
        throw std::invalid_argument("Custom mod-list exports require a template");
    }
    if (request.modListFormat != FrontendModListExportFormat::Custom && !request.customTemplate.empty()) {
        throw std::invalid_argument("Only custom mod-list exports may carry a template");
    }
}

void validateInstanceExportResult(
    const FrontendInstanceExportResult& result,
    const FrontendInstanceExportRequest& request)
{
    if (!isKnownInstanceExportKind(result.kind) || result.kind != request.kind
        || !isKnownInstanceExportOutcome(result.outcome) || result.localizationKey.empty()
        || result.destinationPath.empty() || !result.destinationPath.is_absolute()
        || result.destinationPath.lexically_normal() != request.destinationPath.lexically_normal()) {
        throw std::invalid_argument("Instance export results must confirm the requested kind and destination");
    }
}

bool isKnownProviderKind(FrontendProviderKind provider) noexcept
{
    switch (provider) {
        case FrontendProviderKind::Modrinth:
        case FrontendProviderKind::CurseForge:
        case FrontendProviderKind::FTB:
        case FrontendProviderKind::ATLauncher:
        case FrontendProviderKind::Technic:
        case FrontendProviderKind::LegacyFTB:
            return true;
    }
    return false;
}

bool isKnownProviderSort(FrontendProviderSort sort) noexcept
{
    switch (sort) {
        case FrontendProviderSort::Relevance:
        case FrontendProviderSort::Popularity:
        case FrontendProviderSort::Newest:
        case FrontendProviderSort::Updated:
        case FrontendProviderSort::Name:
        case FrontendProviderSort::Downloads:
        case FrontendProviderSort::Follows:
        case FrontendProviderSort::GameVersion:
        case FrontendProviderSort::Plays:
        case FrontendProviderSort::Installs:
            return true;
    }
    return false;
}

bool isKnownProviderReleaseType(FrontendProviderReleaseType releaseType) noexcept
{
    switch (releaseType) {
        case FrontendProviderReleaseType::Unknown:
        case FrontendProviderReleaseType::Release:
        case FrontendProviderReleaseType::Beta:
        case FrontendProviderReleaseType::Alpha:
            return true;
    }
    return false;
}

bool isKnownProviderSide(FrontendProviderSide side) noexcept
{
    switch (side) {
        case FrontendProviderSide::Any:
        case FrontendProviderSide::Client:
        case FrontendProviderSide::Server:
        case FrontendProviderSide::Universal:
            return true;
    }
    return false;
}

void validateProviderStringFilters(const std::vector<std::string>& values, const char* description)
{
    std::set<std::string> uniqueValues;
    for (const auto& value : values) {
        if (value.empty() || !uniqueValues.insert(value).second) {
            throw std::invalid_argument(std::string("Provider ") + description + " require unique non-empty values");
        }
    }
}

void validateProviderReleaseFilters(const std::vector<FrontendProviderReleaseType>& values)
{
    std::set<FrontendProviderReleaseType> uniqueValues;
    for (const auto value : values) {
        if (!isKnownProviderReleaseType(value) || !uniqueValues.insert(value).second) {
            throw std::invalid_argument("Provider release filters require known unique values");
        }
    }
}

void validateProviderBrowseRequest(const FrontendProviderBrowseRequest& request)
{
    if (!isKnownProviderKind(request.provider) || !isKnownProviderSort(request.sort)
        || !isKnownProviderSide(request.side) || request.pageSize == 0 || request.pageSize > 100) {
        throw std::invalid_argument("Provider browse requires known provider, sort, side, and bounded page size");
    }
    validateProviderStringFilters(request.gameVersions, "game-version filters");
    validateProviderStringFilters(request.loaders, "loader filters");
    validateProviderStringFilters(request.categories, "category filters");
    validateProviderReleaseFilters(request.releaseTypes);
}

void validateProviderPackSnapshot(const FrontendProviderPackSnapshot& pack, FrontendProviderKind provider)
{
    if (!isKnownProviderKind(pack.provider) || pack.provider != provider || !pack.hasStableIdentifier()
        || pack.name.empty()) {
        throw std::invalid_argument("Provider browse rows require a provider, stable identifier, and name");
    }
    validateProviderStringFilters(pack.categories, "pack categories");
}

void validateProviderBrowsePage(
    const FrontendProviderBrowsePage& page,
    const FrontendProviderBrowseRequest& request)
{
    if (!isKnownProviderKind(page.provider) || page.provider != request.provider || page.offset != request.offset
        || page.pageSize != request.pageSize) {
        throw std::invalid_argument("Provider browse pages must echo provider and pagination values");
    }

    std::set<std::string> identifiers;
    for (const auto& pack : page.packs) {
        validateProviderPackSnapshot(pack, request.provider);
        if (!identifiers.insert(pack.id).second) {
            throw std::invalid_argument("Provider browse pages require unique pack identifiers");
        }
    }
    if (page.nextOffset.has_value() && page.nextOffset.value() <= page.offset) {
        throw std::invalid_argument("Provider browse next offsets must advance the current page");
    }
}

bool isKnownProviderBrowseOutcome(FrontendProviderBrowseOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendProviderBrowseOutcome::Succeeded:
        case FrontendProviderBrowseOutcome::Failed:
        case FrontendProviderBrowseOutcome::Cancelled:
        case FrontendProviderBrowseOutcome::Rejected:
            return true;
    }
    return false;
}

void validateProviderBrowseResult(
    const FrontendProviderBrowseResult& result,
    const FrontendProviderBrowseRequest& request)
{
    if (!isKnownProviderBrowseOutcome(result.outcome) || result.localizationKey.empty()) {
        throw std::invalid_argument("Provider browse results require a known outcome and localization key");
    }
    if (result.outcome == FrontendProviderBrowseOutcome::Succeeded) {
        if (!result.page.has_value()) {
            throw std::invalid_argument("Successful provider browse must carry a page");
        }
        validateProviderBrowsePage(*result.page, request);
    } else if (result.page.has_value()) {
        throw std::invalid_argument("Non-successful provider browse cannot carry a page");
    }
}

void validateProviderVersionRequest(const FrontendProviderVersionRequest& request)
{
    if (!isKnownProviderKind(request.provider) || request.packIdentifier.empty()) {
        throw std::invalid_argument("Provider version requests require a provider and pack identifier");
    }
    validateProviderStringFilters(request.gameVersions, "version game filters");
    validateProviderStringFilters(request.loaders, "version loader filters");
}

void validateProviderVersionSnapshot(
    const FrontendProviderVersionSnapshot& version,
    const FrontendProviderVersionRequest& request)
{
    if (!isKnownProviderKind(version.provider) || version.provider != request.provider || !version.hasStableIdentifier()
        || version.packIdentifier != request.packIdentifier || version.name.empty() || version.version.empty()
        || !isKnownProviderReleaseType(version.releaseType)) {
        throw std::invalid_argument("Provider versions require matching provider data and stable metadata");
    }
    validateProviderStringFilters(version.gameVersions, "version game metadata");
    validateProviderStringFilters(version.loaders, "version loader metadata");
}

bool isKnownProviderVersionOutcome(FrontendProviderVersionOutcome outcome) noexcept
{
    switch (outcome) {
        case FrontendProviderVersionOutcome::Succeeded:
        case FrontendProviderVersionOutcome::Failed:
        case FrontendProviderVersionOutcome::Cancelled:
        case FrontendProviderVersionOutcome::Rejected:
            return true;
    }
    return false;
}

void validateProviderVersionResult(
    const FrontendProviderVersionResult& result,
    const FrontendProviderVersionRequest& request)
{
    if (!isKnownProviderVersionOutcome(result.outcome) || !isKnownProviderKind(result.provider)
        || result.provider != request.provider || result.packIdentifier != request.packIdentifier
        || result.localizationKey.empty()) {
        throw std::invalid_argument("Provider version results require matching provider identity and localization key");
    }
    if (result.outcome != FrontendProviderVersionOutcome::Succeeded && !result.versions.empty()) {
        throw std::invalid_argument("Non-successful provider version loads cannot carry versions");
    }

    std::set<std::string> identifiers;
    for (const auto& version : result.versions) {
        validateProviderVersionSnapshot(version, request);
        if (!identifiers.insert(version.id).second) {
            throw std::invalid_argument("Provider version results require unique identifiers");
        }
    }
}

bool isMatchingProviderTerminalState(
    FrontendProviderBrowseOutcome outcome,
    FrontendTaskState terminalState) noexcept
{
    return (outcome == FrontendProviderBrowseOutcome::Succeeded && terminalState == FrontendTaskState::Succeeded)
        || (outcome == FrontendProviderBrowseOutcome::Failed && terminalState == FrontendTaskState::Failed)
        || (outcome == FrontendProviderBrowseOutcome::Cancelled && terminalState == FrontendTaskState::Cancelled);
}

bool isMatchingProviderTerminalState(
    FrontendProviderVersionOutcome outcome,
    FrontendTaskState terminalState) noexcept
{
    return (outcome == FrontendProviderVersionOutcome::Succeeded && terminalState == FrontendTaskState::Succeeded)
        || (outcome == FrontendProviderVersionOutcome::Failed && terminalState == FrontendTaskState::Failed)
        || (outcome == FrontendProviderVersionOutcome::Cancelled && terminalState == FrontendTaskState::Cancelled);
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

FrontendOfflineLaunchIdentityLoadResult executeOfflineLaunchIdentityLoad(
    const FrontendRuntimeDependencies::OfflineLaunchIdentityLoader& loader,
    const std::filesystem::path& dataRoot,
    const FrontendOfflineLaunchIdentityRequest& request)
{
    validateOfflineLaunchIdentityLoadRequest(request);
    if (!loader) {
        return FrontendOfflineLaunchIdentityLoadResult{
            FrontendOfflineLaunchIdentityLoadOutcome::Rejected,
            std::nullopt,
            "accounts.offlineIdentity.unavailable",
            "Offline launch identity is unavailable.",
            true,
        };
    }

    auto result = loader(dataRoot, request);
    validateOfflineLaunchIdentityLoadResult(result, request);
    return result;
}

FrontendOfflineLaunchIdentityUpdateResult executeOfflineLaunchIdentityUpdate(
    const FrontendRuntimeDependencies::OfflineLaunchIdentityUpdater& updater,
    const std::filesystem::path& dataRoot,
    const FrontendOfflineLaunchIdentityUpdateRequest& request)
{
    validateOfflineLaunchIdentityUpdateRequest(request);
    if (request.name.empty() || (!request.allowInvalidName && !isValidOfflineLaunchIdentityName(request.name))) {
        return FrontendOfflineLaunchIdentityUpdateResult{
            FrontendOfflineLaunchIdentityUpdateOutcome::InvalidName,
            std::nullopt,
            "accounts.offlineIdentity.invalidName",
            "Offline launch names must be 3–16 English letters, numbers, or underscores.",
            false,
        };
    }
    if (!updater) {
        return FrontendOfflineLaunchIdentityUpdateResult{
            FrontendOfflineLaunchIdentityUpdateOutcome::Rejected,
            std::nullopt,
            "accounts.offlineIdentity.unavailable",
            "Offline launch identity is unavailable.",
            true,
        };
    }

    auto result = updater(dataRoot, request);
    validateOfflineLaunchIdentityUpdateResult(result, request);
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

FrontendVanillaCreationResult executeVanillaCreation(
    const FrontendRuntimeDependencies::VanillaCreationRunner& runner,
    const std::filesystem::path& dataRoot,
    const FrontendVanillaCreationRequest& request,
    const FrontendRuntimeDependencies::VanillaCreationProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::VanillaCreationCancellationCheck& cancellationCheck)
{
    validateVanillaCreationRequest(request);
    if (!runner) {
        return FrontendVanillaCreationResult{
            FrontendVanillaCreationOutcome::Rejected,
            std::nullopt,
            "instances.creation.vanilla.unavailable",
            "Vanilla instance creation is unavailable.",
            true,
        };
    }

    bool terminalProgressSeen = false;
    FrontendTaskState terminalState = FrontendTaskState::Queued;
    const auto progress = [&](const FrontendTaskSnapshot& snapshot) {
        validateTaskSnapshot(snapshot);
        if (snapshot.title.empty()) {
            throw std::invalid_argument("Vanilla creation progress requires a task title");
        }
        if (terminalProgressSeen) {
            throw std::invalid_argument("Vanilla creation cannot report progress after a terminal event");
        }
        if (isTerminalTaskState(snapshot.state)) {
            terminalProgressSeen = true;
            terminalState = snapshot.state;
        }
        if (progressHandler) {
            progressHandler(snapshot);
        }
    };

    auto result = runner(dataRoot, request, progress, cancellationCheck);
    validateVanillaCreationResult(result, request);
    if (result.outcome == FrontendVanillaCreationOutcome::Rejected) {
        if (terminalProgressSeen) {
            throw std::invalid_argument("Rejected vanilla creation cannot report a terminal progress event");
        }
        return result;
    }

    const bool matchingTerminalState = (result.outcome == FrontendVanillaCreationOutcome::Succeeded
                                         && terminalState == FrontendTaskState::Succeeded)
        || (result.outcome == FrontendVanillaCreationOutcome::Failed && terminalState == FrontendTaskState::Failed)
        || (result.outcome == FrontendVanillaCreationOutcome::Cancelled
            && terminalState == FrontendTaskState::Cancelled);
    if (!terminalProgressSeen || !matchingTerminalState) {
        throw std::invalid_argument("Vanilla creation result must match its terminal progress event");
    }
    return result;
}

FrontendInstanceImportResult executeInstanceImport(
    const FrontendRuntimeDependencies::InstanceImportRunner& runner,
    const std::filesystem::path& dataRoot,
    const FrontendInstanceImportRequest& request,
    const FrontendRuntimeDependencies::InstanceImportProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::InstanceImportCancellationCheck& cancellationCheck)
{
    validateInstanceImportRequest(request);
    if (!runner) {
        return FrontendInstanceImportResult{
            FrontendInstanceImportOutcome::Rejected,
            std::nullopt,
            "instances.import.unavailable",
            "Instance import is unavailable.",
            true,
            false,
        };
    }

    bool terminalProgressSeen = false;
    FrontendTaskState terminalState = FrontendTaskState::Queued;
    const auto progress = [&](const FrontendTaskSnapshot& snapshot) {
        validateTaskSnapshot(snapshot);
        if (snapshot.title.empty()) {
            throw std::invalid_argument("Instance import progress requires a task title");
        }
        if (terminalProgressSeen) {
            throw std::invalid_argument("Instance import cannot report progress after a terminal event");
        }
        if (isTerminalTaskState(snapshot.state)) {
            terminalProgressSeen = true;
            terminalState = snapshot.state;
        }
        if (progressHandler) {
            progressHandler(snapshot);
        }
    };

    auto result = runner(dataRoot, request, progress, cancellationCheck);
    validateInstanceImportResult(result, request);
    if (result.outcome == FrontendInstanceImportOutcome::Rejected) {
        if (terminalProgressSeen) {
            throw std::invalid_argument("Rejected instance import cannot report a terminal progress event");
        }
        return result;
    }

    const bool matchingTerminalState = (result.outcome == FrontendInstanceImportOutcome::Succeeded
                                         && terminalState == FrontendTaskState::Succeeded)
        || (result.outcome == FrontendInstanceImportOutcome::Failed && terminalState == FrontendTaskState::Failed)
        || (result.outcome == FrontendInstanceImportOutcome::Cancelled
            && terminalState == FrontendTaskState::Cancelled);
    if (!terminalProgressSeen || !matchingTerminalState) {
        throw std::invalid_argument("Instance import result must match its terminal progress event");
    }
    return result;
}

FrontendInstanceCopyResult executeInstanceCopy(
    const FrontendRuntimeDependencies::InstanceCopyRunner& runner,
    const std::filesystem::path& dataRoot,
    const FrontendInstanceCopyRequest& request,
    const FrontendRuntimeDependencies::InstanceCopyProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::InstanceCopyCancellationCheck& cancellationCheck)
{
    validateInstanceCopyRequest(request);
    if (!runner) {
        return FrontendInstanceCopyResult{
            FrontendInstanceCopyOutcome::Rejected,
            std::nullopt,
            "instances.copy.unavailable",
            "Instance copy is unavailable.",
            true,
            false,
        };
    }

    bool terminalProgressSeen = false;
    FrontendTaskState terminalState = FrontendTaskState::Queued;
    const auto progress = [&](const FrontendTaskSnapshot& snapshot) {
        validateTaskSnapshot(snapshot);
        if (snapshot.title.empty()) {
            throw std::invalid_argument("Instance copy progress requires a task title");
        }
        if (terminalProgressSeen) {
            throw std::invalid_argument("Instance copy cannot report progress after a terminal event");
        }
        if (isTerminalTaskState(snapshot.state)) {
            terminalProgressSeen = true;
            terminalState = snapshot.state;
        }
        if (progressHandler) {
            progressHandler(snapshot);
        }
    };

    auto result = runner(dataRoot, request, progress, cancellationCheck);
    validateInstanceCopyResult(result, request);
    if (result.outcome == FrontendInstanceCopyOutcome::Rejected) {
        if (terminalProgressSeen) {
            throw std::invalid_argument("Rejected instance copy cannot report a terminal progress event");
        }
        return result;
    }

    const bool matchingTerminalState = (result.outcome == FrontendInstanceCopyOutcome::Succeeded
                                         && terminalState == FrontendTaskState::Succeeded)
        || (result.outcome == FrontendInstanceCopyOutcome::Failed && terminalState == FrontendTaskState::Failed)
        || (result.outcome == FrontendInstanceCopyOutcome::Cancelled
            && terminalState == FrontendTaskState::Cancelled);
    if (!terminalProgressSeen || !matchingTerminalState) {
        throw std::invalid_argument("Instance copy result must match its terminal progress event");
    }
    return result;
}

FrontendInstanceExportResult executeInstanceExport(
    const FrontendRuntimeDependencies::InstanceExportRunner& runner,
    const std::filesystem::path& dataRoot,
    const FrontendInstanceExportRequest& request,
    const FrontendRuntimeDependencies::InstanceExportProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::InstanceExportCancellationCheck& cancellationCheck)
{
    validateInstanceExportRequest(request);
    if (!runner) {
        return FrontendInstanceExportResult{
            request.kind,
            FrontendInstanceExportOutcome::Rejected,
            request.destinationPath,
            "instances.export.unavailable",
            "Instance export is unavailable.",
            true,
            false,
        };
    }

    bool terminalProgressSeen = false;
    FrontendTaskState terminalState = FrontendTaskState::Queued;
    const auto progress = [&](const FrontendTaskSnapshot& snapshot) {
        validateTaskSnapshot(snapshot);
        if (snapshot.title.empty()) {
            throw std::invalid_argument("Instance export progress requires a task title");
        }
        if (terminalProgressSeen) {
            throw std::invalid_argument("Instance export cannot report progress after a terminal event");
        }
        if (isTerminalTaskState(snapshot.state)) {
            terminalProgressSeen = true;
            terminalState = snapshot.state;
        }
        if (progressHandler) {
            progressHandler(snapshot);
        }
    };

    auto result = runner(dataRoot, request, progress, cancellationCheck);
    validateInstanceExportResult(result, request);
    if (result.outcome == FrontendInstanceExportOutcome::Rejected) {
        if (terminalProgressSeen) {
            throw std::invalid_argument("Rejected instance export cannot report a terminal progress event");
        }
        return result;
    }

    const bool matchingTerminalState = (result.outcome == FrontendInstanceExportOutcome::Succeeded
                                         && terminalState == FrontendTaskState::Succeeded)
        || (result.outcome == FrontendInstanceExportOutcome::Failed && terminalState == FrontendTaskState::Failed)
        || (result.outcome == FrontendInstanceExportOutcome::Cancelled
            && terminalState == FrontendTaskState::Cancelled);
    if (!terminalProgressSeen || !matchingTerminalState) {
        throw std::invalid_argument("Instance export result must match its terminal progress event");
    }
    return result;
}

FrontendProviderBrowseResult executeProviderBrowse(
    const FrontendRuntimeDependencies::ProviderBrowseRunner& runner,
    const std::filesystem::path& dataRoot,
    const FrontendProviderBrowseRequest& request,
    const FrontendRuntimeDependencies::ProviderBrowseProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::ProviderBrowseCancellationCheck& cancellationCheck)
{
    validateProviderBrowseRequest(request);
    if (!runner) {
        return FrontendProviderBrowseResult{
            FrontendProviderBrowseOutcome::Rejected,
            std::nullopt,
            "providers.browse.unavailable",
            "Provider browsing is unavailable.",
            true,
        };
    }

    bool terminalProgressSeen = false;
    FrontendTaskState terminalState = FrontendTaskState::Queued;
    const auto progress = [&](const FrontendTaskSnapshot& snapshot) {
        validateTaskSnapshot(snapshot);
        if (snapshot.title.empty()) {
            throw std::invalid_argument("Provider browse progress requires a task title");
        }
        if (terminalProgressSeen) {
            throw std::invalid_argument("Provider browse cannot report progress after a terminal event");
        }
        if (isTerminalTaskState(snapshot.state)) {
            terminalProgressSeen = true;
            terminalState = snapshot.state;
        }
        if (progressHandler) {
            progressHandler(snapshot);
        }
    };

    auto result = runner(dataRoot, request, progress, cancellationCheck);
    validateProviderBrowseResult(result, request);
    if (result.outcome == FrontendProviderBrowseOutcome::Rejected) {
        if (terminalProgressSeen) {
            throw std::invalid_argument("Rejected provider browse cannot report a terminal progress event");
        }
        return result;
    }
    if (!terminalProgressSeen || !isMatchingProviderTerminalState(result.outcome, terminalState)) {
        throw std::invalid_argument("Provider browse result must match its terminal progress event");
    }
    return result;
}

FrontendProviderVersionResult executeProviderVersions(
    const FrontendRuntimeDependencies::ProviderVersionRunner& runner,
    const std::filesystem::path& dataRoot,
    const FrontendProviderVersionRequest& request,
    const FrontendRuntimeDependencies::ProviderVersionProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::ProviderVersionCancellationCheck& cancellationCheck)
{
    validateProviderVersionRequest(request);
    if (!runner) {
        return FrontendProviderVersionResult{
            FrontendProviderVersionOutcome::Rejected,
            request.provider,
            request.packIdentifier,
            {},
            "providers.versions.unavailable",
            "Provider version selection is unavailable.",
            true,
        };
    }

    bool terminalProgressSeen = false;
    FrontendTaskState terminalState = FrontendTaskState::Queued;
    const auto progress = [&](const FrontendTaskSnapshot& snapshot) {
        validateTaskSnapshot(snapshot);
        if (snapshot.title.empty()) {
            throw std::invalid_argument("Provider version progress requires a task title");
        }
        if (terminalProgressSeen) {
            throw std::invalid_argument("Provider version loading cannot report progress after a terminal event");
        }
        if (isTerminalTaskState(snapshot.state)) {
            terminalProgressSeen = true;
            terminalState = snapshot.state;
        }
        if (progressHandler) {
            progressHandler(snapshot);
        }
    };

    auto result = runner(dataRoot, request, progress, cancellationCheck);
    validateProviderVersionResult(result, request);
    if (result.outcome == FrontendProviderVersionOutcome::Rejected) {
        if (terminalProgressSeen) {
            throw std::invalid_argument("Rejected provider version loading cannot report a terminal progress event");
        }
        return result;
    }
    if (!terminalProgressSeen || !isMatchingProviderTerminalState(result.outcome, terminalState)) {
        throw std::invalid_argument("Provider version result must match its terminal progress event");
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

FrontendVanillaCreationResult FrontendFacade::createVanillaInstance(
    const FrontendVanillaCreationRequest& request,
    const FrontendRuntimeDependencies::VanillaCreationProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::VanillaCreationCancellationCheck& cancellationCheck) const
{
    ensureRunning(m_lifecycleState);
    return executeVanillaCreation(
        m_runtimeDependencies.createVanillaInstance, m_dataRoot, request, progressHandler, cancellationCheck);
}

FrontendInstanceImportResult FrontendFacade::importInstance(
    const FrontendInstanceImportRequest& request,
    const FrontendRuntimeDependencies::InstanceImportProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::InstanceImportCancellationCheck& cancellationCheck) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceImport(
        m_runtimeDependencies.importInstance, m_dataRoot, request, progressHandler, cancellationCheck);
}

FrontendInstanceCopyResult FrontendFacade::copyInstance(
    const FrontendInstanceCopyRequest& request,
    const FrontendRuntimeDependencies::InstanceCopyProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::InstanceCopyCancellationCheck& cancellationCheck) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceCopy(
        m_runtimeDependencies.copyInstance, m_dataRoot, request, progressHandler, cancellationCheck);
}

FrontendInstanceExportResult FrontendFacade::exportInstance(
    const FrontendInstanceExportRequest& request,
    const FrontendRuntimeDependencies::InstanceExportProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::InstanceExportCancellationCheck& cancellationCheck) const
{
    ensureRunning(m_lifecycleState);
    return executeInstanceExport(
        m_runtimeDependencies.exportInstance, m_dataRoot, request, progressHandler, cancellationCheck);
}

FrontendProviderBrowseResult FrontendFacade::browseProvider(
    const FrontendProviderBrowseRequest& request,
    const FrontendRuntimeDependencies::ProviderBrowseProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::ProviderBrowseCancellationCheck& cancellationCheck) const
{
    ensureRunning(m_lifecycleState);
    return executeProviderBrowse(
        m_runtimeDependencies.browseProvider, m_dataRoot, request, progressHandler, cancellationCheck);
}

FrontendProviderVersionResult FrontendFacade::providerVersions(
    const FrontendProviderVersionRequest& request,
    const FrontendRuntimeDependencies::ProviderVersionProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::ProviderVersionCancellationCheck& cancellationCheck) const
{
    ensureRunning(m_lifecycleState);
    return executeProviderVersions(
        m_runtimeDependencies.loadProviderVersions, m_dataRoot, request, progressHandler, cancellationCheck);
}

FrontendOfflineLaunchIdentityLoadResult FrontendFacade::loadOfflineLaunchIdentity(
    const FrontendOfflineLaunchIdentityRequest& request) const
{
    ensureRunning(m_lifecycleState);
    return executeOfflineLaunchIdentityLoad(m_runtimeDependencies.loadOfflineLaunchIdentity, m_dataRoot, request);
}

FrontendOfflineLaunchIdentityUpdateResult FrontendFacade::updateOfflineLaunchIdentity(
    const FrontendOfflineLaunchIdentityUpdateRequest& request) const
{
    ensureRunning(m_lifecycleState);
    return executeOfflineLaunchIdentityUpdate(m_runtimeDependencies.updateOfflineLaunchIdentity, m_dataRoot, request);
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
