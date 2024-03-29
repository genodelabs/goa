set(GENODE 1)

set(CMAKE_FIND_LIBRARY_SUFFIXES ".lib.so")
set(CMAKE_FIND_LIBRARY_PREFIXES "")
set(CMAKE_SHARED_LIBRARY_SUFFIX ".lib.so")
set(CMAKE_SHARED_LIBRARY_RPATH_LINK_C_FLAG "-Wl,-rpath-link,")

set(CMAKE_FIND_USE_CMAKE_ENVIRONMENT_PATH FALSE)
set(CMAKE_FIND_USE_CMAKE_PATH FALSE)
set(CMAKE_FIND_USE_CMAKE_SYSTEM_PATH FALSE)
set(CMAKE_FIND_USE_PACKAGE_REGISTRY FALSE)
set(CMAKE_FIND_USE_PACKAGE_ROOT_PATH FALSE)

set(CMAKE_FIND_USE_INSTALL_PREFIX TRUE)

# library that contains 'dlopen' and friends
set(CMAKE_DL_LIBS "-l:libc.lib.so")

# force link libgcc to all targets
link_libraries(gcc)
