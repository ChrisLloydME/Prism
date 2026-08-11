// SPDX-License-Identifier: GPL-3.0-only

#include "ProductionProviderRuntime.h"

#include "BuildConfig.h"
#include "Json.h"
#include "archive/ArchiveReader.h"
#include "minecraft/OneSixVersionFormat.h"
#include "minecraft/VersionFile.h"
#include "modplatform/atlauncher/ATLPackIndex.h"
#include "modplatform/atlauncher/ATLPackManifest.h"
#include "modplatform/ftb/FTBPackManifest.h"
#include "modplatform/technic/SolderPackManifest.h"
#include "settings/INIFile.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QEventLoop>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QRegularExpression>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#include <QXmlStreamReader>

#include <archive.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <limits>
#include <map>
#include <set>
#include <stdexcept>
#include <string_view>
#include <system_error>
#include <utility>

namespace {

constexpr std::size_t kMaximumPayloadBytes = 256U * 1024U * 1024U;
constexpr std::size_t kMaximumArchiveEntries = 100000;
constexpr std::size_t kMaximumArchiveBytes = 256U * 1024U * 1024U;
constexpr std::size_t kMaximumCacheEntries = 256;
constexpr std::uintmax_t kMaximumCacheBytes = 512U * 1024U * 1024U;

using Bytes = ProductionProviderRuntime::DownloadBytes;

std::filesystem::path normalizeRoot(std::filesystem::path root)
{
    root = std::move(root).lexically_normal();
    if (root.empty() || !root.is_absolute()) {
        throw std::invalid_argument("Provider runtime requires an absolute data root");
    }
    return root;
}

bool isSymlink(const std::filesystem::path& path)
{
    std::error_code error;
    const auto status = std::filesystem::symlink_status(path, error);
    return !error && std::filesystem::is_symlink(status);
}

bool isRegularFile(const std::filesystem::path& path)
{
    std::error_code error;
    return std::filesystem::is_regular_file(path, error) && !error && !isSymlink(path);
}

bool isDirectory(const std::filesystem::path& path)
{
    std::error_code error;
    return std::filesystem::is_directory(path, error) && !error && !isSymlink(path);
}

bool isSafeText(const std::string& value, std::size_t maximum, bool allowEmpty = false)
{
    if ((!allowEmpty && value.empty()) || value.size() > maximum) {
        return false;
    }
    return std::all_of(value.begin(), value.end(), [](unsigned char character) {
        return character != 0 && character != '\r' && character != '\n' && character != 0x7f;
    });
}

bool isSafeComponent(const std::string& value, std::size_t maximum = 255)
{
    return isSafeText(value, maximum) && value != "." && value != ".."
        && std::all_of(value.begin(), value.end(), [](unsigned char character) {
               return character != '/' && character != '\\';
           });
}

bool isCancellationRequested(const std::function<bool()>& cancellation)
{
    return cancellation && cancellation();
}

QByteArray byteArrayFromVector(const Bytes& bytes)
{
    if (bytes.empty() || bytes.size() > static_cast<std::size_t>(std::numeric_limits<qsizetype>::max())) {
        return {};
    }
    return QByteArray(reinterpret_cast<const char*>(bytes.data()), static_cast<qsizetype>(bytes.size()));
}

Bytes vectorFromByteArray(const QByteArray& bytes)
{
    return Bytes(reinterpret_cast<const std::uint8_t*>(bytes.constData()),
                 reinterpret_cast<const std::uint8_t*>(bytes.constData()) + bytes.size());
}

bool pathIsContained(const std::filesystem::path& root, const std::filesystem::path& candidate)
{
    const auto relative = candidate.lexically_normal().lexically_relative(root.lexically_normal());
    if (relative.empty() || relative.is_absolute() || relative.has_root_path()
        || std::any_of(relative.begin(), relative.end(), [](const auto& component) {
               return component == std::filesystem::path("..");
           })) {
        return false;
    }

    std::filesystem::path current = root.lexically_normal();
    std::error_code error;
    if (isSymlink(current)) {
        return false;
    }
    for (const auto& component : relative) {
        current /= component;
        const auto status = std::filesystem::symlink_status(current, error);
        if (error) {
            if (error == std::errc::no_such_file_or_directory) {
                return true;
            }
            return false;
        }
        if (std::filesystem::is_symlink(status)) {
            return false;
        }
        error.clear();
    }
    return true;
}

bool writeBytes(const std::filesystem::path& path, const QByteArray& bytes)
{
    std::error_code error;
    std::filesystem::create_directories(path.parent_path(), error);
    if (error || isSymlink(path.parent_path()) || !pathIsContained(path.parent_path(), path)) {
        return false;
    }

    QSaveFile file(QString::fromStdString(path.string()));
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size()) {
        file.cancelWriting();
        return false;
    }
    return file.commit();
}

bool writeText(const std::filesystem::path& path, const QJsonDocument& document)
{
    return writeBytes(path, document.toJson(QJsonDocument::Indented));
}

std::optional<QByteArray> readBytes(const std::filesystem::path& path)
{
    if (!isRegularFile(path)) {
        return std::nullopt;
    }
    QFile file(QString::fromStdString(path.string()));
    if (!file.open(QIODevice::ReadOnly)) {
        return std::nullopt;
    }
    const auto bytes = file.readAll();
    if (bytes.isEmpty() || bytes.size() > static_cast<qsizetype>(kMaximumPayloadBytes)) {
        return std::nullopt;
    }
    return bytes;
}

std::optional<QJsonDocument> parseJson(const Bytes& bytes, QString& diagnostic)
{
    const auto data = byteArrayFromVector(bytes);
    if (data.isEmpty()) {
        diagnostic = QStringLiteral("Provider response was empty.");
        return std::nullopt;
    }
    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(data, &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        diagnostic = QStringLiteral("Provider response is not valid JSON: %1").arg(parseError.errorString());
        return std::nullopt;
    }
    return document;
}

QString providerName(FrontendProviderKind provider)
{
    switch (provider) {
        case FrontendProviderKind::Modrinth:
            return QStringLiteral("modrinth");
        case FrontendProviderKind::CurseForge:
            return QStringLiteral("curseforge");
        case FrontendProviderKind::FTB:
            return QStringLiteral("ftb");
        case FrontendProviderKind::ATLauncher:
            return QStringLiteral("atlauncher");
        case FrontendProviderKind::Technic:
            return QStringLiteral("technic");
        case FrontendProviderKind::LegacyFTB:
            return QStringLiteral("legacy-ftb");
    }
    return QStringLiteral("provider");
}

QString encodePath(QString value)
{
    return QString::fromUtf8(QUrl::toPercentEncoding(value.toUtf8(), QByteArray(), QByteArray()));
}

QStringList stringArray(const QJsonValue& value)
{
    QStringList values;
    for (const auto& item : value.toArray()) {
        if (item.isString()) {
            const auto text = item.toString().trimmed();
            if (!text.isEmpty() && !values.contains(text)) {
                values.append(text);
            }
        }
    }
    return values;
}

FrontendProviderReleaseType releaseType(const QJsonValue& value)
{
    if (value.isDouble()) {
        switch (value.toInt()) {
            case 1:
                return FrontendProviderReleaseType::Release;
            case 2:
                return FrontendProviderReleaseType::Beta;
            case 3:
                return FrontendProviderReleaseType::Alpha;
            default:
                return FrontendProviderReleaseType::Unknown;
        }
    }
    const auto raw = value.toString().toLower();
    if (raw == QStringLiteral("release")) {
        return FrontendProviderReleaseType::Release;
    }
    if (raw == QStringLiteral("beta")) {
        return FrontendProviderReleaseType::Beta;
    }
    if (raw == QStringLiteral("alpha")) {
        return FrontendProviderReleaseType::Alpha;
    }
    return FrontendProviderReleaseType::Unknown;
}

std::int64_t unixSeconds(const QJsonValue& value)
{
    if (value.isDouble()) {
        return static_cast<std::int64_t>(value.toDouble());
    }
    const auto date = QDateTime::fromString(value.toString(), Qt::ISODateWithMs);
    return date.isValid() ? date.toSecsSinceEpoch() : 0;
}

FrontendProviderPackSnapshot packSnapshot(
    FrontendProviderKind provider,
    QString id,
    QString name,
    QString slug,
    QString summary,
    QString author,
    QStringList categories)
{
    FrontendProviderPackSnapshot result;
    result.provider = provider;
    result.id = id.toStdString();
    result.name = name.toStdString();
    result.slug = slug.toStdString();
    result.summary = summary.toStdString();
    result.author = author.toStdString();
    for (const auto& category : categories) {
        result.categories.push_back(category.toStdString());
    }
    return result;
}

FrontendProviderVersionSnapshot versionSnapshot(
    FrontendProviderKind provider,
    FrontendProviderInstallKind installKind,
    QString id,
    QString packIdentifier,
    QString name,
    QString version,
    QStringList gameVersions,
    QStringList loaders,
    FrontendProviderReleaseType release,
    std::int64_t published,
    bool recommended)
{
    FrontendProviderVersionSnapshot result;
    result.provider = provider;
    result.installKind = installKind;
    result.id = id.toStdString();
    result.packIdentifier = packIdentifier.toStdString();
    result.name = name.toStdString();
    result.version = version.toStdString();
    result.releaseType = release;
    result.publishedUnixSeconds = published;
    result.recommended = recommended;
    for (const auto& item : gameVersions) {
        result.gameVersions.push_back(item.toStdString());
    }
    for (const auto& item : loaders) {
        result.loaders.push_back(item.toStdString());
    }
    return result;
}

FrontendTaskSnapshot progressSnapshot(
    const std::string& id,
    const std::string& title,
    FrontendTaskState state,
    FrontendTaskProgressKind progressKind,
    double fraction,
    bool cancellable,
    std::optional<FrontendTaskTerminalResult> terminal = std::nullopt)
{
    FrontendTaskSnapshot result;
    result.id = id;
    result.title = title;
    result.state = state;
    result.progressKind = progressKind;
    result.progressFraction = fraction;
    result.cancellationAllowed = cancellable;
    result.terminalResult = std::move(terminal);
    return result;
}

std::string safeName(QString value)
{
    const QString bad = QStringLiteral("<>:\"|?*!\r\n");
    for (qsizetype i = 0; i < value.size(); ++i) {
        const auto character = value.at(i);
        if (character.unicode() < 0x20 || !character.isPrint() || bad.contains(character)
            || character == QLatin1Char('/') || character == QLatin1Char('\\')) {
            value[i] = QLatin1Char('-');
        }
    }
    value = value.trimmed();
    if (value.isEmpty() || value == QStringLiteral(".") || value == QStringLiteral("..")) {
        value = QStringLiteral("Instance");
    }
    return value.toStdString();
}

struct Destination final {
    std::string identifier;
    std::filesystem::path path;
};

Destination destinationForName(const std::filesystem::path& instancesRoot, const std::string& name)
{
    const auto base = safeName(QString::fromStdString(name));
    for (int suffix = 0; suffix <= 9000; ++suffix) {
        const auto identifier = suffix == 0 ? base : base + "(" + std::to_string(suffix) + ")";
        const auto path = instancesRoot / identifier;
        std::error_code error;
        if (!std::filesystem::exists(path, error)) {
            if (error) {
                throw std::runtime_error("Could not inspect the provider instance destination");
            }
            return { identifier, path };
        }
    }
    throw std::runtime_error("No safe provider instance destination is available");
}

std::optional<FrontendInstanceSnapshot> readSnapshot(
    const std::filesystem::path& instancesRoot, const std::filesystem::path& instancePath)
{
    if (!isDirectory(instancePath) || instancePath.parent_path() != instancesRoot || !pathIsContained(instancesRoot, instancePath)) {
        return std::nullopt;
    }
    const auto configPath = instancePath / "instance.cfg";
    if (!isRegularFile(configPath)) {
        return std::nullopt;
    }
    INIFile settings;
    if (!settings.loadFile(QString::fromStdString(configPath.string()))) {
        return std::nullopt;
    }
    const auto name = settings.get("name", QStringLiteral("Unnamed Instance")).toString().trimmed().toStdString();
    const auto icon = settings.get("iconKey", QStringLiteral("default")).toString().trimmed().toStdString();
    const auto group = settings.get("InstanceGroupId", QString()).toString().trimmed().toStdString();
    if (!isSafeText(name, 512) || !isSafeText(icon, 256) || !isSafeText(group, 512, true)) {
        return std::nullopt;
    }
    return FrontendInstanceSnapshot{ instancePath.filename().string(), name, icon, group };
}

std::optional<Bytes> defaultDownload(
    const std::string& source,
    const ProductionProviderRuntime::DownloadProgressHandler& progress,
    const ProductionProviderRuntime::DownloadCancellationCheck& cancellation)
{
    static std::mutex networkMutex;
    std::lock_guard<std::mutex> networkLock(networkMutex);

    const QUrl url(QString::fromStdString(source));
    if (!url.isValid() || url.scheme() != QStringLiteral("https") || url.host().isEmpty()) {
        return std::nullopt;
    }

    if (!QCoreApplication::instance()) {
        return std::nullopt;
    }

    QNetworkAccessManager manager;
    QNetworkRequest request(url);
    const auto configuredUserAgent = BuildConfig.USER_AGENT.trimmed();
    request.setRawHeader(
        QByteArrayLiteral("User-Agent"),
        configuredUserAgent.isEmpty() ? QByteArrayLiteral("Prism/12.0 (com.lloydME.Prism)")
                                      : configuredUserAgent.toUtf8());
    if (url.host() == QUrl(BuildConfig.FLAME_BASE_URL).host() && !BuildConfig.FLAME_API_KEY.isEmpty()) {
        request.setRawHeader(QByteArrayLiteral("x-api-key"), BuildConfig.FLAME_API_KEY.toUtf8());
    }
    QNetworkReply* reply = manager.get(request);
    if (!reply) {
        return std::nullopt;
    }

    QEventLoop eventLoop;
    QTimer cancellationTimer;
    cancellationTimer.setInterval(50);
    QTimer timeoutTimer;
    timeoutTimer.setSingleShot(true);
    bool cancelled = false;
    bool timedOut = false;
    QByteArray bytes;

    QObject::connect(reply, &QNetworkReply::readyRead, [&] {
        if (isCancellationRequested(cancellation)) {
            cancelled = true;
            reply->abort();
            return;
        }
        bytes.append(reply->readAll());
        if (bytes.size() > static_cast<qsizetype>(kMaximumPayloadBytes)) {
            reply->abort();
        }
    });
    QObject::connect(reply, &QNetworkReply::downloadProgress, [&](qint64 received, qint64 total) {
        if (progress) {
            progress(received < 0 ? 0 : static_cast<std::uint64_t>(received),
                     total < 0 ? 0 : static_cast<std::uint64_t>(total));
        }
    });
    QObject::connect(&cancellationTimer, &QTimer::timeout, [&] {
        if (isCancellationRequested(cancellation)) {
            cancelled = true;
            reply->abort();
        }
    });
    QObject::connect(&timeoutTimer, &QTimer::timeout, [&] {
        timedOut = true;
        reply->abort();
    });
    QObject::connect(reply, &QNetworkReply::finished, &eventLoop, &QEventLoop::quit);

    cancellationTimer.start();
    timeoutTimer.start(60000);
    eventLoop.exec();
    cancellationTimer.stop();
    timeoutTimer.stop();

    if (cancelled || isCancellationRequested(cancellation) || timedOut || reply->error() != QNetworkReply::NoError) {
        reply->deleteLater();
        return std::nullopt;
    }
    bytes.append(reply->readAll());
    const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute);
    reply->deleteLater();
    if (status.isValid() && (status.toInt() < 200 || status.toInt() >= 300)) {
        return std::nullopt;
    }
    if (bytes.isEmpty() || bytes.size() > static_cast<qsizetype>(kMaximumPayloadBytes)) {
        return std::nullopt;
    }
    return vectorFromByteArray(bytes);
}

}  // namespace

ProductionProviderRuntime::ProductionProviderRuntime(std::filesystem::path dataRoot, DownloadHandler download)
    : m_dataRoot(normalizeRoot(std::move(dataRoot))),
      m_instancesRoot(m_dataRoot / "instances"),
      m_cacheRoot(m_dataRoot / "provider-cache"),
      m_stagingRoot(m_instancesRoot / ".prism-native-provider-staging"),
      m_download(download ? std::move(download) : DownloadHandler(defaultDownload))
{
    std::error_code error;
    if (std::filesystem::exists(m_dataRoot, error) && (error || isSymlink(m_dataRoot))) {
        throw std::invalid_argument("Provider runtime rejects a symlinked data root");
    }
    std::filesystem::create_directories(m_cacheRoot, error);
    std::filesystem::create_directories(m_stagingRoot, error);
    if (error || isSymlink(m_dataRoot) || isSymlink(m_instancesRoot) || isSymlink(m_cacheRoot)
        || isSymlink(m_stagingRoot) || !isDirectory(m_cacheRoot) || !isDirectory(m_stagingRoot)) {
        throw std::runtime_error("Provider runtime could not create its isolated roots");
    }
}

ProductionProviderRuntime::~ProductionProviderRuntime() noexcept
{
    shutdown();
}

void ProductionProviderRuntime::shutdown() noexcept
{
    std::lock_guard<std::mutex> lock(m_operationMutex);
    m_shutdown = true;
}

std::shared_ptr<ProductionProviderRuntime> makeProductionProviderRuntime(
    std::filesystem::path dataRoot, ProductionProviderRuntime::DownloadHandler download)
{
    return std::make_shared<ProductionProviderRuntime>(std::move(dataRoot), std::move(download));
}

namespace {

struct FetchContext final {
    std::filesystem::path cacheRoot;
    FrontendProviderKind provider = FrontendProviderKind::Modrinth;
    ProductionProviderRuntime::DownloadHandler download;
    std::function<bool()> cancellation;
    std::function<void(std::uint64_t, std::uint64_t)> progress;

    std::optional<Bytes> get(const QString& url, QString& diagnostic)
    {
        if (url.isEmpty() || isCancellationRequested(cancellation)) {
            return std::nullopt;
        }

        const auto providerRoot = cacheRoot / providerName(provider).toStdString();
        const auto key = QCryptographicHash::hash(url.toUtf8(), QCryptographicHash::Sha256).toHex().toStdString();
        const auto cachePath = providerRoot / (key + ".bin");
        if (!pathIsContained(cacheRoot, cachePath)) {
            diagnostic = QStringLiteral("Provider cache path was rejected.");
            return std::nullopt;
        }
        if (const auto cached = readBytes(cachePath)) {
            std::error_code touchError;
            std::filesystem::last_write_time(cachePath, std::filesystem::file_time_type::clock::now(), touchError);
            if (progress) {
                progress(static_cast<std::uint64_t>(cached->size()), static_cast<std::uint64_t>(cached->size()));
            }
            return vectorFromByteArray(*cached);
        }

        if (!download) {
            diagnostic = QStringLiteral("Provider downloads are unavailable.");
            return std::nullopt;
        }
        const auto downloaded = download(
            url.toStdString(),
            [&](std::uint64_t current, std::uint64_t total) {
                if (progress) {
                    progress(current, total);
                }
            },
            cancellation);
        if (!downloaded.has_value() || downloaded->empty()) {
            diagnostic = isCancellationRequested(cancellation) ? QStringLiteral("Provider download was cancelled.")
                                                                : QStringLiteral("Provider download failed.");
            return std::nullopt;
        }
        if (downloaded->size() > kMaximumPayloadBytes) {
            diagnostic = QStringLiteral("Provider response exceeded the size limit.");
            return std::nullopt;
        }
        const auto data = byteArrayFromVector(*downloaded);
        if (data.isEmpty()) {
            diagnostic = QStringLiteral("Provider response was empty.");
            return std::nullopt;
        }
        std::error_code error;
        std::filesystem::create_directories(providerRoot, error);
        if (error || isSymlink(providerRoot) || !writeBytes(cachePath, data)) {
            diagnostic = QStringLiteral("Provider cache could not be written.");
            return std::nullopt;
        }
        struct CacheEntry final {
            std::filesystem::path path;
            std::filesystem::file_time_type timestamp;
            std::uintmax_t size = 0;
        };
        std::vector<CacheEntry> entries;
        std::uintmax_t totalBytes = 0;
        std::filesystem::recursive_directory_iterator iterator(cacheRoot, error), end;
        for (; !error && iterator != end; iterator.increment(error)) {
            const auto path = iterator->path();
            if (!pathIsContained(cacheRoot, path) || isSymlink(path) || !iterator->is_regular_file(error)) {
                continue;
            }
            const auto size = iterator->file_size(error);
            const auto timestamp = iterator->last_write_time(error);
            if (error) {
                break;
            }
            entries.push_back({ path, timestamp, size });
            totalBytes += size;
        }
        if (!error && (entries.size() > kMaximumCacheEntries || totalBytes > kMaximumCacheBytes)) {
            std::sort(entries.begin(), entries.end(), [](const auto& left, const auto& right) {
                return left.timestamp < right.timestamp;
            });
            std::size_t remainingEntries = entries.size();
            for (const auto& entry : entries) {
                if (remainingEntries <= kMaximumCacheEntries && totalBytes <= kMaximumCacheBytes) {
                    break;
                }
                if (entry.path == cachePath) {
                    continue;
                }
                std::filesystem::remove(entry.path, error);
                if (error) {
                    break;
                }
                totalBytes -= entry.size;
                --remainingEntries;
            }
        }
        return *downloaded;
    }
};

QString modrinthSearchURL(const FrontendProviderBrowseRequest& request)
{
    QUrl url(BuildConfig.MODRINTH_PROD_URL + QStringLiteral("/search"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("query"), QString::fromStdString(request.query));
    query.addQueryItem(QStringLiteral("offset"), QString::number(request.offset));
    query.addQueryItem(QStringLiteral("limit"), QString::number(request.pageSize));
    switch (request.sort) {
        case FrontendProviderSort::Popularity:
        case FrontendProviderSort::Downloads:
            query.addQueryItem(QStringLiteral("index"), QStringLiteral("downloads"));
            break;
        case FrontendProviderSort::Newest:
            query.addQueryItem(QStringLiteral("index"), QStringLiteral("newest"));
            break;
        case FrontendProviderSort::Updated:
            query.addQueryItem(QStringLiteral("index"), QStringLiteral("updated"));
            break;
        case FrontendProviderSort::Follows:
            query.addQueryItem(QStringLiteral("index"), QStringLiteral("follows"));
            break;
        case FrontendProviderSort::Name:
            query.addQueryItem(QStringLiteral("index"), QStringLiteral("name"));
            break;
        default:
            query.addQueryItem(QStringLiteral("index"), QStringLiteral("relevance"));
            break;
    }
    QJsonArray facets;
    const auto appendFacet = [&](const std::vector<std::string>& values, const QString& prefix) {
        QJsonArray group;
        for (const auto& value : values) {
            group.append(prefix + QString::fromStdString(value));
        }
        if (!group.isEmpty()) {
            facets.append(group);
        }
    };
    appendFacet(request.gameVersions, QStringLiteral("versions:"));
    appendFacet(request.loaders, QStringLiteral("categories:"));
    appendFacet(request.categories, QStringLiteral("categories:"));
    switch (request.side) {
        case FrontendProviderSide::Client:
            facets.append(QJsonArray{ QStringLiteral("client_side:required"), QStringLiteral("client_side:optional") });
            facets.append(QJsonArray{ QStringLiteral("server_side:optional"), QStringLiteral("server_side:unsupported") });
            break;
        case FrontendProviderSide::Server:
            facets.append(QJsonArray{ QStringLiteral("server_side:required"), QStringLiteral("server_side:optional") });
            facets.append(QJsonArray{ QStringLiteral("client_side:optional"), QStringLiteral("client_side:unsupported") });
            break;
        case FrontendProviderSide::Universal:
            facets.append(QJsonArray{ QStringLiteral("client_side:required") });
            facets.append(QJsonArray{ QStringLiteral("server_side:required") });
            break;
        case FrontendProviderSide::Any:
            break;
    }
    if (request.openSource) {
        facets.append(QJsonArray{ QStringLiteral("open_source:true") });
    }
    facets.append(QJsonArray{ QStringLiteral("project_type:modpack") });
    query.addQueryItem(QStringLiteral("facets"), QString::fromUtf8(QJsonDocument(facets).toJson(QJsonDocument::Compact)));
    url.setQuery(query);
    return url.toString(QUrl::FullyEncoded);
}

QString modrinthVersionsURL(const FrontendProviderVersionRequest& request)
{
    QUrl url(BuildConfig.MODRINTH_PROD_URL + QStringLiteral("/project/")
             + encodePath(QString::fromStdString(request.packIdentifier)) + QStringLiteral("/version"));
    QUrlQuery query;
    if (!request.gameVersions.empty()) {
        QJsonArray values;
        for (const auto& version : request.gameVersions) {
            values.append(QString::fromStdString(version));
        }
        query.addQueryItem(QStringLiteral("game_versions"), QString::fromUtf8(QJsonDocument(values).toJson(QJsonDocument::Compact)));
    }
    if (!request.loaders.empty()) {
        QJsonArray values;
        for (const auto& loader : request.loaders) {
            values.append(QString::fromStdString(loader));
        }
        query.addQueryItem(QStringLiteral("loaders"), QString::fromUtf8(QJsonDocument(values).toJson(QJsonDocument::Compact)));
    }
    url.setQuery(query);
    return url.toString(QUrl::FullyEncoded);
}

QString curseForgeSearchURL(const FrontendProviderBrowseRequest& request)
{
    QUrl url(BuildConfig.FLAME_BASE_URL + QStringLiteral("/mods/search"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("gameId"), QStringLiteral("432"));
    query.addQueryItem(QStringLiteral("pageSize"), QString::number(request.pageSize));
    query.addQueryItem(QStringLiteral("index"), QString::number(request.offset));
    const auto search = QString::fromStdString(request.query);
    if (!search.isEmpty()) {
        query.addQueryItem(QStringLiteral("searchFilter"), search);
    }
    int sortField = 2;
    switch (request.sort) {
        case FrontendProviderSort::Updated:
        case FrontendProviderSort::Newest:
            sortField = 3;
            break;
        case FrontendProviderSort::Name:
            sortField = 4;
            break;
        case FrontendProviderSort::Downloads:
            sortField = 6;
            break;
        case FrontendProviderSort::GameVersion:
            sortField = 8;
            break;
        default:
            break;
    }
    query.addQueryItem(QStringLiteral("sortField"), QString::number(sortField));
    query.addQueryItem(QStringLiteral("sortOrder"), QStringLiteral("desc"));
    if (!request.gameVersions.empty()) {
        query.addQueryItem(QStringLiteral("gameVersion"), QString::fromStdString(request.gameVersions.front()));
    }
    QJsonArray loaderTypes;
    const std::map<QString, int> loaderMappings{
        { QStringLiteral("forge"), 1 },
        { QStringLiteral("liteloader"), 3 },
        { QStringLiteral("fabric"), 4 },
        { QStringLiteral("quilt"), 5 },
        { QStringLiteral("neoforge"), 6 },
    };
    for (const auto& loader : request.loaders) {
        const auto iterator = loaderMappings.find(QString::fromStdString(loader).toLower());
        if (iterator != loaderMappings.end()) {
            loaderTypes.append(iterator->second);
        }
    }
    if (!loaderTypes.isEmpty()) {
        query.addQueryItem(
            QStringLiteral("modLoaderTypes"), QString::fromUtf8(QJsonDocument(loaderTypes).toJson(QJsonDocument::Compact)));
    }
    QJsonArray categoryIDs;
    for (const auto& category : request.categories) {
        bool valid = false;
        const auto identifier = QString::fromStdString(category).toInt(&valid);
        if (valid && identifier > 0) {
            categoryIDs.append(identifier);
        }
    }
    if (!categoryIDs.isEmpty()) {
        query.addQueryItem(
            QStringLiteral("categoryIds"), QString::fromUtf8(QJsonDocument(categoryIDs).toJson(QJsonDocument::Compact)));
    }
    url.setQuery(query);
    return url.toString(QUrl::FullyEncoded);
}

QString curseForgeVersionsURL(const FrontendProviderVersionRequest& request)
{
    QUrl url(QString(BuildConfig.FLAME_BASE_URL + QStringLiteral("/mods/%1/files"))
                 .arg(encodePath(QString::fromStdString(request.packIdentifier))));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("pageSize"), QStringLiteral("100"));
    query.addQueryItem(QStringLiteral("index"), QStringLiteral("0"));
    if (!request.gameVersions.empty()) {
        query.addQueryItem(QStringLiteral("gameVersion"), QString::fromStdString(request.gameVersions.front()));
    }
    if (request.loaders.size() == 1) {
        const std::map<QString, int> loaderMappings{
            { QStringLiteral("forge"), 1 },
            { QStringLiteral("liteloader"), 3 },
            { QStringLiteral("fabric"), 4 },
            { QStringLiteral("quilt"), 5 },
            { QStringLiteral("neoforge"), 6 },
        };
        const auto iterator = loaderMappings.find(QString::fromStdString(request.loaders.front()).toLower());
        if (iterator != loaderMappings.end()) {
            query.addQueryItem(QStringLiteral("modLoaderType"), QString::number(iterator->second));
        }
    }
    url.setQuery(query);
    return url.toString(QUrl::FullyEncoded);
}

QString ftbBaseURL()
{
    return BuildConfig.FTB_API_BASE_URL;
}

QString atlauncherIndexURL()
{
    return BuildConfig.ATL_DOWNLOAD_SERVER_URL + QStringLiteral("launcher/json/packsnew.json");
}

QString safeATLauncherPackName(QString value);

QString technicSearchURL(const FrontendProviderBrowseRequest& request)
{
    const auto term = QString::fromStdString(request.query).trimmed();
    if (term.startsWith(QLatin1Char('#'))) {
        return QString(BuildConfig.TECHNIC_API_BASE_URL + QStringLiteral("modpack/%1?build=%2"))
            .arg(encodePath(term.mid(1)), BuildConfig.TECHNIC_API_BUILD);
    }
    QUrl url(BuildConfig.TECHNIC_API_BASE_URL + (term.isEmpty() ? QStringLiteral("trending") : QStringLiteral("search")));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("build"), BuildConfig.TECHNIC_API_BUILD);
    if (!term.isEmpty()) {
        query.addQueryItem(QStringLiteral("q"), term);
    }
    url.setQuery(query);
    return url.toString(QUrl::FullyEncoded);
}

QString technicDetailURL(const QString& slug)
{
    QUrl url(BuildConfig.TECHNIC_API_BASE_URL + QStringLiteral("modpack/") + encodePath(slug));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("build"), BuildConfig.TECHNIC_API_BUILD);
    url.setQuery(query);
    return url.toString(QUrl::FullyEncoded);
}

struct LegacyPack final {
    QString name;
    QString currentVersion;
    QStringList oldVersions;
    QString mcVersion;
    QString description;
    QString author;
    QString dir;
    QString file;
};

QList<LegacyPack> parseLegacyPacks(const QByteArray& bytes, QString& diagnostic)
{
    QList<LegacyPack> packs;
    QXmlStreamReader xml(bytes);
    while (!xml.atEnd()) {
        xml.readNext();
        if (!xml.isStartElement() || xml.name() != QStringLiteral("modpack")) {
            continue;
        }
        const auto attributes = xml.attributes();
        LegacyPack pack;
        pack.name = attributes.value(QStringLiteral("name")).toString();
        pack.currentVersion = attributes.value(QStringLiteral("version")).toString();
        pack.mcVersion = attributes.value(QStringLiteral("mcVersion")).toString();
        pack.description = attributes.value(QStringLiteral("description")).toString();
        pack.author = attributes.value(QStringLiteral("author")).toString();
        pack.dir = attributes.value(QStringLiteral("dir")).toString();
        pack.file = attributes.value(QStringLiteral("url")).toString();
        for (const auto& version : attributes.value(QStringLiteral("oldVersions")).toString().split(';', Qt::SkipEmptyParts)) {
            if (!pack.oldVersions.contains(version)) {
                pack.oldVersions.append(version);
            }
        }
        if (pack.oldVersions.isEmpty() && !pack.currentVersion.isEmpty()) {
            pack.oldVersions.append(pack.currentVersion);
        }
        if (!pack.name.isEmpty() && !pack.dir.isEmpty() && !pack.file.isEmpty()) {
            packs.append(std::move(pack));
        }
    }
    if (xml.hasError()) {
        diagnostic = QStringLiteral("Legacy FTB XML is invalid: %1").arg(xml.errorString());
        packs.clear();
    }
    return packs;
}

QList<FrontendProviderPackSnapshot> parseBrowseRows(
    FrontendProviderKind provider,
    const QJsonDocument& document,
    QString& diagnostic)
{
    QList<FrontendProviderPackSnapshot> rows;
    if (provider == FrontendProviderKind::Modrinth) {
        for (const auto& raw : document.object().value(QStringLiteral("hits")).toArray()) {
            const auto object = raw.toObject();
            const auto id = object.value(QStringLiteral("project_id")).toString(object.value(QStringLiteral("id")).toString());
            const auto name = object.value(QStringLiteral("title")).toString(object.value(QStringLiteral("name")).toString());
            if (!id.isEmpty() && !name.isEmpty()) {
                rows.append(packSnapshot(provider,
                                         id,
                                         name,
                                         object.value(QStringLiteral("slug")).toString(),
                                         object.value(QStringLiteral("description")).toString(),
                                         object.value(QStringLiteral("author")).toString(),
                                         stringArray(object.value(QStringLiteral("categories")))));
            }
        }
        return rows;
    }

    if (provider == FrontendProviderKind::CurseForge) {
        for (const auto& raw : document.object().value(QStringLiteral("data")).toArray()) {
            const auto object = raw.toObject();
            const auto id = QString::number(object.value(QStringLiteral("id")).toInteger());
            const auto name = object.value(QStringLiteral("name")).toString();
            if (id != QStringLiteral("0") && !name.isEmpty()) {
                QStringList categories;
                for (const auto& category : object.value(QStringLiteral("categories")).toArray()) {
                    const auto categoryName = category.toObject().value(QStringLiteral("name")).toString();
                    if (!categoryName.isEmpty() && !categories.contains(categoryName)) {
                        categories.append(categoryName);
                    }
                }
                QString author;
                const auto authors = object.value(QStringLiteral("authors")).toArray();
                if (!authors.isEmpty()) {
                    author = authors.first().toObject().value(QStringLiteral("name")).toString();
                }
                rows.append(packSnapshot(provider,
                                         id,
                                         name,
                                         object.value(QStringLiteral("slug")).toString(),
                                         object.value(QStringLiteral("summary")).toString(),
                                         author,
                                         categories));
            }
        }
        return rows;
    }

    if (provider == FrontendProviderKind::Technic) {
        const auto root = document.object();
        const auto source = root.contains(QStringLiteral("modpacks")) ? root.value(QStringLiteral("modpacks")).toArray()
                                                                       : QJsonArray{ root };
        for (const auto& raw : source) {
            const auto object = raw.toObject();
            const auto id = object.value(QStringLiteral("slug")).toString(object.value(QStringLiteral("name")).toString());
            const auto name = object.value(QStringLiteral("name")).toString(object.value(QStringLiteral("displayName")).toString());
            if (!id.isEmpty() && !name.isEmpty() && id != QStringLiteral("vanilla")) {
                rows.append(packSnapshot(provider,
                                         id,
                                         name,
                                         id,
                                         object.value(QStringLiteral("description")).toString(),
                                         object.value(QStringLiteral("user")).toString(),
                                         {}));
            }
        }
        return rows;
    }

    diagnostic = QStringLiteral("Provider browse response shape was not recognized.");
    return rows;
}

std::set<std::string> installedProviderPacks(
    const std::filesystem::path& instancesRoot, FrontendProviderKind provider)
{
    std::set<std::string> identifiers;
    std::error_code error;
    if (!isDirectory(instancesRoot)) {
        return identifiers;
    }
    for (std::filesystem::directory_iterator iterator(instancesRoot, error), end; iterator != end; iterator.increment(error)) {
        if (error) {
            break;
        }
        const auto instance = iterator->path();
        if (!isDirectory(instance) || !pathIsContained(instancesRoot, instance)) {
            continue;
        }
        const auto metadata = readBytes(instance / ".prism-native-provider.json");
        if (!metadata) {
            continue;
        }
        const auto document = QJsonDocument::fromJson(*metadata);
        if (!document.isObject()) {
            continue;
        }
        const auto object = document.object();
        const auto identifier = object.value(QStringLiteral("packIdentifier")).toString().trimmed();
        if (object.value(QStringLiteral("provider")).toString() == providerName(provider) && !identifier.isEmpty()) {
            identifiers.insert(identifier.toStdString());
        }
    }
    return identifiers;
}

bool matchesFilters(
    const FrontendProviderPackSnapshot& row,
    const FrontendProviderBrowseRequest& request,
    const std::set<std::string>& installed)
{
    auto query = QString::fromStdString(request.query).trimmed();
    if (request.provider == FrontendProviderKind::LegacyFTB && query.startsWith(QStringLiteral("thirdparty:"))) {
        query = query.mid(QStringLiteral("thirdparty:").size()).trimmed();
    }
    if (request.provider == FrontendProviderKind::Technic && query.startsWith(QLatin1Char('#'))) {
        query.remove(0, 1);
    }
    if (!query.isEmpty()) {
        const auto name = QString::fromStdString(row.name);
        const auto summary = QString::fromStdString(row.summary);
        const auto identifier = QString::fromStdString(row.id);
        const auto slug = QString::fromStdString(row.slug);
        if (!name.contains(query, Qt::CaseInsensitive) && !summary.contains(query, Qt::CaseInsensitive)
            && !identifier.contains(query, Qt::CaseInsensitive) && !slug.contains(query, Qt::CaseInsensitive)) {
            return false;
        }
    }
    if (!request.categories.empty() && request.provider != FrontendProviderKind::Modrinth
        && request.provider != FrontendProviderKind::CurseForge) {
        const bool matched = std::any_of(request.categories.begin(), request.categories.end(), [&](const auto& wanted) {
            return std::any_of(row.categories.begin(), row.categories.end(), [&](const auto& category) {
                return QString::fromStdString(category).compare(QString::fromStdString(wanted), Qt::CaseInsensitive) == 0;
            });
        });
        if (!matched) {
            return false;
        }
    }
    if (request.hideInstalled && installed.contains(row.id)) {
        return false;
    }
    return true;
}

bool matchesVersionFilters(
    const FrontendProviderVersionSnapshot& row,
    const std::vector<std::string>& gameVersions,
    const std::vector<std::string>& loaders,
    const std::vector<FrontendProviderReleaseType>& releaseTypes)
{
    for (const auto& wanted : gameVersions) {
        if (std::find(row.gameVersions.begin(), row.gameVersions.end(), wanted) == row.gameVersions.end()) {
            return false;
        }
    }
    for (const auto& wanted : loaders) {
        if (std::find(row.loaders.begin(), row.loaders.end(), wanted) == row.loaders.end()) {
            return false;
        }
    }
    if (!releaseTypes.empty()
        && std::find(releaseTypes.begin(), releaseTypes.end(), row.releaseType) == releaseTypes.end()) {
        return false;
    }
    return true;
}

}  // namespace

FrontendProviderBrowseResult ProductionProviderRuntime::browse(
    const FrontendProviderBrowseRequest& request,
    const FrontendRuntimeDependencies::ProviderBrowseProgressHandler& progress,
    const FrontendRuntimeDependencies::ProviderBrowseCancellationCheck& cancellation)
{
    std::lock_guard<std::mutex> operationLock(m_operationMutex);
    const std::string taskId = "provider-browse." + providerName(request.provider).toStdString();
    const std::string title = "Browse Provider Packs";
    const auto report = [&](const FrontendTaskSnapshot& snapshot) {
        if (progress) {
            progress(snapshot);
        }
    };
    const auto terminal = [&](FrontendProviderBrowseOutcome outcome,
                              std::optional<FrontendProviderBrowsePage> page,
                              std::string localizationKey,
                              std::string diagnosticText,
                              bool retryable) {
        const auto state = outcome == FrontendProviderBrowseOutcome::Succeeded
            ? FrontendTaskState::Succeeded
            : (outcome == FrontendProviderBrowseOutcome::Cancelled ? FrontendTaskState::Cancelled : FrontendTaskState::Failed);
        const auto terminalOutcome = outcome == FrontendProviderBrowseOutcome::Succeeded
            ? FrontendTaskTerminalOutcome::Succeeded
            : (outcome == FrontendProviderBrowseOutcome::Cancelled ? FrontendTaskTerminalOutcome::Cancelled
                                                                     : FrontendTaskTerminalOutcome::Failed);
        report(progressSnapshot(taskId,
                                title,
                                state,
                                outcome == FrontendProviderBrowseOutcome::Succeeded ? FrontendTaskProgressKind::Determinate
                                                                                     : FrontendTaskProgressKind::None,
                                outcome == FrontendProviderBrowseOutcome::Succeeded ? 1.0 : 0.0,
                                false,
                                FrontendTaskTerminalResult{ terminalOutcome,
                                                            localizationKey,
                                                            {},
                                                            diagnosticText,
                                                            false }));
        return FrontendProviderBrowseResult{ outcome,
                                            std::move(page),
                                            std::move(localizationKey),
                                            std::move(diagnosticText),
                                            retryable };
    };

    if (m_shutdown) {
        return terminal(FrontendProviderBrowseOutcome::Failed,
                        std::nullopt,
                        "providers.browse.shutdown",
                        "Provider browsing is shut down.",
                        false);
    }
    report(progressSnapshot(taskId, title, FrontendTaskState::Queued, FrontendTaskProgressKind::None, 0.0, true));
    if (isCancellationRequested(cancellation)) {
        return terminal(FrontendProviderBrowseOutcome::Cancelled,
                        std::nullopt,
                        "providers.browse.cancelled",
                        "Provider browsing was cancelled.",
                        false);
    }
    report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Indeterminate, 0.0, true));

    FetchContext fetch{ m_cacheRoot, request.provider, m_download, cancellation, {} };
    QString diagnostic;
    QList<FrontendProviderPackSnapshot> allRows;
    bool serverPaged = false;
    std::optional<std::size_t> serverTotal;
    try {
        if (request.provider == FrontendProviderKind::Modrinth || request.provider == FrontendProviderKind::CurseForge) {
            serverPaged = true;
            const auto url = request.provider == FrontendProviderKind::Modrinth ? modrinthSearchURL(request)
                                                                                 : curseForgeSearchURL(request);
            const auto response = fetch.get(url, diagnostic);
            if (!response) {
                if (isCancellationRequested(cancellation)) {
                    return terminal(FrontendProviderBrowseOutcome::Cancelled,
                                    std::nullopt,
                                    "providers.browse.cancelled",
                                    "Provider browsing was cancelled.",
                                    false);
                }
                return terminal(FrontendProviderBrowseOutcome::Failed,
                                std::nullopt,
                                "providers.browse.networkError",
                                diagnostic.toStdString(),
                                true);
            }
            const auto document = parseJson(*response, diagnostic);
            if (!document) {
                return terminal(FrontendProviderBrowseOutcome::Failed,
                                std::nullopt,
                                "providers.browse.providerError",
                                diagnostic.toStdString(),
                                true);
            }
            allRows = parseBrowseRows(request.provider, *document, diagnostic);
            if (!diagnostic.isEmpty()) {
                return terminal(FrontendProviderBrowseOutcome::Failed,
                                std::nullopt,
                                "providers.browse.providerError",
                                diagnostic.toStdString(),
                                true);
            }
            if (request.provider == FrontendProviderKind::Modrinth) {
                const auto total = document->object().value(QStringLiteral("total_hits")).toInteger(-1);
                if (total >= 0) {
                    serverTotal = static_cast<std::size_t>(total);
                }
            } else {
                const auto total = document->object().value(QStringLiteral("pagination"))
                                       .toObject()
                                       .value(QStringLiteral("totalCount"))
                                       .toInteger(-1);
                if (total >= 0) {
                    serverTotal = static_cast<std::size_t>(total);
                }
            }
        } else if (request.provider == FrontendProviderKind::FTB) {
            const auto response = fetch.get(ftbBaseURL() + QStringLiteral("/modpack/all"), diagnostic);
            if (!response) {
                return terminal(isCancellationRequested(cancellation) ? FrontendProviderBrowseOutcome::Cancelled
                                                                       : FrontendProviderBrowseOutcome::Failed,
                                std::nullopt,
                                isCancellationRequested(cancellation) ? "providers.browse.cancelled"
                                                                      : "providers.browse.networkError",
                                diagnostic.toStdString(),
                                !isCancellationRequested(cancellation));
            }
            const auto document = parseJson(*response, diagnostic);
            if (!document || !document->isObject()) {
                return terminal(FrontendProviderBrowseOutcome::Failed,
                                std::nullopt,
                                "providers.browse.providerError",
                                diagnostic.isEmpty() ? "FTB pack index is invalid." : diagnostic.toStdString(),
                                true);
            }
            const auto packs = document->object().value(QStringLiteral("packs")).toArray();
            for (const auto& raw : packs) {
                if (isCancellationRequested(cancellation)) {
                    return terminal(FrontendProviderBrowseOutcome::Cancelled,
                                    std::nullopt,
                                    "providers.browse.cancelled",
                                    "Provider browsing was cancelled.",
                                    false);
                }
                QJsonObject packObject;
                int packId = 0;
                if (raw.isObject()) {
                    packObject = raw.toObject();
                    packId = packObject.value(QStringLiteral("id")).toInt();
                } else {
                    packId = raw.toInt();
                }
                if (packId <= 0) {
                    continue;
                }
                if (packObject.isEmpty()) {
                    const auto packResponse = fetch.get(ftbBaseURL() + QStringLiteral("/modpack/%1").arg(packId), diagnostic);
                    if (!packResponse) {
                        continue;
                    }
                    const auto packDocument = parseJson(*packResponse, diagnostic);
                    if (!packDocument || !packDocument->isObject()) {
                        continue;
                    }
                    packObject = packDocument->object();
                }
                FTB::Modpack pack;
                FTB::loadModpack(pack, packObject);
                QStringList categories;
                for (const auto& tag : pack.tags) {
                    categories.append(tag.name);
                }
                const auto author = pack.authors.isEmpty() ? QString() : pack.authors.first().name;
                allRows.append(packSnapshot(request.provider,
                                             QString::number(pack.id),
                                             pack.name,
                                             pack.safeName,
                                             pack.synopsis,
                                             author,
                                             categories));
            }
        } else if (request.provider == FrontendProviderKind::ATLauncher) {
            const auto response = fetch.get(atlauncherIndexURL(), diagnostic);
            if (!response) {
                return terminal(isCancellationRequested(cancellation) ? FrontendProviderBrowseOutcome::Cancelled
                                                                       : FrontendProviderBrowseOutcome::Failed,
                                std::nullopt,
                                isCancellationRequested(cancellation) ? "providers.browse.cancelled"
                                                                      : "providers.browse.networkError",
                                diagnostic.toStdString(),
                                !isCancellationRequested(cancellation));
            }
            const auto document = parseJson(*response, diagnostic);
            if (!document || !document->isArray()) {
                return terminal(FrontendProviderBrowseOutcome::Failed,
                                std::nullopt,
                                "providers.browse.providerError",
                                diagnostic.isEmpty() ? "ATLauncher pack index is invalid." : diagnostic.toStdString(),
                                true);
            }
            for (const auto& raw : document->array()) {
                auto object = raw.toObject();
                ATLauncher::IndexedPack pack;
                ATLauncher::loadIndexedPack(pack, object);
                if (pack.type != ATLauncher::PackType::Public || pack.system || pack.versions.isEmpty()) {
                    continue;
                }
                allRows.append(packSnapshot(request.provider, pack.name, pack.name, pack.safeName, pack.description, {}, {}));
            }
        } else if (request.provider == FrontendProviderKind::Technic) {
            const auto response = fetch.get(technicSearchURL(request), diagnostic);
            if (!response) {
                return terminal(isCancellationRequested(cancellation) ? FrontendProviderBrowseOutcome::Cancelled
                                                                       : FrontendProviderBrowseOutcome::Failed,
                                std::nullopt,
                                isCancellationRequested(cancellation) ? "providers.browse.cancelled"
                                                                      : "providers.browse.networkError",
                                diagnostic.toStdString(),
                                !isCancellationRequested(cancellation));
            }
            const auto document = parseJson(*response, diagnostic);
            if (!document || !document->isObject()) {
                return terminal(FrontendProviderBrowseOutcome::Failed,
                                std::nullopt,
                                "providers.browse.providerError",
                                diagnostic.isEmpty() ? "Technic pack index is invalid." : diagnostic.toStdString(),
                                true);
            }
            allRows = parseBrowseRows(request.provider, *document, diagnostic);
        } else if (request.provider == FrontendProviderKind::LegacyFTB) {
            const auto term = QString::fromStdString(request.query).trimmed();
            const auto listName = term.startsWith(QStringLiteral("thirdparty:")) ? QStringLiteral("thirdparty.xml")
                                                                                   : QStringLiteral("modpacks.xml");
            const auto response = fetch.get(BuildConfig.LEGACY_FTB_CDN_BASE_URL + QStringLiteral("static/") + listName, diagnostic);
            if (!response) {
                return terminal(isCancellationRequested(cancellation) ? FrontendProviderBrowseOutcome::Cancelled
                                                                       : FrontendProviderBrowseOutcome::Failed,
                                std::nullopt,
                                isCancellationRequested(cancellation) ? "providers.browse.cancelled"
                                                                      : "providers.browse.networkError",
                                diagnostic.toStdString(),
                                !isCancellationRequested(cancellation));
            }
            const auto packs = parseLegacyPacks(byteArrayFromVector(*response), diagnostic);
            if (!diagnostic.isEmpty()) {
                return terminal(FrontendProviderBrowseOutcome::Failed,
                                std::nullopt,
                                "providers.browse.providerError",
                                diagnostic.toStdString(),
                                true);
            }
            for (const auto& pack : packs) {
                allRows.append(packSnapshot(request.provider,
                                             pack.dir + QStringLiteral("|") + pack.file,
                                             pack.name,
                                             pack.dir,
                                             pack.description,
                                             pack.author,
                                             {}));
            }
        }
    } catch (const std::exception& exception) {
        return terminal(FrontendProviderBrowseOutcome::Failed,
                        std::nullopt,
                        "providers.browse.providerError",
                        exception.what(),
                        true);
    }

    if (isCancellationRequested(cancellation)) {
        return terminal(FrontendProviderBrowseOutcome::Cancelled,
                        std::nullopt,
                        "providers.browse.cancelled",
                        "Provider browsing was cancelled.",
                        false);
    }

    const std::size_t serverResultCount = static_cast<std::size_t>(allRows.size());
    const auto installed = request.hideInstalled ? installedProviderPacks(m_instancesRoot, request.provider)
                                                  : std::set<std::string>{};
    QList<FrontendProviderPackSnapshot> filtered;
    for (const auto& row : allRows) {
        if (matchesFilters(row, request, installed)) {
            filtered.append(row);
        }
    }
    if (request.sort == FrontendProviderSort::Name) {
        std::sort(filtered.begin(), filtered.end(), [](const auto& left, const auto& right) {
            const auto order = QString::fromStdString(left.name).localeAwareCompare(QString::fromStdString(right.name));
            return order == 0 ? left.id < right.id : order < 0;
        });
    }
    const std::size_t total = static_cast<std::size_t>(filtered.size());
    const std::size_t start = serverPaged ? 0 : std::min(request.offset, total);
    const std::size_t count = serverPaged ? total : std::min(request.pageSize, total - start);
    FrontendProviderBrowsePage page;
    page.provider = request.provider;
    page.offset = request.offset;
    page.pageSize = request.pageSize;
    for (std::size_t index = 0; index < count; ++index) {
        page.packs.push_back(filtered.at(static_cast<qsizetype>(start + index)));
    }
    if (serverTotal.has_value()) {
        if (request.offset + serverResultCount < *serverTotal) {
            page.nextOffset = request.offset + serverResultCount;
        }
    } else if (serverPaged && serverResultCount == request.pageSize) {
        page.nextOffset = request.offset + serverResultCount;
    } else if (!serverPaged && start + page.packs.size() < total) {
        page.nextOffset = start + page.packs.size();
    }
    return terminal(FrontendProviderBrowseOutcome::Succeeded,
                    std::move(page),
                    "providers.browse.completed",
                    {},
                    false);
}

FrontendProviderVersionResult ProductionProviderRuntime::versions(
    const FrontendProviderVersionRequest& request,
    const FrontendRuntimeDependencies::ProviderVersionProgressHandler& progress,
    const FrontendRuntimeDependencies::ProviderVersionCancellationCheck& cancellation)
{
    std::lock_guard<std::mutex> operationLock(m_operationMutex);
    const std::string taskId = "provider-versions." + providerName(request.provider).toStdString();
    const std::string title = "Load Provider Versions";
    const auto report = [&](const FrontendTaskSnapshot& snapshot) {
        if (progress) {
            progress(snapshot);
        }
    };
    const auto terminal = [&](FrontendProviderVersionOutcome outcome,
                              std::vector<FrontendProviderVersionSnapshot> values,
                              std::string localizationKey,
                              std::string diagnosticText,
                              bool retryable) {
        const auto state = outcome == FrontendProviderVersionOutcome::Succeeded
            ? FrontendTaskState::Succeeded
            : (outcome == FrontendProviderVersionOutcome::Cancelled ? FrontendTaskState::Cancelled : FrontendTaskState::Failed);
        const auto terminalOutcome = outcome == FrontendProviderVersionOutcome::Succeeded
            ? FrontendTaskTerminalOutcome::Succeeded
            : (outcome == FrontendProviderVersionOutcome::Cancelled ? FrontendTaskTerminalOutcome::Cancelled
                                                                     : FrontendTaskTerminalOutcome::Failed);
        report(progressSnapshot(taskId,
                                title,
                                state,
                                outcome == FrontendProviderVersionOutcome::Succeeded ? FrontendTaskProgressKind::Determinate
                                                                                      : FrontendTaskProgressKind::None,
                                outcome == FrontendProviderVersionOutcome::Succeeded ? 1.0 : 0.0,
                                false,
                                FrontendTaskTerminalResult{ terminalOutcome,
                                                            localizationKey,
                                                            {},
                                                            diagnosticText,
                                                            false }));
        return FrontendProviderVersionResult{ outcome,
                                              request.provider,
                                              request.packIdentifier,
                                              std::move(values),
                                              std::move(localizationKey),
                                              std::move(diagnosticText),
                                              retryable };
    };

    if (m_shutdown) {
        return terminal(FrontendProviderVersionOutcome::Failed,
                        {},
                        "providers.versions.shutdown",
                        "Provider version loading is shut down.",
                        false);
    }
    report(progressSnapshot(taskId, title, FrontendTaskState::Queued, FrontendTaskProgressKind::None, 0.0, true));
    if (isCancellationRequested(cancellation)) {
        return terminal(FrontendProviderVersionOutcome::Cancelled,
                        {},
                        "providers.versions.cancelled",
                        "Provider version loading was cancelled.",
                        false);
    }
    report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Indeterminate, 0.0, true));

    FetchContext fetch{ m_cacheRoot, request.provider, m_download, cancellation, {} };
    QString diagnostic;
    std::vector<FrontendProviderVersionSnapshot> values;
    try {
        if (request.provider == FrontendProviderKind::Modrinth || request.provider == FrontendProviderKind::CurseForge) {
            const auto url = request.provider == FrontendProviderKind::Modrinth ? modrinthVersionsURL(request)
                                                                                 : curseForgeVersionsURL(request);
            const auto response = fetch.get(url, diagnostic);
            if (!response) {
                return terminal(isCancellationRequested(cancellation) ? FrontendProviderVersionOutcome::Cancelled
                                                                       : FrontendProviderVersionOutcome::Failed,
                                {},
                                isCancellationRequested(cancellation) ? "providers.versions.cancelled"
                                                                      : "providers.versions.networkError",
                                diagnostic.toStdString(),
                                !isCancellationRequested(cancellation));
            }
            const auto document = parseJson(*response, diagnostic);
            if (!document) {
                return terminal(FrontendProviderVersionOutcome::Failed,
                                {},
                                "providers.versions.providerError",
                                diagnostic.toStdString(),
                                true);
            }
            const auto array = request.provider == FrontendProviderKind::Modrinth ? document->array()
                                                                                    : document->object().value(QStringLiteral("data")).toArray();
            for (const auto& raw : array) {
                const auto object = raw.toObject();
                const auto id = request.provider == FrontendProviderKind::Modrinth
                    ? object.value(QStringLiteral("id")).toString()
                    : QString::number(object.value(QStringLiteral("id")).toInteger());
                const auto name = request.provider == FrontendProviderKind::Modrinth
                    ? object.value(QStringLiteral("name")).toString(object.value(QStringLiteral("version_number")).toString())
                    : object.value(QStringLiteral("displayName")).toString(object.value(QStringLiteral("fileName")).toString());
                const auto version = request.provider == FrontendProviderKind::Modrinth
                    ? object.value(QStringLiteral("version_number")).toString(name)
                    : object.value(QStringLiteral("fileName")).toString(name);
                if (id.isEmpty() || name.isEmpty() || version.isEmpty()) {
                    continue;
                }
                auto gameVersions = stringArray(object.value(QStringLiteral("game_versions")));
                auto loaders = stringArray(object.value(QStringLiteral("loaders")));
                if (request.provider == FrontendProviderKind::CurseForge) {
                    loaders.clear();
                    const auto loaderType = object.value(QStringLiteral("modLoaderType")).toInt();
                    const std::map<int, QString> loaderNames{
                        { 1, QStringLiteral("forge") },
                        { 3, QStringLiteral("liteloader") },
                        { 4, QStringLiteral("fabric") },
                        { 5, QStringLiteral("quilt") },
                        { 6, QStringLiteral("neoforge") },
                    };
                    if (const auto iterator = loaderNames.find(loaderType); iterator != loaderNames.end()) {
                        loaders.append(iterator->second);
                    }
                    gameVersions = stringArray(object.value(QStringLiteral("gameVersions")));
                }
                const auto row = versionSnapshot(request.provider,
                                                 request.provider == FrontendProviderKind::Modrinth
                                                     ? FrontendProviderInstallKind::Modrinth
                                                     : FrontendProviderInstallKind::CurseForgeFlame,
                                                 id,
                                                 QString::fromStdString(request.packIdentifier),
                                                 name,
                                                 version,
                                                 gameVersions,
                                                 loaders,
                                                 releaseType(object.value(request.provider == FrontendProviderKind::Modrinth
                                                                             ? QStringLiteral("version_type")
                                                                             : QStringLiteral("releaseType"))),
                                                 unixSeconds(object.value(request.provider == FrontendProviderKind::Modrinth
                                                                              ? QStringLiteral("date_published")
                                                                              : QStringLiteral("fileDate"))),
                                                 object.value(QStringLiteral("featured")).toBool());
                if (matchesVersionFilters(row, request.gameVersions, request.loaders, request.releaseTypes)) {
                    values.push_back(row);
                }
            }
        } else if (request.provider == FrontendProviderKind::FTB) {
            const auto response = fetch.get(ftbBaseURL() + QStringLiteral("/modpack/")
                                                 + encodePath(QString::fromStdString(request.packIdentifier)),
                                             diagnostic);
            if (!response) {
                return terminal(isCancellationRequested(cancellation) ? FrontendProviderVersionOutcome::Cancelled
                                                                       : FrontendProviderVersionOutcome::Failed,
                                {},
                                isCancellationRequested(cancellation) ? "providers.versions.cancelled"
                                                                      : "providers.versions.networkError",
                                diagnostic.toStdString(),
                                !isCancellationRequested(cancellation));
            }
            const auto document = parseJson(*response, diagnostic);
            if (!document || !document->isObject()) {
                return terminal(FrontendProviderVersionOutcome::Failed,
                                {},
                                "providers.versions.providerError",
                                diagnostic.isEmpty() ? "FTB pack metadata is invalid." : diagnostic.toStdString(),
                                true);
            }
            FTB::Modpack pack;
            auto object = document->object();
            FTB::loadModpack(pack, object);
            for (qsizetype index = pack.versions.size() - 1; index >= 0; --index) {
                const auto& version = pack.versions.at(index);
                QStringList gameVersions;
                QStringList loaders;
                if (!request.gameVersions.empty() || !request.loaders.empty()) {
                    const auto versionResponse = fetch.get(
                        ftbBaseURL() + QStringLiteral("/modpack/")
                            + encodePath(QString::fromStdString(request.packIdentifier)) + QLatin1Char('/')
                            + QString::number(version.id),
                        diagnostic);
                    if (!versionResponse) {
                        return terminal(isCancellationRequested(cancellation) ? FrontendProviderVersionOutcome::Cancelled
                                                                               : FrontendProviderVersionOutcome::Failed,
                                        {},
                                        isCancellationRequested(cancellation) ? "providers.versions.cancelled"
                                                                              : "providers.versions.networkError",
                                        diagnostic.toStdString(),
                                        !isCancellationRequested(cancellation));
                    }
                    const auto versionDocument = parseJson(*versionResponse, diagnostic);
                    if (!versionDocument || !versionDocument->isObject()) {
                        return terminal(FrontendProviderVersionOutcome::Failed,
                                        {},
                                        "providers.versions.providerError",
                                        diagnostic.isEmpty() ? "FTB version metadata is invalid." : diagnostic.toStdString(),
                                        true);
                    }
                    FTB::Version manifest;
                    auto versionObject = versionDocument->object();
                    FTB::loadVersion(manifest, versionObject);
                    for (const auto& target : manifest.targets) {
                        const auto type = target.type.toLower();
                        if (type == QStringLiteral("minecraft") || type == QStringLiteral("game")) {
                            if (!target.version.isEmpty() && !gameVersions.contains(target.version)) {
                                gameVersions.append(target.version);
                            }
                        } else if ((type == QStringLiteral("forge") || type == QStringLiteral("fabric")
                                    || type == QStringLiteral("quilt") || type == QStringLiteral("neoforge"))
                                   && !loaders.contains(type)) {
                            loaders.append(type);
                        }
                    }
                }
                const auto row = versionSnapshot(request.provider,
                                                 FrontendProviderInstallKind::FTB,
                                                 QString::number(version.id),
                                                 QString::fromStdString(request.packIdentifier),
                                                 version.name,
                                                 version.name,
                                                 gameVersions,
                                                 loaders,
                                                 version.type == QStringLiteral("release") ? FrontendProviderReleaseType::Release
                                                                                            : FrontendProviderReleaseType::Unknown,
                                                 version.updated,
                                                 index == pack.versions.size() - 1);
                if (matchesVersionFilters(row, request.gameVersions, request.loaders, request.releaseTypes)) {
                    values.push_back(row);
                }
            }
        } else if (request.provider == FrontendProviderKind::ATLauncher) {
            const auto response = fetch.get(atlauncherIndexURL(), diagnostic);
            if (!response) {
                return terminal(isCancellationRequested(cancellation) ? FrontendProviderVersionOutcome::Cancelled
                                                                       : FrontendProviderVersionOutcome::Failed,
                                {},
                                isCancellationRequested(cancellation) ? "providers.versions.cancelled"
                                                                      : "providers.versions.networkError",
                                diagnostic.toStdString(),
                                !isCancellationRequested(cancellation));
            }
            const auto document = parseJson(*response, diagnostic);
            if (!document || !document->isArray()) {
                return terminal(FrontendProviderVersionOutcome::Failed,
                                {},
                                "providers.versions.providerError",
                                diagnostic.isEmpty() ? "ATLauncher pack index is invalid." : diagnostic.toStdString(),
                                true);
            }
            for (const auto& raw : document->array()) {
                ATLauncher::IndexedPack pack;
                auto object = raw.toObject();
                ATLauncher::loadIndexedPack(pack, object);
                if (pack.name != QString::fromStdString(request.packIdentifier)) {
                    continue;
                }
                for (qsizetype index = pack.versions.size() - 1; index >= 0; --index) {
                    const auto& version = pack.versions.at(index);
                    QStringList loaders;
                    if (!request.loaders.empty()) {
                        const auto manifestURL = BuildConfig.ATL_DOWNLOAD_SERVER_URL + QStringLiteral("packs/")
                            + safeATLauncherPackName(pack.name) + QStringLiteral("/versions/")
                            + encodePath(version.version) + QStringLiteral("/Configs.json");
                        const auto manifestResponse = fetch.get(manifestURL, diagnostic);
                        if (!manifestResponse) {
                            return terminal(isCancellationRequested(cancellation) ? FrontendProviderVersionOutcome::Cancelled
                                                                                   : FrontendProviderVersionOutcome::Failed,
                                            {},
                                            isCancellationRequested(cancellation) ? "providers.versions.cancelled"
                                                                                  : "providers.versions.networkError",
                                            diagnostic.toStdString(),
                                            !isCancellationRequested(cancellation));
                        }
                        const auto manifestDocument = parseJson(*manifestResponse, diagnostic);
                        if (!manifestDocument || !manifestDocument->isObject()) {
                            return terminal(FrontendProviderVersionOutcome::Failed,
                                            {},
                                            "providers.versions.providerError",
                                            diagnostic.isEmpty() ? "ATLauncher version metadata is invalid."
                                                                 : diagnostic.toStdString(),
                                            true);
                        }
                        ATLauncher::PackVersion manifest;
                        auto manifestObject = manifestDocument->object();
                        ATLauncher::loadVersion(manifest, manifestObject);
                        const auto loader = manifest.loader.type.trimmed().toLower();
                        if (!loader.isEmpty()) {
                            loaders.append(loader);
                        }
                    }
                    values.push_back(versionSnapshot(request.provider,
                                                     FrontendProviderInstallKind::ATLauncher,
                                                     version.version,
                                                     pack.name,
                                                     version.version,
                                                     version.version,
                                                     { version.minecraft },
                                                     loaders,
                                                     FrontendProviderReleaseType::Release,
                                                     0,
                                                     index == pack.versions.size() - 1));
                }
            }
        } else if (request.provider == FrontendProviderKind::Technic) {
            const auto response = fetch.get(technicDetailURL(QString::fromStdString(request.packIdentifier)), diagnostic);
            if (!response) {
                return terminal(isCancellationRequested(cancellation) ? FrontendProviderVersionOutcome::Cancelled
                                                                       : FrontendProviderVersionOutcome::Failed,
                                {},
                                isCancellationRequested(cancellation) ? "providers.versions.cancelled"
                                                                      : "providers.versions.networkError",
                                diagnostic.toStdString(),
                                !isCancellationRequested(cancellation));
            }
            const auto document = parseJson(*response, diagnostic);
            if (!document || !document->isObject()) {
                return terminal(FrontendProviderVersionOutcome::Failed,
                                {},
                                "providers.versions.providerError",
                                diagnostic.isEmpty() ? "Technic pack metadata is invalid." : diagnostic.toStdString(),
                                true);
            }
            const auto object = document->object();
            const auto solder = object.value(QStringLiteral("solder")).toString();
            if (!solder.isEmpty()) {
                auto solderURL = solder;
                while (solderURL.endsWith(QLatin1Char('/'))) {
                    solderURL.chop(1);
                }
                const auto solderResponse = fetch.get(solderURL + QStringLiteral("/modpack/")
                                                         + encodePath(QString::fromStdString(request.packIdentifier)),
                                                     diagnostic);
                if (solderResponse) {
                    const auto solderDocument = parseJson(*solderResponse, diagnostic);
                    if (solderDocument && solderDocument->isObject()) {
                        TechnicSolder::Pack pack;
                        auto solderObject = solderDocument->object();
                        TechnicSolder::loadPack(pack, solderObject);
                        for (qsizetype index = pack.builds.size() - 1; index >= 0; --index) {
                            const auto& build = pack.builds.at(index);
                            values.push_back(versionSnapshot(request.provider,
                                                             FrontendProviderInstallKind::TechnicSolder,
                                                             build,
                                                             QString::fromStdString(request.packIdentifier),
                                                             build,
                                                             build,
                                                             { object.value(QStringLiteral("minecraft")).toString() },
                                                             {},
                                                             FrontendProviderReleaseType::Release,
                                                             0,
                                                             build == pack.recommended));
                        }
                    }
                }
            }
            if (values.empty()) {
                const auto version = object.value(QStringLiteral("version")).toString();
                if (!version.isEmpty()) {
                    values.push_back(versionSnapshot(request.provider,
                                                     FrontendProviderInstallKind::TechnicZip,
                                                     version,
                                                     QString::fromStdString(request.packIdentifier),
                                                     version,
                                                     version,
                                                     { object.value(QStringLiteral("minecraft")).toString() },
                                                     {},
                                                     FrontendProviderReleaseType::Release,
                                                     0,
                                                     true));
                }
            }
        } else if (request.provider == FrontendProviderKind::LegacyFTB) {
            const auto separator = QString::fromStdString(request.packIdentifier).indexOf(QLatin1Char('|'));
            if (separator <= 0) {
                return terminal(FrontendProviderVersionOutcome::Failed,
                                {},
                                "providers.versions.providerError",
                                "Legacy FTB pack identifier is invalid.",
                                false);
            }
            const auto wantedDir = QString::fromStdString(request.packIdentifier).left(separator);
            const auto wantedFile = QString::fromStdString(request.packIdentifier).mid(separator + 1);
            for (const auto& listName : { QStringLiteral("modpacks.xml"), QStringLiteral("thirdparty.xml") }) {
                const auto response = fetch.get(
                    BuildConfig.LEGACY_FTB_CDN_BASE_URL + QStringLiteral("static/") + listName, diagnostic);
                if (!response) {
                    return terminal(isCancellationRequested(cancellation) ? FrontendProviderVersionOutcome::Cancelled
                                                                           : FrontendProviderVersionOutcome::Failed,
                                    {},
                                    isCancellationRequested(cancellation) ? "providers.versions.cancelled"
                                                                          : "providers.versions.networkError",
                                    diagnostic.toStdString(),
                                    !isCancellationRequested(cancellation));
                }
                const auto packs = parseLegacyPacks(byteArrayFromVector(*response), diagnostic);
                if (!diagnostic.isEmpty()) {
                    return terminal(FrontendProviderVersionOutcome::Failed,
                                    {},
                                    "providers.versions.providerError",
                                    diagnostic.toStdString(),
                                    true);
                }
                for (const auto& pack : packs) {
                    if (pack.dir != wantedDir || pack.file != wantedFile) {
                        continue;
                    }
                    for (qsizetype index = pack.oldVersions.size() - 1; index >= 0; --index) {
                        const auto& version = pack.oldVersions.at(index);
                        values.push_back(versionSnapshot(request.provider,
                                                         FrontendProviderInstallKind::LegacyFTB,
                                                         version,
                                                         QString::fromStdString(request.packIdentifier),
                                                         version,
                                                         version,
                                                         { pack.mcVersion },
                                                         {},
                                                         FrontendProviderReleaseType::Release,
                                                         0,
                                                         version == pack.currentVersion));
                    }
                    break;
                }
                if (!values.empty()) {
                    break;
                }
            }
        }
    } catch (const std::exception& exception) {
        return terminal(FrontendProviderVersionOutcome::Failed,
                        {},
                        "providers.versions.providerError",
                        exception.what(),
                        true);
    }

    std::erase_if(values, [&](const auto& row) {
        return !matchesVersionFilters(row, request.gameVersions, request.loaders, request.releaseTypes);
    });

    if (isCancellationRequested(cancellation)) {
        return terminal(FrontendProviderVersionOutcome::Cancelled,
                        {},
                        "providers.versions.cancelled",
                        "Provider version loading was cancelled.",
                        false);
    }
    return terminal(FrontendProviderVersionOutcome::Succeeded,
                    std::move(values),
                    "providers.versions.completed",
                    {},
                    false);
}

namespace {

struct InstallFilePlan final {
    QString id;
    QString name;
    QString targetPath;
    QString url;
    bool required = true;
    bool optional = false;
    bool blocked = false;
    bool selected = true;
    QString hashAlgorithm;
    QString hashDigest;
};

struct InstallPlan final {
    QString minecraftVersion;
    QString loaderIdentifier;
    QString loaderVersion;
    QJsonArray preservedComponents;
    std::vector<InstallFilePlan> files;
    std::filesystem::path extractedRoot;
};

struct InstallFailure final : std::runtime_error {
    FrontendProviderInstallRecoveryKind kind;
    bool retryable;
    std::optional<FrontendProviderInstallRecoveryPrompt> prompt;

    InstallFailure(
        FrontendProviderInstallRecoveryKind failureKind,
        std::string message,
        bool canRetry,
        std::optional<FrontendProviderInstallRecoveryPrompt> recovery = std::nullopt)
        : std::runtime_error(std::move(message)), kind(failureKind), retryable(canRetry), prompt(std::move(recovery))
    {}
};

QString normalizeArchivePath(const QString& raw, bool& directory)
{
    if (raw.isEmpty() || raw.contains(QChar('\0')) || raw.contains(QLatin1Char('\\'))) {
        return {};
    }
    directory = raw.endsWith(QLatin1Char('/'));
    QString candidate = raw;
    while (candidate.startsWith(QStringLiteral("./"))) {
        candidate.remove(0, 2);
    }
    if (candidate.isEmpty()) {
        return {};
    }
    if (candidate.startsWith(QLatin1Char('/')) || candidate.contains(QStringLiteral("//"))) {
        return {};
    }
    const auto components = candidate.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    QStringList normalized;
    for (const auto& component : components) {
        if (!isSafeComponent(component.toStdString(), 512)) {
            return {};
        }
        normalized.append(component);
    }
    return normalized.join(QLatin1Char('/'));
}

bool extractArchive(
    const std::filesystem::path& archivePath,
    const std::filesystem::path& destination,
    const std::function<bool()>& cancellation,
    QString& diagnostic)
{
    if (!isRegularFile(archivePath) || !pathIsContained(destination.parent_path(), destination)) {
        diagnostic = QStringLiteral("Provider archive path was rejected.");
        return false;
    }
    std::error_code error;
    std::filesystem::create_directories(destination, error);
    if (error || isSymlink(destination)) {
        diagnostic = QStringLiteral("Provider archive staging could not be created.");
        return false;
    }

    MMCZip::ArchiveReader archive(QString::fromStdString(archivePath.string()));
    std::size_t entries = 0;
    std::size_t totalBytes = 0;
    bool valid = true;
    const bool parsed = archive.parse([&](MMCZip::ArchiveReader::File* file) {
        if (isCancellationRequested(cancellation)) {
            valid = false;
            return false;
        }
        if (++entries > kMaximumArchiveEntries) {
            diagnostic = QStringLiteral("Provider archive contains too many entries.");
            valid = false;
            return false;
        }
        bool directory = false;
        const auto normalized = normalizeArchivePath(file->filename(), directory);
        if (normalized.isEmpty()) {
            diagnostic = QStringLiteral("Provider archive contains an unsafe path.");
            valid = false;
            return false;
        }
        const auto target = destination / normalized.toStdString();
        if (!pathIsContained(destination, target)) {
            diagnostic = QStringLiteral("Provider archive escaped its staging directory.");
            valid = false;
            return false;
        }
        if (!file->isFile()) {
            if (!directory) {
                diagnostic = QStringLiteral("Provider archive contains an unsupported link.");
                valid = false;
                return false;
            }
            std::filesystem::create_directories(target, error);
            return !error && !isSymlink(target);
        }
        int status = ARCHIVE_OK;
        const auto data = file->readAll(&status);
        if (status != ARCHIVE_OK && status != ARCHIVE_EOF) {
            diagnostic = QStringLiteral("Provider archive entry could not be read.");
            valid = false;
            return false;
        }
        if (data.size() < 0 || static_cast<std::size_t>(data.size()) > kMaximumArchiveBytes - totalBytes) {
            diagnostic = QStringLiteral("Provider archive is too large.");
            valid = false;
            return false;
        }
        totalBytes += static_cast<std::size_t>(data.size());
        if (!writeBytes(target, data)) {
            diagnostic = QStringLiteral("Provider archive entry could not be written.");
            valid = false;
            return false;
        }
        return true;
    });
    if (!parsed || !valid) {
        if (diagnostic.isEmpty()) {
            diagnostic = isCancellationRequested(cancellation) ? QStringLiteral("Provider archive extraction was cancelled.")
                                                                : QStringLiteral("Provider archive could not be extracted.");
        }
        return false;
    }
    return true;
}

bool copyTreeContents(
    const std::filesystem::path& source,
    const std::filesystem::path& destination,
    const std::set<std::string>& excludedNames,
    QString& diagnostic,
    const std::function<bool()>& cancellation)
{
    if (!isDirectory(source) || !pathIsContained(source.parent_path(), source)
        || !pathIsContained(destination.parent_path(), destination)) {
        diagnostic = QStringLiteral("Provider source tree was rejected.");
        return false;
    }
    std::error_code error;
    std::filesystem::create_directories(destination, error);
    if (error || isSymlink(destination)) {
        diagnostic = QStringLiteral("Provider destination tree could not be created.");
        return false;
    }
    std::filesystem::recursive_directory_iterator iterator(source, error);
    const std::filesystem::recursive_directory_iterator end;
    if (error) {
        diagnostic = QStringLiteral("Provider source tree could not be inspected.");
        return false;
    }
    for (; iterator != end; iterator.increment(error)) {
        if (error || isCancellationRequested(cancellation)) {
            diagnostic = isCancellationRequested(cancellation) ? QStringLiteral("Provider installation was cancelled.")
                                                                : QStringLiteral("Provider source tree could not be inspected.");
            return false;
        }
        const auto& entry = *iterator;
        const auto relative = entry.path().lexically_relative(source);
        if (relative.empty() || !pathIsContained(source, entry.path())) {
            diagnostic = QStringLiteral("Provider source tree escaped its root.");
            return false;
        }
        if (relative.has_parent_path() && excludedNames.contains(relative.begin()->string())) {
            iterator.disable_recursion_pending();
            continue;
        }
        if (excludedNames.contains(relative.filename().string())) {
            if (entry.is_directory(error)) {
                iterator.disable_recursion_pending();
            }
            continue;
        }
        const auto target = destination / relative;
        if (!pathIsContained(destination, target) || isSymlink(entry.path())) {
            diagnostic = QStringLiteral("Provider source tree contains an unsafe link or path.");
            return false;
        }
        if (entry.is_directory(error)) {
            std::filesystem::create_directories(target, error);
            if (error || isSymlink(target)) {
                diagnostic = QStringLiteral("Provider directory could not be created.");
                return false;
            }
        } else if (entry.is_regular_file(error)) {
            const auto data = readBytes(entry.path());
            if (!data || !writeBytes(target, *data)) {
                diagnostic = QStringLiteral("Provider file could not be copied.");
                return false;
            }
        } else {
            diagnostic = QStringLiteral("Provider source tree contains an unsupported entry.");
            return false;
        }
    }
    return !error;
}

std::optional<QJsonObject> readJsonObject(const std::filesystem::path& path, QString& diagnostic)
{
    const auto data = readBytes(path);
    if (!data) {
        diagnostic = QStringLiteral("Provider manifest was not found.");
        return std::nullopt;
    }
    const auto document = QJsonDocument::fromJson(*data);
    if (!document.isObject()) {
        diagnostic = QStringLiteral("Provider manifest is not a JSON object.");
        return std::nullopt;
    }
    return document.object();
}

QString absoluteProviderURL(const QString& base, const QString& raw)
{
    if (raw.isEmpty()) {
        return {};
    }
    const QUrl value(raw);
    if (value.isValid() && !value.isRelative()) {
        return value.toString(QUrl::FullyEncoded);
    }
    return QUrl(base + raw).toString(QUrl::FullyEncoded);
}

QString jsonString(const QJsonObject& object, std::initializer_list<QString> names)
{
    for (const auto& name : names) {
        const auto value = object.value(name);
        if (value.isString() && !value.toString().trimmed().isEmpty()) {
            return value.toString().trimmed();
        }
    }
    return {};
}

std::pair<QString, QString> preferredHash(const QJsonObject& hashes)
{
    for (const auto& algorithm : { QStringLiteral("sha512"), QStringLiteral("sha1"), QStringLiteral("md5") }) {
        const auto digest = hashes.value(algorithm).toString().trimmed().toLower();
        if (!digest.isEmpty()) {
            return { algorithm, digest };
        }
    }
    return {};
}

std::pair<QString, QString> curseForgeHash(const QJsonArray& hashes)
{
    std::pair<QString, QString> selected;
    for (const auto& raw : hashes) {
        const auto object = raw.toObject();
        const auto digest = object.value(QStringLiteral("value")).toString().trimmed().toLower();
        if (digest.isEmpty()) {
            continue;
        }
        if (object.value(QStringLiteral("algo")).toInt() == 1) {
            return { QStringLiteral("sha1"), digest };
        }
        if (object.value(QStringLiteral("algo")).toInt() == 2) {
            selected = { QStringLiteral("md5"), digest };
        }
    }
    return selected;
}

bool hashMatches(const Bytes& bytes, const QString& algorithm, const QString& expected)
{
    if (algorithm.isEmpty() && expected.isEmpty()) {
        return true;
    }
    if (algorithm.isEmpty() || expected.isEmpty()) {
        return false;
    }
    QCryptographicHash::Algorithm qtAlgorithm;
    if (algorithm == QStringLiteral("sha512")) {
        qtAlgorithm = QCryptographicHash::Sha512;
    } else if (algorithm == QStringLiteral("sha1")) {
        qtAlgorithm = QCryptographicHash::Sha1;
    } else if (algorithm == QStringLiteral("md5")) {
        qtAlgorithm = QCryptographicHash::Md5;
    } else {
        return false;
    }
    const auto actual = QCryptographicHash::hash(byteArrayFromVector(bytes), qtAlgorithm).toHex();
    return QString::fromLatin1(actual).compare(expected, Qt::CaseInsensitive) == 0;
}

void addPlanFile(
    InstallPlan& plan,
    QString id,
    QString name,
    QString targetPath,
    QString url,
    bool required,
    bool optional,
    bool blocked,
    QString hashAlgorithm = {},
    QString hashDigest = {})
{
    bool directory = false;
    const auto normalized = normalizeArchivePath(targetPath, directory);
    if (normalized.isEmpty() || directory) {
        throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                             "Provider manifest contains an unsafe file path.",
                             false);
    }
    if (id.isEmpty()) {
        id = normalized;
    }
    if (name.isEmpty()) {
        name = normalized;
    }
    plan.files.push_back({ std::move(id),
                           std::move(name),
                           normalized,
                           std::move(url),
                           required,
                           optional,
                           blocked,
                           !optional && !blocked,
                           std::move(hashAlgorithm),
                           std::move(hashDigest) });
}

FrontendProviderKind providerForInstallKind(FrontendProviderInstallKind kind)
{
    switch (kind) {
        case FrontendProviderInstallKind::Modrinth:
            return FrontendProviderKind::Modrinth;
        case FrontendProviderInstallKind::CurseForgeFlame:
            return FrontendProviderKind::CurseForge;
        case FrontendProviderInstallKind::FTB:
        case FrontendProviderInstallKind::FTBImport:
            return FrontendProviderKind::FTB;
        case FrontendProviderInstallKind::LegacyFTB:
            return FrontendProviderKind::LegacyFTB;
        case FrontendProviderInstallKind::ATLauncher:
            return FrontendProviderKind::ATLauncher;
        case FrontendProviderInstallKind::TechnicZip:
        case FrontendProviderInstallKind::TechnicSolder:
            return FrontendProviderKind::Technic;
        case FrontendProviderInstallKind::CustomArchive:
            return FrontendProviderKind::Modrinth;
    }
    return FrontendProviderKind::Modrinth;
}

QString installKindName(FrontendProviderInstallKind kind)
{
    switch (kind) {
        case FrontendProviderInstallKind::Modrinth: return QStringLiteral("modrinth");
        case FrontendProviderInstallKind::CurseForgeFlame: return QStringLiteral("curseforge");
        case FrontendProviderInstallKind::FTB: return QStringLiteral("ftb");
        case FrontendProviderInstallKind::LegacyFTB: return QStringLiteral("legacy-ftb");
        case FrontendProviderInstallKind::FTBImport: return QStringLiteral("ftb-import");
        case FrontendProviderInstallKind::ATLauncher: return QStringLiteral("atlauncher");
        case FrontendProviderInstallKind::TechnicZip:
        case FrontendProviderInstallKind::TechnicSolder: return QStringLiteral("technic");
        case FrontendProviderInstallKind::CustomArchive: return QStringLiteral("custom");
    }
    return QStringLiteral("unknown");
}

QString safeATLauncherPackName(QString value)
{
    value.remove(QRegularExpression(QStringLiteral("[^A-Za-z0-9]")));
    return value;
}

QString atLauncherTarget(ATLauncher::ModType type, const QString& file)
{
    switch (type) {
        case ATLauncher::ModType::Root:
            return file;
        case ATLauncher::ModType::Forge:
        case ATLauncher::ModType::Jar:
            return QStringLiteral("jarmods/") + file;
        case ATLauncher::ModType::Flan:
            return QStringLiteral("flan/") + file;
        case ATLauncher::ModType::ResourcePack:
        case ATLauncher::ModType::ResourcePackExtract:
            return QStringLiteral("resourcepacks/") + file;
        case ATLauncher::ModType::TexturePack:
        case ATLauncher::ModType::TexturePackExtract:
            return QStringLiteral("texturepacks/") + file;
        case ATLauncher::ModType::ShaderPack:
            return QStringLiteral("shaderpacks/") + file;
        case ATLauncher::ModType::Plugins:
            return QStringLiteral("plugins/") + file;
        case ATLauncher::ModType::Extract:
        case ATLauncher::ModType::Decomp:
            return file;
        default:
            return QStringLiteral("mods/") + file;
    }
}

QString loaderUID(const QString& raw)
{
    if (raw == QStringLiteral("fabric-loader")) {
        return QStringLiteral("net.fabricmc.fabric-loader");
    }
    if (raw == QStringLiteral("quilt-loader")) {
        return QStringLiteral("org.quiltmc.quilt-loader");
    }
    if (raw == QStringLiteral("forge")) {
        return QStringLiteral("net.minecraftforge");
    }
    if (raw == QStringLiteral("neoforge")) {
        return QStringLiteral("net.neoforged");
    }
    return raw;
}

bool writeProviderMetadata(
    const std::filesystem::path& staging,
    const FrontendProviderInstallRequest& request,
    const InstallPlan& plan,
    QString& diagnostic)
{
    if (plan.minecraftVersion.trimmed().isEmpty()
        || (plan.loaderIdentifier.isEmpty() != plan.loaderVersion.isEmpty())) {
        diagnostic = QStringLiteral("Provider metadata does not identify a complete Minecraft version.");
        return false;
    }
    std::error_code error;
    std::filesystem::create_directories(staging / "minecraft", error);
    std::filesystem::create_directories(staging / "patches", error);
    if (error) {
        diagnostic = QStringLiteral("Provider instance staging could not be prepared.");
        return false;
    }
    INIFile settings;
    settings.set("InstanceType", QStringLiteral("Minecraft"));
    settings.set("name", QString::fromStdString(request.name));
    settings.set("iconKey", QString::fromStdString(request.iconKey));
    settings.set("InstanceGroupId", QString::fromStdString(request.groupId));
    settings.set("totalTimePlayed", 0);
    settings.set("lastTimePlayed", 0);
    if (!settings.saveFile(QString::fromStdString((staging / "instance.cfg").string()))) {
        diagnostic = QStringLiteral("Provider instance metadata could not be saved.");
        return false;
    }

    QJsonObject root;
    root.insert(QStringLiteral("formatVersion"), 1);
    QJsonArray components = plan.preservedComponents;
    if (components.isEmpty()) {
        QJsonObject minecraft;
        minecraft.insert(QStringLiteral("uid"), QStringLiteral("net.minecraft"));
        minecraft.insert(QStringLiteral("version"), plan.minecraftVersion);
        minecraft.insert(QStringLiteral("important"), true);
        components.append(minecraft);
        if (!plan.loaderIdentifier.isEmpty() && !plan.loaderVersion.isEmpty()) {
            QJsonObject loader;
            loader.insert(QStringLiteral("uid"), plan.loaderIdentifier);
            loader.insert(QStringLiteral("version"), plan.loaderVersion);
            components.append(loader);
        }
    }
    root.insert(QStringLiteral("components"), components);
    if (!writeText(staging / "mmc-pack.json", QJsonDocument(root))) {
        diagnostic = QStringLiteral("Provider component metadata could not be saved.");
        return false;
    }

    auto patch = std::make_shared<VersionFile>();
    patch->name = QStringLiteral("Minecraft");
    patch->uid = QStringLiteral("net.minecraft");
    patch->version = plan.minecraftVersion;
    patch->minecraftVersion = plan.minecraftVersion;
    patch->type = QStringLiteral("release");
    if (!writeBytes(staging / "patches/net.minecraft.json",
                    OneSixVersionFormat::versionFileToJson(patch).toJson(QJsonDocument::Indented))) {
        diagnostic = QStringLiteral("Provider Minecraft metadata could not be saved.");
        return false;
    }

    QJsonObject providerMetadata;
    providerMetadata.insert(QStringLiteral("formatVersion"), 1);
    providerMetadata.insert(QStringLiteral("provider"), installKindName(request.kind));
    providerMetadata.insert(QStringLiteral("packIdentifier"), QString::fromStdString(request.packIdentifier));
    providerMetadata.insert(QStringLiteral("versionIdentifier"), QString::fromStdString(request.versionIdentifier));
    if (!writeText(staging / ".prism-native-provider.json", QJsonDocument(providerMetadata))) {
        diagnostic = QStringLiteral("Provider provenance metadata could not be saved.");
        return false;
    }
    return true;
}

std::filesystem::path stageArchive(
    const Bytes& bytes,
    const std::filesystem::path& staging,
    const std::string& label,
    const std::function<bool()>& cancellation)
{
    const auto archivePath = staging / ("." + label + ".archive");
    const auto extracted = staging / (label + "-contents");
    if (!writeBytes(archivePath, byteArrayFromVector(bytes))) {
        throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                             "Provider archive could not be staged.",
                             true);
    }
    QString diagnostic;
    if (!extractArchive(archivePath, extracted, cancellation, diagnostic)) {
        throw InstallFailure(isCancellationRequested(cancellation) ? FrontendProviderInstallRecoveryKind::ProviderError
                                                                     : FrontendProviderInstallRecoveryKind::ProviderError,
                             diagnostic.toStdString(),
                             false);
    }
    std::error_code error;
    std::filesystem::remove(archivePath, error);
    return extracted;
}

void downloadArchive(
    FetchContext& fetch,
    const QString& url,
    const std::filesystem::path& staging,
    const std::string& label,
    const std::function<bool()>& cancellation,
    std::filesystem::path& extractedRoot,
    QString& diagnostic,
    QString hashAlgorithm = {},
    QString hashDigest = {})
{
    const auto bytes = fetch.get(url, diagnostic);
    if (!bytes) {
        throw InstallFailure(FrontendProviderInstallRecoveryKind::NetworkError,
                             diagnostic.isEmpty() ? "Provider archive download failed." : diagnostic.toStdString(),
                             true);
    }
    if (!hashMatches(*bytes, hashAlgorithm, hashDigest)) {
        throw InstallFailure(FrontendProviderInstallRecoveryKind::NetworkError,
                             "Provider archive failed its integrity check.",
                             true);
    }
    extractedRoot = stageArchive(*bytes, staging, label, cancellation);
}

bool loadPrismPackComponents(InstallPlan& plan, std::filesystem::path& sourceRoot)
{
    std::vector<std::filesystem::path> candidates{ sourceRoot };
    std::error_code error;
    for (std::filesystem::directory_iterator iterator(sourceRoot, error), end;
         !error && iterator != end;
         iterator.increment(error)) {
        if (iterator->is_directory(error) && !isSymlink(iterator->path())
            && pathIsContained(sourceRoot, iterator->path())) {
            candidates.push_back(iterator->path());
        }
    }
    for (const auto& candidate : candidates) {
        QString diagnostic;
        const auto pack = readJsonObject(candidate / "mmc-pack.json", diagnostic);
        if (!pack) {
            continue;
        }
        const auto components = pack->value(QStringLiteral("components")).toArray();
        QJsonArray validatedComponents;
        std::set<QString> identifiers;
        QString minecraftVersion;
        QString loaderIdentifier;
        QString loaderVersion;
        for (const auto& raw : components) {
            const auto component = raw.toObject();
            const auto uid = component.value(QStringLiteral("uid")).toString();
            const auto version = component.value(QStringLiteral("version")).toString();
            if (uid.isEmpty() || version.isEmpty() || identifiers.contains(uid)) {
                validatedComponents = {};
                break;
            }
            identifiers.insert(uid);
            validatedComponents.append(component);
            if (uid == QStringLiteral("net.minecraft")) {
                minecraftVersion = version;
            } else if ((uid == QStringLiteral("net.fabricmc.fabric-loader")
                        || uid == QStringLiteral("org.quiltmc.quilt-loader")
                        || uid == QStringLiteral("net.minecraftforge")
                        || uid == QStringLiteral("net.neoforged"))
                       && loaderIdentifier.isEmpty()) {
                loaderIdentifier = uid;
                loaderVersion = version;
            }
        }
        if (!minecraftVersion.isEmpty() && validatedComponents.size() == components.size()) {
            plan.minecraftVersion = minecraftVersion;
            plan.loaderIdentifier = loaderIdentifier;
            plan.loaderVersion = loaderVersion;
            plan.preservedComponents = validatedComponents;
            sourceRoot = candidate;
            return true;
        }
    }
    return false;
}

bool loadFTBImportComponents(InstallPlan& plan, const std::filesystem::path& sourceRoot)
{
    QString diagnostic;
    const auto instance = readJsonObject(sourceRoot / "instance.json", diagnostic);
    if (!instance) {
        return false;
    }
    plan.minecraftVersion = instance->value(QStringLiteral("mcVersion")).toString().trimmed();
    const auto loader = instance->value(QStringLiteral("modLoader")).toString().trimmed();
    const auto separator = loader.indexOf(QLatin1Char('-'));
    if (separator > 0 && separator + 1 < loader.size()) {
        plan.loaderIdentifier = loaderUID(loader.left(separator).toLower());
        plan.loaderVersion = loader.mid(separator + 1).trimmed();
    }
    if (plan.loaderIdentifier.isEmpty()) {
        auto versionPath = sourceRoot / ".ftbapp/version.json";
        if (!isRegularFile(versionPath)) {
            versionPath = sourceRoot / "version.json";
        }
        if (const auto version = readJsonObject(versionPath, diagnostic)) {
            for (const auto& raw : version->value(QStringLiteral("targets")).toArray()) {
                const auto target = raw.toObject();
                const auto name = target.value(QStringLiteral("name")).toString().toLower();
                const auto value = target.value(QStringLiteral("version")).toString();
                if ((name == QStringLiteral("forge") || name == QStringLiteral("neoforge")
                     || name == QStringLiteral("fabric") || name == QStringLiteral("quilt"))
                    && !value.isEmpty()) {
                    plan.loaderIdentifier = loaderUID(name == QStringLiteral("fabric") ? QStringLiteral("fabric-loader")
                                                                                         : (name == QStringLiteral("quilt")
                                                                                                ? QStringLiteral("quilt-loader")
                                                                                                : name));
                    plan.loaderVersion = value;
                    break;
                }
            }
        }
    }
    return !plan.minecraftVersion.isEmpty();
}

InstallPlan resolveInstallPlan(
    FetchContext& fetch,
    const FrontendProviderInstallRequest& request,
    const std::filesystem::path& staging,
    const std::function<bool()>& cancellation)
{
    InstallPlan plan;
    QString diagnostic;
    auto requireResponse = [&](const QString& url, const char* failureMessage) {
        const auto response = fetch.get(url, diagnostic);
        if (!response) {
            throw InstallFailure(isCancellationRequested(cancellation) ? FrontendProviderInstallRecoveryKind::NetworkError
                                                                         : FrontendProviderInstallRecoveryKind::NetworkError,
                                 diagnostic.isEmpty() ? failureMessage : diagnostic.toStdString(),
                                 true);
        }
        return *response;
    };
    auto setMinecraftFrom = [&](const QJsonObject& object) {
        const auto value = jsonString(object, { QStringLiteral("minecraft"), QStringLiteral("minecraftVersion") });
        if (!value.isEmpty()) {
            plan.minecraftVersion = value;
        }
    };

    switch (request.kind) {
        case FrontendProviderInstallKind::Modrinth: {
            const auto response = requireResponse(BuildConfig.MODRINTH_PROD_URL + QStringLiteral("/version/")
                                                       + encodePath(QString::fromStdString(request.versionIdentifier)),
                                                   "Modrinth version metadata could not be loaded.");
            const auto document = parseJson(response, diagnostic);
            if (!document || !document->isObject()) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     diagnostic.toStdString(),
                                     true);
            }
            const auto object = document->object();
            setMinecraftFrom(object.value(QStringLiteral("dependencies")).toObject());
            const auto dependencies = object.value(QStringLiteral("dependencies")).toObject();
            for (auto iterator = dependencies.constBegin(); iterator != dependencies.constEnd(); ++iterator) {
                if (iterator.key() == QStringLiteral("minecraft")) {
                    plan.minecraftVersion = iterator.value().toString(plan.minecraftVersion);
                    continue;
                }
                if (iterator.key() == QStringLiteral("fabric-loader") || iterator.key() == QStringLiteral("quilt-loader")
                    || iterator.key() == QStringLiteral("forge") || iterator.key() == QStringLiteral("neoforge")) {
                    plan.loaderIdentifier = loaderUID(iterator.key());
                    plan.loaderVersion = iterator.value().toString();
                }
            }
            QString archiveURL;
            QString archiveHashAlgorithm;
            QString archiveHashDigest;
            for (const auto& raw : object.value(QStringLiteral("files")).toArray()) {
                const auto file = raw.toObject();
                const auto url = jsonString(file, { QStringLiteral("url"), QStringLiteral("downloadUrl") });
                const auto fileName = file.value(QStringLiteral("filename")).toString();
                if (!url.isEmpty() && (file.value(QStringLiteral("primary")).toBool() || archiveURL.isEmpty()
                                       || fileName.endsWith(QStringLiteral(".mrpack")))) {
                    archiveURL = url;
                    const auto [algorithm, digest] = preferredHash(file.value(QStringLiteral("hashes")).toObject());
                    archiveHashAlgorithm = algorithm;
                    archiveHashDigest = digest;
                }
            }
            if (archiveURL.isEmpty()) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     "Modrinth version has no downloadable archive.",
                                     true);
            }
            downloadArchive(fetch,
                            archiveURL,
                            staging,
                            "modrinth",
                            cancellation,
                            plan.extractedRoot,
                            diagnostic,
                            archiveHashAlgorithm,
                            archiveHashDigest);
            const auto index = readJsonObject(plan.extractedRoot / "modrinth.index.json", diagnostic);
            if (!index) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     diagnostic.toStdString(),
                                     false);
            }
            const auto indexDependencies = index->value(QStringLiteral("dependencies")).toObject();
            if (plan.minecraftVersion.isEmpty()) {
                plan.minecraftVersion = indexDependencies.value(QStringLiteral("minecraft")).toString(plan.minecraftVersion);
            }
            for (auto iterator = indexDependencies.constBegin(); iterator != indexDependencies.constEnd(); ++iterator) {
                if (iterator.key() == QStringLiteral("minecraft")) {
                    continue;
                }
                if (iterator.key() == QStringLiteral("fabric-loader") || iterator.key() == QStringLiteral("quilt-loader")
                    || iterator.key() == QStringLiteral("forge") || iterator.key() == QStringLiteral("neoforge")) {
                    plan.loaderIdentifier = loaderUID(iterator.key());
                    plan.loaderVersion = iterator.value().toString();
                }
            }
            for (const auto& raw : index->value(QStringLiteral("files")).toArray()) {
                const auto file = raw.toObject();
                const auto target = file.value(QStringLiteral("path")).toString();
                const auto downloads = file.value(QStringLiteral("downloads")).toArray();
                const auto url = downloads.isEmpty() ? QString() : downloads.first().toString();
                const auto env = file.value(QStringLiteral("env")).toObject();
                const auto client = env.value(QStringLiteral("client")).toString(QStringLiteral("required"));
                const bool optional = client != QStringLiteral("required");
                const auto [algorithm, digest] = preferredHash(file.value(QStringLiteral("hashes")).toObject());
                addPlanFile(plan,
                            digest,
                            target,
                            target,
                            url,
                            !optional,
                            optional,
                            url.isEmpty(),
                            algorithm,
                            digest);
            }
            break;
        }
        case FrontendProviderInstallKind::CurseForgeFlame: {
            const auto url = QString(BuildConfig.FLAME_BASE_URL + QStringLiteral("/mods/%1/files/%2"))
                                 .arg(encodePath(QString::fromStdString(request.packIdentifier)),
                                      encodePath(QString::fromStdString(request.versionIdentifier)));
            const auto response = requireResponse(url, "CurseForge file metadata could not be loaded.");
            const auto document = parseJson(response, diagnostic);
            if (!document || !document->isObject()) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     diagnostic.toStdString(),
                                     true);
            }
            const auto object = document->object().value(QStringLiteral("data")).toObject().isEmpty()
                ? document->object()
                : document->object().value(QStringLiteral("data")).toObject();
            const auto archiveURL = jsonString(object, { QStringLiteral("downloadUrl"), QStringLiteral("download_url"), QStringLiteral("url") });
            if (archiveURL.isEmpty()) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::NetworkError,
                                     "CurseForge did not provide a downloadable file URL.",
                                     true);
            }
            const auto [archiveHashAlgorithm, archiveHashDigest] = curseForgeHash(
                object.value(QStringLiteral("hashes")).toArray());
            downloadArchive(fetch,
                            archiveURL,
                            staging,
                            "curseforge",
                            cancellation,
                            plan.extractedRoot,
                            diagnostic,
                            archiveHashAlgorithm,
                            archiveHashDigest);
            auto manifest = readJsonObject(plan.extractedRoot / "manifest.json", diagnostic);
            if (!manifest) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     diagnostic.toStdString(),
                                     false);
            }
            const auto minecraft = manifest->value(QStringLiteral("minecraft")).toObject();
            plan.minecraftVersion = minecraft.value(QStringLiteral("version")).toString().trimmed();
            const auto loaders = minecraft.value(QStringLiteral("modLoaders")).toArray();
            if (!loaders.isEmpty()) {
                const auto loader = loaders.first().toObject().value(QStringLiteral("id")).toString();
                const auto split = loader.indexOf(QLatin1Char('-'));
                if (split > 0) {
                    plan.loaderIdentifier = loaderUID(loader.left(split));
                    plan.loaderVersion = loader.mid(split + 1);
                }
            }
            for (const auto& raw : manifest->value(QStringLiteral("files")).toArray()) {
                const auto file = raw.toObject();
                const auto projectID = QString::number(file.value(QStringLiteral("projectID")).toInteger());
                const auto fileID = QString::number(file.value(QStringLiteral("fileID")).toInteger());
                if (projectID == QStringLiteral("0") || fileID == QStringLiteral("0")) {
                    throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                         "CurseForge manifest contains an invalid project or file identifier.",
                                         false);
                }
                const auto metadataResponse = requireResponse(
                    QString(BuildConfig.FLAME_BASE_URL + QStringLiteral("/mods/%1/files/%2"))
                        .arg(encodePath(projectID), encodePath(fileID)),
                    "CurseForge dependency metadata could not be loaded.");
                const auto metadataDocument = parseJson(metadataResponse, diagnostic);
                if (!metadataDocument || !metadataDocument->isObject()) {
                    throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                         diagnostic.isEmpty() ? "CurseForge dependency metadata is invalid."
                                                              : diagnostic.toStdString(),
                                         true);
                }
                const auto metadata = metadataDocument->object().value(QStringLiteral("data")).toObject().isEmpty()
                    ? metadataDocument->object()
                    : metadataDocument->object().value(QStringLiteral("data")).toObject();
                const auto downloadURL = jsonString(
                    metadata, { QStringLiteral("downloadUrl"), QStringLiteral("download_url"), QStringLiteral("url") });
                auto fileName = jsonString(metadata, { QStringLiteral("fileName"), QStringLiteral("displayName") });
                if (fileName.isEmpty()) {
                    fileName = fileID + QStringLiteral(".jar");
                }
                const bool required = file.value(QStringLiteral("required")).toBool(true);
                const auto [algorithm, digest] = curseForgeHash(metadata.value(QStringLiteral("hashes")).toArray());
                addPlanFile(plan,
                            fileID,
                            fileName,
                            QStringLiteral("mods/") + fileName,
                            downloadURL,
                            required,
                            !required,
                            downloadURL.isEmpty(),
                            algorithm,
                            digest);
            }
            break;
        }
        case FrontendProviderInstallKind::FTB: {
            const auto url = ftbBaseURL() + QStringLiteral("/modpack/") + encodePath(QString::fromStdString(request.packIdentifier))
                + QLatin1Char('/') + encodePath(QString::fromStdString(request.versionIdentifier));
            const auto response = requireResponse(url, "FTB version metadata could not be loaded.");
            const auto document = parseJson(response, diagnostic);
            if (!document || !document->isObject()) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     diagnostic.toStdString(),
                                     true);
            }
            auto object = document->object();
            setMinecraftFrom(object);
            const auto archiveURL = jsonString(object, { QStringLiteral("archiveUrl"), QStringLiteral("downloadUrl") });
            if (!archiveURL.isEmpty()) {
                downloadArchive(fetch, archiveURL, staging, "ftb", cancellation, plan.extractedRoot, diagnostic);
            }
            FTB::Version version;
            FTB::loadVersion(version, object);
            for (const auto& target : version.targets) {
                if (target.type == QStringLiteral("minecraft") || target.type == QStringLiteral("game")) {
                    plan.minecraftVersion = target.version;
                } else {
                    const auto loader = target.name.isEmpty() ? target.type : target.name;
                    const auto normalized = loader.toLower();
                    if (normalized == QStringLiteral("forge") || normalized == QStringLiteral("neoforge")
                        || normalized == QStringLiteral("fabric") || normalized == QStringLiteral("quilt")) {
                        plan.loaderIdentifier = loaderUID(
                            normalized == QStringLiteral("fabric") ? QStringLiteral("fabric-loader")
                                                                    : (normalized == QStringLiteral("quilt")
                                                                           ? QStringLiteral("quilt-loader")
                                                                           : normalized));
                        plan.loaderVersion = target.version;
                    }
                }
            }
            for (const auto& file : version.files) {
                const auto fileURL = absoluteProviderURL(ftbBaseURL() + QLatin1Char('/'), file.url);
                const bool blocked = fileURL.isEmpty();
                addPlanFile(plan,
                            QString::number(file.id),
                            file.name,
                            file.path,
                            fileURL,
                            !file.optional,
                            file.optional,
                            blocked,
                            file.sha1.isEmpty() ? QString() : QStringLiteral("sha1"),
                            file.sha1);
            }
            break;
        }
        case FrontendProviderInstallKind::ATLauncher: {
            const auto pack = safeATLauncherPackName(QString::fromStdString(request.packIdentifier));
            const auto url = BuildConfig.ATL_DOWNLOAD_SERVER_URL + QStringLiteral("packs/") + pack + QStringLiteral("/versions/")
                + encodePath(QString::fromStdString(request.versionIdentifier)) + QStringLiteral("/Configs.json");
            const auto response = requireResponse(url, "ATLauncher version metadata could not be loaded.");
            const auto document = parseJson(response, diagnostic);
            if (!document || !document->isObject()) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     diagnostic.toStdString(),
                                     true);
            }
            ATLauncher::PackVersion version;
            auto object = document->object();
            ATLauncher::loadVersion(version, object);
            plan.minecraftVersion = version.minecraft;
            if (!version.loader.type.isEmpty() && !version.loader.version.isEmpty()) {
                plan.loaderIdentifier = loaderUID(version.loader.type);
                plan.loaderVersion = version.loader.version;
            }
            for (const auto& library : version.libraries) {
                const auto urlValue = absoluteProviderURL(BuildConfig.ATL_DOWNLOAD_SERVER_URL, library.url);
                addPlanFile(plan,
                            library.file,
                            library.file,
                            library.file,
                            urlValue,
                            true,
                            false,
                            urlValue.isEmpty(),
                            library.md5.isEmpty() ? QString() : QStringLiteral("md5"),
                            library.md5);
            }
            for (const auto& mod : version.mods) {
                const auto urlValue = absoluteProviderURL(BuildConfig.ATL_DOWNLOAD_SERVER_URL, mod.url);
                addPlanFile(plan,
                            mod.file,
                            mod.name,
                            atLauncherTarget(mod.type, mod.file),
                            urlValue,
                            !mod.optional,
                            mod.optional,
                            urlValue.isEmpty() || mod.download == ATLauncher::DownloadType::Browser
                                || mod.download == ATLauncher::DownloadType::Unknown,
                            mod.md5.isEmpty() ? QString() : QStringLiteral("md5"),
                            mod.md5);
            }
            break;
        }
        case FrontendProviderInstallKind::TechnicZip:
        case FrontendProviderInstallKind::TechnicSolder: {
            const auto detailResponse = requireResponse(technicDetailURL(QString::fromStdString(request.packIdentifier)),
                                                         "Technic pack metadata could not be loaded.");
            const auto detailDocument = parseJson(detailResponse, diagnostic);
            if (!detailDocument || !detailDocument->isObject()) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     diagnostic.toStdString(),
                                     true);
            }
            const auto detail = detailDocument->object();
            setMinecraftFrom(detail);
            const auto directURL = jsonString(detail, { QStringLiteral("url"), QStringLiteral("archiveUrl") });
            const auto solderURL = jsonString(detail, { QStringLiteral("solder") });
            if (request.kind == FrontendProviderInstallKind::TechnicZip) {
                if (directURL.isEmpty()) {
                    throw InstallFailure(FrontendProviderInstallRecoveryKind::NetworkError,
                                         "Technic did not provide a downloadable archive URL.",
                                         true);
                }
                downloadArchive(fetch,
                                directURL,
                                staging,
                                "technic",
                                cancellation,
                                plan.extractedRoot,
                                diagnostic,
                                detail.value(QStringLiteral("md5")).toString().isEmpty() ? QString()
                                                                                          : QStringLiteral("md5"),
                                detail.value(QStringLiteral("md5")).toString());
            } else {
                if (solderURL.isEmpty()) {
                    throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                         "Technic Solder metadata is missing.",
                                         true);
                }
                auto base = solderURL;
                while (base.endsWith(QLatin1Char('/'))) {
                    base.chop(1);
                }
                const auto buildURL = base + QStringLiteral("/modpack/") + encodePath(QString::fromStdString(request.packIdentifier))
                    + QLatin1Char('/') + encodePath(QString::fromStdString(request.versionIdentifier));
                const auto buildResponse = requireResponse(buildURL, "Technic Solder build metadata could not be loaded.");
                const auto buildDocument = parseJson(buildResponse, diagnostic);
                if (!buildDocument || !buildDocument->isObject()) {
                    throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                         diagnostic.toStdString(),
                                         true);
                }
                auto buildObject = buildDocument->object();
                TechnicSolder::PackBuild build;
                TechnicSolder::loadPackBuild(build, buildObject);
                plan.minecraftVersion = build.minecraft;
                for (const auto& mod : build.mods) {
                    addPlanFile(plan,
                                mod.name,
                                mod.name,
                                QStringLiteral("mods/") + mod.name + QStringLiteral(".jar"),
                                absoluteProviderURL(base, mod.url),
                                true,
                                false,
                                mod.url.isEmpty(),
                                mod.md5.isEmpty() ? QString() : QStringLiteral("md5"),
                                mod.md5);
                }
            }
            break;
        }
        case FrontendProviderInstallKind::LegacyFTB: {
            const auto identifier = QString::fromStdString(request.packIdentifier);
            const auto separator = identifier.indexOf(QLatin1Char('|'));
            if (separator <= 0) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     "Legacy FTB pack identifier is invalid.",
                                     false);
            }
            const auto dir = identifier.left(separator);
            const auto file = identifier.mid(separator + 1);
            for (const auto& listName : { QStringLiteral("modpacks.xml"), QStringLiteral("thirdparty.xml") }) {
                const auto listResponse = requireResponse(
                    BuildConfig.LEGACY_FTB_CDN_BASE_URL + QStringLiteral("static/") + listName,
                    "Legacy FTB metadata could not be loaded.");
                for (const auto& pack : parseLegacyPacks(byteArrayFromVector(listResponse), diagnostic)) {
                    if (pack.dir == dir && pack.file == file) {
                        plan.minecraftVersion = pack.mcVersion;
                        break;
                    }
                }
                if (!plan.minecraftVersion.isEmpty()) {
                    break;
                }
            }
            if (plan.minecraftVersion.isEmpty()) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     "Legacy FTB metadata did not identify the selected pack.",
                                     false);
            }
            auto version = QString::fromStdString(request.versionIdentifier);
            version.replace(QLatin1Char('.'), QLatin1Char('_'));
            const auto archiveURL = BuildConfig.LEGACY_FTB_CDN_BASE_URL + QStringLiteral("modpacks/") + dir + QLatin1Char('/')
                + version + QLatin1Char('/') + file;
            downloadArchive(fetch, archiveURL, staging, "legacy-ftb", cancellation, plan.extractedRoot, diagnostic);
            break;
        }
        case FrontendProviderInstallKind::FTBImport:
        case FrontendProviderInstallKind::CustomArchive: {
            const auto source = request.sourcePath.lexically_normal();
            if (!source.is_absolute() || isSymlink(source)) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                     "The selected provider source is not safe.",
                                     false);
            }
            if (isDirectory(source)) {
                plan.extractedRoot = staging / "local-source";
                std::error_code error;
                std::filesystem::create_directories(plan.extractedRoot, error);
                if (error || !copyTreeContents(source, plan.extractedRoot, {}, diagnostic, cancellation)) {
                    throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                         diagnostic.toStdString(),
                                         true);
                }
            } else if (isRegularFile(source)) {
                const auto data = readBytes(source);
                if (!data) {
                    throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                         "The selected provider archive could not be read.",
                                         true);
                }
                plan.extractedRoot = stageArchive(vectorFromByteArray(*data), staging, "local", cancellation);
            } else {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                     "The selected provider source does not exist.",
                                     true);
            }
            if (request.kind == FrontendProviderInstallKind::FTBImport) {
                if (!loadFTBImportComponents(plan, plan.extractedRoot)) {
                    throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                         "The selected FTB App directory has no valid instance metadata.",
                                         false);
                }
            } else if (!loadPrismPackComponents(plan, plan.extractedRoot)) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     "The selected custom pack has no valid Prism component metadata.",
                                     false);
            }
            break;
        }
    }
    return plan;
}

FrontendProviderInstallRecoveryPrompt makeFilePrompt(
    FrontendProviderInstallRecoveryKind kind, const std::vector<InstallFilePlan>& files)
{
    FrontendProviderInstallRecoveryPrompt prompt;
    prompt.kind = kind;
    prompt.localizationKey = kind == FrontendProviderInstallRecoveryKind::OptionalFiles
        ? "providers.install.optionalFiles"
        : "providers.install.blockedFiles";
    prompt.diagnosticText = kind == FrontendProviderInstallRecoveryKind::OptionalFiles
        ? "Choose which optional provider files to install."
        : "Some provider files are unavailable and require an explicit decision.";
    prompt.retryable = true;
    for (const auto& file : files) {
        if ((kind == FrontendProviderInstallRecoveryKind::OptionalFiles && !file.optional)
            || (kind == FrontendProviderInstallRecoveryKind::BlockedFiles && !file.blocked)) {
            continue;
        }
        prompt.files.push_back({ file.id.toStdString(),
                                 file.name.toStdString(),
                                 file.targetPath.toStdString(),
                                 file.required,
                                 file.blocked,
                                 file.optional && file.selected });
    }
    return prompt;
}

FrontendProviderInstallRecoveryPrompt makeErrorPrompt(
    FrontendProviderInstallRecoveryKind kind, const std::string& diagnostic)
{
    FrontendProviderInstallRecoveryPrompt prompt;
    prompt.kind = kind;
    prompt.localizationKey = kind == FrontendProviderInstallRecoveryKind::NetworkError
        ? "providers.install.networkError"
        : (kind == FrontendProviderInstallRecoveryKind::DiskError ? "providers.install.diskError"
                                                                   : "providers.install.providerError");
    prompt.diagnosticText = diagnostic;
    prompt.retryable = true;
    return prompt;
}

void applyRecoveryDecision(InstallPlan& plan, const FrontendProviderInstallRequest& request)
{
    std::vector<InstallFilePlan*> optional;
    std::vector<InstallFilePlan*> blocked;
    for (auto& file : plan.files) {
        if (file.optional) {
            optional.push_back(&file);
        }
        if (file.blocked) {
            blocked.push_back(&file);
        }
    }
    const auto promptForPendingFiles = [&]() {
        if (!optional.empty()) {
            for (auto* file : optional) {
                file->selected = true;
            }
            throw InstallFailure(FrontendProviderInstallRecoveryKind::OptionalFiles,
                                 "Optional provider files require confirmation.",
                                 true,
                                 makeFilePrompt(FrontendProviderInstallRecoveryKind::OptionalFiles, plan.files));
        }
        if (!blocked.empty()) {
            throw InstallFailure(FrontendProviderInstallRecoveryKind::BlockedFiles,
                                 "Blocked provider files require confirmation.",
                                 true,
                                 makeFilePrompt(FrontendProviderInstallRecoveryKind::BlockedFiles, plan.files));
        }
    };
    if (!request.recoveryDecision.has_value()) {
        promptForPendingFiles();
        return;
    }

    const auto& decision = *request.recoveryDecision;
    if (decision.kind != FrontendProviderInstallRecoveryKind::OptionalFiles
        && decision.kind != FrontendProviderInstallRecoveryKind::BlockedFiles) {
        promptForPendingFiles();
        return;
    }

    const auto applyOptionalSelection = [&]() {
        const std::set<std::string> selected(
            decision.selectedFileIdentifiers.begin(), decision.selectedFileIdentifiers.end());
        for (auto* file : optional) {
            file->selected = selected.contains(file->id.toStdString());
        }
        for (const auto& identifier : selected) {
            if (std::none_of(optional.begin(), optional.end(), [&](const auto* file) {
                    return file->id.toStdString() == identifier;
                })) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     "Optional-file recovery selection did not match the manifest.",
                                     false);
            }
        }
    };

    if (decision.kind == FrontendProviderInstallRecoveryKind::OptionalFiles) {
        applyOptionalSelection();
        if (!blocked.empty()) {
            throw InstallFailure(FrontendProviderInstallRecoveryKind::BlockedFiles,
                                 "Blocked provider files require confirmation.",
                                 true,
                                 makeFilePrompt(FrontendProviderInstallRecoveryKind::BlockedFiles, plan.files));
        }
    } else if (decision.kind == FrontendProviderInstallRecoveryKind::BlockedFiles) {
        applyOptionalSelection();
        const std::set<std::string> resolved(
            decision.resolvedBlockedFileIdentifiers.begin(), decision.resolvedBlockedFileIdentifiers.end());
        for (auto* file : blocked) {
            file->selected = resolved.contains(file->id.toStdString());
            if (!file->selected) {
                continue;
            }
            if (file->url.isEmpty()) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::NetworkError,
                                     "A resolved provider file has no download URL.",
                                     true);
            }
            file->blocked = false;
        }
        for (const auto& identifier : resolved) {
            if (std::none_of(blocked.begin(), blocked.end(), [&](const auto* file) {
                    return file->id.toStdString() == identifier;
                })) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::ProviderError,
                                     "Blocked-file recovery selection did not match the manifest.",
                                     false);
            }
        }
    }
}

}  // namespace

FrontendProviderInstallResult ProductionProviderRuntime::install(
    const FrontendProviderInstallRequest& request,
    const FrontendRuntimeDependencies::ProviderInstallProgressHandler& progress,
    const FrontendRuntimeDependencies::ProviderInstallCancellationCheck& cancellation)
{
    std::lock_guard<std::mutex> operationLock(m_operationMutex);
    const std::string taskId = "provider-install." + installKindName(request.kind).toStdString();
    const std::string title = "Install Provider Pack";
    const auto report = [&](const FrontendTaskSnapshot& snapshot) {
        if (progress) {
            progress(snapshot);
        }
    };
    const auto result = [&](FrontendProviderInstallOutcome outcome,
                            std::optional<FrontendInstanceSnapshot> instance,
                            FrontendProviderInstallRollbackOutcome rollback,
                            std::string localizationKey,
                            std::string diagnosticText,
                            bool retryable,
                            std::optional<FrontendProviderInstallRecoveryPrompt> prompt = std::nullopt) {
        const auto state = outcome == FrontendProviderInstallOutcome::Succeeded
            ? FrontendTaskState::Succeeded
            : (outcome == FrontendProviderInstallOutcome::Cancelled ? FrontendTaskState::Cancelled : FrontendTaskState::Failed);
        const auto terminalOutcome = outcome == FrontendProviderInstallOutcome::Succeeded
            ? FrontendTaskTerminalOutcome::Succeeded
            : (outcome == FrontendProviderInstallOutcome::Cancelled ? FrontendTaskTerminalOutcome::Cancelled
                                                                     : FrontendTaskTerminalOutcome::Failed);
        report(progressSnapshot(taskId,
                                title,
                                state,
                                outcome == FrontendProviderInstallOutcome::Succeeded ? FrontendTaskProgressKind::Determinate
                                                                                      : FrontendTaskProgressKind::None,
                                outcome == FrontendProviderInstallOutcome::Succeeded ? 1.0 : 0.0,
                                false,
                                FrontendTaskTerminalResult{ terminalOutcome,
                                                            localizationKey,
                                                            {},
                                                            diagnosticText,
                                                            rollback == FrontendProviderInstallRollbackOutcome::Applied }));
        return FrontendProviderInstallResult{ request.kind,
                                              outcome,
                                              std::move(instance),
                                              request.packIdentifier,
                                              request.versionIdentifier,
                                              rollback,
                                              std::move(localizationKey),
                                              std::move(diagnosticText),
                                              retryable,
                                              std::move(prompt) };
    };

    if (m_shutdown) {
        return result(FrontendProviderInstallOutcome::Failed,
                      std::nullopt,
                      FrontendProviderInstallRollbackOutcome::NotRequired,
                      "providers.install.shutdown",
                      "Provider installation is shut down.",
                      false);
    }
    report(progressSnapshot(taskId, title, FrontendTaskState::Queued, FrontendTaskProgressKind::None, 0.0, true));
    if (isCancellationRequested(cancellation)) {
        return result(FrontendProviderInstallOutcome::Cancelled,
                      std::nullopt,
                      FrontendProviderInstallRollbackOutcome::NotRequired,
                      "providers.install.cancelled",
                      "Provider installation was cancelled.",
                      false);
    }
    if (request.recoveryDecision.has_value()
        && request.recoveryDecision->action == FrontendProviderInstallRecoveryAction::Cancel) {
        return result(FrontendProviderInstallOutcome::Cancelled,
                      std::nullopt,
                      FrontendProviderInstallRollbackOutcome::NotRequired,
                      "providers.install.cancelled",
                      "Provider installation recovery was cancelled.",
                      false);
    }

    std::optional<std::filesystem::path> staging;
    bool committed = false;
    const auto rollback = [&]() {
        if (!staging.has_value()) {
            return true;
        }
        std::error_code error;
        std::filesystem::remove_all(*staging, error);
        if (!error) {
            staging.reset();
            return true;
        }
        return false;
    };
    const auto cancelled = [&]() {
        const bool rolledBack = rollback();
        return result(FrontendProviderInstallOutcome::Cancelled,
                      std::nullopt,
                      rolledBack ? FrontendProviderInstallRollbackOutcome::Applied
                                 : FrontendProviderInstallRollbackOutcome::Failed,
                      "providers.install.cancelled",
                      "Provider installation was cancelled.",
                      false);
    };
    try {
        std::error_code error;
        std::filesystem::create_directories(m_stagingRoot, error);
        if (error || isSymlink(m_stagingRoot)) {
            return result(FrontendProviderInstallOutcome::Failed,
                          std::nullopt,
                          FrontendProviderInstallRollbackOutcome::NotRequired,
                          "providers.install.diskError",
                          "Provider staging root could not be prepared.",
                          true,
                          makeErrorPrompt(FrontendProviderInstallRecoveryKind::DiskError,
                                          "Provider staging root could not be prepared."));
        }
        const auto serial = std::chrono::steady_clock::now().time_since_epoch().count();
        staging = m_stagingRoot / (installKindName(request.kind).toStdString() + "-"
                                   + std::to_string(serial));
        std::filesystem::create_directory(*staging, error);
        if (error || isSymlink(*staging)) {
            const bool rolledBack = rollback();
            return result(FrontendProviderInstallOutcome::Failed,
                          std::nullopt,
                          rolledBack ? FrontendProviderInstallRollbackOutcome::Applied
                                     : FrontendProviderInstallRollbackOutcome::Failed,
                          "providers.install.diskError",
                          "Provider staging directory could not be created.",
                          true,
                          makeErrorPrompt(FrontendProviderInstallRecoveryKind::DiskError,
                                          "Provider staging directory could not be created."));
        }
        std::filesystem::create_directories(*staging / "minecraft", error);
        if (error) {
            const bool rolledBack = rollback();
            return result(FrontendProviderInstallOutcome::Failed,
                          std::nullopt,
                          rolledBack ? FrontendProviderInstallRollbackOutcome::Applied
                                     : FrontendProviderInstallRollbackOutcome::Failed,
                          "providers.install.diskError",
                          "Provider staging directory could not be prepared.",
                          true,
                          makeErrorPrompt(FrontendProviderInstallRecoveryKind::DiskError,
                                          "Provider staging directory could not be prepared."));
        }

        report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Determinate, 0.05, true));
        FetchContext fetch{ m_cacheRoot, providerForInstallKind(request.kind), m_download, cancellation, {} };
        fetch.progress = [&](std::uint64_t current, std::uint64_t total) {
            const double fraction = total == 0 ? 0.10 : std::min(0.35, 0.10 + 0.25 * static_cast<double>(current) / total);
            report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Determinate, fraction, true));
        };
        auto plan = resolveInstallPlan(fetch, request, *staging, cancellation);
        if (isCancellationRequested(cancellation)) {
            return cancelled();
        }
        report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Determinate, 0.40, true));
        applyRecoveryDecision(plan, request);

        if (!plan.extractedRoot.empty()) {
            const auto sourceRoot = plan.extractedRoot;
            if (isDirectory(sourceRoot / "minecraft")) {
                QString diagnostic;
                if (!copyTreeContents(sourceRoot / "minecraft", *staging / "minecraft", {}, diagnostic, cancellation)) {
                    throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                         diagnostic.toStdString(),
                                         true);
                }
            } else if (isDirectory(sourceRoot / "overrides")) {
                QString diagnostic;
                if (!copyTreeContents(sourceRoot / "overrides", *staging / "minecraft", {}, diagnostic, cancellation)) {
                    throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                         diagnostic.toStdString(),
                                         true);
                }
            } else {
                QString diagnostic;
                const std::set<std::string> exclusions{
                    "instance.cfg", "mmc-pack.json", "patches", "manifest.json", "modrinth.index.json", "overrides", "minecraft" };
                if (!copyTreeContents(sourceRoot, *staging / "minecraft", exclusions, diagnostic, cancellation)) {
                    throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                         diagnostic.toStdString(),
                                         true);
                }
            }
        }

        std::size_t selectedFiles = 0;
        for (const auto& file : plan.files) {
            if (file.selected && !file.blocked) {
                ++selectedFiles;
            }
        }
        std::size_t completedFiles = 0;
        for (const auto& file : plan.files) {
            if (!file.selected || file.blocked) {
                continue;
            }
            if (isCancellationRequested(cancellation)) {
                return cancelled();
            }
            if (file.url.isEmpty()) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::NetworkError,
                                     "A required provider file has no download URL.",
                                     true);
            }
            QString diagnostic;
            const auto bytes = fetch.get(file.url, diagnostic);
            if (!bytes) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::NetworkError,
                                     diagnostic.toStdString(),
                                     true);
            }
            if (!hashMatches(*bytes, file.hashAlgorithm, file.hashDigest)) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::NetworkError,
                                     "Provider file failed its integrity check.",
                                     true);
            }
            if (!writeBytes(*staging / "minecraft" / file.targetPath.toStdString(), byteArrayFromVector(*bytes))) {
                throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                     "Provider file could not be installed.",
                                     true);
            }
            ++completedFiles;
            const double fraction = selectedFiles == 0 ? 0.80 : 0.45 + 0.35 * static_cast<double>(completedFiles) / selectedFiles;
            report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Determinate, fraction, true));
        }

        QString diagnostic;
        if (!writeProviderMetadata(*staging, request, plan, diagnostic)) {
            throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                 diagnostic.toStdString(),
                                 true);
        }
        if (isCancellationRequested(cancellation)) {
            return cancelled();
        }

        const auto destination = destinationForName(m_instancesRoot, request.name);
        std::filesystem::create_directories(m_instancesRoot, error);
        if (error || isSymlink(m_instancesRoot) || !pathIsContained(m_instancesRoot, destination.path)) {
            throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                 "Provider instance destination could not be prepared.",
                                 true);
        }
        std::filesystem::rename(*staging, destination.path, error);
        if (error) {
            throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                 "Provider instance could not be committed atomically.",
                                 true);
        }
        committed = true;
        staging.reset();
        const auto snapshot = readSnapshot(m_instancesRoot, destination.path);
        if (!snapshot) {
            std::error_code cleanupError;
            std::filesystem::remove_all(destination.path, cleanupError);
            throw InstallFailure(FrontendProviderInstallRecoveryKind::DiskError,
                                 "Committed provider instance could not be read back.",
                                 true);
        }
        report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Determinate, 0.95, false));
        return result(FrontendProviderInstallOutcome::Succeeded,
                      snapshot,
                      FrontendProviderInstallRollbackOutcome::NotRequired,
                      "providers.install.completed",
                      {},
                      false);
    } catch (const InstallFailure& failure) {
        if (isCancellationRequested(cancellation)) {
            return cancelled();
        }
        const bool rolledBack = committed || rollback();
        std::string key;
        switch (failure.kind) {
            case FrontendProviderInstallRecoveryKind::OptionalFiles:
                key = "providers.install.optionalFiles";
                break;
            case FrontendProviderInstallRecoveryKind::BlockedFiles:
                key = "providers.install.blockedFiles";
                break;
            case FrontendProviderInstallRecoveryKind::NetworkError:
                key = "providers.install.networkError";
                break;
            case FrontendProviderInstallRecoveryKind::DiskError:
                key = "providers.install.diskError";
                break;
            case FrontendProviderInstallRecoveryKind::ProviderError:
                key = "providers.install.providerError";
                break;
        }
        auto prompt = failure.prompt;
        if (!prompt.has_value() && failure.retryable
            && failure.kind != FrontendProviderInstallRecoveryKind::OptionalFiles
            && failure.kind != FrontendProviderInstallRecoveryKind::BlockedFiles) {
            prompt = makeErrorPrompt(failure.kind, failure.what());
        }
        return result(FrontendProviderInstallOutcome::Failed,
                      std::nullopt,
                      rolledBack ? FrontendProviderInstallRollbackOutcome::Applied
                                 : FrontendProviderInstallRollbackOutcome::Failed,
                      std::move(key),
                      failure.what(),
                      failure.retryable,
                      std::move(prompt));
    } catch (const std::exception& exception) {
        const bool rolledBack = committed || rollback();
        return result(FrontendProviderInstallOutcome::Failed,
                      std::nullopt,
                      rolledBack ? FrontendProviderInstallRollbackOutcome::Applied
                                 : FrontendProviderInstallRollbackOutcome::Failed,
                      "providers.install.providerError",
                      exception.what(),
                      true,
                      makeErrorPrompt(FrontendProviderInstallRecoveryKind::ProviderError, exception.what()));
    }
}
