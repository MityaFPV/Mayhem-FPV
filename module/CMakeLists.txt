cmake_minimum_required(VERSION 3.15)
project(fpvjoy CXX)

set(GMB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/gmod-module-base)
set(GMB_COMMIT e0156e5f96cd0bad8eed738f0d20e2c9a14b2a0d)
if(NOT EXISTS ${GMB_DIR}/include/GarrysMod/Lua/Interface.h)
    find_package(Git REQUIRED)
    execute_process(COMMAND ${GIT_EXECUTABLE} clone https://github.com/Facepunch/gmod-module-base.git ${GMB_DIR})
    execute_process(COMMAND ${GIT_EXECUTABLE} -C ${GMB_DIR} checkout ${GMB_COMMIT})
endif()

add_library(fpvjoy SHARED src/fpvjoy.cpp src/fpvhid.cpp src/fpvmusic.cpp)
target_include_directories(fpvjoy PRIVATE src ${GMB_DIR}/include)
target_compile_features(fpvjoy PRIVATE cxx_std_17)
target_link_libraries(fpvjoy PRIVATE winmm hid setupapi shell32 ole32 user32)
set_target_properties(fpvjoy PROPERTIES
    PREFIX ""
    OUTPUT_NAME "gmcl_fpvjoy_win64"
    MSVC_RUNTIME_LIBRARY "MultiThreaded")
