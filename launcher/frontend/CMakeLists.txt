# This directory is both a standalone contract build and a launcher subdirectory.
cmake_minimum_required(VERSION 3.25)
project(Launcher_frontend LANGUAGES CXX)
include(CTest)

find_package(Qt6 REQUIRED COMPONENTS Core)

# The native frontend boundary uses only QtCore persistence primitives. Qt
# Widgets, QDialog, QApplication, and launcher/ui remain outside this target.
set(LAUNCHER_FRONTEND_PUBLIC_HEADERS
    FrontendFacade.h
    ProductionInstanceRuntime.h
    ProductionSettingsRuntime.h
)

add_library(Launcher_frontend STATIC
    FrontendFacade.cpp
    ProductionInstanceRuntime.cpp
    ProductionSettingsRuntime.cpp
    ../HardwareInfo.cpp
    ../SysInfo.cpp
    ../settings/INIFile.cpp
    ${LAUNCHER_FRONTEND_PUBLIC_HEADERS}
    ../settings/INIFile.h
)

target_include_directories(Launcher_frontend
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_features(Launcher_frontend PRIVATE cxx_std_20)
target_include_directories(Launcher_frontend PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(Launcher_frontend PUBLIC Qt6::Core)

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

    add_executable(Launcher_frontend_production_instance_test
        FrontendFacadeProductionInstanceTest.cpp
    )
    target_compile_features(Launcher_frontend_production_instance_test PRIVATE cxx_std_20)
    target_link_libraries(Launcher_frontend_production_instance_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeProductionInstance COMMAND Launcher_frontend_production_instance_test)

    add_executable(Launcher_frontend_production_settings_test
        FrontendFacadeProductionSettingsTest.cpp
    )
    target_compile_features(Launcher_frontend_production_settings_test PRIVATE cxx_std_20)
    target_include_directories(Launcher_frontend_production_settings_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
    target_link_libraries(Launcher_frontend_production_settings_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeProductionSettings COMMAND Launcher_frontend_production_settings_test)
endif()
