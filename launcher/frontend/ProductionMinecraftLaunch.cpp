// SPDX-License-Identifier: GPL-3.0-only

#include "ProductionMinecraftLaunch.h"

#include "Commandline.h"
#include "Exception.h"
#include "RuntimeContext.h"
#include "SysInfo.h"
#include "BuildConfig.h"
#include "java/JavaVersion.h"
#include "minecraft/LaunchProfile.h"
#include "minecraft/OneSixVersionFormat.h"
#include "minecraft/VersionFile.h"
#include "settings/INIFile.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QMap>
#include <QMetaType>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QStringList>
#include <QVariant>

#include <algorithm>
#include <filesystem>
#include <map>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

bool isSymlink(const std::filesystem::path& path)
{
    std::error_code error;
    return std::filesystem::is_symlink(std::filesystem::symlink_status(path, error)) && !error;
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

bool isContained(const std::filesystem::path& root, const std::filesystem::path& candidate)
{
    const auto relative = candidate.lexically_normal().lexically_relative(root.lexically_normal());
    if (relative.empty() || relative.is_absolute() || relative.has_root_path()) {
        return false;
    }
    return std::none_of(relative.begin(), relative.end(), [](const auto& component) {
        return component == "..";
    });
}

bool safeIdentifier(const std::string& value)
{
    return !value.empty() && value.size() <= 255 && value != "." && value != ".."
        && std::all_of(value.begin(), value.end(), [](unsigned char character) {
               return character >= 0x20 && character != '/' && character != '\\' && character != 0x7f;
           });
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

QVariant firstValue(const INIFile& instance, const INIFile& global, const char* key, QVariant fallback = {})
{
    const QString qKey = QString::fromUtf8(key);
    if (instance.contains(qKey)) {
        return instance.value(qKey);
    }
    if (global.contains(qKey)) {
        return global.value(qKey);
    }
    return fallback;
}

QString stringValue(const INIFile& instance, const INIFile& global, const char* key, QString fallback = {})
{
    return firstValue(instance, global, key, std::move(fallback)).toString().trimmed();
}

int intValue(const INIFile& instance, const INIFile& global, const char* key, int fallback)
{
    bool ok = false;
    const int value = firstValue(instance, global, key, fallback).toInt(&ok);
    return ok ? value : fallback;
}

bool boolValue(const INIFile& instance, const INIFile& global, const char* key, bool fallback)
{
    const QVariant value = firstValue(instance, global, key, fallback);
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
    return fallback;
}

std::vector<std::string> commandArguments(const QString& value)
{
    std::vector<std::string> result;
    for (const auto& argument : Commandline::splitArgs(value)) {
        result.push_back(argument.toStdString());
    }
    return result;
}

QString replaceTokensIn(const QString& text, const QMap<QString, QString>& mapping)
{
    static const QRegularExpression tokenExpression(
        QStringLiteral("\\$\\{(.+)\\}"), QRegularExpression::InvertedGreedinessOption);
    QString result;
    auto iterator = tokenExpression.globalMatch(text);
    int lastCapturedEnd = 0;
    while (iterator.hasNext()) {
        const auto match = iterator.next();
        result.append(text.mid(lastCapturedEnd, match.capturedStart() - lastCapturedEnd));
        const auto found = mapping.constFind(match.captured(1));
        if (found != mapping.constEnd()) {
            result.append(*found);
        }
        lastCapturedEnd = match.capturedEnd();
    }
    result.append(text.mid(lastCapturedEnd));
    return result;
}

std::optional<std::shared_ptr<LaunchProfile>> loadLaunchProfile(
    const std::filesystem::path& instancePath, const RuntimeContext& runtimeContext, std::string& diagnostic)
{
    const auto componentsPath = instancePath / "mmc-pack.json";
    if (isSymlink(componentsPath) || !isRegularFile(componentsPath)) {
        diagnostic = "The instance component file is unavailable.";
        return std::nullopt;
    }

    QFile componentsFile(QString::fromStdString(componentsPath.string()));
    if (!componentsFile.open(QIODevice::ReadOnly)) {
        diagnostic = "The instance component file could not be read.";
        return std::nullopt;
    }
    QJsonParseError parseError{};
    const auto document = QJsonDocument::fromJson(componentsFile.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        diagnostic = "The instance component file is not valid JSON.";
        return std::nullopt;
    }

    const auto root = document.object();
    if (root.value(QStringLiteral("formatVersion")).toInt(-1) != 1
        || !root.value(QStringLiteral("components")).isArray()) {
        diagnostic = "The instance component file uses an unsupported format.";
        return std::nullopt;
    }

    auto profile = std::make_shared<LaunchProfile>();
    const auto patchesRoot = instancePath / "patches";
    for (const auto& componentValue : root.value(QStringLiteral("components")).toArray()) {
        if (!componentValue.isObject()) {
            diagnostic = "The instance component list contains an invalid component.";
            return std::nullopt;
        }
        const auto component = componentValue.toObject();
        const QString uid = component.value(QStringLiteral("uid")).toString().trimmed();
        if (uid.isEmpty() || uid.contains('/') || uid.contains('\\') || uid == QStringLiteral(".")
            || uid == QStringLiteral("..")) {
            diagnostic = "The instance component identifier is invalid.";
            return std::nullopt;
        }
        if (component.value(QStringLiteral("disabled")).toBool(false)) {
            continue;
        }

        const auto patchPath = patchesRoot / (uid.toStdString() + ".json");
        if (isSymlink(patchPath) || !isRegularFile(patchPath) || !isContained(instancePath, patchPath)) {
            diagnostic = "A required instance component patch is unavailable.";
            return std::nullopt;
        }
        QFile patchFile(QString::fromStdString(patchPath.string()));
        if (!patchFile.open(QIODevice::ReadOnly)) {
            diagnostic = "A required instance component patch could not be read.";
            return std::nullopt;
        }
        QJsonParseError patchError{};
        const auto patchDocument = QJsonDocument::fromJson(patchFile.readAll(), &patchError);
        if (patchError.error != QJsonParseError::NoError || !patchDocument.isObject()) {
            diagnostic = "A required instance component patch is not valid JSON.";
            return std::nullopt;
        }

        try {
            const auto versionFile = OneSixVersionFormat::versionFileFromJson(
                patchDocument, QString::fromStdString(patchPath.string()), false);
            versionFile->applyTo(profile.get(), runtimeContext);
        } catch (const Exception& exception) {
            diagnostic = exception.cause().toStdString();
            return std::nullopt;
        } catch (...) {
            diagnostic = "A required instance component patch could not be applied.";
            return std::nullopt;
        }
    }
    return profile;
}

void isolateLibraryStorage(const std::shared_ptr<LaunchProfile>& profile, const std::filesystem::path& dataRoot)
{
    const auto storagePrefix = QString::fromStdString((dataRoot / "libraries").string());
    auto setPrefix = [storagePrefix](const LibraryPtr& library) {
        if (library) {
            library->setStoragePrefix(storagePrefix);
        }
    };
    for (const auto& library : profile->getLibraries()) {
        setPrefix(library);
    }
    for (const auto& library : profile->getNativeLibraries()) {
        setPrefix(library);
    }
    for (const auto& library : profile->getMavenFiles()) {
        setPrefix(library);
    }
    for (const auto& library : profile->getJarMods()) {
        setPrefix(library);
    }
    for (const auto& agent : profile->getAgents()) {
        setPrefix(agent.library);
    }
    setPrefix(profile->getMainJar());
}

QStringList profileClassPath(
    const std::shared_ptr<LaunchProfile>& profile,
    const RuntimeContext& runtimeContext,
    const std::filesystem::path& instancePath,
    const std::filesystem::path& gameRoot)
{
    QStringList jars;
    QStringList nativeJars;
    profile->getLibraryFiles(
        runtimeContext,
        jars,
        nativeJars,
        QString::fromStdString((instancePath / "libraries").string()),
        QString::fromStdString((gameRoot / "bin").string()));
    return jars;
}

QMap<QString, QString> profileTokenMapping(
    const std::shared_ptr<LaunchProfile>& profile,
    const std::filesystem::path& gameRoot,
    const std::filesystem::path& dataRoot,
    const QString& instanceName,
    const ProductionLaunchSession& session)
{
    QMap<QString, QString> mapping;
    mapping.insert(QStringLiteral("profile_name"), instanceName);
    mapping.insert(QStringLiteral("version_name"), profile->getMinecraftVersion());
    mapping.insert(QStringLiteral("version_type"), profile->getMinecraftVersionType());
    const QString gameDirectory = QDir(QString::fromStdString(gameRoot.string())).absolutePath();
    mapping.insert(QStringLiteral("game_directory"), gameDirectory);
    mapping.insert(QStringLiteral("game_assets"), QDir(gameDirectory + QStringLiteral("/assets")).absolutePath());
    mapping.insert(QStringLiteral("assets_root"), QDir(gameDirectory + QStringLiteral("/assets")).absolutePath());
    mapping.insert(QStringLiteral("assets_index_name"), profile->getMinecraftAssets()->id);
    mapping.insert(
        QStringLiteral("library_directory"), QString::fromStdString((dataRoot / "libraries").string()));
    mapping.insert(QStringLiteral("auth_session"), QString::fromStdString(session.session));
    mapping.insert(QStringLiteral("auth_access_token"), QString::fromStdString(session.accessToken));
    mapping.insert(QStringLiteral("auth_player_name"), QString::fromStdString(session.playerName));
    mapping.insert(QStringLiteral("auth_uuid"), QString::fromStdString(session.uuid));
    mapping.insert(QStringLiteral("user_properties"), QStringLiteral("{}"));
    mapping.insert(QStringLiteral("user_type"), QString::fromStdString(session.userType));
    return mapping;
}

QStringList minecraftArguments(
    const std::shared_ptr<LaunchProfile>& profile,
    const QMap<QString, QString>& mapping,
    const ProductionLaunchSession& session)
{
    QStringList arguments = profile->getMinecraftArguments().split(' ', Qt::SkipEmptyParts);
    arguments.reserve(arguments.size() + profile->getTweakers().size() * 2 + (session.mode == ProductionLaunchMode::Demo ? 1 : 0));
    for (const auto& tweaker : profile->getTweakers()) {
        arguments << QStringLiteral("--tweakClass") << tweaker;
    }
    if (session.mode == ProductionLaunchMode::Demo) {
        arguments << QStringLiteral("--demo");
    }
    for (auto& argument : arguments) {
        argument = replaceTokensIn(argument, mapping);
    }
    return arguments;
}

void appendEnvironment(
    std::map<std::string, std::string>& environment,
    std::vector<std::string>& secrets,
    const QString& encoded)
{
    if (encoded.trimmed().isEmpty()) {
        return;
    }
    QJsonParseError error{};
    const auto document = QJsonDocument::fromJson(encoded.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        throw std::invalid_argument("Env must be a JSON object");
    }
    const QJsonObject object = document.object();
    for (auto iterator = object.constBegin(); iterator != object.constEnd(); ++iterator) {
        const QString key = iterator.key().trimmed();
        const QJsonValue value = iterator.value();
        if (key.isEmpty()) {
            throw std::invalid_argument(
                "Env keys must be non-empty strings (object entries: "
                + std::to_string(document.object().size()) + ", bytes: " + std::to_string(encoded.toUtf8().size()) + ")");
        }
        if (!value.isString()) {
            const auto type = value.isBool() ? "boolean"
                : value.isDouble() ? "number"
                : value.isArray() ? "array"
                : value.isObject() ? "object"
                : "null";
            throw std::invalid_argument("Env value for key " + key.toStdString() + " is a " + type);
        }
        if (value.toString().contains('\0')) {
            throw std::invalid_argument("Env values must not contain NUL bytes");
        }
        const auto valueString = value.toString().toStdString();
        environment[key.toStdString()] = valueString;
        if (valueString.size() >= 3) {
            secrets.push_back(valueString);
        }
    }
}

void appendCleanSystemEnvironment(std::map<std::string, std::string>& environment)
{
    const QProcessEnvironment rawEnvironment = QProcessEnvironment::systemEnvironment();
    const QStringList ignored = {
        QStringLiteral("JAVA_ARGS"),
        QStringLiteral("CLASSPATH"),
        QStringLiteral("CONFIGPATH"),
        QStringLiteral("JAVA_HOME"),
        QStringLiteral("JRE_HOME"),
        QStringLiteral("_JAVA_OPTIONS"),
        QStringLiteral("JAVA_OPTIONS"),
        QStringLiteral("JAVA_TOOL_OPTIONS"),
    };
    for (const auto& key : rawEnvironment.keys()) {
        if (ignored.contains(key) || key.startsWith(QStringLiteral("LAUNCHER_"))) {
            continue;
        }
        environment[key.toStdString()] = rawEnvironment.value(key).toStdString();
    }
}

void appendLaunchScriptLine(std::string& script, const QString& key, const QString& value)
{
    script += key.toStdString();
    script += ' ';
    script += value.toStdString();
    script += '\n';
}

}  // namespace

ProductionLaunchBuildResult buildProductionMinecraftLaunch(
    const std::filesystem::path& dataRoot,
    const std::filesystem::path& instancePath,
    const std::string& instanceIdentifier,
    const ProductionLaunchSession& session)
{
    ProductionLaunchBuildResult result;
    if (!safeIdentifier(instanceIdentifier) || !isContained(dataRoot, instancePath) || !isDirectory(instancePath)
        || isSymlink(instancePath)) {
        result.diagnostic = "The Native Prism instance path is invalid.";
        return result;
    }

    const auto instanceSettings = loadINI(instancePath / "instance.cfg");
    const auto globalSettings = loadINI(dataRoot / "prismlauncher.cfg");
    if (!instanceSettings || !globalSettings) {
        result.diagnostic = "The Native Prism launch settings could not be read.";
        return result;
    }

    const QString javaPath = stringValue(*instanceSettings, *globalSettings, "JavaPath");
    if (javaPath.isEmpty() || !std::filesystem::path(javaPath.toStdString()).is_absolute()) {
        result.diagnostic = "A selected absolute Java executable is required.";
        return result;
    }

    const auto gameRoot = [&] {
        const auto minecraft = instancePath / "minecraft";
        const auto dotMinecraft = instancePath / ".minecraft";
        if (isDirectory(dotMinecraft) && !isDirectory(minecraft)) {
            return dotMinecraft;
        }
        return minecraft;
    }();
    if (!isContained(instancePath, gameRoot) || isSymlink(gameRoot)) {
        result.diagnostic = "The Minecraft game directory is outside the instance.";
        return result;
    }

    RuntimeContext runtimeContext;
    runtimeContext.javaArchitecture = stringValue(*instanceSettings, *globalSettings, "JavaArchitecture", QStringLiteral("64"));
    runtimeContext.javaRealArchitecture = stringValue(
        *instanceSettings, *globalSettings, "JavaRealArchitecture", SysInfo::useQTForArch());

    std::string diagnostic;
    const auto profileResult = loadLaunchProfile(instancePath, runtimeContext, diagnostic);
    if (!profileResult.has_value()) {
        result.diagnostic = std::move(diagnostic);
        return result;
    }
    const auto profile = *profileResult;
    if (profile->getMainClass().isEmpty() || profile->getProblemSeverity() == ProblemSeverity::Error) {
        result.diagnostic = "The instance launch profile is incomplete.";
        return result;
    }
    isolateLibraryStorage(profile, dataRoot);

    const auto launchJar = dataRoot / "jars" / "NewLaunch.jar";
    if (!isRegularFile(launchJar) || isSymlink(launchJar)) {
        result.diagnostic = "The Native Prism launcher library is unavailable.";
        return result;
    }

    const bool legacy = profile->hasTrait(QStringLiteral("legacyLaunch"))
        || profile->hasTrait(QStringLiteral("alphaLaunch"));
    const bool onlineFixes = profile->hasTrait(QStringLiteral("legacyServices"))
        && boolValue(*instanceSettings, *globalSettings, "OnlineFixes", false);
    std::vector<std::filesystem::path> launcherJars{ launchJar };
    if (legacy || onlineFixes) {
        const auto legacyJar = dataRoot / "jars" / "NewLaunchLegacy.jar";
        if (!isRegularFile(legacyJar) || isSymlink(legacyJar)) {
            result.diagnostic = "The Native Prism legacy launcher library is unavailable.";
            return result;
        }
        launcherJars.push_back(legacyJar);
    }

    QStringList classPath = profileClassPath(profile, runtimeContext, instancePath, gameRoot);
    QStringList fullClassPath;
    for (const auto& jar : launcherJars) {
        fullClassPath.append(QString::fromStdString(jar.string()));
    }
    fullClassPath.append(classPath);
    if (fullClassPath.isEmpty()) {
        result.diagnostic = "The instance launch class path is empty.";
        return result;
    }

    const int minMemory = intValue(*instanceSettings, *globalSettings, "MinMemAlloc", 512);
    const int maxMemory = intValue(*instanceSettings, *globalSettings, "MaxMemAlloc", SysInfo::defaultMaxJvmMem());
    const int permGen = intValue(*instanceSettings, *globalSettings, "PermGen", 128);
    if (minMemory < 8 || maxMemory < 8) {
        result.diagnostic = "The configured Java memory range is invalid.";
        return result;
    }

    std::vector<std::string> javaArguments = commandArguments(stringValue(*instanceSettings, *globalSettings, "JvmArgs"));
    javaArguments.insert(javaArguments.begin(), "-Duser.language=en");
#ifdef Q_OS_MACOS
    javaArguments.push_back("-Xdock:icon=icon.png");
    javaArguments.push_back(
        "-Xdock:name=\"" + BuildConfig.LAUNCHER_DISPLAYNAME.toStdString() + ": "
        + stringValue(*instanceSettings, *globalSettings, "name").toStdString() + "\"");
    if (profile->hasTrait(QStringLiteral("FirstThreadOnMacOS"))) {
        javaArguments.push_back("-XstartOnFirstThread");
    }
#endif

    const QString instanceName = stringValue(
        *instanceSettings, *globalSettings, "name", QString::fromStdString(instanceIdentifier));
    const auto mapping = profileTokenMapping(profile, gameRoot, dataRoot, instanceName, session);
    for (const auto& argument : profile->getAddnJvmArguments()) {
        javaArguments.push_back(replaceTokensIn(argument, mapping).toStdString());
    }
    for (const auto& agent : profile->getAgents()) {
        QStringList agentJars;
        QStringList ignoredNative;
        QStringList ignored32;
        QStringList ignored64;
        agent.library->getApplicableFiles(
            runtimeContext,
            agentJars,
            ignoredNative,
            ignored32,
            ignored64,
            QString::fromStdString((instancePath / "libraries").string()));
        if (agentJars.isEmpty()) {
            result.diagnostic = "A Java agent library is unavailable.";
            return result;
        }
        javaArguments.push_back(
            "-javaagent:" + agentJars.front().toStdString()
            + (agent.argument.isEmpty() ? std::string() : "=" + agent.argument.toStdString()));
    }

    const JavaVersion javaVersion(stringValue(*instanceSettings, *globalSettings, "JavaVersion"));
    if (minMemory < maxMemory) {
        javaArguments.push_back("-Xms" + std::to_string(minMemory) + "m");
        javaArguments.push_back("-Xmx" + std::to_string(maxMemory) + "m");
    } else {
        javaArguments.push_back("-Xms" + std::to_string(maxMemory) + "m");
        javaArguments.push_back("-Xmx" + std::to_string(minMemory) + "m");
    }
    if (javaVersion.requiresPermGen() && permGen != 64) {
        javaArguments.push_back("-XX:PermSize=" + std::to_string(permGen) + "m");
    }
    if (javaVersion.isModular() && onlineFixes) {
        javaArguments.push_back("--add-opens");
        javaArguments.push_back("java.base/java.net=ALL-UNNAMED");
    }

    const auto gameArguments = minecraftArguments(profile, mapping, session);
    std::string launchScript;
    appendLaunchScriptLine(launchScript, QStringLiteral("mainClass"), profile->getMainClass());
    if (!profile->getAppletClass().isEmpty()) {
        appendLaunchScriptLine(launchScript, QStringLiteral("appletClass"), profile->getAppletClass());
    }
    for (const auto& argument : gameArguments) {
        appendLaunchScriptLine(launchScript, QStringLiteral("param"), argument);
    }
    const bool launchMaximized = boolValue(*instanceSettings, *globalSettings, "LaunchMaximized", false);
    const int windowWidth = intValue(*instanceSettings, *globalSettings, "MinecraftWinWidth", 854);
    const int windowHeight = intValue(*instanceSettings, *globalSettings, "MinecraftWinHeight", 480);
    appendLaunchScriptLine(
        launchScript,
        QStringLiteral("windowTitle"), QStringLiteral("Prism: ") + instanceName);
    appendLaunchScriptLine(
        launchScript,
        QStringLiteral("windowParams"),
        launchMaximized ? QStringLiteral("maximized") : QStringLiteral("%1x%2").arg(windowWidth).arg(windowHeight));
    appendLaunchScriptLine(launchScript, QStringLiteral("launcherBrand"), BuildConfig.LAUNCHER_NAME);
    appendLaunchScriptLine(launchScript, QStringLiteral("launcherVersion"), BuildConfig.printableVersionString());
    appendLaunchScriptLine(
        launchScript,
        QStringLiteral("instanceName"),
        instanceName);
    appendLaunchScriptLine(launchScript, QStringLiteral("instanceIconKey"), instanceName);
    appendLaunchScriptLine(launchScript, QStringLiteral("instanceIconPath"), QStringLiteral("icon.png"));
    appendLaunchScriptLine(launchScript, QStringLiteral("userName"), QString::fromStdString(session.playerName));
    appendLaunchScriptLine(launchScript, QStringLiteral("sessionId"), QString::fromStdString(session.session));
    for (const auto& trait : profile->getTraits()) {
        appendLaunchScriptLine(launchScript, QStringLiteral("traits"), trait);
    }
    if (onlineFixes) {
        appendLaunchScriptLine(launchScript, QStringLiteral("onlineFixes"), QStringLiteral("true"));
    }
    appendLaunchScriptLine(
        launchScript,
        QStringLiteral("launcher"),
        legacy ? QStringLiteral("legacy") : QStringLiteral("standard"));

    ProductionLaunchRuntime::ProcessSpec process;
    process.program = javaPath.toStdString();
    process.arguments = javaArguments;
    process.arguments.push_back("-Djava.library.path=" + (instancePath / "natives").string());
    process.arguments.push_back("-cp");
    process.arguments.push_back(fullClassPath.join(QDir::listSeparator()).toStdString());
    process.arguments.push_back("org.prismlauncher.EntryPoint");
    process.standardInput = std::move(launchScript);
    process.launchInput = "launch\n";
    process.workingDirectory = gameRoot;

    std::map<std::string, std::string> environment;
    appendCleanSystemEnvironment(environment);
    const auto instanceRootString = QDir(QString::fromStdString(instancePath.string())).absolutePath().toStdString();
    const auto gameRootString = QDir(QString::fromStdString(gameRoot.string())).absolutePath().toStdString();
    environment["INST_NAME"] = stringValue(*instanceSettings, *globalSettings, "name", QString::fromStdString(instanceIdentifier)).toStdString();
    environment["INST_ID"] = instanceIdentifier;
    environment["INST_DIR"] = instanceRootString;
    environment["INST_MC_DIR"] = gameRootString;
    environment["INST_JAVA"] = javaPath.toStdString();
    QStringList javaArgumentStrings;
    for (const auto& argument : javaArguments) {
        javaArgumentStrings.append(QString::fromStdString(argument));
    }
    environment["INST_JAVA_ARGS"] = javaArgumentStrings.join(' ').toStdString();
    environment["NO_COLOR"] = "1";
    try {
        appendEnvironment(environment, result.secrets, stringValue(*instanceSettings, *globalSettings, "Env"));
    } catch (const std::exception& exception) {
        result.diagnostic = exception.what();
        return result;
    }
    process.environment = std::move(environment);
    result.process = std::move(process);
    for (const auto& secret : session.secrets) {
        if (secret.size() >= 3) {
            result.secrets.push_back(secret);
        }
    }
    return result;
}
