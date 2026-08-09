// SPDX-License-Identifier: GPL-3.0-only

#include "ProductionInstanceDetailRuntime.h"

#include "GZip.h"
#include "archive/ArchiveWriter.h"
#include "minecraft/OneSixVersionFormat.h"
#include "minecraft/VersionFile.h"
#include "settings/INIFile.h"

#include <archive.h>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QMetaType>
#include <QSaveFile>
#include <QString>

#include <io/stream_reader.h>
#include <tag_compound.h>
#include <tag_list.h>
#include <tag_primitive.h>
#include <tag_string.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <functional>
#include <regex>
#include <sstream>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>

namespace {

std::filesystem::path normalizeRoot(std::filesystem::path root)
{
    root = std::move(root).lexically_normal();
    if (root.empty() || !root.is_absolute()) {
        throw std::invalid_argument("Production instance detail runtime requires an absolute data root");
    }
    return root;
}

bool isSafeComponent(const std::string& value, std::size_t maxLength = 255)
{
    return !value.empty() && value.size() <= maxLength && value != "." && value != ".."
        && std::all_of(value.begin(), value.end(), [](unsigned char character) {
               return character >= 0x20 && character != '/' && character != '\\' && character != 0x7f;
           });
}

bool isSafeText(const std::string& value, std::size_t maxLength, bool allowEmpty = true)
{
    return value.size() <= maxLength
        && (allowEmpty || !value.empty())
        && std::all_of(value.begin(), value.end(), [](unsigned char character) {
               return character != 0 && character != 0x7f;
           });
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
    return std::filesystem::is_regular_file(path, error) && !error;
}

bool isDirectory(const std::filesystem::path& path)
{
    std::error_code error;
    return std::filesystem::is_directory(path, error) && !error;
}

bool pathIsContainedWithoutSymlinks(const std::filesystem::path& root, const std::filesystem::path& candidate)
{
    const auto normalizedRoot = root.lexically_normal();
    const auto normalizedCandidate = candidate.lexically_normal();
    const auto relative = normalizedCandidate.lexically_relative(normalizedRoot);
    if (relative.empty() || relative.is_absolute() || relative.has_root_path()
        || std::any_of(relative.begin(), relative.end(), [](const auto& component) { return component == ".."; })) {
        return false;
    }

    std::filesystem::path current = normalizedRoot;
    std::error_code error;
    if (std::filesystem::is_symlink(std::filesystem::symlink_status(current, error)) || error) {
        return false;
    }
    for (const auto& component : relative) {
        current /= component;
        const auto status = std::filesystem::symlink_status(current, error);
        if (error) {
            if (error == std::errc::no_such_file_or_directory) {
                // A missing suffix cannot contain a symlink yet. The caller
                // still validates the lexical components and creates the
                // destination only below the already-validated root.
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

bool writeBytesAtomically(const std::filesystem::path& path, const QByteArray& bytes);

bool extractWorldArchive(
    const std::filesystem::path& source,
    const std::filesystem::path& destination,
    const std::function<bool()>& cancellationCheck,
    bool& cancelled)
{
    cancelled = false;
    MMCZip::ArchiveReader archive(QString::fromStdString(source.string()));
    bool foundLevelDat = false;
    const bool parsed = archive.parse([&](MMCZip::ArchiveReader::File* file) {
        if (cancellationCheck && cancellationCheck()) {
            cancelled = true;
            return false;
        }
        const auto rawName = file->filename().replace('\\', '/');
        if (rawName.isEmpty() || rawName.startsWith('/') || rawName.contains("../") || rawName.contains("/..")) {
            return false;
        }
        std::filesystem::path relative;
        for (const auto& component : rawName.split('/', Qt::SkipEmptyParts)) {
            const auto componentText = component.toStdString();
            if (!isSafeComponent(componentText, 512) || componentText == "." || componentText == "..") {
                return false;
            }
            relative /= componentText;
        }
        if (relative.empty() || !pathIsContainedWithoutSymlinks(destination, destination / relative)) {
            return false;
        }
        if (!file->isFile()) {
            return rawName.endsWith('/');
        }
        int status = 0;
        const auto bytes = file->readAll(&status);
        if (status != ARCHIVE_OK && status != ARCHIVE_EOF) {
            return false;
        }
        if (!writeBytesAtomically(destination / relative, bytes)) {
            return false;
        }
        foundLevelDat = foundLevelDat || relative.filename() == "level.dat";
        return true;
    });
    if (cancelled) {
        return false;
    }
    return parsed && foundLevelDat;
}

std::optional<std::filesystem::path> safeChild(
    const std::filesystem::path& root, const std::string& component, bool allowMissing = true)
{
    if (!isSafeComponent(component) || !pathIsContainedWithoutSymlinks(root, root / component)) {
        return std::nullopt;
    }
    const auto child = (root / component).lexically_normal();
    if (!allowMissing && !std::filesystem::exists(child)) {
        return std::nullopt;
    }
    return child;
}

std::optional<QByteArray> readBytes(const std::filesystem::path& path)
{
    if (!isRegularFile(path) || isSymlink(path)) {
        return std::nullopt;
    }
    QFile file(QString::fromStdString(path.string()));
    if (!file.open(QIODevice::ReadOnly)) {
        return std::nullopt;
    }
    return file.readAll();
}

bool writeBytesAtomically(const std::filesystem::path& path, const QByteArray& bytes)
{
    std::error_code error;
    std::filesystem::create_directories(path.parent_path(), error);
    if (error || isSymlink(path.parent_path())) {
        return false;
    }
    QSaveFile file(QString::fromStdString(path.string()));
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size()) {
        file.cancelWriting();
        return false;
    }
    return file.commit();
}

std::optional<QJsonObject> readJsonObject(const std::filesystem::path& path)
{
    const auto bytes = readBytes(path);
    if (!bytes) {
        return std::nullopt;
    }
    QJsonParseError error{};
    const auto document = QJsonDocument::fromJson(*bytes, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        return std::nullopt;
    }
    return document.object();
}

std::optional<INIFile> readINI(const std::filesystem::path& path)
{
    if (!isRegularFile(path) || isSymlink(path)) {
        return std::nullopt;
    }
    INIFile settings;
    if (!settings.loadFile(QString::fromStdString(path.string()))) {
        return std::nullopt;
    }
    return settings;
}

std::string iniString(const INIFile& settings, const char* key, std::string fallback = {})
{
    const auto value = settings.get(QString::fromUtf8(key), QString::fromStdString(fallback)).toString().trimmed();
    return value.toStdString();
}

std::int64_t unixSeconds(const std::filesystem::path& path)
{
    std::error_code error;
    const auto modified = std::filesystem::last_write_time(path, error);
    if (error) {
        return 0;
    }
    const auto systemTime = std::chrono::time_point_cast<std::chrono::seconds>(
        modified - std::filesystem::file_time_type::clock::now() + std::chrono::system_clock::now());
    return systemTime.time_since_epoch().count();
}

std::uint64_t directorySize(const std::filesystem::path& root)
{
    std::uint64_t total = 0;
    std::error_code error;
    if (isRegularFile(root)) {
        const auto size = std::filesystem::file_size(root, error);
        return error ? 0 : size;
    }
    if (!isDirectory(root) || isSymlink(root)) {
        return 0;
    }
    for (std::filesystem::recursive_directory_iterator iterator(root, error), end; iterator != end && !error;
         iterator.increment(error)) {
        const auto& entry = *iterator;
        if (entry.is_symlink(error) || error) {
            error.clear();
            iterator.disable_recursion_pending();
            continue;
        }
        if (entry.is_regular_file(error) && !error) {
            const auto size = entry.file_size(error);
            if (!error) {
                total += size;
            }
        }
        error.clear();
    }
    return total;
}

std::optional<std::string> nbtString(nbt::value& parent, const char* key)
{
    try {
        auto& value = parent.at(key);
        if (value.get_type() != nbt::tag_type::String) {
            return std::nullopt;
        }
        return std::string(value.as<nbt::tag_string>().get());
    } catch (...) {
        return std::nullopt;
    }
}

std::optional<std::int64_t> nbtLong(nbt::value& parent, const char* key)
{
    try {
        auto& value = parent.at(key);
        if (value.get_type() != nbt::tag_type::Long) {
            return std::nullopt;
        }
        return value.as<nbt::tag_long>().get();
    } catch (...) {
        return std::nullopt;
    }
}

std::optional<int> nbtInt(nbt::value& parent, const char* key)
{
    try {
        auto& value = parent.at(key);
        if (value.get_type() != nbt::tag_type::Int) {
            return std::nullopt;
        }
        return value.as<nbt::tag_int>().get();
    } catch (...) {
        return std::nullopt;
    }
}

struct WorldMetadata final {
    std::string name;
    std::string gameMode;
    std::int64_t lastPlayed = 0;
    std::int64_t seed = 0;
    bool hasSeed = false;
};

std::optional<WorldMetadata> readWorldMetadata(const std::filesystem::path& worldPath)
{
    const auto bytes = readBytes(worldPath / "level.dat");
    if (!bytes) {
        return std::nullopt;
    }
    QByteArray uncompressed;
    if (!GZip::unzip(*bytes, uncompressed)) {
        return std::nullopt;
    }
    std::istringstream stream(std::string(uncompressed.constData(), static_cast<std::size_t>(uncompressed.size())));
    try {
        auto pair = nbt::io::read_compound(stream);
        if (pair.first != "" || !pair.second) {
            return std::nullopt;
        }
        auto& root = *pair.second;
        nbt::value* data = nullptr;
        if (root.has_key("Data", nbt::tag_type::Compound)) {
            data = &root["Data"];
        } else if (root.has_key("data", nbt::tag_type::Compound)) {
            data = &root["data"];
        }
        if (!data) {
            return std::nullopt;
        }

        WorldMetadata metadata;
        metadata.name = nbtString(*data, "LevelName").value_or(std::string());
        metadata.lastPlayed = nbtLong(*data, "LastPlayed").value_or(0) / 1000;
        const auto mode = nbtInt(*data, "GameType");
        if (mode) {
            switch (*mode) {
                case 0:
                    metadata.gameMode = "Survival";
                    break;
                case 1:
                    metadata.gameMode = "Creative";
                    break;
                case 2:
                    metadata.gameMode = "Adventure";
                    break;
                case 3:
                    metadata.gameMode = "Spectator";
                    break;
                default:
                    metadata.gameMode = "Unknown";
                    break;
            }
        }
        if (const auto seed = nbtLong(*data, "RandomSeed")) {
            metadata.seed = *seed;
            metadata.hasSeed = true;
        }
        return metadata;
    } catch (...) {
        return std::nullopt;
    }
}

std::string resourceFolder(FrontendInstanceResourceKind kind)
{
    switch (kind) {
        case FrontendInstanceResourceKind::Mods:
            return "mods";
        case FrontendInstanceResourceKind::ResourcePacks:
            return "resourcepacks";
        case FrontendInstanceResourceKind::ShaderPacks:
            return "shaderpacks";
        case FrontendInstanceResourceKind::TexturePacks:
            return "texturepacks";
        case FrontendInstanceResourceKind::DataPacks:
            return "datapacks";
    }
    return {};
}

std::string stripResourceSuffix(std::string filename, bool& enabled)
{
    enabled = true;
    if (filename.ends_with(".disabled")) {
        filename.resize(filename.size() - std::string(".disabled").size());
        enabled = false;
    }
    return filename;
}

std::string resourceDisplayName(std::string filename)
{
    const auto dot = filename.find_last_of('.');
    if (dot != std::string::npos && dot > 0) {
        filename.resize(dot);
    }
    return filename;
}

std::optional<std::filesystem::path> gameRootFor(const std::filesystem::path& instancePath)
{
    const auto minecraft = instancePath / "minecraft";
    const auto dotMinecraft = instancePath / ".minecraft";
    if (isDirectory(dotMinecraft) && !isDirectory(minecraft)) {
        return dotMinecraft;
    }
    return minecraft;
}

bool copyTreeWithoutSymlinks(
    const std::filesystem::path& source,
    const std::filesystem::path& destination,
    const std::function<bool()>& cancellationCheck = {})
{
    if (cancellationCheck && cancellationCheck()) {
        return false;
    }
    if (isSymlink(source) || (!isDirectory(source) && !isRegularFile(source))) {
        return false;
    }
    std::error_code error;
    if (isDirectory(source)) {
        std::filesystem::create_directories(destination, error);
        if (error) {
            return false;
        }
        for (const auto& entry : std::filesystem::directory_iterator(source, error)) {
            if (error || entry.is_symlink(error) || error
                || !copyTreeWithoutSymlinks(
                       entry.path(), destination / entry.path().filename(), cancellationCheck)) {
                return false;
            }
        }
        return true;
    }
    return std::filesystem::copy_file(source, destination, std::filesystem::copy_options::none, error) && !error;
}

bool collectRegularFiles(
    const std::filesystem::path& root,
    std::vector<std::pair<std::filesystem::path, std::string>>& files,
    const std::function<bool()>& cancellationCheck = {})
{
    if (cancellationCheck && cancellationCheck()) {
        return false;
    }
    if (isSymlink(root)) {
        return false;
    }
    if (isRegularFile(root)) {
        files.emplace_back(root, root.filename().generic_string());
        return true;
    }
    if (!isDirectory(root)) {
        return false;
    }

    std::error_code error;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(root, error)) {
        if (error || (cancellationCheck && cancellationCheck())) {
            return false;
        }
        if (entry.is_symlink(error) || error) {
            return false;
        }
        if (!entry.is_regular_file(error) || error) {
            error.clear();
            continue;
        }
        const auto relative = entry.path().lexically_relative(root).generic_string();
        if (relative.empty() || relative.starts_with("../") || relative == "..") {
            return false;
        }
        files.emplace_back(entry.path(), relative);
        error.clear();
    }
    return !error;
}

FrontendTaskSnapshot operationProgress(
    std::string identifier,
    std::string title,
    FrontendTaskState state,
    FrontendTaskProgressKind progressKind,
    double progressFraction,
    bool cancellationAllowed,
    std::optional<FrontendTaskTerminalResult> terminal = std::nullopt)
{
    return { std::move(identifier), std::move(title), state, progressKind, progressFraction, cancellationAllowed, {},
             std::move(terminal) };
}

std::string copyIdentifierBase(const std::string& name)
{
    std::string result = "copy-";
    for (const auto character : name) {
        const auto unsignedCharacter = static_cast<unsigned char>(character);
        if (std::isalnum(unsignedCharacter)) {
            result.push_back(static_cast<char>(std::tolower(unsignedCharacter)));
        } else if (result.back() != '-') {
            result.push_back('-');
        }
        if (result.size() >= 220) {
            break;
        }
    }
    while (result.ends_with('-')) {
        result.pop_back();
    }
    return result == "copy" ? "copy-instance" : result;
}

std::string replaceAll(std::string value, const std::string& needle, const std::string& replacement)
{
    std::size_t offset = 0;
    while ((offset = value.find(needle, offset)) != std::string::npos) {
        value.replace(offset, needle.size(), replacement);
        offset += replacement.size();
    }
    return value;
}

std::string csvValue(const std::string& value)
{
    std::string escaped = value;
    escaped = replaceAll(std::move(escaped), "\"", "\"\"");
    return "\"" + escaped + "\"";
}

struct ServerRecord final {
    std::string name;
    std::string address;
    FrontendServerResourcePolicy resourcePolicy = FrontendServerResourcePolicy::Ask;
};

std::optional<std::vector<ServerRecord>> readServers(const std::filesystem::path& path)
{
    if (!std::filesystem::exists(path)) {
        return std::vector<ServerRecord>();
    }
    const auto bytes = readBytes(path);
    if (!bytes) {
        return std::nullopt;
    }
    std::istringstream stream(std::string(bytes->constData(), static_cast<std::size_t>(bytes->size())));
    try {
        auto pair = nbt::io::read_compound(stream);
        if (pair.first != "" || !pair.second || !pair.second->has_key("servers", nbt::tag_type::List)) {
            return std::nullopt;
        }
        auto& list = pair.second->at("servers").as<nbt::tag_list>();
        std::vector<ServerRecord> result;
        result.reserve(static_cast<std::size_t>(list.size()));
        for (auto iterator = list.begin(); iterator != list.end(); ++iterator) {
            auto& server = iterator->as<nbt::tag_compound>();
            ServerRecord record;
            record.name = std::string(server["name"]);
            record.address = std::string(server["ip"]);
            if (server.has_key("acceptTextures", nbt::tag_type::Byte)) {
                record.resourcePolicy = server["acceptTextures"].as<nbt::tag_byte>().get()
                    ? FrontendServerResourcePolicy::Always
                    : FrontendServerResourcePolicy::Never;
            }
            if (!isSafeText(record.name, 512, false) || !isSafeText(record.address, 512, false)) {
                return std::nullopt;
            }
            result.push_back(std::move(record));
        }
        return result;
    } catch (...) {
        return std::nullopt;
    }
}

bool writeServers(const std::filesystem::path& path, const std::vector<ServerRecord>& servers)
{
    nbt::tag_compound root;
    nbt::tag_list list;
    for (const auto& server : servers) {
        nbt::tag_compound value;
        value.insert("name", server.name);
        value.insert("ip", server.address);
        if (server.resourcePolicy != FrontendServerResourcePolicy::Ask) {
            value.insert("acceptTextures", nbt::tag_byte(server.resourcePolicy == FrontendServerResourcePolicy::Always));
        }
        list.push_back(std::move(value));
    }
    root.insert("servers", nbt::value(std::move(list)));
    std::ostringstream stream;
    nbt::io::write_tag("", root, stream);
    const auto encoded = QByteArray::fromStdString(stream.str());
    return writeBytesAtomically(path, encoded);
}

int serverIndex(const std::string& identifier)
{
    constexpr std::string_view prefix = "server-";
    if (!identifier.starts_with(prefix)) {
        return -1;
    }
    try {
        const auto value = std::stoi(identifier.substr(prefix.size()));
        return value >= 0 ? value : -1;
    } catch (...) {
        return -1;
    }
}

std::string serverIdentifier(std::size_t index)
{
    return "server-" + std::to_string(index);
}

std::string redactLog(std::string text)
{
    static const std::regex credentialPattern(
        R"(((--)?(access[_-]?token|refresh[_-]?token|client[_-]?secret|password|authorization|username|email|account|uuid|token)\s*([:=]|\s)\s*(Bearer\s+)?)([^\s,;]+))",
        std::regex_constants::icase);
    return std::regex_replace(text, credentialPattern, "$1<redacted>");
}

FrontendInstanceResourceMutationResult resourceResult(
    FrontendInstanceResourceKind kind,
    FrontendInstanceResourceAction action,
    FrontendInstanceResourceMutationOutcome outcome,
    const std::string& instanceIdentifier,
    const std::string& resourceIdentifier,
    std::string localizationKey,
    std::string diagnostic,
    bool rolledBack = false)
{
    return { kind,
             action,
             outcome,
             instanceIdentifier,
             resourceIdentifier,
             std::move(localizationKey),
             std::move(diagnostic),
             rolledBack };
}

FrontendInstanceDetailMutationResult detailResult(
    FrontendInstanceDetailKind kind,
    FrontendInstanceDetailAction action,
    FrontendInstanceDetailMutationOutcome outcome,
    const std::string& instanceIdentifier,
    const std::string& itemIdentifier,
    std::string localizationKey,
    std::string diagnostic,
    bool rolledBack = false)
{
    return { kind,
             action,
             outcome,
             instanceIdentifier,
             itemIdentifier,
             std::move(localizationKey),
             std::move(diagnostic),
             rolledBack };
}

}  // namespace

ProductionInstanceDetailRuntime::ProductionInstanceDetailRuntime(std::filesystem::path dataRoot)
    : m_dataRoot(normalizeRoot(std::move(dataRoot))), m_instancesRoot(m_dataRoot / "instances")
{
    if (isSymlink(m_dataRoot) || !isDirectory(m_instancesRoot) || isSymlink(m_instancesRoot)) {
        throw std::invalid_argument("Production instance detail runtime requires a safe Native instances root");
    }
}

std::optional<std::filesystem::path> ProductionInstanceDetailRuntime::instancePath(const std::string& identifier) const
{
    const auto path = safeChild(m_instancesRoot, identifier, false);
    if (!path || !isDirectory(*path) || isSymlink(*path)) {
        return std::nullopt;
    }
    return path;
}

std::optional<std::filesystem::path> ProductionInstanceDetailRuntime::gameRoot(const std::string& identifier) const
{
    const auto instance = instancePath(identifier);
    if (!instance) {
        return std::nullopt;
    }
    const auto game = gameRootFor(*instance);
    if (!game || !pathIsContainedWithoutSymlinks(*instance, *game) || isSymlink(*game)) {
        return std::nullopt;
    }
    return game;
}

std::optional<FrontendInstanceDetailsSnapshot> ProductionInstanceDetailRuntime::instanceDetails(
    const std::string& identifier) const
{
    const auto instance = instancePath(identifier);
    if (!instance) {
        return std::nullopt;
    }
    const auto settings = readINI(*instance / "instance.cfg");
    if (!settings) {
        return std::nullopt;
    }
    const auto name = iniString(*settings, "name", identifier);
    const auto iconKey = iniString(*settings, "iconKey", "default");
    const auto groupId = iniString(*settings, "InstanceGroupId", iniString(*settings, "GroupId"));
    const auto instanceType = iniString(*settings, "InstanceType", "Minecraft");
    const auto notes = iniString(*settings, "notes");
    if (!isSafeText(name, 512, false) || !isSafeText(iconKey, 256, false) || !isSafeText(groupId, 512)
        || !isSafeText(instanceType, 256, false) || !isSafeText(notes, 65536)) {
        return std::nullopt;
    }
    return FrontendInstanceDetailsSnapshot{ identifier, name, iconKey, groupId, instanceType, notes, true };
}

std::optional<std::vector<FrontendInstanceComponentSnapshot>> ProductionInstanceDetailRuntime::instanceComponents(
    const std::string& identifier) const
{
    const auto instance = instancePath(identifier);
    if (!instance) {
        return std::nullopt;
    }
    const auto pack = readJsonObject(*instance / "mmc-pack.json");
    if (!pack || pack->value("formatVersion").toInt(-1) != 1 || !pack->value("components").isArray()) {
        return std::nullopt;
    }

    std::vector<FrontendInstanceComponentSnapshot> result;
    for (const auto& value : pack->value("components").toArray()) {
        if (!value.isObject()) {
            return std::nullopt;
        }
        const auto component = value.toObject();
        const auto uid = component.value("uid").toString().trimmed().toStdString();
        if (!isSafeComponent(uid)) {
            return std::nullopt;
        }
        FrontendInstanceComponentSnapshot snapshot;
        snapshot.id = uid;
        snapshot.name = component.value("cachedName").toString().trimmed().toStdString();
        snapshot.version = component.value("cachedVersion").toString().trimmed().toStdString();
        snapshot.enabled = !component.value("disabled").toBool(false);
        snapshot.dependencyOnly = component.value("dependencyOnly").toBool(false);
        snapshot.important = component.value("important").toBool(false);
        snapshot.custom = component.value("custom").toBool(uid != "net.minecraft");
        snapshot.canBeDisabled = !snapshot.important;

        const auto patchPath = *instance / "patches" / (uid + ".json");
        if (isRegularFile(patchPath) && !isSymlink(patchPath)) {
            if (const auto patch = readJsonObject(patchPath)) {
                try {
                    const auto versionFile = OneSixVersionFormat::versionFileFromJson(
                        QJsonDocument(*patch), QString::fromStdString(patchPath.string()), false);
                    if (snapshot.name.empty()) {
                        snapshot.name = versionFile->name.toStdString();
                    }
                    if (snapshot.version.empty()) {
                        snapshot.version = versionFile->version.toStdString();
                    }
                    switch (versionFile->getProblemSeverity()) {
                        case ProblemSeverity::None:
                            snapshot.problemSeverity = FrontendInstanceComponentProblemSeverity::None;
                            break;
                        case ProblemSeverity::Warning:
                            snapshot.problemSeverity = FrontendInstanceComponentProblemSeverity::Warning;
                            break;
                        case ProblemSeverity::Error:
                            snapshot.problemSeverity = FrontendInstanceComponentProblemSeverity::Error;
                            break;
                    }
                    for (const auto& problem : versionFile->getProblems()) {
                        snapshot.problemDescriptions.push_back(problem.m_description.toStdString());
                    }
                } catch (...) {
                    snapshot.problemSeverity = FrontendInstanceComponentProblemSeverity::Error;
                    snapshot.problemDescriptions.push_back("Component patch could not be parsed.");
                }
            } else {
                snapshot.problemSeverity = FrontendInstanceComponentProblemSeverity::Error;
                snapshot.problemDescriptions.push_back("Component patch is not valid JSON.");
            }
        } else {
            snapshot.problemSeverity = FrontendInstanceComponentProblemSeverity::Error;
            snapshot.problemDescriptions.push_back("Component patch is unavailable.");
        }
        if (snapshot.name.empty()) {
            snapshot.name = uid;
        }
        if (!isSafeText(snapshot.name, 512, false) || !isSafeText(snapshot.version, 512)) {
            return std::nullopt;
        }
        result.push_back(std::move(snapshot));
    }
    return result;
}

std::optional<std::vector<FrontendInstanceResourceSnapshot>> ProductionInstanceDetailRuntime::instanceResources(
    const std::string& identifier, FrontendInstanceResourceKind kind) const
{
    const auto game = gameRoot(identifier);
    const auto folderName = resourceFolder(kind);
    if (!game || folderName.empty()) {
        return std::nullopt;
    }
    const auto folder = *game / folderName;
    if (!pathIsContainedWithoutSymlinks(*game, folder) || isSymlink(folder)) {
        return std::nullopt;
    }
    if (!std::filesystem::exists(folder)) {
        return std::vector<FrontendInstanceResourceSnapshot>();
    }
    if (!isDirectory(folder)) {
        return std::nullopt;
    }

    std::vector<FrontendInstanceResourceSnapshot> result;
    std::error_code error;
    for (const auto& entry : std::filesystem::directory_iterator(folder, error)) {
        if (error) {
            return std::nullopt;
        }
        if (entry.is_symlink(error) || error) {
            error.clear();
            continue;
        }
        const auto filename = entry.path().filename().string();
        if (!isSafeComponent(filename, 512) || (!entry.is_regular_file(error) && !entry.is_directory(error)) || error) {
            error.clear();
            continue;
        }
        bool enabled = true;
        const auto displayFileName = stripResourceSuffix(filename, enabled);
        FrontendInstanceResourceSnapshot snapshot;
        snapshot.id = filename;
        snapshot.name = resourceDisplayName(displayFileName);
        snapshot.version = {};
        snapshot.fileName = filename;
        snapshot.provider = "Unknown";
        snapshot.kind = kind;
        snapshot.enabled = enabled;
        snapshot.isDirectory = entry.is_directory(error);
        snapshot.canBeToggled = !snapshot.isDirectory;
        snapshot.canBeDeleted = true;
        snapshot.hasMetadata = false;
        if (snapshot.name.empty()) {
            snapshot.name = displayFileName;
        }
        result.push_back(std::move(snapshot));
        error.clear();
    }
    return result;
}

FrontendInstanceResourceMutationResult ProductionInstanceDetailRuntime::mutateInstanceResource(
    const std::string& identifier,
    FrontendInstanceResourceKind kind,
    const FrontendInstanceResourceMutationRequest& request)
{
    std::lock_guard<std::mutex> lock(m_mutationMutex);
    const auto game = gameRoot(identifier);
    const auto folderName = resourceFolder(kind);
    if (!game || folderName.empty()) {
        return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::UnknownInstance, identifier,
                              request.resourceIdentifier, "instance.resource.unknown", "Instance is unavailable.");
    }
    const auto folder = *game / folderName;
    std::error_code error;
    std::filesystem::create_directories(folder, error);
    if (error || isSymlink(folder)) {
        return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::Failed, identifier,
                              request.resourceIdentifier, "instance.resource.permission-denied", "Resource folder is unavailable.");
    }

    const auto sourceName = request.resourceIdentifier;
    if (!isSafeComponent(sourceName, 512)) {
        return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::Rejected, identifier,
                              sourceName, "instance.resource.invalid-name", "Resource identifier is invalid.");
    }
    auto missing = [&] {
        return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::UnknownResource, identifier,
                              sourceName, "instance.resource.unknown", "Resource is unavailable.");
    };
    const auto currentOptional = safeChild(
        folder, sourceName, request.action == FrontendInstanceResourceAction::Import);
    if (!currentOptional) {
        return missing();
    }
    const auto current = *currentOptional;

    switch (request.action) {
        case FrontendInstanceResourceAction::Reveal:
            if (!std::filesystem::exists(current) || isSymlink(current)) {
                return missing();
            }
            return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::Succeeded, identifier,
                                  sourceName, "instance.resource.reveal-ready", "Resource path is safe for a system reveal.");
        case FrontendInstanceResourceAction::Delete:
            if (!request.confirmed || !std::filesystem::exists(current) || isSymlink(current)) {
                return request.confirmed ? missing()
                                         : resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::Rejected,
                                                          identifier, sourceName, "instance.resource.confirmation-required",
                                                          "Resource deletion requires confirmation.");
            }
            std::filesystem::remove_all(current, error);
            return resourceResult(kind, request.action,
                                  error ? FrontendInstanceResourceMutationOutcome::Failed
                                         : FrontendInstanceResourceMutationOutcome::Succeeded,
                                  identifier, sourceName,
                                  error ? "instance.resource.permission-denied" : "instance.resource.deleted",
                                  error ? "Resource could not be deleted." : "Resource deleted.");
        case FrontendInstanceResourceAction::Enable:
            if (!sourceName.ends_with(".disabled") || !std::filesystem::exists(current) || isSymlink(current)) {
                return missing();
            }
            {
                const auto destination = folder / sourceName.substr(0, sourceName.size() - std::string(".disabled").size());
                if (std::filesystem::exists(destination, error) || error || isSymlink(destination)) {
                    return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::Failed, identifier,
                                          sourceName, "instance.resource.conflict", "Enabled resource destination already exists.");
                }
                std::filesystem::rename(current, destination, error);
            }
            return resourceResult(kind, request.action,
                                  error ? FrontendInstanceResourceMutationOutcome::Failed
                                         : FrontendInstanceResourceMutationOutcome::Succeeded,
                                  identifier, sourceName,
                                  error ? "instance.resource.permission-denied" : "instance.resource.enabled",
                                  error ? "Resource could not be enabled." : "Resource enabled.");
        case FrontendInstanceResourceAction::Disable:
            if (sourceName.ends_with(".disabled") || !std::filesystem::exists(current) || isSymlink(current)) {
                return missing();
            }
            {
                const auto destination = folder / (sourceName + ".disabled");
                if (std::filesystem::exists(destination, error) || error || isSymlink(destination)) {
                    return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::Failed, identifier,
                                          sourceName, "instance.resource.conflict", "Disabled resource destination already exists.");
                }
                std::filesystem::rename(current, destination, error);
            }
            return resourceResult(kind, request.action,
                                  error ? FrontendInstanceResourceMutationOutcome::Failed
                                         : FrontendInstanceResourceMutationOutcome::Succeeded,
                                  identifier, sourceName,
                                  error ? "instance.resource.permission-denied" : "instance.resource.disabled",
                                  error ? "Resource could not be disabled." : "Resource disabled.");
        case FrontendInstanceResourceAction::Import: {
            if (request.sourcePath.empty() || !request.sourcePath.is_absolute() || isSymlink(request.sourcePath)
                || (!isRegularFile(request.sourcePath) && !isDirectory(request.sourcePath))) {
                return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::Rejected, identifier,
                                      sourceName, "instance.resource.invalid-source", "The selected resource is invalid.");
            }
            if (!pathIsContainedWithoutSymlinks(folder, folder / sourceName) || std::filesystem::exists(current, error)
                || error) {
                return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::Failed, identifier,
                                      sourceName, "instance.resource.conflict", "Resource destination already exists.");
            }
            if (!copyTreeWithoutSymlinks(request.sourcePath, current)) {
                std::filesystem::remove_all(current, error);
                return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::Failed, identifier,
                                      sourceName, "instance.resource.rollback", "Resource import failed and was rolled back.", true);
            }
            return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::Succeeded, identifier,
                                  sourceName, "instance.resource.imported", "Resource imported.");
        }
    }
    return resourceResult(kind, request.action, FrontendInstanceResourceMutationOutcome::Rejected, identifier,
                          sourceName, "instance.resource.invalid-action", "Resource action is unsupported.");
}

std::optional<std::vector<FrontendInstanceWorldSnapshot>> ProductionInstanceDetailRuntime::instanceWorlds(
    const std::string& identifier) const
{
    const auto game = gameRoot(identifier);
    if (!game) {
        return std::nullopt;
    }
    const auto saves = *game / "saves";
    if (!std::filesystem::exists(saves)) {
        return std::vector<FrontendInstanceWorldSnapshot>();
    }
    if (!isDirectory(saves) || isSymlink(saves)) {
        return std::nullopt;
    }
    std::vector<FrontendInstanceWorldSnapshot> result;
    std::error_code error;
    for (const auto& entry : std::filesystem::directory_iterator(saves, error)) {
        if (error) {
            return std::nullopt;
        }
        if (entry.is_symlink(error) || error) {
            error.clear();
            continue;
        }
        const auto filename = entry.path().filename().string();
        if (!isSafeComponent(filename, 512) || (!entry.is_directory(error) && !entry.is_regular_file(error)) || error) {
            error.clear();
            continue;
        }
        const bool archive = entry.is_regular_file(error) && filename.ends_with(".zip");
        if (!archive && !entry.is_directory(error)) {
            error.clear();
            continue;
        }
        FrontendInstanceWorldSnapshot snapshot;
        snapshot.id = filename;
        snapshot.folderName = filename;
        snapshot.name = archive ? filename.substr(0, filename.size() - 4) : filename;
        snapshot.lastPlayedUnixSeconds = unixSeconds(entry.path());
        snapshot.sizeBytes = directorySize(entry.path());
        snapshot.isArchive = archive;
        snapshot.canBeRenamed = !archive;
        snapshot.canBeCopied = true;
        snapshot.canBeDeleted = true;
        snapshot.canBeJoined = !archive && isDirectory(entry.path());
        const auto icon = entry.path() / "icon.png";
        snapshot.hasIcon = isRegularFile(icon) && !isSymlink(icon);
        if (!archive) {
            if (const auto metadata = readWorldMetadata(entry.path())) {
                if (!metadata->name.empty()) {
                    snapshot.name = metadata->name;
                }
                snapshot.gameMode = metadata->gameMode;
                snapshot.lastPlayedUnixSeconds = metadata->lastPlayed;
                snapshot.seed = metadata->seed;
                snapshot.hasSeed = metadata->hasSeed;
            } else {
                snapshot.warningDescription = "World metadata could not be read.";
            }
        }
        result.push_back(std::move(snapshot));
        error.clear();
    }
    return result;
}

std::optional<std::vector<FrontendInstanceServerSnapshot>> ProductionInstanceDetailRuntime::instanceServers(
    const std::string& identifier) const
{
    const auto game = gameRoot(identifier);
    if (!game) {
        return std::nullopt;
    }
    const auto records = readServers(*game / "servers.dat");
    if (!records) {
        return std::nullopt;
    }
    std::vector<FrontendInstanceServerSnapshot> result;
    result.reserve(records->size());
    for (std::size_t index = 0; index < records->size(); ++index) {
        const auto& record = (*records)[index];
        result.push_back({ serverIdentifier(index), record.name, record.address, record.resourcePolicy,
                           FrontendServerStatus::Unknown, -1, true, true, !record.address.empty() });
    }
    return result;
}

std::optional<std::vector<FrontendInstanceScreenshotSnapshot>> ProductionInstanceDetailRuntime::instanceScreenshots(
    const std::string& identifier) const
{
    const auto game = gameRoot(identifier);
    if (!game) {
        return std::nullopt;
    }
    const auto folder = *game / "screenshots";
    if (!std::filesystem::exists(folder)) {
        return std::vector<FrontendInstanceScreenshotSnapshot>();
    }
    if (!isDirectory(folder) || isSymlink(folder)) {
        return std::nullopt;
    }
    std::vector<FrontendInstanceScreenshotSnapshot> result;
    std::error_code error;
    for (const auto& entry : std::filesystem::directory_iterator(folder, error)) {
        if (error) {
            return std::nullopt;
        }
        if (entry.is_symlink(error) || error || !entry.is_regular_file(error) || error) {
            error.clear();
            continue;
        }
        const auto filename = entry.path().filename().string();
        if (!isSafeComponent(filename, 512)
            || !QString::fromStdString(filename).endsWith(".png", Qt::CaseInsensitive)) {
            continue;
        }
        const auto permissions = entry.status(error).permissions();
        const bool readable = !error && (permissions & std::filesystem::perms::owner_read) != std::filesystem::perms::none;
        const bool writable = !error && (permissions & std::filesystem::perms::owner_write) != std::filesystem::perms::none;
        result.push_back({ filename, filename, filename.substr(0, filename.size() - 4), unixSeconds(entry.path()),
                           directorySize(entry.path()), readable, writable });
        error.clear();
    }
    return result;
}

std::optional<std::vector<FrontendInstanceLogFileSnapshot>> ProductionInstanceDetailRuntime::instanceLogFiles(
    const std::string& identifier) const
{
    const auto game = gameRoot(identifier);
    if (!game) {
        return std::nullopt;
    }
    const auto folder = *game / "logs";
    if (!std::filesystem::exists(folder)) {
        return std::vector<FrontendInstanceLogFileSnapshot>();
    }
    if (!isDirectory(folder) || isSymlink(folder)) {
        return std::nullopt;
    }
    std::vector<FrontendInstanceLogFileSnapshot> result;
    std::error_code error;
    for (const auto& entry : std::filesystem::directory_iterator(folder, error)) {
        if (error) {
            return std::nullopt;
        }
        if (entry.is_symlink(error) || error || !entry.is_regular_file(error) || error) {
            error.clear();
            continue;
        }
        const auto filename = entry.path().filename().string();
        if (!isSafeComponent(filename, 512)) {
            continue;
        }
        const bool current = filename == "latest.log";
        const bool compressed = filename.ends_with(".gz");
        result.push_back({ filename, filename, filename, unixSeconds(entry.path()), directorySize(entry.path()), compressed,
                           current, true, !current });
        error.clear();
    }
    return result;
}

std::optional<FrontendInstanceLogSnapshot> ProductionInstanceDetailRuntime::instanceLog(
    const std::string& identifier, const std::string& logIdentifier) const
{
    const auto game = gameRoot(identifier);
    if (!game || !isSafeComponent(logIdentifier, 512)) {
        return std::nullopt;
    }
    const auto folder = *game / "logs";
    const auto path = safeChild(folder, logIdentifier, false);
    if (!path || !isRegularFile(*path) || isSymlink(*path)) {
        return std::nullopt;
    }
    const auto bytes = readBytes(*path);
    if (!bytes) {
        return std::nullopt;
    }
    QByteArray content = *bytes;
    if (logIdentifier.ends_with(".gz")) {
        QByteArray uncompressed;
        if (!GZip::unzip(content, uncompressed)) {
            return std::nullopt;
        }
        content = std::move(uncompressed);
    }
    const bool inputTruncated = content.size() > static_cast<qsizetype>(kFrontendLogMaxBytes);
    QByteArray bounded = content;
    if (inputTruncated) {
        bounded = bounded.right(static_cast<qsizetype>(kFrontendLogMaxBytes));
    }
    const auto lines = bounded.split('\n');
    FrontendInstanceLogSnapshot snapshot;
    snapshot.instanceIdentifier = identifier;
    snapshot.logIdentifier = logIdentifier;
    snapshot.truncated = inputTruncated;
    std::size_t start = lines.size() > kFrontendLogMaxEntries ? lines.size() - kFrontendLogMaxEntries : 0;
    snapshot.droppedEntryCount = start;
    snapshot.truncated = snapshot.truncated || start > 0;
    for (std::size_t index = start; index < static_cast<std::size_t>(lines.size()); ++index) {
        auto line = redactLog(lines[static_cast<qsizetype>(index)].toStdString());
        bool truncated = false;
        if (line.size() > kFrontendLogMaxBytes) {
            line.resize(kFrontendLogMaxBytes);
            truncated = true;
        }
        snapshot.entries.push_back({ static_cast<std::uint64_t>(index - start), std::move(line), truncated });
        snapshot.truncated = snapshot.truncated || truncated;
    }
    for (const auto& entry : snapshot.entries) {
        snapshot.totalByteCount += entry.text.size();
    }
    return snapshot;
}

FrontendInstanceDetailMutationResult ProductionInstanceDetailRuntime::mutateInstanceDetail(
    const std::string& identifier, const FrontendInstanceDetailMutationRequest& request)
{
    std::lock_guard<std::mutex> lock(m_mutationMutex);
    const auto instance = instancePath(identifier);
    if (!instance) {
        return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::UnknownInstance, identifier,
                            request.itemIdentifier, "instance.detail.unknown", "Instance is unavailable.");
    }

    if (request.kind == FrontendInstanceDetailKind::Servers) {
        const auto game = gameRoot(identifier);
        if (!game) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::UnknownInstance, identifier,
                                request.itemIdentifier, "instance.detail.unknown", "Instance game directory is unavailable.");
        }
        const auto path = *game / "servers.dat";
        auto records = readServers(path);
        if (!records) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Failed, identifier,
                                request.itemIdentifier, "instance.server.invalid-file", "servers.dat could not be parsed.");
        }
        const int index = serverIndex(request.itemIdentifier);
        if (request.action == FrontendInstanceDetailAction::Add) {
            records->push_back({ request.name, request.address, request.resourcePolicy });
        } else if (index < 0 || static_cast<std::size_t>(index) >= records->size()) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::UnknownItem, identifier,
                                request.itemIdentifier, "instance.server.unknown", "Server entry is unavailable.");
        } else if (request.action == FrontendInstanceDetailAction::Update) {
            (*records)[index] = { request.name, request.address, request.resourcePolicy };
        } else if (request.action == FrontendInstanceDetailAction::Delete) {
            records->erase(records->begin() + index);
        } else if (request.action == FrontendInstanceDetailAction::MoveUp) {
            if (index == 0) {
                return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                    request.itemIdentifier, "instance.server.boundary", "Server is already first.");
            }
            std::swap((*records)[index], (*records)[index - 1]);
        } else if (request.action == FrontendInstanceDetailAction::MoveDown) {
            if (static_cast<std::size_t>(index + 1) >= records->size()) {
                return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                    request.itemIdentifier, "instance.server.boundary", "Server is already last.");
            }
            std::swap((*records)[index], (*records)[index + 1]);
        } else if (request.action == FrontendInstanceDetailAction::Join) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                request.itemIdentifier, "instance.server.join-unavailable", "Server joining remains an external launch action.");
        } else {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                request.itemIdentifier, "instance.server.invalid-action", "Server action is unsupported.");
        }
        if (!writeServers(path, *records)) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Failed, identifier,
                                request.itemIdentifier, "instance.server.rollback", "Server change could not be saved; no partial file was committed.", true);
        }
        const auto resultIdentifier = request.action == FrontendInstanceDetailAction::Add
            ? serverIdentifier(records->size() - 1)
            : request.itemIdentifier;
        return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Succeeded, identifier,
                            resultIdentifier, "instance.server.saved", "Server list saved.");
    }

    const auto game = gameRoot(identifier);
    if (!game) {
        return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::UnknownInstance, identifier,
                            request.itemIdentifier, "instance.detail.unknown", "Instance game directory is unavailable.");
    }

    std::filesystem::path folder;
    switch (request.kind) {
        case FrontendInstanceDetailKind::Worlds:
            folder = *game / "saves";
            break;
        case FrontendInstanceDetailKind::Screenshots:
            folder = *game / "screenshots";
            break;
        case FrontendInstanceDetailKind::Logs:
            folder = *game / "logs";
            break;
        case FrontendInstanceDetailKind::Servers:
            break;
    }
    std::error_code error;
    std::filesystem::create_directories(folder, error);
    if (error || isSymlink(folder)) {
        return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Failed, identifier,
                            request.itemIdentifier, "instance.detail.permission-denied", "Detail folder is unavailable.");
    }
    const auto path = safeChild(folder, request.itemIdentifier, false);
    if (!path && request.action != FrontendInstanceDetailAction::Import) {
        return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::UnknownItem, identifier,
                            request.itemIdentifier, "instance.detail.unknown", "Detail item is unavailable.");
    }

    if (request.kind == FrontendInstanceDetailKind::Logs) {
        if (request.action == FrontendInstanceDetailAction::Delete) {
            if (!request.confirmed || request.itemIdentifier == "latest.log") {
                return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                    request.itemIdentifier, "instance.log.protected", "The current log cannot be deleted without a retained run.");
            }
            std::filesystem::remove(*path, error);
            return detailResult(request.kind, request.action,
                                error ? FrontendInstanceDetailMutationOutcome::Failed
                                       : FrontendInstanceDetailMutationOutcome::Succeeded,
                                identifier, request.itemIdentifier,
                                error ? "instance.detail.permission-denied" : "instance.log.deleted",
                                error ? "Log file could not be deleted." : "Log file deleted.");
        }
        if (request.action == FrontendInstanceDetailAction::Open || request.action == FrontendInstanceDetailAction::Reveal) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Succeeded, identifier,
                                request.itemIdentifier, "instance.log.action-ready", "Log file is safe for a system action.");
        }
        return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                            request.itemIdentifier, "instance.log.invalid-action", "Log action is unsupported.");
    }

    if (request.kind == FrontendInstanceDetailKind::Screenshots) {
        if (request.action == FrontendInstanceDetailAction::Delete) {
            if (!request.confirmed) {
                return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                    request.itemIdentifier, "instance.screenshot.confirmation-required", "Screenshot deletion requires confirmation.");
            }
            std::filesystem::remove(*path, error);
        } else if (request.action == FrontendInstanceDetailAction::Rename) {
            if (!isSafeComponent(request.targetName, 512) || !request.targetName.ends_with(".png")) {
                return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                    request.itemIdentifier, "instance.screenshot.invalid-name", "Screenshot names must be safe PNG filenames.");
            }
            const auto destination = *safeChild(folder, request.targetName, true);
            if (std::filesystem::exists(destination, error) || error) {
                return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Failed, identifier,
                                    request.itemIdentifier, "instance.screenshot.conflict", "Screenshot destination already exists.");
            }
            std::filesystem::rename(*path, destination, error);
        } else if (request.action == FrontendInstanceDetailAction::Open || request.action == FrontendInstanceDetailAction::Reveal
                   || request.action == FrontendInstanceDetailAction::CopyImage || request.action == FrontendInstanceDetailAction::CopyFiles) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Succeeded, identifier,
                                request.itemIdentifier, "instance.screenshot.action-ready", "Screenshot is safe for a system action.");
        } else {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                request.itemIdentifier, "instance.screenshot.invalid-action", "Screenshot action is unsupported.");
        }
        return detailResult(request.kind, request.action,
                            error ? FrontendInstanceDetailMutationOutcome::Failed
                                   : FrontendInstanceDetailMutationOutcome::Succeeded,
                            identifier, request.itemIdentifier,
                            error ? "instance.detail.permission-denied" : "instance.screenshot.saved",
                            error ? "Screenshot change could not be saved." : "Screenshot change saved.");
    }

    if (request.action == FrontendInstanceDetailAction::Delete) {
        if (!request.confirmed) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                request.itemIdentifier, "instance.world.confirmation-required", "World deletion requires confirmation.");
        }
        std::filesystem::remove_all(*path, error);
    } else if (request.action == FrontendInstanceDetailAction::Rename || request.action == FrontendInstanceDetailAction::Copy) {
        if (!isSafeComponent(request.targetName, 512)) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                request.itemIdentifier, "instance.world.invalid-name", "World name is invalid.");
        }
        const auto destination = *safeChild(folder, request.targetName, true);
        if (std::filesystem::exists(destination, error) || error) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Failed, identifier,
                                request.itemIdentifier, "instance.world.conflict", "World destination already exists.");
        }
        if (request.action == FrontendInstanceDetailAction::Copy) {
            if (!copyTreeWithoutSymlinks(*path, destination)) {
                std::filesystem::remove_all(destination, error);
                return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Failed, identifier,
                                    request.itemIdentifier, "instance.world.rollback", "World copy failed and was rolled back.", true);
            }
        } else {
            std::filesystem::rename(*path, destination, error);
        }
    } else if (request.action == FrontendInstanceDetailAction::ResetIcon) {
        const auto icon = *path / "icon.png";
        if (!isRegularFile(icon) || isSymlink(icon)) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::UnknownItem, identifier,
                                request.itemIdentifier, "instance.world.icon-missing", "World icon is unavailable.");
        }
        std::filesystem::remove(icon, error);
    } else if (request.action == FrontendInstanceDetailAction::Import) {
        if (request.sourcePath.empty() || !request.sourcePath.is_absolute() || isSymlink(request.sourcePath)
            || (!isDirectory(request.sourcePath) && !isRegularFile(request.sourcePath))) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                request.itemIdentifier, "instance.world.invalid-source", "The selected world is invalid.");
        }
        if (!isSafeComponent(request.itemIdentifier, 512)) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                request.itemIdentifier, "instance.world.invalid-name", "World import name is invalid.");
        }
        const auto destination = *safeChild(folder, request.itemIdentifier, true);
        if (std::filesystem::exists(destination, error) || error) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Failed, identifier,
                                request.itemIdentifier, "instance.world.conflict", "World destination already exists.");
        }
        const auto extension = QString::fromStdString(request.sourcePath.extension().string()).toLower();
        bool archiveCancelled = false;
        const bool isArchive = extension == ".zip";
        if (isRegularFile(request.sourcePath) && !isArchive) {
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                request.itemIdentifier, "instance.world.invalid-source", "World files must be directories or ZIP archives.");
        }
        if (isArchive) {
            std::filesystem::create_directory(destination, error);
            if (error) {
                return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Failed, identifier,
                                    request.itemIdentifier, "instance.world.rollback", "World archive staging could not be created.", true);
            }
        }
        const bool imported = isArchive
            ? extractWorldArchive(request.sourcePath, destination, {}, archiveCancelled)
            : isDirectory(request.sourcePath) && copyTreeWithoutSymlinks(request.sourcePath, destination);
        if (isArchive && !imported && !archiveCancelled) {
            std::filesystem::remove_all(destination, error);
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                                request.itemIdentifier, "instance.world.invalid-archive", "The selected world archive is invalid or does not contain level.dat.");
        }
        if (!imported) {
            std::filesystem::remove_all(destination, error);
            return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Failed, identifier,
                                request.itemIdentifier, "instance.world.rollback", "World import failed and was rolled back.", true);
        }
    } else if (request.action == FrontendInstanceDetailAction::Reveal) {
        return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Succeeded, identifier,
                            request.itemIdentifier, "instance.world.action-ready", "World is safe for a system reveal.");
    } else if (request.action == FrontendInstanceDetailAction::Join) {
        return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                            request.itemIdentifier, "instance.world.join-unavailable", "World joining remains an external launch action.");
    } else {
        return detailResult(request.kind, request.action, FrontendInstanceDetailMutationOutcome::Rejected, identifier,
                            request.itemIdentifier, "instance.world.invalid-action", "World action is unsupported.");
    }

    return detailResult(request.kind, request.action,
                        error ? FrontendInstanceDetailMutationOutcome::Failed
                               : FrontendInstanceDetailMutationOutcome::Succeeded,
                        identifier, request.itemIdentifier,
                        error ? "instance.detail.permission-denied" : "instance.world.saved",
                        error ? "World change could not be saved." : "World change saved.");
}

FrontendInstanceNotesUpdateResult ProductionInstanceDetailRuntime::updateInstanceNotes(
    const std::string& identifier, const std::string& notes)
{
    std::lock_guard<std::mutex> lock(m_mutationMutex);
    const auto instance = instancePath(identifier);
    if (!instance) {
        return { FrontendInstanceNotesUpdateOutcome::UnknownInstance, {} };
    }
    if (!isSafeText(notes, 65536)) {
        return { FrontendInstanceNotesUpdateOutcome::Rejected, {} };
    }
    auto settings = readINI(*instance / "instance.cfg");
    if (!settings) {
        return { FrontendInstanceNotesUpdateOutcome::Rejected, {} };
    }
    settings->set("notes", QString::fromStdString(notes));
    if (!settings->saveFile(QString::fromStdString((*instance / "instance.cfg").string()))) {
        return { FrontendInstanceNotesUpdateOutcome::Rejected, {} };
    }
    return { FrontendInstanceNotesUpdateOutcome::Succeeded, notes };
}

FrontendInstanceDeleteResult ProductionInstanceDetailRuntime::deleteInstance(
    const std::string& identifier, bool confirmed)
{
    if (!confirmed) {
        return { FrontendInstanceDeleteOutcome::Rejected,
                 identifier,
                 "instances.delete.confirmation-required",
                 "Deleting an instance requires explicit confirmation.",
                 false,
                 false };
    }
    if (!isSafeComponent(identifier)) {
        return { FrontendInstanceDeleteOutcome::Rejected,
                 identifier,
                 "instances.delete.invalid-identifier",
                 "The instance identifier is invalid.",
                 false,
                 false };
    }

    std::lock_guard<std::mutex> lock(m_mutationMutex);
    const auto instance = instancePath(identifier);
    if (!instance) {
        return { FrontendInstanceDeleteOutcome::UnknownInstance,
                 identifier,
                 "instances.delete.unknown-instance",
                 "The instance is no longer available.",
                 false,
                 false };
    }

    const auto trashRoot = m_instancesRoot / ".prism-native-trash";
    std::error_code error;
    if (std::filesystem::exists(trashRoot, error)) {
        if (error || isSymlink(trashRoot) || !isDirectory(trashRoot)) {
            return { FrontendInstanceDeleteOutcome::Failed,
                     identifier,
                     "instances.delete.recovery-unavailable",
                     "The isolated recovery directory is unavailable.",
                     true,
                     false };
        }
    } else {
        std::filesystem::create_directory(trashRoot, error);
        if (error || isSymlink(trashRoot) || !isDirectory(trashRoot)) {
            return { FrontendInstanceDeleteOutcome::Failed,
                     identifier,
                     "instances.delete.recovery-unavailable",
                     "The isolated recovery directory could not be created.",
                     true,
                     false };
        }
    }

    auto recoveryPath = trashRoot / identifier;
    for (std::size_t suffix = 2; std::filesystem::exists(recoveryPath, error); ++suffix) {
        if (error) {
            return { FrontendInstanceDeleteOutcome::Failed,
                     identifier,
                     "instances.delete.recovery-unavailable",
                     "The isolated recovery directory could not be inspected.",
                     true,
                     false };
        }
        recoveryPath = trashRoot / (identifier + "-" + std::to_string(suffix));
    }
    if (error || !pathIsContainedWithoutSymlinks(trashRoot, recoveryPath)) {
        return { FrontendInstanceDeleteOutcome::Failed,
                 identifier,
                 "instances.delete.recovery-unavailable",
                 "The isolated recovery destination is unsafe.",
                 true,
                 false };
    }

    std::filesystem::rename(*instance, recoveryPath, error);
    if (error) {
        return { FrontendInstanceDeleteOutcome::Failed,
                 identifier,
                 "instances.delete.permission-denied",
                 "The instance could not be moved to the isolated recovery directory.",
                 true,
                 false };
    }

    return { FrontendInstanceDeleteOutcome::Succeeded,
             identifier,
             "instances.delete.succeeded",
             "The instance was moved to the isolated recovery directory.",
             false,
             false };
}

FrontendInstanceCopyResult ProductionInstanceDetailRuntime::copyInstance(
    const FrontendInstanceCopyRequest& request,
    const FrontendRuntimeDependencies::InstanceCopyProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::InstanceCopyCancellationCheck& cancellationCheck)
{
    std::lock_guard<std::mutex> lock(m_mutationMutex);
    const auto source = instancePath(request.sourceInstanceIdentifier);
    const auto taskIdentifier = "instance-copy." + request.sourceInstanceIdentifier;
    const auto reportProgress = [&](FrontendTaskState state,
                          double fraction,
                          bool cancellationAllowed,
                          std::optional<FrontendTaskTerminalResult> terminal = std::nullopt) {
        if (progressHandler) {
            progressHandler(operationProgress(
                taskIdentifier, "Copying Instance", state, FrontendTaskProgressKind::Determinate, fraction,
                cancellationAllowed, std::move(terminal)));
        }
    };
    const auto cancelled = [&] { return cancellationCheck && cancellationCheck(); };
    const auto failed = [&](std::string key, std::string diagnostic, bool rolledBack) {
        reportProgress(FrontendTaskState::Failed, 1.0, false,
             FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Failed, key, {}, diagnostic, rolledBack });
        return FrontendInstanceCopyResult{ FrontendInstanceCopyOutcome::Failed, std::nullopt,
                                           std::move(key), std::move(diagnostic), true, rolledBack };
    };
    const auto cancelledResult = [&] {
        reportProgress(FrontendTaskState::Cancelled, 1.0, false,
             FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Cancelled, "instances.copy.cancelled", {},
                                         "Instance copy was cancelled.", true });
        return FrontendInstanceCopyResult{ FrontendInstanceCopyOutcome::Cancelled, std::nullopt,
                                           "instances.copy.cancelled", "Instance copy was cancelled.", true, true };
    };

    if (!source) {
        return failed("instances.copy.source-missing", "The source instance is unavailable.", false);
    }
    if (!isSafeText(request.name, 512, false) || !isSafeText(request.groupId, 512)
        || !isSafeText(request.iconKey, 256, false)) {
        return { FrontendInstanceCopyOutcome::Rejected, std::nullopt, "instances.copy.invalid-metadata",
                 "The copied instance metadata is invalid.", false, false };
    }
    if (request.options.useSymbolicLinks || request.options.useHardLinks || request.options.useClone) {
        return { FrontendInstanceCopyOutcome::Rejected, std::nullopt, "instances.copy.link-policy-unsupported",
                 "Native instance copies use safe regular-file copies; link and clone policies are not enabled.",
                 false, false };
    }
    if (cancelled()) {
        return cancelledResult();
    }

    std::string identifier = copyIdentifierBase(request.name);
    for (std::size_t suffix = 2; instancePath(identifier).has_value(); ++suffix) {
        identifier = copyIdentifierBase(request.name) + "-" + std::to_string(suffix);
    }
    const auto destination = m_instancesRoot / identifier;
    const auto staging = m_instancesRoot / ("." + identifier + ".staging");
    std::error_code error;
    if (std::filesystem::exists(staging, error) || error) {
        return failed("instances.copy.staging-conflict", "The copy staging directory already exists.", false);
    }

    reportProgress(FrontendTaskState::Running, 0.0, true);
    std::filesystem::create_directory(staging, error);
    if (error || isSymlink(staging) || !copyTreeWithoutSymlinks(*source, staging, cancelled)) {
        const bool wasCancelled = cancelled();
        std::filesystem::remove_all(staging, error);
        return wasCancelled ? cancelledResult()
                            : failed("instances.copy.rollback", "Instance copy failed and was rolled back.", true);
    }

    const auto stagedGame = gameRootFor(staging);
    if (!stagedGame) {
        std::filesystem::remove_all(staging, error);
        return failed("instances.copy.rollback", "The copied game directory is unsafe; the copy was rolled back.", true);
    }
    const auto removeOptional = [&](const std::filesystem::path& path) {
        if (!std::filesystem::exists(path, error)) {
            error.clear();
            return true;
        }
        std::filesystem::remove_all(path, error);
        return !error;
    };
    const auto& options = request.options;
    if ((!options.copySaves && !removeOptional(*stagedGame / "saves"))
        || (!options.copyGameOptions && !removeOptional(*stagedGame / "options.txt"))
        || (!options.copyResourcePacks && !removeOptional(*stagedGame / "resourcepacks"))
        || (!options.copyShaderPacks && !removeOptional(*stagedGame / "shaderpacks"))
        || (!options.copyServers && !removeOptional(*stagedGame / "servers.dat"))
        || (!options.copyMods && !removeOptional(*stagedGame / "mods"))
        || (!options.copyScreenshots && !removeOptional(*stagedGame / "screenshots"))) {
        std::filesystem::remove_all(staging, error);
        return failed("instances.copy.rollback", "Optional instance data could not be filtered; the copy was rolled back.", true);
    }

    auto settings = readINI(staging / "instance.cfg");
    if (!settings) {
        std::filesystem::remove_all(staging, error);
        return failed("instances.copy.rollback", "The copied instance metadata could not be read; the copy was rolled back.", true);
    }
    settings->set("name", QString::fromStdString(request.name));
    settings->set("iconKey", QString::fromStdString(request.iconKey));
    settings->set("InstanceGroupId", QString::fromStdString(request.groupId));
    if (!options.keepPlaytime) {
        settings->set("totalTimePlayed", 0);
    }
    if (!settings->saveFile(QString::fromStdString((staging / "instance.cfg").string()))) {
        std::filesystem::remove_all(staging, error);
        return failed("instances.copy.rollback", "The copied instance metadata could not be saved; the copy was rolled back.", true);
    }
    if (cancelled()) {
        std::filesystem::remove_all(staging, error);
        return cancelledResult();
    }

    std::filesystem::rename(staging, destination, error);
    if (error) {
        std::filesystem::remove_all(staging, error);
        return failed("instances.copy.rollback", "The copied instance could not be committed; the copy was rolled back.", true);
    }
    const auto summary = FrontendInstanceSnapshot{ identifier, request.name, request.iconKey, request.groupId };
    reportProgress(FrontendTaskState::Succeeded, 1.0, false,
         FrontendTaskTerminalResult{ FrontendTaskTerminalOutcome::Succeeded, "instances.copy.succeeded", {},
                                     "Instance copy completed.", false });
    return { FrontendInstanceCopyOutcome::Succeeded, summary, "instances.copy.succeeded",
             "Instance copy completed.", false, false };
}

FrontendInstanceExportResult ProductionInstanceDetailRuntime::exportInstance(
    const FrontendInstanceExportRequest& request,
    const FrontendRuntimeDependencies::InstanceExportProgressHandler& progressHandler,
    const FrontendRuntimeDependencies::InstanceExportCancellationCheck& cancellationCheck)
{
    std::lock_guard<std::mutex> lock(m_mutationMutex);
    const auto source = instancePath(request.sourceInstanceIdentifier);
    const auto taskIdentifier = "instance-export." + request.sourceInstanceIdentifier;
    const auto reportProgress = [&](FrontendTaskState state,
                          double fraction,
                          bool cancellationAllowed,
                          std::optional<FrontendTaskTerminalResult> terminal = std::nullopt) {
        if (progressHandler) {
            progressHandler(operationProgress(
                taskIdentifier, "Exporting Instance", state, FrontendTaskProgressKind::Determinate, fraction,
                cancellationAllowed, std::move(terminal)));
        }
    };
    const auto cancelled = [&] { return cancellationCheck && cancellationCheck(); };
    const auto result = [&](FrontendInstanceExportOutcome outcome,
                            std::string key,
                            std::string diagnostic,
                            bool retryable,
                            bool rolledBack) {
        if (outcome != FrontendInstanceExportOutcome::Rejected) {
            const auto terminalOutcome = outcome == FrontendInstanceExportOutcome::Succeeded
                ? FrontendTaskTerminalOutcome::Succeeded
                : outcome == FrontendInstanceExportOutcome::Cancelled ? FrontendTaskTerminalOutcome::Cancelled
                                                                        : FrontendTaskTerminalOutcome::Failed;
            reportProgress(outcome == FrontendInstanceExportOutcome::Succeeded ? FrontendTaskState::Succeeded
                                                                      : outcome == FrontendInstanceExportOutcome::Cancelled
                                                                          ? FrontendTaskState::Cancelled
                                                                          : FrontendTaskState::Failed,
                 1.0, false,
                 FrontendTaskTerminalResult{ terminalOutcome, key, {}, diagnostic, rolledBack });
        }
        return FrontendInstanceExportResult{ request.kind, outcome, request.destinationPath, std::move(key),
                                             std::move(diagnostic), retryable, rolledBack };
    };

    if (!source) {
        return result(FrontendInstanceExportOutcome::Failed, "instances.export.source-missing",
                      "The source instance is unavailable.", true, false);
    }
    if (!request.destinationPath.is_absolute() || pathIsContainedWithoutSymlinks(*source, request.destinationPath)) {
        return result(FrontendInstanceExportOutcome::Rejected, "instances.export.invalid-destination",
                      "The export destination is invalid or inside the source instance.", false, false);
    }
    std::error_code error;
    const auto parent = request.destinationPath.lexically_normal().parent_path();
    std::filesystem::create_directories(parent, error);
    const auto canonicalParent = std::filesystem::weakly_canonical(parent, error);
    if (error || canonicalParent.empty() || std::filesystem::exists(request.destinationPath, error)) {
        return result(FrontendInstanceExportOutcome::Failed, "instances.export.destination-conflict",
                      "The export destination is unavailable or already exists.", true, false);
    }
    if (cancelled()) {
        return result(FrontendInstanceExportOutcome::Cancelled, "instances.export.cancelled",
                      "Instance export was cancelled.", true, true);
    }

    reportProgress(FrontendTaskState::Running, 0.0, true);
    std::vector<std::pair<std::filesystem::path, std::string>> files;
    if (request.kind == FrontendInstanceExportKind::ZipArchive) {
        if (!collectRegularFiles(*source, files, cancelled)) {
            const bool wasCancelled = cancelled();
            return result(wasCancelled ? FrontendInstanceExportOutcome::Cancelled : FrontendInstanceExportOutcome::Failed,
                          wasCancelled ? "instances.export.cancelled" : "instances.export.rollback",
                          wasCancelled ? "Instance export was cancelled." : "Instance export rejected a symlink or unreadable file.",
                          true, true);
        }
    }

    const auto temporary = parent / ("." + request.destinationPath.filename().string() + ".prism-export.staging");
    if (std::filesystem::exists(temporary, error) || error || isSymlink(temporary)) {
        return result(FrontendInstanceExportOutcome::Failed, "instances.export.staging-conflict",
                      "The export staging file already exists.", true, false);
    }

    QByteArray output;
    if (request.kind == FrontendInstanceExportKind::ZipArchive) {
        MMCZip::ArchiveWriter archive(QString::fromStdString(temporary.string()));
        if (!archive.open()) {
            return result(FrontendInstanceExportOutcome::Failed, "instances.export.open-failed",
                          "The ZIP archive could not be opened.", true, true);
        }
        const double total = files.empty() ? 1.0 : static_cast<double>(files.size());
        for (std::size_t index = 0; index < files.size(); ++index) {
            if (cancelled()) {
                archive.close();
                std::filesystem::remove(temporary, error);
                return result(FrontendInstanceExportOutcome::Cancelled, "instances.export.cancelled",
                              "Instance export was cancelled.", true, true);
            }
            if (!archive.addFile(QString::fromStdString(files[index].first.string()),
                                 QString::fromStdString(files[index].second))) {
                archive.close();
                std::filesystem::remove(temporary, error);
                return result(FrontendInstanceExportOutcome::Failed, "instances.export.rollback",
                              "The ZIP archive could not be completed and was rolled back.", true, true);
            }
            reportProgress(FrontendTaskState::Running, static_cast<double>(index + 1) / total, true);
        }
        if (!archive.close()) {
            std::filesystem::remove(temporary, error);
            return result(FrontendInstanceExportOutcome::Failed, "instances.export.rollback",
                          "The ZIP archive could not be finalized and was rolled back.", true, true);
        }
    } else {
        const auto resources = instanceResources(request.sourceInstanceIdentifier, FrontendInstanceResourceKind::Mods);
        if (!resources) {
            return result(FrontendInstanceExportOutcome::Failed, "instances.export.mods-unavailable",
                          "The mod list could not be read.", true, false);
        }
        if (request.modListFormat == FrontendModListExportFormat::JSON) {
            QJsonArray rows;
            for (const auto& resource : *resources) {
                QJsonObject row;
                row.insert("name", QString::fromStdString(resource.name));
                row.insert("filename", QString::fromStdString(resource.fileName));
                rows.append(row);
            }
            output = QJsonDocument(rows).toJson(QJsonDocument::Indented);
        } else if (request.modListFormat == FrontendModListExportFormat::CSV) {
            output = "Name,Filename\n";
            for (const auto& resource : *resources) {
                output += QByteArray::fromStdString(csvValue(resource.name) + "," + csvValue(resource.fileName) + "\n");
            }
        } else {
            std::string text;
            for (const auto& resource : *resources) {
                const auto name = resource.name;
                const auto filename = resource.fileName;
                if (request.modListFormat == FrontendModListExportFormat::HTML) {
                    text += "<li><span>" + QString::fromStdString(name).toHtmlEscaped().toStdString()
                        + "</span> <code>" + QString::fromStdString(filename).toHtmlEscaped().toStdString()
                        + "</code></li>\n";
                } else if (request.modListFormat == FrontendModListExportFormat::Markdown) {
                    text += "- " + name + " (" + filename + ")\n";
                } else if (request.modListFormat == FrontendModListExportFormat::Custom) {
                    auto row = request.customTemplate;
                    row = replaceAll(std::move(row), "{name}", name);
                    row = replaceAll(std::move(row), "{filename}", filename);
                    row = replaceAll(std::move(row), "{version}", "");
                    row = replaceAll(std::move(row), "{url}", "");
                    row = replaceAll(std::move(row), "{authors}", "");
                    text += row;
                    text.push_back('\n');
                } else {
                    text += name + " (" + filename + ")\n";
                }
            }
            if (request.modListFormat == FrontendModListExportFormat::HTML) {
                text = "<ul>\n" + text + "</ul>\n";
            }
            output = QByteArray::fromStdString(text);
        }
        if (!writeBytesAtomically(temporary, output)) {
            return result(FrontendInstanceExportOutcome::Failed, "instances.export.rollback",
                          "The mod-list export could not be written and was rolled back.", true, true);
        }
    }

    if (cancelled()) {
        std::filesystem::remove(temporary, error);
        return result(FrontendInstanceExportOutcome::Cancelled, "instances.export.cancelled",
                      "Instance export was cancelled.", true, true);
    }
    std::filesystem::rename(temporary, request.destinationPath, error);
    if (error) {
        std::filesystem::remove(temporary, error);
        return result(FrontendInstanceExportOutcome::Failed, "instances.export.rollback",
                      "The export could not be committed and was rolled back.", true, true);
    }
    return result(FrontendInstanceExportOutcome::Succeeded, "instances.export.succeeded",
                  "Instance export completed.", false, false);
}

std::shared_ptr<ProductionInstanceDetailRuntime> makeProductionInstanceDetailRuntime(std::filesystem::path dataRoot)
{
    return std::make_shared<ProductionInstanceDetailRuntime>(std::move(dataRoot));
}
