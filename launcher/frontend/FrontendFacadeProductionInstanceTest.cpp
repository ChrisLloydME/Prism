// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"
#include "ProductionInstanceRuntime.h"

#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string>

namespace {

std::filesystem::path temporaryRoot()
{
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    return std::filesystem::temp_directory_path() / ("prism-native-production-" + std::to_string(stamp));
}

bool contains(const std::vector<FrontendInstanceSnapshot>& snapshots, const std::string& identifier)
{
    for (const auto& snapshot : snapshots) {
        if (snapshot.id == identifier) {
            return true;
        }
    }
    return false;
}

}  // namespace

int main()
{
    const auto root = temporaryRoot();
    std::error_code cleanupError;
    try {
        std::filesystem::create_directories(root);
        FrontendFacade facade(root, productionInstanceRuntimeDependencies(root));

        const auto invalid = facade.createMetadataInstance({ "../escape", "Rejected", "default" });
        if (invalid.outcome != FrontendMetadataInstanceOutcome::InvalidInput || invalid.instance.has_value()) {
            throw std::runtime_error("path traversal was not rejected");
        }

        const auto first = facade.createMetadataInstance({ "native.metadata", "Native Metadata", "default" });
        if (first.outcome != FrontendMetadataInstanceOutcome::Succeeded || !first.instance.has_value()
            || first.instance->name != "Native Metadata") {
            throw std::runtime_error("metadata instance was not created");
        }

        std::mutex eventMutex;
        std::condition_variable eventCondition;
        bool observedAdded = false;
        if (!facade.startInstanceObservation([&](const FrontendInstanceChange& change) {
                if (change.kind == FrontendInstanceChangeKind::Added && change.instance.id == "native.observed") {
                    std::lock_guard<std::mutex> lock(eventMutex);
                    observedAdded = true;
                    eventCondition.notify_all();
                }
            })) {
            throw std::runtime_error("production observation did not start");
        }

        const auto second = facade.createMetadataInstance({ "native.observed", "Observed Metadata", "default" });
        if (second.outcome != FrontendMetadataInstanceOutcome::Succeeded) {
            throw std::runtime_error("observed metadata instance was not created");
        }
        {
            std::unique_lock<std::mutex> lock(eventMutex);
            if (!eventCondition.wait_for(lock, std::chrono::seconds(3), [&] { return observedAdded; })) {
                throw std::runtime_error("production observation did not report the created instance");
            }
        }

        facade.shutdown();
        FrontendFacade reconstructed(root, productionInstanceRuntimeDependencies(root));
        const auto snapshots = reconstructed.instanceSnapshots();
        if (snapshots.size() != 2 || !contains(snapshots, "native.metadata") || !contains(snapshots, "native.observed")) {
            throw std::runtime_error("reconstructed facade did not reload persisted instances");
        }
        reconstructed.shutdown();
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        std::filesystem::remove_all(root, cleanupError);
        return 1;
    }

    std::filesystem::remove_all(root, cleanupError);
    return cleanupError ? 1 : 0;
}
