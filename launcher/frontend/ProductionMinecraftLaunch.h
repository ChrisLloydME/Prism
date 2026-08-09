// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "ProductionLaunchRuntime.h"
#include "ProductionLaunchSession.h"

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

struct ProductionLaunchBuildResult final {
    std::optional<ProductionLaunchRuntime::ProcessSpec> process;
    std::vector<std::string> secrets;
    std::string diagnostic;
};

/// Load Prism's persisted component/patch format and build the same
/// NewLaunch EntryPoint command used by the legacy MinecraftInstance path.
/// The caller owns process execution; this function only performs bounded,
/// QWidget-free preparation against the supplied Native root.
ProductionLaunchBuildResult buildProductionMinecraftLaunch(
    const std::filesystem::path& dataRoot,
    const std::filesystem::path& instancePath,
    const std::string& instanceIdentifier,
    const ProductionLaunchSession& session);
