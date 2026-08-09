// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

#include <chrono>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

void require(bool condition, const char* message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

FrontendRuntimeDependencies makeDependencies()
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](std::function<void()> work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::now(); };
    dependencies.cancelPendingWork = [] {};
    dependencies.shutdown = [] {};
    return dependencies;
}

FrontendTaskSnapshot progressSnapshot(
    const std::string& taskId,
    FrontendTaskState state,
    std::optional<FrontendTaskTerminalResult> terminal = std::nullopt)
{
    return FrontendTaskSnapshot{
        taskId,
        "Install Provider Pack",
        state,
        state == FrontendTaskState::Queued ? FrontendTaskProgressKind::None : FrontendTaskProgressKind::Determinate,
        state == FrontendTaskState::Queued ? 0.0 : (state == FrontendTaskState::Succeeded ? 1.0 : 0.5),
        state == FrontendTaskState::Queued || state == FrontendTaskState::Running,
        {},
        std::move(terminal),
    };
}

FrontendProviderInstallResult installResult(
    const FrontendProviderInstallRequest& request,
    FrontendProviderInstallOutcome outcome,
    FrontendProviderInstallRollbackOutcome rollbackOutcome,
    std::string localizationKey,
    std::string diagnosticText = {},
    bool retryable = false)
{
    FrontendProviderInstallResult result;
    result.kind = request.kind;
    result.outcome = outcome;
    result.packIdentifier = request.packIdentifier;
    result.versionIdentifier = request.versionIdentifier;
    result.rollbackOutcome = rollbackOutcome;
    result.localizationKey = std::move(localizationKey);
    result.diagnosticText = std::move(diagnosticText);
    result.retryable = retryable;
    if (outcome == FrontendProviderInstallOutcome::Succeeded) {
        result.instance = FrontendInstanceSnapshot{
            "instance.fixture." + request.packIdentifier,
            request.name,
            request.iconKey,
            request.groupId,
        };
    }
    return result;
}

void testProviderInstallContract()
{
    const auto fixtureRoot = (std::filesystem::temp_directory_path() / "prism-native-m8-w5-fixture").lexically_normal();
    const auto customArchive = fixtureRoot / "custom-pack.fixture.zip";
    const std::vector<FrontendProviderInstallKind> kinds{
        FrontendProviderInstallKind::Modrinth,
        FrontendProviderInstallKind::CurseForgeFlame,
        FrontendProviderInstallKind::FTB,
        FrontendProviderInstallKind::LegacyFTB,
        FrontendProviderInstallKind::FTBImport,
        FrontendProviderInstallKind::ATLauncher,
        FrontendProviderInstallKind::TechnicZip,
        FrontendProviderInstallKind::TechnicSolder,
        FrontendProviderInstallKind::CustomArchive,
    };

    auto dependencies = makeDependencies();
    std::size_t calls = 0;
    std::size_t progressEvents = 0;
    bool rootPreserved = true;
    bool requestPreserved = true;
    bool cancellationObserved = false;
    dependencies.installProviderPack = [&](
                                             const std::filesystem::path& root,
                                             const FrontendProviderInstallRequest& request,
                                             const FrontendRuntimeDependencies::ProviderInstallProgressHandler& progress,
                                             const FrontendRuntimeDependencies::ProviderInstallCancellationCheck& isCancelled) {
        ++calls;
        rootPreserved = rootPreserved && root == fixtureRoot;
        const bool requiresLocalSource = request.kind == FrontendProviderInstallKind::CustomArchive
            || request.kind == FrontendProviderInstallKind::FTBImport;
        requestPreserved = requestPreserved && !request.packIdentifier.empty() && !request.versionIdentifier.empty()
            && !request.name.empty() && !request.iconKey.empty()
            && (requiresLocalSource == !request.sourcePath.empty());

        const std::string taskId = "provider-install." + request.packIdentifier;
        progress(progressSnapshot(taskId, FrontendTaskState::Queued));
        ++progressEvents;
        progress(progressSnapshot(taskId, FrontendTaskState::Running));
        ++progressEvents;

        if (isCancelled && isCancelled()) {
            cancellationObserved = true;
            progress(progressSnapshot(
                taskId,
                FrontendTaskState::Cancelled,
                FrontendTaskTerminalResult{
                    FrontendTaskTerminalOutcome::Cancelled,
                    "providers.install.cancelled",
                    {},
                    "Fixture installation cancelled",
                    false,
                }));
            ++progressEvents;
            return installResult(
                request,
                FrontendProviderInstallOutcome::Cancelled,
                FrontendProviderInstallRollbackOutcome::Applied,
                "providers.install.cancelled",
                "Fixture installation cancelled");
        }

        if (request.packIdentifier == "fixture.failure") {
            progress(progressSnapshot(
                taskId,
                FrontendTaskState::Failed,
                FrontendTaskTerminalResult{
                    FrontendTaskTerminalOutcome::Failed,
                    "providers.install.failed",
                    {},
                    "Fixture installation failed",
                    true,
                }));
            ++progressEvents;
            return installResult(
                request,
                FrontendProviderInstallOutcome::Failed,
                FrontendProviderInstallRollbackOutcome::Applied,
                "providers.install.failed",
                "Fixture installation failed",
                true);
        }

        progress(progressSnapshot(
            taskId,
            FrontendTaskState::Succeeded,
            FrontendTaskTerminalResult{
                FrontendTaskTerminalOutcome::Succeeded,
                "providers.install.completed",
                {},
                {},
                false,
            }));
        ++progressEvents;
        return installResult(
            request,
            FrontendProviderInstallOutcome::Succeeded,
            FrontendProviderInstallRollbackOutcome::NotRequired,
            "providers.install.completed");
    };

    FrontendFacade facade(fixtureRoot / "nested" / "..", std::move(dependencies));
    for (std::size_t index = 0; index < kinds.size(); ++index) {
        FrontendProviderInstallRequest request;
        request.kind = kinds[index];
        request.packIdentifier = "pack.fixture." + std::to_string(index);
        request.versionIdentifier = "version.fixture." + std::to_string(index);
        request.name = "Fixture Pack " + std::to_string(index);
        request.groupId = "fixture-group";
        request.iconKey = "fixture-icon";
        if (request.kind == FrontendProviderInstallKind::CustomArchive) {
            request.sourcePath = customArchive;
        } else if (request.kind == FrontendProviderInstallKind::FTBImport) {
            request.sourcePath = fixtureRoot / "ftb-app.fixture";
        }

        std::size_t receivedProgress = 0;
        const auto result = facade.installProviderPack(request, [&](const FrontendTaskSnapshot&) { ++receivedProgress; });
        require(result.outcome == FrontendProviderInstallOutcome::Succeeded, "provider install success missing");
        require(result.instance.has_value(), "provider install instance missing");
        require(result.kind == request.kind && result.packIdentifier == request.packIdentifier
                    && result.versionIdentifier == request.versionIdentifier,
                "provider install identity was not echoed");
        require(receivedProgress == 3, "provider install progress was not forwarded");
    }

    FrontendProviderInstallRequest failureRequest;
    failureRequest.kind = FrontendProviderInstallKind::CurseForgeFlame;
    failureRequest.packIdentifier = "fixture.failure";
    failureRequest.versionIdentifier = "version.failure";
    failureRequest.name = "Fixture Failure";
    failureRequest.iconKey = "fixture-icon";
    const auto failure = facade.installProviderPack(failureRequest);
    require(failure.outcome == FrontendProviderInstallOutcome::Failed && !failure.instance.has_value()
                && failure.rollbackOutcome == FrontendProviderInstallRollbackOutcome::Applied && failure.retryable,
            "provider install failure did not report rollback");

    FrontendProviderInstallRequest cancelledRequest = failureRequest;
    cancelledRequest.packIdentifier = "pack.cancelled";
    const auto cancelled = facade.installProviderPack(cancelledRequest, {}, [] { return true; });
    require(cancelled.outcome == FrontendProviderInstallOutcome::Cancelled && !cancelled.instance.has_value()
                && cancelled.rollbackOutcome == FrontendProviderInstallRollbackOutcome::Applied,
            "provider install cancellation did not report rollback");

    auto noRunnerDependencies = makeDependencies();
    FrontendFacade noRunnerFacade(fixtureRoot, std::move(noRunnerDependencies));
    require(noRunnerFacade.installProviderPack(failureRequest).outcome == FrontendProviderInstallOutcome::Rejected,
            "missing provider install runner was not rejected");

    bool invalidRequestRejected = false;
    try {
        auto invalid = failureRequest;
        invalid.sourcePath = std::filesystem::path("relative.fixture.zip");
        invalid.kind = FrontendProviderInstallKind::CustomArchive;
        (void) facade.installProviderPack(invalid);
    } catch (const std::invalid_argument&) {
        invalidRequestRejected = true;
    }
    require(invalidRequestRejected, "relative custom archive path was accepted");

    require(calls == kinds.size() + 2 && progressEvents == (kinds.size() * 3) + 6 && rootPreserved
                && requestPreserved && cancellationObserved,
            "provider install fixture evidence was incomplete");
}

}  // namespace

int main()
{
    try {
        testProviderInstallContract();
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
    return 0;
}
