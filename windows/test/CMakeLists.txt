cmake_minimum_required(VERSION 3.21)
project(universal_ble_windows_tests LANGUAGES CXX)

enable_testing()

add_executable(async_operation_tracker_test async_operation_tracker_test.cpp)
target_compile_features(async_operation_tracker_test PRIVATE cxx_std_20)
target_include_directories(async_operation_tracker_test PRIVATE ../src)

add_test(NAME async_operation_tracker_test COMMAND async_operation_tracker_test)

if(WIN32)
  add_executable(callback_drain_test callback_drain_test.cpp)
  target_compile_features(callback_drain_test PRIVATE cxx_std_20)
  target_include_directories(callback_drain_test PRIVATE ../src)
  target_link_libraries(callback_drain_test PRIVATE windowsapp)

  add_test(NAME callback_drain_test COMMAND callback_drain_test)
  set_tests_properties(callback_drain_test PROPERTIES TIMEOUT 10)
endif()
