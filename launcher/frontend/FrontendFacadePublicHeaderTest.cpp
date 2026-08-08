// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

#include <cstdint>

static_assert(kFrontendLogMaxEntries > 0);
static_assert(kFrontendLogMaxBytes > 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceChangeKind::Added) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceChangeKind::Updated) == 1);
static_assert(static_cast<std::uint8_t>(FrontendInstanceChangeKind::Removed) == 2);
static_assert(static_cast<std::uint8_t>(FrontendLifecycleState::Running) == 0);
static_assert(static_cast<std::uint8_t>(FrontendLifecycleState::ShuttingDown) == 1);
static_assert(static_cast<std::uint8_t>(FrontendLifecycleState::Stopped) == 2);
static_assert(static_cast<std::uint8_t>(FrontendInstanceCommandResult::Succeeded) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceCommandResult::UnknownInstance) == 1);
static_assert(static_cast<std::uint8_t>(FrontendInstanceCommandResult::Rejected) == 2);
static_assert(static_cast<std::uint8_t>(FrontendInstanceNotesUpdateOutcome::Succeeded) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceNotesUpdateOutcome::UnknownInstance) == 1);
static_assert(static_cast<std::uint8_t>(FrontendInstanceNotesUpdateOutcome::Rejected) == 2);
static_assert(static_cast<std::uint8_t>(FrontendInstanceJoinTarget::None) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceJoinTarget::Server) == 1);
static_assert(static_cast<std::uint8_t>(FrontendInstanceJoinTarget::World) == 2);
static_assert(static_cast<std::uint8_t>(FrontendInstanceComponentProblemSeverity::None) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceComponentProblemSeverity::Warning) == 1);
static_assert(static_cast<std::uint8_t>(FrontendInstanceComponentProblemSeverity::Error) == 2);
static_assert(static_cast<std::uint8_t>(FrontendInstanceResourceKind::Mods) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceResourceKind::ResourcePacks) == 1);
static_assert(static_cast<std::uint8_t>(FrontendInstanceResourceKind::DataPacks) == 4);
static_assert(static_cast<std::uint8_t>(FrontendInstanceResourceAction::Enable) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceResourceAction::Reveal) == 4);
static_assert(static_cast<std::uint8_t>(FrontendInstanceResourceMutationOutcome::Succeeded) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceResourceMutationOutcome::Failed) == 4);
static_assert(static_cast<std::uint8_t>(FrontendInstanceDetailKind::Worlds) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceDetailKind::Logs) == 3);
static_assert(static_cast<std::uint8_t>(FrontendInstanceDetailAction::Add) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceDetailAction::CopyFiles) == 14);
static_assert(static_cast<std::uint8_t>(FrontendInstanceDetailMutationOutcome::Succeeded) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceDetailMutationOutcome::Failed) == 4);
static_assert(static_cast<std::uint8_t>(FrontendServerResourcePolicy::Ask) == 0);
static_assert(static_cast<std::uint8_t>(FrontendServerStatus::Online) == 1);
static_assert(static_cast<std::uint8_t>(FrontendInstanceSettingsUpdateOutcome::Succeeded) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceSettingsUpdateOutcome::UnknownInstance) == 1);
static_assert(static_cast<std::uint8_t>(FrontendInstanceSettingsUpdateOutcome::Rejected) == 2);
static_assert(static_cast<std::uint8_t>(FrontendTaskState::Queued) == 0);
static_assert(static_cast<std::uint8_t>(FrontendTaskState::Running) == 1);
static_assert(static_cast<std::uint8_t>(FrontendTaskState::Cancelling) == 2);
static_assert(static_cast<std::uint8_t>(FrontendTaskState::Succeeded) == 3);
static_assert(static_cast<std::uint8_t>(FrontendTaskState::Failed) == 4);
static_assert(static_cast<std::uint8_t>(FrontendTaskState::Cancelled) == 5);
static_assert(static_cast<std::uint8_t>(FrontendTaskProgressKind::None) == 0);
static_assert(static_cast<std::uint8_t>(FrontendTaskProgressKind::Indeterminate) == 1);
static_assert(static_cast<std::uint8_t>(FrontendTaskProgressKind::Determinate) == 2);
static_assert(static_cast<std::uint8_t>(FrontendTaskTerminalOutcome::Succeeded) == 0);
static_assert(static_cast<std::uint8_t>(FrontendTaskTerminalOutcome::Failed) == 1);
static_assert(static_cast<std::uint8_t>(FrontendTaskTerminalOutcome::Cancelled) == 2);
static_assert(static_cast<std::uint8_t>(FrontendTaskCancellationResult::Requested) == 0);
static_assert(static_cast<std::uint8_t>(FrontendTaskCancellationResult::AlreadyTerminal) == 1);
static_assert(static_cast<std::uint8_t>(FrontendTaskCancellationResult::UnknownTask) == 2);
static_assert(static_cast<std::uint8_t>(FrontendTaskCancellationResult::Rejected) == 3);

int main()
{
    const FrontendInstanceSnapshot snapshot{ "header-contract", "Header Contract", "", "" };
    const FrontendInstanceDetailsSnapshot details{ "header-contract", "Header Contract", "", "", "Minecraft", "", true };
    const FrontendInstanceComponentSnapshot component{ "component-contract", "Component Contract", "1.0", true,
                                                       false, false, true, false,
                                                       FrontendInstanceComponentProblemSeverity::None, {} };
    const FrontendInstanceResourceSnapshot resource{ "resource-contract", "Resource Contract", "1.0", "resource.zip", "Fixture",
                                                     FrontendInstanceResourceKind::Mods, true, true, true, false, true, {} };
    FrontendInstanceResourceMutationRequest mutationRequest;
    mutationRequest.resourceIdentifier = resource.id;
    mutationRequest.action = FrontendInstanceResourceAction::Reveal;
    const FrontendInstanceResourceMutationResult mutationResult{
        FrontendInstanceResourceKind::Mods,
        FrontendInstanceResourceAction::Reveal,
        FrontendInstanceResourceMutationOutcome::Rejected,
        "header-contract",
        resource.id,
        "resource.rejected",
        "fixture rejection",
        false,
    };
    const FrontendInstanceWorldSnapshot world{ "world-contract", "World Contract", "world", "Survival", "", "", 0, 0,
                                               0, false, false, true, true, true, false, false };
    const FrontendInstanceServerSnapshot server{ "server-contract", "Server Contract", "server.example",
                                                  FrontendServerResourcePolicy::Ask, FrontendServerStatus::Unknown, -1,
                                                  true, true, false };
    const FrontendInstanceScreenshotSnapshot screenshot{ "screenshot-contract", "fixture.png", "Fixture", 0, 0, true, true };
    const FrontendInstanceLogFileSnapshot logFile{ "log-contract", "latest.log", "Latest", 0, 0, false, true, true, false };
    const FrontendInstanceLogSnapshot instanceLog{ "header-contract", "log-contract", {}, 0, 0, false };
    FrontendInstanceDetailMutationRequest detailRequest;
    detailRequest.kind = FrontendInstanceDetailKind::Worlds;
    detailRequest.action = FrontendInstanceDetailAction::Reveal;
    detailRequest.itemIdentifier = world.id;
    const FrontendInstanceDetailMutationResult detailResult{
        FrontendInstanceDetailKind::Worlds,
        FrontendInstanceDetailAction::Reveal,
        FrontendInstanceDetailMutationOutcome::Rejected,
        "header-contract",
        world.id,
        "instance.detail.rejected",
        "fixture rejection",
        false,
    };
    FrontendInstanceSettingsSnapshot settings;
    settings.id = "header-contract";
    const FrontendInstanceChange change{ FrontendInstanceChangeKind::Added, snapshot };
    const FrontendLogSnapshot logSnapshot{ "header-contract", {}, 0, 0, false };
    const FrontendRuntimeDependencies dependencies;
    return snapshot.hasStableIdentifier() && details.hasStableIdentifier() && component.hasStableIdentifier()
            && resource.hasStableIdentifier() && mutationRequest.resourceIdentifier == resource.id
            && mutationResult.instanceIdentifier == "header-contract"
            && world.hasStableIdentifier() && server.hasStableIdentifier() && screenshot.hasStableIdentifier()
            && logFile.hasStableIdentifier() && instanceLog.instanceIdentifier == "header-contract"
            && detailRequest.itemIdentifier == world.id && detailResult.itemIdentifier == world.id
            && details.notesEditable
            && settings.hasStableIdentifier()
            && change.instance.id == snapshot.id && logSnapshot.hasStableIdentifier()
            && !dependencies.isComplete()
        ? 0
        : 1;
}
