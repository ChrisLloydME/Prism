// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <string>
#include <stdexcept>
#include <system_error>
#include <vector>

namespace {

std::filesystem::path makeFixtureRoot(std::error_code& error)
{
    const auto root = std::filesystem::temp_directory_path(error);
    if (error) {
        return {};
    }

    const auto suffix = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto fixtureRoot = root / ("prism-instance-detail-contract-" + std::to_string(suffix));
    std::filesystem::create_directories(fixtureRoot / "world-one", error);
    return error ? std::filesystem::path{} : fixtureRoot;
}

FrontendRuntimeDependencies makeDependencies()
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::time_point{}; };
    dependencies.cancelPendingWork = [] {};
    dependencies.shutdown = [] {};
    return dependencies;
}

bool throwsInvalidArgument(auto&& function)
{
    try {
        function();
    } catch (const std::invalid_argument&) {
        return true;
    }
    return false;
}

bool throwsLogicError(auto&& function)
{
    try {
        function();
    } catch (const std::logic_error&) {
        return true;
    }
    return false;
}

}  // namespace

int main()
{
    std::error_code error;
    const auto fixtureRoot = makeFixtureRoot(error);
    if (error || fixtureRoot.empty()) {
        return 1;
    }
    {
        std::ofstream importFile(fixtureRoot / "world-import.zip");
        importFile << "temporary world archive";
    }
    {
        std::ofstream invalidArchive(fixtureRoot / "invalid-world.zip");
        invalidArchive << "not a valid zip archive";
    }

    auto dependencies = makeDependencies();
    bool rootMatches = true;
    std::vector<std::string> calls;
    dependencies.loadInstanceWorlds = [&](const std::filesystem::path& root, const std::string& identifier)
        -> std::optional<std::vector<FrontendInstanceWorldSnapshot>> {
        rootMatches = rootMatches && root == fixtureRoot.lexically_normal();
        calls.push_back("worlds:" + identifier);
        if (identifier != "fixture.one") {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceWorldSnapshot>{
            { "world.one", "Fixture World", "world-one", "Survival", "grass", "", 1700000000, 4096, 1234, true,
              false, true, true, true, true, true },
            { "world.archive", "Fixture Archive", "archive.zip", "Creative", "", "Archive world", 0, 128, 0, false,
              true, false, true, true, false },
        };
    };
    dependencies.loadInstanceServers = [&](const std::filesystem::path& root, const std::string& identifier)
        -> std::optional<std::vector<FrontendInstanceServerSnapshot>> {
        rootMatches = rootMatches && root == fixtureRoot.lexically_normal();
        calls.push_back("servers:" + identifier);
        if (identifier != "fixture.one") {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceServerSnapshot>{
            { "server.one", "Fixture Server", "fixture.example:25565", FrontendServerResourcePolicy::Ask,
              FrontendServerStatus::Online, 4, true, true, false },
        };
    };
    dependencies.loadInstanceScreenshots = [&](const std::filesystem::path& root, const std::string& identifier)
        -> std::optional<std::vector<FrontendInstanceScreenshotSnapshot>> {
        rootMatches = rootMatches && root == fixtureRoot.lexically_normal();
        calls.push_back("screenshots:" + identifier);
        if (identifier != "fixture.one") {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceScreenshotSnapshot>{
            { "screenshot.one", "2026-08-09.png", "2026-08-09", 1700000000, 1024, true, true },
        };
    };
    dependencies.loadInstanceLogFiles = [&](const std::filesystem::path& root, const std::string& identifier)
        -> std::optional<std::vector<FrontendInstanceLogFileSnapshot>> {
        rootMatches = rootMatches && root == fixtureRoot.lexically_normal();
        calls.push_back("logs:" + identifier);
        if (identifier != "fixture.one") {
            return std::nullopt;
        }
        return std::vector<FrontendInstanceLogFileSnapshot>{
            { "latest.log", "latest.log", "Current Log", 1700000000, 2048, false, true, true, false },
            { "2026-08-09.log.gz", "2026-08-09.log.gz", "2026-08-09", 1699990000, 512, true, false, true, true },
        };
    };
    dependencies.loadInstanceLog = [&](const std::filesystem::path& root,
                                       const std::string& instanceIdentifier,
                                       const std::string& logIdentifier) -> std::optional<FrontendInstanceLogSnapshot> {
        rootMatches = rootMatches && root == fixtureRoot.lexically_normal();
        if (instanceIdentifier != "fixture.one" || logIdentifier != "latest.log") {
            return std::nullopt;
        }
        return FrontendInstanceLogSnapshot{
            instanceIdentifier,
            logIdentifier,
            { { 1, "fixture log line", false }, { 2, "second fixture line", false } },
            0,
            35,
            false,
        };
    };
    dependencies.mutateInstanceDetail = [&](const std::filesystem::path& root,
                                             const std::string& instanceIdentifier,
                                             const FrontendInstanceDetailMutationRequest& request) {
        rootMatches = rootMatches && root == fixtureRoot.lexically_normal();
        if (request.itemIdentifier == "world.permission") {
            return FrontendInstanceDetailMutationResult{
                request.kind,
                request.action,
                FrontendInstanceDetailMutationOutcome::Rejected,
                instanceIdentifier,
                request.itemIdentifier,
                "instance.world.deletePermissionDenied",
                "fixture permission denied",
                false,
            };
        }
        if (request.itemIdentifier == "screenshot.missing") {
            return FrontendInstanceDetailMutationResult{
                request.kind,
                request.action,
                FrontendInstanceDetailMutationOutcome::UnknownItem,
                instanceIdentifier,
                request.itemIdentifier,
                "instance.screenshot.missing",
                "fixture screenshot is missing",
                false,
            };
        }
        if (request.itemIdentifier == "server.conflict") {
            return FrontendInstanceDetailMutationResult{
                request.kind,
                request.action,
                FrontendInstanceDetailMutationOutcome::Failed,
                instanceIdentifier,
                request.itemIdentifier,
                "instance.server.updateConflict",
                "fixture server changed externally",
                true,
            };
        }
        if (request.itemIdentifier == "invalid-world.zip") {
            std::ifstream archive(request.sourcePath);
            std::string archiveContents;
            std::getline(archive, archiveContents);
            if (archiveContents != "temporary world archive") {
                return FrontendInstanceDetailMutationResult{
                    request.kind,
                    request.action,
                    FrontendInstanceDetailMutationOutcome::Failed,
                    instanceIdentifier,
                    request.itemIdentifier,
                    "instance.world.importInvalidArchive",
                    "fixture archive is not a valid world archive",
                    false,
                };
            }
        }
        if (request.kind == FrontendInstanceDetailKind::Worlds
            && request.action == FrontendInstanceDetailAction::Delete) {
            std::filesystem::remove_all(root / "world-one", error);
        }
        if (request.kind == FrontendInstanceDetailKind::Worlds
            && request.action == FrontendInstanceDetailAction::Import) {
            std::filesystem::copy_file(request.sourcePath, root / "world-imported.zip",
                                       std::filesystem::copy_options::overwrite_existing, error);
        }
        return FrontendInstanceDetailMutationResult{
            request.kind,
            request.action,
            FrontendInstanceDetailMutationOutcome::Succeeded,
            instanceIdentifier,
            request.itemIdentifier.empty() ? "server.added" : request.itemIdentifier,
            "instance.detail.updated",
            "fixture detail mutation succeeded",
            false,
        };
    };

    FrontendFacade facade(fixtureRoot / "nested" / "..", std::move(dependencies));
    const auto worlds = facade.instanceWorlds("fixture.one");
    const auto servers = facade.instanceServers("fixture.one");
    const auto screenshots = facade.instanceScreenshots("fixture.one");
    const auto logs = facade.instanceLogFiles("fixture.one");
    const auto log = facade.instanceLog("fixture.one", "latest.log");

    FrontendInstanceDetailMutationRequest deleteWorld;
    deleteWorld.kind = FrontendInstanceDetailKind::Worlds;
    deleteWorld.action = FrontendInstanceDetailAction::Delete;
    deleteWorld.itemIdentifier = "world.one";
    const bool rejectedUnconfirmedDelete = throwsInvalidArgument([&] { (void) facade.mutateInstanceDetail("fixture.one", deleteWorld); });
    deleteWorld.confirmed = true;
    const auto deleteResult = facade.mutateInstanceDetail("fixture.one", deleteWorld);

    FrontendInstanceDetailMutationRequest importWorld;
    importWorld.kind = FrontendInstanceDetailKind::Worlds;
    importWorld.action = FrontendInstanceDetailAction::Import;
    importWorld.itemIdentifier = "world-import.zip";
    importWorld.sourcePath = fixtureRoot / "world-import.zip";
    const auto importResult = facade.mutateInstanceDetail("fixture.one", importWorld);

    FrontendInstanceDetailMutationRequest updateServer;
    updateServer.kind = FrontendInstanceDetailKind::Servers;
    updateServer.action = FrontendInstanceDetailAction::Update;
    updateServer.itemIdentifier = "server.one";
    updateServer.name = "Updated Server";
    updateServer.address = "updated.example:25565";
    const auto updateResult = facade.mutateInstanceDetail("fixture.one", updateServer);

    FrontendInstanceDetailMutationRequest permissionDelete = deleteWorld;
    permissionDelete.itemIdentifier = "world.permission";
    const auto permissionResult = facade.mutateInstanceDetail("fixture.one", permissionDelete);

    FrontendInstanceDetailMutationRequest missingScreenshot;
    missingScreenshot.kind = FrontendInstanceDetailKind::Screenshots;
    missingScreenshot.action = FrontendInstanceDetailAction::Delete;
    missingScreenshot.itemIdentifier = "screenshot.missing";
    missingScreenshot.confirmed = true;
    const auto missingScreenshotResult = facade.mutateInstanceDetail("fixture.one", missingScreenshot);

    FrontendInstanceDetailMutationRequest conflictingServer = updateServer;
    conflictingServer.itemIdentifier = "server.conflict";
    const auto conflictResult = facade.mutateInstanceDetail("fixture.one", conflictingServer);

    FrontendInstanceDetailMutationRequest invalidArchiveImport = importWorld;
    invalidArchiveImport.itemIdentifier = "invalid-world.zip";
    invalidArchiveImport.sourcePath = fixtureRoot / "invalid-world.zip";
    const auto invalidArchiveResult = facade.mutateInstanceDetail("fixture.one", invalidArchiveImport);

    FrontendInstanceDetailMutationRequest relativeImport = importWorld;
    relativeImport.sourcePath = "relative.zip";
    const bool rejectedRelativeImport = throwsInvalidArgument([&] { (void) facade.mutateInstanceDetail("fixture.one", relativeImport); });
    FrontendInstanceDetailMutationRequest invalidKind = updateServer;
    invalidKind.kind = FrontendInstanceDetailKind::Logs;
    const bool rejectedWrongKind = throwsInvalidArgument([&] { (void) facade.mutateInstanceDetail("fixture.one", invalidKind); });

    auto invalidDependencies = makeDependencies();
    invalidDependencies.loadInstanceServers = [](const std::filesystem::path&, const std::string&)
        -> std::optional<std::vector<FrontendInstanceServerSnapshot>> {
        return std::vector<FrontendInstanceServerSnapshot>{
            { "duplicate", "First", "one.example", FrontendServerResourcePolicy::Ask, FrontendServerStatus::Unknown, -1, true, true, false },
            { "duplicate", "Second", "two.example", FrontendServerResourcePolicy::Ask, FrontendServerStatus::Unknown, -1, true, true, false },
        };
    };
    FrontendFacade invalidFacade(fixtureRoot, std::move(invalidDependencies));
    const bool rejectedDuplicateServers = throwsInvalidArgument([&] { (void) invalidFacade.instanceServers("fixture.one"); });

    auto missingDependencies = makeDependencies();
    FrontendFacade missingFacade(fixtureRoot, std::move(missingDependencies));
    const bool missingPortsSafe = !missingFacade.instanceWorlds("fixture.one").has_value()
        && missingFacade.mutateInstanceDetail("fixture.one", deleteWorld).outcome
            == FrontendInstanceDetailMutationOutcome::Rejected;

    const bool contract = rootMatches && worlds.has_value() && worlds->size() == 2 && worlds->at(0).hasSeed
        && worlds->at(1).isArchive && servers.has_value() && servers->at(0).status == FrontendServerStatus::Online
        && servers->at(0).onlinePlayers == 4 && screenshots.has_value() && screenshots->at(0).writable
        && logs.has_value() && logs->size() == 2 && logs->at(1).compressed && log.has_value()
        && log->entries.size() == 2 && log->entries.at(0).text == "fixture log line"
        && rejectedUnconfirmedDelete && deleteResult.outcome == FrontendInstanceDetailMutationOutcome::Succeeded
        && importResult.outcome == FrontendInstanceDetailMutationOutcome::Succeeded
        && updateResult.outcome == FrontendInstanceDetailMutationOutcome::Succeeded
        && std::filesystem::exists(fixtureRoot / "world-imported.zip")
        && !std::filesystem::exists(fixtureRoot / "world-one") && rejectedRelativeImport && rejectedWrongKind
        && rejectedDuplicateServers && missingPortsSafe && calls.size() == 4;

    const bool failureScenarioContract = permissionResult.outcome == FrontendInstanceDetailMutationOutcome::Rejected
        && permissionResult.localizationKey == "instance.world.deletePermissionDenied"
        && permissionResult.diagnosticText == "fixture permission denied"
        && missingScreenshotResult.outcome == FrontendInstanceDetailMutationOutcome::UnknownItem
        && missingScreenshotResult.localizationKey == "instance.screenshot.missing"
        && conflictResult.outcome == FrontendInstanceDetailMutationOutcome::Failed
        && conflictResult.localizationKey == "instance.server.updateConflict"
        && conflictResult.partialChangesRolledBack
        && invalidArchiveResult.outcome == FrontendInstanceDetailMutationOutcome::Failed
        && invalidArchiveResult.localizationKey == "instance.world.importInvalidArchive"
        && !invalidArchiveResult.partialChangesRolledBack
        && std::filesystem::exists(fixtureRoot / "invalid-world.zip")
        && !std::filesystem::exists(fixtureRoot / "invalid-world-imported.zip");

    const bool shutdownContract = facade.shutdown()
        && throwsLogicError([&] { (void) facade.instanceWorlds("fixture.one"); })
        && throwsLogicError([&] { (void) facade.instanceLog("fixture.one", "latest.log"); });

    std::filesystem::remove_all(fixtureRoot, error);
    return contract && failureScenarioContract && shutdownContract && !error ? 0 : 2;
}
