# The native frontend boundary is deliberately free of Qt and launcher/ui
# dependencies until a later work unit adds tested domain adapters.
add_library(Launcher_frontend STATIC
    FrontendFacade.cpp
    FrontendFacade.h
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
endif()
