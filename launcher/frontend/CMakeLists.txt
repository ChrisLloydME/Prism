# This directory is both a standalone contract build and a launcher subdirectory.
cmake_minimum_required(VERSION 3.25)
project(Launcher_frontend LANGUAGES CXX)
include(CTest)

# The native frontend boundary is deliberately free of Qt and launcher/ui
# dependencies until a later work unit adds tested domain adapters.
set(LAUNCHER_FRONTEND_PUBLIC_HEADERS
    FrontendFacade.h
)

add_library(Launcher_frontend STATIC
    FrontendFacade.cpp
    ${LAUNCHER_FRONTEND_PUBLIC_HEADERS}
)

target_include_directories(Launcher_frontend
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_features(Launcher_frontend PRIVATE cxx_std_20)

if(BUILD_TESTING)
    add_executable(Launcher_frontend_contract_test
        FrontendFacadeContractTest.cpp
    )
    target_compile_features(Launcher_frontend_contract_test PRIVATE cxx_std_20)
    target_link_libraries(Launcher_frontend_contract_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeContract COMMAND Launcher_frontend_contract_test)

    add_executable(Launcher_frontend_instance_detail_contract_test
        FrontendFacadeInstanceDetailContractTest.cpp
    )
    target_compile_features(Launcher_frontend_instance_detail_contract_test PRIVATE cxx_std_20)
    target_link_libraries(Launcher_frontend_instance_detail_contract_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeInstanceDetailContract COMMAND Launcher_frontend_instance_detail_contract_test)

    add_executable(Launcher_frontend_provider_install_contract_test
        FrontendFacadeProviderInstallContractTest.cpp
    )
    target_compile_features(Launcher_frontend_provider_install_contract_test PRIVATE cxx_std_20)
    target_link_libraries(Launcher_frontend_provider_install_contract_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeProviderInstallContract COMMAND Launcher_frontend_provider_install_contract_test)

    add_executable(Launcher_frontend_provider_install_recovery_contract_test
        FrontendFacadeProviderInstallRecoveryContractTest.cpp
    )
    target_compile_features(Launcher_frontend_provider_install_recovery_contract_test PRIVATE cxx_std_20)
    target_link_libraries(Launcher_frontend_provider_install_recovery_contract_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeProviderInstallRecoveryContract COMMAND Launcher_frontend_provider_install_recovery_contract_test)

    add_executable(Launcher_frontend_public_header_test
        FrontendFacadePublicHeaderTest.cpp
    )
    target_compile_features(Launcher_frontend_public_header_test PRIVATE cxx_std_20)
    target_include_directories(Launcher_frontend_public_header_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    add_test(NAME FrontendFacadePublicHeaders COMMAND Launcher_frontend_public_header_test)
endif()
