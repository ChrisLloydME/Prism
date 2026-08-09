// SPDX-License-Identifier: GPL-3.0-only

#include "ProductionInstanceRuntime.h"

#include "settings/INIFile.h"

#include <QVariant>

#include <algorithm>
#include <chrono>
#include <system_error>
#include <utility>

namespace {

std::filesystem::path normalizeRoot(std::filesystem::path root)
{
    root = std::move(root).lexically_normal();
    if (root.empty() || !root.is_absolute()) {
        throw std::invalid_argument("Production instance runtime requires an absolute data root");
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

bool isSafeDisplayValue(const std::string& value, std::size_t maxLength)
{
    return !value.empty() && value.size() <= maxLength
        && std::all_of(value.begin(), value.end(), [](unsigned char character) {
               return character != '\0' && character != '\n' && character != '\r';
           });
}

std::string trimmedValue(const QVariant& value)
{
    return value.toString().trimmed().toStdString();
}

std::optional<FrontendInstanceSnapshot> readSnapshot(
    const std::filesystem::path& instancesRoot, const std::filesystem::directory_entry& entry)
{
    std::error_code error;
    if (entry.is_symlink(error) || error || !entry.is_directory(error) || error) {
        return std::nullopt;
    }

    const std::string identifier = entry.path().filename().string();
    if (!isSafeInstanceIdentifier(identifier)) {
        return std::nullopt;
    }

    const auto configPath = entry.path() / "instance.cfg";
    if (std::filesystem::is_symlink(configPath, error) || error || !std::filesystem::is_regular_file(configPath, error)
        || error) {
        return std::nullopt;
    }
    if (entry.path().lexically_relative(instancesRoot).has_parent_path()) {
        return std::nullopt;
    }

    INIFile settings;
    if (!settings.loadFile(QString::fromStdString(configPath.string()))) {
        return std::nullopt;
    }

    const std::string name = trimmedValue(settings.get("name", QStringLiteral("Unnamed Instance")));
    const std::string iconKey = trimmedValue(settings.get("iconKey", QStringLiteral("default")));
    if (!isSafeDisplayValue(name, 512) || !isSafeDisplayValue(iconKey, 256)) {
        return std::nullopt;
    }

    return FrontendInstanceSnapshot{ identifier, name, iconKey, "" };
}

ProductionInstanceRuntime::SnapshotMap scanRoot(const std::filesystem::path& instancesRoot)
{
    ProductionInstanceRuntime::SnapshotMap snapshots;
    std::error_code error;
    if (!std::filesystem::is_directory(instancesRoot, error) || error
        || std::filesystem::is_symlink(instancesRoot, error) || error) {
        return snapshots;
    }

    for (const auto& entry : std::filesystem::directory_iterator(instancesRoot, error)) {
        if (error) {
            break;
        }
        if (auto snapshot = readSnapshot(instancesRoot, entry)) {
            snapshots.emplace(snapshot->id, std::move(*snapshot));
        }
    }
    return snapshots;
}

}  // namespace

ProductionInstanceRuntime::ProductionInstanceRuntime(std::filesystem::path dataRoot)
    : m_dataRoot(normalizeRoot(std::move(dataRoot))), m_instancesRoot(m_dataRoot / "instances")
{
    std::error_code error;
    if (std::filesystem::exists(m_dataRoot, error) && (error || std::filesystem::is_symlink(m_dataRoot, error))) {
        throw std::invalid_argument("Production instance runtime rejects a symlinked data root");
    }
    std::filesystem::create_directories(m_instancesRoot, error);
    if (error || std::filesystem::is_symlink(m_instancesRoot, error)
        || !std::filesystem::is_directory(m_instancesRoot, error) || error) {
        throw std::runtime_error("Production instance runtime could not create its instance root");
    }
}

ProductionInstanceRuntime::~ProductionInstanceRuntime() noexcept
{
    shutdown();
}

ProductionInstanceRuntime::SnapshotMap ProductionInstanceRuntime::scanInstances() const
{
    return scanRoot(m_instancesRoot);
}

std::vector<FrontendInstanceSnapshot> ProductionInstanceRuntime::instanceSnapshots() const
{
    std::lock_guard<std::mutex> lock(m_dataMutex);
    const auto snapshots = scanInstances();
    std::vector<FrontendInstanceSnapshot> result;
    result.reserve(snapshots.size());
    for (const auto& [identifier, snapshot] : snapshots) {
        static_cast<void>(identifier);
        result.push_back(snapshot);
    }
    return result;
}

std::vector<FrontendInstanceChange> ProductionInstanceRuntime::takeInstanceChanges()
{
    std::lock_guard<std::mutex> lock(m_observationMutex);
    std::vector<FrontendInstanceChange> changes;
    changes.swap(m_pendingChanges);
    return changes;
}

FrontendMetadataInstanceResult ProductionInstanceRuntime::createMetadataInstance(
    const FrontendMetadataInstanceRequest& request)
{
    if (!isSafeInstanceIdentifier(request.id) || !isSafeDisplayValue(request.name, 512)
        || !isSafeDisplayValue(request.iconKey, 256)) {
        return { FrontendMetadataInstanceOutcome::InvalidInput, std::nullopt, "Metadata instance input is invalid" };
    }

    std::lock_guard<std::mutex> lock(m_dataMutex);
    {
        std::lock_guard<std::mutex> observationLock(m_observationMutex);
        if (m_shutdown) {
            return { FrontendMetadataInstanceOutcome::Failed, std::nullopt, "Production runtime is shut down" };
        }
    }

    const auto instancePath = m_instancesRoot / request.id;
    const auto configPath = instancePath / "instance.cfg";
    std::error_code error;
    if (instancePath.lexically_relative(m_instancesRoot).has_parent_path()
        || std::filesystem::exists(instancePath, error) || error) {
        return { FrontendMetadataInstanceOutcome::Failed, std::nullopt, "Instance already exists" };
    }
    std::filesystem::create_directory(instancePath, error);
    if (error || std::filesystem::is_symlink(instancePath, error)) {
        return { FrontendMetadataInstanceOutcome::Failed, std::nullopt, "Instance directory could not be created" };
    }

    INIFile settings;
    settings.set("InstanceType", QStringLiteral("NativeMetadata"));
    settings.set("name", QString::fromStdString(request.name));
    settings.set("iconKey", QString::fromStdString(request.iconKey));
    settings.set("notes", QString());
    if (!settings.saveFile(QString::fromStdString(configPath.string()))) {
        std::filesystem::remove_all(instancePath, error);
        return { FrontendMetadataInstanceOutcome::Failed, std::nullopt, "Instance metadata could not be saved" };
    }

    std::filesystem::directory_entry entry(instancePath, error);
    auto snapshot = error ? std::nullopt : readSnapshot(m_instancesRoot, entry);
    if (!snapshot) {
        std::filesystem::remove_all(instancePath, error);
        return { FrontendMetadataInstanceOutcome::Failed, std::nullopt, "Saved instance metadata could not be read back" };
    }
    return { FrontendMetadataInstanceOutcome::Succeeded, std::move(snapshot), {} };
}

bool ProductionInstanceRuntime::startInstanceObservation(FrontendRuntimeDependencies::InstanceChangeHandler handler)
{
    if (!handler) {
        return false;
    }

    std::lock_guard<std::mutex> lock(m_observationMutex);
    if (m_shutdown || m_observer.joinable()) {
        return false;
    }
    m_knownInstances = scanInstances();
    m_pendingChanges.clear();
    m_changeHandler = std::move(handler);
    m_stopRequested = false;
    m_observer = std::thread([this] { observeUntilStopped(); });
    return true;
}

void ProductionInstanceRuntime::stopInstanceObservation() noexcept
{
    std::thread observer;
    {
        std::lock_guard<std::mutex> lock(m_observationMutex);
        m_stopRequested = true;
        m_observationCondition.notify_all();
        observer = std::move(m_observer);
    }
    if (observer.joinable()) {
        observer.join();
    }
    std::lock_guard<std::mutex> lock(m_observationMutex);
    m_changeHandler = {};
}

void ProductionInstanceRuntime::observeUntilStopped()
{
    for (;;) {
        {
            std::unique_lock<std::mutex> lock(m_observationMutex);
            if (m_observationCondition.wait_for(lock, std::chrono::milliseconds(100), [this] { return m_stopRequested; })) {
                return;
            }
        }

        const auto current = scanInstances();
        std::vector<FrontendInstanceChange> changes;
        FrontendRuntimeDependencies::InstanceChangeHandler handler;
        {
            std::lock_guard<std::mutex> lock(m_observationMutex);
            if (m_stopRequested) {
                return;
            }
            for (const auto& [identifier, snapshot] : current) {
                const auto previous = m_knownInstances.find(identifier);
                if (previous == m_knownInstances.end()) {
                    changes.push_back({ FrontendInstanceChangeKind::Added, snapshot });
                } else if (previous->second.name != snapshot.name || previous->second.iconKey != snapshot.iconKey
                           || previous->second.groupId != snapshot.groupId) {
                    changes.push_back({ FrontendInstanceChangeKind::Updated, snapshot });
                }
            }
            for (const auto& [identifier, snapshot] : m_knownInstances) {
                if (!current.contains(identifier)) {
                    changes.push_back({ FrontendInstanceChangeKind::Removed, snapshot });
                }
            }
            m_knownInstances = current;
            m_pendingChanges.insert(m_pendingChanges.end(), changes.begin(), changes.end());
            handler = m_changeHandler;
        }

        for (const auto& change : changes) {
            {
                std::lock_guard<std::mutex> lock(m_observationMutex);
                if (m_stopRequested) {
                    return;
                }
            }
            if (handler) {
                handler(change);
            }
        }
    }
}

void ProductionInstanceRuntime::shutdown() noexcept
{
    {
        std::lock_guard<std::mutex> lock(m_observationMutex);
        if (m_shutdown) {
            return;
        }
        m_shutdown = true;
    }
    stopInstanceObservation();
}

std::shared_ptr<ProductionInstanceRuntime> makeProductionInstanceRuntime(std::filesystem::path dataRoot)
{
    return std::make_shared<ProductionInstanceRuntime>(std::move(dataRoot));
}

FrontendRuntimeDependencies productionInstanceRuntimeDependencies(std::filesystem::path dataRoot)
{
    auto runtime = makeProductionInstanceRuntime(std::move(dataRoot));
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::now(); };
    dependencies.cancelPendingWork = [runtime] { runtime->stopInstanceObservation(); };
    dependencies.shutdown = [runtime] { runtime->shutdown(); };
    dependencies.loadInstanceSnapshots = [runtime](const std::filesystem::path&) { return runtime->instanceSnapshots(); };
    dependencies.loadInstanceChanges = [runtime](const std::filesystem::path&) { return runtime->takeInstanceChanges(); };
    dependencies.createMetadataInstance =
        [runtime](const std::filesystem::path&, const FrontendMetadataInstanceRequest& request) {
            return runtime->createMetadataInstance(request);
        };
    dependencies.startInstanceObservation =
        [runtime](FrontendRuntimeDependencies::InstanceChangeHandler handler) {
            return runtime->startInstanceObservation(std::move(handler));
        };
    dependencies.stopInstanceObservation = [runtime] { runtime->stopInstanceObservation(); };
    return dependencies;
}
