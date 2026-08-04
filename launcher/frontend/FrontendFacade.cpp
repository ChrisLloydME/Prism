// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

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
