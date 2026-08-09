# This directory is both a standalone contract build and a launcher subdirectory.
cmake_minimum_required(VERSION 3.25)
project(Launcher_frontend LANGUAGES CXX)
include(CTest)

find_package(Qt6 REQUIRED COMPONENTS Core Network)
find_package(ZLIB REQUIRED)
find_package(LibArchive)

if(NOT LibArchive_FOUND AND NOT TARGET PkgConfig::libarchive)
    find_path(PRISM_NATIVE_LIBARCHIVE_INCLUDE_DIR archive.h
        PATHS /opt/homebrew/opt/libarchive/include /usr/local/include /usr/include)
    find_library(PRISM_NATIVE_LIBARCHIVE_LIBRARY archive
        PATHS /opt/homebrew/opt/libarchive/lib /usr/local/lib /usr/lib)
    if(PRISM_NATIVE_LIBARCHIVE_INCLUDE_DIR AND PRISM_NATIVE_LIBARCHIVE_LIBRARY)
        add_library(PrismNativeLibArchive UNKNOWN IMPORTED)
        set_target_properties(PrismNativeLibArchive PROPERTIES
            IMPORTED_LOCATION "${PRISM_NATIVE_LIBARCHIVE_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${PRISM_NATIVE_LIBARCHIVE_INCLUDE_DIR}")
    endif()
endif()

if(NOT TARGET nbt++)
    set(NBT_BUILD_TESTS OFF CACHE BOOL "Build libnbt++ tests for the native frontend" FORCE)
    set(NBT_USE_ZLIB OFF CACHE BOOL "Build libnbt++ zlib streams for the native frontend" FORCE)
    add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../libraries/libnbtplusplus
        ${CMAKE_CURRENT_BINARY_DIR}/libnbtplusplus)
endif()

# The native frontend boundary uses only QtCore/QtNetwork persistence and
# transport primitives. Qt Widgets, QDialog, QApplication, and launcher/ui
# remain outside this target.
set(LAUNCHER_FRONTEND_PUBLIC_HEADERS
    FrontendFacade.h
    ProductionInstanceRuntime.h
    ProductionInstanceAcquisitionRuntime.h
    ProductionSettingsRuntime.h
    ProductionJavaRuntime.h
    ProductionAccountRuntime.h
    ProductionLaunchRuntime.h
    ProductionInstanceDetailRuntime.h
)

add_library(Launcher_frontend STATIC
    FrontendFacade.cpp
    ProductionInstanceRuntime.cpp
    ProductionInstanceAcquisitionRuntime.cpp
    ProductionSettingsRuntime.cpp
    ProductionJavaRuntime.cpp
    ProductionAccountRuntime.cpp
    ProductionLaunchRuntime.cpp
    ProductionMinecraftLaunch.cpp
    ProductionInstanceDetailRuntime.cpp
    ../archive/ArchiveReader.cpp
    ../archive/ArchiveWriter.cpp
    ../GZip.cpp
    NativeBuildConfig.cpp
    NativeFileSystemCore.cpp
    NativeMetadataFormat.cpp
    ../minecraft/auth/AccountData.cpp
    ../Commandline.cpp
    ../HardwareInfo.cpp
    ../Json.cpp
    ../SysInfo.cpp
    ../StringUtils.cpp
    ../Version.cpp
    ../java/JavaVersion.cpp
    ../java/JavaMetadata.cpp
    ../minecraft/LaunchProfile.cpp
    ../minecraft/LibraryCore.cpp
    ../minecraft/MojangVersionFormat.cpp
    ../minecraft/OneSixVersionFormat.cpp
    ../minecraft/ParseUtils.cpp
    ../minecraft/Rule.cpp
    ../minecraft/VersionFile.cpp
    ../settings/INIFile.cpp
    ${LAUNCHER_FRONTEND_PUBLIC_HEADERS}
    ../settings/INIFile.h
)

target_include_directories(Launcher_frontend
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_features(Launcher_frontend PRIVATE cxx_std_20)
target_include_directories(Launcher_frontend PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/..
    ${CMAKE_CURRENT_SOURCE_DIR}/../../buildconfig
    ${CMAKE_CURRENT_SOURCE_DIR}/../../libraries/libnbtplusplus/include
)
target_link_libraries(Launcher_frontend PUBLIC Qt6::Core Qt6::Network ZLIB::ZLIB nbt++)
if(TARGET PkgConfig::libarchive)
    target_link_libraries(Launcher_frontend PUBLIC PkgConfig::libarchive)
elseif(TARGET LibArchive::LibArchive)
    target_link_libraries(Launcher_frontend PUBLIC LibArchive::LibArchive)
elseif(LibArchive_FOUND)
    target_include_directories(Launcher_frontend PRIVATE ${LibArchive_INCLUDE_DIRS})
    target_link_libraries(Launcher_frontend PUBLIC ${LibArchive_LIBRARIES})
elseif(TARGET PrismNativeLibArchive)
    target_link_libraries(Launcher_frontend PUBLIC PrismNativeLibArchive)
else()
    message(FATAL_ERROR "The native instance export adapter requires libarchive")
endif()

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

    add_executable(Launcher_frontend_production_instance_acquisition_test
        FrontendFacadeProductionInstanceAcquisitionTest.cpp
    )
    target_compile_features(Launcher_frontend_production_instance_acquisition_test PRIVATE cxx_std_20)
    target_include_directories(Launcher_frontend_production_instance_acquisition_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
    target_link_libraries(Launcher_frontend_production_instance_acquisition_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeProductionInstanceAcquisition COMMAND Launcher_frontend_production_instance_acquisition_test)

    add_executable(Launcher_frontend_production_settings_test
        FrontendFacadeProductionSettingsTest.cpp
    )
    target_compile_features(Launcher_frontend_production_settings_test PRIVATE cxx_std_20)
    target_include_directories(Launcher_frontend_production_settings_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
    target_link_libraries(Launcher_frontend_production_settings_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeProductionSettings COMMAND Launcher_frontend_production_settings_test)

    add_executable(Launcher_frontend_production_java_test
        FrontendFacadeProductionJavaTest.cpp
    )
    target_compile_features(Launcher_frontend_production_java_test PRIVATE cxx_std_20)
    target_include_directories(Launcher_frontend_production_java_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
    target_link_libraries(Launcher_frontend_production_java_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeProductionJava COMMAND Launcher_frontend_production_java_test)

    add_executable(Launcher_frontend_production_account_test
        FrontendFacadeProductionAccountTest.cpp
    )
    target_compile_features(Launcher_frontend_production_account_test PRIVATE cxx_std_20)
    target_include_directories(Launcher_frontend_production_account_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
    target_link_libraries(Launcher_frontend_production_account_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeProductionAccount COMMAND Launcher_frontend_production_account_test)

    add_executable(Launcher_frontend_production_launch_test
        FrontendFacadeProductionLaunchTest.cpp
    )
    target_compile_features(Launcher_frontend_production_launch_test PRIVATE cxx_std_20)
    target_include_directories(Launcher_frontend_production_launch_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
    target_link_libraries(Launcher_frontend_production_launch_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeProductionLaunch COMMAND Launcher_frontend_production_launch_test)

    add_executable(Launcher_frontend_production_instance_detail_test
        FrontendFacadeProductionInstanceDetailTest.cpp
    )
    target_compile_features(Launcher_frontend_production_instance_detail_test PRIVATE cxx_std_20)
    target_include_directories(Launcher_frontend_production_instance_detail_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
    target_link_libraries(Launcher_frontend_production_instance_detail_test PRIVATE Launcher_frontend)
    add_test(NAME FrontendFacadeProductionInstanceDetail COMMAND Launcher_frontend_production_instance_detail_test)
endif()
