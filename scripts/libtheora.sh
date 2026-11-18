#!/bin/sh

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

if [ -z $3 ]; then
  echo Usage: $0 [theoraversion] [oggversion] [vorbisversion]
  exit 1;
fi

SCRIPT_DIR=$(readlink -f "$0")
BASE=$(dirname $(dirname "$SCRIPT_DIR"))
cd "$BASE" || exit 1

. "$BASE/scripts/common.sh" || exit 1
ARCHIVE=$BASE/archive
LIB=$LIB_DIR
FILEPREFIX=libtheora-
FILEPREFIX2=libogg-
FILEPREFIX3=libvorbis-
FILE=$FILEPREFIX$1
FILE2=$FILEPREFIX2$2
FILE3=$FILEPREFIX3$3
ZIP=$(find_archive "$ARCHIVE/$FILE") || ZIP=
ZIP2=$(find_archive "$ARCHIVE/$FILE2") || ZIP2=
ZIP3=$(find_archive "$ARCHIVE/$FILE3") || ZIP3=
ISOSX=`uname`

if [ -z "$ZIP" ] || [ ! -e "$ZIP" ]; then
  echo Error 1: $ZIP not found!
  LS=`ls $ARCHIVE/$FILEPREFIX* 2>/dev/null`
  if [ ! -z $LS ]; then
    echo Available files...
    echo $LS
  fi
  exit 2
fi

if [ -z "$ZIP2" ] || [ ! -e "$ZIP2" ]; then
  echo Error 2: $ZIP2 not found!
  LS=`ls $ARCHIVE/$FILEPREFIX2* 2>/dev/null`
  if [ ! -z $LS ]; then
    echo Available files...
    echo $LS
  fi
  exit 3
fi

if [ -z "$ZIP3" ] || [ ! -e "$ZIP3" ]; then
  echo Error 2: $ZIP3 not found!
  LS=`ls $ARCHIVE/$FILEPREFIX3* 2>/dev/null`
  if [ ! -z $LS ]; then
    echo Available files...
    echo $LS
  fi
  exit 3
fi

extract_if_missing "$FILE" "$ZIP"
if [ ! $? -eq 0 ]; then
  exit 4
fi

extract_if_missing "$FILE2" "$ZIP2"
if [ ! $? -eq 0 ]; then
  exit 5
fi

extract_if_missing "$FILE3" "$ZIP3"
if [ ! $? -eq 0 ]; then
  exit 5
fi

cd $FILE
if [ ! $? -eq 0 ]; then
  exit 4;
fi

rm -rfv *.a 2>/dev/null

build()
{
  ./autogen.sh || exit 5

  if [ $ISOSX = 'Darwin' ]; then
    EXTRA="-arch ${1} -mtune=${2} -mmacosx-version-min=10.15"
  else
    EXTRA=
  fi

  if [ "$BUILD_PLATFORM" = windows ]; then
    CC="$CC" CFLAGS="-O3 -mtune=generic" \
      LDFLAGS="-L$MINGW_PREFIX/lib" \
      configure_target --disable-examples --disable-shared --disable-asm \
        --without-vorbis --disable-oggtest \
        --with-ogg-includes="$MINGW_PREFIX/include" \
        --with-ogg-libraries="$MINGW_PREFIX/lib"
  else
    CC="$CC -O3 $EXTRA" configure_target \
      --disable-examples --without-vorbis --disable-oggtest \
      --with-ogg-includes="../${FILE2}/include/" \
      --with-ogg-libraries="../${FILE2}" \
      --with-vorbis-includes="../${FILE3}/include/" \
      --with-vorbis-libraries="../${FILE3}"
  fi
  if [ $? -ne 0 ]; then exit 5; fi

  make -j"$BUILD_JOBS"
  if [ ! $? -eq 0 ]; then
    exit 5;
  fi

  rm -rfv "theora64-${1}-${2}.a" 2>/dev/null
  cp -f lib/.libs/libtheora.a "theora64-${1}-${2}.a"
  if [ ! $? -eq 0 ]; then
    exit 6;
  fi

  make clean 2>/dev/null
}

if [ "$BUILD_PLATFORM" = windows ]; then
  build x86_64 generic
  publish_library theora64-x86_64-generic.a theora64.la libtheora.a
elif [ $ISOSX = 'Darwin' ]; then
  build x86_64 generic
  build arm64 apple-m1
  lipo theora64-*.a -create -output "${LIB}/theora64.ma"
else
  build x86_64 generic
  cp -f theora64-x86_64-generic.a "${LIB}/theora64.la"
fi

if [ ! $? -eq 0 ]; then
  exit 7;
fi

install_headers "$INCLUDE_ROOT/theora" "$BASE/$FILE/include/theora" || exit 8
