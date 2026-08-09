// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <cstdint>
#include <string>
#include <vector>

/// C++-only launch identity. It never crosses the Objective-C++ bridge or
/// enters a frontend DTO, diagnostic, or persisted task record.
enum class ProductionLaunchMode : std::uint8_t { Normal, Offline, Demo };

struct ProductionLaunchSession final {
    ProductionLaunchMode mode = ProductionLaunchMode::Offline;
    std::string session = "-";
    std::string accessToken = "0";
    std::string playerName;
    std::string uuid;
    std::string userType = "offline";
    std::vector<std::string> secrets;
};
