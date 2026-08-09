// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"

#include <chrono>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>

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

FrontendTaskSnapshot terminalProgress(
    const std::string& taskId,
    FrontendTaskState state,
    FrontendTaskTerminalOutcome outcome,
    const std::string& localizationKey)
{
    return FrontendTaskSnapshot{
        taskId,
        "Install Provider Pack",
        state,
        FrontendTaskProgressKind::Determinate,
        state == FrontendTaskState::Succeeded ? 1.0 : 0.5,
        false,
        {},
        FrontendTaskTerminalResult{ outcome, localizationKey, {}, {}, false },
    };
}

FrontendProviderInstallRecoveryPrompt filePrompt(FrontendProviderInstallRecoveryKind kind)
{
    FrontendProviderInstallRecoveryPrompt prompt;
    prompt.kind = kind;
    prompt.localizationKey = kind == FrontendProviderInstallRecoveryKind::OptionalFiles
        ? "providers.install.optionalFiles"
        : "providers.install.blockedFiles";
    prompt.diagnosticText = "Fixture file selection is required.";
    prompt.retryable = true;
    if (kind == FrontendProviderInstallRecoveryKind::OptionalFiles) {
        prompt.files = {
            { "optional-a", "Optional A", "mods/optional-a.jar", false, false, true },
            { "optional-b", "Optional B", "mods/optional-b.jar", false, false, false },
        };
    } else {
        prompt.files = {
            { "blocked-a", "Blocked A", "mods/blocked-a.jar", true, true, false },
        };
    }
    return prompt;
}

FrontendProviderInstallRecoveryPrompt errorPrompt(FrontendProviderInstallRecoveryKind kind)
{
    FrontendProviderInstallRecoveryPrompt prompt;
    prompt.kind = kind;
    prompt.localizationKey = kind == FrontendProviderInstallRecoveryKind::ProviderError
        ? "providers.install.providerError"
        : (kind == FrontendProviderInstallRecoveryKind::NetworkError ? "providers.install.networkError"
                                                                       : "providers.install.diskError");
    prompt.diagnosticText = "Fixture provider recovery is retryable.";
    prompt.retryable = true;
    return prompt;
}

FrontendProviderInstallResult succeeded(const FrontendProviderInstallRequest& request)
{
    FrontendProviderInstallResult result;
    result.kind = request.kind;
    result.outcome = FrontendProviderInstallOutcome::Succeeded;
    result.instance = FrontendInstanceSnapshot{
        "instance.recovery.fixture", request.name, request.iconKey, request.groupId };
    result.packIdentifier = request.packIdentifier;
    result.versionIdentifier = request.versionIdentifier;
    result.localizationKey = "providers.install.completed";
    return result;
}

FrontendProviderInstallResult failedWithPrompt(
    const FrontendProviderInstallRequest& request,
    FrontendProviderInstallRecoveryPrompt prompt,
    FrontendProviderInstallRollbackOutcome rollbackOutcome)
{
    FrontendProviderInstallResult result;
    result.kind = request.kind;
    result.outcome = FrontendProviderInstallOutcome::Failed;
    result.packIdentifier = request.packIdentifier;
    result.versionIdentifier = request.versionIdentifier;
    result.rollbackOutcome = rollbackOutcome;
    result.localizationKey = prompt.localizationKey;
    result.diagnosticText = prompt.diagnosticText;
    result.retryable = true;
    result.recoveryPrompt = std::move(prompt);
    return result;
}

void testProviderInstallRecoveryContract()
{
    const auto fixtureRoot = (std::filesystem::temp_directory_path() / "prism-native-m8-w6-recovery-fixture").lexically_normal();
    auto dependencies = makeDependencies();
    std::size_t progressEvents = 0;
    bool rootPreserved = true;
    dependencies.installProviderPack = [&](
                                             const std::filesystem::path& root,
                                             const FrontendProviderInstallRequest& request,
                                             const FrontendRuntimeDependencies::ProviderInstallProgressHandler& progress,
                                             const FrontendRuntimeDependencies::ProviderInstallCancellationCheck& isCancelled) {
        rootPreserved = rootPreserved && root == fixtureRoot;
        const auto taskId = "provider-recovery." + request.packIdentifier;
        progress(FrontendTaskSnapshot{
            taskId, "Install Provider Pack", FrontendTaskState::Running,
            FrontendTaskProgressKind::Determinate, 0.5, true, {}, std::nullopt });
        ++progressEvents;

        if (isCancelled && isCancelled()) {
            progress(terminalProgress(
                taskId, FrontendTaskState::Cancelled, FrontendTaskTerminalOutcome::Cancelled,
                "providers.install.cancelled"));
            ++progressEvents;
            FrontendProviderInstallResult result;
            result.kind = request.kind;
            result.outcome = FrontendProviderInstallOutcome::Cancelled;
            result.packIdentifier = request.packIdentifier;
            result.versionIdentifier = request.versionIdentifier;
            result.rollbackOutcome = FrontendProviderInstallRollbackOutcome::Applied;
            result.localizationKey = "providers.install.cancelled";
            result.diagnosticText = "Fixture installation cancelled.";
            return result;
        }

        const auto decision = request.recoveryDecision;
        if (request.packIdentifier == "optional.prompt" && !decision.has_value()) {
            progress(terminalProgress(
                taskId, FrontendTaskState::Failed, FrontendTaskTerminalOutcome::Failed,
                "providers.install.optionalFiles"));
            ++progressEvents;
            return failedWithPrompt(request, filePrompt(FrontendProviderInstallRecoveryKind::OptionalFiles),
                                    FrontendProviderInstallRollbackOutcome::NotRequired);
        }
        if (request.packIdentifier == "blocked.prompt" && !decision.has_value()) {
            progress(terminalProgress(
                taskId, FrontendTaskState::Failed, FrontendTaskTerminalOutcome::Failed,
                "providers.install.blockedFiles"));
            ++progressEvents;
            return failedWithPrompt(request, filePrompt(FrontendProviderInstallRecoveryKind::BlockedFiles),
                                    FrontendProviderInstallRollbackOutcome::NotRequired);
        }

        if (request.packIdentifier == "provider.prompt" && !decision.has_value()) {
            progress(terminalProgress(
                taskId, FrontendTaskState::Failed, FrontendTaskTerminalOutcome::Failed,
                "providers.install.providerError"));
            ++progressEvents;
            return failedWithPrompt(request, errorPrompt(FrontendProviderInstallRecoveryKind::ProviderError),
                                    FrontendProviderInstallRollbackOutcome::Applied);
        }
        if (request.packIdentifier == "network.prompt" && !decision.has_value()) {
            progress(terminalProgress(
                taskId, FrontendTaskState::Failed, FrontendTaskTerminalOutcome::Failed,
                "providers.install.networkError"));
            ++progressEvents;
            return failedWithPrompt(request, errorPrompt(FrontendProviderInstallRecoveryKind::NetworkError),
                                    FrontendProviderInstallRollbackOutcome::Applied);
        }
        if (request.packIdentifier == "disk.prompt" && !decision.has_value()) {
            progress(terminalProgress(
                taskId, FrontendTaskState::Failed, FrontendTaskTerminalOutcome::Failed,
                "providers.install.diskError"));
            ++progressEvents;
            return failedWithPrompt(request, errorPrompt(FrontendProviderInstallRecoveryKind::DiskError),
                                    FrontendProviderInstallRollbackOutcome::Failed);
        }

        if (request.packIdentifier == "optional.prompt") {
            require(decision->kind == FrontendProviderInstallRecoveryKind::OptionalFiles
                        && decision->action == FrontendProviderInstallRecoveryAction::Continue
                        && decision->selectedFileIdentifiers == std::vector<std::string>{ "optional-a" },
                    "optional file decision was not preserved");
        } else if (request.packIdentifier == "blocked.prompt") {
            require(decision->kind == FrontendProviderInstallRecoveryKind::BlockedFiles
                        && decision->action == FrontendProviderInstallRecoveryAction::Continue
                        && decision->resolvedBlockedFileIdentifiers == std::vector<std::string>{ "blocked-a" },
                    "blocked file decision was not preserved");
        } else if (request.packIdentifier == "provider.prompt" || request.packIdentifier == "network.prompt"
                   || request.packIdentifier == "disk.prompt") {
            require(decision->action == FrontendProviderInstallRecoveryAction::Retry,
                    "provider error decision did not request retry");
        }

        progress(terminalProgress(
            taskId, FrontendTaskState::Succeeded, FrontendTaskTerminalOutcome::Succeeded,
            "providers.install.completed"));
        ++progressEvents;
        return succeeded(request);
    };

    FrontendFacade facade(fixtureRoot / "nested" / "..", std::move(dependencies));
    auto makeRequest = [](const std::string& packIdentifier) {
        FrontendProviderInstallRequest request;
        request.kind = FrontendProviderInstallKind::Modrinth;
        request.packIdentifier = packIdentifier;
        request.versionIdentifier = "version.recovery";
        request.name = "Recovery Fixture";
        request.iconKey = "default";
        return request;
    };

    auto optionalRequest = makeRequest("optional.prompt");
    auto optionalFailure = facade.installProviderPack(optionalRequest);
    require(optionalFailure.outcome == FrontendProviderInstallOutcome::Failed
                && optionalFailure.recoveryPrompt.has_value()
                && optionalFailure.recoveryPrompt->kind == FrontendProviderInstallRecoveryKind::OptionalFiles
                && optionalFailure.rollbackOutcome == FrontendProviderInstallRollbackOutcome::NotRequired,
            "optional recovery prompt was not returned");
    optionalRequest.recoveryDecision = FrontendProviderInstallRecoveryDecision{
        FrontendProviderInstallRecoveryKind::OptionalFiles,
        FrontendProviderInstallRecoveryAction::Continue,
        { "optional-a" },
        {},
    };
    require(facade.installProviderPack(optionalRequest).outcome == FrontendProviderInstallOutcome::Succeeded,
            "optional recovery retry did not succeed");

    auto blockedRequest = makeRequest("blocked.prompt");
    require(facade.installProviderPack(blockedRequest).recoveryPrompt->kind
                == FrontendProviderInstallRecoveryKind::BlockedFiles,
            "blocked recovery prompt was not returned");
    blockedRequest.recoveryDecision = FrontendProviderInstallRecoveryDecision{
        FrontendProviderInstallRecoveryKind::BlockedFiles,
        FrontendProviderInstallRecoveryAction::Continue,
        {},
        { "blocked-a" },
    };
    require(facade.installProviderPack(blockedRequest).outcome == FrontendProviderInstallOutcome::Succeeded,
            "blocked recovery retry did not succeed");

    for (const auto& [packIdentifier, kind, rollback] : {
             std::tuple<std::string, FrontendProviderInstallRecoveryKind, FrontendProviderInstallRollbackOutcome>{
                 "provider.prompt", FrontendProviderInstallRecoveryKind::ProviderError,
                 FrontendProviderInstallRollbackOutcome::Applied },
             { "network.prompt", FrontendProviderInstallRecoveryKind::NetworkError,
               FrontendProviderInstallRollbackOutcome::Applied },
             { "disk.prompt", FrontendProviderInstallRecoveryKind::DiskError,
               FrontendProviderInstallRollbackOutcome::Failed },
         }) {
        auto request = makeRequest(packIdentifier);
        const auto failure = facade.installProviderPack(request);
        require(failure.recoveryPrompt.has_value() && failure.recoveryPrompt->kind == kind
                    && failure.rollbackOutcome == rollback,
                "provider recovery category or rollback was not preserved");
        request.recoveryDecision = FrontendProviderInstallRecoveryDecision{
            kind, FrontendProviderInstallRecoveryAction::Retry, {}, {} };
        require(facade.installProviderPack(request).outcome == FrontendProviderInstallOutcome::Succeeded,
                "provider error recovery retry did not succeed");
    }

    auto cancelledRequest = makeRequest("cancelled.recovery");
    const auto cancelled = facade.installProviderPack(cancelledRequest, {}, [] { return true; });
    require(cancelled.outcome == FrontendProviderInstallOutcome::Cancelled
                && cancelled.rollbackOutcome == FrontendProviderInstallRollbackOutcome::Applied,
            "provider cancellation rollback was not preserved");

    bool invalidDecisionRejected = false;
    try {
        auto invalidRequest = makeRequest("invalid.decision");
        invalidRequest.recoveryDecision = FrontendProviderInstallRecoveryDecision{
            FrontendProviderInstallRecoveryKind::ProviderError,
            FrontendProviderInstallRecoveryAction::Continue,
            {},
            {},
        };
        (void) facade.installProviderPack(invalidRequest);
    } catch (const std::invalid_argument&) {
        invalidDecisionRejected = true;
    }
    require(invalidDecisionRejected && rootPreserved && progressEvents >= 20,
            "provider recovery fixture evidence was incomplete");
}

}  // namespace

int main()
{
    try {
        testProviderInstallRecoveryContract();
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
    return 0;
}
