// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <string>
#include <system_error>

namespace {

std::filesystem::path makeFixtureRoot(std::error_code& error)
{
    const auto temporaryRoot = std::filesystem::temp_directory_path(error);
    if (error) {
        return {};
    }

    const auto suffix = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto fixtureRoot = temporaryRoot / ("prism-frontend-contract-" + std::to_string(suffix));
    if (!std::filesystem::create_directory(fixtureRoot, error)) {
        return {};
    }
    return fixtureRoot;
}

}  // namespace

int main()
{
    std::error_code error;
    const auto fixtureRoot = makeFixtureRoot(error);
    if (error || fixtureRoot.empty()) {
        return 1;
    }

    const auto fixtureMarker = fixtureRoot / "fixture.marker";
    {
        std::ofstream marker(fixtureMarker);
        if (!marker) {
            std::filesystem::remove(fixtureRoot, error);
            return 2;
        }
        marker << "temporary fixture";
    }

    {
        FrontendFacade facade;
        (void) facade;
    }

    const bool fixtureWasPreserved = std::filesystem::exists(fixtureMarker);
    std::filesystem::remove(fixtureMarker, error);
    std::filesystem::remove(fixtureRoot, error);
    return fixtureWasPreserved && !error ? 0 : 3;
}
