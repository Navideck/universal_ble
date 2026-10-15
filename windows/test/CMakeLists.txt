cmake_minimum_required(VERSION 3.21)
project(universal_ble_windows_tests LANGUAGES CXX)

enable_testing()

add_executable(async_operation_tracker_test async_operation_tracker_test.cpp)
target_compile_features(async_operation_tracker_test PRIVATE cxx_std_20)
target_include_directories(async_operation_tracker_test PRIVATE ../src)

add_test(NAME async_operation_tracker_test COMMAND async_operation_tracker_test)

add_executable(scan_result_merge_test scan_result_merge_test.cpp)
target_compile_features(scan_result_merge_test PRIVATE cxx_std_20)
target_include_directories(scan_result_merge_test PRIVATE ../src)

add_test(NAME scan_result_merge_test COMMAND scan_result_merge_test)

# Drives the platform-agnostic filter core from the shared Dart/Android/C++
# conformance fixture.
add_executable(scan_filter_matcher_test
  scan_filter_matcher_test.cpp
  ../src/scan_filter_matcher.cpp
)
target_compile_features(scan_filter_matcher_test PRIVATE cxx_std_20)
target_include_directories(scan_filter_matcher_test PRIVATE ../src)
target_compile_definitions(scan_filter_matcher_test PRIVATE
  SCAN_FILTER_FIXTURE_PATH="${CMAKE_CURRENT_SOURCE_DIR}/../../test/fixtures/scan_filter_cases.tsv"
)

add_test(NAME scan_filter_matcher_test COMMAND scan_filter_matcher_test)

if(WIN32)
  add_executable(cleanup_drain_test cleanup_drain_test.cpp)
  target_compile_features(cleanup_drain_test PRIVATE cxx_std_20)
  target_include_directories(cleanup_drain_test PRIVATE ../src)
  target_link_libraries(cleanup_drain_test PRIVATE windowsapp)
  add_test(NAME cleanup_drain_test COMMAND cleanup_drain_test)
  set_tests_properties(cleanup_drain_test PROPERTIES TIMEOUT 10)
  add_executable(callback_drain_test callback_drain_test.cpp)
  target_compile_features(callback_drain_test PRIVATE cxx_std_20)
  target_include_directories(callback_drain_test PRIVATE ../src)
  target_link_libraries(callback_drain_test PRIVATE windowsapp)

  add_test(NAME callback_drain_test COMMAND callback_drain_test)
  set_tests_properties(callback_drain_test PROPERTIES TIMEOUT 10)

  add_executable(initialization_lifetime_test initialization_lifetime_test.cpp)
  target_compile_features(initialization_lifetime_test PRIVATE cxx_std_20)
  target_include_directories(initialization_lifetime_test PRIVATE ../src)
  target_link_libraries(initialization_lifetime_test PRIVATE windowsapp)
  if(MSVC)
    target_compile_options(initialization_lifetime_test PRIVATE /EHsc)
  endif()
  add_test(NAME initialization_lifetime_test COMMAND initialization_lifetime_test)
  set_tests_properties(initialization_lifetime_test PROPERTIES TIMEOUT 10)
endif()
