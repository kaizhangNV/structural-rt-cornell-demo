cmake_minimum_required(VERSION 3.25)

project(structural-rt-cornell-demo LANGUAGES C CXX)

set(SLANG_REPO "" CACHE PATH "Path to the Slang source tree")
set(SLANG_BUILD_CONFIG_DIR "" CACHE PATH "Path to the built Slang configuration")
if(NOT SLANG_REPO)
    message(FATAL_ERROR "SLANG_REPO must point at the Slang source tree")
endif()
if(NOT SLANG_BUILD_CONFIG_DIR)
    message(FATAL_ERROR "SLANG_BUILD_CONFIG_DIR must contain Slang's bin/ and lib/ directories")
endif()

# Build only the D3D12 portion of slang-rhi. Slang itself is imported from the
# selected compiler build so the demo exercises the exact structural-RT compiler
# that the caller requested.
set(SLANG_RHI_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(SLANG_RHI_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SLANG_RHI_INSTALL OFF CACHE BOOL "" FORCE)
set(SLANG_RHI_FETCH_SLANG OFF CACHE BOOL "" FORCE)
set(SLANG_RHI_BUILD_FROM_SLANG_REPO OFF)
set(SLANG_RHI_SLANG_INCLUDE_DIR "${SLANG_REPO}/include" CACHE PATH "" FORCE)
set(SLANG_RHI_SLANG_BINARY_DIR "${SLANG_BUILD_CONFIG_DIR}" CACHE PATH "" FORCE)
set(SLANG_RHI_ENABLE_CPU OFF CACHE BOOL "" FORCE)
set(SLANG_RHI_ENABLE_D3D11 OFF CACHE BOOL "" FORCE)
set(SLANG_RHI_ENABLE_D3D12 ON CACHE BOOL "" FORCE)
set(SLANG_RHI_ENABLE_NVAPI OFF CACHE BOOL "" FORCE)
set(SLANG_RHI_ENABLE_VULKAN OFF CACHE BOOL "" FORCE)
set(SLANG_RHI_ENABLE_CUDA OFF CACHE BOOL "" FORCE)
set(SLANG_RHI_ENABLE_OPTIX OFF CACHE BOOL "" FORCE)
set(SLANG_RHI_ENABLE_WGPU OFF CACHE BOOL "" FORCE)

set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLFW_INSTALL OFF CACHE BOOL "" FORCE)

add_subdirectory("${SLANG_REPO}/external/slang-rhi" slang-rhi EXCLUDE_FROM_ALL)
add_subdirectory(external/glfw EXCLUDE_FROM_ALL)

add_executable(structural-rt-cornell-rhi rhi-main.cpp)
target_compile_features(structural-rt-cornell-rhi PRIVATE cxx_std_17)
target_link_libraries(structural-rt-cornell-rhi PRIVATE glfw slang-rhi)

add_executable(slang-compile-benchmark perf/slang-compile-benchmark.cpp)
target_compile_features(slang-compile-benchmark PRIVATE cxx_std_17)
target_link_libraries(slang-compile-benchmark PRIVATE slang)

set_target_properties(
    structural-rt-cornell-rhi
    PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/$<CONFIG>"
)
set_target_properties(
    slang-compile-benchmark
    PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/$<CONFIG>"
)

if(WIN32)
    file(
        GLOB
        slang_standard_module_dirs
        LIST_DIRECTORIES true
        "${SLANG_BUILD_CONFIG_DIR}/bin/slang-standard-module-*"
    )
    list(LENGTH slang_standard_module_dirs slang_standard_module_dir_count)
    if(NOT slang_standard_module_dir_count EQUAL 1)
        message(
            FATAL_ERROR
            "Expected one built slang-standard-module-* directory under "
            "${SLANG_BUILD_CONFIG_DIR}/bin"
        )
    endif()
    list(GET slang_standard_module_dirs 0 slang_standard_module_dir)
    get_filename_component(slang_standard_module_dir_name "${slang_standard_module_dir}" NAME)
    add_custom_command(
        TARGET structural-rt-cornell-rhi
        POST_BUILD
        COMMAND
            ${CMAKE_COMMAND} -E copy_directory
            "${slang_standard_module_dir}"
            "$<TARGET_FILE_DIR:structural-rt-cornell-rhi>/${slang_standard_module_dir_name}"
        COMMENT "Copying Slang standard modules"
    )
endif()
