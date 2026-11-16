#!/bin/sh

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

if [ -z $2 ]; then
  echo Usage: $0 [oggversion] [vorbisversion]
  exit 1;
fi

SCRIPT_DIR=$(readlink -f "$0")
BASE=$(dirname $(dirname "$SCRIPT_DIR"))
cd "$BASE" || exit 1

. "$BASE/scripts/common.sh" || exit 1
ARCHIVE=$BASE/archive
LIB=$BASE/lib
FILEPREFIX=libogg-
FILEPREFIX2=libvorbis-
FILE=$FILEPREFIX$1
FILE2=$FILEPREFIX2$2
ZIP=$ARCHIVE/$FILE.tar.gz
ZIP2=$ARCHIVE/$FILE2.tar.gz
ISOSX=`uname`

if [ ! -e $ZIP ]; then
  echo Error 1: $ZIP not found!
  LS=`ls $ARCHIVE/$FILEPREFIX* 2>/dev/null`
  if [ ! -z $LS ]; then
    echo Available files...
    echo $LS
  fi
  exit 2
fi

if [ ! -e $ZIP2 ]; then
  echo Error 2: $ZIP2 not found!
  LS=`ls $ARCHIVE/$FILEPREFIX2* 2>/dev/null`
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

rm -rfv "${FILE2}/lib/barkmel.c" \
        "${FILE2}/lib/tone.c" \
        "${FILE2}/lib/psytune.c" 2>/dev/null
if [ ! $? -eq 0 ]; then
  exit 6;
fi

cd $FILE
if [ ! $? -eq 0 ]; then
  exit 7;
fi

build()
{
  if [ $ISOSX = 'Darwin' ]; then
    gcc -O3 -arch $1 -mtune=$2 -mmacosx-version-min=10.15 \
      -Iinclude \
      -I"../${FILE2}/include" \
      -I"../${FILE2}/lib" \
      -c ../${FILE2}/lib/*.c src/*.c
  else
    gcc -O3 -mtune=$2 \
      -Iinclude \
      -I"../${FILE2}/include" \
      -I"../${FILE2}/lib" \
      -c ../${FILE2}/lib/*.c src/*.c
  fi

  if [ ! $? -eq 0 ]; then
    exit 8;
  fi

  rm -rfv "ogg64-${1}-${2}.a" 2>/dev/null

  ar rcs "ogg64-${1}-${2}.a" *.o
  if [ ! $? -eq 0 ]; then
    exit 9;
  fi

  rm -rf *.o 2>/dev/null
  if [ ! $? -eq 0 ]; then
    exit 10;
  fi
}

build x86_64 generic

if [ $ISOSX = 'Darwin' ]; then
  build arm64 apple-m1
  lipo ogg64-*.a -create -output "${LIB}/ogg64.ma"
else
  cp -f ogg64-x86_64-generic.a "${LIB}/ogg64.la"
fi

if [ ! $? -eq 0 ]; then
  exit 11;
fi

install_headers "$BASE/include/ogg" \
  "$BASE/$FILE/include/ogg/"*.h \
  "$BASE/$FILE2/include/vorbis/"*.h || exit 12
