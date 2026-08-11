// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"
#include "ProductionInstanceRuntime.h"
#include "ProductionProviderRuntime.h"
#include "archive/ArchiveWriter.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>
#include <QUrlQuery>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using Bytes = ProductionProviderRuntime::DownloadBytes;

void require(bool condition, const char* message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

std::filesystem::path temporaryRoot()
{
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    return std::filesystem::temp_directory_path() / ("prism-native-provider-" + std::to_string(stamp));
}

Bytes bytes(const QByteArray& value)
{
    return { reinterpret_cast<const std::uint8_t*>(value.constData()),
             reinterpret_cast<const std::uint8_t*>(value.constData()) + value.size() };
}

Bytes textBytes(const char* value)
{
    return bytes(QByteArray(value));
}

void writeFile(const std::filesystem::path& path, const QByteArray& contents)
{
    std::filesystem::create_directories(path.parent_path());
    QFile file(QString::fromStdString(path.string()));
    require(file.open(QIODevice::WriteOnly | QIODevice::Truncate), "fixture file could not be opened");
    require(file.write(contents) == contents.size(), "fixture file could not be written");
    file.close();
}

QByteArray readFile(const std::filesystem::path& path)
{
    QFile file(QString::fromStdString(path.string()));
    require(file.open(QIODevice::ReadOnly), "fixture output could not be read");
    return file.readAll();
}

Bytes archiveBytes(
    const std::filesystem::path& root,
    const std::string& name,
    const std::vector<std::pair<QString, QByteArray>>& entries)
{
    const auto path = root / name;
    MMCZip::ArchiveWriter archive(QString::fromStdString(path.string()));
    require(archive.open(), "provider fixture archive could not be opened");
    for (const auto& [entry, contents] : entries) {
        require(archive.addFile(entry, contents), "provider fixture archive entry could not be added");
    }
    require(archive.close(), "provider fixture archive could not be closed");

    QFile file(QString::fromStdString(path.string()));
    require(file.open(QIODevice::ReadOnly), "provider fixture archive could not be read");
    return bytes(file.readAll());
}

struct RecordedProviderProtocol final {
    Bytes modrinthArchive;
    Bytes curseForgeArchive;
    Bytes genericArchive;
    std::map<std::string, int> calls;
    std::string failNeedle;
    std::string corruptNeedle;
    int failuresRemaining = 0;

    Bytes modrinthSearchResponse(const std::string& source) const
    {
        const QUrl url(QString::fromStdString(source));
        const QUrlQuery query(url);
        const int offset = query.queryItemValue(QStringLiteral("offset")).toInt();
        const int limit = query.queryItemValue(QStringLiteral("limit")).toInt();
        constexpr int total = 200;
        QJsonArray hits;
        for (int index = offset; index < std::min(offset + limit, total); ++index) {
            QJsonObject row;
            row.insert(QStringLiteral("project_id"),
                       index == 0 ? QStringLiteral("mr-pack")
                                  : (index == 1 ? QStringLiteral("mr-other")
                                                : QStringLiteral("mr-pack-%1").arg(index)));
            row.insert(QStringLiteral("title"), QStringLiteral("Native Pack %1").arg(index, 3, 10, QLatin1Char('0')));
            row.insert(QStringLiteral("slug"), QStringLiteral("native-pack-%1").arg(index));
            row.insert(QStringLiteral("description"), QStringLiteral("Native synthetic provider pack"));
            row.insert(QStringLiteral("author"), QStringLiteral("Fixture"));
            row.insert(QStringLiteral("categories"), QJsonArray{ QStringLiteral("adventure"), QStringLiteral("fabric") });
            hits.append(row);
        }
        QJsonObject root;
        root.insert(QStringLiteral("total_hits"), total);
        root.insert(QStringLiteral("hits"), hits);
        return bytes(QJsonDocument(root).toJson(QJsonDocument::Compact));
    }

    std::optional<Bytes> download(
        const std::string& source,
        const ProductionProviderRuntime::DownloadProgressHandler& progress,
        const ProductionProviderRuntime::DownloadCancellationCheck& cancellation)
    {
        ++calls[source];
        if ((cancellation && cancellation()) || (!failNeedle.empty() && failuresRemaining > 0
                                                  && source.find(failNeedle) != std::string::npos)) {
            if (!failNeedle.empty() && source.find(failNeedle) != std::string::npos && failuresRemaining > 0) {
                --failuresRemaining;
            }
            return std::nullopt;
        }

        const auto contains = [&](std::string_view needle) { return source.find(needle) != std::string::npos; };
        std::optional<Bytes> response;
        if (source == "https://fixture.invalid/modrinth.mrpack") {
            response = modrinthArchive;
        } else if (source == "https://fixture.invalid/curseforge.zip") {
            response = curseForgeArchive;
        } else if (source == "https://fixture.invalid/technic.zip" || contains("/modpacks/legacydir/1_0/legacy.zip")) {
            response = genericArchive;
        } else if (source == "https://fixture.invalid/mr-required") {
            response = textBytes("required modrinth bytes");
        } else if (source == "https://fixture.invalid/mr-optional") {
            response = textBytes("optional modrinth bytes");
        } else if (source == "https://fixture.invalid/cf-mod") {
            response = textBytes("curseforge mod bytes");
        } else if (source == "https://fixture.invalid/ftb-mod") {
            response = textBytes("ftb mod bytes");
        } else if (source == "https://fixture.invalid/at-required") {
            response = textBytes("atlauncher required bytes");
        } else if (source == "https://fixture.invalid/at-optional") {
            response = textBytes("atlauncher optional bytes");
        } else if (source == "https://fixture.invalid/at-blocked") {
            response = textBytes("atlauncher resolved blocked bytes");
        } else if (source == "https://fixture.invalid/solder-mod") {
            response = textBytes("technic solder bytes");
        } else if (contains("api.curseforge.com/v1/mods/901/files/902")) {
            response = textBytes(R"json({"data":{"id":902,"fileName":"cf-mod.jar","downloadUrl":"https://fixture.invalid/cf-mod"}})json");
        } else if (contains("api.modrinth.com/v2/version/mr-version")) {
            response = textBytes(R"json({
                "id":"mr-version","name":"1.0","version_number":"1.0","version_type":"release",
                "dependencies":{"minecraft":"1.20.1","fabric-loader":"0.15.0"},
                "files":[{"filename":"native.mrpack","url":"https://fixture.invalid/modrinth.mrpack","primary":true}]
            })json");
        } else if (contains("api.modrinth.com/v2/project/mr-pack/version")) {
            response = textBytes(R"json([
                {"id":"mr-version","name":"Native 1.0","version_number":"1.0","version_type":"release",
                 "game_versions":["1.20.1"],"loaders":["fabric"],"date_published":"2026-01-02T03:04:05.000Z","featured":true}
            ])json");
        } else if (contains("api.modrinth.com/v2/search?")) {
            response = modrinthSearchResponse(source);
        } else if (contains("api.curseforge.com/v1/mods/202/files/303")) {
            response = textBytes(R"json({"data":{"id":303,"downloadUrl":"https://fixture.invalid/curseforge.zip"}})json");
        } else if (contains("api.curseforge.com/v1/mods/202/files?")) {
            response = textBytes(R"json({"data":[
                {"id":303,"displayName":"CF 1.0","fileName":"cf-1.0.zip","gameVersions":["1.20.1"],"modLoaderType":4,
                 "releaseType":1,"fileDate":"2026-01-02T03:04:05.000Z"}
            ]})json");
        } else if (contains("api.curseforge.com/v1/mods/search?")) {
            response = textBytes(R"json({
                "data":[{"id":202,"name":"Native CurseForge","slug":"native-cf","summary":"Fixture pack",
                         "authors":[{"name":"Fixture"}],"categories":[{"name":"Adventure"}]}],
                "pagination":{"totalCount":1}
            })json");
        } else if (contains("api.feed-the-beast.com/v1/modpacks/public/modpack/303/404")) {
            response = textBytes(R"json({
                "id":404,"parent":303,"name":"1.0","type":"release","installs":1,"plays":2,"updated":3,"refreshed":4,
                "specs":{"id":1,"minimum":1,"recommended":1},
                "targets":[{"id":1,"name":"Minecraft","type":"minecraft","version":"1.20.1","updated":3}],
                "files":[{"id":501,"type":"mod","path":"mods/ftb.jar","name":"FTB Mod","version":"1.0",
                          "url":"https://fixture.invalid/ftb-mod","sha1":"4aa70ab73005d12a422fe32ad45217e3bfc1f487","size":9,"clientonly":false,
                          "serveronly":false,"optional":false,"updated":3,"curseforge":{}}]
            })json");
        } else if (contains("api.feed-the-beast.com/v1/modpacks/public/modpack/303")) {
            response = textBytes(ftbPackJson());
        } else if (contains("api.feed-the-beast.com/v1/modpacks/public/modpack/all")) {
            response = textBytes((std::string("{\"packs\":[") + ftbPackJson() + "]}").c_str());
        } else if (contains("download.nodecdn.net/containers/atl/packs/ATPack/versions/1.0/Configs.json")) {
            response = textBytes(R"json({
                "version":"1.0","minecraft":"1.20.1","noConfigs":true,
                "loader":{"type":"fabric","choose":false,
                          "metadata":{"latest":false,"recommended":true,"loader":"0.15.0"}},
                "mods":[
                    {"name":"Required AT","version":"1","url":"https://fixture.invalid/at-required","file":"required-at.jar","md5":"7b1655554c7b45fffe7fc61188ccfb97","download":"direct","type":"mods","optional":false},
                    {"name":"Optional AT","version":"1","url":"https://fixture.invalid/at-optional","file":"optional-at.jar","md5":"67ae51df5f9b21df1a02458774f0f143","download":"direct","type":"mods","optional":true,"recommended":true},
                    {"name":"Blocked AT","version":"1","url":"https://fixture.invalid/at-blocked","file":"blocked-at.jar","md5":"ed2729c218009c69a09e99bc0114ed68","download":"browser","type":"mods","optional":false}
                ],
                "colours":{},"warnings":{},"messages":{},"keeps":{},"deletes":{}
            })json");
        } else if (contains("download.nodecdn.net/containers/atl/launcher/json/packsnew.json")) {
            response = textBytes(R"json([
                {"id":1,"position":1,"name":"AT Pack","type":"public","system":false,"description":"Native AT fixture",
                 "versions":[{"version":"1.0","minecraft":"1.20.1"}]}
            ])json");
        } else if (source == "https://fixture.invalid/solder/modpack/technic-pack/2.0") {
            response = textBytes(R"json({"minecraft":"1.20.1","mods":[
                {"name":"solder-mod","version":"1.0","md5":"e581000622c0c680cd711773afb6c535","url":"https://fixture.invalid/solder-mod"}
            ]})json");
        } else if (source == "https://fixture.invalid/solder/modpack/technic-pack") {
            response = textBytes(R"json({"recommended":"2.0","latest":"2.0","builds":["1.0","2.0"]})json");
        } else if (contains("api.technicpack.net/modpack/technic-zip?")) {
            response = textBytes(R"json({"slug":"technic-zip","name":"Native Technic ZIP","version":"1.0",
                "minecraft":"1.20.1","url":"https://fixture.invalid/technic.zip"})json");
        } else if (contains("api.technicpack.net/modpack/technic-pack?")) {
            response = textBytes(R"json({"slug":"technic-pack","name":"Native Technic","version":"1.0","minecraft":"1.20.1",
                "url":"https://fixture.invalid/technic.zip","solder":"https://fixture.invalid/solder/"})json");
        } else if (contains("api.technicpack.net/search?") || contains("api.technicpack.net/trending?")) {
            response = textBytes(R"json({"modpacks":[
                {"slug":"technic-pack","name":"Native Technic","description":"Fixture pack","user":"Fixture"}
            ]})json");
        } else if (contains("dist.creeper.host/FTB2/static/thirdparty.xml")) {
            response = textBytes(R"xml(<root><modpack name="Native Third-Party Legacy" version="2.0" mcVersion="1.19.4"
                description="Third-party fixture pack" author="Fixture" dir="thirdparty" url="third.zip" oldVersions="1.0;2.0"/></root>)xml");
        } else if (contains("dist.creeper.host/FTB2/static/modpacks.xml")) {
            response = textBytes(R"xml(<root><modpack name="Native Legacy" version="1.0" mcVersion="1.20.1"
                description="Fixture pack" author="Fixture" dir="legacydir" url="legacy.zip" oldVersions="0.9;1.0"/></root>)xml");
        }

        if (response.has_value() && !corruptNeedle.empty() && source.find(corruptNeedle) != std::string::npos) {
            response = textBytes("corrupt provider bytes");
        }
        if (response.has_value() && progress) {
            progress(response->size(), response->size());
        }
        return response;
    }

    static const char* ftbPackJson()
    {
        return R"json({
            "id":303,"name":"Native FTB","synopsis":"Fixture pack","description":"Synthetic FTB pack","type":"public",
            "featured":false,"installs":1,"plays":2,"updated":3,"refreshed":4,"art":[],
            "authors":[{"id":1,"name":"Fixture","type":"author","website":"https://example.invalid","updated":3}],
            "versions":[{"id":404,"name":"1.0","type":"release","updated":3,"specs":{"id":1,"minimum":1,"recommended":1}}],
            "tags":[{"id":1,"name":"Adventure"}]
        })json";
    }
};

FrontendRuntimeDependencies providerDependencies(const std::shared_ptr<ProductionProviderRuntime>& runtime)
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::now(); };
    dependencies.cancelPendingWork = [] {};
    dependencies.shutdown = [runtime] { runtime->shutdown(); };
    dependencies.browseProvider = [runtime](
                                             const std::filesystem::path&,
                                             const FrontendProviderBrowseRequest& request,
                                             const FrontendRuntimeDependencies::ProviderBrowseProgressHandler& progress,
                                             const FrontendRuntimeDependencies::ProviderBrowseCancellationCheck& cancellation) {
        return runtime->browse(request, progress, cancellation);
    };
    dependencies.loadProviderVersions = [runtime](
                                                   const std::filesystem::path&,
                                                   const FrontendProviderVersionRequest& request,
                                                   const FrontendRuntimeDependencies::ProviderVersionProgressHandler& progress,
                                                   const FrontendRuntimeDependencies::ProviderVersionCancellationCheck& cancellation) {
        return runtime->versions(request, progress, cancellation);
    };
    dependencies.installProviderPack = [runtime](
                                                  const std::filesystem::path&,
                                                  const FrontendProviderInstallRequest& request,
                                                  const FrontendRuntimeDependencies::ProviderInstallProgressHandler& progress,
                                                  const FrontendRuntimeDependencies::ProviderInstallCancellationCheck& cancellation) {
        return runtime->install(request, progress, cancellation);
    };
    return dependencies;
}

FrontendProviderBrowseRequest browseRequest(FrontendProviderKind provider)
{
    FrontendProviderBrowseRequest request;
    request.provider = provider;
    request.pageSize = 20;
    return request;
}

FrontendProviderVersionRequest versionRequest(FrontendProviderKind provider, std::string identifier)
{
    FrontendProviderVersionRequest request;
    request.provider = provider;
    request.packIdentifier = std::move(identifier);
    return request;
}

FrontendProviderInstallRequest installRequest(
    FrontendProviderInstallKind kind,
    std::string pack,
    std::string version,
    std::string name,
    std::filesystem::path source = {})
{
    FrontendProviderInstallRequest request;
    request.kind = kind;
    request.packIdentifier = std::move(pack);
    request.versionIdentifier = std::move(version);
    request.name = std::move(name);
    request.groupId = "Provider Fixtures";
    request.iconKey = "default";
    request.sourcePath = std::move(source);
    return request;
}

void requireSucceeded(
    const FrontendProviderInstallResult& result,
    const std::vector<FrontendTaskSnapshot>& progress,
    const char* message)
{
    require(result.outcome == FrontendProviderInstallOutcome::Succeeded && result.instance.has_value(), message);
    require(result.rollbackOutcome == FrontendProviderInstallRollbackOutcome::NotRequired
                && !progress.empty() && progress.back().state == FrontendTaskState::Succeeded
                && progress.back().terminalResult.has_value()
                && progress.back().terminalResult->outcome == FrontendTaskTerminalOutcome::Succeeded,
            "provider install terminal progress was incomplete");
}

}  // namespace

int main()
{
    const auto root = temporaryRoot();
    std::error_code cleanupError;
    try {
        std::filesystem::create_directories(root);
        RecordedProviderProtocol protocol;
        protocol.modrinthArchive = archiveBytes(
            root,
            "modrinth.mrpack",
            {
                { QStringLiteral("modrinth.index.json"), QByteArrayLiteral(R"json({
                    "formatVersion":1,"game":"minecraft","versionId":"fixture","name":"Native Modrinth",
                    "dependencies":{"minecraft":"1.20.1","fabric-loader":"0.15.0"},
                    "files":[
                        {"path":"mods/required.jar","hashes":{"sha1":"e168f7970b55179ff3ea1d9e2a6ae8707aa9df04"},"downloads":["https://fixture.invalid/mr-required"],"env":{"client":"required"}},
                        {"path":"mods/optional.jar","hashes":{"sha1":"ee07e263a501801b5e2eb93618696fed9ba3b81d"},"downloads":["https://fixture.invalid/mr-optional"],"env":{"client":"optional"}}
                    ]
                })json") },
                { QStringLiteral("overrides/options.txt"), QByteArrayLiteral("native options") },
            });
        protocol.curseForgeArchive = archiveBytes(
            root,
            "curseforge.zip",
            {
                { QStringLiteral("manifest.json"), QByteArrayLiteral(R"json({
                    "minecraft":{"version":"1.20.1","modLoaders":[{"id":"fabric-0.15.0","primary":true}]},
                    "files":[{"projectID":901,"fileID":902,"required":true}]
                })json") },
                { QStringLiteral("overrides/config/native.txt"), QByteArrayLiteral("curse config") },
            });
        protocol.genericArchive = archiveBytes(
            root,
            "generic.zip",
            { { QStringLiteral("minecraft/mods/archive.jar"), QByteArrayLiteral("archive mod") } });

        const auto customSource = root / "custom-source";
        const auto ftbImportSource = root / "ftb-import-source";
        writeFile(customSource / "minecraft/mods/custom.jar", QByteArrayLiteral("custom mod"));
        writeFile(customSource / "mmc-pack.json", QByteArrayLiteral(R"json({
            "formatVersion":1,"components":[
                {"uid":"net.minecraft","version":"1.19.4","important":true},
                {"uid":"net.fabricmc.fabric-loader","version":"0.14.25"}
            ]
        })json"));
        writeFile(ftbImportSource / "minecraft/mods/ftb-import.jar", QByteArrayLiteral("ftb import mod"));
        writeFile(ftbImportSource / "instance.json", QByteArrayLiteral(R"json({
            "uuid":"fixture","id":1,"versionId":2,"name":"FTB Import","version":"1.0",
            "mcVersion":"1.18.2","totalPlayTime":0,"jvmArgs":"","modLoader":"forge-40.2.0"
        })json"));

        auto runtime = makeProductionProviderRuntime(
            root,
            [&](const std::string& source,
                const ProductionProviderRuntime::DownloadProgressHandler& progress,
                const ProductionProviderRuntime::DownloadCancellationCheck& cancellation) {
                return protocol.download(source, progress, cancellation);
            });
        FrontendFacade facade(root, providerDependencies(runtime));

        FrontendProviderBrowseRequest modrinthBrowse = browseRequest(FrontendProviderKind::Modrinth);
        modrinthBrowse.query = "Native";
        modrinthBrowse.pageSize = 2;
        modrinthBrowse.sort = FrontendProviderSort::Name;
        modrinthBrowse.gameVersions = { "1.20.1" };
        modrinthBrowse.loaders = { "fabric" };
        modrinthBrowse.categories = { "adventure" };
        modrinthBrowse.side = FrontendProviderSide::Client;
        modrinthBrowse.openSource = true;
        std::vector<FrontendTaskSnapshot> browseProgress;
        const auto modrinthPage = facade.browseProvider(
            modrinthBrowse, [&](const auto& snapshot) { browseProgress.push_back(snapshot); });
        require(modrinthPage.outcome == FrontendProviderBrowseOutcome::Succeeded && modrinthPage.page.has_value()
                    && modrinthPage.page->packs.size() == 2 && modrinthPage.page->nextOffset == 2
                    && browseProgress.back().state == FrontendTaskState::Succeeded,
                "Modrinth production browse did not preserve filtering or server pagination");
        bool encodedFacetsObserved = false;
        for (const auto& [url, count] : protocol.calls) {
            if (count > 0 && url.find("api.modrinth.com/v2/search?") != std::string::npos) {
                const auto decoded = QUrl::fromPercentEncoding(QByteArray::fromStdString(url));
                encodedFacetsObserved = decoded.contains(QStringLiteral("open_source:true"))
                    && decoded.contains(QStringLiteral("project_type:modpack"))
                    && decoded.contains(QStringLiteral("client_side:required"));
            }
        }
        require(encodedFacetsObserved, "Modrinth production browse did not encode source and side facets");

        auto pressureBrowse = browseRequest(FrontendProviderKind::Modrinth);
        std::set<std::string> pressureIdentifiers;
        std::size_t pressurePages = 0;
        do {
            const auto pageResult = facade.browseProvider(pressureBrowse);
            require(pageResult.outcome == FrontendProviderBrowseOutcome::Succeeded && pageResult.page.has_value()
                        && pageResult.page->offset == pressureBrowse.offset,
                    "Modrinth production pressure page was invalid");
            for (const auto& pack : pageResult.page->packs) {
                require(pressureIdentifiers.insert(pack.id).second, "Modrinth production pagination repeated a pack");
            }
            ++pressurePages;
            if (!pageResult.page->nextOffset.has_value()) {
                break;
            }
            pressureBrowse.offset = *pageResult.page->nextOffset;
        } while (pressurePages <= 10);
        require(pressurePages == 10 && pressureIdentifiers.size() == 200,
                "Modrinth production pagination did not cover the ten-page pressure fixture");

        auto curseBrowse = browseRequest(FrontendProviderKind::CurseForge);
        curseBrowse.gameVersions = { "1.20.1" };
        curseBrowse.loaders = { "fabric" };
        require(facade.browseProvider(curseBrowse).page->packs.front().id == "202",
                "CurseForge production browse did not parse the recorded protocol");
        require(facade.browseProvider(browseRequest(FrontendProviderKind::FTB)).page->packs.front().id == "303",
                "FTB production browse did not reuse the FTB manifest parser");
        require(facade.browseProvider(browseRequest(FrontendProviderKind::ATLauncher)).page->packs.front().id == "AT Pack",
                "ATLauncher production browse did not reuse the pack index parser");
        require(facade.browseProvider(browseRequest(FrontendProviderKind::Technic)).page->packs.front().id == "technic-pack",
                "Technic production browse did not parse the recorded protocol");
        require(facade.browseProvider(browseRequest(FrontendProviderKind::LegacyFTB)).page->packs.front().id
                    == "legacydir|legacy.zip",
                "Legacy FTB production browse did not parse the recorded XML");
        auto thirdPartyBrowse = browseRequest(FrontendProviderKind::LegacyFTB);
        thirdPartyBrowse.query = "thirdparty:";
        require(facade.browseProvider(thirdPartyBrowse).page->packs.front().id == "thirdparty|third.zip",
                "Legacy FTB production browse did not parse the recorded third-party XML");

        auto modrinthVersions = versionRequest(FrontendProviderKind::Modrinth, "mr-pack");
        modrinthVersions.gameVersions = { "1.20.1" };
        modrinthVersions.loaders = { "fabric" };
        modrinthVersions.releaseTypes = { FrontendProviderReleaseType::Release };
        require(facade.providerVersions(modrinthVersions).versions.front().id == "mr-version",
                "Modrinth production versions did not apply compatibility filters");
        modrinthVersions.releaseTypes = { FrontendProviderReleaseType::Alpha };
        require(facade.providerVersions(modrinthVersions).versions.empty(),
                "Modrinth production versions did not apply release filters");
        auto curseVersions = versionRequest(FrontendProviderKind::CurseForge, "202");
        curseVersions.gameVersions = { "1.20.1" };
        curseVersions.loaders = { "fabric" };
        require(facade.providerVersions(curseVersions).versions.front().id == "303",
                "CurseForge production versions did not normalize loader metadata");
        auto ftbVersions = versionRequest(FrontendProviderKind::FTB, "303");
        ftbVersions.gameVersions = { "1.20.1" };
        require(!facade.providerVersions(ftbVersions).versions.empty(),
                "FTB production versions were empty");
        auto atLauncherVersions = versionRequest(FrontendProviderKind::ATLauncher, "AT Pack");
        atLauncherVersions.loaders = { "fabric" };
        require(facade.providerVersions(atLauncherVersions).versions.size() == 1,
                "ATLauncher production versions did not resolve loader metadata");
        atLauncherVersions.loaders = { "forge" };
        require(facade.providerVersions(atLauncherVersions).versions.empty(),
                "ATLauncher production versions did not apply loader filters");
        const auto technicVersions =
            facade.providerVersions(versionRequest(FrontendProviderKind::Technic, "technic-pack")).versions;
        require(technicVersions.size() == 2
                    && std::all_of(technicVersions.begin(), technicVersions.end(), [](const auto& version) {
                           return version.installKind == FrontendProviderInstallKind::TechnicSolder;
                       }),
                "Technic Solder production versions did not retain their installation task family");
        const auto technicZipVersions =
            facade.providerVersions(versionRequest(FrontendProviderKind::Technic, "technic-zip")).versions;
        require(technicZipVersions.size() == 1
                    && technicZipVersions.front().installKind == FrontendProviderInstallKind::TechnicZip,
                "Technic archive versions did not retain their installation task family");
        require(facade.providerVersions(versionRequest(FrontendProviderKind::LegacyFTB, "legacydir|legacy.zip"))
                        .versions.size()
                    == 2,
                "Legacy FTB production versions were not parsed");
        const auto thirdPartyVersions =
            facade.providerVersions(versionRequest(FrontendProviderKind::LegacyFTB, "thirdparty|third.zip"));
        require(thirdPartyVersions.versions.size() == 2
                    && thirdPartyVersions.versions.front().gameVersions == std::vector<std::string>{ "1.19.4" },
                "Legacy FTB third-party versions were not parsed from the matching list");

        std::vector<FrontendTaskSnapshot> installProgress;
        auto modrinthInstall = installRequest(
            FrontendProviderInstallKind::Modrinth, "mr-pack", "mr-version", "Installed Modrinth");
        protocol.failNeedle = "/version/mr-version";
        protocol.failuresRemaining = 1;
        auto networkFailure = facade.installProviderPack(modrinthInstall);
        require(networkFailure.outcome == FrontendProviderInstallOutcome::Failed && networkFailure.recoveryPrompt.has_value()
                    && networkFailure.recoveryPrompt->kind == FrontendProviderInstallRecoveryKind::NetworkError
                    && networkFailure.rollbackOutcome == FrontendProviderInstallRollbackOutcome::Applied
                    && std::filesystem::is_empty(root / "instances/.prism-native-provider-staging"),
                "provider network failure did not return recovery and rollback evidence");
        protocol.failNeedle.clear();
        modrinthInstall.recoveryDecision = FrontendProviderInstallRecoveryDecision{
            FrontendProviderInstallRecoveryKind::NetworkError,
            FrontendProviderInstallRecoveryAction::Retry,
            {},
            {},
        };
        const auto optionalPrompt = facade.installProviderPack(modrinthInstall);
        require(optionalPrompt.recoveryPrompt.has_value()
                    && optionalPrompt.recoveryPrompt->kind == FrontendProviderInstallRecoveryKind::OptionalFiles
                    && optionalPrompt.recoveryPrompt->files.front().selected,
                "Modrinth optional-file recovery prompt was not produced after retry");
        modrinthInstall.recoveryDecision = FrontendProviderInstallRecoveryDecision{
            FrontendProviderInstallRecoveryKind::OptionalFiles,
            FrontendProviderInstallRecoveryAction::Continue,
            { "ee07e263a501801b5e2eb93618696fed9ba3b81d" },
            {},
        };
        const auto modrinthInstalled = facade.installProviderPack(
            modrinthInstall, [&](const auto& snapshot) { installProgress.push_back(snapshot); });
        requireSucceeded(modrinthInstalled, installProgress, "Modrinth production install did not commit");
        require(std::filesystem::is_regular_file(root / "instances/Installed Modrinth/minecraft/mods/required.jar")
                    && std::filesystem::is_regular_file(root / "instances/Installed Modrinth/minecraft/mods/optional.jar")
                    && std::filesystem::is_regular_file(root / "instances/Installed Modrinth/.prism-native-provider.json"),
                "Modrinth selected files or provenance metadata were not committed");

        auto hiddenBrowse = modrinthBrowse;
        hiddenBrowse.hideInstalled = true;
        const auto hiddenPage = facade.browseProvider(hiddenBrowse);
        require(hiddenPage.page.has_value() && hiddenPage.page->packs.size() == 1
                    && hiddenPage.page->packs.front().id == "mr-other",
                "hide-installed did not use persisted provider provenance");

        installProgress.clear();
        requireSucceeded(
            facade.installProviderPack(
                installRequest(FrontendProviderInstallKind::CurseForgeFlame, "202", "303", "Installed CurseForge"),
                [&](const auto& snapshot) { installProgress.push_back(snapshot); }),
            installProgress,
            "CurseForge production install did not commit");
        require(std::filesystem::is_regular_file(root / "instances/Installed CurseForge/minecraft/mods/cf-mod.jar")
                    && std::filesystem::is_regular_file(root / "instances/Installed CurseForge/minecraft/config/native.txt"),
                "CurseForge manifest files or overrides were not committed");

        installProgress.clear();
        requireSucceeded(
            facade.installProviderPack(
                installRequest(FrontendProviderInstallKind::FTB, "303", "404", "Installed FTB"),
                [&](const auto& snapshot) { installProgress.push_back(snapshot); }),
            installProgress,
            "FTB production install did not commit");
        require(std::filesystem::is_regular_file(root / "instances/Installed FTB/minecraft/mods/ftb.jar"),
                "FTB manifest file was not committed");

        auto atInstall = installRequest(
            FrontendProviderInstallKind::ATLauncher, "AT Pack", "1.0", "Installed ATLauncher");
        const auto atOptional = facade.installProviderPack(atInstall);
        require(atOptional.recoveryPrompt.has_value()
                    && atOptional.recoveryPrompt->kind == FrontendProviderInstallRecoveryKind::OptionalFiles,
                "ATLauncher optional-file prompt was not returned");
        atInstall.recoveryDecision = FrontendProviderInstallRecoveryDecision{
            FrontendProviderInstallRecoveryKind::OptionalFiles,
            FrontendProviderInstallRecoveryAction::Continue,
            { "optional-at.jar" },
            {},
        };
        const auto atBlocked = facade.installProviderPack(atInstall);
        require(atBlocked.recoveryPrompt.has_value()
                    && atBlocked.recoveryPrompt->kind == FrontendProviderInstallRecoveryKind::BlockedFiles,
                "ATLauncher blocked-file prompt did not follow optional-file confirmation");
        atInstall.recoveryDecision = FrontendProviderInstallRecoveryDecision{
            FrontendProviderInstallRecoveryKind::BlockedFiles,
            FrontendProviderInstallRecoveryAction::Continue,
            { "optional-at.jar" },
            { "blocked-at.jar" },
        };
        installProgress.clear();
        requireSucceeded(
            facade.installProviderPack(atInstall, [&](const auto& snapshot) { installProgress.push_back(snapshot); }),
            installProgress,
            "ATLauncher production install did not preserve two-stage recovery selections");
        require(std::filesystem::is_regular_file(root / "instances/Installed ATLauncher/minecraft/mods/required-at.jar")
                    && std::filesystem::is_regular_file(root / "instances/Installed ATLauncher/minecraft/mods/optional-at.jar")
                    && std::filesystem::is_regular_file(root / "instances/Installed ATLauncher/minecraft/mods/blocked-at.jar"),
                "ATLauncher optional or resolved blocked file was skipped");

        for (const auto& request : {
                 installRequest(FrontendProviderInstallKind::TechnicZip, "technic-pack", "1.0", "Installed Technic Zip"),
                 installRequest(FrontendProviderInstallKind::TechnicSolder, "technic-pack", "2.0", "Installed Technic Solder"),
                 installRequest(FrontendProviderInstallKind::LegacyFTB, "legacydir|legacy.zip", "1.0", "Installed Legacy FTB"),
                 installRequest(FrontendProviderInstallKind::CustomArchive, "custom", "1", "Installed Custom", customSource),
                 installRequest(FrontendProviderInstallKind::FTBImport, "ftb-import", "1", "Installed FTB Import", ftbImportSource),
             }) {
            installProgress.clear();
            requireSucceeded(
                facade.installProviderPack(request, [&](const auto& snapshot) { installProgress.push_back(snapshot); }),
                installProgress,
                "one production provider install family did not commit");
        }
        require(std::filesystem::is_regular_file(root / "instances/Installed Technic Zip/minecraft/mods/archive.jar")
                    && std::filesystem::is_regular_file(root / "instances/Installed Technic Solder/minecraft/mods/solder-mod.jar")
                    && std::filesystem::is_regular_file(root / "instances/Installed Legacy FTB/minecraft/mods/archive.jar")
                    && std::filesystem::is_regular_file(root / "instances/Installed Custom/minecraft/mods/custom.jar")
                    && std::filesystem::is_regular_file(root / "instances/Installed FTB Import/minecraft/mods/ftb-import.jar"),
                "provider archive or local-source content was not committed");
        require(readFile(root / "instances/Installed Custom/mmc-pack.json").contains("1.19.4")
                    && readFile(root / "instances/Installed Custom/mmc-pack.json").contains("net.fabricmc.fabric-loader")
                    && readFile(root / "instances/Installed FTB Import/mmc-pack.json").contains("1.18.2")
                    && readFile(root / "instances/Installed FTB Import/mmc-pack.json").contains("net.minecraftforge"),
                "local provider metadata was not reconstructed from the selected source");

        const auto unsafeArchive = root / "unsafe-provider.zip";
        MMCZip::ArchiveWriter unsafeWriter(QString::fromStdString(unsafeArchive.string()));
        require(unsafeWriter.open() && unsafeWriter.addFile(QStringLiteral("../escaped.txt"), QByteArrayLiteral("escape"))
                    && unsafeWriter.close(),
                "unsafe provider fixture archive could not be written");
        const auto unsafeResult = facade.installProviderPack(installRequest(
            FrontendProviderInstallKind::CustomArchive, "unsafe", "1", "Unsafe Provider", unsafeArchive));
        require(unsafeResult.outcome == FrontendProviderInstallOutcome::Failed
                    && unsafeResult.rollbackOutcome == FrontendProviderInstallRollbackOutcome::Applied
                    && !std::filesystem::exists(root / "escaped.txt")
                    && !std::filesystem::exists(root / "instances/Unsafe Provider"),
                "unsafe provider archive path was not rejected and rolled back");

        const int searchCallsBeforeReconstruction = std::accumulate(
            protocol.calls.begin(), protocol.calls.end(), 0, [](int total, const auto& entry) {
                return total + (entry.first.find("api.modrinth.com/v2/search?") != std::string::npos ? entry.second : 0);
            });
        facade.shutdown();
        auto cachedRuntime = makeProductionProviderRuntime(
            root,
            [&](const std::string& source,
                const ProductionProviderRuntime::DownloadProgressHandler& progress,
                const ProductionProviderRuntime::DownloadCancellationCheck& cancellation) {
                return protocol.download(source, progress, cancellation);
            });
        FrontendFacade cachedFacade(root, providerDependencies(cachedRuntime));
        require(cachedFacade.browseProvider(modrinthBrowse).outcome == FrontendProviderBrowseOutcome::Succeeded,
                "provider cache did not survive runtime reconstruction");
        const int searchCallsAfterReconstruction = std::accumulate(
            protocol.calls.begin(), protocol.calls.end(), 0, [](int total, const auto& entry) {
                return total + (entry.first.find("api.modrinth.com/v2/search?") != std::string::npos ? entry.second : 0);
            });
        require(searchCallsAfterReconstruction == searchCallsBeforeReconstruction
                    && !std::filesystem::is_empty(root / "provider-cache/modrinth"),
                "provider reconstruction bypassed or lost the deterministic cache");
        cachedFacade.shutdown();

        const auto cacheBoundRoot = root / "cache-bound";
        auto cacheBoundRuntime = makeProductionProviderRuntime(
            cacheBoundRoot,
            [&](const std::string& source,
                const ProductionProviderRuntime::DownloadProgressHandler& progress,
                const ProductionProviderRuntime::DownloadCancellationCheck& cancellation) {
                return protocol.download(source, progress, cancellation);
            });
        for (int index = 0; index < 300; ++index) {
            writeFile(cacheBoundRoot / "provider-cache/modrinth" / ("stale-" + std::to_string(index) + ".bin"),
                      QByteArrayLiteral("stale"));
        }
        FrontendFacade cacheBoundFacade(cacheBoundRoot, providerDependencies(cacheBoundRuntime));
        require(cacheBoundFacade.browseProvider(browseRequest(FrontendProviderKind::Modrinth)).outcome
                    == FrontendProviderBrowseOutcome::Succeeded,
                "bounded provider cache fixture did not browse");
        std::size_t retainedCacheEntries = 0;
        for (std::filesystem::recursive_directory_iterator iterator(cacheBoundRoot / "provider-cache"), end;
             iterator != end;
             ++iterator) {
            if (iterator->is_regular_file()) {
                ++retainedCacheEntries;
            }
        }
        require(retainedCacheEntries <= 256, "provider cache entry bound was not enforced");
        cacheBoundFacade.shutdown();

        FrontendFacade reconstructed(root, productionInstanceRuntimeDependencies(root));
        const auto reconstructedInstances = reconstructed.instanceSnapshots();
        require(reconstructedInstances.size() >= 9
                    && std::any_of(reconstructedInstances.begin(), reconstructedInstances.end(), [](const auto& snapshot) {
                           return snapshot.name == "Installed ATLauncher";
                       }),
                "provider instances did not survive default production-composition reconstruction");
        reconstructed.shutdown();

        const auto cancellationRoot = root / "cancellation";
        bool cancellationFlag = false;
        auto cancellationRuntime = makeProductionProviderRuntime(
            cancellationRoot,
            [&](const std::string& source,
                const ProductionProviderRuntime::DownloadProgressHandler& progress,
                const ProductionProviderRuntime::DownloadCancellationCheck& cancellation) {
                auto response = protocol.download(source, progress, cancellation);
                cancellationFlag = true;
                return response;
            });
        FrontendFacade cancellationFacade(cancellationRoot, providerDependencies(cancellationRuntime));
        const auto cancelled = cancellationFacade.installProviderPack(
            installRequest(FrontendProviderInstallKind::Modrinth, "mr-pack", "mr-version", "Cancelled Provider"),
            {},
            [&] { return cancellationFlag; });
        require(cancelled.outcome == FrontendProviderInstallOutcome::Cancelled
                    && cancelled.rollbackOutcome == FrontendProviderInstallRollbackOutcome::Applied
                    && !std::filesystem::exists(cancellationRoot / "instances/Cancelled Provider")
                    && std::filesystem::is_empty(cancellationRoot / "instances/.prism-native-provider-staging"),
                "provider cancellation did not roll back the production staging tree");
        cancellationFacade.shutdown();

        const auto integrityRoot = root / "integrity-failure";
        protocol.corruptNeedle = "https://fixture.invalid/ftb-mod";
        auto integrityRuntime = makeProductionProviderRuntime(
            integrityRoot,
            [&](const std::string& source,
                const ProductionProviderRuntime::DownloadProgressHandler& progress,
                const ProductionProviderRuntime::DownloadCancellationCheck& cancellation) {
                return protocol.download(source, progress, cancellation);
            });
        FrontendFacade integrityFacade(integrityRoot, providerDependencies(integrityRuntime));
        const auto integrityFailure = integrityFacade.installProviderPack(
            installRequest(FrontendProviderInstallKind::FTB, "303", "404", "Integrity Failure"));
        require(integrityFailure.outcome == FrontendProviderInstallOutcome::Failed
                    && integrityFailure.recoveryPrompt.has_value()
                    && integrityFailure.recoveryPrompt->kind == FrontendProviderInstallRecoveryKind::NetworkError
                    && integrityFailure.rollbackOutcome == FrontendProviderInstallRollbackOutcome::Applied
                    && !std::filesystem::exists(integrityRoot / "instances/Integrity Failure"),
                "provider hash mismatch did not fail safely and roll back");
        integrityFacade.shutdown();
        protocol.corruptNeedle.clear();

        const auto diskRoot = root / "disk-failure";
        auto diskRuntime = makeProductionProviderRuntime(diskRoot, {});
        const auto staging = diskRoot / "instances/.prism-native-provider-staging";
        std::filesystem::remove(staging);
        std::filesystem::create_directory(diskRoot / "unsafe-target");
        std::filesystem::create_directory_symlink(diskRoot / "unsafe-target", staging);
        FrontendFacade diskFacade(diskRoot, providerDependencies(diskRuntime));
        const auto diskFailure = diskFacade.installProviderPack(installRequest(
            FrontendProviderInstallKind::CustomArchive, "disk", "1", "Disk Failure", customSource));
        require(diskFailure.outcome == FrontendProviderInstallOutcome::Failed && diskFailure.recoveryPrompt.has_value()
                    && diskFailure.recoveryPrompt->kind == FrontendProviderInstallRecoveryKind::DiskError
                    && !std::filesystem::exists(diskRoot / "instances/Disk Failure"),
                "provider disk containment failure did not return typed recovery");
        diskFacade.shutdown();
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        std::filesystem::remove_all(root, cleanupError);
        return 1;
    }

    std::filesystem::remove_all(root, cleanupError);
    return cleanupError ? 1 : 0;
}
