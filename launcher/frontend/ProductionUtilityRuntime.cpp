// SPDX-License-Identifier: GPL-3.0-only

#include "ProductionUtilityRuntime.h"

#include "settings/INIFile.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QVersionNumber>
#include <QXmlStreamReader>

#include <zlib.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cctype>
#include <filesystem>
#include <limits>
#include <set>
#include <stdexcept>
#include <string_view>
#include <system_error>
#include <utility>

namespace {

constexpr std::size_t kMaximumNetworkBytes = 16U * 1024U * 1024U;
constexpr std::size_t kMaximumSkinBytes = 8U * 1024U * 1024U;
constexpr std::size_t kMaximumNewsEntries = 100;
constexpr auto kNewsFeedURL = "https://prismlauncher.org/feed/feed.xml";
constexpr auto kUpdateFeedURL = "https://prismlauncher.org/feed/appcast.xml";

using Bytes = ProductionUtilityRuntime::Bytes;
using CancellationCheck = ProductionUtilityRuntime::CancellationCheck;

bool cancelled(const CancellationCheck& check)
{
    return check && check();
}

std::filesystem::path normalizeRoot(std::filesystem::path root)
{
    root = std::move(root).lexically_normal();
    if (root.empty() || !root.is_absolute()) {
        throw std::invalid_argument("Utility runtime requires an absolute data root");
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

bool pathIsContained(const std::filesystem::path& root, const std::filesystem::path& candidate)
{
    const auto normalizedRoot = root.lexically_normal();
    const auto normalizedCandidate = candidate.lexically_normal();
    const auto relative = normalizedCandidate.lexically_relative(normalizedRoot);
    if (relative.empty() || relative.is_absolute() || relative.has_root_path()
        || std::any_of(relative.begin(), relative.end(), [](const auto& component) {
               return component == std::filesystem::path("..");
           })) {
        return false;
    }

    std::filesystem::path current = normalizedRoot;
    if (isSymlink(current)) {
        return false;
    }
    for (const auto& component : relative) {
        current /= component;
        std::error_code error;
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
    }
    return true;
}

bool safeText(const std::string& value, std::size_t maximum, bool allowEmpty = false)
{
    if ((!allowEmpty && value.empty()) || value.size() > maximum) {
        return false;
    }
    return std::all_of(value.begin(), value.end(), [](unsigned char character) {
        return character != 0 && character != '\r' && character != '\n' && character != 0x7f;
    });
}

bool safeComponent(const std::string& value, std::size_t maximum = 128)
{
    return safeText(value, maximum) && value != "." && value != ".."
        && std::all_of(value.begin(), value.end(), [](unsigned char character) {
               return character != '/' && character != '\\' && character != ':';
           });
}

bool safeHTTPSURL(const std::string& value)
{
    const QUrl url(QString::fromStdString(value));
    return url.isValid() && url.scheme().compare(QStringLiteral("https"), Qt::CaseInsensitive) == 0
        && !url.host().isEmpty() && url.userInfo().isEmpty();
}

bool safeWebURL(const std::string& value)
{
    const QUrl url(QString::fromStdString(value));
    const auto scheme = url.scheme().toLower();
    return url.isValid() && (scheme == QStringLiteral("http") || scheme == QStringLiteral("https"))
        && !url.host().isEmpty() && url.userInfo().isEmpty();
}

QByteArray byteArray(const Bytes& bytes)
{
    if (bytes.empty() || bytes.size() > static_cast<std::size_t>(std::numeric_limits<qsizetype>::max())) {
        return {};
    }
    return QByteArray(reinterpret_cast<const char*>(bytes.data()), static_cast<qsizetype>(bytes.size()));
}

Bytes byteVector(const QByteArray& bytes)
{
    if (bytes.isEmpty()) {
        return {};
    }
    return { reinterpret_cast<const std::uint8_t*>(bytes.constData()),
             reinterpret_cast<const std::uint8_t*>(bytes.constData()) + bytes.size() };
}

std::optional<Bytes> readBytes(const std::filesystem::path& path, std::size_t maximum = kMaximumSkinBytes)
{
    if (!isRegularFile(path)) {
        return std::nullopt;
    }
    QFile file(QString::fromStdString(path.string()));
    if (!file.open(QIODevice::ReadOnly) || file.size() <= 0 || static_cast<std::uint64_t>(file.size()) > maximum) {
        return std::nullopt;
    }
    return byteVector(file.readAll());
}

bool writeBytes(const std::filesystem::path& root, const std::filesystem::path& path, const QByteArray& contents)
{
    if (!pathIsContained(root, path) || isSymlink(path)) {
        return false;
    }
    std::error_code error;
    std::filesystem::create_directories(path.parent_path(), error);
    if (error || isSymlink(path.parent_path())) {
        return false;
    }
    QSaveFile file(QString::fromStdString(path.string()));
    if (!file.open(QIODevice::WriteOnly) || file.write(contents) != contents.size()) {
        file.cancelWriting();
        return false;
    }
    return file.commit();
}

std::uint32_t pngInteger(const Bytes& bytes, std::size_t offset)
{
    return (static_cast<std::uint32_t>(bytes[offset]) << 24U)
        | (static_cast<std::uint32_t>(bytes[offset + 1]) << 16U)
        | (static_cast<std::uint32_t>(bytes[offset + 2]) << 8U)
        | static_cast<std::uint32_t>(bytes[offset + 3]);
}

bool validSkinPNG(const Bytes& bytes)
{
    constexpr std::array<std::uint8_t, 8> signature{ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a };
    if (bytes.size() < 57 || bytes.size() > kMaximumSkinBytes
        || !std::equal(signature.begin(), signature.end(), bytes.begin())) {
        return false;
    }

    bool sawHeader = false;
    bool sawImageData = false;
    std::size_t offset = signature.size();
    while (offset <= bytes.size() - 12) {
        const auto length = static_cast<std::size_t>(pngInteger(bytes, offset));
        if (length > bytes.size() - offset - 12) {
            return false;
        }
        const auto* typeBytes = bytes.data() + offset + 4;
        const auto type = std::string_view(reinterpret_cast<const char*>(typeBytes), 4);
        const auto* data = bytes.data() + offset + 8;
        const auto expectedCRC = pngInteger(bytes, offset + 8 + length);
        auto actualCRC = crc32(0L, Z_NULL, 0);
        actualCRC = crc32(actualCRC, reinterpret_cast<const Bytef*>(typeBytes), 4);
        actualCRC = crc32(actualCRC, reinterpret_cast<const Bytef*>(data), static_cast<uInt>(length));
        if (expectedCRC != static_cast<std::uint32_t>(actualCRC)) {
            return false;
        }

        if (!sawHeader) {
            if (type != "IHDR" || length != 13) {
                return false;
            }
            const auto width = pngInteger(bytes, offset + 8);
            const auto height = pngInteger(bytes, offset + 12);
            const auto bitDepth = data[8];
            const auto colorType = data[9];
            const bool validDepth = (colorType == 0 && (bitDepth == 1 || bitDepth == 2 || bitDepth == 4
                                                           || bitDepth == 8 || bitDepth == 16))
                || (colorType == 2 && (bitDepth == 8 || bitDepth == 16))
                || (colorType == 3 && (bitDepth == 1 || bitDepth == 2 || bitDepth == 4 || bitDepth == 8))
                || ((colorType == 4 || colorType == 6) && (bitDepth == 8 || bitDepth == 16));
            if (width != 64 || (height != 32 && height != 64) || !validDepth
                || data[10] != 0 || data[11] != 0 || data[12] > 1) {
                return false;
            }
            sawHeader = true;
        } else if (type == "IHDR") {
            return false;
        } else if (type == "IDAT") {
            sawImageData = sawImageData || length > 0;
        } else if (type == "IEND") {
            return length == 0 && sawImageData && offset + 12 == bytes.size();
        } else if (type[0] >= 'A' && type[0] <= 'Z' && type != "PLTE") {
            return false;
        }
        offset += 12 + length;
    }
    return false;
}

struct NetworkReply final {
    bool transportSucceeded = false;
    bool cancelled = false;
    int statusCode = 0;
    QByteArray body;
};

NetworkReply finishReply(QNetworkReply* reply, const CancellationCheck& cancellation)
{
    QEventLoop loop;
    bool exceededSizeLimit = false;
    QTimer deadline;
    deadline.setSingleShot(true);
    deadline.setInterval(60000);
    QTimer cancellationTimer;
    cancellationTimer.setInterval(25);
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    QObject::connect(reply, &QNetworkReply::downloadProgress, &loop, [reply, &exceededSizeLimit](qint64 received) {
        if (received > static_cast<qint64>(kMaximumNetworkBytes)) {
            exceededSizeLimit = true;
            reply->abort();
        }
    });
    QObject::connect(reply, &QIODevice::readyRead, &loop, [reply, &exceededSizeLimit] {
        if (reply->bytesAvailable() > static_cast<qint64>(kMaximumNetworkBytes)) {
            exceededSizeLimit = true;
            reply->abort();
        }
    });
    QObject::connect(&deadline, &QTimer::timeout, reply, &QNetworkReply::abort);
    QObject::connect(&cancellationTimer, &QTimer::timeout, reply, [reply, cancellation] {
        if (cancelled(cancellation)) {
            reply->abort();
        }
    });
    deadline.start();
    cancellationTimer.start();
    loop.exec();
    cancellationTimer.stop();

    NetworkReply result;
    result.cancelled = cancelled(cancellation);
    result.statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (!exceededSizeLimit) {
        result.body = reply->readAll();
    }
    result.transportSucceeded = !result.cancelled && !exceededSizeLimit && reply->error() == QNetworkReply::NoError
        && result.statusCode >= 200 && result.statusCode < 300
        && result.body.size() <= static_cast<qsizetype>(kMaximumNetworkBytes);
    reply->deleteLater();
    return result;
}

std::optional<Bytes> defaultDownload(const std::string& source, const CancellationCheck& cancellation)
{
    if (!safeWebURL(source) || cancelled(cancellation)) {
        return std::nullopt;
    }
    QNetworkAccessManager manager;
    QNetworkRequest request(QUrl(QString::fromStdString(source)));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("PrismNative/12"));
    const auto result = finishReply(manager.get(request), cancellation);
    if (!result.transportSucceeded || result.body.isEmpty()) {
        return std::nullopt;
    }
    return byteVector(result.body);
}

std::optional<FrontendNewsEntry> parseNewsEntry(QXmlStreamReader& reader)
{
    QString identifier;
    QString title;
    QString link;
    QString content;
    QString published;
    while (reader.readNextStartElement()) {
        const auto name = reader.name().toString().toLower();
        if (name == QStringLiteral("id")) {
            identifier = reader.readElementText(QXmlStreamReader::IncludeChildElements).trimmed();
        } else if (name == QStringLiteral("title")) {
            title = reader.readElementText(QXmlStreamReader::IncludeChildElements).trimmed();
        } else if (name == QStringLiteral("content") || name == QStringLiteral("summary")
                   || name == QStringLiteral("description")) {
            const auto value = reader.readElementText(QXmlStreamReader::IncludeChildElements).trimmed();
            if (!value.isEmpty()) {
                content = value;
            }
        } else if (name == QStringLiteral("published") || name == QStringLiteral("updated")
                   || name == QStringLiteral("pubdate")) {
            const auto value = reader.readElementText(QXmlStreamReader::IncludeChildElements).trimmed();
            if (published.isEmpty()) {
                published = value;
            }
        } else if (name == QStringLiteral("link")) {
            const auto href = reader.attributes().value(QStringLiteral("href")).toString().trimmed();
            const auto text = reader.readElementText(QXmlStreamReader::IncludeChildElements).trimmed();
            if (link.isEmpty()) {
                link = href.isEmpty() ? text : href;
            }
        } else {
            reader.skipCurrentElement();
        }
    }
    if (link.isEmpty() && safeHTTPSURL(identifier.toStdString())) {
        link = identifier;
    }
    if (identifier.isEmpty()) {
        identifier = link;
    }
    if (identifier.isEmpty() || title.isEmpty() || content.isEmpty() || !safeHTTPSURL(link.toStdString())) {
        return std::nullopt;
    }
    return FrontendNewsEntry{ identifier.toStdString(), title.toStdString(), link.toStdString(),
                              content.toStdString(), published.toStdString() };
}

std::optional<std::vector<FrontendNewsEntry>> parseNews(const Bytes& bytes, std::string& diagnostic)
{
    QXmlStreamReader reader(byteArray(bytes));
    std::vector<FrontendNewsEntry> entries;
    std::set<std::string> identifiers;
    while (!reader.atEnd()) {
        reader.readNext();
        if (!reader.isStartElement()) {
            continue;
        }
        const auto name = reader.name().toString().toLower();
        if (name != QStringLiteral("entry") && name != QStringLiteral("item")) {
            continue;
        }
        auto entry = parseNewsEntry(reader);
        if (entry.has_value() && identifiers.insert(entry->id).second) {
            entries.push_back(std::move(*entry));
            if (entries.size() == kMaximumNewsEntries) {
                break;
            }
        }
    }
    if (reader.hasError()) {
        diagnostic = "The Prism news feed is not valid XML: " + reader.errorString().toStdString();
        return std::nullopt;
    }
    return entries;
}

struct ParsedUpdate final {
    std::string version;
    std::string releaseNotes;
    std::string downloadURL;
};

QString attributeValue(const QXmlStreamAttributes& attributes, const QString& localName)
{
    for (const auto& attribute : attributes) {
        if (attribute.name().compare(localName, Qt::CaseInsensitive) == 0
            || attribute.qualifiedName().endsWith(QStringLiteral(":") + localName, Qt::CaseInsensitive)) {
            return attribute.value().toString().trimmed();
        }
    }
    return {};
}

std::optional<ParsedUpdate> parseUpdateItem(QXmlStreamReader& reader)
{
    QString version;
    QString notes;
    QString title;
    QString downloadURL;
    while (reader.readNextStartElement()) {
        const auto name = reader.name().toString().toLower();
        if (name == QStringLiteral("title")) {
            title = reader.readElementText(QXmlStreamReader::IncludeChildElements).trimmed();
        } else if (name == QStringLiteral("description") || name == QStringLiteral("releasenoteslink")) {
            const auto value = reader.readElementText(QXmlStreamReader::IncludeChildElements).trimmed();
            if (!value.isEmpty()) {
                notes = value;
            }
        } else if (name == QStringLiteral("enclosure")) {
            const auto attributes = reader.attributes();
            version = attributeValue(attributes, QStringLiteral("shortVersionString"));
            if (version.isEmpty()) {
                version = attributeValue(attributes, QStringLiteral("version"));
            }
            downloadURL = attributeValue(attributes, QStringLiteral("url"));
            reader.skipCurrentElement();
        } else {
            reader.skipCurrentElement();
        }
    }
    if (notes.isEmpty()) {
        notes = title;
    }
    if (version.isEmpty() || notes.isEmpty() || !safeHTTPSURL(downloadURL.toStdString())) {
        return std::nullopt;
    }
    return ParsedUpdate{ version.toStdString(), notes.toStdString(), downloadURL.toStdString() };
}

std::optional<std::vector<ParsedUpdate>> parseUpdates(const Bytes& bytes, std::string& diagnostic)
{
    QXmlStreamReader reader(byteArray(bytes));
    std::vector<ParsedUpdate> updates;
    while (!reader.atEnd()) {
        reader.readNext();
        if (reader.isStartElement() && reader.name().compare(QStringLiteral("item"), Qt::CaseInsensitive) == 0) {
            if (auto update = parseUpdateItem(reader); update.has_value()) {
                updates.push_back(std::move(*update));
            }
        }
    }
    if (reader.hasError()) {
        diagnostic = "The Prism update feed is not valid XML: " + reader.errorString().toStdString();
        return std::nullopt;
    }
    return updates;
}

int compareVersions(const std::string& lhs, const std::string& rhs)
{
    const auto left = QVersionNumber::fromString(QString::fromStdString(lhs));
    const auto right = QVersionNumber::fromString(QString::fromStdString(rhs));
    if (!left.isNull() && !right.isNull()) {
        return QVersionNumber::compare(left, right);
    }
    return QString::fromStdString(lhs).compare(QString::fromStdString(rhs), Qt::CaseInsensitive);
}

std::string skippedVersion(const std::filesystem::path& path)
{
    const auto data = readBytes(path, 64U * 1024U);
    if (!data.has_value()) {
        return {};
    }
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(byteArray(*data), &error);
    return error.error == QJsonParseError::NoError && document.isObject()
        ? document.object().value(QStringLiteral("skippedVersion")).toString().toStdString()
        : std::string();
}

bool persistSkippedVersion(
    const std::filesystem::path& root, const std::filesystem::path& path, const std::string& version)
{
    QJsonObject object;
    object.insert(QStringLiteral("skippedVersion"), QString::fromStdString(version));
    return writeBytes(root, path, QJsonDocument(object).toJson(QJsonDocument::Indented));
}

QString shellQuote(const std::string& value)
{
    QString escaped = QString::fromStdString(value);
    escaped.replace(QLatin1Char('\''), QStringLiteral("'\\''"));
    return QLatin1Char('\'') + escaped + QLatin1Char('\'');
}

std::string sanitizedShortcutName(const std::string& value)
{
    QString name = QString::fromStdString(value).trimmed();
    for (const QChar character : { QLatin1Char('/'), QLatin1Char('\\'), QLatin1Char(':') }) {
        name.replace(character, QLatin1Char('-'));
    }
    while (name.startsWith(QLatin1Char('.'))) {
        name.remove(0, 1);
    }
    return name.left(128).trimmed().toStdString();
}

std::optional<std::filesystem::path> defaultDestination(FrontendShortcutDestination destination)
{
    QStandardPaths::StandardLocation location;
    switch (destination) {
        case FrontendShortcutDestination::Desktop:
            location = QStandardPaths::DesktopLocation;
            break;
        case FrontendShortcutDestination::Applications:
            location = QStandardPaths::ApplicationsLocation;
            break;
        case FrontendShortcutDestination::Other:
            return std::nullopt;
    }
    const auto value = QStandardPaths::writableLocation(location);
    return value.isEmpty() ? std::nullopt : std::optional<std::filesystem::path>(value.toStdString());
}

std::optional<std::filesystem::path> defaultShortcutWriter(
    const ProductionUtilityRuntime::ShortcutDescriptor& descriptor)
{
    if (descriptor.destinationPath.empty() || !descriptor.destinationPath.is_absolute()
        || descriptor.launcherExecutablePath.empty() || !descriptor.launcherExecutablePath.is_absolute()
        || !isRegularFile(descriptor.launcherExecutablePath)) {
        return std::nullopt;
    }
    auto finalPath = descriptor.destinationPath;
    if (finalPath.extension() != ".app") {
        finalPath += ".app";
    }
    if (std::filesystem::exists(finalPath) || isSymlink(finalPath.parent_path())) {
        return std::nullopt;
    }

    const auto stage = finalPath.parent_path()
        / ("." + finalPath.filename().string() + ".prism-stage-"
           + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    std::error_code error;
    const auto contents = stage / "Contents";
    const auto resources = contents / "Resources";
    const auto executableRoot = contents / "MacOS";
    std::filesystem::create_directories(resources, error);
    if (!error) {
        std::filesystem::create_directories(executableRoot, error);
    }
    const auto rollback = [&] {
        std::error_code rollbackError;
        std::filesystem::remove_all(stage, rollbackError);
    };
    if (error || isSymlink(stage)) {
        rollback();
        return std::nullopt;
    }

    QString command = QStringLiteral("#!/bin/sh\nexec ") + shellQuote(descriptor.launcherExecutablePath.string());
    for (const auto& argument : descriptor.arguments) {
        command += QLatin1Char(' ') + shellQuote(argument);
    }
    command += QLatin1Char('\n');
    const auto commandPath = executableRoot / "Run.command";
    if (!writeBytes(stage, commandPath, command.toUtf8())) {
        rollback();
        return std::nullopt;
    }
    QFile commandFile(QString::fromStdString(commandPath.string()));
    if (!commandFile.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner
                                    | QFileDevice::ReadGroup | QFileDevice::ExeGroup | QFileDevice::ReadOther
                                    | QFileDevice::ExeOther)) {
        rollback();
        return std::nullopt;
    }

    bool hasIcon = false;
    if (!descriptor.launcherIconPath.empty() && isRegularFile(descriptor.launcherIconPath)) {
        const auto iconBytes = readBytes(descriptor.launcherIconPath, kMaximumNetworkBytes);
        hasIcon = iconBytes.has_value() && writeBytes(stage, resources / "Prism.icns", byteArray(*iconBytes));
    }
    const auto escapedName = QString::fromStdString(descriptor.name).toHtmlEscaped();
    QString plist = QStringLiteral(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
        "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        "<plist version=\"1.0\"><dict>\n"
        "<key>CFBundleExecutable</key><string>Run.command</string>\n"
        "<key>CFBundleName</key><string>%1</string>\n"
        "<key>CFBundlePackageType</key><string>APPL</string>\n"
        "<key>CFBundleShortVersionString</key><string>1.0</string>\n"
        "<key>CFBundleVersion</key><string>1.0</string>\n")
                        .arg(escapedName);
    if (hasIcon) {
        plist += QStringLiteral("<key>CFBundleIconFile</key><string>Prism.icns</string>\n");
    }
    plist += QStringLiteral("</dict></plist>\n");
    if (!writeBytes(stage, contents / "Info.plist", plist.toUtf8())) {
        rollback();
        return std::nullopt;
    }

    std::filesystem::rename(stage, finalPath, error);
    if (error) {
        rollback();
        return std::nullopt;
    }
    return finalPath;
}

struct SkinIndexEntry final {
    std::string name;
    FrontendSkinModel model = FrontendSkinModel::Classic;
    std::string capeIdentifier;
    std::string remoteURL;
};

std::vector<SkinIndexEntry> readSkinIndex(const std::filesystem::path& skinRoot)
{
    std::vector<SkinIndexEntry> entries;
    const auto bytes = readBytes(skinRoot / "index.json", 1024U * 1024U);
    if (!bytes.has_value()) {
        return entries;
    }
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(byteArray(*bytes), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        return entries;
    }
    std::set<std::string> names;
    for (const auto& value : document.object().value(QStringLiteral("skins")).toArray()) {
        const auto object = value.toObject();
        const auto name = object.value(QStringLiteral("name")).toString().trimmed().toStdString();
        if (!safeComponent(name) || !names.insert(name).second) {
            continue;
        }
        const auto model = object.value(QStringLiteral("model")).toString().compare(
                               QStringLiteral("SLIM"), Qt::CaseInsensitive)
                == 0
            ? FrontendSkinModel::Slim
            : FrontendSkinModel::Classic;
        entries.push_back({ name,
                            model,
                            object.value(QStringLiteral("capeId")).toString().toStdString(),
                            object.value(QStringLiteral("url")).toString().toStdString() });
    }
    return entries;
}

bool writeSkinIndex(
    const std::filesystem::path& dataRoot,
    const std::filesystem::path& skinRoot,
    const std::vector<SkinIndexEntry>& entries)
{
    QJsonArray values;
    for (const auto& entry : entries) {
        QJsonObject object;
        object.insert(QStringLiteral("name"), QString::fromStdString(entry.name));
        object.insert(QStringLiteral("capeId"), QString::fromStdString(entry.capeIdentifier));
        object.insert(QStringLiteral("url"), QString::fromStdString(entry.remoteURL));
        object.insert(QStringLiteral("model"),
                      entry.model == FrontendSkinModel::Slim ? QStringLiteral("SLIM") : QStringLiteral("CLASSIC"));
        values.append(object);
    }
    QJsonObject root;
    root.insert(QStringLiteral("skins"), values);
    return writeBytes(dataRoot, skinRoot / "index.json", QJsonDocument(root).toJson(QJsonDocument::Indented));
}

std::optional<std::string> uniqueSkinName(
    const std::filesystem::path& skinRoot, std::string preferred, const std::set<std::string>& reserved = {})
{
    preferred = sanitizedShortcutName(preferred);
    if (!safeComponent(preferred)) {
        preferred = "skin";
    }
    for (int suffix = 0; suffix <= 256; ++suffix) {
        const auto candidate = suffix == 0 ? preferred : preferred + std::to_string(suffix);
        if (!reserved.contains(candidate) && !std::filesystem::exists(skinRoot / (candidate + ".png"))) {
            return candidate;
        }
    }
    return std::nullopt;
}

struct LoadedSkinState final {
    std::vector<SkinIndexEntry> index;
    std::vector<FrontendSkinSnapshot> skins;
    std::vector<FrontendSkinCapeSnapshot> capes;
    std::optional<std::string> current;
    FrontendSkinAccountProfile profile;
};

std::optional<LoadedSkinState> loadSkinState(
    const std::filesystem::path& dataRoot,
    const std::filesystem::path& skinRoot,
    const ProductionUtilityRuntime::Dependencies& dependencies,
    const std::string& accountIdentifier,
    const CancellationCheck& cancellation,
    std::string& diagnostic)
{
    if (cancelled(cancellation)) {
        return std::nullopt;
    }
    std::error_code error;
    std::filesystem::create_directories(skinRoot, error);
    if (error || isSymlink(skinRoot) || !pathIsContained(dataRoot, skinRoot)) {
        diagnostic = "The Native Prism skin directory is not safely available.";
        return std::nullopt;
    }
    if (!dependencies.accountProfileLoader) {
        diagnostic = "The selected account profile is not available to the skin adapter.";
        return std::nullopt;
    }
    const auto profile = dependencies.accountProfileLoader(accountIdentifier);
    if (!profile.has_value() || profile->accountIdentifier != accountIdentifier) {
        diagnostic = "The selected account is not available for skin management.";
        return std::nullopt;
    }

    LoadedSkinState state;
    state.profile = *profile;
    state.index = readSkinIndex(skinRoot);
    std::set<std::string> tracked;
    bool needsSave = false;
    for (auto iterator = state.index.begin(); iterator != state.index.end();) {
        const auto path = skinRoot / (iterator->name + ".png");
        const auto bytes = readBytes(path);
        if (!bytes.has_value() || !validSkinPNG(*bytes)) {
            iterator = state.index.erase(iterator);
            needsSave = true;
            continue;
        }
        tracked.insert(iterator->name);
        ++iterator;
    }

    if (!profile->currentSkinURL.empty() && validSkinPNG(profile->currentSkinData)) {
        auto found = std::find_if(state.index.begin(), state.index.end(), [&](const auto& entry) {
            return entry.remoteURL == profile->currentSkinURL;
        });
        if (found == state.index.end()) {
            auto name = uniqueSkinName(skinRoot, profile->profileName.empty() ? "current-skin" : profile->profileName, tracked);
            if (name.has_value() && writeBytes(dataRoot, skinRoot / (*name + ".png"), byteArray(profile->currentSkinData))) {
                state.index.push_back({ *name, profile->currentModel, profile->currentCapeIdentifier,
                                        profile->currentSkinURL });
                tracked.insert(*name);
                needsSave = true;
            }
        } else {
            found->model = profile->currentModel;
            found->capeIdentifier = profile->currentCapeIdentifier;
        }
    }

    for (const auto& entry : std::filesystem::directory_iterator(skinRoot, error)) {
        if (error || cancelled(cancellation)) {
            diagnostic = cancelled(cancellation) ? "Skin loading was cancelled." : "The skin directory could not be read.";
            return std::nullopt;
        }
        if (entry.is_symlink(error) || !entry.is_regular_file(error) || entry.path().extension() != ".png") {
            continue;
        }
        const auto name = entry.path().stem().string();
        const auto bytes = readBytes(entry.path());
        if (safeComponent(name) && !tracked.contains(name) && bytes.has_value() && validSkinPNG(*bytes)) {
            state.index.push_back({ name, FrontendSkinModel::Classic, {}, {} });
            tracked.insert(name);
            needsSave = true;
        }
    }
    std::sort(state.index.begin(), state.index.end(), [](const auto& lhs, const auto& rhs) {
        return QString::localeAwareCompare(QString::fromStdString(lhs.name), QString::fromStdString(rhs.name)) < 0;
    });
    if (needsSave && !writeSkinIndex(dataRoot, skinRoot, state.index)) {
        diagnostic = "The skin index could not be updated.";
        return std::nullopt;
    }

    for (const auto& entry : state.index) {
        const auto path = (skinRoot / (entry.name + ".png")).lexically_normal();
        const auto bytes = readBytes(path);
        if (!bytes.has_value()) {
            continue;
        }
        state.skins.push_back({ entry.name, entry.name, entry.model, entry.capeIdentifier,
                                *bytes, *bytes, path, entry.remoteURL });
        if (!profile->currentSkinURL.empty() && entry.remoteURL == profile->currentSkinURL) {
            state.current = entry.name;
        }
    }
    for (auto cape : profile->capes) {
        if (cape.imageData.empty() && safeHTTPSURL(cape.remoteURL) && dependencies.download) {
            if (const auto downloaded = dependencies.download(cape.remoteURL, cancellation); downloaded.has_value()) {
                cape.imageData = *downloaded;
            }
        }
        if (!cape.id.empty() && !cape.displayName.empty() && !cape.imageData.empty()) {
            state.capes.push_back(std::move(cape));
        }
    }
    return state;
}

std::optional<FrontendSkinAccountProfile> parseServiceProfile(
    const QByteArray& body,
    const std::string& accountIdentifier,
    const ProductionUtilityRuntime::SkinServiceRequest& request,
    QNetworkAccessManager& manager)
{
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(body, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        return std::nullopt;
    }
    const auto object = document.object();
    FrontendSkinAccountProfile profile;
    profile.accountIdentifier = accountIdentifier;
    profile.profileName = object.value(QStringLiteral("name")).toString().toStdString();
    const auto skins = object.value(QStringLiteral("skins")).toArray();
    for (const auto& value : skins) {
        const auto skin = value.toObject();
        if (skin.value(QStringLiteral("state")).toString().compare(QStringLiteral("ACTIVE"), Qt::CaseInsensitive) != 0) {
            continue;
        }
        profile.currentSkinIdentifier = skin.value(QStringLiteral("id")).toString().toStdString();
        profile.currentSkinURL = skin.value(QStringLiteral("url")).toString().toStdString();
        profile.currentModel = skin.value(QStringLiteral("variant")).toString().compare(
                                   QStringLiteral("SLIM"), Qt::CaseInsensitive)
                == 0
            ? FrontendSkinModel::Slim
            : FrontendSkinModel::Classic;
        break;
    }
    if (request.operation == ProductionUtilityRuntime::SkinServiceOperation::Upload) {
        profile.currentSkinData = request.textureData;
    } else if (safeHTTPSURL(profile.currentSkinURL)) {
        QNetworkRequest skinRequest(QUrl(QString::fromStdString(profile.currentSkinURL)));
        const auto skinReply = finishReply(manager.get(skinRequest), request.cancellation);
        if (skinReply.transportSucceeded) {
            const auto data = byteVector(skinReply.body);
            if (validSkinPNG(data)) {
                profile.currentSkinData = data;
            }
        }
    }
    for (const auto& value : object.value(QStringLiteral("capes")).toArray()) {
        const auto cape = value.toObject();
        FrontendSkinCapeSnapshot snapshot;
        snapshot.id = cape.value(QStringLiteral("id")).toString().toStdString();
        snapshot.displayName = cape.value(QStringLiteral("alias")).toString().toStdString();
        snapshot.remoteURL = cape.value(QStringLiteral("url")).toString().toStdString();
        if (snapshot.displayName.empty()) {
            snapshot.displayName = snapshot.id;
        }
        if (cape.value(QStringLiteral("state")).toString().compare(QStringLiteral("ACTIVE"), Qt::CaseInsensitive) == 0) {
            profile.currentCapeIdentifier = snapshot.id;
        }
        if (safeHTTPSURL(snapshot.remoteURL)) {
            QNetworkRequest capeRequest(QUrl(QString::fromStdString(snapshot.remoteURL)));
            const auto capeReply = finishReply(manager.get(capeRequest), request.cancellation);
            if (capeReply.transportSucceeded) {
                snapshot.imageData = byteVector(capeReply.body);
            }
        }
        profile.capes.push_back(std::move(snapshot));
    }
    return profile;
}

ProductionUtilityRuntime::SkinServiceResult defaultSkinService(
    const ProductionUtilityRuntime::SkinServiceRequest& request)
{
    ProductionUtilityRuntime::SkinServiceResult result;
    if (request.authorizationCredential.empty() || cancelled(request.cancellation)) {
        result.cancelled = cancelled(request.cancellation);
        result.diagnosticText = result.cancelled ? "Skin service request was cancelled."
                                                  : "The selected account requires authentication.";
        return result;
    }

    QNetworkAccessManager manager;
    auto authorizedRequest = [&](const char* url) {
        QNetworkRequest networkRequest(QUrl(QString::fromLatin1(url)));
        networkRequest.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
        networkRequest.setRawHeader("Authorization", QByteArray("Bearer ") + QByteArray::fromStdString(request.authorizationCredential));
        networkRequest.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("PrismNative/12"));
        return networkRequest;
    };

    NetworkReply mutation;
    if (request.operation == ProductionUtilityRuntime::SkinServiceOperation::Upload) {
        if (!validSkinPNG(request.textureData)) {
            result.diagnosticText = "The selected skin is not a valid Minecraft PNG.";
            return result;
        }
        auto* multipart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
        QHttpPart file;
        file.setHeader(QNetworkRequest::ContentTypeHeader, QVariant(QStringLiteral("image/png")));
        file.setHeader(QNetworkRequest::ContentDispositionHeader,
                       QVariant(QStringLiteral("form-data; name=\"file\"; filename=\"skin.png\"")));
        file.setBody(byteArray(request.textureData));
        multipart->append(file);
        QHttpPart variant;
        variant.setHeader(QNetworkRequest::ContentDispositionHeader,
                          QVariant(QStringLiteral("form-data; name=\"variant\"")));
        variant.setBody(request.model == FrontendSkinModel::Slim ? QByteArray("SLIM") : QByteArray("CLASSIC"));
        multipart->append(variant);
        auto* reply = manager.post(
            authorizedRequest("https://api.minecraftservices.com/minecraft/profile/skins"), multipart);
        multipart->setParent(reply);
        mutation = finishReply(reply, request.cancellation);
    } else {
        mutation = finishReply(
            manager.deleteResource(authorizedRequest("https://api.minecraftservices.com/minecraft/profile/skins/active")),
            request.cancellation);
    }
    if (!mutation.transportSucceeded) {
        result.cancelled = mutation.cancelled;
        result.retryable = !mutation.cancelled;
        result.diagnosticText = mutation.cancelled ? "Skin service request was cancelled."
                                                    : "The Minecraft skin service rejected the profile change.";
        return result;
    }

    if (request.operation == ProductionUtilityRuntime::SkinServiceOperation::Upload) {
        auto capeRequest = authorizedRequest("https://api.minecraftservices.com/minecraft/profile/capes/active");
        NetworkReply capeReply;
        if (request.capeIdentifier.empty()) {
            capeReply = finishReply(manager.deleteResource(capeRequest), request.cancellation);
        } else {
            capeRequest.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
            QJsonObject body;
            body.insert(QStringLiteral("capeId"), QString::fromStdString(request.capeIdentifier));
            capeReply = finishReply(manager.put(capeRequest, QJsonDocument(body).toJson(QJsonDocument::Compact)),
                                    request.cancellation);
        }
        if (!capeReply.transportSucceeded) {
            result.cancelled = capeReply.cancelled;
            result.retryable = !capeReply.cancelled;
            result.diagnosticText = capeReply.cancelled ? "Cape selection was cancelled."
                                                        : "The Minecraft cape service rejected the profile change.";
            return result;
        }
    }

    const auto profileReply = finishReply(
        manager.get(authorizedRequest("https://api.minecraftservices.com/minecraft/profile")), request.cancellation);
    if (!profileReply.transportSucceeded) {
        result.cancelled = profileReply.cancelled;
        result.retryable = !profileReply.cancelled;
        result.diagnosticText = profileReply.cancelled ? "Profile refresh was cancelled."
                                                       : "The changed Minecraft profile could not be refreshed.";
        return result;
    }
    const auto profile = parseServiceProfile(profileReply.body, request.accountIdentifier, request, manager);
    if (!profile.has_value()) {
        result.retryable = true;
        result.diagnosticText = "The refreshed Minecraft profile could not be understood.";
        return result;
    }
    result.succeeded = true;
    result.profile = *profile;
    return result;
}

std::optional<Bytes> usernameSkin(
    const ProductionUtilityRuntime::Dependencies& dependencies,
    const std::string& username,
    FrontendSkinModel& model,
    std::string& remoteURL,
    const CancellationCheck& cancellation)
{
    if (!dependencies.download || !safeText(username, 16)) {
        return std::nullopt;
    }
    const auto encoded = QUrl::toPercentEncoding(QString::fromStdString(username)).toStdString();
    const auto lookup = dependencies.download(
        "https://api.minecraftservices.com/minecraft/profile/lookup/name/" + encoded, cancellation);
    if (!lookup.has_value()) {
        return std::nullopt;
    }
    QJsonParseError error;
    const auto lookupDocument = QJsonDocument::fromJson(byteArray(*lookup), &error);
    const auto identifier = lookupDocument.object().value(QStringLiteral("id")).toString();
    if (error.error != QJsonParseError::NoError || identifier.isEmpty()) {
        return std::nullopt;
    }
    const auto profile = dependencies.download(
        "https://sessionserver.mojang.com/session/minecraft/profile/" + identifier.toStdString(), cancellation);
    if (!profile.has_value()) {
        return std::nullopt;
    }
    const auto profileDocument = QJsonDocument::fromJson(byteArray(*profile), &error);
    if (error.error != QJsonParseError::NoError || !profileDocument.isObject()) {
        return std::nullopt;
    }
    QString encodedTextures;
    for (const auto& value : profileDocument.object().value(QStringLiteral("properties")).toArray()) {
        const auto object = value.toObject();
        if (object.value(QStringLiteral("name")).toString() == QStringLiteral("textures")) {
            encodedTextures = object.value(QStringLiteral("value")).toString();
            break;
        }
    }
    const auto textureDocument = QJsonDocument::fromJson(QByteArray::fromBase64(encodedTextures.toLatin1()), &error);
    const auto skin = textureDocument.object().value(QStringLiteral("textures")).toObject()
                          .value(QStringLiteral("SKIN")).toObject();
    remoteURL = skin.value(QStringLiteral("url")).toString().toStdString();
    model = skin.value(QStringLiteral("metadata")).toObject().value(QStringLiteral("model")).toString()
                    .compare(QStringLiteral("slim"), Qt::CaseInsensitive)
            == 0
        ? FrontendSkinModel::Slim
        : FrontendSkinModel::Classic;
    if (error.error != QJsonParseError::NoError || !safeHTTPSURL(remoteURL)) {
        return std::nullopt;
    }
    return dependencies.download(remoteURL, cancellation);
}

FrontendSkinActionResult skinFailure(
    const FrontendSkinActionRequest& request,
    FrontendSkinActionOutcome outcome,
    std::string key,
    std::string diagnostic,
    bool retryable)
{
    return { request.operation, outcome, request.accountIdentifier, {}, {}, std::nullopt, std::nullopt,
             std::move(key), std::move(diagnostic), retryable };
}

}  // namespace

ProductionUtilityRuntime::Dependencies ProductionUtilityRuntime::defaultDependencies(
    std::filesystem::path launcherExecutablePath, std::filesystem::path launcherIconPath)
{
    Dependencies dependencies;
    dependencies.download = defaultDownload;
    dependencies.updateInstaller = [](const std::string&) { return false; };
    dependencies.destinationResolver = defaultDestination;
    dependencies.shortcutWriter = defaultShortcutWriter;
    dependencies.accountProfileLoader = [](const std::string&) {
        return std::optional<FrontendSkinAccountProfile>();
    };
    dependencies.accountCredentialProvider = [](const std::string&) { return std::optional<std::string>(); };
    dependencies.accountProfileWriter = [](const FrontendSkinAccountProfile&) { return false; };
    dependencies.skinService = defaultSkinService;
    dependencies.launcherExecutablePath = std::move(launcherExecutablePath);
    dependencies.launcherIconPath = std::move(launcherIconPath);
    return dependencies;
}

ProductionUtilityRuntime::ProductionUtilityRuntime(std::filesystem::path dataRoot, Dependencies dependencies)
    : m_dataRoot(normalizeRoot(std::move(dataRoot))),
      m_skinRoot(m_dataRoot / "skins"),
      m_updateStatePath(m_dataRoot / "native-updates.json"),
      m_dependencies(std::move(dependencies))
{
    const auto defaults = defaultDependencies(m_dependencies.launcherExecutablePath, m_dependencies.launcherIconPath);
    if (!m_dependencies.download) {
        m_dependencies.download = defaults.download;
    }
    if (!m_dependencies.updateInstaller) {
        m_dependencies.updateInstaller = defaults.updateInstaller;
    }
    if (!m_dependencies.destinationResolver) {
        m_dependencies.destinationResolver = defaults.destinationResolver;
    }
    if (!m_dependencies.shortcutWriter) {
        m_dependencies.shortcutWriter = defaults.shortcutWriter;
    }
    if (!m_dependencies.accountProfileLoader) {
        m_dependencies.accountProfileLoader = defaults.accountProfileLoader;
    }
    if (!m_dependencies.accountCredentialProvider) {
        m_dependencies.accountCredentialProvider = defaults.accountCredentialProvider;
    }
    if (!m_dependencies.accountProfileWriter) {
        m_dependencies.accountProfileWriter = defaults.accountProfileWriter;
    }
    if (!m_dependencies.skinService) {
        m_dependencies.skinService = defaults.skinService;
    }
}

ProductionUtilityRuntime::~ProductionUtilityRuntime() noexcept
{
    shutdown();
}

FrontendNewsResult ProductionUtilityRuntime::news(const CancellationCheck& cancellation)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown || cancelled(cancellation)) {
        return { FrontendNewsOutcome::Cancelled, {}, "news.cancelled", "News loading was cancelled.", false };
    }
    const auto response = m_dependencies.download(kNewsFeedURL, cancellation);
    if (!response.has_value()) {
        return { cancelled(cancellation) ? FrontendNewsOutcome::Cancelled : FrontendNewsOutcome::Failed,
                 {}, cancelled(cancellation) ? "news.cancelled" : "news.networkFailed",
                 cancelled(cancellation) ? "News loading was cancelled." : "The Prism news feed could not be downloaded.",
                 !cancelled(cancellation) };
    }
    std::string diagnostic;
    auto entries = parseNews(*response, diagnostic);
    if (!entries.has_value()) {
        return { FrontendNewsOutcome::Failed, {}, "news.invalidFeed", std::move(diagnostic), true };
    }
    return { FrontendNewsOutcome::Succeeded, std::move(*entries), "news.loaded", {}, false };
}

FrontendUpdateCheckResult ProductionUtilityRuntime::checkForUpdates(
    const std::string& currentVersion, const CancellationCheck& cancellation)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown || cancelled(cancellation)) {
        return { FrontendUpdateCheckOutcome::Cancelled, std::nullopt, "updates.cancelled",
                 "Update checking was cancelled.", false };
    }
    const auto response = m_dependencies.download(kUpdateFeedURL, cancellation);
    if (!response.has_value()) {
        return { cancelled(cancellation) ? FrontendUpdateCheckOutcome::Cancelled : FrontendUpdateCheckOutcome::Failed,
                 std::nullopt, cancelled(cancellation) ? "updates.cancelled" : "updates.networkFailed",
                 cancelled(cancellation) ? "Update checking was cancelled." : "The Prism update feed could not be downloaded.",
                 !cancelled(cancellation) };
    }
    std::string diagnostic;
    const auto updates = parseUpdates(*response, diagnostic);
    if (!updates.has_value()) {
        return { FrontendUpdateCheckOutcome::Failed, std::nullopt, "updates.invalidFeed", std::move(diagnostic), true };
    }
    const auto skipped = skippedVersion(m_updateStatePath);
    const ParsedUpdate* best = nullptr;
    for (const auto& update : *updates) {
        if (update.version == skipped || compareVersions(update.version, currentVersion) <= 0) {
            continue;
        }
        if (!best || compareVersions(update.version, best->version) > 0) {
            best = &update;
        }
    }
    if (!best) {
        m_availableVersion.clear();
        m_availableDownloadURL.clear();
        return { FrontendUpdateCheckOutcome::NoUpdate, std::nullopt, "updates.current", {}, false };
    }
    m_availableVersion = best->version;
    m_availableDownloadURL = best->downloadURL;
    return { FrontendUpdateCheckOutcome::Available,
             FrontendUpdateNotice{ currentVersion, best->version, best->releaseNotes },
             "updates.available", {}, false };
}

FrontendUpdateDecisionResult ProductionUtilityRuntime::applyUpdateDecision(
    const FrontendUpdateDecisionRequest& request, const CancellationCheck& cancellation)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown || cancelled(cancellation)) {
        return { request.decision, FrontendUpdateDecisionOutcome::Cancelled, request.availableVersion,
                 "updates.decision.cancelled", "The update decision was cancelled.", false };
    }
    if (request.decision == FrontendUpdateDecision::RemindLater) {
        return { request.decision, FrontendUpdateDecisionOutcome::Succeeded, request.availableVersion,
                 "updates.remindLater", {}, false };
    }
    if (request.decision == FrontendUpdateDecision::SkipVersion) {
        if (!persistSkippedVersion(m_dataRoot, m_updateStatePath, request.availableVersion)) {
            return { request.decision, FrontendUpdateDecisionOutcome::Failed, request.availableVersion,
                     "updates.skip.failed", "The skipped update version could not be saved.", true };
        }
        return { request.decision, FrontendUpdateDecisionOutcome::Succeeded, request.availableVersion,
                 "updates.skip.saved", {}, false };
    }
    if (m_availableVersion != request.availableVersion || !safeHTTPSURL(m_availableDownloadURL)) {
        return { request.decision, FrontendUpdateDecisionOutcome::Rejected, request.availableVersion,
                 "updates.install.stale", "Check for updates again before requesting installation.", true };
    }
    if (!m_dependencies.updateInstaller(m_availableDownloadURL)) {
        return { request.decision, FrontendUpdateDecisionOutcome::AuthorizationRequired, request.availableVersion,
                 "updates.install.authorizationRequired",
                 "Installing an update requires a separately authorized updater action.", false };
    }
    return { request.decision, FrontendUpdateDecisionOutcome::Succeeded, request.availableVersion,
             "updates.install.requested", {}, false };
}

FrontendShortcutCreationResult ProductionUtilityRuntime::createShortcut(
    const FrontendShortcutCreationRequest& request, const CancellationCheck& cancellation)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown || cancelled(cancellation)) {
        return { FrontendShortcutCreationOutcome::Cancelled, request.instanceIdentifier,
                 "shortcuts.cancelled", "Shortcut creation was cancelled.", false };
    }
    if (!safeComponent(request.instanceIdentifier, 255) || !safeText(request.name, 128)) {
        return { FrontendShortcutCreationOutcome::Rejected, request.instanceIdentifier,
                 "shortcuts.invalidRequest", "The shortcut request contains invalid text.", false };
    }
    const auto instanceRoot = (m_dataRoot / "instances" / request.instanceIdentifier).lexically_normal();
    if (!pathIsContained(m_dataRoot, instanceRoot) || !isDirectory(instanceRoot)) {
        return { FrontendShortcutCreationOutcome::UnknownInstance, request.instanceIdentifier,
                 "shortcuts.unknownInstance", "The selected instance is no longer available.", false };
    }
    auto shortcutIconPath = m_dependencies.launcherIconPath;
    if (request.iconKey != "default") {
        if (!safeComponent(request.iconKey, 128)) {
            return { FrontendShortcutCreationOutcome::Rejected, request.instanceIdentifier,
                     "shortcuts.invalidIcon", "The selected shortcut icon is invalid.", false };
        }
        const auto customIconPath = (m_dataRoot / "icons" / (request.iconKey + ".icns")).lexically_normal();
        if (!pathIsContained(m_dataRoot, customIconPath) || !isRegularFile(customIconPath)) {
            return { FrontendShortcutCreationOutcome::Rejected, request.instanceIdentifier,
                     "shortcuts.iconUnavailable", "The selected shortcut icon is no longer available.", false };
        }
        shortcutIconPath = customIconPath;
    }
    std::string launchIdentifier = request.instanceIdentifier;
    const auto configPath = instanceRoot / "instance.cfg";
    if (isRegularFile(configPath)) {
        INIFile config;
        if (config.loadFile(QString::fromStdString(configPath.string()))) {
            const auto uuid = config.get(QStringLiteral("uuid"), QString()).toString().trimmed();
            const auto instanceID = config.get(QStringLiteral("InstanceID"), QString()).toString().trimmed();
            if (!uuid.isEmpty()) {
                launchIdentifier = uuid.toStdString();
            } else if (!instanceID.isEmpty()) {
                launchIdentifier = instanceID.toStdString();
            }
        }
    }

    auto baseName = sanitizedShortcutName(request.name);
    if (baseName.empty()) {
        return { FrontendShortcutCreationOutcome::Rejected, request.instanceIdentifier,
                 "shortcuts.invalidName", "Enter a valid shortcut name.", false };
    }
    std::filesystem::path destination;
    if (request.destination == FrontendShortcutDestination::Other) {
        destination = request.destinationPath.lexically_normal();
        if (destination.extension() == ".app") {
            destination.replace_extension();
        }
    } else {
        const auto root = m_dependencies.destinationResolver(request.destination);
        if (!root.has_value() || root->empty() || !root->is_absolute()) {
            return { FrontendShortcutCreationOutcome::Failed, request.instanceIdentifier,
                     "shortcuts.destinationUnavailable", "The requested shortcut folder is unavailable.", true };
        }
        destination = *root;
        if (request.destination == FrontendShortcutDestination::Applications) {
            destination /= "Prism Instances";
        }
        destination /= baseName;
    }
    std::vector<std::string> arguments{ "--launch", launchIdentifier };
    if (request.launchTarget == FrontendShortcutLaunchTarget::World) {
        arguments.insert(arguments.end(), { "--world", request.worldIdentifier });
    } else if (request.launchTarget == FrontendShortcutLaunchTarget::Server) {
        arguments.insert(arguments.end(), { "--server", request.serverAddress });
    }
    if (!request.profileName.empty()) {
        arguments.insert(arguments.end(), { "--profile", request.profileName });
    }
    const auto written = m_dependencies.shortcutWriter({ destination,
                                                         m_dependencies.launcherExecutablePath,
                                                         std::move(shortcutIconPath),
                                                         request.name,
                                                         std::move(arguments) });
    if (!written.has_value()) {
        return { FrontendShortcutCreationOutcome::Failed, request.instanceIdentifier,
                 "shortcuts.writeFailed", "The macOS application shortcut could not be created.", true };
    }
    return { FrontendShortcutCreationOutcome::Succeeded, request.instanceIdentifier,
             "shortcuts.created", {}, false };
}

FrontendSkinLoadResult ProductionUtilityRuntime::skins(
    const std::string& accountIdentifier, const CancellationCheck& cancellation)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown || cancelled(cancellation)) {
        return { FrontendSkinLoadOutcome::Cancelled, accountIdentifier, {}, {}, std::nullopt,
                 "skins.load.cancelled", "Skin loading was cancelled.", false };
    }
    std::string diagnostic;
    auto state = loadSkinState(m_dataRoot, m_skinRoot, m_dependencies, accountIdentifier, cancellation, diagnostic);
    if (!state.has_value()) {
        return { cancelled(cancellation) ? FrontendSkinLoadOutcome::Cancelled : FrontendSkinLoadOutcome::Failed,
                 accountIdentifier, {}, {}, std::nullopt,
                 cancelled(cancellation) ? "skins.load.cancelled" : "skins.load.failed",
                 std::move(diagnostic), !cancelled(cancellation) };
    }
    return { FrontendSkinLoadOutcome::Succeeded, accountIdentifier, std::move(state->skins),
             std::move(state->capes), std::move(state->current), "skins.load.succeeded", {}, false };
}

FrontendSkinActionResult ProductionUtilityRuntime::performSkinAction(
    const FrontendSkinActionRequest& request, const CancellationCheck& cancellation)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown || cancelled(cancellation)) {
        return skinFailure(request, FrontendSkinActionOutcome::Cancelled, "skins.action.cancelled",
                           "The skin action was cancelled.", false);
    }
    std::string diagnostic;
    auto state = loadSkinState(m_dataRoot, m_skinRoot, m_dependencies, request.accountIdentifier, cancellation, diagnostic);
    if (!state.has_value()) {
        return skinFailure(request, cancelled(cancellation) ? FrontendSkinActionOutcome::Cancelled
                                                            : FrontendSkinActionOutcome::Failed,
                           cancelled(cancellation) ? "skins.action.cancelled" : "skins.load.failed",
                           std::move(diagnostic), !cancelled(cancellation));
    }

    std::optional<std::string> selected;
    if (request.operation == FrontendSkinOperation::ImportFile
        || request.operation == FrontendSkinOperation::ImportURL
        || request.operation == FrontendSkinOperation::ImportUser) {
        std::optional<Bytes> source;
        std::string preferredName;
        FrontendSkinModel model = FrontendSkinModel::Classic;
        std::string remoteURL;
        if (request.operation == FrontendSkinOperation::ImportFile) {
            if (request.sourcePath.empty() || !request.sourcePath.is_absolute() || isSymlink(request.sourcePath)) {
                return skinFailure(request, FrontendSkinActionOutcome::Rejected, "skins.import.invalidFile",
                                   "Choose a readable local PNG skin file.", false);
            }
            source = readBytes(request.sourcePath);
            preferredName = request.sourcePath.stem().string();
        } else if (request.operation == FrontendSkinOperation::ImportURL) {
            if (!safeWebURL(request.sourceURL)) {
                return skinFailure(request, FrontendSkinActionOutcome::Rejected, "skins.import.invalidURL",
                                   "Enter a valid HTTP or HTTPS skin URL.", false);
            }
            source = m_dependencies.download(request.sourceURL, cancellation);
            preferredName = QUrl(QString::fromStdString(request.sourceURL)).fileName().toStdString();
            if (preferredName.ends_with(".png")) {
                preferredName.resize(preferredName.size() - 4);
            }
            remoteURL = request.sourceURL;
        } else {
            source = usernameSkin(m_dependencies, request.username, model, remoteURL, cancellation);
            preferredName = request.username;
        }
        if (cancelled(cancellation)) {
            return skinFailure(request, FrontendSkinActionOutcome::Cancelled, "skins.action.cancelled",
                               "The skin import was cancelled.", false);
        }
        if (!source.has_value() || !validSkinPNG(*source)) {
            return skinFailure(request, FrontendSkinActionOutcome::Failed, "skins.import.invalidSkin",
                               "Skin images must be 64x64 or 64x32 pixel PNG files.", true);
        }
        std::set<std::string> reserved;
        for (const auto& entry : state->index) {
            reserved.insert(entry.name);
        }
        const auto name = uniqueSkinName(m_skinRoot, preferredName, reserved);
        if (!name.has_value() || !writeBytes(m_dataRoot, m_skinRoot / (*name + ".png"), byteArray(*source))) {
            return skinFailure(request, FrontendSkinActionOutcome::Failed, "skins.import.copyFailed",
                               "The skin could not be copied into the Native Prism skin directory.", true);
        }
        state->index.push_back({ *name, model, {}, remoteURL });
        if (!writeSkinIndex(m_dataRoot, m_skinRoot, state->index)) {
            std::error_code rollbackError;
            std::filesystem::remove(m_skinRoot / (*name + ".png"), rollbackError);
            return skinFailure(request, FrontendSkinActionOutcome::Failed, "skins.import.indexFailed",
                               "The skin index could not be saved; the copied file was rolled back.", true);
        }
        selected = *name;
    } else if (request.operation == FrontendSkinOperation::Delete) {
        if (!request.confirmed) {
            return skinFailure(request, FrontendSkinActionOutcome::Rejected, "skins.delete.confirmationRequired",
                               "Deleting a skin requires confirmation.", false);
        }
        if (state->current == std::optional<std::string>(request.skinIdentifier)) {
            return skinFailure(request, FrontendSkinActionOutcome::Rejected, "skins.delete.currentRejected",
                               "The skin currently in use cannot be deleted.", false);
        }
        const auto found = std::find_if(state->index.begin(), state->index.end(), [&](const auto& entry) {
            return entry.name == request.skinIdentifier;
        });
        if (found == state->index.end()) {
            return skinFailure(request, FrontendSkinActionOutcome::Rejected, "skins.delete.unknownSkin",
                               "The selected skin is no longer available.", false);
        }
        const auto path = m_skinRoot / (found->name + ".png");
        const auto stagedPath = m_skinRoot / (found->name + ".delete-stage");
        std::error_code error;
        if (!pathIsContained(m_skinRoot, path) || !pathIsContained(m_skinRoot, stagedPath) || isSymlink(path)
            || std::filesystem::exists(stagedPath, error) || error) {
            return skinFailure(request, FrontendSkinActionOutcome::Failed, "skins.delete.failed",
                               "The selected skin file could not be removed.", true);
        }
        std::filesystem::rename(path, stagedPath, error);
        if (error) {
            return skinFailure(request, FrontendSkinActionOutcome::Failed, "skins.delete.failed",
                               "The selected skin file could not be staged for removal.", true);
        }
        state->index.erase(found);
        if (!writeSkinIndex(m_dataRoot, m_skinRoot, state->index)) {
            std::filesystem::rename(stagedPath, path, error);
            return skinFailure(request, FrontendSkinActionOutcome::Failed, "skins.delete.indexFailed",
                               error ? "The skin index and file rollback both failed."
                                     : "The skin index could not be saved; the removal was rolled back.",
                               true);
        }
        std::filesystem::remove(stagedPath, error);
        if (!state->index.empty()) {
            selected = state->index.front().name;
        }
    } else if (request.operation == FrontendSkinOperation::Rename) {
        if (!safeComponent(request.newName, 64)) {
            return skinFailure(request, FrontendSkinActionOutcome::Rejected, "skins.rename.invalidName",
                               "Enter a skin name from 1 to 64 characters without path separators.", false);
        }
        const auto found = std::find_if(state->index.begin(), state->index.end(), [&](const auto& entry) {
            return entry.name == request.skinIdentifier;
        });
        if (found == state->index.end()) {
            return skinFailure(request, FrontendSkinActionOutcome::Rejected, "skins.rename.unknownSkin",
                               "The selected skin is no longer available.", false);
        }
        const auto source = m_skinRoot / (found->name + ".png");
        const auto target = m_skinRoot / (request.newName + ".png");
        if (std::filesystem::exists(target) || !pathIsContained(m_skinRoot, target)) {
            return skinFailure(request, FrontendSkinActionOutcome::Rejected, "skins.rename.conflict",
                               "A skin with that name already exists.", false);
        }
        std::error_code error;
        std::filesystem::rename(source, target, error);
        if (error) {
            return skinFailure(request, FrontendSkinActionOutcome::Failed, "skins.rename.failed",
                               "The selected skin file could not be renamed.", true);
        }
        const auto oldName = found->name;
        found->name = request.newName;
        if (!writeSkinIndex(m_dataRoot, m_skinRoot, state->index)) {
            std::filesystem::rename(target, source, error);
            found->name = oldName;
            return skinFailure(request, FrontendSkinActionOutcome::Failed, "skins.rename.indexFailed",
                               "The skin index could not be saved; the rename was rolled back.", true);
        }
        selected = request.newName;
    } else {
        const bool upload = request.operation == FrontendSkinOperation::Upload;
        const SkinIndexEntry* selectedEntry = nullptr;
        Bytes texture;
        if (upload) {
            const auto found = std::find_if(state->index.begin(), state->index.end(), [&](const auto& entry) {
                return entry.name == request.skinIdentifier;
            });
            if (found == state->index.end()) {
                return skinFailure(request, FrontendSkinActionOutcome::Rejected, "skins.upload.unknownSkin",
                                   "The selected skin is no longer available.", false);
            }
            selectedEntry = &*found;
            const auto bytes = readBytes(m_skinRoot / (found->name + ".png"));
            if (!bytes.has_value() || !validSkinPNG(*bytes)) {
                return skinFailure(request, FrontendSkinActionOutcome::Failed, "skins.upload.invalidSkin",
                                   "The selected skin file is no longer a valid Minecraft PNG.", false);
            }
            texture = *bytes;
        }
        const auto credential = m_dependencies.accountCredentialProvider(request.accountIdentifier);
        if (!credential.has_value() || credential->empty()) {
            return skinFailure(request, FrontendSkinActionOutcome::Rejected, "skins.authentication.required",
                               "Refresh the selected Microsoft account before changing its skin.", true);
        }
        SkinServiceRequest serviceRequest;
        serviceRequest.operation = upload ? SkinServiceOperation::Upload : SkinServiceOperation::Reset;
        serviceRequest.accountIdentifier = request.accountIdentifier;
        serviceRequest.authorizationCredential = *credential;
        serviceRequest.model = request.model;
        serviceRequest.capeIdentifier = request.capeIdentifier;
        serviceRequest.textureData = std::move(texture);
        serviceRequest.cancellation = cancellation;
        const auto serviceResult = m_dependencies.skinService(serviceRequest);
        if (!serviceResult.succeeded) {
            return skinFailure(request,
                               serviceResult.cancelled ? FrontendSkinActionOutcome::Cancelled
                                                       : FrontendSkinActionOutcome::Failed,
                               serviceResult.cancelled ? "skins.action.cancelled" : "skins.service.failed",
                               serviceResult.diagnosticText, serviceResult.retryable);
        }
        if (serviceResult.profile.accountIdentifier != request.accountIdentifier
            || !m_dependencies.accountProfileWriter(serviceResult.profile)) {
            return skinFailure(request, FrontendSkinActionOutcome::Failed, "skins.profile.persistenceFailed",
                               "The changed Minecraft profile could not be saved in Native Prism.", true);
        }
        if (upload && selectedEntry) {
            auto found = std::find_if(state->index.begin(), state->index.end(), [&](const auto& entry) {
                return entry.name == selectedEntry->name;
            });
            if (found != state->index.end()) {
                found->model = request.model;
                found->capeIdentifier = request.capeIdentifier;
                found->remoteURL = serviceResult.profile.currentSkinURL;
                if (!writeSkinIndex(m_dataRoot, m_skinRoot, state->index)) {
                    return skinFailure(request, FrontendSkinActionOutcome::Failed, "skins.upload.indexFailed",
                                       "The profile changed, but the local skin index could not be saved.", true);
                }
                selected = found->name;
            }
        }
    }

    diagnostic.clear();
    auto confirmed = loadSkinState(m_dataRoot, m_skinRoot, m_dependencies, request.accountIdentifier, cancellation, diagnostic);
    if (!confirmed.has_value()) {
        return skinFailure(request, cancelled(cancellation) ? FrontendSkinActionOutcome::Cancelled
                                                            : FrontendSkinActionOutcome::Failed,
                           cancelled(cancellation) ? "skins.action.cancelled" : "skins.confirmation.failed",
                           std::move(diagnostic), !cancelled(cancellation));
    }
    if (selected.has_value()
        && std::none_of(confirmed->skins.begin(), confirmed->skins.end(), [&](const auto& skin) {
               return skin.id == *selected;
           })) {
        selected.reset();
    }
    if (!selected.has_value()) {
        selected = confirmed->current;
    }
    return { request.operation, FrontendSkinActionOutcome::Succeeded, request.accountIdentifier,
             std::move(confirmed->skins), std::move(confirmed->capes), std::move(confirmed->current),
             std::move(selected), "skins.action.succeeded", {}, false };
}

void ProductionUtilityRuntime::shutdown() noexcept
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_shutdown = true;
    m_availableVersion.clear();
    m_availableDownloadURL.clear();
}

std::shared_ptr<ProductionUtilityRuntime> makeProductionUtilityRuntime(
    std::filesystem::path dataRoot, ProductionUtilityRuntime::Dependencies dependencies)
{
    return std::make_shared<ProductionUtilityRuntime>(std::move(dataRoot), std::move(dependencies));
}

FrontendRuntimeDependencies productionUtilityRuntimeDependencies(
    std::shared_ptr<ProductionUtilityRuntime> runtime, FrontendRuntimeDependencies dependencies)
{
    if (!runtime) {
        throw std::invalid_argument("Production utility runtime dependency requires an owner");
    }
    dependencies.loadNews = [runtime](const std::filesystem::path&, const auto& cancellation) {
        return runtime->news(cancellation);
    };
    dependencies.checkForUpdates = [runtime](
                                               const std::filesystem::path&,
                                               const std::string& currentVersion,
                                               const auto& cancellation) {
        return runtime->checkForUpdates(currentVersion, cancellation);
    };
    dependencies.applyUpdateDecision = [runtime](
                                                    const std::filesystem::path&,
                                                    const FrontendUpdateDecisionRequest& request,
                                                    const auto& cancellation) {
        return runtime->applyUpdateDecision(request, cancellation);
    };
    dependencies.createShortcut = [runtime](
                                               const std::filesystem::path&,
                                               const FrontendShortcutCreationRequest& request,
                                               const auto& cancellation) {
        return runtime->createShortcut(request, cancellation);
    };
    dependencies.loadSkins = [runtime](
                                         const std::filesystem::path&,
                                         const std::string& accountIdentifier,
                                         const auto& cancellation) {
        return runtime->skins(accountIdentifier, cancellation);
    };
    dependencies.performSkinAction = [runtime](
                                                  const std::filesystem::path&,
                                                  const FrontendSkinActionRequest& request,
                                                  const auto& cancellation) {
        return runtime->performSkinAction(request, cancellation);
    };
    return dependencies;
}
