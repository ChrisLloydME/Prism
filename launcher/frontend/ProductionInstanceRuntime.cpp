// SPDX-License-Identifier: GPL-3.0-only

#include "ProductionInstanceRuntime.h"
#include "ProductionInstanceAcquisitionRuntime.h"
#include "ProductionAccountRuntime.h"
#include "ProductionInstanceDetailRuntime.h"
#include "ProductionJavaRuntime.h"
#include "ProductionLaunchRuntime.h"
#include "ProductionSettingsRuntime.h"

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

bool isSafeDisplayValue(const std::string& value, std::size_t maxLength, bool allowEmpty = false)
{
    return (allowEmpty || !value.empty()) && value.size() <= maxLength
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
    const std::string groupId = trimmedValue(settings.get("InstanceGroupId", QString()));
    if (!isSafeDisplayValue(name, 512) || !isSafeDisplayValue(iconKey, 256)
        || !isSafeDisplayValue(groupId, 512, true)) {
        return std::nullopt;
    }

    return FrontendInstanceSnapshot{ identifier, name, iconKey, groupId };
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
    const auto normalizedDataRoot = dataRoot.lexically_normal();
    auto runtime = makeProductionInstanceRuntime(normalizedDataRoot);
    auto settingsRuntime = makeProductionSettingsRuntime(normalizedDataRoot);
    auto javaRuntime = makeProductionJavaRuntime(normalizedDataRoot);
    auto accountRuntime = makeProductionAccountRuntime(normalizedDataRoot);
    auto acquisitionRuntime = makeProductionInstanceAcquisitionRuntime(normalizedDataRoot);
    auto detailRuntime = makeProductionInstanceDetailRuntime(normalizedDataRoot);
    auto launchRuntime = makeProductionLaunchRuntime(
        normalizedDataRoot,
        {},
        [accountRuntime](const std::string& instanceIdentifier) {
            return accountRuntime->launchSessionForInstance(instanceIdentifier);
        });
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::now(); };
    dependencies.cancelPendingWork = [runtime, launchRuntime] {
        runtime->stopInstanceObservation();
        launchRuntime->cancelPendingWork();
    };
    dependencies.shutdown = [runtime, settingsRuntime, javaRuntime, accountRuntime, acquisitionRuntime, detailRuntime, launchRuntime] {
        runtime->shutdown();
        settingsRuntime->shutdown();
        javaRuntime->shutdown();
        accountRuntime->shutdown();
        acquisitionRuntime->shutdown();
        static_cast<void>(detailRuntime);
        launchRuntime->shutdown();
    };
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
    dependencies.loadInstanceDetails = [detailRuntime](const std::filesystem::path&, const std::string& identifier) {
        return detailRuntime->instanceDetails(identifier);
    };
    dependencies.loadInstanceComponents = [detailRuntime](const std::filesystem::path&, const std::string& identifier) {
        return detailRuntime->instanceComponents(identifier);
    };
    dependencies.loadInstanceResources = [detailRuntime](
                                             const std::filesystem::path&,
                                             const std::string& identifier,
                                             FrontendInstanceResourceKind kind) {
        return detailRuntime->instanceResources(identifier, kind);
    };
    dependencies.mutateInstanceResource = [detailRuntime](
                                             const std::filesystem::path&,
                                             const std::string& identifier,
                                             FrontendInstanceResourceKind kind,
                                             const FrontendInstanceResourceMutationRequest& request) {
        return detailRuntime->mutateInstanceResource(identifier, kind, request);
    };
    dependencies.loadInstanceWorlds = [detailRuntime](const std::filesystem::path&, const std::string& identifier) {
        return detailRuntime->instanceWorlds(identifier);
    };
    dependencies.loadInstanceServers = [detailRuntime](const std::filesystem::path&, const std::string& identifier) {
        return detailRuntime->instanceServers(identifier);
    };
    dependencies.loadInstanceScreenshots = [detailRuntime](const std::filesystem::path&, const std::string& identifier) {
        return detailRuntime->instanceScreenshots(identifier);
    };
    dependencies.loadInstanceLogFiles = [detailRuntime](const std::filesystem::path&, const std::string& identifier) {
        return detailRuntime->instanceLogFiles(identifier);
    };
    dependencies.loadInstanceLog = [detailRuntime](
                                      const std::filesystem::path&,
                                      const std::string& identifier,
                                      const std::string& logIdentifier) {
        return detailRuntime->instanceLog(identifier, logIdentifier);
    };
    dependencies.mutateInstanceDetail = [detailRuntime](
                                           const std::filesystem::path&,
                                           const std::string& identifier,
                                           const FrontendInstanceDetailMutationRequest& request) {
        return detailRuntime->mutateInstanceDetail(identifier, request);
    };
    dependencies.updateInstanceNotes = [detailRuntime](
                                         const std::filesystem::path&,
                                         const std::string& identifier,
                                         const std::string& notes) {
        return detailRuntime->updateInstanceNotes(identifier, notes);
    };
    dependencies.deleteInstance = [detailRuntime](
                                      const std::filesystem::path&,
                                      const std::string& identifier,
                                      bool confirmed) {
        return detailRuntime->deleteInstance(identifier, confirmed);
    };
    dependencies.copyInstance = [detailRuntime](
                                    const std::filesystem::path&,
                                    const FrontendInstanceCopyRequest& request,
                                    const FrontendRuntimeDependencies::InstanceCopyProgressHandler& progress,
                                    const FrontendRuntimeDependencies::InstanceCopyCancellationCheck& cancellation) {
        return detailRuntime->copyInstance(request, progress, cancellation);
    };
    dependencies.exportInstance = [detailRuntime](
                                      const std::filesystem::path&,
                                      const FrontendInstanceExportRequest& request,
                                      const FrontendRuntimeDependencies::InstanceExportProgressHandler& progress,
                                      const FrontendRuntimeDependencies::InstanceExportCancellationCheck& cancellation) {
        return detailRuntime->exportInstance(request, progress, cancellation);
    };
    dependencies.createVanillaInstance = [acquisitionRuntime](
                                             const std::filesystem::path&,
                                             const FrontendVanillaCreationRequest& request,
                                             const FrontendRuntimeDependencies::VanillaCreationProgressHandler& progress,
                                             const FrontendRuntimeDependencies::VanillaCreationCancellationCheck& cancellation) {
        return acquisitionRuntime->createVanillaInstance(request, progress, cancellation);
    };
    dependencies.importInstance = [acquisitionRuntime](
                                      const std::filesystem::path&,
                                      const FrontendInstanceImportRequest& request,
                                      const FrontendRuntimeDependencies::InstanceImportProgressHandler& progress,
                                      const FrontendRuntimeDependencies::InstanceImportCancellationCheck& cancellation) {
        return acquisitionRuntime->importInstance(request, progress, cancellation);
    };
    dependencies.loadInstanceSettings = [settingsRuntime](
                                            const std::filesystem::path&,
                                            const std::string& identifier) {
        return settingsRuntime->instanceSettings(identifier);
    };
    dependencies.updateInstanceSettings = [settingsRuntime](
                                              const std::filesystem::path&,
                                              const std::string& identifier,
                                              const FrontendInstanceSettingsSnapshot& settings) {
        return settingsRuntime->updateInstanceSettings(identifier, settings);
    };
    dependencies.loadGlobalSettings = [settingsRuntime](const std::filesystem::path&) {
        return settingsRuntime->globalSettings();
    };
    dependencies.updateGlobalSettings = [settingsRuntime](
                                            const std::filesystem::path&,
                                            const FrontendGlobalSettingsSnapshot& settings) {
        return settingsRuntime->updateGlobalSettings(settings);
    };
    dependencies = productionJavaRuntimeDependencies(std::move(javaRuntime), std::move(dependencies));
    dependencies = productionAccountRuntimeDependencies(std::move(accountRuntime), std::move(dependencies));
    return productionLaunchRuntimeDependencies(std::move(launchRuntime), std::move(dependencies));
}
