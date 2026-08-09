// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"
#include "ProductionAccountRuntime.h"
#include "ProductionLaunchRuntime.h"

#include "settings/INIFile.h"

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {

std::filesystem::path temporaryRoot()
{
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    return std::filesystem::temp_directory_path() / ("prism-native-launch-" + std::to_string(stamp));
}

void require(bool condition, const char* message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

void writeSyntheticAccounts(const std::filesystem::path& root)
{
    std::ofstream file(root / "accounts.json");
    file << R"JSON({
  "formatVersion": 3,
  "accounts": [
    {
      "type": "Offline",
      "profile": {
        "id": "fixture.profile",
        "name": "Fixture_Player",
        "skin": { "id": "", "url": "", "variant": "" },
        "capes": []
      },
      "entitlement": { "ownsMinecraft": true, "canPlayMinecraft": true },
      "active": true
    }
  ]
})JSON";
    require(file.good(), "synthetic account file could not be written");
}

void writeGlobalFixture(const std::filesystem::path& root)
{
    std::filesystem::create_directories(root / "jars");
    std::ofstream jar(root / "jars" / "NewLaunch.jar");
    require(jar.good(), "launcher jar fixture could not be created");

    INIFile settings;
    settings.set("JavaPath", QStringLiteral("/usr/bin/java"));
    settings.set("JavaVersion", QStringLiteral("17"));
    settings.set("JavaArchitecture", QStringLiteral("64"));
    settings.set("JavaRealArchitecture", QStringLiteral("arm64"));
    require(settings.saveFile(QString::fromStdString((root / "prismlauncher.cfg").string())),
            "global launch settings could not be written");
}

void writeInstanceFixture(const std::filesystem::path& root, const std::string& identifier, bool complete)
{
    const auto instancePath = root / "instances" / identifier;
    std::filesystem::create_directories(instancePath / "minecraft");
    std::filesystem::create_directories(instancePath / "patches");
    std::filesystem::create_directories(instancePath / "libraries");

    INIFile instance;
    instance.set("name", QStringLiteral("Launch Fixture"));
    instance.set("iconKey", QStringLiteral("default"));
    instance.set("JavaPath", QStringLiteral("/usr/bin/java"));
    instance.set("JavaVersion", QStringLiteral("17"));
    instance.set("JavaArchitecture", QStringLiteral("64"));
    instance.set("JavaRealArchitecture", QStringLiteral("arm64"));
    instance.set("MinMemAlloc", 512);
    instance.set("MaxMemAlloc", 2048);
    instance.set("JvmArgs", QStringLiteral("-DfixtureJvm=true"));
    instance.set("Env", QStringLiteral("{\"CUSTOM_SECRET\":\"fixture-secret\"}"));
    require(instance.saveFile(QString::fromStdString((instancePath / "instance.cfg").string())),
            "instance launch settings could not be written");
    if (!complete) {
        return;
    }

    std::ofstream components(instancePath / "mmc-pack.json");
    components << R"JSON({
  "formatVersion": 1,
  "components": [ { "uid": "net.minecraft" } ]
})JSON";
    require(components.good(), "component file could not be written");

    std::ofstream patch(instancePath / "patches" / "net.minecraft.json");
    patch << R"JSON({
  "formatVersion": 1,
  "name": "Minecraft",
  "uid": "net.minecraft",
  "version": "1.20.1",
  "id": "1.20.1",
  "type": "release",
  "mainClass": "com.example.Main",
  "minecraftArguments": "--username ${auth_player_name} --session ${auth_session} --version ${version_name} --gameDir ${game_directory} --profile ${profile_name}",
  "mainJar": {
    "name": "com.example:minecraft:1.20.1",
    "MMC-hint": "local",
    "MMC-filename": "minecraft.jar"
  },
  "libraries": [
    {
      "name": "com.example:game:1.0",
      "MMC-hint": "local",
      "MMC-filename": "game.jar"
    }
  ]
})JSON";
    require(patch.good(), "component patch could not be written");

    std::ofstream mainJar(instancePath / "libraries" / "minecraft.jar");
    std::ofstream library(instancePath / "libraries" / "game.jar");
    require(mainJar.good() && library.good(), "local library fixtures could not be created");
}

struct FakeProcess final {
    std::mutex mutex;
    std::condition_variable condition;
    ProductionLaunchRuntime::ProcessSpec capturedSpec;
    bool started = false;
    bool succeedAutomatically = false;
    int invocationCount = 0;

    void setSucceedAutomatically(bool value)
    {
        std::lock_guard<std::mutex> lock(mutex);
        succeedAutomatically = value;
        condition.notify_all();
    }

    ProductionLaunchRuntime::ProcessResult run(
        const ProductionLaunchRuntime::ProcessSpec& spec,
        const ProductionLaunchRuntime::ProcessLogHandler& log,
        const ProductionLaunchRuntime::CancellationCheck& cancelled)
    {
        {
            std::lock_guard<std::mutex> lock(mutex);
            capturedSpec = spec;
            started = true;
            ++invocationCount;
            condition.notify_all();
        }
        if (log) {
            log("access_token=fixture-access-token process output");
        }
        while (!(cancelled && cancelled())) {
            std::unique_lock<std::mutex> lock(mutex);
            condition.wait_for(lock, std::chrono::milliseconds(10));
            if (succeedAutomatically) {
                return { ProductionLaunchRuntime::ProcessResult::Outcome::Succeeded, 0, {} };
            }
        }
        return { ProductionLaunchRuntime::ProcessResult::Outcome::Cancelled, -1, "cancelled" };
    }
};

FrontendRuntimeDependencies dependenciesFor(const std::shared_ptr<ProductionLaunchRuntime>& runtime)
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] { return std::chrono::system_clock::now(); };
    dependencies.cancelPendingWork = [runtime] { runtime->cancelPendingWork(); };
    dependencies.shutdown = [runtime] { runtime->shutdown(); };
    return productionLaunchRuntimeDependencies(runtime, std::move(dependencies));
}

}  // namespace

int main()
{
    const auto root = temporaryRoot();
    std::error_code cleanupError;
    try {
        std::filesystem::create_directories(root / "instances");
        writeGlobalFixture(root);
        writeSyntheticAccounts(root);
        writeInstanceFixture(root, "launch.fixture", true);

        auto accountRuntime = makeProductionAccountRuntime(root, ProductionAccountRuntime::defaultDependencies());
        auto fake = std::make_shared<FakeProcess>();
        auto runtime = makeProductionLaunchRuntime(
            root,
            [fake](const ProductionLaunchRuntime::ProcessSpec& spec,
                   const ProductionLaunchRuntime::ProcessLogHandler& log,
                   const ProductionLaunchRuntime::CancellationCheck& cancelled) {
                return fake->run(spec, log, cancelled);
            },
            [accountRuntime](const std::string& instanceIdentifier) {
                return accountRuntime->launchSessionForInstance(instanceIdentifier);
            });
        FrontendFacade facade(root, dependenciesFor(runtime));

        std::mutex observationMutex;
        std::condition_variable observationCondition;
        std::vector<FrontendTaskSnapshot> observations;
        require(facade.startTaskObservation([&](const FrontendTaskSnapshot& snapshot) {
                    std::lock_guard<std::mutex> lock(observationMutex);
                    observations.push_back(snapshot);
                    observationCondition.notify_all();
                }),
                "task observation did not start");

        require(facade.launchInstance("launch.fixture") == FrontendInstanceCommandResult::Succeeded,
                "launch command was rejected");
        {
            std::unique_lock<std::mutex> lock(fake->mutex);
            if (!fake->condition.wait_for(lock, std::chrono::seconds(3), [&] { return fake->started; })) {
                const auto failed = facade.taskSnapshot(ProductionLaunchRuntime::taskIdentifierForInstance("launch.fixture"));
                if (failed.has_value() && failed->terminalResult.has_value()) {
                    std::cerr << failed->terminalResult->localizationKey << ": "
                              << failed->terminalResult->diagnosticText << '\n';
                }
                throw std::runtime_error("fake process was not invoked");
            }
            const auto instancePath = root / "instances" / "launch.fixture";
            const auto expectedClassPath = (root / "jars" / "NewLaunch.jar").string()
                + ":" + (instancePath / "libraries" / "game.jar").string()
                + ":" + (instancePath / "libraries" / "minecraft.jar").string();
            require(fake->capturedSpec.program == "/usr/bin/java", "Java executable was not isolated exactly");
            require(
                fake->capturedSpec.arguments
                    == std::vector<std::string>{
                        "-Duser.language=en",
                        "-DfixtureJvm=true",
                        "-Xdock:icon=icon.png",
                        "-Xdock:name=\"Prism: Launch Fixture\"",
                        "-Xms512m",
                        "-Xmx2048m",
                        "-Djava.library.path=" + (instancePath / "natives").string(),
                        "-cp",
                        expectedClassPath,
                        "org.prismlauncher.EntryPoint",
                    },
                "production Java arguments were not constructed exactly");
            require(fake->capturedSpec.workingDirectory == instancePath / "minecraft",
                    "Minecraft working directory was not isolated");
            require(fake->capturedSpec.environment.at("CUSTOM_SECRET") == "fixture-secret"
                        && fake->capturedSpec.environment.at("NO_COLOR") == "1"
                        && fake->capturedSpec.environment.at("INST_ID") == "launch.fixture"
                        && fake->capturedSpec.environment.at("INST_MC_DIR") == (instancePath / "minecraft").string(),
                    "launch environment was not constructed exactly");
            const std::string expectedInput =
                "mainClass com.example.Main\n"
                "param --username\n"
                "param Fixture_Player\n"
                "param --session\n"
                "param -\n"
                "param --version\n"
                "param 1.20.1\n"
                "param --gameDir\nparam "
                + (instancePath / "minecraft").string()
                + "\nparam --profile\nparam Launch Fixture\n"
                  "windowTitle Prism: Launch Fixture\n"
                  "windowParams 854x480\n"
                  "launcherBrand Prism\n"
                  "launcherVersion 0.0.0\n"
                  "instanceName Launch Fixture\n"
                  "instanceIconKey Launch Fixture\n"
                  "instanceIconPath icon.png\n"
                  "userName Fixture_Player\n"
                  "sessionId -\n"
                  "launcher standard\n";
            if (fake->capturedSpec.standardInput != expectedInput || fake->capturedSpec.launchInput != "launch\n") {
                std::cerr << "actual NewLaunch input:\n" << fake->capturedSpec.standardInput;
                throw std::runtime_error("NewLaunch standard input was not reconstructed exactly");
            }
        }

        const auto taskIdentifier = ProductionLaunchRuntime::taskIdentifierForInstance("launch.fixture");
        const auto running = facade.taskSnapshot(taskIdentifier);
        require(running.has_value() && running->state == FrontendTaskState::Running && running->cancellationAllowed,
                "running task snapshot was not observable");
        require(facade.cancelTask(taskIdentifier) == FrontendTaskCancellationResult::Requested,
                "task cancellation was not requested");

        bool cancelled = false;
        {
            std::unique_lock<std::mutex> lock(observationMutex);
            cancelled = observationCondition.wait_for(lock, std::chrono::seconds(3), [&] {
                return std::any_of(observations.begin(), observations.end(), [&](const FrontendTaskSnapshot& snapshot) {
                    return snapshot.id == taskIdentifier && snapshot.state == FrontendTaskState::Cancelled;
                });
            });
        }
        require(cancelled, "cancelled task was not observed");
        require(facade.cancelTask(taskIdentifier) == FrontendTaskCancellationResult::AlreadyTerminal,
                "terminal cancellation was not idempotent");

        const auto log = facade.taskLogSnapshot(taskIdentifier);
        require(log.has_value() && !log->entries.empty(), "launch log was not available");
        for (const auto& entry : log->entries) {
            require(entry.text.find("fixture-access-token") == std::string::npos,
                    "launch log leaked an account access token");
            require(entry.text.find("fixture-secret") == std::string::npos,
                    "launch log leaked an environment secret");
        }

        writeInstanceFixture(root, "launch.stop", true);
        const auto stopTaskIdentifier = ProductionLaunchRuntime::taskIdentifierForInstance("launch.stop");
        require(facade.launchInstance("launch.stop") == FrontendInstanceCommandResult::Succeeded,
                "stop fixture launch was rejected");
        {
            std::unique_lock<std::mutex> lock(fake->mutex);
            require(fake->condition.wait_for(lock, std::chrono::seconds(3), [&] { return fake->invocationCount >= 2; }),
                    "stop fixture process was not invoked");
        }
        require(facade.stopInstance("launch.stop") == FrontendInstanceCommandResult::Succeeded,
                "stop command was not accepted");
        bool stopped = false;
        {
            std::unique_lock<std::mutex> lock(observationMutex);
            stopped = observationCondition.wait_for(lock, std::chrono::seconds(3), [&] {
                return std::any_of(observations.begin(), observations.end(), [&](const FrontendTaskSnapshot& snapshot) {
                    return snapshot.id == stopTaskIdentifier && snapshot.state == FrontendTaskState::Cancelled;
                });
            });
        }
        require(stopped, "stop command did not terminate the process task");

        writeInstanceFixture(root, "launch.recovery", false);
        const auto recoveryTaskIdentifier = ProductionLaunchRuntime::taskIdentifierForInstance("launch.recovery");
        require(facade.launchInstance("launch.recovery") == FrontendInstanceCommandResult::Succeeded,
                "preparation failure was rejected instead of becoming a task");
        const auto preparationFailure = facade.taskSnapshot(recoveryTaskIdentifier);
        require(preparationFailure.has_value() && preparationFailure->state == FrontendTaskState::Failed
                    && preparationFailure->terminalResult.has_value()
                    && preparationFailure->terminalResult->localizationKey == "launch.preparation.failed",
                "launch preparation failure did not preserve recovery metadata");

        writeInstanceFixture(root, "launch.recovery", true);
        fake->setSucceedAutomatically(true);
        require(facade.launchInstance("launch.recovery") == FrontendInstanceCommandResult::Succeeded,
                "failed launch could not be retried");
        bool recovered = false;
        {
            std::unique_lock<std::mutex> lock(observationMutex);
            recovered = observationCondition.wait_for(lock, std::chrono::seconds(3), [&] {
                return std::any_of(observations.begin(), observations.end(), [&](const FrontendTaskSnapshot& snapshot) {
                    return snapshot.id == recoveryTaskIdentifier && snapshot.state == FrontendTaskState::Succeeded;
                });
            });
        }
        require(recovered, "retried launch did not reach success");

        writeInstanceFixture(root, "launch.shutdown", true);
        const auto shutdownTaskIdentifier = ProductionLaunchRuntime::taskIdentifierForInstance("launch.shutdown");
        fake->setSucceedAutomatically(false);
        require(facade.launchInstance("launch.shutdown") == FrontendInstanceCommandResult::Succeeded,
                "shutdown fixture launch was rejected");
        {
            std::unique_lock<std::mutex> lock(fake->mutex);
            require(fake->condition.wait_for(lock, std::chrono::seconds(3), [&] { return fake->invocationCount >= 4; }),
                    "shutdown fixture process was not invoked");
        }
        facade.shutdown();
        auto reconstructedRuntime = makeProductionLaunchRuntime(root);
        FrontendFacade reconstructed(root, dependenciesFor(reconstructedRuntime));
        const auto reconstructedTask = reconstructed.taskSnapshot(taskIdentifier);
        require(reconstructedTask.has_value() && reconstructedTask->state == FrontendTaskState::Cancelled
                    && reconstructedTask->terminalResult.has_value(),
                "persisted launch task was not reconstructed");
        const auto reconstructedShutdownTask = reconstructed.taskSnapshot(shutdownTaskIdentifier);
        require(reconstructedShutdownTask.has_value() && reconstructedShutdownTask->state == FrontendTaskState::Cancelled
                    && reconstructedShutdownTask->terminalResult.has_value(),
                "shutdown did not persist a cancelled launch task");
        reconstructed.shutdown();
        accountRuntime->shutdown();
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        std::filesystem::remove_all(root, cleanupError);
        return 1;
    }

    std::filesystem::remove_all(root, cleanupError);
    return cleanupError ? 1 : 0;
}
