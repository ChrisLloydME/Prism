// SPDX-License-Identifier: GPL-3.0-only

#include "ProductionAccountRuntime.h"

#include "minecraft/auth/AccountData.h"
#include "settings/INIFile.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSaveFile>
#include <QString>
#include <QUuid>

#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <system_error>
#include <thread>
#include <unordered_set>

namespace {

constexpr int kAccountsFormatVersion = 3;
constexpr std::size_t kMaximumAccountIdentifierLength = 256;
constexpr std::size_t kMaximumDisplayNameLength = 256;
constexpr std::size_t kMaximumDiagnosticLength = 512;
constexpr int kMaximumDevicePolls = 8;

std::filesystem::path normalizeRoot(std::filesystem::path root)
{
    if (root.empty() || root.is_relative()) {
        throw std::invalid_argument("Production account runtime requires an absolute data root");
    }

    root = root.lexically_normal();
    std::error_code error;
    if (std::filesystem::exists(root, error) && (error || std::filesystem::is_symlink(root, error))) {
        throw std::invalid_argument("Production account runtime rejects a symlinked data root");
    }
    std::filesystem::create_directories(root, error);
    if (error || std::filesystem::is_symlink(root, error) || !std::filesystem::is_directory(root, error) || error) {
        throw std::runtime_error("Production account runtime could not create its data root");
    }
    return root;
}

bool safeText(const std::string& value, std::size_t maximum)
{
    return !value.empty() && value.size() <= maximum
        && std::all_of(value.begin(), value.end(), [](unsigned char character) {
               return character != '\0' && character != '\n' && character != '\r';
           });
}

bool safeURL(const std::string& value)
{
    return safeText(value, 2048) && value.rfind("https://", 0) == 0;
}

bool validOfflineName(const std::string& name)
{
    if (name.size() < 3 || name.size() > 16) {
        return false;
    }
    return std::all_of(name.begin(), name.end(), [](unsigned char character) {
        return std::isalnum(character) != 0 || character == '_';
    });
}

std::string toUTF8(const QString& value)
{
    return value.toStdString();
}

QString fromUTF8(const std::string& value)
{
    return QString::fromStdString(value);
}

std::string jsonString(const QJsonObject& object, const char* key)
{
    const auto value = object.value(QLatin1String(key));
    return value.isString() ? toUTF8(value.toString()) : std::string();
}

std::optional<int> jsonInteger(const QJsonObject& object, const char* key)
{
    const auto value = object.value(QLatin1String(key));
    if (!value.isDouble()) {
        return std::nullopt;
    }
    return value.toInt();
}

bool jsonBoolean(const QJsonObject& object, const char* key, bool fallback = false)
{
    const auto value = object.value(QLatin1String(key));
    return value.isBool() ? value.toBool() : fallback;
}

std::optional<QJsonObject> parseObject(const std::string& body)
{
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(QByteArray::fromStdString(body), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        return std::nullopt;
    }
    return document.object();
}

bool responseSucceeded(const ProductionAccountRuntime::HttpResponse& response)
{
    return response.transportSucceeded && response.statusCode >= 200 && response.statusCode < 300;
}

bool isSymlink(const std::filesystem::path& path)
{
    std::error_code error;
    return std::filesystem::is_symlink(std::filesystem::symlink_status(path, error)) && !error;
}

std::string offlineUUID(const QString& username)
{
    QByteArray digest = QCryptographicHash::hash(
        QStringLiteral("OfflinePlayer:%1").arg(username).toUtf8(), QCryptographicHash::Md5);
    digest[6] = static_cast<char>((static_cast<unsigned char>(digest[6]) & 0x0f) | 0x30);
    digest[8] = static_cast<char>((static_cast<unsigned char>(digest[8]) & 0x3f) | 0x80);
    return QUuid::fromRfc4122(digest).toString(QUuid::Id128).toStdString();
}

std::optional<QJsonObject> readAccountsObject(const std::filesystem::path& path, std::string& key, std::string& text)
{
    if (isSymlink(path)) {
        key = "accounts.discovery.unsafePath";
        text = "The Native Prism account file is a symbolic link.";
        return std::nullopt;
    }
    if (!QFile::exists(fromUTF8(path.string()))) {
        return QJsonObject{};
    }

    QFile file(fromUTF8(path.string()));
    if (!file.open(QIODevice::ReadOnly)) {
        key = "accounts.discovery.readFailed";
        text = "The Native Prism account file could not be read.";
        return std::nullopt;
    }

    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        key = "accounts.discovery.invalidFile";
        text = "The Native Prism account file is not valid JSON.";
        return std::nullopt;
    }
    return document.object();
}

bool writeAccountsObject(const std::filesystem::path& path, const QJsonObject& root)
{
    if (isSymlink(path)) {
        return false;
    }

    QDir parent(fromUTF8(path.parent_path().string()));
    if (!parent.exists() && !parent.mkpath(QStringLiteral("."))) {
        return false;
    }

    QSaveFile file(fromUTF8(path.string()));
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ReadUser | QFile::WriteUser);
    return file.commit();
}

QJsonObject profileObject(const std::string& identifier, const std::string& name)
{
    QJsonObject skin;
    skin.insert(QStringLiteral("id"), QString());
    skin.insert(QStringLiteral("url"), QString());
    skin.insert(QStringLiteral("variant"), QString());

    QJsonObject profile;
    profile.insert(QStringLiteral("id"), fromUTF8(identifier));
    profile.insert(QStringLiteral("name"), fromUTF8(name));
    profile.insert(QStringLiteral("skin"), skin);
    profile.insert(QStringLiteral("capes"), QJsonArray());
    return profile;
}

}  // namespace

struct ProductionAccountRuntime::AccountRecord final {
    QJsonObject object;
    AccountData data;
    std::string identifier;
    bool active = false;
};

struct ProductionAccountRuntime::AuthenticationArtifacts final {
    std::string primaryCredential;
    std::string secondaryCredential;
    std::string profileIdentifier;
    std::string profileName;
    bool ownsMinecraft = false;
};

ProductionAccountRuntime::Dependencies ProductionAccountRuntime::defaultDependencies()
{
    Dependencies dependencies;
    dependencies.http = [](const HttpRequest&) { return HttpResponse{}; };
    dependencies.browser = [](const std::string&) { return false; };
    dependencies.wait = [](std::chrono::seconds duration) {
        if (duration.count() > 0) {
            std::this_thread::sleep_for(duration);
        }
    };
    dependencies.keychain.read = [](const std::string&) { return std::optional<std::string>(); };
    dependencies.keychain.write = [](const std::string&, const std::string&) { return false; };
    dependencies.keychain.erase = [](const std::string&) { return false; };
    return dependencies;
}

ProductionAccountRuntime::ProductionAccountRuntime(std::filesystem::path dataRoot, Dependencies dependencies)
    : m_dataRoot(normalizeRoot(std::move(dataRoot))),
      m_accountsPath(m_dataRoot / "accounts.json"),
      m_globalSettingsPath(m_dataRoot / "prismlauncher.cfg"),
      m_dependencies(std::move(dependencies))
{
    const auto defaults = defaultDependencies();
    if (!m_dependencies.http) {
        m_dependencies.http = defaults.http;
    }
    if (!m_dependencies.browser) {
        m_dependencies.browser = defaults.browser;
    }
    if (!m_dependencies.wait) {
        m_dependencies.wait = defaults.wait;
    }
    if (!m_dependencies.keychain.read) {
        m_dependencies.keychain.read = defaults.keychain.read;
    }
    if (!m_dependencies.keychain.write) {
        m_dependencies.keychain.write = defaults.keychain.write;
    }
    if (!m_dependencies.keychain.erase) {
        m_dependencies.keychain.erase = defaults.keychain.erase;
    }
}

ProductionAccountRuntime::~ProductionAccountRuntime() noexcept
{
    shutdown();
}

std::vector<ProductionAccountRuntime::AccountRecord> ProductionAccountRuntime::loadAccountRecords(
    std::string& failureKey, std::string& failureText) const
{
    const auto root = readAccountsObject(m_accountsPath, failureKey, failureText);
    if (!root.has_value()) {
        return {};
    }
    if (root->isEmpty()) {
        return {};
    }

    const auto version = root->value(QStringLiteral("formatVersion"));
    if (!version.isDouble() || version.toInt() != kAccountsFormatVersion) {
        failureKey = "accounts.discovery.unsupportedFormat";
        failureText = "The Native Prism account file uses an unsupported format.";
        return {};
    }

    const auto accountArray = root->value(QStringLiteral("accounts"));
    if (!accountArray.isArray()) {
        failureKey = "accounts.discovery.invalidFile";
        failureText = "The Native Prism account file has no account list.";
        return {};
    }

    std::vector<AccountRecord> records;
    std::unordered_set<std::string> identifiers;
    for (const auto& value : accountArray.toArray()) {
        if (!value.isObject()) {
            continue;
        }

        AccountRecord record;
        record.object = value.toObject();
        if (!record.data.resumeStateFromV3(record.object)) {
            continue;
        }
        record.identifier = toUTF8(record.data.profileId());
        if (!safeText(record.identifier, kMaximumAccountIdentifierLength)
            || !identifiers.insert(record.identifier).second) {
            continue;
        }
        record.active = jsonBoolean(record.object, "active");
        records.push_back(std::move(record));
    }
    return records;
}

FrontendAccountSnapshot ProductionAccountRuntime::snapshotForRecord(const AccountRecord& record) const
{
    FrontendAccountSnapshot snapshot;
    snapshot.id = record.identifier;
    snapshot.displayName = toUTF8(record.data.minecraftProfile.name);
    if (snapshot.displayName.empty()) {
        snapshot.displayName = "No Minecraft profile";
    }
    if (snapshot.displayName.size() > kMaximumDisplayNameLength) {
        snapshot.displayName.resize(kMaximumDisplayNameLength);
    }
    snapshot.type = record.data.type == AccountType::Offline ? FrontendAccountType::Offline : FrontendAccountType::Microsoft;
    if (snapshot.type == FrontendAccountType::Offline) {
        snapshot.state = FrontendAccountState::Offline;
    } else if (const auto overrideState = m_stateOverrides.find(record.identifier); overrideState != m_stateOverrides.end()) {
        snapshot.state = overrideState->second;
    } else if (record.data.minecraftProfile.validity != Validity::None) {
        snapshot.state = FrontendAccountState::Online;
    } else {
        snapshot.state = FrontendAccountState::Unchecked;
    }
    snapshot.ownsMinecraft = record.data.type != AccountType::Offline && record.data.minecraftEntitlement.ownsMinecraft;
    snapshot.isBusy = snapshot.state == FrontendAccountState::Working;
    snapshot.canBeSelected = !snapshot.id.empty() && !snapshot.isBusy && snapshot.state != FrontendAccountState::Disabled
        && snapshot.state != FrontendAccountState::Gone;
    if (const auto diagnostic = m_diagnostics.find(record.identifier); diagnostic != m_diagnostics.end()) {
        snapshot.diagnosticText = diagnostic->second;
    }
    return snapshot;
}

FrontendAccountSnapshotResult ProductionAccountRuntime::failedSnapshotResult(
    std::string key, std::string text, bool retryable) const
{
    return {
        FrontendAccountSnapshotOutcome::Failed,
        {},
        std::nullopt,
        std::move(key),
        std::move(text),
        retryable,
    };
}

FrontendAccountSnapshotResult ProductionAccountRuntime::accountSnapshots()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown) {
        return failedSnapshotResult("accounts.discovery.cancelled", "Account snapshot loading was cancelled.", false);
    }

    std::string failureKey;
    std::string failureText;
    auto records = loadAccountRecords(failureKey, failureText);
    if (!failureKey.empty()) {
        return failedSnapshotResult(std::move(failureKey), std::move(failureText), true);
    }

    std::optional<std::string> activeIdentifier;
    std::vector<FrontendAccountSnapshot> snapshots;
    snapshots.reserve(records.size());
    for (const auto& record : records) {
        snapshots.push_back(snapshotForRecord(record));
        if (record.active && snapshots.back().canBeSelected && !activeIdentifier.has_value()) {
            activeIdentifier = record.identifier;
        }
    }
    m_lastRecords = records;
    return {
        FrontendAccountSnapshotOutcome::Succeeded,
        std::move(snapshots),
        std::move(activeIdentifier),
        "accounts.discovery.succeeded",
        {},
        false,
    };
}

bool ProductionAccountRuntime::persistAccountObjects(
    const std::vector<std::pair<std::string, bool>>& activeByIdentifier) const
{
    std::string failureKey;
    std::string failureText;
    const auto root = readAccountsObject(m_accountsPath, failureKey, failureText);
    if (!root.has_value() || root->isEmpty()) {
        return false;
    }
    auto accounts = root->value(QStringLiteral("accounts")).toArray();
    for (int index = 0; index < accounts.size(); ++index) {
        if (!accounts.at(index).isObject()) {
            continue;
        }
        auto object = accounts.at(index).toObject();
        AccountData data;
        if (!data.resumeStateFromV3(object)) {
            continue;
        }
        const auto identifier = toUTF8(data.profileId());
        const auto found = std::find_if(activeByIdentifier.begin(), activeByIdentifier.end(), [&](const auto& value) {
            return value.first == identifier;
        });
        if (found != activeByIdentifier.end()) {
            object.insert(QStringLiteral("active"), found->second);
            accounts.replace(index, object);
        }
    }
    QJsonObject updated = *root;
    updated.insert(QStringLiteral("accounts"), accounts);
    return writeAccountsObject(m_accountsPath, updated);
}

FrontendAccountSelectionResult ProductionAccountRuntime::selectActiveAccount(
    const std::optional<std::string>& accountIdentifier)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown) {
        return {
            FrontendAccountSelectionOutcome::Rejected,
            std::nullopt,
            "accounts.selection.cancelled",
            "Account selection was cancelled.",
        };
    }

    std::string failureKey;
    std::string failureText;
    const auto records = loadAccountRecords(failureKey, failureText);
    if (!failureKey.empty()) {
        return { FrontendAccountSelectionOutcome::Rejected, std::nullopt, std::move(failureKey), std::move(failureText) };
    }

    const AccountRecord* selected = nullptr;
    if (accountIdentifier.has_value()) {
        const auto found = std::find_if(records.begin(), records.end(), [&](const auto& record) {
            return record.identifier == *accountIdentifier;
        });
        if (found == records.end()) {
            return {
                FrontendAccountSelectionOutcome::UnknownAccount,
                std::nullopt,
                "accounts.selection.unknownAccount",
                "The requested account is no longer available.",
            };
        }
        selected = &*found;
        const auto snapshot = snapshotForRecord(*selected);
        if (!snapshot.canBeSelected || snapshot.isBusy) {
            return {
                FrontendAccountSelectionOutcome::Rejected,
                snapshot,
                "accounts.selection.notSelectable",
                "The requested account cannot be selected right now.",
            };
        }
    }

    std::vector<std::pair<std::string, bool>> activeByIdentifier;
    activeByIdentifier.reserve(records.size());
    for (const auto& record : records) {
        activeByIdentifier.emplace_back(record.identifier, selected && record.identifier == selected->identifier);
    }
    if (!persistAccountObjects(activeByIdentifier)) {
        return {
            FrontendAccountSelectionOutcome::Rejected,
            std::nullopt,
            "accounts.selection.persistenceFailed",
            "The active account could not be saved.",
        };
    }

    m_lastRecords = records;
    if (selected) {
        return {
            FrontendAccountSelectionOutcome::Succeeded,
            snapshotForRecord(*selected),
            "accounts.selection.succeeded",
            {},
        };
    }
    return {
        FrontendAccountSelectionOutcome::Succeeded,
        std::nullopt,
        "accounts.selection.cleared",
        {},
    };
}

FrontendAccountAuthenticationProgress ProductionAccountRuntime::makeProgress(
    const FrontendAccountAuthenticationRequest& request,
    FrontendAccountAuthenticationPhase phase,
    FrontendAccountAuthenticationOutcome outcome,
    std::string localizationKey,
    std::string diagnosticText,
    bool canCancel,
    bool retryable,
    bool requiresUserAction,
    std::string verificationURL,
    std::int32_t expiresInSeconds) const
{
    return {
        request.accountIdentifier,
        request.action,
        phase,
        outcome,
        "Microsoft",
        std::move(verificationURL),
        std::move(localizationKey),
        std::move(diagnosticText),
        expiresInSeconds,
        canCancel,
        retryable,
        requiresUserAction,
    };
}

FrontendAccountAuthenticationResult ProductionAccountRuntime::finishAuthenticationFailure(
    const FrontendAccountAuthenticationRequest& request,
    const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progressHandler,
    std::string localizationKey,
    std::string diagnosticText,
    bool retryable,
    FrontendAccountAuthenticationPhase phase)
{
    m_stateOverrides[request.accountIdentifier] = request.action == FrontendAccountAuthenticationAction::Refresh
        ? FrontendAccountState::Expired
        : FrontendAccountState::Errored;
    m_diagnostics[request.accountIdentifier] = diagnosticText.substr(0, kMaximumDiagnosticLength);
    const auto progress = makeProgress(
        request,
        phase,
        FrontendAccountAuthenticationOutcome::Failed,
        localizationKey,
        diagnosticText,
        false,
        retryable,
        false);
    if (progressHandler) {
        progressHandler(progress);
    }
    return {
        FrontendAccountAuthenticationOutcome::Failed,
        std::nullopt,
        std::move(localizationKey),
        std::move(diagnosticText),
        retryable,
    };
}

std::optional<ProductionAccountRuntime::AuthenticationArtifacts> ProductionAccountRuntime::authenticateWithProvider(
    const AccountRecord& record,
    const FrontendAccountAuthenticationRequest& request,
    const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progressHandler,
    std::string& failureKey,
    std::string& failureText,
    bool& retryable)
{
    auto performRequest = [&](const HttpRequest& httpRequest) -> std::optional<QJsonObject> {
        const auto response = m_dependencies.http(httpRequest);
        if (!responseSucceeded(response)) {
            failureKey = "accounts.authentication.networkFailed";
            failureText = "The Microsoft authentication service could not be reached.";
            retryable = true;
            return std::nullopt;
        }
        const auto object = parseObject(response.body);
        if (!object.has_value()) {
            failureKey = "accounts.authentication.invalidResponse";
            failureText = "The Microsoft authentication response could not be understood.";
            retryable = true;
            return std::nullopt;
        }
        return object;
    };

    AuthenticationArtifacts artifacts;
    std::string primary;
    std::string secondary;
    if (request.action == FrontendAccountAuthenticationAction::Refresh) {
        const auto stored = m_dependencies.keychain.read(request.accountIdentifier);
        if (!stored.has_value() || stored->empty()) {
            failureKey = "accounts.authentication.refreshExpired";
            failureText = "The saved Microsoft sign-in has expired and must be renewed.";
            retryable = true;
            return std::nullopt;
        }
        primary = *stored;
        secondary = *stored;

        const auto response = performRequest({
            "POST",
            "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
            "grant_type=refresh_token&client_id=" + toUTF8(record.data.msaClientID) + "&refresh_token=" + primary,
        });
        if (!response.has_value()) {
            return std::nullopt;
        }
        const auto refreshed = jsonString(*response, "access_token");
        if (refreshed.empty()) {
            failureKey = "accounts.authentication.refreshFailed";
            failureText = "Microsoft sign-in refresh was rejected.";
            retryable = true;
            return std::nullopt;
        }
        primary = refreshed;
        secondary = jsonString(*response, "refresh_token");
        if (secondary.empty()) {
            secondary = *stored;
        }
    } else {
        const auto device = performRequest({
            "POST",
            "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode",
            "client_id=" + toUTF8(record.data.msaClientID) + "&scope=XboxLive.SignIn%20XboxLive.offline_access",
        });
        if (!device.has_value()) {
            return std::nullopt;
        }

        const auto verification = jsonString(*device, "verification_uri");
        const auto completeVerification = jsonString(*device, "verification_uri_complete");
        const auto opaqueDeviceCode = jsonString(*device, "device_code");
        const auto expires = jsonInteger(*device, "expires_in");
        const auto interval = jsonInteger(*device, "interval").value_or(1);
        if (!safeURL(verification) || opaqueDeviceCode.empty() || !expires.has_value() || *expires <= 0) {
            failureKey = "accounts.authentication.invalidDeviceFlow";
            failureText = "Microsoft sign-in did not return valid verification instructions.";
            retryable = true;
            return std::nullopt;
        }

        const auto browserURL = safeURL(completeVerification) ? completeVerification : verification;
        if (!m_dependencies.browser(browserURL)) {
            failureKey = "accounts.authentication.browserRejected";
            failureText = "The verification page could not be opened.";
            retryable = true;
            return std::nullopt;
        }
        if (progressHandler) {
            progressHandler(makeProgress(
                request,
                FrontendAccountAuthenticationPhase::AwaitingUser,
                FrontendAccountAuthenticationOutcome::InProgress,
                "accounts.authentication.awaitingUser",
                {},
                true,
                false,
                true,
                verification,
                *expires));
        }

        bool received = false;
        for (int attempt = 0; attempt < kMaximumDevicePolls; ++attempt) {
            const auto response = performRequest({
                "POST",
                "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
                "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=" + toUTF8(record.data.msaClientID)
                    + "&device_code=" + opaqueDeviceCode,
            });
            if (!response.has_value()) {
                return std::nullopt;
            }
            const auto error = jsonString(*response, "error");
            if (error == "authorization_pending") {
                m_dependencies.wait(std::chrono::seconds(std::max(interval, 1)));
                continue;
            }
            primary = jsonString(*response, "access_token");
            secondary = jsonString(*response, "refresh_token");
            if (primary.empty()) {
                failureKey = "accounts.authentication.authorizationFailed";
                failureText = "Microsoft sign-in was not completed.";
                retryable = true;
                return std::nullopt;
            }
            received = true;
            break;
        }
        if (!received) {
            failureKey = "accounts.authentication.authorizationTimedOut";
            failureText = "Microsoft sign-in verification timed out.";
            retryable = true;
            return std::nullopt;
        }
    }

    if (progressHandler) {
        progressHandler(makeProgress(
            request,
            FrontendAccountAuthenticationPhase::Authenticating,
            FrontendAccountAuthenticationOutcome::InProgress,
            "accounts.authentication.authenticating",
            {},
            true,
            false,
            false));
    }

    if (!m_dependencies.keychain.write(request.accountIdentifier, secondary.empty() ? primary : secondary)) {
        failureKey = "accounts.authentication.persistenceFailed";
        failureText = "The Microsoft sign-in could not be saved in the Native Prism credential store.";
        retryable = true;
        return std::nullopt;
    }

    const auto entitlement = performRequest({
        "GET",
        "https://api.minecraftservices.com/entitlements/license",
        primary,
    });
    if (!entitlement.has_value()) {
        return std::nullopt;
    }
    const auto entitlementItems = entitlement->value(QStringLiteral("items"));
    artifacts.ownsMinecraft = entitlementItems.isArray() && !entitlementItems.toArray().isEmpty();

    const auto profile = performRequest({
        "GET",
        "https://api.minecraftservices.com/minecraft/profile",
        primary,
    });
    if (!profile.has_value()) {
        return std::nullopt;
    }
    artifacts.profileIdentifier = jsonString(*profile, "id");
    artifacts.profileName = jsonString(*profile, "name");
    if (!safeText(artifacts.profileIdentifier, kMaximumAccountIdentifierLength)
        || !safeText(artifacts.profileName, kMaximumDisplayNameLength)
        || artifacts.profileIdentifier != request.accountIdentifier) {
        failureKey = "accounts.authentication.profileChanged";
        failureText = "The authenticated Minecraft profile does not match the selected account.";
        retryable = true;
        return std::nullopt;
    }

    artifacts.primaryCredential = std::move(primary);
    artifacts.secondaryCredential = std::move(secondary);
    return artifacts;
}

bool ProductionAccountRuntime::persistAuthenticatedProfile(
    const std::string& accountIdentifier,
    const std::string& profileIdentifier,
    const std::string& profileName,
    bool ownsMinecraft) const
{
    std::string failureKey;
    std::string failureText;
    const auto root = readAccountsObject(m_accountsPath, failureKey, failureText);
    if (!root.has_value() || root->isEmpty()) {
        return false;
    }
    auto accounts = root->value(QStringLiteral("accounts")).toArray();
    bool found = false;
    for (int index = 0; index < accounts.size(); ++index) {
        if (!accounts.at(index).isObject()) {
            continue;
        }
        auto object = accounts.at(index).toObject();
        AccountData data;
        if (!data.resumeStateFromV3(object) || toUTF8(data.profileId()) != accountIdentifier) {
            continue;
        }
        object.insert(QStringLiteral("profile"), profileObject(profileIdentifier, profileName));
        QJsonObject entitlement;
        entitlement.insert(QStringLiteral("ownsMinecraft"), ownsMinecraft);
        entitlement.insert(QStringLiteral("canPlayMinecraft"), ownsMinecraft);
        object.insert(QStringLiteral("entitlement"), entitlement);
        accounts.replace(index, object);
        found = true;
        break;
    }
    if (!found) {
        return false;
    }
    QJsonObject updated = *root;
    updated.insert(QStringLiteral("accounts"), accounts);
    return writeAccountsObject(m_accountsPath, updated);
}

FrontendAccountAuthenticationResult ProductionAccountRuntime::authenticateAccount(
    const FrontendAccountAuthenticationRequest& request,
    const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progressHandler)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown) {
        return {
            FrontendAccountAuthenticationOutcome::Rejected,
            std::nullopt,
            "accounts.authentication.cancelled",
            "Account authentication was cancelled.",
            false,
        };
    }

    std::string failureKey;
    std::string failureText;
    const auto records = loadAccountRecords(failureKey, failureText);
    if (!failureKey.empty()) {
        return finishAuthenticationFailure(
            request,
            progressHandler,
            std::move(failureKey),
            std::move(failureText),
            true);
    }
    const auto found = std::find_if(records.begin(), records.end(), [&](const auto& record) {
        return record.identifier == request.accountIdentifier;
    });
    if (found == records.end()) {
        return {
            FrontendAccountAuthenticationOutcome::Rejected,
            std::nullopt,
            "accounts.authentication.unknownAccount",
            "The requested account is no longer available.",
            false,
        };
    }
    if (found->data.type != AccountType::MSA) {
        return {
            FrontendAccountAuthenticationOutcome::Rejected,
            std::nullopt,
            "accounts.authentication.unsupportedAccount",
            "Only Microsoft accounts can be authenticated here.",
            false,
        };
    }

    if (progressHandler) {
        progressHandler(makeProgress(
            request,
            FrontendAccountAuthenticationPhase::Preparing,
            FrontendAccountAuthenticationOutcome::InProgress,
            "accounts.authentication.preparing",
            {},
            true,
            false,
            false));
    }

    bool retryable = true;
    const auto artifacts = authenticateWithProvider(
        *found,
        request,
        progressHandler,
        failureKey,
        failureText,
        retryable);
    if (!artifacts.has_value()) {
        if (failureKey.empty()) {
            failureKey = "accounts.authentication.failed";
            failureText = "Microsoft authentication failed.";
        }
        return finishAuthenticationFailure(
            request,
            progressHandler,
            std::move(failureKey),
            std::move(failureText),
            retryable);
    }

    if (!persistAuthenticatedProfile(
            request.accountIdentifier,
            artifacts->profileIdentifier,
            artifacts->profileName,
            artifacts->ownsMinecraft)) {
        static_cast<void>(m_dependencies.keychain.erase(request.accountIdentifier));
        return finishAuthenticationFailure(
            request,
            progressHandler,
            "accounts.authentication.persistenceFailed",
            "The authenticated account profile could not be saved.",
            true);
    }

    // Keep the short-lived access token in the C++ runtime only. The launch
    // session provider consumes it without exposing it through the facade or
    // persisting it in task state; the refresh credential remains in the
    // injected credential port.
    m_launchCredentials[request.accountIdentifier] = artifacts->primaryCredential;

    m_stateOverrides.erase(request.accountIdentifier);
    m_diagnostics.erase(request.accountIdentifier);
    std::string reloadKey;
    std::string reloadText;
    const auto updatedRecords = loadAccountRecords(reloadKey, reloadText);
    const auto updated = std::find_if(updatedRecords.begin(), updatedRecords.end(), [&](const auto& record) {
        return record.identifier == request.accountIdentifier;
    });
    if (updated == updatedRecords.end()) {
        return finishAuthenticationFailure(
            request,
            progressHandler,
            "accounts.authentication.persistenceFailed",
            "The authenticated account could not be confirmed after saving.",
            true);
    }
    if (progressHandler) {
        progressHandler(makeProgress(
            request,
            FrontendAccountAuthenticationPhase::Succeeded,
            FrontendAccountAuthenticationOutcome::Succeeded,
            "accounts.authentication.succeeded",
            {},
            false,
            false,
            false));
    }
    return {
        FrontendAccountAuthenticationOutcome::Succeeded,
        snapshotForRecord(*updated),
        "accounts.authentication.succeeded",
        {},
        false,
    };
}

std::optional<std::string> ProductionAccountRuntime::savedOfflineName() const
{
    if (isSymlink(m_globalSettingsPath) || !QFile::exists(fromUTF8(m_globalSettingsPath.string()))) {
        return std::nullopt;
    }
    INIFile settings;
    if (!settings.loadFile(fromUTF8(m_globalSettingsPath.string()))) {
        return std::nullopt;
    }
    const auto name = settings.get(QStringLiteral("LastOfflinePlayerName"), QString()).toString().toStdString();
    return name.empty() ? std::nullopt : std::optional<std::string>(name);
}

bool ProductionAccountRuntime::persistOfflineName(const std::string& name) const
{
    if (isSymlink(m_globalSettingsPath)) {
        return false;
    }
    INIFile settings;
    if (QFile::exists(fromUTF8(m_globalSettingsPath.string()))
        && !settings.loadFile(fromUTF8(m_globalSettingsPath.string()))) {
        return false;
    }
    settings.set(QStringLiteral("LastOfflinePlayerName"), fromUTF8(name));
    return settings.saveFile(fromUTF8(m_globalSettingsPath.string()));
}

FrontendOfflineLaunchIdentityLoadResult ProductionAccountRuntime::loadOfflineLaunchIdentity(
    const FrontendOfflineLaunchIdentityRequest& request)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown) {
        return {
            FrontendOfflineLaunchIdentityLoadOutcome::Cancelled,
            std::nullopt,
            "accounts.offlineIdentity.cancelled",
            "Offline launch identity loading was cancelled.",
            false,
        };
    }

    if (request.accountIdentifier.has_value()) {
        std::string failureKey;
        std::string failureText;
        const auto records = loadAccountRecords(failureKey, failureText);
        if (!failureKey.empty()) {
            return {
                FrontendOfflineLaunchIdentityLoadOutcome::Failed,
                std::nullopt,
                std::move(failureKey),
                std::move(failureText),
                true,
            };
        }
        const auto found = std::find_if(records.begin(), records.end(), [&](const auto& record) {
            return record.identifier == *request.accountIdentifier;
        });
        if (found == records.end() || found->data.type != AccountType::Offline) {
            return {
                FrontendOfflineLaunchIdentityLoadOutcome::Failed,
                std::nullopt,
                "accounts.offlineIdentity.unknownAccount",
                "The requested offline account is no longer available.",
                false,
            };
        }
    }

    const auto name = savedOfflineName().value_or(request.fallbackName);
    return {
        FrontendOfflineLaunchIdentityLoadOutcome::Succeeded,
        FrontendOfflineLaunchIdentitySnapshot{ request.mode, request.accountIdentifier, name },
        "accounts.offlineIdentity.loaded",
        {},
        false,
    };
}

FrontendOfflineLaunchIdentityUpdateResult ProductionAccountRuntime::updateOfflineLaunchIdentity(
    const FrontendOfflineLaunchIdentityUpdateRequest& request)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown) {
        return {
            FrontendOfflineLaunchIdentityUpdateOutcome::Cancelled,
            std::nullopt,
            "accounts.offlineIdentity.cancelled",
            "Offline launch identity saving was cancelled.",
            false,
        };
    }
    if (request.name.empty() || (!request.allowInvalidName && !validOfflineName(request.name))) {
        return {
            FrontendOfflineLaunchIdentityUpdateOutcome::InvalidName,
            std::nullopt,
            "accounts.offlineIdentity.invalidName",
            "Offline launch names must be 3–16 English letters, numbers, or underscores.",
            false,
        };
    }
    if (request.accountIdentifier.has_value()) {
        std::string failureKey;
        std::string failureText;
        const auto records = loadAccountRecords(failureKey, failureText);
        if (!failureKey.empty()) {
            return {
                FrontendOfflineLaunchIdentityUpdateOutcome::Failed,
                std::nullopt,
                std::move(failureKey),
                std::move(failureText),
                true,
            };
        }
        const auto found = std::find_if(records.begin(), records.end(), [&](const auto& record) {
            return record.identifier == *request.accountIdentifier;
        });
        if (found == records.end() || found->data.type != AccountType::Offline) {
            return {
                FrontendOfflineLaunchIdentityUpdateOutcome::Failed,
                std::nullopt,
                "accounts.offlineIdentity.unknownAccount",
                "The requested offline account is no longer available.",
                false,
            };
        }
    }
    if (!persistOfflineName(request.name)) {
        return {
            FrontendOfflineLaunchIdentityUpdateOutcome::Failed,
            std::nullopt,
            "accounts.offlineIdentity.persistenceFailed",
            "The offline launch name could not be saved.",
            true,
        };
    }
    return {
        FrontendOfflineLaunchIdentityUpdateOutcome::Succeeded,
        FrontendOfflineLaunchIdentitySnapshot{ request.mode, request.accountIdentifier, request.name },
        "accounts.offlineIdentity.saved",
        {},
        false,
    };
}

std::optional<ProductionLaunchSession> ProductionAccountRuntime::launchSessionForInstance(
    const std::string& instanceIdentifier)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown || !safeText(instanceIdentifier, kMaximumAccountIdentifierLength)) {
        return std::nullopt;
    }

    std::optional<std::string> requestedIdentifier;
    const auto instancePath = m_dataRoot / "instances" / instanceIdentifier / "instance.cfg";
    if (!isSymlink(instancePath) && QFile::exists(fromUTF8(instancePath.string()))) {
        INIFile instanceSettings;
        if (!instanceSettings.loadFile(fromUTF8(instancePath.string()))) {
            return std::nullopt;
        }
        const auto configured = instanceSettings.get(QStringLiteral("InstanceAccountId"), QString()).toString().trimmed();
        if (!configured.isEmpty()) {
            requestedIdentifier = configured.toStdString();
        }
    }

    std::string failureKey;
    std::string failureText;
    const auto records = loadAccountRecords(failureKey, failureText);
    if (!failureKey.empty()) {
        return std::nullopt;
    }

    const AccountRecord* selected = nullptr;
    if (requestedIdentifier.has_value()) {
        const auto found = std::find_if(records.begin(), records.end(), [&](const auto& record) {
            return record.identifier == *requestedIdentifier;
        });
        if (found == records.end()) {
            return std::nullopt;
        }
        selected = &*found;
    } else {
        const auto found = std::find_if(records.begin(), records.end(), [](const auto& record) { return record.active; });
        if (found != records.end()) {
            selected = &*found;
        }
    }

    ProductionLaunchSession session;
    if (selected && selected->data.type == AccountType::MSA) {
        const auto profileName = selected->data.profileName();
        if (profileName.isEmpty()) {
            return std::nullopt;
        }
        std::string accessToken = selected->data.accessToken().toStdString();
        if (const auto inMemory = m_launchCredentials.find(selected->identifier); inMemory != m_launchCredentials.end()) {
            accessToken = inMemory->second;
        }
        if (accessToken.empty() || accessToken == "0" || !selected->data.minecraftEntitlement.ownsMinecraft) {
            return std::nullopt;
        }
        session.mode = ProductionLaunchMode::Normal;
        session.accessToken = accessToken;
        session.playerName = profileName.toStdString();
        session.uuid = selected->data.profileId().toStdString();
        if (session.uuid.empty()) {
            session.uuid = offlineUUID(profileName);
        }
        session.userType = "msa";
        session.session = "token:" + session.accessToken + ":" + selected->data.profileId().toStdString();
        session.secrets = { session.accessToken, session.session };
        return session;
    }

    QString offlineName;
    if (const auto saved = savedOfflineName(); saved.has_value()) {
        offlineName = fromUTF8(*saved);
    } else if (selected) {
        offlineName = selected->data.profileName();
    }
    if (offlineName.isEmpty()) {
        return std::nullopt;
    }

    session.mode = selected ? ProductionLaunchMode::Offline : ProductionLaunchMode::Demo;
    session.playerName = offlineName.toStdString();
    session.uuid = offlineUUID(offlineName);
    session.userType = "offline";
    if (session.mode == ProductionLaunchMode::Demo) {
        session.session = "-";
        session.accessToken = "0";
    }
    return session;
}

void ProductionAccountRuntime::shutdown() noexcept
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_shutdown = true;
    m_lastRecords.clear();
    m_launchCredentials.clear();
}

std::shared_ptr<ProductionAccountRuntime> makeProductionAccountRuntime(
    std::filesystem::path dataRoot, ProductionAccountRuntime::Dependencies dependencies)
{
    return std::make_shared<ProductionAccountRuntime>(std::move(dataRoot), std::move(dependencies));
}

FrontendRuntimeDependencies productionAccountRuntimeDependencies(
    std::shared_ptr<ProductionAccountRuntime> runtime, FrontendRuntimeDependencies dependencies)
{
    if (!runtime) {
        throw std::invalid_argument("Production account runtime dependency requires an owner");
    }
    dependencies.loadAccountSnapshots = [runtime](const std::filesystem::path&) { return runtime->accountSnapshots(); };
    dependencies.selectActiveAccount = [runtime](
                                           const std::filesystem::path&, const std::optional<std::string>& identifier) {
        return runtime->selectActiveAccount(identifier);
    };
    dependencies.authenticateAccount = [runtime](
                                           const std::filesystem::path&,
                                           const FrontendAccountAuthenticationRequest& request,
                                           const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progress) {
        return runtime->authenticateAccount(request, progress);
    };
    dependencies.loadOfflineLaunchIdentity = [runtime](
                                                 const std::filesystem::path&,
                                                 const FrontendOfflineLaunchIdentityRequest& request) {
        return runtime->loadOfflineLaunchIdentity(request);
    };
    dependencies.updateOfflineLaunchIdentity = [runtime](
                                                   const std::filesystem::path&,
                                                   const FrontendOfflineLaunchIdentityUpdateRequest& request) {
        return runtime->updateOfflineLaunchIdentity(request);
    };
    return dependencies;
}
