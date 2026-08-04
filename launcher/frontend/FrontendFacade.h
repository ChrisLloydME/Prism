// SPDX-License-Identifier: GPL-3.0-only

#pragma once

/// UI-free entry point for native frontend use cases.
///
/// The initial target establishes the ownership boundary only. Backend
/// services, explicit data-root construction, snapshots, events, and
/// lifecycle operations are added by the following Milestone 2 work units.
class FrontendFacade final {
   public:
    FrontendFacade() noexcept;
    ~FrontendFacade() noexcept;

    FrontendFacade(const FrontendFacade&) = delete;
    FrontendFacade& operator=(const FrontendFacade&) = delete;
    FrontendFacade(FrontendFacade&&) = delete;
    FrontendFacade& operator=(FrontendFacade&&) = delete;
};
