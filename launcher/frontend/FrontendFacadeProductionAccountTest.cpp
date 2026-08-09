// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"
#include "ProductionAccountRuntime.h"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

void require(bool condition, const char* message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

void writeSyntheticAccounts(const std::filesystem::path& root)
{
    std::ofstream file(root / "accounts.json");
    file << R"JSON({
  "formatVersion": 3,
  "accounts": [
    {
      "type": "Offline",
      "profile": {
        "id": "offline.profile",
        "name": "Offline_Player",
        "skin": { "id": "", "url": "", "variant": "" },
        "capes": []
      },
      "active": true
    },
    {
      "type": "MSA",
      "msa-client-id": "synthetic-client",
      "profile": {
        "id": "microsoft.profile",
        "name": "Microsoft_Player",
        "skin": { "id": "", "url": "", "variant": "" },
        "capes": []
      },
      "entitlement": { "ownsMinecraft": true, "canPlayMinecraft": true },
      "active": false
    }
  ]
})JSON";
    require(file.good(), "synthetic account file could not be written");
}

FrontendRuntimeDependencies accountDependencies(
    const std::filesystem::path& root, const std::shared_ptr<ProductionAccountRuntime>& runtime)
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::now(); };
    dependencies.cancelPendingWork = [] {};
    dependencies.shutdown = [runtime] { runtime->shutdown(); };
    static_cast<void>(root);
    return productionAccountRuntimeDependencies(runtime, std::move(dependencies));
}

}  // namespace

int main()
{
    const auto root = std::filesystem::temp_directory_path() / "prism-native-account-production-contract";
    std::error_code cleanupError;
    std::filesystem::remove_all(root, cleanupError);
    std::filesystem::create_directories(root);
    writeSyntheticAccounts(root);

    std::optional<std::string> storedCredential;
    std::vector<std::string> browserURLs;
    std::size_t waitCalls = 0;
    bool failRefresh = false;

    try {
        auto dependencies = ProductionAccountRuntime::defaultDependencies();
        dependencies.browser = [&browserURLs](const std::string& url) {
            browserURLs.push_back(url);
            return true;
        };
        dependencies.wait = [&waitCalls](std::chrono::seconds) { ++waitCalls; };
        dependencies.keychain.read = [&storedCredential](const std::string&) { return storedCredential; };
        dependencies.keychain.write = [&storedCredential](const std::string&, const std::string& value) {
            storedCredential = value;
            return true;
        };
        dependencies.keychain.erase = [&storedCredential](const std::string&) {
            storedCredential.reset();
            return true;
        };
        dependencies.http = [&failRefresh](const ProductionAccountRuntime::HttpRequest& request) {
            ProductionAccountRuntime::HttpResponse response;
            response.transportSucceeded = true;
            response.statusCode = 200;
            if (request.url.find("devicecode") != std::string::npos) {
                response.body =
                    R"JSON({"verification_uri":"https://login.example.invalid/device","verification_uri_complete":"https://login.example.invalid/device?flow=synthetic","device_code":"synthetic-device","expires_in":600,"interval":1})JSON";
            } else if (request.url.find("oauth2/v2.0/token") != std::string::npos) {
                if (failRefresh && request.body.find("refresh_token=") != std::string::npos) {
                    response.transportSucceeded = false;
                } else {
                    response.body = R"JSON({"access_token":"synthetic-access","refresh_token":"synthetic-refresh"})JSON";
                }
            } else if (request.url.find("entitlements/license") != std::string::npos) {
                response.body = R"JSON({"items":[{"name":"synthetic-entitlement"}]})JSON";
            } else if (request.url.find("minecraft/profile") != std::string::npos) {
                response.body = R"JSON({"id":"microsoft.profile","name":"Microsoft_Player"})JSON";
            } else {
                response.transportSucceeded = false;
            }
            return response;
        };

        auto runtime = makeProductionAccountRuntime(root, std::move(dependencies));
        FrontendFacade facade(root, accountDependencies(root, runtime));

        const auto initial = facade.accountSnapshots();
        require(initial.outcome == FrontendAccountSnapshotOutcome::Succeeded, "production account discovery failed");
        require(initial.accounts.size() == 2, "production account discovery did not preserve both records");
        require(initial.activeAccountIdentifier == std::optional<std::string>("offline.profile"),
                "legacy active account was not reconstructed");
        require(initial.accounts.front().type == FrontendAccountType::Offline
                    && initial.accounts.front().state == FrontendAccountState::Offline,
                "offline account metadata was not mapped through AccountData");

        const auto selected = facade.selectActiveAccount("microsoft.profile");
        require(selected.outcome == FrontendAccountSelectionOutcome::Succeeded && selected.account.has_value(),
                "active Microsoft account selection failed");
        require(selected.account->id == "microsoft.profile" && selected.account->canBeSelected,
                "selected account was not confirmed as selectable");

        FrontendOfflineLaunchIdentityRequest offlineLoadRequest;
        offlineLoadRequest.accountIdentifier = "offline.profile";
        offlineLoadRequest.fallbackName = "Player";
        const auto initialOffline = facade.loadOfflineLaunchIdentity(offlineLoadRequest);
        require(initialOffline.outcome == FrontendOfflineLaunchIdentityLoadOutcome::Succeeded
                    && initialOffline.identity->name == "Player",
                "offline identity did not use the Native root fallback");

        FrontendOfflineLaunchIdentityUpdateRequest offlineUpdateRequest;
        offlineUpdateRequest.accountIdentifier = "offline.profile";
        offlineUpdateRequest.name = "Saved_Player";
        const auto savedOffline = facade.updateOfflineLaunchIdentity(offlineUpdateRequest);
        require(savedOffline.outcome == FrontendOfflineLaunchIdentityUpdateOutcome::Succeeded,
                "offline identity did not persist through INIFile");

        std::vector<FrontendAccountAuthenticationPhase> phases;
        FrontendAccountAuthenticationRequest loginRequest;
        loginRequest.accountIdentifier = "microsoft.profile";
        loginRequest.action = FrontendAccountAuthenticationAction::Login;
        const auto login = facade.authenticateAccount(
            loginRequest,
            [&phases](const FrontendAccountAuthenticationProgress& progress) { phases.push_back(progress.phase); });
        require(login.outcome == FrontendAccountAuthenticationOutcome::Succeeded && login.account.has_value(),
                "production Microsoft device-flow authentication failed");
        require(login.account->id == "microsoft.profile" && login.account->state == FrontendAccountState::Online,
                "authenticated profile was not confirmed as an online account");
        require(phases.size() == 4 && phases[0] == FrontendAccountAuthenticationPhase::Preparing
                    && phases[1] == FrontendAccountAuthenticationPhase::AwaitingUser
                    && phases[2] == FrontendAccountAuthenticationPhase::Authenticating
                    && phases[3] == FrontendAccountAuthenticationPhase::Succeeded,
                "device-flow progress did not preserve the expected safe phase order");
        require(browserURLs.size() == 1 && browserURLs.front().rfind("https://login.example.invalid/device", 0) == 0,
                "device-flow browser port did not receive a safe HTTPS URL");
        require(storedCredential == std::optional<std::string>("synthetic-refresh"),
                "authentication did not persist through the injected Keychain port");

        failRefresh = true;
        FrontendAccountAuthenticationRequest refreshRequest = loginRequest;
        refreshRequest.action = FrontendAccountAuthenticationAction::Refresh;
        phases.clear();
        const auto failedRefresh = facade.authenticateAccount(
            refreshRequest,
            [&phases](const FrontendAccountAuthenticationProgress& progress) { phases.push_back(progress.phase); });
        require(failedRefresh.outcome == FrontendAccountAuthenticationOutcome::Failed && failedRefresh.retryable,
                "refresh failure did not preserve retry recovery");
        require(!phases.empty() && phases.back() == FrontendAccountAuthenticationPhase::Failed,
                "refresh failure did not emit terminal error progress");
        const auto erroredSnapshot = facade.accountSnapshots();
        const auto errored = std::find_if(erroredSnapshot.accounts.begin(), erroredSnapshot.accounts.end(), [](const auto& account) {
            return account.id == "microsoft.profile";
        });
        require(errored != erroredSnapshot.accounts.end() && errored->state == FrontendAccountState::Expired,
                "refresh failure did not expose expired recovery state");

        failRefresh = false;
        const auto recovered = facade.authenticateAccount(refreshRequest);
        require(recovered.outcome == FrontendAccountAuthenticationOutcome::Succeeded,
                "refresh recovery did not restore the production account");
        facade.shutdown();

        auto reconstructedRuntime = makeProductionAccountRuntime(root, ProductionAccountRuntime::defaultDependencies());
        auto reconstructedDependencies = accountDependencies(root, reconstructedRuntime);
        reconstructedDependencies.shutdown = [reconstructedRuntime] { reconstructedRuntime->shutdown(); };
        FrontendFacade reconstructed(root, std::move(reconstructedDependencies));
        const auto rebuiltAccounts = reconstructed.accountSnapshots();
        require(rebuiltAccounts.activeAccountIdentifier == std::optional<std::string>("microsoft.profile"),
                "active account selection did not survive reconstruction");
        const auto rebuiltOffline = reconstructed.loadOfflineLaunchIdentity(offlineLoadRequest);
        require(rebuiltOffline.outcome == FrontendOfflineLaunchIdentityLoadOutcome::Succeeded
                    && rebuiltOffline.identity->name == "Saved_Player",
                "offline identity did not survive reconstruction");
        reconstructed.shutdown();
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        std::filesystem::remove_all(root, cleanupError);
        return 1;
    }

    std::filesystem::remove_all(root, cleanupError);
    return cleanupError ? 1 : 0;
}
