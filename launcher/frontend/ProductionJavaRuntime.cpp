// SPDX-License-Identifier: GPL-3.0-only

#include "ProductionJavaRuntime.h"

#include "SysInfo.h"
#include "java/JavaVersion.h"
#include "settings/INIFile.h"

#include <QProcess>
#include <QProcessEnvironment>
#include <QString>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <system_error>
#include <unordered_map>
#include <unordered_set>
#include <utility>

namespace {

std::filesystem::path normalizeRoot(std::filesystem::path root)
{
    root = std::move(root).lexically_normal();
    if (root.empty() || !root.is_absolute()) {
        throw std::invalid_argument("Production Java runtime requires an absolute data root");
    }
    return root;
}

std::string trim(std::string value)
{
    auto isWhitespace = [](unsigned char character) { return std::isspace(character) != 0; };
    value.erase(value.begin(), std::find_if(value.begin(), value.end(), [&](unsigned char character) {
        return !isWhitespace(character);
    }));
    value.erase(std::find_if(value.rbegin(), value.rend(), [&](unsigned char character) {
                    return !isWhitespace(character);
                }).base(),
                value.end());
    return value;
}

bool safeText(const std::string& value, std::size_t maximumLength)
{
    return !value.empty() && value.size() <= maximumLength
        && std::all_of(value.begin(), value.end(), [](unsigned char character) {
               return character != '\0' && character != '\n' && character != '\r';
           });
}

bool pathWithin(const std::filesystem::path& candidate,
                const std::filesystem::path& root,
                const ProductionJavaRuntime::FilesystemExecutor& filesystem)
{
    const auto canonicalCandidate = filesystem.canonicalPath(candidate);
    const auto canonicalRoot = filesystem.canonicalPath(root);
    const auto relative = canonicalCandidate.lexically_relative(canonicalRoot);
    if (relative.empty()) {
        return true;
    }
    for (const auto& component : relative) {
        if (component == ".." || component == ".") {
            return false;
        }
    }
    return true;
}

std::string stablePathIdentifier(const std::filesystem::path& path,
                                 const ProductionJavaRuntime::FilesystemExecutor& filesystem)
{
    const std::string value = filesystem.canonicalPath(path).string();
    std::uint64_t hash = 1469598103934665603ULL;
    for (unsigned char character : value) {
        hash ^= character;
        hash *= 1099511628211ULL;
    }
    std::ostringstream output;
    output << "system." << std::hex << std::setfill('0') << std::setw(16) << hash;
    return output.str();
}

std::string managedIdentifier(const std::filesystem::path& path)
{
    std::string value = path.filename().string();
    if (!safeText(value, 128)) {
        value = "runtime";
    }
    for (char& character : value) {
        if (character == '/' || character == '\\' || character == ':' || character == ' ') {
            character = '_';
        }
    }
    return "managed." + value;
}

bool is64BitArchitecture(const std::string& architecture)
{
    return architecture == "x86_64" || architecture == "amd64" || architecture == "aarch64"
        || architecture == "arm64" || architecture == "riscv64" || architecture == "ppc64le"
        || architecture == "ppc64";
}

bool hostArchitectureMatches(const std::string& architecture)
{
    const QString host = SysInfo::useQTForArch().toLower();
    const QString candidate = QString::fromStdString(architecture).toLower();
    if (host.contains("arm64") || host.contains("aarch64")) {
        return candidate == "arm64" || candidate == "aarch64";
    }
    if (host.contains("x86_64") || host.contains("amd64") || host.contains("x86-64")) {
        return candidate == "x86_64" || candidate == "amd64";
    }
    return true;
}

std::unordered_map<std::string, std::string> parseProperties(const std::string& output)
{
    std::unordered_map<std::string, std::string> properties;
    std::size_t start = 0;
    while (start <= output.size()) {
        const auto end = output.find('\n', start);
        std::string line = output.substr(start, end == std::string::npos ? std::string::npos : end - start);
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        const auto equals = line.find('=');
        if (equals != std::string::npos) {
            const auto key = trim(line.substr(0, equals));
            const auto value = trim(line.substr(equals + 1));
            if (key == "java.version" || key == "java.vendor" || key == "os.arch") {
                properties[key] = value;
            }
        }
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return properties;
}

std::string fallbackVersion(const std::string& output)
{
    const auto marker = output.find("version \"");
    if (marker == std::string::npos) {
        return {};
    }
    const auto first = marker + 9;
    const auto last = output.find('"', first);
    return last == std::string::npos ? std::string() : output.substr(first, last - first);
}

ProductionJavaRuntime::FilesystemExecutor defaultFilesystem()
{
    ProductionJavaRuntime::FilesystemExecutor filesystem;
    filesystem.isDirectory = [](const std::filesystem::path& path) {
        std::error_code error;
        return std::filesystem::is_directory(path, error) && !error;
    };
    filesystem.isRegularFile = [](const std::filesystem::path& path) {
        std::error_code error;
        return std::filesystem::is_regular_file(path, error) && !error;
    };
    filesystem.isSymlink = [](const std::filesystem::path& path) {
        std::error_code error;
        return std::filesystem::is_symlink(path, error) && !error;
    };
    filesystem.childDirectories = [](const std::filesystem::path& root) {
        std::vector<std::filesystem::path> children;
        std::error_code error;
        for (const auto& entry : std::filesystem::directory_iterator(root, error)) {
            if (error) {
                break;
            }
            std::error_code entryError;
            if (!entry.is_symlink(entryError) && !entryError && entry.is_directory(entryError) && !entryError) {
                children.push_back(entry.path());
            }
        }
        std::sort(children.begin(), children.end());
        return children;
    };
    filesystem.canonicalPath = [](const std::filesystem::path& path) {
        std::error_code error;
        const auto canonical = std::filesystem::weakly_canonical(path, error);
        return error ? path.lexically_normal() : canonical;
    };
    filesystem.createDirectories = [](const std::filesystem::path& path) {
        std::error_code error;
        std::filesystem::create_directories(path, error);
        return !error && std::filesystem::is_directory(path, error) && !error;
    };
    filesystem.loadINIFile = [](const std::filesystem::path& path, INIFile& settings) {
        return settings.loadFile(QString::fromStdString(path.string()));
    };
    filesystem.saveINIFile = [](const std::filesystem::path& path, INIFile& settings) {
        return settings.saveFile(QString::fromStdString(path.string()));
    };
    return filesystem;
}

ProductionJavaRuntime::ProcessExecutor defaultProcess()
{
    return [](const std::filesystem::path& executablePath) {
        ProductionJavaRuntime::ProcessResult result;
        QProcess process;
        process.setProgram(QString::fromStdString(executablePath.string()));
        process.setArguments({ "-XshowSettings:properties", "-version" });

        auto environment = QProcessEnvironment::systemEnvironment();
        for (const auto& key : { "JAVA_HOME", "JRE_HOME", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JAVA_OPTIONS",
                                 "CLASSPATH", "JAVA_ARGS" }) {
            environment.remove(QString::fromUtf8(key));
        }
        process.setProcessEnvironment(environment);
        process.setProcessChannelMode(QProcess::SeparateChannels);
        process.start();
        if (!process.waitForStarted(2000)) {
            return result;
        }
        if (!process.waitForFinished(15000)) {
            result.timedOut = true;
            process.kill();
            process.waitForFinished(2000);
        }
        result.started = true;
        result.exitCode = process.exitCode();
        result.standardOutput = process.readAllStandardOutput().toStdString();
        result.standardError = process.readAllStandardError().toStdString();
        return result;
    };
}

}  // namespace

ProductionJavaRuntime::Dependencies ProductionJavaRuntime::defaultDependencies()
{
    return { defaultFilesystem(), defaultProcess() };
}

ProductionJavaRuntime::ProductionJavaRuntime(std::filesystem::path dataRoot, Dependencies dependencies)
    : m_dataRoot(normalizeRoot(std::move(dataRoot))),
      m_managedRoot(m_dataRoot / "java"),
      m_globalSettingsPath(m_dataRoot / "prismlauncher.cfg"),
      m_dependencies(std::move(dependencies))
{
    const auto defaults = defaultDependencies();
    if (!m_dependencies.filesystem.isDirectory) {
        m_dependencies.filesystem.isDirectory = defaults.filesystem.isDirectory;
    }
    if (!m_dependencies.filesystem.isRegularFile) {
        m_dependencies.filesystem.isRegularFile = defaults.filesystem.isRegularFile;
    }
    if (!m_dependencies.filesystem.isSymlink) {
        m_dependencies.filesystem.isSymlink = defaults.filesystem.isSymlink;
    }
    if (!m_dependencies.filesystem.childDirectories) {
        m_dependencies.filesystem.childDirectories = defaults.filesystem.childDirectories;
    }
    if (!m_dependencies.filesystem.canonicalPath) {
        m_dependencies.filesystem.canonicalPath = defaults.filesystem.canonicalPath;
    }
    if (!m_dependencies.filesystem.createDirectories) {
        m_dependencies.filesystem.createDirectories = defaults.filesystem.createDirectories;
    }
    if (!m_dependencies.filesystem.loadINIFile) {
        m_dependencies.filesystem.loadINIFile = defaults.filesystem.loadINIFile;
    }
    if (!m_dependencies.filesystem.saveINIFile) {
        m_dependencies.filesystem.saveINIFile = defaults.filesystem.saveINIFile;
    }
    if (!m_dependencies.process) {
        m_dependencies.process = defaults.process;
    }

    if (m_dependencies.filesystem.isSymlink(m_dataRoot)) {
        throw std::invalid_argument("Production Java runtime rejects a symlinked data root");
    }
    if (!m_dependencies.filesystem.isDirectory(m_dataRoot)
        && !m_dependencies.filesystem.createDirectories(m_dataRoot)) {
        throw std::runtime_error("Production Java runtime could not create its data root");
    }
    if (m_dependencies.filesystem.isSymlink(m_managedRoot)) {
        throw std::invalid_argument("Production Java runtime rejects a symlinked managed root");
    }
    if (!m_dependencies.filesystem.isDirectory(m_managedRoot)
        && !m_dependencies.filesystem.createDirectories(m_managedRoot)) {
        throw std::runtime_error("Production Java runtime could not create its managed root");
    }
}

ProductionJavaRuntime::~ProductionJavaRuntime() noexcept
{
    shutdown();
}

std::vector<ProductionJavaRuntime::Candidate> ProductionJavaRuntime::candidates() const
{
    std::vector<Candidate> result;
    std::unordered_set<std::string> seen;

    const auto addCandidate = [&](std::filesystem::path executablePath, bool managed, std::string managedID) {
        executablePath = executablePath.lexically_normal();
        const auto key = m_dependencies.filesystem.canonicalPath(executablePath).string();
        if (key.empty() || !seen.insert(key).second) {
            return;
        }
        result.push_back({ std::move(executablePath), std::move(managedID), managed });
    };

    for (const auto& runtime : m_dependencies.filesystem.childDirectories(m_managedRoot)) {
        if (m_dependencies.filesystem.isSymlink(runtime)) {
            continue;
        }
        const auto id = managedIdentifier(runtime);
        const std::vector<std::filesystem::path> possiblePaths = {
            runtime / "bin" / "java",
            runtime / "jre" / "bin" / "java",
            runtime / "Contents" / "Home" / "bin" / "java",
            runtime / "Contents" / "Home" / "jre" / "bin" / "java",
            runtime / "java",
        };
        auto selectedPath = possiblePaths.front();
        for (const auto& possiblePath : possiblePaths) {
            if (m_dependencies.filesystem.isRegularFile(possiblePath)) {
                selectedPath = possiblePath;
                break;
            }
        }
        addCandidate(selectedPath, true, id);
    }

    const std::vector<std::filesystem::path> systemRoots = {
        "/Library/Java/JavaVirtualMachines",
        "/System/Library/Java/JavaVirtualMachines",
    };
    addCandidate("/usr/bin/java", false, {});
    addCandidate("/System/Library/Frameworks/JavaVM.framework/Versions/Current/Commands/java", false, {});
    for (const auto& root : systemRoots) {
        for (const auto& runtime : m_dependencies.filesystem.childDirectories(root)) {
            addCandidate(runtime / "Contents" / "Home" / "bin" / "java", false, {});
            addCandidate(runtime / "Contents" / "Home" / "jre" / "bin" / "java", false, {});
            addCandidate(runtime / "Contents" / "Commands" / "java", false, {});
        }
    }

    std::sort(result.begin(), result.end(), [](const Candidate& left, const Candidate& right) {
        if (left.managed != right.managed) {
            return left.managed > right.managed;
        }
        return left.executablePath.string() < right.executablePath.string();
    });
    return result;
}

FrontendJavaInstallationSnapshot ProductionJavaRuntime::probe(const Candidate& candidate) const
{
    const auto unavailable = [&](const std::string& identifier, const std::string& diagnostic) {
        return FrontendJavaInstallationSnapshot{
            identifier,
            "",
            "",
            "",
            candidate.executablePath,
            false,
            candidate.managed,
            FrontendJavaInstallationValidity::Unavailable,
            diagnostic,
        };
    };
    const std::string identifier = candidate.managed
        ? candidate.managedIdentifier
        : stablePathIdentifier(candidate.executablePath, m_dependencies.filesystem);

    if (candidate.managed && !pathWithin(candidate.executablePath, m_managedRoot, m_dependencies.filesystem)) {
        return unavailable(identifier, "Managed Java runtime path is outside the Native Prism root.");
    }
    if (!m_dependencies.filesystem.isRegularFile(candidate.executablePath)) {
        return unavailable(identifier, "The Java executable is not available.");
    }

    const auto processResult = m_dependencies.process(candidate.executablePath);
    if (!processResult.started || processResult.timedOut || processResult.exitCode != 0) {
        return unavailable(
            identifier,
            processResult.timedOut ? "Java validation timed out." : "Java could not be started or returned no metadata.");
    }

    const auto properties = parseProperties(processResult.standardOutput + "\n" + processResult.standardError);
    std::string version = properties.contains("java.version") ? properties.at("java.version") : std::string();
    if (version.empty()) {
        version = fallbackVersion(processResult.standardOutput + "\n" + processResult.standardError);
    }
    const auto vendor = properties.contains("java.vendor") ? properties.at("java.vendor") : std::string();
    const auto architecture = properties.contains("os.arch") ? properties.at("os.arch") : std::string();
    if (!safeText(version, 128) || !safeText(vendor, 256) || !safeText(architecture, 64)) {
        return unavailable(identifier, "Java returned incomplete validation metadata.");
    }

    const JavaVersion parsedVersion(QString::fromStdString(version));
    if (parsedVersion.major() <= 0) {
        return unavailable(identifier, "Java returned an unrecognized version.");
    }

    const bool is64Bit = is64BitArchitecture(architecture);
    const auto validity = hostArchitectureMatches(architecture)
        ? FrontendJavaInstallationValidity::Valid
        : FrontendJavaInstallationValidity::Incompatible;
    const std::string diagnostic = validity == FrontendJavaInstallationValidity::Valid
        ? std::string()
        : "Java architecture is incompatible with this Native Prism build.";
    return FrontendJavaInstallationSnapshot{
        identifier,
        version,
        vendor,
        architecture,
        candidate.executablePath,
        is64Bit,
        candidate.managed,
        validity,
        diagnostic,
    };
}

std::string ProductionJavaRuntime::savedJavaPath() const
{
    if (!m_dependencies.filesystem.isRegularFile(m_globalSettingsPath)) {
        return {};
    }
    INIFile settings;
    if (!m_dependencies.filesystem.loadINIFile(m_globalSettingsPath, settings)) {
        return {};
    }
    return settings.get("JavaPath", QString()).toString().trimmed().toStdString();
}

FrontendJavaDiscoveryResult ProductionJavaRuntime::discover()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_shutdown) {
        return { FrontendJavaDiscoveryOutcome::Cancelled, {}, "java.discovery.cancelled", "Java discovery was cancelled.", true, {} };
    }

    const auto discoveredCandidates = candidates();
    std::vector<FrontendJavaInstallationSnapshot> installations;
    installations.reserve(discoveredCandidates.size());
    for (const auto& candidate : discoveredCandidates) {
        if (!candidate.managed && !m_dependencies.filesystem.isRegularFile(candidate.executablePath)) {
            continue;
        }
        installations.push_back(probe(candidate));
    }

    std::optional<std::string> selectedIdentifier;
    const auto savedPath = savedJavaPath();
    if (!savedPath.empty()) {
        const std::filesystem::path saved(savedPath);
        if (saved.is_absolute()) {
            const auto savedCanonical = m_dependencies.filesystem.canonicalPath(saved);
            for (const auto& installation : installations) {
                if (installation.validity == FrontendJavaInstallationValidity::Valid
                    && m_dependencies.filesystem.canonicalPath(installation.executablePath) == savedCanonical) {
                    selectedIdentifier = installation.id;
                    break;
                }
            }
        }
    }

    m_lastInstallations = installations;
    return {
        FrontendJavaDiscoveryOutcome::Succeeded,
        std::move(installations),
        "",
        "",
        false,
        std::move(selectedIdentifier),
    };
}

bool ProductionJavaRuntime::persistSelection(const FrontendJavaInstallationSnapshot& installation) const
{
    INIFile settings;
    if (m_dependencies.filesystem.isRegularFile(m_globalSettingsPath)
        && !m_dependencies.filesystem.loadINIFile(m_globalSettingsPath, settings)) {
        return false;
    }
    settings.set("JavaPath", QString::fromStdString(installation.executablePath.string()));
    settings.set("JavaVersion", QString::fromStdString(installation.version));
    settings.set("JavaVendor", QString::fromStdString(installation.vendor));
    settings.set("JavaArchitecture", installation.is64Bit ? QStringLiteral("64") : QStringLiteral("32"));
    settings.set("JavaRealArchitecture", QString::fromStdString(installation.architecture));
    settings.set("JavaSignature", QString::fromStdString("native:" + installation.id));
    return m_dependencies.filesystem.saveINIFile(m_globalSettingsPath, settings);
}

FrontendJavaSelectionResult ProductionJavaRuntime::select(const std::string& installationIdentifier)
{
    if (!safeText(installationIdentifier, 255)) {
        return { FrontendJavaSelectionOutcome::Rejected, std::nullopt, "java.selection.invalidIdentifier", "Java selection requires a stable identifier." };
    }

    std::vector<FrontendJavaInstallationSnapshot> installations;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_shutdown) {
            return { FrontendJavaSelectionOutcome::Rejected, std::nullopt, "java.selection.cancelled", "Java selection was cancelled." };
        }
        installations = m_lastInstallations;
    }
    if (installations.empty()) {
        const auto result = discover();
        if (result.outcome != FrontendJavaDiscoveryOutcome::Succeeded) {
            return { FrontendJavaSelectionOutcome::Rejected, std::nullopt, "java.selection.discoveryUnavailable", "Java discovery is unavailable." };
        }
        installations = result.installations;
    }

    const auto selected = std::find_if(installations.begin(), installations.end(), [&](const auto& installation) {
        return installation.id == installationIdentifier;
    });
    if (selected == installations.end()) {
        return { FrontendJavaSelectionOutcome::UnknownInstallation, std::nullopt,
                 "java.selection.unknownInstallation", "The requested Java installation is no longer available." };
    }
    if (selected->validity != FrontendJavaInstallationValidity::Valid) {
        return { FrontendJavaSelectionOutcome::UnknownInstallation, *selected,
                 "java.selection.incompatible", "The selected Java installation is not compatible." };
    }
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_shutdown || !persistSelection(*selected)) {
            return { FrontendJavaSelectionOutcome::Rejected, std::nullopt,
                     m_shutdown ? "java.selection.cancelled" : "java.selection.persistenceUnavailable",
                     m_shutdown ? "Java selection was cancelled." : "The Java selection could not be saved." };
        }
    }
    return { FrontendJavaSelectionOutcome::Succeeded, *selected, {}, {} };
}

void ProductionJavaRuntime::shutdown() noexcept
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_shutdown = true;
    m_lastInstallations.clear();
}

std::shared_ptr<ProductionJavaRuntime> makeProductionJavaRuntime(
    std::filesystem::path dataRoot, ProductionJavaRuntime::Dependencies dependencies)
{
    return std::make_shared<ProductionJavaRuntime>(std::move(dataRoot), std::move(dependencies));
}

FrontendRuntimeDependencies productionJavaRuntimeDependencies(
    std::shared_ptr<ProductionJavaRuntime> runtime, FrontendRuntimeDependencies dependencies)
{
    if (!runtime) {
        throw std::invalid_argument("Production Java runtime dependency requires an owner");
    }
    dependencies.loadJavaInstallations = [runtime](const std::filesystem::path&) { return runtime->discover(); };
    dependencies.selectJavaInstallation = [runtime](const std::filesystem::path&, const std::string& identifier) {
        return runtime->select(identifier);
    };
    return dependencies;
}
