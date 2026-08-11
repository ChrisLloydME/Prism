// SPDX-License-Identifier: GPL-3.0-only

#include "ProductionInstanceAcquisitionRuntime.h"

#include "archive/ArchiveReader.h"
#include "minecraft/OneSixVersionFormat.h"
#include "minecraft/VersionFile.h"
#include "settings/INIFile.h"

#include <QCoreApplication>
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
#include <QTimer>
#include <QUrl>

#include <archive.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cctype>
#include <limits>
#include <set>
#include <stdexcept>
#include <system_error>
#include <utility>

namespace {

constexpr std::size_t kMaximumArchiveEntries = 100000;
constexpr std::size_t kMaximumArchiveBytes = 256U * 1024U * 1024U;

std::filesystem::path normalizeRoot(std::filesystem::path root)
{
    root = std::move(root).lexically_normal();
    if (root.empty() || !root.is_absolute()) {
        throw std::invalid_argument("Instance acquisition requires an absolute data root");
    }
    return root;
}

bool isSafeDisplayValue(const std::string& value, std::size_t maxLength, bool allowEmpty = false)
{
    if ((!allowEmpty && value.empty()) || value.size() > maxLength) {
        return false;
    }
    return std::all_of(value.begin(), value.end(), [](unsigned char character) {
        return character != 0 && character != '\n' && character != '\r';
    });
}

bool isSafeComponentIdentifier(const std::string& value)
{
    if (value.empty() || value.size() > 255) {
        return false;
    }
    return std::all_of(value.begin(), value.end(), [](unsigned char character) {
        return std::isalnum(character) || character == '-' || character == '_' || character == '.';
    });
}

bool isCancellationRequested(const std::function<bool()>& cancellation)
{
    return cancellation && cancellation();
}

std::string trimmedValue(const QVariant& value)
{
    return value.toString().trimmed().toStdString();
}

QByteArray byteArrayFromVector(const ProductionInstanceAcquisitionRuntime::DownloadBytes& bytes)
{
    if (bytes.empty()) {
        return {};
    }
    if (bytes.size() > static_cast<std::size_t>(std::numeric_limits<qsizetype>::max())) {
        throw std::runtime_error("Downloaded archive is too large");
    }
    return QByteArray(reinterpret_cast<const char*>(bytes.data()), static_cast<qsizetype>(bytes.size()));
}

bool writeBytes(const std::filesystem::path& path, const QByteArray& bytes)
{
    std::error_code error;
    std::filesystem::create_directories(path.parent_path(), error);
    if (error || std::filesystem::is_symlink(path.parent_path(), error) || error) {
        return false;
    }

    QSaveFile file(QString::fromStdString(path.string()));
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    if (file.write(bytes) != bytes.size()) {
        return false;
    }
    return file.commit();
}

bool writeText(const std::filesystem::path& path, const QJsonDocument& document)
{
    return writeBytes(path, document.toJson(QJsonDocument::Indented));
}

QString sanitizeInstanceName(QString value)
{
    const QString badCharacters = QStringLiteral("<>:\"|?*!\r\n");
    for (qsizetype index = 0; index < value.size(); ++index) {
        const QChar character = value.at(index);
        if (character.unicode() < 0x20 || !character.isPrint() || badCharacters.contains(character)
            || character == QLatin1Char('/') || character == QLatin1Char('\\')) {
            value[index] = QLatin1Char('-');
        }
    }
    if (value.isEmpty() || value == QLatin1String(".") || value == QLatin1String("..")) {
        value = QLatin1String("Instance");
    }
    return value;
}

struct Destination final {
    std::string identifier;
    std::filesystem::path path;
};

Destination destinationForName(const std::filesystem::path& instancesRoot, const std::string& name)
{
    const QString base = sanitizeInstanceName(QString::fromStdString(name));
    for (int suffix = 0; suffix <= 9000; ++suffix) {
        const QString candidate = suffix == 0 ? base : base + QStringLiteral("(") + QString::number(suffix) + QLatin1Char(')');
        const std::string identifier = candidate.toStdString();
        const auto path = instancesRoot / identifier;
        std::error_code error;
        if (!std::filesystem::exists(path, error)) {
            if (error) {
                throw std::runtime_error("Could not inspect the instance destination");
            }
            return { identifier, path };
        }
        if (error) {
            throw std::runtime_error("Could not inspect the instance destination");
        }
    }
    throw std::runtime_error("No safe instance destination is available");
}

std::optional<FrontendInstanceSnapshot> readSnapshot(const std::filesystem::path& instancesRoot,
                                                     const std::filesystem::path& instancePath)
{
    std::error_code error;
    if (!std::filesystem::is_directory(instancePath, error) || error || std::filesystem::is_symlink(instancePath, error)
        || error || instancePath.parent_path() != instancesRoot) {
        return std::nullopt;
    }

    const std::string identifier = instancePath.filename().string();
    if (!isSafeDisplayValue(identifier, 255)) {
        return std::nullopt;
    }
    const auto configPath = instancePath / "instance.cfg";
    if (std::filesystem::is_symlink(configPath, error) || error || !std::filesystem::is_regular_file(configPath, error)
        || error) {
        return std::nullopt;
    }

    INIFile settings;
    if (!settings.loadFile(QString::fromStdString(configPath.string()))) {
        return std::nullopt;
    }

    const std::string name = trimmedValue(settings.get("name", QStringLiteral("Unnamed Instance")));
    const std::string iconKey = trimmedValue(settings.get("iconKey", QStringLiteral("default")));
    const std::string groupId = trimmedValue(settings.get("InstanceGroupId", QString()));
    if (!isSafeDisplayValue(name, 512) || !isSafeDisplayValue(iconKey, 256)
        || !isSafeDisplayValue(groupId, 512, true)) {
        return std::nullopt;
    }
    return FrontendInstanceSnapshot{ identifier, name, iconKey, groupId };
}

FrontendTaskSnapshot progressSnapshot(const std::string& id,
                                      const std::string& title,
                                      FrontendTaskState state,
                                      FrontendTaskProgressKind progressKind,
                                      double fraction,
                                      bool cancellationAllowed,
                                      std::optional<FrontendTaskTerminalResult> terminal = std::nullopt)
{
    FrontendTaskSnapshot snapshot;
    snapshot.id = id;
    snapshot.title = title;
    snapshot.state = state;
    snapshot.progressKind = progressKind;
    snapshot.progressFraction = fraction;
    snapshot.cancellationAllowed = cancellationAllowed;
    snapshot.terminalResult = std::move(terminal);
    return snapshot;
}

FrontendVanillaCreationResult vanillaResult(FrontendVanillaCreationOutcome outcome,
                                            std::optional<FrontendInstanceSnapshot> instance,
                                            std::string localizationKey,
                                            std::string diagnosticText,
                                            bool retryable)
{
    return { outcome, std::move(instance), std::move(localizationKey), std::move(diagnosticText), retryable };
}

FrontendInstanceImportResult importResult(FrontendInstanceImportOutcome outcome,
                                          std::optional<FrontendInstanceSnapshot> instance,
                                          std::string localizationKey,
                                          std::string diagnosticText,
                                          bool retryable,
                                          bool rolledBack)
{
    return { outcome,
             std::move(instance),
             std::move(localizationKey),
             std::move(diagnosticText),
             retryable,
             rolledBack };
}

bool normalizeArchivePath(const QString& raw, QString& normalized, bool& isDirectory)
{
    if (raw.isEmpty() || raw.contains(QChar('\0')) || raw.contains(QLatin1Char('\\'))) {
        return false;
    }

    isDirectory = raw.endsWith(QLatin1Char('/'));
    QString candidate = raw;
    while (candidate.startsWith(QStringLiteral("./"))) {
        candidate.remove(0, 2);
    }
    if (candidate.isEmpty()) {
        normalized.clear();
        return true;
    }

    const QString clean = QDir::cleanPath(candidate);
    if (clean.isEmpty() || clean == QLatin1String(".")) {
        normalized.clear();
        return true;
    }
    if (clean.startsWith(QLatin1Char('/')) || clean == QLatin1String("..")
        || clean.startsWith(QStringLiteral("../")) || clean.contains(QStringLiteral("/../"))) {
        return false;
    }
    normalized = clean;
    return true;
}

struct ArchiveEntry final {
    QString path;
    QByteArray data;
};

struct ArchiveManifest final {
    std::vector<ArchiveEntry> entries;
};

std::optional<ArchiveManifest> inspectArchive(const std::filesystem::path& archivePath, std::string& diagnostic)
{
    MMCZip::ArchiveReader reader(QString::fromStdString(archivePath.string()));
    std::vector<ArchiveEntry> entries;
    std::set<QString> paths;
    std::size_t totalBytes = 0;
    bool invalid = false;

    const bool parsed = reader.parse([&](MMCZip::ArchiveReader::File* file) {
        if (entries.size() >= kMaximumArchiveEntries) {
            diagnostic = "The archive contains too many entries.";
            invalid = true;
            return false;
        }

        QString normalized;
        bool isDirectory = false;
        if (!normalizeArchivePath(file->filename(), normalized, isDirectory)) {
            diagnostic = "The archive contains an unsafe path.";
            invalid = true;
            return false;
        }
        if (!file->isFile()) {
            if (!isDirectory) {
                diagnostic = "The archive contains a link or unsupported entry.";
                invalid = true;
                return false;
            }
            return file->skip();
        }
        if (normalized.isEmpty() || !paths.insert(normalized).second) {
            diagnostic = "The archive contains duplicate or empty file paths.";
            invalid = true;
            return false;
        }

        int status = ARCHIVE_OK;
        const QByteArray data = file->readAll(&status);
        if (status != ARCHIVE_OK && status != ARCHIVE_EOF) {
            diagnostic = "The archive could not be read.";
            invalid = true;
            return false;
        }
        if (data.size() < 0 || data.size() > static_cast<qsizetype>(kMaximumArchiveBytes)
            || totalBytes > kMaximumArchiveBytes - static_cast<std::size_t>(data.size())) {
            diagnostic = "The archive is too large.";
            invalid = true;
            return false;
        }
        totalBytes += static_cast<std::size_t>(data.size());
        entries.push_back({ std::move(normalized), data });
        return true;
    });

    if (!parsed || invalid) {
        if (diagnostic.empty()) {
            diagnostic = "The archive could not be inspected.";
        }
        return std::nullopt;
    }

    std::vector<QString> prefixes;
    for (const auto& entry : entries) {
        QString prefix;
        if (entry.path == QLatin1String("instance.cfg")) {
            prefix = QString();
        } else if (entry.path.endsWith(QStringLiteral("/instance.cfg"))) {
            prefix = entry.path.left(entry.path.size() - QStringLiteral("instance.cfg").size());
        } else {
            continue;
        }
        const QString packPath = prefix + QStringLiteral("mmc-pack.json");
        const bool hasPack = std::any_of(entries.begin(), entries.end(), [&](const ArchiveEntry& candidate) {
            return candidate.path == packPath;
        });
        if (hasPack) {
            prefixes.push_back(prefix);
        }
    }
    if (prefixes.size() != 1) {
        diagnostic = "The archive must contain exactly one Prism instance root.";
        return std::nullopt;
    }

    const QString prefix = prefixes.front();
    for (auto& entry : entries) {
        if (!entry.path.startsWith(prefix)) {
            diagnostic = "The archive contains files outside the instance root.";
            return std::nullopt;
        }
        entry.path.remove(0, prefix.size());
        if (entry.path.isEmpty() || entry.path.startsWith(QLatin1Char('/'))) {
            diagnostic = "The archive contains an invalid instance root.";
            return std::nullopt;
        }
    }

    return ArchiveManifest{ std::move(entries) };
}

const ArchiveEntry* findEntry(const ArchiveManifest& manifest, const QString& path)
{
    const auto found = std::find_if(manifest.entries.begin(), manifest.entries.end(), [&](const ArchiveEntry& entry) {
        return entry.path == path;
    });
    return found == manifest.entries.end() ? nullptr : &*found;
}

bool validatePackProfile(const QByteArray& bytes, std::string& diagnostic)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(bytes, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        diagnostic = "The instance component list is not valid JSON.";
        return false;
    }
    const QJsonObject root = document.object();
    if (!root.value(QStringLiteral("formatVersion")).isDouble()
        || root.value(QStringLiteral("formatVersion")).toInt(-1) != 1
        || !root.value(QStringLiteral("components")).isArray()) {
        diagnostic = "The instance component list has an unsupported format.";
        return false;
    }

    const QJsonArray components = root.value(QStringLiteral("components")).toArray();
    bool hasMinecraft = false;
    for (const QJsonValue& value : components) {
        if (!value.isObject()) {
            diagnostic = "The instance component list contains an invalid component.";
            return false;
        }
        const QJsonObject component = value.toObject();
        const std::string identifier = component.value(QStringLiteral("uid")).toString().toStdString();
        if (!isSafeComponentIdentifier(identifier)) {
            diagnostic = "The instance component list contains an unsafe component identifier.";
            return false;
        }
        if (identifier == "net.minecraft") {
            hasMinecraft = true;
        }
    }
    if (!hasMinecraft) {
        diagnostic = "The instance component list does not contain Minecraft.";
        return false;
    }
    return true;
}

bool validatePatchFiles(const ArchiveManifest& manifest, std::string& diagnostic)
{
    const ArchiveEntry* minecraftPatch = findEntry(manifest, QStringLiteral("patches/net.minecraft.json"));
    if (!minecraftPatch) {
        diagnostic = "The archive does not contain the Minecraft component metadata.";
        return false;
    }

    for (const auto& entry : manifest.entries) {
        if (!entry.path.startsWith(QStringLiteral("patches/")) || !entry.path.endsWith(QStringLiteral(".json"))) {
            continue;
        }
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(entry.data, &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            diagnostic = "The archive contains invalid component metadata.";
            return false;
        }
        try {
            const auto patch = OneSixVersionFormat::versionFileFromJson(document, entry.path, false);
            if (!patch || !isSafeComponentIdentifier(patch->uid.toStdString())) {
                diagnostic = "The archive contains an unsafe component metadata identifier.";
                return false;
            }
        } catch (const std::exception&) {
            diagnostic = "The archive contains invalid component metadata.";
            return false;
        }
    }
    return true;
}

bool extractManifest(const ArchiveManifest& manifest, const std::filesystem::path& staging, std::string& diagnostic)
{
    for (const auto& entry : manifest.entries) {
        const auto target = staging / entry.path.toStdString();
        const auto relative = target.lexically_relative(staging);
        std::error_code error;
        if (relative.empty() || relative.is_absolute()
            || std::any_of(relative.begin(), relative.end(), [](const auto& component) {
                   return component == std::filesystem::path("..");
               })) {
            diagnostic = "The archive extraction path escaped staging.";
            return false;
        }
        std::filesystem::create_directories(target.parent_path(), error);
        if (error || std::filesystem::is_symlink(target.parent_path(), error) || error
            || !writeBytes(target, entry.data)) {
            diagnostic = "The archive could not be extracted safely.";
            return false;
        }
    }
    return true;
}

bool validateExtractedInstance(const std::filesystem::path& staging, std::string& diagnostic)
{
    INIFile settings;
    if (!settings.loadFile(QString::fromStdString((staging / "instance.cfg").string()))) {
        diagnostic = "The instance metadata could not be read.";
        return false;
    }
    QFile packFile(QString::fromStdString((staging / "mmc-pack.json").string()));
    if (!packFile.open(QIODevice::ReadOnly)) {
        diagnostic = "The instance component list could not be read.";
        return false;
    }
    if (!validatePackProfile(packFile.readAll(), diagnostic)) {
        return false;
    }

    const auto patchPath = staging / "patches/net.minecraft.json";
    QFile patchFile(QString::fromStdString(patchPath.string()));
    if (!patchFile.open(QIODevice::ReadOnly)) {
        diagnostic = "The Minecraft component metadata could not be read.";
        return false;
    }
    QJsonParseError parseError;
    const QJsonDocument patch = QJsonDocument::fromJson(patchFile.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !patch.isObject()) {
        diagnostic = "The Minecraft component metadata is not valid JSON.";
        return false;
    }
    try {
        if (!OneSixVersionFormat::versionFileFromJson(patch, QStringLiteral("patches/net.minecraft.json"), false)) {
            diagnostic = "The Minecraft component metadata is invalid.";
            return false;
        }
    } catch (const std::exception&) {
        diagnostic = "The Minecraft component metadata is invalid.";
        return false;
    }
    return true;
}

std::optional<ProductionInstanceAcquisitionRuntime::DownloadBytes> defaultDownload(
    const std::string& source,
    const ProductionInstanceAcquisitionRuntime::DownloadProgressHandler& progress,
    const ProductionInstanceAcquisitionRuntime::DownloadCancellationCheck& cancellation)
{
    static std::mutex networkMutex;
    std::lock_guard<std::mutex> networkLock(networkMutex);

    const QUrl url(QString::fromStdString(source));
    if (!url.isValid() || url.host().isEmpty()) {
        return std::nullopt;
    }

    if (!QCoreApplication::instance()) {
        return std::nullopt;
    }

    QNetworkAccessManager manager;
    QNetworkRequest request(url);
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

    if (cancelled || isCancellationRequested(cancellation)) {
        reply->deleteLater();
        return std::nullopt;
    }
    if (timedOut || reply->error() != QNetworkReply::NoError) {
        reply->deleteLater();
        return std::nullopt;
    }
    bytes.append(reply->readAll());
    const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute);
    if (status.isValid() && (status.toInt() < 200 || status.toInt() >= 300)) {
        reply->deleteLater();
        return std::nullopt;
    }
    reply->deleteLater();
    const auto size = static_cast<std::size_t>(bytes.size());
    if (size == 0 || size > kMaximumArchiveBytes) {
        return std::nullopt;
    }
    return ProductionInstanceAcquisitionRuntime::DownloadBytes(
        reinterpret_cast<const std::uint8_t*>(bytes.constData()),
        reinterpret_cast<const std::uint8_t*>(bytes.constData()) + bytes.size());
}

}  // namespace

ProductionInstanceAcquisitionRuntime::ProductionInstanceAcquisitionRuntime(
    std::filesystem::path dataRoot, DownloadHandler download)
    : m_dataRoot(normalizeRoot(std::move(dataRoot))),
      m_instancesRoot(m_dataRoot / "instances"),
      m_stagingRoot(m_instancesRoot / ".prism-native-staging"),
      m_download(download ? std::move(download) : DownloadHandler(defaultDownload))
{
    std::error_code error;
    if (std::filesystem::exists(m_dataRoot, error) && (error || std::filesystem::is_symlink(m_dataRoot, error))) {
        throw std::invalid_argument("Instance acquisition rejects a symlinked data root");
    }
    std::filesystem::create_directories(m_stagingRoot, error);
    if (error || std::filesystem::is_symlink(m_instancesRoot, error) || error
        || std::filesystem::is_symlink(m_stagingRoot, error) || error
        || !std::filesystem::is_directory(m_stagingRoot, error) || error) {
        throw std::runtime_error("Instance acquisition could not create its staging root");
    }
}

ProductionInstanceAcquisitionRuntime::~ProductionInstanceAcquisitionRuntime() noexcept
{
    shutdown();
}

std::filesystem::path ProductionInstanceAcquisitionRuntime::makeStagingDirectory(const char* operation)
{
    static std::atomic<std::uint64_t> sequence{ 0 };
    const auto now = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto serial = sequence.fetch_add(1, std::memory_order_relaxed);
    const auto directory = m_stagingRoot / (std::string(operation) + "-" + std::to_string(now) + "-" + std::to_string(serial));
    std::error_code error;
    std::filesystem::create_directory(directory, error);
    if (error || std::filesystem::is_symlink(directory, error) || error) {
        throw std::runtime_error("Instance acquisition could not create a staging directory");
    }
    return directory;
}

FrontendVanillaCreationResult ProductionInstanceAcquisitionRuntime::createVanillaInstance(
    const FrontendVanillaCreationRequest& request,
    const FrontendRuntimeDependencies::VanillaCreationProgressHandler& progress,
    const FrontendRuntimeDependencies::VanillaCreationCancellationCheck& cancellation)
{
    std::lock_guard<std::mutex> operationLock(m_operationMutex);
    constexpr const char* taskId = "creation.vanilla";
    constexpr const char* title = "Create Vanilla Instance";
    const auto report = [&](FrontendTaskSnapshot snapshot) {
        if (progress) {
            progress(snapshot);
        }
    };
    std::optional<std::filesystem::path> staging;
    const auto rollback = [&] {
        if (staging.has_value()) {
            std::error_code error;
            std::filesystem::remove_all(*staging, error);
            staging.reset();
        }
    };
    const auto reportCancelled = [&](bool rolledBack) {
        rollback();
        report(progressSnapshot(taskId,
                                title,
                                FrontendTaskState::Cancelled,
                                FrontendTaskProgressKind::None,
                                0.0,
                                false,
                                FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Cancelled,
                                                            "instances.creation.vanilla.cancelled",
                                                            {},
                                                            "Vanilla instance creation was cancelled.",
                                                            rolledBack }));
        return vanillaResult(FrontendVanillaCreationOutcome::Cancelled,
                             std::nullopt,
                             "instances.creation.vanilla.cancelled",
                             "Vanilla instance creation was cancelled.",
                             true);
    };

    report(progressSnapshot(taskId, title, FrontendTaskState::Queued, FrontendTaskProgressKind::None, 0.0, true));
    if (isCancellationRequested(cancellation)) {
        return reportCancelled(false);
    }

    // The operation mutex is already held. Keep the shutdown check adjacent to
    // the first state transition so no operation can start after shutdown.
    if (m_shutdown) {
        const std::string diagnostic = "Instance creation is shutting down.";
        report(progressSnapshot(taskId,
                                title,
                                FrontendTaskState::Failed,
                                FrontendTaskProgressKind::None,
                                0.0,
                                false,
                                FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Failed,
                                                            "instances.creation.vanilla.failed",
                                                            {},
                                                            diagnostic,
                                                            true }));
        return vanillaResult(FrontendVanillaCreationOutcome::Failed,
                             std::nullopt,
                             "instances.creation.vanilla.failed",
                             diagnostic,
                             true);
    }

    const auto failed = [&](const std::string& diagnostic, bool retryable) {
        rollback();
        report(progressSnapshot(taskId,
                                title,
                                FrontendTaskState::Failed,
                                FrontendTaskProgressKind::None,
                                0.0,
                                false,
                                FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Failed,
                                                            "instances.creation.vanilla.failed",
                                                            {},
                                                            diagnostic,
                                                            true }));
        return vanillaResult(FrontendVanillaCreationOutcome::Failed,
                             std::nullopt,
                             "instances.creation.vanilla.failed",
                             diagnostic,
                             retryable);
    };

    try {
        report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Determinate, 0.05, true));
        if (!isSafeDisplayValue(request.versionDescriptor, 256) || !isSafeDisplayValue(request.versionName, 512)
            || !isSafeDisplayValue(request.name, 512) || !isSafeDisplayValue(request.groupId, 512, true)
            || !isSafeDisplayValue(request.iconKey, 256) || (request.loaderIdentifier.has_value()
                && (!isSafeComponentIdentifier(*request.loaderIdentifier)
                    || !request.loaderVersionDescriptor.has_value()
                    || !isSafeDisplayValue(*request.loaderVersionDescriptor, 256)))) {
            return failed("Vanilla instance metadata is invalid.", false);
        }
        if (isCancellationRequested(cancellation)) {
            return reportCancelled(false);
        }

        staging = makeStagingDirectory("vanilla");
        std::error_code error;
        std::filesystem::create_directories(*staging / "minecraft" / "mods", error);
        if (error) {
            return failed("Vanilla instance staging could not be prepared.", true);
        }

        INIFile settings;
        settings.set("InstanceType", QStringLiteral("Minecraft"));
        settings.set("name", QString::fromStdString(request.name));
        settings.set("iconKey", QString::fromStdString(request.iconKey));
        settings.set("InstanceGroupId", QString::fromStdString(request.groupId));
        settings.set("totalTimePlayed", 0);
        settings.set("lastTimePlayed", 0);
        if (!settings.saveFile(QString::fromStdString((*staging / "instance.cfg").string()))) {
            return failed("Vanilla instance metadata could not be saved.", true);
        }

        QJsonObject packRoot;
        packRoot.insert(QStringLiteral("formatVersion"), 1);
        QJsonArray components;
        QJsonObject minecraftComponent;
        minecraftComponent.insert(QStringLiteral("uid"), QStringLiteral("net.minecraft"));
        minecraftComponent.insert(QStringLiteral("version"), QString::fromStdString(request.versionDescriptor));
        minecraftComponent.insert(QStringLiteral("important"), true);
        components.append(minecraftComponent);
        if (request.loaderIdentifier.has_value()) {
            QJsonObject loaderComponent;
            loaderComponent.insert(QStringLiteral("uid"), QString::fromStdString(*request.loaderIdentifier));
            loaderComponent.insert(QStringLiteral("version"), QString::fromStdString(*request.loaderVersionDescriptor));
            components.append(loaderComponent);
        }
        packRoot.insert(QStringLiteral("components"), components);
        QJsonDocument packDocument(packRoot);
        if (!writeText(*staging / "mmc-pack.json", packDocument)) {
            return failed("Vanilla component metadata could not be saved.", true);
        }

        auto patch = std::make_shared<VersionFile>();
        patch->name = QStringLiteral("Minecraft");
        patch->uid = QStringLiteral("net.minecraft");
        patch->version = QString::fromStdString(request.versionDescriptor);
        patch->minecraftVersion = QString::fromStdString(request.versionDescriptor);
        patch->type = QStringLiteral("release");
        if (!writeText(*staging / "patches/net.minecraft.json", OneSixVersionFormat::versionFileToJson(patch))) {
            return failed("Vanilla Minecraft metadata could not be saved.", true);
        }
        report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Determinate, 0.70, true));
        if (isCancellationRequested(cancellation)) {
            return reportCancelled(true);
        }

        Destination destination = destinationForName(m_instancesRoot, request.name);
        bool committed = false;
        for (int attempt = 0; attempt <= 9000 && !committed; ++attempt) {
            std::error_code renameError;
            std::filesystem::rename(*staging, destination.path, renameError);
            if (!renameError) {
                committed = true;
                break;
            }
            if (renameError == std::errc::file_exists) {
                destination = destinationForName(m_instancesRoot, request.name);
                continue;
            }
            return failed("Vanilla instance could not be committed atomically.", true);
        }
        if (!committed) {
            return failed("No safe destination was available for the vanilla instance.", true);
        }
        staging.reset();
        const auto snapshot = readSnapshot(m_instancesRoot, destination.path);
        if (!snapshot) {
            std::error_code cleanupError;
            std::filesystem::remove_all(destination.path, cleanupError);
            return failed("The committed vanilla instance could not be read back.", true);
        }
        report(progressSnapshot(taskId,
                                title,
                                FrontendTaskState::Succeeded,
                                FrontendTaskProgressKind::Determinate,
                                1.0,
                                false,
                                FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Succeeded,
                                                            "instances.creation.vanilla.created",
                                                            {},
                                                            "Vanilla instance creation completed.",
                                                            false }));
        return vanillaResult(FrontendVanillaCreationOutcome::Succeeded,
                             snapshot,
                             "instances.creation.vanilla.created",
                             "Vanilla instance creation completed.",
                             false);
    } catch (const std::exception& exception) {
        return failed(exception.what(), true);
    } catch (...) {
        return failed("Vanilla instance creation failed unexpectedly.", true);
    }
}

FrontendInstanceImportResult ProductionInstanceAcquisitionRuntime::importInstance(
    const FrontendInstanceImportRequest& request,
    const FrontendRuntimeDependencies::InstanceImportProgressHandler& progress,
    const FrontendRuntimeDependencies::InstanceImportCancellationCheck& cancellation)
{
    std::lock_guard<std::mutex> operationLock(m_operationMutex);
    constexpr const char* taskId = "instance.import";
    constexpr const char* title = "Import Instance";
    const auto report = [&](FrontendTaskSnapshot snapshot) {
        if (progress) {
            progress(snapshot);
        }
    };
    std::optional<std::filesystem::path> staging;
    const auto rollback = [&] {
        if (staging.has_value()) {
            std::error_code error;
            std::filesystem::remove_all(*staging, error);
            staging.reset();
        }
    };
    const auto reportCancelled = [&](bool rolledBack) {
        rollback();
        report(progressSnapshot(taskId,
                                title,
                                FrontendTaskState::Cancelled,
                                FrontendTaskProgressKind::None,
                                0.0,
                                false,
                                FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Cancelled,
                                                            "instances.import.cancelled",
                                                            {},
                                                            "Instance import was cancelled.",
                                                            rolledBack }));
        return importResult(FrontendInstanceImportOutcome::Cancelled,
                            std::nullopt,
                            "instances.import.cancelled",
                            "Instance import was cancelled.",
                            true,
                            rolledBack);
    };
    report(progressSnapshot(taskId, title, FrontendTaskState::Queued, FrontendTaskProgressKind::None, 0.0, true));
    if (isCancellationRequested(cancellation)) {
        return reportCancelled(false);
    }

    if (m_shutdown) {
        const std::string diagnostic = "Instance import is shutting down.";
        report(progressSnapshot(taskId,
                                title,
                                FrontendTaskState::Failed,
                                FrontendTaskProgressKind::None,
                                0.0,
                                false,
                                FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Failed,
                                                            "instances.import.failed",
                                                            {},
                                                            diagnostic,
                                                            true }));
        return importResult(FrontendInstanceImportOutcome::Failed,
                            std::nullopt,
                            "instances.import.failed",
                            diagnostic,
                            true,
                            false);
    }

    const auto failed = [&](const std::string& diagnostic, bool retryable, bool rolledBack) {
        rollback();
        report(progressSnapshot(taskId,
                                title,
                                FrontendTaskState::Failed,
                                FrontendTaskProgressKind::None,
                                0.0,
                                false,
                                FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Failed,
                                                            "instances.import.failed",
                                                            {},
                                                            diagnostic,
                                                            rolledBack }));
        return importResult(FrontendInstanceImportOutcome::Failed,
                            std::nullopt,
                            "instances.import.failed",
                            diagnostic,
                            retryable,
                            rolledBack);
    };

    try {
        report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Determinate, 0.05, true));
        if (!isSafeDisplayValue(request.name, 512) || !isSafeDisplayValue(request.groupId, 512, true)
            || !isSafeDisplayValue(request.iconKey, 256)) {
            return failed("Imported instance metadata is invalid.", false, false);
        }
        if (request.sourceKind == FrontendInstanceImportSourceKind::LocalFile) {
            const std::filesystem::path source(request.source);
            std::error_code error;
            if (!source.is_absolute() || std::filesystem::is_symlink(source, error) || error
                || !std::filesystem::is_regular_file(source, error) || error) {
                return failed("The selected instance archive is not a regular local file.", false, false);
            }
        }
        if (isCancellationRequested(cancellation)) {
            return reportCancelled(false);
        }

        staging = makeStagingDirectory("import");
        std::filesystem::path archivePath;
        if (request.sourceKind == FrontendInstanceImportSourceKind::LocalFile) {
            archivePath = std::filesystem::path(request.source);
        } else {
            if (!m_download) {
                return failed("The instance download adapter is unavailable.", true, true);
            }
            const auto downloaded = m_download(
                request.source,
                [&](std::uint64_t received, std::uint64_t total) {
                    const double downloadFraction = total == 0
                        ? 0.15
                        : std::min(0.30, 0.10 + (0.30 * static_cast<double>(received) / static_cast<double>(total)));
                    report(progressSnapshot(taskId,
                                            title,
                                            FrontendTaskState::Running,
                                            FrontendTaskProgressKind::Determinate,
                                            downloadFraction,
                                            true));
                },
                cancellation);
            if (isCancellationRequested(cancellation)) {
                return reportCancelled(true);
            }
            if (!downloaded.has_value() || downloaded->empty()) {
                return failed("The instance archive could not be downloaded.", true, true);
            }
            const QByteArray archiveBytes = byteArrayFromVector(*downloaded);
            archivePath = *staging / ".download.archive";
            if (!writeBytes(archivePath, archiveBytes)) {
                return failed("The downloaded instance archive could not be staged.", true, true);
            }
        }

        std::string diagnostic;
        const auto manifest = inspectArchive(archivePath, diagnostic);
        if (!manifest) {
            return failed(diagnostic, false, true);
        }
        const auto pack = findEntry(*manifest, QStringLiteral("mmc-pack.json"));
        if (!pack || !validatePackProfile(pack->data, diagnostic) || !validatePatchFiles(*manifest, diagnostic)) {
            return failed(diagnostic.empty() ? "The archive is not a valid Prism instance." : diagnostic, false, true);
        }
        report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Determinate, 0.50, true));
        if (isCancellationRequested(cancellation)) {
            return reportCancelled(true);
        }

        if (!extractManifest(*manifest, *staging, diagnostic)) {
            return failed(diagnostic, false, true);
        }
        std::error_code removeError;
        std::filesystem::remove(*staging / ".download.archive", removeError);
        if (removeError && request.sourceKind == FrontendInstanceImportSourceKind::RemoteURL) {
            return failed("The staged download could not be removed before commit.", true, true);
        }
        report(progressSnapshot(taskId, title, FrontendTaskState::Running, FrontendTaskProgressKind::Determinate, 0.72, true));

        if (!validateExtractedInstance(*staging, diagnostic)) {
            return failed(diagnostic, false, true);
        }
        INIFile settings;
        if (!settings.loadFile(QString::fromStdString((*staging / "instance.cfg").string()))) {
            return failed("The imported instance metadata could not be loaded.", false, true);
        }
        settings.set("InstanceType", settings.get("InstanceType", QStringLiteral("Minecraft")));
        settings.set("name", QString::fromStdString(request.name));
        settings.set("iconKey", QString::fromStdString(request.iconKey));
        settings.set("InstanceGroupId", QString::fromStdString(request.groupId));
        settings.set("totalTimePlayed", 0);
        settings.set("lastTimePlayed", 0);
        if (!settings.saveFile(QString::fromStdString((*staging / "instance.cfg").string()))) {
            return failed("The imported instance metadata could not be saved.", true, true);
        }
        if (isCancellationRequested(cancellation)) {
            return reportCancelled(true);
        }

        Destination destination = destinationForName(m_instancesRoot, request.name);
        bool committed = false;
        for (int attempt = 0; attempt <= 9000 && !committed; ++attempt) {
            std::error_code renameError;
            std::filesystem::rename(*staging, destination.path, renameError);
            if (!renameError) {
                committed = true;
                break;
            }
            if (renameError == std::errc::file_exists) {
                destination = destinationForName(m_instancesRoot, request.name);
                continue;
            }
            return failed("Imported instance could not be committed atomically.", true, true);
        }
        if (!committed) {
            return failed("No safe destination was available for the imported instance.", true, true);
        }
        staging.reset();
        const auto snapshot = readSnapshot(m_instancesRoot, destination.path);
        if (!snapshot) {
            std::error_code cleanupError;
            std::filesystem::remove_all(destination.path, cleanupError);
            return failed("The committed imported instance could not be read back.", true, true);
        }
        report(progressSnapshot(taskId,
                                title,
                                FrontendTaskState::Succeeded,
                                FrontendTaskProgressKind::Determinate,
                                1.0,
                                false,
                                FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Succeeded,
                                                            "instances.import.completed",
                                                            {},
                                                            "Instance import completed.",
                                                            false }));
        return importResult(FrontendInstanceImportOutcome::Succeeded,
                            snapshot,
                            "instances.import.completed",
                            "Instance import completed.",
                            false,
                            false);
    } catch (const std::exception& exception) {
        return failed(exception.what(), true, staging.has_value());
    } catch (...) {
        return failed("Instance import failed unexpectedly.", true, staging.has_value());
    }
}

void ProductionInstanceAcquisitionRuntime::shutdown() noexcept
{
    std::lock_guard<std::mutex> lock(m_operationMutex);
    if (m_shutdown) {
        return;
    }
    m_shutdown = true;
}

std::shared_ptr<ProductionInstanceAcquisitionRuntime> makeProductionInstanceAcquisitionRuntime(
    std::filesystem::path dataRoot, ProductionInstanceAcquisitionRuntime::DownloadHandler download)
{
    return std::make_shared<ProductionInstanceAcquisitionRuntime>(std::move(dataRoot), std::move(download));
}
