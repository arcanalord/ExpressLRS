cmake_minimum_required(VERSION 3.24)
project(EMManaNext VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(EMNEXT_REQUIRE_EIGEN "Fail configuration when Eigen is unavailable" OFF)
option(EMNEXT_BUILD_TESTS "Build bootstrap tests" ON)
option(EMNEXT_REQUIRE_LAPACK "Fail configuration when LAPACK is unavailable" OFF)

find_package(Threads REQUIRED)
find_path(BOOST_JSON_INCLUDE_DIR boost/json.hpp REQUIRED)

find_package(Eigen3 CONFIG QUIET)
if(NOT Eigen3_FOUND)
  find_path(EIGEN3_INCLUDE_DIR Eigen/Dense PATH_SUFFIXES eigen3)
  if(EIGEN3_INCLUDE_DIR)
    add_library(Eigen3::Eigen INTERFACE IMPORTED)
    set_target_properties(Eigen3::Eigen PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${EIGEN3_INCLUDE_DIR}")
    set(Eigen3_FOUND TRUE)
  endif()
endif()
if(Eigen3_FOUND)
  message(STATUS "Eigen3 found: production linear algebra backend enabled")
  set(EMNEXT_HAS_EIGEN 1)
elseif(EMNEXT_REQUIRE_EIGEN)
  message(FATAL_ERROR "Eigen3 is required but was not found")
else()
  message(STATUS "Eigen3 not found: Eigen backend disabled (LAPACK/bootstrap selection follows).")
  set(EMNEXT_HAS_EIGEN 0)
endif()

find_package(LAPACK QUIET)
if(LAPACK_FOUND)
  message(STATUS "LAPACK found: zgesv dense backend enabled")
  set(EMNEXT_HAS_LAPACK 1)
elseif(EMNEXT_REQUIRE_LAPACK)
  message(FATAL_ERROR "LAPACK is required but was not found")
else()
  message(WARNING "LAPACK not found. LAPACK dense backend disabled.")
  set(EMNEXT_HAS_LAPACK 0)
endif()

add_library(emnext_core
  src/core_model_tools.cpp
  src/core_parallel.cpp
  src/geometry/discretization.cpp
  src/linalg/bootstrap_dense_solver.cpp
  src/linalg/solver_factory.cpp
  src/linalg/diagnostics.cpp
  src/physics/dipole_reference.cpp
  src/physics/wire_mom.cpp
  src/physics/sweep.cpp
  src/io/project_io.cpp
  src/io/result_io.cpp
  src/io/sweep_io.cpp
  src/optimization/optimizer.cpp
  src/io/optimizer_io.cpp
  src/reference/nec2.cpp
)
target_include_directories(emnext_core PUBLIC include ${BOOST_JSON_INCLUDE_DIR})
target_compile_definitions(emnext_core PUBLIC EMNEXT_HAS_EIGEN=${EMNEXT_HAS_EIGEN} EMNEXT_HAS_LAPACK=${EMNEXT_HAS_LAPACK})
if(MSVC)
  target_compile_definitions(emnext_core PUBLIC BOOST_JSON_NO_LIB BOOST_CONTAINER_NO_LIB)
endif()
target_link_libraries(emnext_core PUBLIC Threads::Threads)
if(Eigen3_FOUND)
  target_sources(emnext_core PRIVATE src/linalg/eigen_dense_solver.cpp)
  target_link_libraries(emnext_core PUBLIC Eigen3::Eigen)
endif()
if(LAPACK_FOUND)
  target_sources(emnext_core PRIVATE src/linalg/lapack_dense_solver.cpp)
  target_link_libraries(emnext_core PUBLIC ${LAPACK_LIBRARIES})
endif()

if(MSVC)
  target_compile_options(emnext_core PRIVATE /W4 /permissive-)
else()
  target_compile_options(emnext_core PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wshadow)
endif()

add_executable(emnext src/cli/main.cpp)
target_link_libraries(emnext PRIVATE emnext_core)

if(EMNEXT_BUILD_TESTS)
  enable_testing()
  add_executable(emnext_tests tests/test_bootstrap.cpp)
  target_link_libraries(emnext_tests PRIVATE emnext_core)
  target_compile_definitions(emnext_tests PRIVATE EMNEXT_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
  add_test(NAME emnext_bootstrap COMMAND emnext_tests)

  add_executable(emnext_ground_tests tests/test_ground_alpha20.cpp)
  target_link_libraries(emnext_ground_tests PRIVATE emnext_core)
  target_compile_definitions(emnext_ground_tests PRIVATE EMNEXT_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
  add_test(NAME emnext_ground_alpha20 COMMAND emnext_ground_tests)

  add_executable(emnext_b02_ground_terminal_tests tests/test_b02_ground_terminal.cpp)
  target_link_libraries(emnext_b02_ground_terminal_tests PRIVATE emnext_core)
  target_compile_definitions(emnext_b02_ground_terminal_tests PRIVATE EMNEXT_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
  add_test(NAME emnext_b02_ground_terminal COMMAND emnext_b02_ground_terminal_tests)

  find_package(Python3 COMPONENTS Interpreter QUIET)
  if(Python3_Interpreter_FOUND AND UNIX)
    add_test(
      NAME emnext_reference_runner_fake
      COMMAND ${Python3_EXECUTABLE}
              ${CMAKE_SOURCE_DIR}/tools/run_nec2_reference.py
              ${CMAKE_SOURCE_DIR}/benchmarks/B01_halfwave_dipole_51seg.emnx
              --emnext $<TARGET_FILE:emnext>
              --engine ${CMAKE_SOURCE_DIR}/tests/fake_nec2c.py
              --compare-own
              --r-tol 3.0
              --x-tol 3.0
    )

    if(LAPACK_FOUND)
      add_test(
        NAME emnext_linear_backend_parity
        COMMAND ${Python3_EXECUTABLE}
                ${CMAKE_SOURCE_DIR}/tools/compare_linear_backends.py
                --root ${CMAKE_SOURCE_DIR}
                --emnext $<TARGET_FILE:emnext>
                --r-tol 1e-8
                --x-tol 1e-8
                --residual-max 1e-10
      )
    endif()

    add_test(
      NAME emnext_parallel_execution_parity
      COMMAND ${Python3_EXECUTABLE}
              ${CMAKE_SOURCE_DIR}/tools/compare_parallel_execution.py
              --root ${CMAKE_SOURCE_DIR}
              --emnext $<TARGET_FILE:emnext>
    )

    add_test(
      NAME emnext_linux_ui_smoke
      COMMAND ${Python3_EXECUTABLE}
              ${CMAKE_SOURCE_DIR}/tests/test_linux_ui.py
              --root ${CMAKE_SOURCE_DIR}
              --emnext $<TARGET_FILE:emnext>
    )

    add_test(
      NAME emnext_help_registry_content
      COMMAND ${Python3_EXECUTABLE}
              ${CMAKE_SOURCE_DIR}/tests/test_help_registry.py
              ${CMAKE_SOURCE_DIR}
    )

    find_program(EMNEXT_NODE_EXECUTABLE node)
    if(EMNEXT_NODE_EXECUTABLE)
      add_test(
        NAME emnext_help_registry_js
        COMMAND ${EMNEXT_NODE_EXECUTABLE}
                ${CMAKE_SOURCE_DIR}/tests/test_help_registry.mjs
                ${CMAKE_SOURCE_DIR}
      )
    endif()
  endif()
endif()
