cmake_minimum_required(VERSION 3.21)
project(kanpai_image VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(KANPAI_BUILD_CLI "Build the debug command line tool" ON)
option(KANPAI_BUILD_TESTS "Build native unit tests" ON)
option(KANPAI_BUILD_GDEXTENSION "Build the Godot GDExtension" ON)

find_package(OpenCV 4.14 REQUIRED COMPONENTS core imgproc objdetect)
if(OpenCV_VERSION VERSION_GREATER_EQUAL 4.15)
    message(FATAL_ERROR
        "This project supports OpenCV 4.14.x, but ${OpenCV_VERSION} was found. "
        "Install the Homebrew opencv@4 formula used by this project."
    )
endif()
message(STATUS "Using supported OpenCV ${OpenCV_VERSION}")

add_library(kanpai_image_core STATIC src/core/character_generator.cpp)
set_target_properties(kanpai_image_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(kanpai_image_core PUBLIC include)
target_link_libraries(kanpai_image_core PUBLIC
    opencv_core
    opencv_imgproc
    opencv_objdetect
)
target_compile_options(kanpai_image_core PRIVATE -Wall -Wextra -Wpedantic)

if(KANPAI_BUILD_CLI)
    find_package(OpenCV REQUIRED COMPONENTS imgcodecs)
    add_executable(kanpai_image_cli src/cli/main.cpp)
    target_link_libraries(kanpai_image_cli PRIVATE
        kanpai_image_core
        opencv_imgcodecs
    )
endif()

if(KANPAI_BUILD_TESTS)
    enable_testing()
    add_executable(kanpai_image_tests tests/character_generator_test.cpp)
    target_link_libraries(kanpai_image_tests PRIVATE kanpai_image_core)
    add_test(NAME kanpai_image_tests COMMAND kanpai_image_tests)
endif()

if(KANPAI_BUILD_GDEXTENSION)
    if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/godot-cpp/CMakeLists.txt")
        message(FATAL_ERROR
            "godot-cpp is missing. Initialize third_party/godot-cpp or configure "
            "with -DKANPAI_BUILD_GDEXTENSION=OFF."
        )
    endif()

    add_subdirectory(third_party/godot-cpp EXCLUDE_FROM_ALL)
    add_library(kanpai_image_gdextension SHARED
        src/gdextension/kanpai_character_image_set.cpp
        src/gdextension/kanpai_image_processor.cpp
        src/gdextension/register_types.cpp
    )
    target_include_directories(kanpai_image_gdextension PRIVATE include)
    target_link_libraries(kanpai_image_gdextension PRIVATE
        kanpai_image_core
        godot-cpp
    )
    get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
    set_target_properties(kanpai_image_gdextension PROPERTIES
        PREFIX "lib"
        OUTPUT_NAME "kanpai_image${GODOTCPP_SUFFIX}"
        CXX_VISIBILITY_PRESET "hidden"
        POSITION_INDEPENDENT_CODE ON
        BUILD_RPATH_USE_ORIGIN ON
        LIBRARY_OUTPUT_DIRECTORY
            "${CMAKE_CURRENT_SOURCE_DIR}/../../addons/kanpai_image/bin/macos-arm64"
    )
endif()
