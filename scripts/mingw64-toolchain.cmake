set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 10.0)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Some static C++ dependencies must use the same MinGW threading model as the
# Windows-hosted compiler. Default to the distro's selected variant, but allow
# callers (for example OpenAL Soft) to request the POSIX variant explicitly.
set(MINGW_THREAD_MODEL "$ENV{MINGW_THREAD_MODEL}")
set(MINGW_COMPILER_SUFFIX "")
if(MINGW_THREAD_MODEL)
  if(NOT MINGW_THREAD_MODEL MATCHES "^(posix|win32)$")
    message(FATAL_ERROR "Unsupported MINGW_THREAD_MODEL='${MINGW_THREAD_MODEL}'")
  endif()
  set(MINGW_COMPILER_SUFFIX "-${MINGW_THREAD_MODEL}")
endif()

if(DEFINED ENV{MINGW_TARGET} AND NOT "$ENV{MINGW_TARGET}" STREQUAL "")
  set(MINGW_TRIPLET "$ENV{MINGW_TARGET}")
else()
  set(MINGW_TRIPLET "x86_64-w64-mingw32")
endif()

set(CMAKE_C_COMPILER "${MINGW_TRIPLET}-gcc${MINGW_COMPILER_SUFFIX}")
set(CMAKE_CXX_COMPILER "${MINGW_TRIPLET}-g++${MINGW_COMPILER_SUFFIX}")
set(CMAKE_RC_COMPILER "${MINGW_TRIPLET}-windres")
set(CMAKE_AR "${MINGW_TRIPLET}-ar")
set(CMAKE_RANLIB "${MINGW_TRIPLET}-ranlib")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_FIND_ROOT_PATH "/usr/${MINGW_TRIPLET}" "$ENV{MINGW_PREFIX}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Let host pkg-config run only against the target staging prefix, never the
# container's Linux development packages.
set(ENV{PKG_CONFIG_LIBDIR} "$ENV{MINGW_PREFIX}/lib/pkgconfig:$ENV{MINGW_PREFIX}/share/pkgconfig")
set(ENV{PKG_CONFIG_SYSROOT_DIR} "/usr/${MINGW_TRIPLET}")
