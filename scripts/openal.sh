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
LIB=$BASE/lib
FILEPREFIX=openal-soft-
FILE=$FILEPREFIX$1
ZIP=$ARCHIVE/$FILE.tar.gz
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

if [ ! -e $ZIP ]; then
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

sed -i '' '410,412d' CMakeLists.txt

build()
{
  rm -rfv CMakeFiles CMakeCache* 2>/dev/null

  if [ $ISOSX = 'Darwin' ]; then
    EXTRA = -D"CMAKE_OSX_ARCHITECTURES=${1}" \
        -D"CMAKE_CXX_FLAGS=-mtune=${2} -stdlib=libc++" \
        -D"CMAKE_OSX_DEPLOYMENT_TARGET=${3}"
  fi

  cmake -D"LIBTYPE=STATIC" \
        -D"CMAKE_BUILD_TYPE=Release" \
        $EXTRA \
        -D"ALSOFT_BACKEND_PIPEWIRE=TRUE" \
        -D"ALSOFT_REQUIRE_PIPEWIRE=TRUE" \
        -D"ALSOFT_BACKEND_ALSA=TRUE" \
        -D"ALSOFT_REQUIRE_ALSA=TRUE" \
        -D"ALSOFT_BACKEND_PULSEAUDIO=TRUE" \
        -D"ALSOFT_REQUIRE_PULSEAUDIO=TRUE" \
        -D"ALSOFT_BACKEND_PORTAUDIO=FALSE" \
        -D"ALSOFT_REQUIRE_SDL2=TRUE" \
        -D"ALSOFT_BACKEND_SDL2=TRUE" \
        -D"ALSOFT_BACKEND_WAVE=FALSE" \
        -D"ALSOFT_DLOPEN=TRUE" \
        -D"ALSOFT_EMBED_HRTF_DATA=FALSE" \
        -D"ALSOFT_EXAMPLES=FALSE" \
        -D"ALSOFT_INSTALL_AMBDEC_PRESETS=FALSE" \
        -D"ALSOFT_INSTALL_CONFIG=FALSE" \
        -D"ALSOFT_INSTALL_EXAMPLES=FALSE" \
        -D"ALSOFT_INSTALL_HRTF_DATA=FALSE" \
        -D"ALSOFT_INSTALL_UTILS=FALSE" \
        -D"ALSOFT_INSTALL=FALSE" \
        -D"ALSOFT_NO_CONFIG_UTIL=TRUE" \
        -D"ALSOFT_REQUIRE_SDL2=FALSE" \
        -D"ALSOFT_UPDATE_BUILD_VERSION=FALSE" \
        -D"ALSOFT_UTILS=FALSE" \
        .
  if [ ! $? -eq 0 ]; then
    exit 6
  fi

  make -j"$BUILD_JOBS"
  if [ ! $? -eq 0 ]; then
    exit 7
  fi

  find CMakeFiles/OpenAL.dir -name *.o -print > openalfiles.txt
  if [ ! $? -eq 0 ]; then
    exit 8
  fi

  find fmt-*/CMakeFiles/alsoft.fmt.dir/src -name *.o -print >> openalfiles.txt
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
  ar rcs "al64-${1}-${2}.a" *.o
  if [ ! $? -eq 0 ]; then
    exit 15
  fi

  rm -rfv *.o
  if [ ! $? -eq 0 ]; then
    exit 16
  fi
}


build x86_64 generic 10.15

if [ $ISOSX = 'Darwin' ]; then
  build arm64 apple-m1 11.0
  lipo al64-*.a -create -output "${LIB}/al64.ma"
else
  cp -f al64-x86_64-generic.a "${LIB}/al64.la"
fi

if [ ! $? -eq 0 ]; then
  exit 17
fi

install_headers "$BASE/include/al" "$BASE/$FILE/include/AL" || exit 18
