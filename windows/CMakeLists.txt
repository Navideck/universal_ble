cmake_minimum_required(VERSION 3.21)
set(PROJECT_NAME "universal_ble")
project(${PROJECT_NAME} LANGUAGES CXX)
cmake_policy(VERSION 3.14...3.25)
include(FetchContent)
set(CPPWINRT_VERSION "2.0.220418.1")
set(PLUGIN_NAME "universal_ble_plugin")

# ############### NuGet intall begin ################
FetchContent_Declare(nuget
  URL "https://dist.nuget.org/win-x86-commandline/v6.0.0/nuget.exe"
  URL_HASH SHA256=04eb6c4fe4213907e2773e1be1bbbd730e9a655a3c9c58387ce8d4a714a5b9e1
  DOWNLOAD_NO_EXTRACT true
)

find_program(NUGET nuget)

if(NOT NUGET)
  # message("Nuget.exe not found, trying to download or use cached version.")
  FetchContent_MakeAvailable(nuget)
  set(NUGET ${nuget_SOURCE_DIR}/nuget.exe)
endif()

# Use CMAKE_CURRENT_BINARY_DIR for plugin's build directory (absolute path)
get_filename_component(PLUGIN_BUILD_DIR ${CMAKE_CURRENT_BINARY_DIR} ABSOLUTE)
set(NUGET_PACKAGES_DIR "${PLUGIN_BUILD_DIR}/packages")
set(CPPWINRT_PACKAGE_DIR "${NUGET_PACKAGES_DIR}/Microsoft.Windows.CppWinRT.${CPPWINRT_VERSION}")

# Only install if package doesn't exist
if(NOT EXISTS "${CPPWINRT_PACKAGE_DIR}")
  execute_process(COMMAND
    ${NUGET} install "Microsoft.Windows.CppWinRT" -Version ${CPPWINRT_VERSION} -OutputDirectory packages
    WORKING_DIRECTORY ${PLUGIN_BUILD_DIR}
    RESULT_VARIABLE ret)

  if(NOT ret EQUAL 0)
    message(FATAL_ERROR "Failed to install nuget package Microsoft.Windows.CppWinRT.${CPPWINRT_VERSION}")
  endif()
endif()

# ############### NuGet install end ################

# Compilation settings that should be applied to most targets.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_20)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

list(APPEND PLUGIN_SOURCES
  "src/universal_ble_plugin.cpp"
  "src/universal_ble_plugin.h"
  "src/helper/universal_enum.h"
  "src/helper/universal_ble_base.h"
  "src/helper/utils.cpp"
  "src/helper/utils.h"
  "src/ui_thread_handler.hpp"
  "src/generated/universal_ble.g.cpp"
  "src/generated/universal_ble.g.h"
  "src/pin_entry.h"
  "src/universal_ble_filter_util.cpp"
  "src/universal_ble_filter_util.h"
  "src/universal_ble_thread_safe.h"
  "src/enum_parser.h"
  "src/helper/universal_ble_logger.cpp"
  "src/helper/universal_ble_logger.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/universal_ble/universal_ble_plugin_c_api.h"
  "universal_ble_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

# ############### NuGet import begin ################
set(CPPWINRT_PROPS "${CPPWINRT_PACKAGE_DIR}/build/native/Microsoft.Windows.CppWinRT.props")

if(NOT EXISTS "${CPPWINRT_PROPS}")
  message(FATAL_ERROR "CppWinRT props file not found: ${CPPWINRT_PROPS}")
endif()

# Import CppWinRT props file - MSBuild will automatically handle the targets file
# The props file imports the targets file internally, so we don't need to link it
set_target_properties(${PLUGIN_NAME} PROPERTIES VS_PROJECT_IMPORT
  "${CPPWINRT_PROPS}"
)

# ############### NuGet import end ################
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(universal_ble_bundled_libraries
  ""
  PARENT_SCOPE
)
