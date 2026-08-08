cmake_minimum_required(VERSION 3.15)
project(audio_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(audio_engine SHARED audio_engine.cpp audio_engine.h)

target_link_libraries(audio_engine PRIVATE ole32 uuid)

set_target_properties(audio_engine PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)
