
cmake_minimum_required(VERSION 3.10...3.21)

set(LIB_VERSION "1.0.0")

project(forty_two VERSION ${LIB_VERSION} LANGUAGES CXX)

message(STATUS "Build forty_two: ${LIB_VERSION}")

set(LIB_SRCS lib.cc)
set(LIB_HDRS include/forty_two.h)

add_library(forty_two SHARED ${LIB_SRCS} ${LIB_HDRS})

target_include_directories(forty_two PUBLIC "$<BUILD_INTERFACE:${CMAKE_CURRENT_LIST_DIR}/include>")

file(COPY include
    DESTINATION .
    FILES_MATCHING
        PATTERN *
)
