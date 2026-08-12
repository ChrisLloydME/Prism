// SPDX-License-Identifier: GPL-3.0-only

#include "ProductionSettingsRuntime.h"

#include "SysInfo.h"
#include "settings/INIFile.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QNetworkProxy>
#include <QNetworkProxyFactory>
#include <QString>
#include <QUrl>
#include <QVariant>

#include <algorithm>
#include <cstring>
#include <filesystem>
#include <initializer_list>
#include <set>
#include <stdexcept>
#include <system_error>
#include <utility>

namespace {

constexpr const char* kGlobalSettingsFile = "prismlauncher.cfg";
constexpr const char* kDefaultInstancesDirectory = "instances";

struct DomainSettings final {
    QString instanceDirectory = QStringLiteral("instances");
    QString iconTheme;
    QString applicationTheme;
    QString backgroundCat = QStringLiteral("kitteh");
    int catOpacity = 100;
    QString catFit = QStringLiteral("fit");
    QString language;
    bool useSystemLocale = false;
    bool menuBarInsteadOfToolBar = false;
    bool statusBarVisible = true;
    bool toolbarsLocked = false;
    int numberOfConcurrentTasks = 10;
    int numberOfConcurrentDownloads = 6;
    int numberOfManualRetries = 1;
    int requestTimeoutSeconds = 60;
    QString consoleFont = QStringLiteral("Menlo");
    int consoleFontSize = 11;
    int consoleMaxLines = 100000;
    bool consoleOverflowStop = true;
    bool showConsole = false;
    bool autoCloseConsole = false;
    bool showConsoleOnError = true;
    bool logPrePostOutput = true;
    int pasteType = 3;
    QString pasteCustomAPIBase;
    QString metadataURLOverride;
    bool refreshMetadataOnLaunch = true;
    QString assetsURLOverride;
    QString legacyFMLLibrariesURLOverride;
    bool fallbackForBlockedModrinthProjects = true;
    QString userAgentOverride;
    QString microsoftClientIDOverride;
    QString curseForgeAPIKey;
    QString modrinthToken;
    QString technicClientID;
    QString proxyType = QStringLiteral("None");
    QString proxyAddress = QStringLiteral("127.0.0.1");
    int proxyPort = 8080;
    QString proxyUsername;
    QString proxyPassword;

    bool launchMaximized = false;
    int windowWidth = 854;
    int windowHeight = 480;
    bool closeAfterLaunch = false;
    bool quitAfterGameStop = false;
    bool showGameTime = true;
    bool recordGameTime = true;
    QString javaPath;
    bool ignoreJavaCompatibility = false;
    int minMemoryMiB = 512;
    int maxMemoryMiB = SysInfo::defaultMaxJvmMem();
    int permGenMiB = 128;
    bool lowMemoryWarning = true;
    QString jvmArguments;
    QString preLaunchCommand;
    QString wrapperCommand;
    QString postExitCommand;
    bool onlineFixes = false;
    bool useNativeGLFW = false;
    QString customGLFWPath;
    bool useNativeOpenAL = false;
    QString customOpenALPath;
};

std::filesystem::path normalizeRoot(std::filesystem::path root)
{
    root = std::move(root).lexically_normal();
    if (root.empty() || !root.is_absolute()) {
        throw std::invalid_argument("Production settings runtime requires an absolute data root");
    }
    return root;
}

bool isSafeInstanceIdentifier(const std::string& value)
{
    if (value.empty() || value.size() > 255 || value == "." || value == "..") {
        return false;
    }
    return std::all_of(value.begin(), value.end(), [](unsigned char character) {
        return character >= 0x20 && character != '/' && character != '\\' && character != 0x7f;
    });
}

bool isDirectChild(const std::filesystem::path& parent, const std::filesystem::path& candidate)
{
    const auto relative = candidate.lexically_normal().lexically_relative(parent.lexically_normal());
    return !relative.empty() && relative != "." && !relative.has_root_path() && !relative.has_parent_path()
        && relative.filename() == relative;
}

bool isSymlink(const std::filesystem::path& path)
{
    std::error_code error;
    const bool result = std::filesystem::is_symlink(path, error);
    return !error && result;
}

bool isRegularFile(const std::filesystem::path& path)
{
    std::error_code error;
    const bool result = std::filesystem::is_regular_file(path, error);
    return !error && result;
}

std::optional<QVariant> firstValue(const INIFile& settings, std::initializer_list<const char*> keys)
{
    for (const auto* key : keys) {
        const QString qKey = QString::fromUtf8(key);
        if (settings.contains(qKey)) {
            return settings.value(qKey);
        }
    }
    return std::nullopt;
}

std::optional<bool> parseBool(const QVariant& value)
{
    if (value.userType() == QMetaType::Bool) {
        return value.toBool();
    }

    const QString text = value.toString().trimmed().toLower();
    if (text == QStringLiteral("true") || text == QStringLiteral("1") || text == QStringLiteral("yes")) {
        return true;
    }
    if (text == QStringLiteral("false") || text == QStringLiteral("0") || text == QStringLiteral("no")) {
        return false;
    }
    return std::nullopt;
}

std::optional<int> parseInt(const QVariant& value)
{
    bool ok = false;
    const int result = value.toInt(&ok);
    return ok ? std::optional<int>(result) : std::nullopt;
}

QString readString(
    const INIFile& settings,
    std::initializer_list<const char*> keys,
    const QString& defaultValue)
{
    if (const auto value = firstValue(settings, keys)) {
        return value->toString();
    }
    return defaultValue;
}

std::optional<bool> readBool(
    const INIFile& settings,
    std::initializer_list<const char*> keys,
    bool defaultValue)
{
    if (const auto value = firstValue(settings, keys)) {
        return parseBool(*value);
    }
    return defaultValue;
}

std::optional<int> readInt(
    const INIFile& settings,
    std::initializer_list<const char*> keys,
    int defaultValue)
{
    if (const auto value = firstValue(settings, keys)) {
        return parseInt(*value);
    }
    return defaultValue;
}

void setValue(INIFile& settings, const char* canonicalKey, std::initializer_list<const char*> aliases, QVariant value)
{
    settings.set(QString::fromUtf8(canonicalKey), std::move(value));
    for (const auto* alias : aliases) {
        if (std::strcmp(canonicalKey, alias) != 0) {
            settings.remove(QString::fromUtf8(alias));
        }
    }
}

void removeValues(INIFile& settings, std::initializer_list<const char*> keys)
{
    for (const auto* key : keys) {
        settings.remove(QString::fromUtf8(key));
    }
}

void applyProxySettings(const DomainSettings& settings)
{
    if (settings.proxyType == QStringLiteral("Default")) {
        QNetworkProxyFactory::setUseSystemConfiguration(true);
        return;
    }

    QNetworkProxyFactory::setUseSystemConfiguration(false);
    if (settings.proxyType == QStringLiteral("SOCKS5")) {
        QNetworkProxy::setApplicationProxy(QNetworkProxy(
            QNetworkProxy::Socks5Proxy, settings.proxyAddress, settings.proxyPort,
            settings.proxyUsername, settings.proxyPassword));
    } else if (settings.proxyType == QStringLiteral("HTTP")) {
        QNetworkProxy::setApplicationProxy(QNetworkProxy(
            QNetworkProxy::HttpProxy, settings.proxyAddress, settings.proxyPort,
            settings.proxyUsername, settings.proxyPassword));
    } else {
        QNetworkProxy::setApplicationProxy(QNetworkProxy(QNetworkProxy::NoProxy));
    }
}

QString normalizedServiceURL(QString value, bool requiresTrailingSlash)
{
    if (value.trimmed().isEmpty()) {
        return {};
    }
    QUrl url(value.trimmed());
    if (!url.isValid() || (url.scheme() != QStringLiteral("http") && url.scheme() != QStringLiteral("https"))) {
        return value;
    }
    const bool localhost = url.host() == QStringLiteral("localhost") || url.host() == QStringLiteral("127.0.0.1")
        || url.host() == QStringLiteral("::1");
    if (url.scheme() == QStringLiteral("http") && !localhost) {
        url.setScheme(QStringLiteral("https"));
    }
    if (requiresTrailingSlash && !url.path().endsWith(QLatin1Char('/'))) {
        url.setPath(url.path() + QLatin1Char('/'));
    }
    return url.toString();
}

std::optional<INIFile> loadINI(const std::filesystem::path& path)
{
    if (isSymlink(path)) {
        return std::nullopt;
    }
    std::error_code error;
    if (!std::filesystem::exists(path, error)) {
        return error ? std::nullopt : std::optional<INIFile>(INIFile{});
    }
    if (error || !isRegularFile(path)) {
        return std::nullopt;
    }

    INIFile settings;
    if (!settings.loadFile(QString::fromStdString(path.string()))) {
        return std::nullopt;
    }
    return settings;
}

bool saveINI(const std::filesystem::path& path, const INIFile& settings)
{
    if (isSymlink(path)) {
        return false;
    }

    INIFile copy = settings;
    return copy.saveFile(QString::fromStdString(path.string()));
}

std::optional<std::vector<std::string>> readLoaders(const INIFile& settings)
{
    const QString encoded = readString(settings, { "ModDownloadLoaders" }, QStringLiteral("[]"));
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(encoded.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isArray()) {
        return std::nullopt;
    }

    std::vector<std::string> loaders;
    std::set<std::string> identifiers;
    for (const auto& value : document.array()) {
        if (!value.isString()) {
            return std::nullopt;
        }
        const std::string loader = value.toString().trimmed().toStdString();
        if (loader.empty() || !identifiers.insert(loader).second) {
            return std::nullopt;
        }
        loaders.push_back(loader);
    }
    return loaders;
}

void writeLoaders(INIFile& settings, const std::vector<std::string>& loaders)
{
    QJsonArray array;
    for (const auto& loader : loaders) {
        array.append(QString::fromStdString(loader));
    }
    setValue(
        settings,
        "ModDownloadLoaders",
        { "ModDownloadLoaders" },
        QString::fromUtf8(QJsonDocument(array).toJson(QJsonDocument::Compact)));
}

std::optional<DomainSettings> loadDomain(const INIFile& settings)
{
    DomainSettings result;
    result.instanceDirectory = readString(settings, { "InstanceDir" }, result.instanceDirectory);
    result.iconTheme = readString(settings, { "IconTheme" }, result.iconTheme);
    result.applicationTheme = readString(settings, { "ApplicationTheme" }, result.applicationTheme);
    result.backgroundCat = readString(settings, { "BackgroundCat" }, result.backgroundCat);
    result.catFit = readString(settings, { "CatFit" }, result.catFit);
    result.language = readString(settings, { "Language" }, result.language);
    result.consoleFont = readString(settings, { "ConsoleFont" }, result.consoleFont);
    result.javaPath = readString(settings, { "JavaPath" }, result.javaPath);
    result.jvmArguments = readString(settings, { "JvmArgs" }, result.jvmArguments);
    result.preLaunchCommand = readString(settings, { "PreLaunchCommand", "PreLaunchCmd" }, result.preLaunchCommand);
    result.wrapperCommand = readString(settings, { "WrapperCommand" }, result.wrapperCommand);
    result.postExitCommand = readString(settings, { "PostExitCommand", "PostExitCmd" }, result.postExitCommand);
    result.customGLFWPath = readString(settings, { "CustomGLFWPath" }, result.customGLFWPath);
    result.customOpenALPath = readString(settings, { "CustomOpenALPath" }, result.customOpenALPath);
    result.pasteCustomAPIBase = readString(settings, { "PastebinCustomAPIBase" }, result.pasteCustomAPIBase);
    result.metadataURLOverride = readString(settings, { "MetaURLOverride" }, result.metadataURLOverride);
    result.assetsURLOverride = readString(settings, { "ResourceURLOverride", "ResourceURL" }, result.assetsURLOverride);
    result.legacyFMLLibrariesURLOverride = readString(settings, { "LegacyFMLLibsURLOverride" }, result.legacyFMLLibrariesURLOverride);
    result.userAgentOverride = readString(settings, { "UserAgentOverride" }, result.userAgentOverride);
    result.microsoftClientIDOverride = readString(settings, { "MSAClientIDOverride" }, result.microsoftClientIDOverride);
    result.curseForgeAPIKey = readString(settings, { "FlameKeyOverride" }, result.curseForgeAPIKey);
    result.modrinthToken = readString(settings, { "ModrinthToken" }, result.modrinthToken);
    result.technicClientID = readString(settings, { "TechnicClientID" }, result.technicClientID);
    result.proxyType = readString(settings, { "ProxyType" }, result.proxyType);
    result.proxyAddress = readString(settings, { "ProxyAddr", "ProxyHostName" }, result.proxyAddress);
    result.proxyUsername = readString(settings, { "ProxyUser", "ProxyUsername" }, result.proxyUsername);
    result.proxyPassword = readString(settings, { "ProxyPass", "ProxyPassword" }, result.proxyPassword);
    result.pasteCustomAPIBase = normalizedServiceURL(result.pasteCustomAPIBase, false);
    result.metadataURLOverride = normalizedServiceURL(result.metadataURLOverride, true);
    result.assetsURLOverride = normalizedServiceURL(result.assetsURLOverride, true);
    result.legacyFMLLibrariesURLOverride = normalizedServiceURL(result.legacyFMLLibrariesURLOverride, true);

    const auto catOpacity = readInt(settings, { "CatOpacity" }, result.catOpacity);
    const auto numberOfConcurrentTasks = readInt(settings, { "NumberOfConcurrentTasks" }, result.numberOfConcurrentTasks);
    const auto numberOfConcurrentDownloads = readInt(settings, { "NumberOfConcurrentDownloads" }, result.numberOfConcurrentDownloads);
    const auto numberOfManualRetries = readInt(settings, { "NumberOfManualRetries" }, result.numberOfManualRetries);
    const auto requestTimeoutSeconds = readInt(settings, { "RequestTimeout" }, result.requestTimeoutSeconds);
    const auto consoleFontSize = readInt(settings, { "ConsoleFontSize" }, result.consoleFontSize);
    const auto consoleMaxLines = readInt(settings, { "ConsoleMaxLines" }, result.consoleMaxLines);
    const auto windowWidth = readInt(settings, { "MinecraftWinWidth", "MCWindowWidth" }, result.windowWidth);
    const auto windowHeight = readInt(settings, { "MinecraftWinHeight", "MCWindowHeight" }, result.windowHeight);
    const auto minMemory = readInt(settings, { "MinMemAlloc", "MinMemoryAlloc" }, result.minMemoryMiB);
    const auto maxMemory = readInt(settings, { "MaxMemAlloc", "MaxMemoryAlloc" }, result.maxMemoryMiB);
    const auto permGen = readInt(settings, { "PermGen" }, result.permGenMiB);
    const auto pasteType = readInt(settings, { "PastebinType" }, result.pasteType);
    const auto proxyPort = readInt(settings, { "ProxyPort" }, result.proxyPort);

    const auto useSystemLocale = readBool(settings, { "UseSystemLocale" }, result.useSystemLocale);
    const auto menuBarInsteadOfToolBar = readBool(settings, { "MenuBarInsteadOfToolBar" }, result.menuBarInsteadOfToolBar);
    const auto statusBarVisible = readBool(settings, { "StatusBarVisible" }, result.statusBarVisible);
    const auto toolbarsLocked = readBool(settings, { "ToolbarsLocked" }, result.toolbarsLocked);
    const auto consoleOverflowStop = readBool(settings, { "ConsoleOverflowStop" }, result.consoleOverflowStop);
    const auto showConsole = readBool(settings, { "ShowConsole" }, result.showConsole);
    const auto autoCloseConsole = readBool(settings, { "AutoCloseConsole" }, result.autoCloseConsole);
    const auto showConsoleOnError = readBool(settings, { "ShowConsoleOnError" }, result.showConsoleOnError);
    const auto logPrePostOutput = readBool(settings, { "LogPrePostOutput" }, result.logPrePostOutput);
    const auto launchMaximized = readBool(settings, { "LaunchMaximized", "MCWindowMaximize" }, result.launchMaximized);
    const auto closeAfterLaunch = readBool(settings, { "CloseAfterLaunch" }, result.closeAfterLaunch);
    const auto quitAfterGameStop = readBool(settings, { "QuitAfterGameStop" }, result.quitAfterGameStop);
    const auto showGameTime = readBool(settings, { "ShowGameTime" }, result.showGameTime);
    const auto recordGameTime = readBool(settings, { "RecordGameTime" }, result.recordGameTime);
    const auto ignoreJavaCompatibility = readBool(settings, { "IgnoreJavaCompatibility" }, result.ignoreJavaCompatibility);
    const auto lowMemoryWarning = readBool(settings, { "LowMemWarning" }, result.lowMemoryWarning);
    const auto onlineFixes = readBool(settings, { "OnlineFixes" }, result.onlineFixes);
    const auto useNativeGLFW = readBool(settings, { "UseNativeGLFW" }, result.useNativeGLFW);
    const auto useNativeOpenAL = readBool(settings, { "UseNativeOpenAL" }, result.useNativeOpenAL);
    const auto refreshMetadataOnLaunch = readBool(settings, { "MetaRefreshOnLaunch" }, result.refreshMetadataOnLaunch);
    const auto fallbackForBlockedModrinthProjects = readBool(
        settings, { "FallbackMRBlockedMods" }, result.fallbackForBlockedModrinthProjects);

    if (!catOpacity || !numberOfConcurrentTasks || !numberOfConcurrentDownloads || !numberOfManualRetries
        || !requestTimeoutSeconds || !consoleFontSize || !consoleMaxLines || !windowWidth || !windowHeight || !minMemory
        || !maxMemory || !permGen || !useSystemLocale || !menuBarInsteadOfToolBar || !statusBarVisible || !toolbarsLocked
        || !consoleOverflowStop || !showConsole || !autoCloseConsole || !showConsoleOnError || !logPrePostOutput
        || !launchMaximized || !closeAfterLaunch || !quitAfterGameStop || !showGameTime || !recordGameTime
        || !ignoreJavaCompatibility || !lowMemoryWarning || !onlineFixes || !useNativeGLFW || !useNativeOpenAL
        || !pasteType || !proxyPort || !refreshMetadataOnLaunch || !fallbackForBlockedModrinthProjects) {
        return std::nullopt;
    }

    result.catOpacity = *catOpacity;
    result.numberOfConcurrentTasks = *numberOfConcurrentTasks;
    result.numberOfConcurrentDownloads = *numberOfConcurrentDownloads;
    result.numberOfManualRetries = *numberOfManualRetries;
    result.requestTimeoutSeconds = *requestTimeoutSeconds;
    result.consoleFontSize = *consoleFontSize;
    result.consoleMaxLines = *consoleMaxLines;
    result.windowWidth = *windowWidth;
    result.windowHeight = *windowHeight;
    result.minMemoryMiB = *minMemory;
    result.maxMemoryMiB = *maxMemory;
    result.permGenMiB = *permGen;
    result.useSystemLocale = *useSystemLocale;
    result.menuBarInsteadOfToolBar = *menuBarInsteadOfToolBar;
    result.statusBarVisible = *statusBarVisible;
    result.toolbarsLocked = *toolbarsLocked;
    result.consoleOverflowStop = *consoleOverflowStop;
    result.showConsole = *showConsole;
    result.autoCloseConsole = *autoCloseConsole;
    result.showConsoleOnError = *showConsoleOnError;
    result.logPrePostOutput = *logPrePostOutput;
    result.launchMaximized = *launchMaximized;
    result.closeAfterLaunch = *closeAfterLaunch;
    result.quitAfterGameStop = *quitAfterGameStop;
    result.showGameTime = *showGameTime;
    result.recordGameTime = *recordGameTime;
    result.ignoreJavaCompatibility = *ignoreJavaCompatibility;
    result.lowMemoryWarning = *lowMemoryWarning;
    result.onlineFixes = *onlineFixes;
    result.useNativeGLFW = *useNativeGLFW;
    result.useNativeOpenAL = *useNativeOpenAL;
    result.pasteType = *pasteType;
    result.proxyPort = *proxyPort;
    result.refreshMetadataOnLaunch = *refreshMetadataOnLaunch;
    result.fallbackForBlockedModrinthProjects = *fallbackForBlockedModrinthProjects;

    if (result.catFit != QStringLiteral("fit") && result.catFit != QStringLiteral("fill")
        && result.catFit != QStringLiteral("strech")) {
        result.catFit = QStringLiteral("strech");
    }
    if (result.catOpacity < 0 || result.catOpacity > 100 || result.numberOfConcurrentTasks < 1
        || result.numberOfConcurrentDownloads < 1 || result.numberOfManualRetries < 0 || result.requestTimeoutSeconds < 0
        || result.consoleFontSize < 5 || result.consoleFontSize > 16 || result.consoleMaxLines < 10000
        || result.consoleMaxLines > 1000000 || result.windowWidth < 1 || result.windowHeight < 1
        || result.minMemoryMiB < 8 || result.maxMemoryMiB < 8 || result.minMemoryMiB > result.maxMemoryMiB
        || result.permGenMiB < 4 || result.pasteType < 0 || result.pasteType > 3
        || result.proxyPort < 1 || result.proxyPort > 65535
        || (result.proxyType != QStringLiteral("Default") && result.proxyType != QStringLiteral("None")
            && result.proxyType != QStringLiteral("SOCKS5") && result.proxyType != QStringLiteral("HTTP"))) {
        return std::nullopt;
    }
    for (const QString& url : { result.pasteCustomAPIBase, result.metadataURLOverride, result.assetsURLOverride,
                                result.legacyFMLLibrariesURLOverride }) {
        if (!url.isEmpty()) {
            const QUrl parsed(url);
            if (!parsed.isValid() || (parsed.scheme() != QStringLiteral("https")
                                      && !(parsed.scheme() == QStringLiteral("http")
                                           && (parsed.host() == QStringLiteral("localhost")
                                               || parsed.host() == QStringLiteral("127.0.0.1")
                                               || parsed.host() == QStringLiteral("::1"))))) {
                return std::nullopt;
            }
        }
    }
    return result;
}

std::optional<INIFile> loadGlobalINI(const std::filesystem::path& path)
{
    return loadINI(path);
}

std::filesystem::path normalizeInstancesRoot(const std::filesystem::path& dataRoot)
{
    return (dataRoot / kDefaultInstancesDirectory).lexically_normal();
}

bool isSupportedInstanceDirectory(
    const std::filesystem::path& dataRoot,
    const std::filesystem::path& instancesRoot,
    const QString& configuredDirectory)
{
    const std::filesystem::path configuredPath = configuredDirectory.isEmpty()
        ? instancesRoot
        : (configuredDirectory.startsWith('/')
                ? std::filesystem::path(configuredDirectory.toStdString())
                : dataRoot / configuredDirectory.toStdString())
              .lexically_normal();
    return configuredPath == instancesRoot && !isSymlink(instancesRoot);
}

std::optional<DomainSettings> loadDomainFromRoot(
    const std::filesystem::path& dataRoot,
    const std::filesystem::path& instancesRoot,
    const std::filesystem::path& globalSettingsPath)
{
    const auto ini = loadGlobalINI(globalSettingsPath);
    if (!ini) {
        return std::nullopt;
    }
    auto domain = loadDomain(*ini);
    if (!domain || !isSupportedInstanceDirectory(dataRoot, instancesRoot, domain->instanceDirectory)) {
        return std::nullopt;
    }
    return domain;
}

FrontendGlobalSettingsSnapshot globalSnapshot(
    const std::filesystem::path& instancesRoot,
    const DomainSettings& domain)
{
    FrontendGlobalSettingsSnapshot snapshot;
    snapshot.instanceDirectory = instancesRoot;
    snapshot.iconTheme = domain.iconTheme.toStdString();
    snapshot.applicationTheme = domain.applicationTheme.toStdString();
    snapshot.backgroundCat = domain.backgroundCat.toStdString();
    snapshot.catOpacity = domain.catOpacity;
    snapshot.catFit = domain.catFit.toStdString();
    snapshot.language = domain.language.toStdString();
    snapshot.useSystemLocale = domain.useSystemLocale;
    snapshot.menuBarInsteadOfToolBar = domain.menuBarInsteadOfToolBar;
    snapshot.statusBarVisible = domain.statusBarVisible;
    snapshot.toolbarsLocked = domain.toolbarsLocked;
    snapshot.numberOfConcurrentTasks = domain.numberOfConcurrentTasks;
    snapshot.numberOfConcurrentDownloads = domain.numberOfConcurrentDownloads;
    snapshot.numberOfManualRetries = domain.numberOfManualRetries;
    snapshot.requestTimeoutSeconds = domain.requestTimeoutSeconds;
    snapshot.consoleFont = domain.consoleFont.toStdString();
    snapshot.consoleFontSize = domain.consoleFontSize;
    snapshot.consoleMaxLines = domain.consoleMaxLines;
    snapshot.consoleOverflowStop = domain.consoleOverflowStop;
    snapshot.showConsole = domain.showConsole;
    snapshot.autoCloseConsole = domain.autoCloseConsole;
    snapshot.showConsoleOnError = domain.showConsoleOnError;
    snapshot.logPrePostOutput = domain.logPrePostOutput;
    snapshot.pasteType = domain.pasteType;
    snapshot.pasteCustomAPIBase = domain.pasteCustomAPIBase.toStdString();
    snapshot.metadataURLOverride = domain.metadataURLOverride.toStdString();
    snapshot.refreshMetadataOnLaunch = domain.refreshMetadataOnLaunch;
    snapshot.assetsURLOverride = domain.assetsURLOverride.toStdString();
    snapshot.legacyFMLLibrariesURLOverride = domain.legacyFMLLibrariesURLOverride.toStdString();
    snapshot.fallbackForBlockedModrinthProjects = domain.fallbackForBlockedModrinthProjects;
    snapshot.userAgentOverride = domain.userAgentOverride.toStdString();
    snapshot.microsoftClientIDOverride = domain.microsoftClientIDOverride.toStdString();
    snapshot.curseForgeAPIKey = domain.curseForgeAPIKey.toStdString();
    snapshot.modrinthToken = domain.modrinthToken.toStdString();
    snapshot.technicClientID = domain.technicClientID.toStdString();
    snapshot.proxyType = domain.proxyType.toStdString();
    snapshot.proxyAddress = domain.proxyAddress.toStdString();
    snapshot.proxyPort = domain.proxyPort;
    snapshot.proxyUsername = domain.proxyUsername.toStdString();
    snapshot.proxyPassword = domain.proxyPassword.toStdString();
    return snapshot;
}

std::optional<bool> instanceBool(const INIFile& settings, const char* key, bool defaultValue)
{
    return readBool(settings, { key }, defaultValue);
}

std::optional<int> instanceInt(
    const INIFile& settings,
    std::initializer_list<const char*> keys,
    int defaultValue)
{
    return readInt(settings, keys, defaultValue);
}

std::optional<FrontendInstanceSettingsSnapshot> instanceSnapshot(
    const std::filesystem::path& dataRoot,
    const std::filesystem::path& instancesRoot,
    const std::filesystem::path& globalSettingsPath,
    const std::string& instanceIdentifier)
{
    if (!isSafeInstanceIdentifier(instanceIdentifier)) {
        return std::nullopt;
    }
    const auto instancePath = instancesRoot / instanceIdentifier;
    const auto configPath = instancePath / "instance.cfg";
    if (!isDirectChild(instancesRoot, instancePath) || isSymlink(instancePath) || isSymlink(configPath)
        || !isRegularFile(configPath)) {
        return std::nullopt;
    }

    const auto domain = loadDomainFromRoot(dataRoot, instancesRoot, globalSettingsPath);
    const auto settings = loadINI(configPath);
    if (!domain || !settings) {
        return std::nullopt;
    }

    FrontendInstanceSettingsSnapshot snapshot;
    snapshot.id = instanceIdentifier;

    const auto windowOverride = instanceBool(*settings, "OverrideWindow", false);
    const auto consoleOverride = instanceBool(*settings, "OverrideConsole", false);
    const auto gameTimeOverride = instanceBool(*settings, "OverrideGameTime", false);
    const auto javaLocationOverride = instanceBool(*settings, "OverrideJavaLocation", false);
    const auto javaArgumentsOverride = instanceBool(*settings, "OverrideJavaArgs", false);
    const auto memoryOverride = instanceBool(*settings, "OverrideMemory", false);
    const auto commandOverride = readBool(*settings, { "OverrideCommands", "OverrideLaunchCmd" }, false);
    const auto legacyOverride = instanceBool(*settings, "OverrideLegacySettings", false);
    const auto nativeOverride = instanceBool(*settings, "OverrideNativeWorkarounds", false);
    if (!windowOverride || !consoleOverride || !gameTimeOverride || !javaLocationOverride || !javaArgumentsOverride
        || !memoryOverride || !commandOverride || !legacyOverride || !nativeOverride) {
        return std::nullopt;
    }

    snapshot.windowOverrideEnabled = *windowOverride;
    const auto launchMaximized = snapshot.windowOverrideEnabled
        ? instanceBool(*settings, "LaunchMaximized", domain->launchMaximized)
        : std::optional<bool>(domain->launchMaximized);
    const auto windowWidth = snapshot.windowOverrideEnabled
        ? instanceInt(*settings, { "MinecraftWinWidth", "MCWindowWidth" }, domain->windowWidth)
        : std::optional<int>(domain->windowWidth);
    const auto windowHeight = snapshot.windowOverrideEnabled
        ? instanceInt(*settings, { "MinecraftWinHeight", "MCWindowHeight" }, domain->windowHeight)
        : std::optional<int>(domain->windowHeight);
    const auto closeAfterLaunch = snapshot.windowOverrideEnabled
        ? instanceBool(*settings, "CloseAfterLaunch", domain->closeAfterLaunch)
        : std::optional<bool>(domain->closeAfterLaunch);
    const auto quitAfterGameStop = snapshot.windowOverrideEnabled
        ? instanceBool(*settings, "QuitAfterGameStop", domain->quitAfterGameStop)
        : std::optional<bool>(domain->quitAfterGameStop);
    if (!launchMaximized || !windowWidth || !windowHeight || !closeAfterLaunch || !quitAfterGameStop) {
        return std::nullopt;
    }
    snapshot.launchMaximized = *launchMaximized;
    snapshot.windowWidth = *windowWidth;
    snapshot.windowHeight = *windowHeight;
    snapshot.closeAfterLaunch = *closeAfterLaunch;
    snapshot.quitAfterGameStop = *quitAfterGameStop;

    snapshot.consoleOverrideEnabled = *consoleOverride;
    const auto showConsole = snapshot.consoleOverrideEnabled
        ? instanceBool(*settings, "ShowConsole", domain->showConsole)
        : std::optional<bool>(domain->showConsole);
    const auto showConsoleOnError = snapshot.consoleOverrideEnabled
        ? instanceBool(*settings, "ShowConsoleOnError", domain->showConsoleOnError)
        : std::optional<bool>(domain->showConsoleOnError);
    const auto autoCloseConsole = snapshot.consoleOverrideEnabled
        ? instanceBool(*settings, "AutoCloseConsole", domain->autoCloseConsole)
        : std::optional<bool>(domain->autoCloseConsole);
    if (!showConsole || !showConsoleOnError || !autoCloseConsole) {
        return std::nullopt;
    }
    snapshot.showConsole = *showConsole;
    snapshot.showConsoleOnError = *showConsoleOnError;
    snapshot.autoCloseConsole = *autoCloseConsole;

    const auto globalDataPacksEnabled = instanceBool(*settings, "GlobalDataPacksEnabled", false);
    if (!globalDataPacksEnabled) {
        return std::nullopt;
    }
    snapshot.globalDataPacksEnabled = *globalDataPacksEnabled;
    snapshot.globalDataPacksPath = readString(*settings, { "GlobalDataPacksPath" }, {}).toStdString();

    snapshot.gameTimeOverrideEnabled = *gameTimeOverride;
    const auto showGameTime = snapshot.gameTimeOverrideEnabled
        ? instanceBool(*settings, "ShowGameTime", domain->showGameTime)
        : std::optional<bool>(domain->showGameTime);
    const auto recordGameTime = snapshot.gameTimeOverrideEnabled
        ? instanceBool(*settings, "RecordGameTime", domain->recordGameTime)
        : std::optional<bool>(domain->recordGameTime);
    const auto countGameTime = instanceBool(*settings, "CountGameTime", true);
    if (!showGameTime || !recordGameTime || !countGameTime) {
        return std::nullopt;
    }
    snapshot.showGameTime = *showGameTime;
    snapshot.recordGameTime = *recordGameTime;
    snapshot.countGameTime = *countGameTime;

    const auto joinServerOnLaunch = instanceBool(*settings, "JoinServerOnLaunch", false);
    if (!joinServerOnLaunch) {
        return std::nullopt;
    }
    snapshot.joinServerOnLaunch = *joinServerOnLaunch;
    snapshot.joinServerAddress = readString(*settings, { "JoinServerOnLaunchAddress" }, {}).toStdString();
    snapshot.joinWorld = readString(*settings, { "JoinWorldOnLaunch" }, {}).toStdString();
    snapshot.joinTarget = !snapshot.joinServerAddress.empty() ? FrontendInstanceJoinTarget::Server
                                                               : (!snapshot.joinWorld.empty() ? FrontendInstanceJoinTarget::World
                                                                                              : FrontendInstanceJoinTarget::None);

    const auto overrideModDownloadLoaders = instanceBool(*settings, "OverrideModDownloadLoaders", false);
    const auto loaders = readLoaders(*settings);
    if (!overrideModDownloadLoaders || !loaders) {
        return std::nullopt;
    }
    snapshot.overrideModDownloadLoaders = *overrideModDownloadLoaders;
    snapshot.modDownloadLoaders = *loaders;

    snapshot.javaLocationOverrideEnabled = *javaLocationOverride;
    const auto javaPath = snapshot.javaLocationOverrideEnabled
        ? std::optional<QString>(readString(*settings, { "JavaPath" }, domain->javaPath))
        : std::optional<QString>(domain->javaPath);
    const auto ignoreJavaCompatibility = snapshot.javaLocationOverrideEnabled
        ? instanceBool(*settings, "IgnoreJavaCompatibility", domain->ignoreJavaCompatibility)
        : std::optional<bool>(domain->ignoreJavaCompatibility);
    if (!javaPath || !ignoreJavaCompatibility) {
        return std::nullopt;
    }
    snapshot.javaPath = javaPath->toStdString();
    snapshot.ignoreJavaCompatibility = *ignoreJavaCompatibility;

    snapshot.memoryOverrideEnabled = *memoryOverride;
    const auto minMemory = snapshot.memoryOverrideEnabled
        ? instanceInt(*settings, { "MinMemAlloc", "MinMemoryAlloc" }, domain->minMemoryMiB)
        : std::optional<int>(domain->minMemoryMiB);
    const auto maxMemory = snapshot.memoryOverrideEnabled
        ? instanceInt(*settings, { "MaxMemAlloc", "MaxMemoryAlloc" }, domain->maxMemoryMiB)
        : std::optional<int>(domain->maxMemoryMiB);
    const auto permGen = snapshot.memoryOverrideEnabled
        ? instanceInt(*settings, { "PermGen" }, domain->permGenMiB)
        : std::optional<int>(domain->permGenMiB);
    const auto lowMemoryWarning = snapshot.memoryOverrideEnabled
        ? instanceBool(*settings, "LowMemWarning", domain->lowMemoryWarning)
        : std::optional<bool>(domain->lowMemoryWarning);
    if (!minMemory || !maxMemory || !permGen || !lowMemoryWarning) {
        return std::nullopt;
    }
    snapshot.minMemoryMiB = *minMemory;
    snapshot.maxMemoryMiB = *maxMemory;
    snapshot.permGenMiB = *permGen;
    snapshot.lowMemoryWarning = *lowMemoryWarning;

    snapshot.javaArgumentsOverrideEnabled = *javaArgumentsOverride;
    snapshot.jvmArguments = snapshot.javaArgumentsOverrideEnabled
        ? readString(*settings, { "JvmArgs" }, domain->jvmArguments).toStdString()
        : domain->jvmArguments.toStdString();

    snapshot.commandOverrideEnabled = *commandOverride;
    snapshot.preLaunchCommand = snapshot.commandOverrideEnabled
        ? readString(*settings, { "PreLaunchCommand", "PreLaunchCmd" }, domain->preLaunchCommand).toStdString()
        : domain->preLaunchCommand.toStdString();
    snapshot.wrapperCommand = snapshot.commandOverrideEnabled
        ? readString(*settings, { "WrapperCommand" }, domain->wrapperCommand).toStdString()
        : domain->wrapperCommand.toStdString();
    snapshot.postExitCommand = snapshot.commandOverrideEnabled
        ? readString(*settings, { "PostExitCommand", "PostExitCmd" }, domain->postExitCommand).toStdString()
        : domain->postExitCommand.toStdString();

    snapshot.legacySettingsOverrideEnabled = *legacyOverride;
    snapshot.onlineFixes = snapshot.legacySettingsOverrideEnabled
        ? instanceBool(*settings, "OnlineFixes", domain->onlineFixes).value_or(domain->onlineFixes)
        : domain->onlineFixes;

    snapshot.nativeWorkaroundsOverrideEnabled = *nativeOverride;
    snapshot.useNativeGLFW = snapshot.nativeWorkaroundsOverrideEnabled
        ? instanceBool(*settings, "UseNativeGLFW", domain->useNativeGLFW).value_or(domain->useNativeGLFW)
        : domain->useNativeGLFW;
    snapshot.customGLFWPath = snapshot.nativeWorkaroundsOverrideEnabled
        ? readString(*settings, { "CustomGLFWPath" }, domain->customGLFWPath).toStdString()
        : domain->customGLFWPath.toStdString();
    snapshot.useNativeOpenAL = snapshot.nativeWorkaroundsOverrideEnabled
        ? instanceBool(*settings, "UseNativeOpenAL", domain->useNativeOpenAL).value_or(domain->useNativeOpenAL)
        : domain->useNativeOpenAL;
    snapshot.customOpenALPath = snapshot.nativeWorkaroundsOverrideEnabled
        ? readString(*settings, { "CustomOpenALPath" }, domain->customOpenALPath).toStdString()
        : domain->customOpenALPath.toStdString();

    return snapshot;
}

void writeOverride(INIFile& settings, const char* key, bool enabled)
{
    setValue(settings, key, { key }, enabled);
}

void writeInstanceSnapshot(INIFile& settings, const FrontendInstanceSettingsSnapshot& snapshot)
{
    writeOverride(settings, "OverrideWindow", snapshot.windowOverrideEnabled);
    if (snapshot.windowOverrideEnabled) {
        setValue(settings, "LaunchMaximized", { "LaunchMaximized", "MCWindowMaximize" }, snapshot.launchMaximized);
        setValue(settings, "MinecraftWinWidth", { "MinecraftWinWidth", "MCWindowWidth" }, snapshot.windowWidth);
        setValue(settings, "MinecraftWinHeight", { "MinecraftWinHeight", "MCWindowHeight" }, snapshot.windowHeight);
        setValue(settings, "CloseAfterLaunch", { "CloseAfterLaunch" }, snapshot.closeAfterLaunch);
        setValue(settings, "QuitAfterGameStop", { "QuitAfterGameStop" }, snapshot.quitAfterGameStop);
    } else {
        removeValues(settings, { "LaunchMaximized", "MCWindowMaximize", "MinecraftWinWidth", "MCWindowWidth",
                                 "MinecraftWinHeight", "MCWindowHeight", "CloseAfterLaunch", "QuitAfterGameStop" });
    }

    writeOverride(settings, "OverrideConsole", snapshot.consoleOverrideEnabled);
    if (snapshot.consoleOverrideEnabled) {
        setValue(settings, "ShowConsole", { "ShowConsole" }, snapshot.showConsole);
        setValue(settings, "ShowConsoleOnError", { "ShowConsoleOnError" }, snapshot.showConsoleOnError);
        setValue(settings, "AutoCloseConsole", { "AutoCloseConsole" }, snapshot.autoCloseConsole);
    } else {
        removeValues(settings, { "ShowConsole", "ShowConsoleOnError", "AutoCloseConsole" });
    }

    setValue(settings, "GlobalDataPacksEnabled", { "GlobalDataPacksEnabled" }, snapshot.globalDataPacksEnabled);
    setValue(settings, "GlobalDataPacksPath", { "GlobalDataPacksPath" }, QString::fromStdString(snapshot.globalDataPacksPath));

    writeOverride(settings, "OverrideGameTime", snapshot.gameTimeOverrideEnabled);
    if (snapshot.gameTimeOverrideEnabled) {
        setValue(settings, "ShowGameTime", { "ShowGameTime" }, snapshot.showGameTime);
        setValue(settings, "RecordGameTime", { "RecordGameTime" }, snapshot.recordGameTime);
    } else {
        removeValues(settings, { "ShowGameTime", "RecordGameTime" });
    }
    setValue(settings, "CountGameTime", { "CountGameTime" }, snapshot.countGameTime);

    setValue(settings, "JoinServerOnLaunch", { "JoinServerOnLaunch" }, snapshot.joinServerOnLaunch);
    if (!snapshot.joinServerOnLaunch || snapshot.joinTarget == FrontendInstanceJoinTarget::None) {
        removeValues(settings, { "JoinServerOnLaunchAddress", "JoinWorldOnLaunch" });
    } else if (snapshot.joinTarget == FrontendInstanceJoinTarget::Server) {
        setValue(settings, "JoinServerOnLaunchAddress", { "JoinServerOnLaunchAddress" },
                 QString::fromStdString(snapshot.joinServerAddress));
        removeValues(settings, { "JoinWorldOnLaunch" });
    } else {
        setValue(settings, "JoinWorldOnLaunch", { "JoinWorldOnLaunch" }, QString::fromStdString(snapshot.joinWorld));
        removeValues(settings, { "JoinServerOnLaunchAddress" });
    }

    setValue(settings, "OverrideModDownloadLoaders", { "OverrideModDownloadLoaders" }, snapshot.overrideModDownloadLoaders);
    writeLoaders(settings, snapshot.modDownloadLoaders);

    writeOverride(settings, "OverrideJavaLocation", snapshot.javaLocationOverrideEnabled);
    if (snapshot.javaLocationOverrideEnabled) {
        setValue(settings, "JavaPath", { "JavaPath" }, QString::fromStdString(snapshot.javaPath));
        setValue(settings, "IgnoreJavaCompatibility", { "IgnoreJavaCompatibility" }, snapshot.ignoreJavaCompatibility);
    } else {
        removeValues(settings, { "JavaPath", "IgnoreJavaCompatibility" });
    }

    writeOverride(settings, "OverrideMemory", snapshot.memoryOverrideEnabled);
    if (snapshot.memoryOverrideEnabled) {
        setValue(settings, "MinMemAlloc", { "MinMemAlloc", "MinMemoryAlloc" }, snapshot.minMemoryMiB);
        setValue(settings, "MaxMemAlloc", { "MaxMemAlloc", "MaxMemoryAlloc" }, snapshot.maxMemoryMiB);
        setValue(settings, "PermGen", { "PermGen" }, snapshot.permGenMiB);
        setValue(settings, "LowMemWarning", { "LowMemWarning" }, snapshot.lowMemoryWarning);
    } else {
        removeValues(settings, { "MinMemAlloc", "MinMemoryAlloc", "MaxMemAlloc", "MaxMemoryAlloc", "PermGen", "LowMemWarning" });
    }

    writeOverride(settings, "OverrideJavaArgs", snapshot.javaArgumentsOverrideEnabled);
    if (snapshot.javaArgumentsOverrideEnabled) {
        setValue(settings, "JvmArgs", { "JvmArgs" }, QString::fromStdString(snapshot.jvmArguments));
    } else {
        removeValues(settings, { "JvmArgs" });
    }

    setValue(settings, "OverrideCommands", { "OverrideCommands", "OverrideLaunchCmd" }, snapshot.commandOverrideEnabled);
    if (snapshot.commandOverrideEnabled) {
        setValue(settings, "PreLaunchCommand", { "PreLaunchCommand", "PreLaunchCmd" },
                 QString::fromStdString(snapshot.preLaunchCommand));
        setValue(settings, "WrapperCommand", { "WrapperCommand" }, QString::fromStdString(snapshot.wrapperCommand));
        setValue(settings, "PostExitCommand", { "PostExitCommand", "PostExitCmd" },
                 QString::fromStdString(snapshot.postExitCommand));
    } else {
        removeValues(settings, { "PreLaunchCommand", "PreLaunchCmd", "WrapperCommand", "PostExitCommand", "PostExitCmd" });
    }

    writeOverride(settings, "OverrideLegacySettings", snapshot.legacySettingsOverrideEnabled);
    if (snapshot.legacySettingsOverrideEnabled) {
        setValue(settings, "OnlineFixes", { "OnlineFixes" }, snapshot.onlineFixes);
    } else {
        removeValues(settings, { "OnlineFixes" });
    }

    writeOverride(settings, "OverrideNativeWorkarounds", snapshot.nativeWorkaroundsOverrideEnabled);
    if (snapshot.nativeWorkaroundsOverrideEnabled) {
        setValue(settings, "UseNativeGLFW", { "UseNativeGLFW" }, snapshot.useNativeGLFW);
        setValue(settings, "CustomGLFWPath", { "CustomGLFWPath" }, QString::fromStdString(snapshot.customGLFWPath));
        setValue(settings, "UseNativeOpenAL", { "UseNativeOpenAL" }, snapshot.useNativeOpenAL);
        setValue(settings, "CustomOpenALPath", { "CustomOpenALPath" }, QString::fromStdString(snapshot.customOpenALPath));
    } else {
        removeValues(settings, { "UseNativeGLFW", "CustomGLFWPath", "UseNativeOpenAL", "CustomOpenALPath" });
    }
}

void writeGlobalSnapshot(INIFile& settings, const FrontendGlobalSettingsSnapshot& snapshot)
{
    setValue(settings, "InstanceDir", { "InstanceDir" }, QStringLiteral("instances"));
    setValue(settings, "IconTheme", { "IconTheme" }, QString::fromStdString(snapshot.iconTheme));
    setValue(settings, "ApplicationTheme", { "ApplicationTheme" }, QString::fromStdString(snapshot.applicationTheme));
    setValue(settings, "BackgroundCat", { "BackgroundCat" }, QString::fromStdString(snapshot.backgroundCat));
    setValue(settings, "CatOpacity", { "CatOpacity" }, snapshot.catOpacity);
    setValue(settings, "CatFit", { "CatFit" }, QString::fromStdString(snapshot.catFit));
    setValue(settings, "Language", { "Language" }, QString::fromStdString(snapshot.language));
    setValue(settings, "UseSystemLocale", { "UseSystemLocale" }, snapshot.useSystemLocale);
    setValue(settings, "MenuBarInsteadOfToolBar", { "MenuBarInsteadOfToolBar" }, snapshot.menuBarInsteadOfToolBar);
    setValue(settings, "StatusBarVisible", { "StatusBarVisible" }, snapshot.statusBarVisible);
    setValue(settings, "ToolbarsLocked", { "ToolbarsLocked" }, snapshot.toolbarsLocked);
    setValue(settings, "NumberOfConcurrentTasks", { "NumberOfConcurrentTasks" }, snapshot.numberOfConcurrentTasks);
    setValue(settings, "NumberOfConcurrentDownloads", { "NumberOfConcurrentDownloads" }, snapshot.numberOfConcurrentDownloads);
    setValue(settings, "NumberOfManualRetries", { "NumberOfManualRetries" }, snapshot.numberOfManualRetries);
    setValue(settings, "RequestTimeout", { "RequestTimeout" }, snapshot.requestTimeoutSeconds);
    setValue(settings, "ConsoleFont", { "ConsoleFont" }, QString::fromStdString(snapshot.consoleFont));
    setValue(settings, "ConsoleFontSize", { "ConsoleFontSize" }, snapshot.consoleFontSize);
    setValue(settings, "ConsoleMaxLines", { "ConsoleMaxLines" }, snapshot.consoleMaxLines);
    setValue(settings, "ConsoleOverflowStop", { "ConsoleOverflowStop" }, snapshot.consoleOverflowStop);
    setValue(settings, "ShowConsole", { "ShowConsole" }, snapshot.showConsole);
    setValue(settings, "AutoCloseConsole", { "AutoCloseConsole" }, snapshot.autoCloseConsole);
    setValue(settings, "ShowConsoleOnError", { "ShowConsoleOnError" }, snapshot.showConsoleOnError);
    setValue(settings, "LogPrePostOutput", { "LogPrePostOutput" }, snapshot.logPrePostOutput);
    setValue(settings, "PastebinType", { "PastebinType" }, snapshot.pasteType);
    setValue(settings, "PastebinCustomAPIBase", { "PastebinCustomAPIBase" }, QString::fromStdString(snapshot.pasteCustomAPIBase));
    setValue(settings, "MetaURLOverride", { "MetaURLOverride" }, QString::fromStdString(snapshot.metadataURLOverride));
    setValue(settings, "MetaRefreshOnLaunch", { "MetaRefreshOnLaunch" }, snapshot.refreshMetadataOnLaunch);
    setValue(settings, "ResourceURLOverride", { "ResourceURLOverride", "ResourceURL" }, QString::fromStdString(snapshot.assetsURLOverride));
    setValue(settings, "LegacyFMLLibsURLOverride", { "LegacyFMLLibsURLOverride" }, QString::fromStdString(snapshot.legacyFMLLibrariesURLOverride));
    setValue(settings, "FallbackMRBlockedMods", { "FallbackMRBlockedMods" }, snapshot.fallbackForBlockedModrinthProjects);
    setValue(settings, "UserAgentOverride", { "UserAgentOverride" }, QString::fromStdString(snapshot.userAgentOverride));
    setValue(settings, "MSAClientIDOverride", { "MSAClientIDOverride" }, QString::fromStdString(snapshot.microsoftClientIDOverride));
    setValue(settings, "FlameKeyOverride", { "FlameKeyOverride" }, QString::fromStdString(snapshot.curseForgeAPIKey));
    setValue(settings, "ModrinthToken", { "ModrinthToken" }, QString::fromStdString(snapshot.modrinthToken));
    setValue(settings, "TechnicClientID", { "TechnicClientID" }, QString::fromStdString(snapshot.technicClientID));
    setValue(settings, "ProxyType", { "ProxyType" }, QString::fromStdString(snapshot.proxyType));
    setValue(settings, "ProxyAddr", { "ProxyAddr", "ProxyHostName" }, QString::fromStdString(snapshot.proxyAddress));
    setValue(settings, "ProxyPort", { "ProxyPort" }, snapshot.proxyPort);
    setValue(settings, "ProxyUser", { "ProxyUser", "ProxyUsername" }, QString::fromStdString(snapshot.proxyUsername));
    setValue(settings, "ProxyPass", { "ProxyPass", "ProxyPassword" }, QString::fromStdString(snapshot.proxyPassword));
}

}  // namespace

ProductionSettingsRuntime::ProductionSettingsRuntime(std::filesystem::path dataRoot)
    : m_dataRoot(normalizeRoot(std::move(dataRoot))),
      m_instancesRoot(normalizeInstancesRoot(m_dataRoot)),
      m_globalSettingsPath(m_dataRoot / kGlobalSettingsFile)
{
    std::error_code error;
    if (std::filesystem::exists(m_dataRoot, error) && (error || isSymlink(m_dataRoot))) {
        throw std::invalid_argument("Production settings runtime rejects a symlinked data root");
    }
    std::filesystem::create_directories(m_instancesRoot, error);
    if (error || isSymlink(m_instancesRoot) || !std::filesystem::is_directory(m_instancesRoot, error) || error) {
        throw std::runtime_error("Production settings runtime could not create its instance root");
    }
}

ProductionSettingsRuntime::~ProductionSettingsRuntime() noexcept
{
    shutdown();
}

std::optional<FrontendGlobalSettingsSnapshot> ProductionSettingsRuntime::globalSettings()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown) {
        return std::nullopt;
    }
    const auto domain = loadDomainFromRoot(m_dataRoot, m_instancesRoot, m_globalSettingsPath);
    if (!domain) {
        return std::nullopt;
    }
    applyProxySettings(*domain);
    return globalSnapshot(m_instancesRoot, *domain);
}

FrontendGlobalSettingsUpdateResult ProductionSettingsRuntime::updateGlobalSettings(
    const FrontendGlobalSettingsSnapshot& settings)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown || settings.instanceDirectory.lexically_normal() != m_instancesRoot) {
        return {};
    }

    auto currentINI = loadGlobalINI(m_globalSettingsPath);
    if (!currentINI) {
        return {};
    }
    INIFile original = *currentINI;
    writeGlobalSnapshot(*currentINI, settings);
    if (!saveINI(m_globalSettingsPath, *currentINI)) {
        static_cast<void>(saveINI(m_globalSettingsPath, original));
        return {};
    }

    const auto domain = loadDomainFromRoot(m_dataRoot, m_instancesRoot, m_globalSettingsPath);
    if (!domain) {
        static_cast<void>(saveINI(m_globalSettingsPath, original));
        return {};
    }
    applyProxySettings(*domain);
    return { FrontendGlobalSettingsUpdateOutcome::Succeeded, globalSnapshot(m_instancesRoot, *domain) };
}

std::optional<FrontendInstanceSettingsSnapshot> ProductionSettingsRuntime::instanceSettings(
    const std::string& instanceIdentifier)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown) {
        return std::nullopt;
    }
    return instanceSnapshot(m_dataRoot, m_instancesRoot, m_globalSettingsPath, instanceIdentifier);
}

FrontendInstanceSettingsUpdateResult ProductionSettingsRuntime::updateInstanceSettings(
    const std::string& instanceIdentifier,
    const FrontendInstanceSettingsSnapshot& settings)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown || settings.id != instanceIdentifier || !isSafeInstanceIdentifier(instanceIdentifier)) {
        return {};
    }

    const auto instancePath = m_instancesRoot / instanceIdentifier;
    const auto configPath = instancePath / "instance.cfg";
    if (!isDirectChild(m_instancesRoot, instancePath) || isSymlink(instancePath) || isSymlink(configPath)
        || !isRegularFile(configPath)) {
        return { FrontendInstanceSettingsUpdateOutcome::UnknownInstance, std::nullopt };
    }

    auto currentINI = loadINI(configPath);
    if (!currentINI) {
        return {};
    }
    INIFile original = *currentINI;
    writeInstanceSnapshot(*currentINI, settings);
    if (!saveINI(configPath, *currentINI)) {
        static_cast<void>(saveINI(configPath, original));
        return {};
    }

    const auto confirmed = instanceSnapshot(m_dataRoot, m_instancesRoot, m_globalSettingsPath, instanceIdentifier);
    if (!confirmed) {
        static_cast<void>(saveINI(configPath, original));
        return {};
    }
    return { FrontendInstanceSettingsUpdateOutcome::Succeeded, *confirmed };
}

void ProductionSettingsRuntime::shutdown() noexcept
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_shutdown = true;
}

std::shared_ptr<ProductionSettingsRuntime> makeProductionSettingsRuntime(std::filesystem::path dataRoot)
{
    return std::make_shared<ProductionSettingsRuntime>(std::move(dataRoot));
}
