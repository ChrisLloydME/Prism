// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "FrontendFacade.h"
#include "ProductionLaunchSession.h"

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

/// QWidget-free production owner for Native Prism account persistence and
/// authentication state.
///
/// The persisted account representation remains Prism's version-3
/// accounts.json format. AccountData performs the legacy QtCore data
/// decoding inside the adapter; only non-secret profile/account metadata is
/// converted to FrontendFacade values. Provider effects are explicit ports so
/// tests can exercise the real adapter with synthetic HTTP, browser, and
/// Keychain services without contacting a provider or the user's Keychain.
class ProductionAccountRuntime final {
   public:
    struct HttpRequest final {
        std::string method;
        std::string url;
        std::string body;
    };

    struct HttpResponse final {
        bool transportSucceeded = false;
        int statusCode = 0;
        std::string body;
    };

    using HttpExecutor = std::function<HttpResponse(const HttpRequest&)>;
    using BrowserExecutor = std::function<bool(const std::string& safeURL)>;
    using WaitExecutor = std::function<void(std::chrono::seconds)>;

    struct KeychainPort final {
        using Reader = std::function<std::optional<std::string>(const std::string& accountIdentifier)>;
        using Writer = std::function<bool(const std::string& accountIdentifier, const std::string& opaqueValue)>;
        using Eraser = std::function<bool(const std::string& accountIdentifier)>;

        Reader read;
        Writer write;
        Eraser erase;
    };

    struct Dependencies final {
        HttpExecutor http;
        BrowserExecutor browser;
        WaitExecutor wait;
        KeychainPort keychain;
    };

    static Dependencies defaultDependencies();

    explicit ProductionAccountRuntime(std::filesystem::path dataRoot, Dependencies dependencies = {});
    ~ProductionAccountRuntime() noexcept;

    ProductionAccountRuntime(const ProductionAccountRuntime&) = delete;
    ProductionAccountRuntime& operator=(const ProductionAccountRuntime&) = delete;

    FrontendAccountSnapshotResult accountSnapshots();
    FrontendAccountSelectionResult selectActiveAccount(const std::optional<std::string>& accountIdentifier);
    FrontendAccountAuthenticationResult authenticateAccount(
        const FrontendAccountAuthenticationRequest& request,
        const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progressHandler);
    FrontendOfflineLaunchIdentityLoadResult loadOfflineLaunchIdentity(
        const FrontendOfflineLaunchIdentityRequest& request);
    FrontendOfflineLaunchIdentityUpdateResult updateOfflineLaunchIdentity(
        const FrontendOfflineLaunchIdentityUpdateRequest& request);
    std::optional<ProductionLaunchSession> launchSessionForInstance(const std::string& instanceIdentifier);
    std::optional<FrontendSkinAccountProfile> skinAccountProfile(const std::string& accountIdentifier);
    std::optional<std::string> skinAccessCredential(const std::string& accountIdentifier);
    bool persistSkinAccountProfile(const FrontendSkinAccountProfile& profile);
    void shutdown() noexcept;

    const std::filesystem::path& dataRoot() const noexcept { return m_dataRoot; }

   private:
    struct AccountRecord;
    struct AuthenticationArtifacts;

    std::vector<AccountRecord> loadAccountRecords(std::string& failureKey, std::string& failureText) const;
    FrontendAccountSnapshot snapshotForRecord(const AccountRecord& record) const;
    FrontendAccountSnapshotResult failedSnapshotResult(std::string key, std::string text, bool retryable) const;
    FrontendAccountAuthenticationProgress makeProgress(
        const FrontendAccountAuthenticationRequest& request,
        FrontendAccountAuthenticationPhase phase,
        FrontendAccountAuthenticationOutcome outcome,
        std::string localizationKey,
        std::string diagnosticText,
        bool canCancel,
        bool retryable,
        bool requiresUserAction,
        std::string verificationURL = {},
        std::int32_t expiresInSeconds = 0) const;
    FrontendAccountAuthenticationResult finishAuthenticationFailure(
        const FrontendAccountAuthenticationRequest& request,
        const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progressHandler,
        std::string localizationKey,
        std::string diagnosticText,
        bool retryable,
        FrontendAccountAuthenticationPhase phase = FrontendAccountAuthenticationPhase::Failed);
    std::optional<AuthenticationArtifacts> authenticateWithProvider(
        const AccountRecord& record,
        const FrontendAccountAuthenticationRequest& request,
        const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progressHandler,
        std::string& failureKey,
        std::string& failureText,
        bool& retryable);
    bool persistAccountObjects(const std::vector<std::pair<std::string, bool>>& activeByIdentifier) const;
    bool persistAuthenticatedProfile(
        const std::string& accountIdentifier,
        const std::string& profileIdentifier,
        const std::string& profileName,
        bool ownsMinecraft) const;
    std::optional<std::string> savedOfflineName() const;
    bool persistOfflineName(const std::string& name) const;

    std::filesystem::path m_dataRoot;
    std::filesystem::path m_accountsPath;
    std::filesystem::path m_globalSettingsPath;
    Dependencies m_dependencies;

    mutable std::mutex m_mutex;
    std::vector<AccountRecord> m_lastRecords;
    std::unordered_map<std::string, FrontendAccountState> m_stateOverrides;
    std::unordered_map<std::string, std::string> m_diagnostics;
    std::unordered_map<std::string, std::string> m_launchCredentials;
    bool m_shutdown = false;
};

std::shared_ptr<ProductionAccountRuntime> makeProductionAccountRuntime(
    std::filesystem::path dataRoot,
    ProductionAccountRuntime::Dependencies dependencies = {});

FrontendRuntimeDependencies productionAccountRuntimeDependencies(
    std::shared_ptr<ProductionAccountRuntime> runtime,
    FrontendRuntimeDependencies dependencies = {});
