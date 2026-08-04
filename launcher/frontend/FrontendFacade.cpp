// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

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

FrontendFacade::~FrontendFacade() noexcept = default;

std::vector<FrontendInstanceSnapshot> FrontendFacade::instanceSnapshots() const
{
    if (!m_runtimeDependencies.loadInstanceSnapshots) {
        return {};
    }

    auto snapshots = m_runtimeDependencies.loadInstanceSnapshots(m_dataRoot);
    validateInstanceSnapshots(snapshots);
    return snapshots;
}

std::vector<FrontendInstanceChange> FrontendFacade::instanceChanges() const
{
    if (!m_runtimeDependencies.loadInstanceChanges) {
        return {};
    }

    auto changes = m_runtimeDependencies.loadInstanceChanges(m_dataRoot);
    validateInstanceChanges(changes);
    return changes;
}
