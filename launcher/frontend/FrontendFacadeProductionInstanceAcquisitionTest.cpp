// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"
#include "ProductionInstanceAcquisitionRuntime.h"
#include "ProductionInstanceRuntime.h"
#include "archive/ArchiveWriter.h"

#include <QFile>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

std::filesystem::path temporaryRoot()
{
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    return std::filesystem::temp_directory_path() / ("prism-native-acquisition-" + std::to_string(stamp));
}

void require(bool condition, const char* message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

void writeArchive(const std::filesystem::path& path, const QString& prefix = QStringLiteral("portable"))
{
    MMCZip::ArchiveWriter archive(QString::fromStdString(path.string()));
    require(archive.open(), "archive could not be opened");
    const auto archivePath = [&](const QString& relative) {
        return prefix.isEmpty() ? relative : prefix + QLatin1Char('/') + relative;
    };
    require(archive.addFile(archivePath(QStringLiteral("instance.cfg")), QByteArrayLiteral(
                                "InstanceType=Minecraft\n"
                                "name=Archive Name\n"
                                "iconKey=grass\n"
                                "InstanceGroupId=Archive Group\n"
                                "totalTimePlayed=120\n")),
            "instance metadata could not be archived");
    require(archive.addFile(archivePath(QStringLiteral("mmc-pack.json")), QByteArrayLiteral(
                                "{\n"
                                "  \"formatVersion\": 1,\n"
                                "  \"components\": [\n"
                                "    { \"uid\": \"net.minecraft\", \"version\": \"1.20.1\" }\n"
                                "  ]\n"
                                "}\n")),
            "component list could not be archived");
    require(archive.addFile(archivePath(QStringLiteral("patches/net.minecraft.json")), QByteArrayLiteral(
                                "{\n"
                                "  \"formatVersion\": 1,\n"
                                "  \"name\": \"Minecraft\",\n"
                                "  \"uid\": \"net.minecraft\",\n"
                                "  \"version\": \"1.20.1\",\n"
                                "  \"id\": \"1.20.1\",\n"
                                "  \"type\": \"release\"\n"
                                "}\n")),
            "Minecraft metadata could not be archived");
    require(archive.addFile(archivePath(QStringLiteral("minecraft/mods/example.jar")), QByteArrayLiteral("mod bytes")),
            "instance resource could not be archived");
    require(archive.close(), "archive could not be closed");
}

void writeInvalidArchive(const std::filesystem::path& path)
{
    MMCZip::ArchiveWriter archive(QString::fromStdString(path.string()));
    require(archive.open(), "invalid archive could not be opened");
    require(archive.addFile(QStringLiteral("portable/readme.txt"), QByteArrayLiteral("not an instance")),
            "invalid archive entry could not be written");
    require(archive.close(), "invalid archive could not be closed");
}

std::vector<std::uint8_t> readBytes(const std::filesystem::path& path)
{
    QFile file(QString::fromStdString(path.string()));
    require(file.open(QIODevice::ReadOnly), "archive could not be read");
    const QByteArray bytes = file.readAll();
    return { reinterpret_cast<const std::uint8_t*>(bytes.constData()),
             reinterpret_cast<const std::uint8_t*>(bytes.constData()) + bytes.size() };
}

FrontendRuntimeDependencies minimalDependencies(
    const std::shared_ptr<ProductionInstanceAcquisitionRuntime>& acquisition)
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::now(); };
    dependencies.cancelPendingWork = [] {};
    dependencies.shutdown = [acquisition] { acquisition->shutdown(); };
    dependencies.importInstance = [acquisition](
                                      const std::filesystem::path&,
                                      const FrontendInstanceImportRequest& request,
                                      const FrontendRuntimeDependencies::InstanceImportProgressHandler& progress,
                                      const FrontendRuntimeDependencies::InstanceImportCancellationCheck& cancellation) {
        return acquisition->importInstance(request, progress, cancellation);
    };
    return dependencies;
}

}  // namespace

int main()
{
    const auto root = temporaryRoot();
    std::error_code cleanupError;
    try {
        std::filesystem::create_directories(root);

        FrontendFacade creationFacade(root, productionInstanceRuntimeDependencies(root));
        FrontendVanillaCreationRequest creationRequest;
        creationRequest.versionDescriptor = "1.20.1";
        creationRequest.versionName = "Minecraft 1.20.1";
        creationRequest.name = "Native Vanilla";
        creationRequest.groupId = "Survival";
        creationRequest.iconKey = "default";
        std::vector<FrontendTaskSnapshot> creationProgress;
        const auto created = creationFacade.createVanillaInstance(
            creationRequest, [&](const FrontendTaskSnapshot& snapshot) { creationProgress.push_back(snapshot); });
        require(created.outcome == FrontendVanillaCreationOutcome::Succeeded && created.instance.has_value(),
                "production vanilla creation did not commit");
        require(created.instance->groupId == "Survival" && !creationProgress.empty()
                    && created.localizationKey == "instances.creation.vanilla.created"
                    && creationProgress.back().state == FrontendTaskState::Succeeded
                    && creationProgress.back().terminalResult.has_value()
                    && creationProgress.back().terminalResult->localizationKey == created.localizationKey,
                "vanilla creation metadata or terminal progress was incomplete");
        const auto createdPath = root / "instances" / created.instance->id;
        require(std::filesystem::is_regular_file(createdPath / "instance.cfg")
                    && std::filesystem::is_regular_file(createdPath / "mmc-pack.json")
                    && std::filesystem::is_regular_file(createdPath / "patches/net.minecraft.json"),
                "vanilla Prism files were not staged and committed");
        creationFacade.shutdown();

        FrontendFacade reconstructedFacade(root, productionInstanceRuntimeDependencies(root));
        const auto reconstructedSnapshots = reconstructedFacade.instanceSnapshots();
        require(std::any_of(reconstructedSnapshots.begin(), reconstructedSnapshots.end(), [&](const auto& snapshot) {
                    return snapshot.id == created.instance->id && snapshot.groupId == "Survival";
                }),
                "vanilla instance did not survive facade reconstruction");
        reconstructedFacade.shutdown();

        const auto archivePath = root / "import.zip";
        writeArchive(archivePath);
        const auto rootlessArchivePath = root / "rootless-import.zip";
        writeArchive(rootlessArchivePath, QString());
        const auto invalidArchivePath = root / "invalid-import.zip";
        writeInvalidArchive(invalidArchivePath);
        const auto archiveBytes = readBytes(archivePath);
        bool fakeDownloadCalled = false;
        auto acquisition = makeProductionInstanceAcquisitionRuntime(
            root,
            [&](const std::string& source,
                const ProductionInstanceAcquisitionRuntime::DownloadProgressHandler& progress,
                const ProductionInstanceAcquisitionRuntime::DownloadCancellationCheck&) {
                fakeDownloadCalled = source == "https://example.invalid/instance.zip";
                if (progress) {
                    progress(archiveBytes.size(), archiveBytes.size());
                }
                return std::optional<ProductionInstanceAcquisitionRuntime::DownloadBytes>(archiveBytes);
            });
        FrontendFacade importFacade(root, minimalDependencies(acquisition));
        FrontendInstanceImportRequest importRequest;
        importRequest.sourceKind = FrontendInstanceImportSourceKind::RemoteURL;
        importRequest.source = "https://example.invalid/instance.zip";
        importRequest.name = "Imported Native";
        importRequest.groupId = "Imported Group";
        importRequest.iconKey = "default";
        std::vector<FrontendTaskSnapshot> importProgress;
        const auto imported = importFacade.importInstance(
            importRequest, [&](const FrontendTaskSnapshot& snapshot) { importProgress.push_back(snapshot); });
        require(fakeDownloadCalled && imported.outcome == FrontendInstanceImportOutcome::Succeeded
                    && imported.instance.has_value() && imported.instance->name == "Imported Native"
                    && imported.instance->groupId == "Imported Group"
                    && imported.localizationKey == "instances.import.completed"
                    && importProgress.back().state == FrontendTaskState::Succeeded
                    && importProgress.back().terminalResult.has_value()
                    && importProgress.back().terminalResult->localizationKey == imported.localizationKey,
                "fake URL import did not execute the production archive path");
        require(std::filesystem::is_regular_file(root / "instances" / imported.instance->id / "minecraft/mods/example.jar"),
                "imported instance content was not copied into the committed tree");

        FrontendInstanceImportRequest localRequest;
        localRequest.sourceKind = FrontendInstanceImportSourceKind::LocalFile;
        localRequest.source = rootlessArchivePath.string();
        localRequest.name = "Imported Local";
        localRequest.groupId = "Local Group";
        localRequest.iconKey = "default";
        const auto localImported = importFacade.importInstance(localRequest, [&](const auto& snapshot) {
            importProgress.push_back(snapshot);
        });
        require(localImported.outcome == FrontendInstanceImportOutcome::Succeeded && localImported.instance.has_value()
                    && localImported.instance->name == "Imported Local"
                    && localImported.localizationKey == "instances.import.completed"
                    && std::filesystem::is_regular_file(
                        root / "instances" / localImported.instance->id / "minecraft/mods/example.jar"),
                "local rootless archive import did not use the production archive path");

        localRequest.source = invalidArchivePath.string();
        localRequest.name = "Invalid Import";
        const auto invalidImport = importFacade.importInstance(localRequest, [&](const auto& snapshot) {
            importProgress.push_back(snapshot);
        });
        require(invalidImport.outcome == FrontendInstanceImportOutcome::Failed && invalidImport.partialChangesRolledBack
                    && invalidImport.localizationKey == "instances.import.failed"
                    && !std::filesystem::exists(root / "instances" / "Invalid Import")
                    && std::filesystem::is_empty(root / "instances" / ".prism-native-staging"),
                "invalid archive import did not roll back its staging tree");
        importFacade.shutdown();

        bool cancellationFlag = false;
        auto cancellationAcquisition = makeProductionInstanceAcquisitionRuntime(
            root,
            [&](const std::string&,
                const ProductionInstanceAcquisitionRuntime::DownloadProgressHandler& progress,
                const ProductionInstanceAcquisitionRuntime::DownloadCancellationCheck&) {
                if (progress) {
                    progress(archiveBytes.size(), archiveBytes.size());
                }
                cancellationFlag = true;
                return std::optional<ProductionInstanceAcquisitionRuntime::DownloadBytes>(archiveBytes);
            });
        FrontendFacade cancellationFacade(root, minimalDependencies(cancellationAcquisition));
        importRequest.name = "Cancelled Import";
        const auto cancelled = cancellationFacade.importInstance(importRequest, {}, [&] { return cancellationFlag; });
        require(cancelled.outcome == FrontendInstanceImportOutcome::Cancelled && cancelled.partialChangesRolledBack
                    && cancelled.localizationKey == "instances.import.cancelled"
                    && !std::filesystem::exists(root / "instances" / "Cancelled Import")
                    && std::filesystem::is_empty(root / "instances" / ".prism-native-staging"),
                "cancelled import did not roll back its staging tree");
        cancellationFacade.shutdown();
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        std::filesystem::remove_all(root, cleanupError);
        return 1;
    }

    std::filesystem::remove_all(root, cleanupError);
    return cleanupError ? 1 : 0;
}
