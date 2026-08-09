// SPDX-License-Identifier: GPL-3.0-only

#include "FrontendFacade.h"
#include "ProductionInstanceRuntime.h"
#include "ProductionJavaRuntime.h"

#include "settings/INIFile.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

void require(bool condition, const char* message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

std::string properties(const std::string& version, const std::string& vendor, const std::string& architecture)
{
    return "java.version = " + version + "\njava.vendor = " + vendor + "\nos.arch = " + architecture + "\n";
}

FrontendRuntimeDependencies javaDependencies(
    const std::filesystem::path& root, std::shared_ptr<ProductionJavaRuntime> runtime)
{
    auto dependencies = productionInstanceRuntimeDependencies(root);
    const auto shutdown = dependencies.shutdown;
    dependencies.shutdown = [shutdown, runtime] {
        if (shutdown) {
            shutdown();
        }
        runtime->shutdown();
    };
    return productionJavaRuntimeDependencies(std::move(runtime), std::move(dependencies));
}

}  // namespace

int main()
{
    const auto root = std::filesystem::temp_directory_path() / "prism-native-java-production-contract";
    std::error_code cleanupError;
    std::filesystem::remove_all(root, cleanupError);
    std::filesystem::create_directories(root / "java" / "managed-jdk" / "bin");
    std::filesystem::create_directories(root / "java" / "legacy-jdk" / "bin");
    std::filesystem::create_directories(root / "java" / "missing-jdk");
    std::ofstream(root / "java" / "managed-jdk" / "bin" / "java") << "synthetic managed executable";
    std::ofstream(root / "java" / "legacy-jdk" / "bin" / "java") << "synthetic legacy executable";
    INIFile savedOutsideRoot;
    savedOutsideRoot.set(
        "JavaPath",
        QString::fromStdString((root.parent_path() / "upstream-prism-launcher" / "java" / "bin" / "java").string()));
    require(savedOutsideRoot.saveFile(QString::fromStdString((root / "prismlauncher.cfg").string())),
            "synthetic saved Java choice could not be written");

    std::size_t processCalls = 0;
    std::vector<std::filesystem::path> probedPaths;
    const auto managedRoot = (root / "java").lexically_normal();
    const auto makeControlledDependencies = [&]() {
        const auto defaults = ProductionJavaRuntime::defaultDependencies();
        auto filesystem = defaults.filesystem;
        filesystem.childDirectories = [managedRoot](const std::filesystem::path& directory) {
            if (directory.lexically_normal() == managedRoot) {
                return std::vector<std::filesystem::path>{
                    managedRoot / "legacy-jdk",
                    managedRoot / "managed-jdk",
                    managedRoot / "missing-jdk",
                };
            }
            return std::vector<std::filesystem::path>{};
        };
        filesystem.isRegularFile = [root, defaults](const std::filesystem::path& path) {
            const auto normalized = path.lexically_normal();
            if (normalized.string().rfind(root.lexically_normal().string(), 0) != 0) {
                return false;
            }
            return defaults.filesystem.isRegularFile(path);
        };

        ProductionJavaRuntime::Dependencies dependencies;
        dependencies.filesystem = std::move(filesystem);
        dependencies.process = [&processCalls, &probedPaths, root](const std::filesystem::path& executablePath) {
            ++processCalls;
            probedPaths.push_back(executablePath);
            require(executablePath.lexically_normal().string().rfind(root.lexically_normal().string(), 0) == 0,
                    "production Java test attempted to execute outside the synthetic root");
            ProductionJavaRuntime::ProcessResult result;
            result.started = true;
            result.exitCode = 0;
            if (executablePath.string().find("legacy-jdk") != std::string::npos) {
                result.standardOutput = properties("8.0.392", "Synthetic Legacy JDK", "x86_64");
            } else if (executablePath.string().find("managed-jdk") != std::string::npos) {
                result.standardOutput = properties("17.0.10", "Synthetic Managed JDK", "aarch64");
            } else {
                result.started = false;
            }
            return result;
        };
        return dependencies;
    };

    try {
        auto runtime = makeProductionJavaRuntime(root, makeControlledDependencies());
        FrontendFacade facade(root, javaDependencies(root, runtime));
        const auto discovery = facade.javaInstallations();
        require(discovery.outcome == FrontendJavaDiscoveryOutcome::Succeeded, "production Java discovery failed");
        require(discovery.installations.size() == 3, "managed Java discovery did not preserve unavailable metadata");

        const auto managed = std::find_if(discovery.installations.begin(), discovery.installations.end(), [](const auto& installation) {
            return installation.id == "managed.managed-jdk";
        });
        const auto legacy = std::find_if(discovery.installations.begin(), discovery.installations.end(), [](const auto& installation) {
            return installation.id == "managed.legacy-jdk";
        });
        const auto missing = std::find_if(discovery.installations.begin(), discovery.installations.end(), [](const auto& installation) {
            return installation.id == "managed.missing-jdk";
        });
        require(managed != discovery.installations.end() && managed->managed
                    && managed->validity == FrontendJavaInstallationValidity::Valid
                    && managed->version == "17.0.10" && managed->vendor == "Synthetic Managed JDK",
                "managed Java metadata was not validated through the production adapter");
        require(legacy != discovery.installations.end()
                    && legacy->validity == FrontendJavaInstallationValidity::Incompatible,
                "incompatible Java architecture was not rejected");
        require(missing != discovery.installations.end()
                    && missing->validity == FrontendJavaInstallationValidity::Unavailable,
                "missing managed Java was not represented as unavailable");
        require(!discovery.selectedInstallationIdentifier.has_value(), "Java selection was imported before it was saved");

        const auto selected = facade.selectJavaInstallation("managed.managed-jdk");
        require(selected.outcome == FrontendJavaSelectionOutcome::Succeeded && selected.installation.has_value(),
                "managed Java selection was not confirmed");
        INIFile settings;
        require(settings.loadFile(QString::fromStdString((root / "prismlauncher.cfg").string())),
                "saved Java settings could not be read from the synthetic Native Prism root");
        require(settings.get("JavaPath", QString()).toString().toStdString()
                    == (root / "java" / "managed-jdk" / "bin" / "java").string(),
                "Java selection did not persist the selected executable");
        require(processCalls == 2 && probedPaths.size() == 2, "Java validation executed an unexpected process set");
        facade.shutdown();

        auto reconstructed = makeProductionJavaRuntime(root, makeControlledDependencies());
        auto reconstructedDependencies = javaDependencies(root, reconstructed);
        reconstructedDependencies.loadJavaInstallations = [reconstructed](const std::filesystem::path&) {
            return reconstructed->discover();
        };
        FrontendFacade rebuiltFacade(root, std::move(reconstructedDependencies));
        const auto rebuiltDiscovery = rebuiltFacade.javaInstallations();
        require(rebuiltDiscovery.selectedInstallationIdentifier == std::optional<std::string>("managed.managed-jdk"),
                "saved Java selection did not survive facade reconstruction");
        rebuiltFacade.shutdown();
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        std::filesystem::remove_all(root, cleanupError);
        return 1;
    }

    std::filesystem::remove_all(root, cleanupError);
    return cleanupError ? 1 : 0;
}
