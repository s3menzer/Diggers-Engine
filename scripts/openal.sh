#!/bin/sh

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

if [ -z "${1:-}" ]; then
  echo "Usage: $0 [version] [optional-patch-relative-to-.build-helpers]"
  exit 1
fi

SCRIPT_DIR=$(readlink -f "$0")
BASE=$(dirname $(dirname "$SCRIPT_DIR"))
cd "$BASE" || exit 1

. "$BASE/scripts/common.sh" || exit 1
ARCHIVE=$BASE/archive
LIB=$LIB_DIR
FILEPREFIX=openal-soft-
FILE=$FILEPREFIX$1
ZIP=$(find_archive "$ARCHIVE/$FILE") || ZIP=
ISOSX=`uname`
PATCH_FILE=
if [ -n "${2:-}" ]; then
  case "$2" in
    /*) PATCH_FILE=$2 ;;
    .build-helpers/*) PATCH_FILE=$BASE/$2 ;;
    *) PATCH_FILE=$BASE/.build-helpers/$2 ;;
  esac
  if [ ! -f "$PATCH_FILE" ]; then
    echo "Error: patch file '$PATCH_FILE' not found!" >&2
    exit 2
  fi
fi

if [ -z "$ZIP" ] || [ ! -e "$ZIP" ]; then
  echo Error: $ZIP not found!
  LS=`echo $ARCHIVE/$FILEPREFIX* 2>/dev/null`
  if [ ! -z "${LS}" ]; then
    echo Available files...
    echo $LS | tr " " "\n"
  fi
  exit 2
fi

extract_if_missing "$FILE" "$ZIP"
if [ ! $? -eq 0 ]; then
  exit 3
fi

if [ -n "$PATCH_FILE" ]; then
  apply_patch_if_needed "$PATCH_FILE" "$BASE/$FILE"
  if [ ! $? -eq 0 ]; then
    exit 4
  fi
fi

cd "$FILE"
if [ ! $? -eq 0 ]; then
  exit 5
fi

# Older in-source CMake runs leave generated configuration headers here. The
# source directory is searched before the current build directory, so those
# headers can override the fresh Windows configuration and register Linux-only
# backend factories in the static archive.
rm -f config.h config_backends.h config_simd.h

build()
{
  BUILDDIR="build-${TARGET_TAG}-${1}"
  rm -rfv "$BUILDDIR" 2>/dev/null
  mkdir -p "$BUILDDIR" || exit 6
  cd "$BUILDDIR" || exit 6

  EXTRA=
  if [ $ISOSX = 'Darwin' ]; then
    EXTRA="-DCMAKE_OSX_ARCHITECTURES=${1} -DCMAKE_CXX_FLAGS=-mtune=${2} -DCMAKE_OSX_DEPLOYMENT_TARGET=${3}"
  fi

  if [ "$BUILD_PLATFORM" = windows ]; then
    # The Wine builder uses WinLibs' POSIX-thread MinGW runtime. Build OpenAL
    # with the matching MinGW variant so its std::mutex runtime references link.
    MINGW_THREAD_MODEL=posix
    export MINGW_THREAD_MODEL
    BACKEND_ARGS="-D ALSOFT_BACKEND_PIPEWIRE=OFF -D ALSOFT_REQUIRE_PIPEWIRE=OFF -D ALSOFT_BACKEND_ALSA=OFF -D ALSOFT_REQUIRE_ALSA=OFF -D ALSOFT_BACKEND_OSS=OFF -D ALSOFT_BACKEND_PULSEAUDIO=OFF -D ALSOFT_REQUIRE_PULSEAUDIO=OFF -D ALSOFT_BACKEND_SDL2=OFF -D ALSOFT_BACKEND_WASAPI=ON -D ALSOFT_BACKEND_DSOUND=ON -D ALSOFT_BACKEND_WINMM=ON -D ALSOFT_BACKEND_WAVE=OFF -D ALSOFT_DLOPEN=OFF"
  else
    BACKEND_ARGS="-D ALSOFT_BACKEND_PIPEWIRE=TRUE -D ALSOFT_REQUIRE_PIPEWIRE=TRUE -D ALSOFT_BACKEND_ALSA=TRUE -D ALSOFT_REQUIRE_ALSA=TRUE -D ALSOFT_BACKEND_PULSEAUDIO=TRUE -D ALSOFT_REQUIRE_PULSEAUDIO=TRUE -D ALSOFT_BACKEND_PORTAUDIO=FALSE -D ALSOFT_BACKEND_SDL2=TRUE -D ALSOFT_BACKEND_WAVE=FALSE -D ALSOFT_DLOPEN=TRUE"
  fi

  # Engine uses core OpenAL/EFX APIs, not the legacy EAX interface.
  cmake_configure -D"LIBTYPE=STATIC" \
        -D"CMAKE_BUILD_TYPE=Release" \
        -D"ALSOFT_EAX=FALSE" \
        $EXTRA \
        $BACKEND_ARGS \
        -D"ALSOFT_EMBED_HRTF_DATA=FALSE" \
        -D"ALSOFT_EXAMPLES=FALSE" \
        -D"ALSOFT_INSTALL_AMBDEC_PRESETS=FALSE" \
        -D"ALSOFT_INSTALL_CONFIG=FALSE" \
        -D"ALSOFT_INSTALL_EXAMPLES=FALSE" \
        -D"ALSOFT_INSTALL_HRTF_DATA=FALSE" \
        -D"ALSOFT_INSTALL_UTILS=FALSE" \
        -D"ALSOFT_INSTALL=FALSE" \
        -D"ALSOFT_NO_CONFIG_UTIL=TRUE" \
        -D"ALSOFT_UPDATE_BUILD_VERSION=FALSE" \
        -D"ALSOFT_UTILS=FALSE" \
        "$BASE/$FILE"
  if [ ! $? -eq 0 ]; then
    exit 6
  fi

  if [ "$BUILD_PLATFORM" = windows ]; then
    for backend in HAVE_ALSA HAVE_OSS HAVE_PIPEWIRE HAVE_PULSEAUDIO; do
      if grep -q "^#define $backend 1$" config_backends.h; then
        echo "Error: Windows OpenAL configuration unexpectedly enables $backend." >&2
        exit 6
      fi
    done
  fi

  make -j"$BUILD_JOBS"
  if [ ! $? -eq 0 ]; then
    exit 7
  fi

  find CMakeFiles/OpenAL.dir \( -name '*.o' -o -name '*.obj' \) -print > openalfiles.txt
  if [ ! $? -eq 0 ]; then
    exit 8
  fi

  find fmt-*/CMakeFiles/alsoft.fmt.dir/src \( -name '*.o' -o -name '*.obj' \) -print >> openalfiles.txt
  if [ ! $? -eq 0 ]; then
    exit 9
  fi

  while read p; do
    nn=`echo $p | sed 's|CMakeFiles/OpenAL\.dir/||g'`
    if [ ! $? -eq 0 ]; then
      exit 10
    fi

    nn=`echo $p | sed 's|fmt\-[\d\.]+/CMakeFiles/alsoft\.fmt\.dir/src/||g'`
    if [ ! $? -eq 0 ]; then
      exit 11
    fi

    nn=`echo $nn | sed 's|/|-|g'`
    if [ ! $? -eq 0 ]; then
      exit 12
    fi

    mv -fv "$p" "${nn}-${1}-${2}.o"
    if [ ! $? -eq 0 ]; then
      exit 13
    fi
  done <openalfiles.txt

  rm -fv openalfiles.txt
  if [ ! $? -eq 0 ]; then
    exit 14
  fi

  rm -rfv "al64-${1}-${2}.a" 2>/dev/null
  "$AR" rcs "al64-${1}-${2}.a" *.o
  if [ ! $? -eq 0 ]; then
    exit 15
  fi

  if [ "$BUILD_PLATFORM" = windows ]; then
    # Reject an archive built with MinGW's win32 threading model. It leaves
    # __gthr_win32_* references that cannot be resolved by the POSIX-thread
    # WinLibs compiler used to link the engine under Wine.
    MINGW_NM=${MINGW_TARGET}-nm
    if ! command -v "$MINGW_NM" >/dev/null 2>&1; then
      echo "Error: MinGW nm tool '$MINGW_NM' is required to validate OpenAL." >&2
      exit 17
    fi
    if ! UNDEFINED_SYMBOLS=$("$MINGW_NM" -u "al64-${1}-${2}.a"); then
      echo "Error: unable to inspect the OpenAL archive with '$MINGW_NM'." >&2
      exit 17
    fi
    if printf '%s\n' "$UNDEFINED_SYMBOLS" \
        | grep -Eq '__gthr_win32_mutex_(lock|unlock)'; then
      echo "Error: OpenAL was built with MinGW's win32 threading model." >&2
      echo "Rebuild with MINGW_THREAD_MODEL=posix before linking with WinLibs POSIX." >&2
      exit 17
    fi
  fi

  rm -rfv *.o
  if [ ! $? -eq 0 ]; then
    exit 16
  fi

  cp -f "al64-${1}-${2}.a" "$BASE/$FILE/al64-${1}-${2}.a" || exit 16
  cd "$BASE/$FILE" || exit 16
}

if [ "$BUILD_PLATFORM" = windows ]; then
  build x86_64 generic
  publish_library al64-x86_64-generic.a al64.la libopenal-soft.a
elif [ $ISOSX = 'Darwin' ]; then
  build x86_64 generic 10.15
  build arm64 apple-m1 11.0
  lipo al64-*.a -create -output "${LIB}/al64.ma"
else
  build x86_64 generic 10.15
  cp -f al64-x86_64-generic.a "${LIB}/al64.la"
fi

if [ ! $? -eq 0 ]; then
  exit 17
fi

install_headers "$INCLUDE_ROOT/al" "$BASE/$FILE/include/AL" || exit 18
