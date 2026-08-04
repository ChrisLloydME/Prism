// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <chrono>
#include <filesystem>
#include <functional>

/// Runtime ports are supplied by the owning composition root so the facade
/// does not discover global application state or create hidden workers.
struct FrontendRuntimeDependencies final {
    using Work = std::function<void()>;
    using Dispatch = std::function<void(Work)>;
    using Clock = std::function<std::chrono::system_clock::time_point()>;

    Dispatch dispatch;
    Clock now;

    bool isComplete() const noexcept { return static_cast<bool>(dispatch) && static_cast<bool>(now); }
};

/// UI-free entry point for native frontend use cases.
///
/// The facade owns the explicit root and injected runtime ports. Backend
/// services, snapshots, events, and lifecycle operations are added by the
/// following Milestone 2 work units.
class FrontendFacade final {
   public:
    FrontendFacade(std::filesystem::path dataRoot, FrontendRuntimeDependencies runtimeDependencies);
    ~FrontendFacade() noexcept;

    FrontendFacade(const FrontendFacade&) = delete;
    FrontendFacade& operator=(const FrontendFacade&) = delete;
    FrontendFacade(FrontendFacade&&) = delete;
    FrontendFacade& operator=(FrontendFacade&&) = delete;

    const std::filesystem::path& dataRoot() const noexcept { return m_dataRoot; }
    bool hasRuntimeDependencies() const noexcept { return m_runtimeDependencies.isComplete(); }

   private:
    std::filesystem::path m_dataRoot;
    FrontendRuntimeDependencies m_runtimeDependencies;
};
