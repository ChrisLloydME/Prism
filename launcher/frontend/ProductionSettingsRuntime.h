// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "FrontendFacade.h"

#include <filesystem>
#include <memory>
#include <mutex>

/// QWidget-free production owner for the non-secret global and instance
/// settings used by the native Settings scene and instance settings form.
///
/// The runtime preserves Prism's existing sectionless INI format, defaults,
/// aliases, and override semantics. Swift receives only the typed facade
/// snapshots; it never serializes or interprets the settings file.
class ProductionSettingsRuntime final {
   public:
    explicit ProductionSettingsRuntime(std::filesystem::path dataRoot);
    ~ProductionSettingsRuntime() noexcept;

    ProductionSettingsRuntime(const ProductionSettingsRuntime&) = delete;
    ProductionSettingsRuntime& operator=(const ProductionSettingsRuntime&) = delete;

    std::optional<FrontendGlobalSettingsSnapshot> globalSettings();
    FrontendGlobalSettingsUpdateResult updateGlobalSettings(const FrontendGlobalSettingsSnapshot& settings);
    std::optional<FrontendInstanceSettingsSnapshot> instanceSettings(const std::string& instanceIdentifier);
    FrontendInstanceSettingsUpdateResult updateInstanceSettings(
        const std::string& instanceIdentifier,
        const FrontendInstanceSettingsSnapshot& settings);
    void shutdown() noexcept;

   private:
    std::filesystem::path m_dataRoot;
    std::filesystem::path m_instancesRoot;
    std::filesystem::path m_globalSettingsPath;
    mutable std::mutex m_mutex;
    bool m_shutdown = false;
};

std::shared_ptr<ProductionSettingsRuntime> makeProductionSettingsRuntime(std::filesystem::path dataRoot);
