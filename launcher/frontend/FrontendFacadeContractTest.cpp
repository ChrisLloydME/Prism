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

    auto emptyDependencies = makeFixtureDependencies();
    emptyDependencies.loadInstanceSnapshots = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceSnapshot>{};
    };
    emptyDependencies.loadInstanceChanges = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceChange>{};
    };
    FrontendFacade emptyFacade(fixtureRoot, std::move(emptyDependencies));
    const bool emptyContract = emptyFacade.instanceSnapshots().empty() && emptyFacade.instanceChanges().empty();

    const FrontendInstanceSnapshot firstInstance{ "fixture-one", "Fixture One", "grass", "group-a" };
    const FrontendInstanceSnapshot secondInstance{ "fixture-two", "Fixture Two", "stone", "" };
    bool snapshotRootMatches = false;
    bool changeRootMatches = false;
    auto fixtureDependencies = makeFixtureDependencies();
    fixtureDependencies.loadInstanceSnapshots = [&](const std::filesystem::path& root) {
        snapshotRootMatches = root == fixtureRoot.lexically_normal();
        return std::vector<FrontendInstanceSnapshot>{ firstInstance, secondInstance };
    };
    fixtureDependencies.loadInstanceChanges = [&](const std::filesystem::path& root) {
        changeRootMatches = root == fixtureRoot.lexically_normal();
        return std::vector<FrontendInstanceChange>{
            { FrontendInstanceChangeKind::Added, firstInstance },
            { FrontendInstanceChangeKind::Updated, secondInstance },
            { FrontendInstanceChangeKind::Removed, { secondInstance.id, {}, {}, {} } },
        };
    };
    FrontendFacade fixtureFacade(fixtureRoot / "nested" / "..", std::move(fixtureDependencies));
    const auto snapshots = fixtureFacade.instanceSnapshots();
    const auto changes = fixtureFacade.instanceChanges();
    const bool fixtureSnapshotContract = snapshots.size() == 2 && snapshots[0].id == "fixture-one"
        && snapshots[1].groupId.empty() && snapshotRootMatches;
    const bool fixtureChangeContract = changes.size() == 3 && changes[0].kind == FrontendInstanceChangeKind::Added
        && changes[1].kind == FrontendInstanceChangeKind::Updated && changes[2].kind == FrontendInstanceChangeKind::Removed
        && changes[2].instance.id == "fixture-two" && changeRootMatches;

    auto invalidSnapshotDependencies = makeFixtureDependencies();
    invalidSnapshotDependencies.loadInstanceSnapshots = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceSnapshot>{ { "", "Invalid", "", "" } };
    };
    FrontendFacade invalidSnapshotFacade(fixtureRoot, std::move(invalidSnapshotDependencies));
    const bool rejectedInvalidSnapshot = throwsInvalidArgument([&invalidSnapshotFacade] {
        (void) invalidSnapshotFacade.instanceSnapshots();
    });

    auto invalidChangeDependencies = makeFixtureDependencies();
    invalidChangeDependencies.loadInstanceChanges = [](const std::filesystem::path&) {
        return std::vector<FrontendInstanceChange>{
            { static_cast<FrontendInstanceChangeKind>(99), { "fixture-one", "", "", "" } },
        };
    };
    FrontendFacade invalidChangeFacade(fixtureRoot, std::move(invalidChangeDependencies));
    const bool rejectedInvalidChange = throwsInvalidArgument([&invalidChangeFacade] {
        (void) invalidChangeFacade.instanceChanges();
    });

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
    return fixtureWasPreserved && emptyContract && fixtureSnapshotContract && fixtureChangeContract && rejectedInvalidSnapshot
               && rejectedInvalidChange && rejectedEmptyRoot && rejectedRelativeRoot && rejectedIncompleteDependencies && !error
        ? 0
        : 4;
}
