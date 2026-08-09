// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"
#include "GZip.h"
#include "ProductionInstanceRuntime.h"
#include "archive/ArchiveReader.h"
#include "archive/ArchiveWriter.h"
#include "settings/INIFile.h"

#include <io/stream_writer.h>
#include <tag_compound.h>
#include <tag_list.h>
#include <tag_primitive.h>

#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

std::filesystem::path temporaryRoot()
{
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    return std::filesystem::temp_directory_path() / ("prism-native-instance-detail-" + std::to_string(stamp));
}

void require(bool condition, const char* message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

void writeText(const std::filesystem::path& path, const std::string& text)
{
    std::filesystem::create_directories(path.parent_path());
    std::ofstream file(path, std::ios::binary);
    file << text;
    require(file.good(), "fixture text could not be written");
}

void writeBytes(const std::filesystem::path& path, const QByteArray& bytes)
{
    std::filesystem::create_directories(path.parent_path());
    QFile file(QString::fromStdString(path.string()));
    require(file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size(), "fixture bytes could not be written");
}

void writeGzip(const std::filesystem::path& path, const std::string& text)
{
    QByteArray compressed;
    require(GZip::zip(QByteArray::fromStdString(text), compressed), "fixture gzip could not be created");
    writeBytes(path, compressed);
}

void writeWorldLevel(const std::filesystem::path& worldPath, const std::string& name, std::int64_t lastPlayed)
{
    nbt::tag_compound data{
        { "LevelName", name },
        { "LastPlayed", nbt::tag_long(lastPlayed) },
        { "GameType", nbt::tag_int(0) },
        { "RandomSeed", nbt::tag_long(123456789) },
    };
    nbt::tag_compound root{ { "Data", std::move(data) } };
    std::ostringstream encoded;
    nbt::io::write_tag("", root, encoded);
    QByteArray compressed;
    require(GZip::zip(QByteArray::fromStdString(encoded.str()), compressed), "world level.dat could not be compressed");
    writeBytes(worldPath / "level.dat", compressed);
}

void writeServers(const std::filesystem::path& path)
{
    nbt::tag_compound server{ { "name", "Fixture Server" }, { "ip", "example.invalid:25565" } };
    nbt::tag_compound root{ { "servers", nbt::tag_list{ std::move(server) } } };
    std::ostringstream encoded;
    nbt::io::write_tag("", root, encoded);
    writeBytes(path, QByteArray::fromStdString(encoded.str()));
}

void writeInstanceFixture(const std::filesystem::path& root)
{
    const auto instance = root / "instances" / "detail.fixture";
    const auto game = instance / "minecraft";
    std::filesystem::create_directories(game / "mods");
    std::filesystem::create_directories(game / "resourcepacks");
    std::filesystem::create_directories(game / "shaderpacks");
    std::filesystem::create_directories(game / "screenshots");
    std::filesystem::create_directories(game / "logs");
    std::filesystem::create_directories(game / "saves" / "World One");
    std::filesystem::create_directories(instance / "patches");
    std::filesystem::create_directories(instance / "libraries");

    INIFile settings;
    settings.set("InstanceType", QStringLiteral("Minecraft"));
    settings.set("name", QStringLiteral("Detail Fixture"));
    settings.set("iconKey", QStringLiteral("grass"));
    settings.set("InstanceGroupId", QStringLiteral("Survival"));
    settings.set("notes", QStringLiteral("Initial notes"));
    require(settings.saveFile(QString::fromStdString((instance / "instance.cfg").string())), "instance.cfg could not be written");

    writeText(instance / "mmc-pack.json", R"JSON({
  "formatVersion": 1,
  "components": [ { "uid": "net.minecraft", "cachedName": "Minecraft", "cachedVersion": "1.20.1" } ]
})JSON");
    writeText(instance / "patches" / "net.minecraft.json", R"JSON({
  "formatVersion": 1,
  "name": "Minecraft",
  "uid": "net.minecraft",
  "version": "1.20.1",
  "id": "1.20.1",
  "type": "release",
  "mainClass": "com.example.Main",
  "minecraftArguments": "--username ${auth_player_name}",
  "mainJar": { "name": "com.example:minecraft:1.20.1", "MMC-hint": "local", "MMC-filename": "minecraft.jar" }
})JSON");

    writeText(game / "mods" / "example.jar.disabled", "disabled mod");
    writeText(game / "resourcepacks" / "pack.zip", "resource pack");
    writeText(game / "shaderpacks" / "shader.zip", "shader pack");
    writeWorldLevel(game / "saves" / "World One", "World One", 1700000000000);
    writeText(game / "saves" / "World One" / "icon.png", "icon");
    writeText(game / "screenshots" / "shot.PNG", "png bytes");
    writeText(game / "logs" / "latest.log", "normal line\npassword=fixture-password\n");
    writeGzip(game / "logs" / "old.log.gz", "access_token=fixture-access-token\nold line\n");
    writeServers(game / "servers.dat");
}

void writeWorldArchive(const std::filesystem::path& archivePath, const std::filesystem::path& levelPath)
{
    MMCZip::ArchiveWriter archive(QString::fromStdString(archivePath.string()));
    require(archive.open(), "valid world archive could not open");
    require(archive.addFile(QString::fromStdString(levelPath.string()), QStringLiteral("level.dat")),
            "valid world archive could not add level.dat");
    require(archive.close(), "valid world archive could not close");
}

const FrontendInstanceWorldSnapshot* findWorld(
    const std::vector<FrontendInstanceWorldSnapshot>& worlds, const std::string& identifier)
{
    for (const auto& world : worlds) {
        if (world.id == identifier) {
            return &world;
        }
    }
    return nullptr;
}

const FrontendInstanceResourceSnapshot* findResource(
    const std::vector<FrontendInstanceResourceSnapshot>& resources, const std::string& identifier)
{
    for (const auto& resource : resources) {
        if (resource.id == identifier) {
            return &resource;
        }
    }
    return nullptr;
}

}  // namespace

int main()
{
    const auto root = temporaryRoot();
    std::error_code cleanupError;
    try {
        std::filesystem::create_directories(root / "instances");
        writeInstanceFixture(root);
        const auto instance = root / "instances" / "detail.fixture";
        const auto game = instance / "minecraft";

        FrontendFacade facade(root, productionInstanceRuntimeDependencies(root));
        const auto details = facade.instanceDetails("detail.fixture");
        require(details.has_value() && details->name == "Detail Fixture" && details->groupId == "Survival"
                    && details->notes == "Initial notes",
                "production instance metadata was not loaded");
        const auto components = facade.instanceComponents("detail.fixture");
        require(components.has_value() && components->size() == 1 && components->front().version == "1.20.1",
                "production component metadata was not loaded");
        const auto mods = facade.instanceResources("detail.fixture", FrontendInstanceResourceKind::Mods);
        require(mods.has_value() && findResource(*mods, "example.jar.disabled") != nullptr
                    && !findResource(*mods, "example.jar.disabled")->enabled,
                "disabled mod was not discovered");
        const auto resourcePacks = facade.instanceResources("detail.fixture", FrontendInstanceResourceKind::ResourcePacks);
        const auto shaderPacks = facade.instanceResources("detail.fixture", FrontendInstanceResourceKind::ShaderPacks);
        require(resourcePacks.has_value() && resourcePacks->size() == 1 && shaderPacks.has_value() && shaderPacks->size() == 1,
                "resource-pack and shader-pack folders were not discovered");
        const auto worlds = facade.instanceWorlds("detail.fixture");
        require(worlds.has_value() && findWorld(*worlds, "World One") != nullptr
                    && findWorld(*worlds, "World One")->hasSeed && findWorld(*worlds, "World One")->gameMode == "Survival",
                "world NBT metadata was not loaded");
        const auto servers = facade.instanceServers("detail.fixture");
        require(servers.has_value() && servers->size() == 1 && servers->front().address == "example.invalid:25565",
                "servers.dat was not loaded");
        const auto screenshots = facade.instanceScreenshots("detail.fixture");
        require(screenshots.has_value() && screenshots->size() == 1 && screenshots->front().fileName == "shot.PNG",
                "screenshots were not discovered case-insensitively");
        const auto logs = facade.instanceLogFiles("detail.fixture");
        require(logs.has_value() && logs->size() == 2, "instance logs were not discovered");
        const auto oldLog = facade.instanceLog("detail.fixture", "old.log.gz");
        require(oldLog.has_value() && oldLog->truncated == false && !oldLog->entries.empty()
                    && oldLog->entries.front().text.find("fixture-access-token") == std::string::npos
                    && oldLog->entries.front().text.find("<redacted>") != std::string::npos,
                "compressed instance logs were not bounded and redacted");

        std::mutex observationMutex;
        std::condition_variable observationCondition;
        bool observedCopy = false;
        require(facade.startInstanceObservation([&](const FrontendInstanceChange& change) {
                    if (change.kind == FrontendInstanceChangeKind::Added && change.instance.name == "Copied Detail") {
                        std::lock_guard<std::mutex> lock(observationMutex);
                        observedCopy = true;
                        observationCondition.notify_all();
                    }
                }),
                "instance change observation did not start");

        auto notesResult = facade.updateInstanceNotes("detail.fixture", "Updated notes");
        require(notesResult.outcome == FrontendInstanceNotesUpdateOutcome::Succeeded && notesResult.notes == "Updated notes",
                "notes were not persisted");

        FrontendInstanceResourceMutationRequest enableMod;
        enableMod.action = FrontendInstanceResourceAction::Enable;
        enableMod.resourceIdentifier = "example.jar.disabled";
        auto enabled = facade.mutateInstanceResource("detail.fixture", FrontendInstanceResourceKind::Mods, enableMod);
        require(enabled.outcome == FrontendInstanceResourceMutationOutcome::Succeeded,
                "disabled resource could not be enabled");

        FrontendInstanceResourceMutationRequest importResource;
        importResource.action = FrontendInstanceResourceAction::Import;
        importResource.resourceIdentifier = "imported.jar";
        importResource.sourcePath = root / "outside" / "imported.jar";
        writeText(importResource.sourcePath, "imported");
        auto imported = facade.mutateInstanceResource("detail.fixture", FrontendInstanceResourceKind::Mods, importResource);
        require(imported.outcome == FrontendInstanceResourceMutationOutcome::Succeeded,
                "resource import did not commit");
        auto importConflict = facade.mutateInstanceResource("detail.fixture", FrontendInstanceResourceKind::Mods, importResource);
        require(importConflict.outcome == FrontendInstanceResourceMutationOutcome::Failed
                    && importConflict.localizationKey == "instance.resource.conflict",
                "resource import conflict was not reported");

        std::filesystem::create_directories(root / "outside" / "bad-resource");
        std::error_code symlinkError;
        std::filesystem::create_symlink(root / "outside" / "imported.jar", root / "outside" / "bad-resource" / "escape.jar", symlinkError);
        require(!symlinkError, "symlink fixture could not be created");
        FrontendInstanceResourceMutationRequest badImport;
        badImport.action = FrontendInstanceResourceAction::Import;
        badImport.resourceIdentifier = "bad-resource";
        badImport.sourcePath = root / "outside" / "bad-resource";
        auto rolledBackResource = facade.mutateInstanceResource("detail.fixture", FrontendInstanceResourceKind::Mods, badImport);
        require(rolledBackResource.outcome == FrontendInstanceResourceMutationOutcome::Failed
                    && rolledBackResource.partialChangesRolledBack
                    && !std::filesystem::exists(game / "mods" / "bad-resource"),
                "symlink resource import did not roll back safely");

        writeText(game / "mods" / "conflict.jar", "existing");
        writeText(game / "mods" / "conflict.jar.disabled", "disabled");
        FrontendInstanceResourceMutationRequest enableConflict;
        enableConflict.action = FrontendInstanceResourceAction::Enable;
        enableConflict.resourceIdentifier = "conflict.jar.disabled";
        auto resourceConflict = facade.mutateInstanceResource("detail.fixture", FrontendInstanceResourceKind::Mods, enableConflict);
        require(resourceConflict.outcome == FrontendInstanceResourceMutationOutcome::Failed
                    && resourceConflict.localizationKey == "instance.resource.conflict",
                "resource enable conflict was not reported");

        const auto permissionPath = game / "mods";
        std::filesystem::permissions(permissionPath, std::filesystem::perms::owner_read | std::filesystem::perms::owner_exec,
                                      std::filesystem::perm_options::replace, symlinkError);
        FrontendInstanceResourceMutationRequest permissionMutation;
        permissionMutation.action = FrontendInstanceResourceAction::Disable;
        permissionMutation.resourceIdentifier = "example.jar";
        auto permissionResult = facade.mutateInstanceResource("detail.fixture", FrontendInstanceResourceKind::Mods, permissionMutation);
        std::filesystem::permissions(permissionPath,
                                      std::filesystem::perms::owner_read | std::filesystem::perms::owner_write
                                          | std::filesystem::perms::owner_exec,
                                      std::filesystem::perm_options::replace, symlinkError);
        require(permissionResult.outcome == FrontendInstanceResourceMutationOutcome::Failed,
                "resource permission failure was not surfaced");

        FrontendInstanceDetailMutationRequest renameWorld;
        renameWorld.kind = FrontendInstanceDetailKind::Worlds;
        renameWorld.action = FrontendInstanceDetailAction::Rename;
        renameWorld.itemIdentifier = "World One";
        renameWorld.targetName = "Renamed World";
        auto renamedWorld = facade.mutateInstanceDetail("detail.fixture", renameWorld);
        require(renamedWorld.outcome == FrontendInstanceDetailMutationOutcome::Succeeded,
                "world rename did not commit");

        FrontendInstanceDetailMutationRequest copyWorld;
        copyWorld.kind = FrontendInstanceDetailKind::Worlds;
        copyWorld.action = FrontendInstanceDetailAction::Copy;
        copyWorld.itemIdentifier = "Renamed World";
        copyWorld.targetName = "Copied World";
        auto copiedWorld = facade.mutateInstanceDetail("detail.fixture", copyWorld);
        require(copiedWorld.outcome == FrontendInstanceDetailMutationOutcome::Succeeded,
                "world copy did not commit");

        FrontendInstanceDetailMutationRequest deleteWorld;
        deleteWorld.kind = FrontendInstanceDetailKind::Worlds;
        deleteWorld.action = FrontendInstanceDetailAction::Delete;
        deleteWorld.itemIdentifier = "Copied World";
        deleteWorld.confirmed = true;
        auto deletedWorld = facade.mutateInstanceDetail("detail.fixture", deleteWorld);
        require(deletedWorld.outcome == FrontendInstanceDetailMutationOutcome::Succeeded,
                "world delete did not commit");

        const auto invalidArchive = root / "outside" / "invalid-world.zip";
        writeText(invalidArchive, "not a zip archive");
        FrontendInstanceDetailMutationRequest invalidImport;
        invalidImport.kind = FrontendInstanceDetailKind::Worlds;
        invalidImport.action = FrontendInstanceDetailAction::Import;
        invalidImport.itemIdentifier = "Invalid World";
        invalidImport.sourcePath = invalidArchive;
        auto invalidArchiveResult = facade.mutateInstanceDetail("detail.fixture", invalidImport);
        require(invalidArchiveResult.outcome == FrontendInstanceDetailMutationOutcome::Rejected
                    && invalidArchiveResult.localizationKey == "instance.world.invalid-archive"
                    && !std::filesystem::exists(game / "saves" / "Invalid World"),
                "invalid world archive was not rejected without a partial directory");

        const auto validArchive = root / "outside" / "valid-world.zip";
        writeWorldArchive(validArchive, game / "saves" / "Renamed World" / "level.dat");
        FrontendInstanceDetailMutationRequest validImport = invalidImport;
        validImport.itemIdentifier = "Imported World";
        validImport.sourcePath = validArchive;
        auto validArchiveResult = facade.mutateInstanceDetail("detail.fixture", validImport);
        require(validArchiveResult.outcome == FrontendInstanceDetailMutationOutcome::Succeeded,
                "valid world archive was not imported");

        FrontendInstanceDetailMutationRequest renameScreenshot;
        renameScreenshot.kind = FrontendInstanceDetailKind::Screenshots;
        renameScreenshot.action = FrontendInstanceDetailAction::Rename;
        renameScreenshot.itemIdentifier = "shot.PNG";
        renameScreenshot.targetName = "renamed.png";
        auto renamedScreenshot = facade.mutateInstanceDetail("detail.fixture", renameScreenshot);
        require(renamedScreenshot.outcome == FrontendInstanceDetailMutationOutcome::Succeeded,
                "screenshot rename did not commit");

        FrontendInstanceDetailMutationRequest deleteCurrentLog;
        deleteCurrentLog.kind = FrontendInstanceDetailKind::Logs;
        deleteCurrentLog.action = FrontendInstanceDetailAction::Delete;
        deleteCurrentLog.itemIdentifier = "latest.log";
        deleteCurrentLog.confirmed = true;
        auto protectedLog = facade.mutateInstanceDetail("detail.fixture", deleteCurrentLog);
        require(protectedLog.outcome == FrontendInstanceDetailMutationOutcome::Rejected,
                "current log deletion was not protected");
        deleteCurrentLog.itemIdentifier = "old.log.gz";
        auto deletedLog = facade.mutateInstanceDetail("detail.fixture", deleteCurrentLog);
        require(deletedLog.outcome == FrontendInstanceDetailMutationOutcome::Succeeded,
                "historical log deletion did not commit");

        FrontendInstanceDetailMutationRequest addServer;
        addServer.kind = FrontendInstanceDetailKind::Servers;
        addServer.action = FrontendInstanceDetailAction::Add;
        addServer.name = "Added Server";
        addServer.address = "added.invalid:25565";
        addServer.resourcePolicy = FrontendServerResourcePolicy::Never;
        auto addedServer = facade.mutateInstanceDetail("detail.fixture", addServer);
        require(addedServer.outcome == FrontendInstanceDetailMutationOutcome::Succeeded
                    && addedServer.itemIdentifier == "server-1",
                "server add did not persist a stable identifier");

        FrontendInstanceDetailMutationRequest updateServer;
        updateServer.kind = FrontendInstanceDetailKind::Servers;
        updateServer.action = FrontendInstanceDetailAction::Update;
        updateServer.itemIdentifier = "server-1";
        updateServer.name = "Updated Server";
        updateServer.address = "updated.invalid:25565";
        updateServer.resourcePolicy = FrontendServerResourcePolicy::Always;
        auto updatedServer = facade.mutateInstanceDetail("detail.fixture", updateServer);
        require(updatedServer.outcome == FrontendInstanceDetailMutationOutcome::Succeeded,
                "server update did not persist");

        FrontendInstanceCopyRequest copyRequest;
        copyRequest.sourceInstanceIdentifier = "detail.fixture";
        copyRequest.name = "Copied Detail";
        copyRequest.groupId = "Copies";
        copyRequest.iconKey = "grass";
        std::vector<FrontendTaskSnapshot> copyProgress;
        const auto copied = facade.copyInstance(
            copyRequest,
            [&](const FrontendTaskSnapshot& snapshot) { copyProgress.push_back(snapshot); },
            [] { return false; });
        require(copied.outcome == FrontendInstanceCopyOutcome::Succeeded && copied.instance.has_value()
                    && copied.instance->name == "Copied Detail" && !copyProgress.empty()
                    && copyProgress.back().state == FrontendTaskState::Succeeded,
                "production instance copy did not commit with terminal progress");
        {
            std::unique_lock<std::mutex> lock(observationMutex);
            require(observationCondition.wait_for(lock, std::chrono::seconds(3), [&] { return observedCopy; }),
                    "instance observation did not report the copied instance");
        }

        FrontendInstanceExportRequest zipExport;
        zipExport.kind = FrontendInstanceExportKind::ZipArchive;
        zipExport.sourceInstanceIdentifier = "detail.fixture";
        zipExport.destinationPath = root / "exports" / "detail.zip";
        std::vector<FrontendTaskSnapshot> exportProgress;
        const auto exported = facade.exportInstance(
            zipExport,
            [&](const FrontendTaskSnapshot& snapshot) { exportProgress.push_back(snapshot); },
            [] { return false; });
        require(exported.outcome == FrontendInstanceExportOutcome::Succeeded && std::filesystem::exists(zipExport.destinationPath)
                    && !exportProgress.empty() && exportProgress.back().state == FrontendTaskState::Succeeded,
                "ZIP export did not commit with terminal progress");
        MMCZip::ArchiveReader exportedArchive(QString::fromStdString(zipExport.destinationPath.string()));
        require(exportedArchive.collectFiles() && exportedArchive.exists("instance.cfg")
                    && exportedArchive.exists("minecraft/saves/Renamed World/level.dat"),
                "ZIP export was not a valid readable instance archive");

        FrontendInstanceExportRequest modListExport;
        modListExport.kind = FrontendInstanceExportKind::ModList;
        modListExport.sourceInstanceIdentifier = "detail.fixture";
        modListExport.destinationPath = root / "exports" / "mods.json";
        modListExport.modListFormat = FrontendModListExportFormat::JSON;
        modListExport.modListFieldMask = kFrontendModListFieldFilename;
        const auto modList = facade.exportInstance(modListExport, {}, [] { return false; });
        require(modList.outcome == FrontendInstanceExportOutcome::Succeeded && std::filesystem::exists(modListExport.destinationPath),
                "mod-list export did not commit");

        bool unconfirmedDeleteRejected = false;
        try {
            static_cast<void>(facade.deleteInstance(copied.instance->id, false));
        } catch (const std::invalid_argument&) {
            unconfirmedDeleteRejected = true;
        }
        require(unconfirmedDeleteRejected, "instance deletion did not require explicit confirmation");

        const auto nativeTrash = root / "instances" / ".prism-native-trash";
        std::filesystem::create_symlink(root / "outside", nativeTrash, symlinkError);
        require(!symlinkError, "delete recovery symlink fixture could not be created");
        const auto blockedDelete = facade.deleteInstance(copied.instance->id, true);
        require(blockedDelete.outcome == FrontendInstanceDeleteOutcome::Failed
                    && std::filesystem::exists(root / "instances" / copied.instance->id),
                "unsafe delete recovery path was not rejected safely");
        std::filesystem::remove(nativeTrash, symlinkError);
        require(!symlinkError, "delete recovery symlink fixture could not be removed");

        const auto deletedCopy = facade.deleteInstance(copied.instance->id, true);
        require(deletedCopy.outcome == FrontendInstanceDeleteOutcome::Succeeded
                    && !std::filesystem::exists(root / "instances" / copied.instance->id)
                    && std::filesystem::exists(nativeTrash / copied.instance->id),
                "confirmed instance deletion did not move the tree into isolated recovery storage");
        const auto deletedAgain = facade.deleteInstance(copied.instance->id, true);
        require(deletedAgain.outcome == FrontendInstanceDeleteOutcome::UnknownInstance,
                "deleting an already removed instance was not reported as unknown");

        facade.stopInstanceObservation();
        facade.shutdown();

        FrontendFacade reconstructed(root, productionInstanceRuntimeDependencies(root));
        const auto reconstructedDetails = reconstructed.instanceDetails("detail.fixture");
        require(reconstructedDetails.has_value() && reconstructedDetails->notes == "Updated notes",
                "notes did not survive facade reconstruction");
        const auto reconstructedWorlds = reconstructed.instanceWorlds("detail.fixture");
        require(reconstructedWorlds.has_value() && findWorld(*reconstructedWorlds, "Renamed World") != nullptr
                    && findWorld(*reconstructedWorlds, "Imported World") != nullptr
                    && findWorld(*reconstructedWorlds, "Copied World") == nullptr,
                "world mutations did not survive facade reconstruction");
        const auto reconstructedServers = reconstructed.instanceServers("detail.fixture");
        require(reconstructedServers.has_value() && reconstructedServers->size() == 2
                    && reconstructedServers->at(1).name == "Updated Server",
                "server mutations did not survive facade reconstruction");
        const auto reconstructedScreenshots = reconstructed.instanceScreenshots("detail.fixture");
        require(reconstructedScreenshots.has_value() && reconstructedScreenshots->front().fileName == "renamed.png",
                "screenshot mutation did not survive facade reconstruction");
        const auto reconstructedLogs = reconstructed.instanceLogFiles("detail.fixture");
        require(reconstructedLogs.has_value() && reconstructedLogs->size() == 1 && reconstructedLogs->front().current,
                "log deletion did not survive facade reconstruction");
        const auto reconstructedCopy = reconstructed.instanceDetails(copied.instance->id);
        require(!reconstructedCopy.has_value(), "deleted copied instance reappeared after facade reconstruction");
        reconstructed.shutdown();
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        std::filesystem::remove_all(root, cleanupError);
        return 1;
    }

    std::filesystem::remove_all(root, cleanupError);
    return cleanupError ? 1 : 0;
}
