cmake_minimum_required(VERSION 3.27)

project(sdl2_example VERSION 1.0)

set(CMAKE_CXX_STANDARD 11)

find_package(SDL2 REQUIRED)

add_executable(${PROJECT_NAME} "Main.cpp")
