// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <utility>

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

FrontendRuntimeDependencies makeFixtureDependencies()
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::time_point{}; };
    return dependencies;
}

template <typename Function>
bool throwsInvalidArgument(Function&& function)
{
    try {
        function();
    } catch (const std::invalid_argument&) {
        return true;
    }
    return false;
}

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
        FrontendFacade facade(fixtureRoot / "nested" / "..", makeFixtureDependencies());
        if (facade.dataRoot() != fixtureRoot.lexically_normal() || !facade.hasRuntimeDependencies()) {
            std::filesystem::remove(fixtureMarker, error);
            std::filesystem::remove(fixtureRoot, error);
            return 3;
        }
    }

    const bool fixtureWasPreserved = std::filesystem::exists(fixtureMarker);
    const bool rejectedEmptyRoot = throwsInvalidArgument([] {
        FrontendFacade facade({}, makeFixtureDependencies());
        (void) facade;
    });
    const bool rejectedRelativeRoot = throwsInvalidArgument([] {
        FrontendFacade facade(std::filesystem::path("relative-fixture-root"), makeFixtureDependencies());
        (void) facade;
    });
    const bool rejectedIncompleteDependencies = throwsInvalidArgument([&fixtureRoot] {
        FrontendFacade facade(fixtureRoot, {});
        (void) facade;
    });

    std::filesystem::remove(fixtureMarker, error);
    std::filesystem::remove(fixtureRoot, error);
    return fixtureWasPreserved && rejectedEmptyRoot && rejectedRelativeRoot && rejectedIncompleteDependencies && !error ? 0
                                                                                                                       : 4;
}
