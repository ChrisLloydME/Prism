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
    const FrontendInstanceChange change{ FrontendInstanceChangeKind::Added, snapshot };
    const FrontendLogSnapshot logSnapshot{ "header-contract", {}, 0, 0, false };
    const FrontendRuntimeDependencies dependencies;
    return snapshot.hasStableIdentifier() && details.hasStableIdentifier() && details.notesEditable
            && change.instance.id == snapshot.id && logSnapshot.hasStableIdentifier()
            && !dependencies.isComplete()
        ? 0
        : 1;
}
