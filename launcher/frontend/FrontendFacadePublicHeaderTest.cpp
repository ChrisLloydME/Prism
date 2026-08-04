// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

#include <cstdint>

static_assert(static_cast<std::uint8_t>(FrontendInstanceChangeKind::Added) == 0);
static_assert(static_cast<std::uint8_t>(FrontendInstanceChangeKind::Updated) == 1);
static_assert(static_cast<std::uint8_t>(FrontendInstanceChangeKind::Removed) == 2);
static_assert(static_cast<std::uint8_t>(FrontendLifecycleState::Running) == 0);
static_assert(static_cast<std::uint8_t>(FrontendLifecycleState::ShuttingDown) == 1);
static_assert(static_cast<std::uint8_t>(FrontendLifecycleState::Stopped) == 2);

int main()
{
    const FrontendInstanceSnapshot snapshot{ "header-contract", "Header Contract", "", "" };
    const FrontendInstanceChange change{ FrontendInstanceChangeKind::Added, snapshot };
    const FrontendRuntimeDependencies dependencies;
    return snapshot.hasStableIdentifier() && change.instance.id == snapshot.id && !dependencies.isComplete() ? 0 : 1;
}
