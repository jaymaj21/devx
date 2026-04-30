cmake_minimum_required(VERSION 3.12)
project(cov_server_cpp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Options
option(BUILD_STATIC "Build statically where possible" OFF)

# Find Tcl (for the embedded interpreter)
find_package(TCL REQUIRED)

add_executable(cov_server
    src/main.cpp
)

target_include_directories(cov_server PRIVATE ${TCL_INCLUDE_PATH})
target_link_libraries(cov_server PRIVATE ${TCL_LIBRARY})

if (WIN32)
  # Winsock for networking on Windows
  target_link_libraries(cov_server PRIVATE ws2_32)
endif()

# If building static on Linux, allow override
if (BUILD_STATIC AND UNIX AND NOT APPLE)
  target_link_options(cov_server PRIVATE -static)
endif()
