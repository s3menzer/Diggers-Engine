#!/bin/bash

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

if [ -z $1 ]; then
  echo Usage: $0 [version]
  exit 1
fi

SCRIPT_DIR=$(readlink -f "$0")
BASE=$(dirname $(dirname "$SCRIPT_DIR"))
cd "$BASE" || exit 1

. "$BASE/scripts/common.sh" || exit 1
ARCHIVE=$BASE/archive
LIB=$LIB_DIR
FILEPREFIX=openssl-
FILE=$FILEPREFIX$1
ZIP=$(find_archive "$ARCHIVE/$FILE") || ZIP=
SRC1=libcrypto.a
SRC2=libssl.a

if [ -z "$ZIP" ] || [ ! -e "$ZIP" ]; then
  echo Error: $ZIP not found!
  LS=`echo $ARCHIVE/$FILEPREFIX*`
  if [ ! -z "$LS" ]; then
    echo Available files...
    echo $LS
  fi
  exit 2
fi

extract_if_missing "$FILE" "$ZIP"
if [ ! $? -eq 0 ]; then
  exit 3
fi

cd $FILE
if [ ! $? -eq 0 ]; then
  exit 4
fi

build()
{
  if [ -e "ssl64-${1}-${2}.a" ]; then
    return
  fi

  make clean >/dev/null 2>&1 || true
  rm -f *.o *.obj

  if [ "$BUILD_PLATFORM" = windows ]; then
    # OpenSSL prepends CROSS_COMPILE to tool names itself. Give Configure the
    # generic names here; the common helper's already-prefixed CC/AR/etc.
    # would otherwise produce triplets such as <triplet>-<triplet>-gcc.
    CC=gcc AR=ar RANLIB=ranlib RC=windres \
      perl Configure "$1" --cross-compile-prefix="${MINGW_TARGET}-" $3 \
      no-aria no-blake2 no-camellia no-capieng no-cast no-cmac no-cmp no-cms \
      no-comp no-deprecated no-des no-devcryptoeng no-dh no-dsa no-dso no-dtls1 \
      no-dynamic-engine no-engine no-external-tests no-filenames \
      no-gost no-idea no-legacy no-makedepend no-md4 no-mdc2 no-module no-ocb \
      no-pic no-pinshared no-rc2 no-rc4 no-rmd160 no-scrypt no-seed no-shared \
      no-siphash no-siv no-sm2 no-sm3 no-sm4 no-srp no-srtp no-ssl-trace \
      no-ssl3 no-stdio no-tests no-tls1 no-tls1_1 no-trace no-ts no-ubsan \
      no-ui-console no-unit-test no-uplink no-weak-ssl-ciphers no-whirlpool \
      no-zlib no-zlib-dynamic
  else
    perl Configure $1 -mtune=$2 $3 \
    no-aria no-blake2 no-camellia no-capieng no-cast no-cmac no-cmp no-cms \
    no-comp no-deprecated no-des no-devcryptoeng no-dh no-dsa no-dso no-dtls1 \
    no-dynamic-engine  no-engine no-external-tests no-filenames \
    no-gost no-idea no-legacy no-makedepend no-md4 no-mdc2 no-module no-ocb \
    no-pic no-pinshared no-rc2 no-rc4 no-rmd160 no-scrypt no-seed no-shared \
    no-siphash no-siv no-sm2 no-sm3 no-sm4 no-srp no-srtp no-ssl-trace \
    no-ssl3 no-stdio no-tests no-tls1 no-tls1_1 no-trace no-ts no-ubsan \
    no-ui-console no-unit-test no-uplink no-weak-ssl-ciphers no-whirlpool \
      no-zlib no-zlib-dynamic
  fi

  if [ $? -ne 0 ]; then
    exit 5
  fi

  make -j"$BUILD_JOBS"
  if [ $? -ne 0 ]; then
    exit 6
  fi

  "$AR" -x $SRC1
  if [ $? -ne 0 ]; then
    exit 7
  fi

  "$AR" -x $SRC2
  if [ $? -ne 0 ]; then
    exit 8
  fi

  rm -fv $SRC1 $SRC2
  if [ $? -ne 0 ]; then
    exit 9
  fi

  rm -rfv "ssl64-${1}-${2}.a" 2>/dev/null
  OBJECT_PATTERN='*.o'
  if [ "$BUILD_PLATFORM" = windows ]; then
    OBJECT_PATTERN='*.obj'
  fi
  "$AR" rcs "ssl64-${1}-${2}.a" $OBJECT_PATTERN
  "$RANLIB" "ssl64-${1}-${2}.a"
  if [ $? -ne 0 ]; then
    exit 10
  fi

  rm -f *.o *.obj
  if [ $? -ne 0 ]; then
    exit 11
  fi

  cp -fv "include/openssl/configuration.h" "include/openssl/configuration-$4.h"
  if [ $? -ne 0 ]; then
    exit 12
  fi

  rm -rf "include/openssl/configuration.h"
  if [ $? -ne 0 ]; then
    exit 13
  fi
}

PLATFORM=$(uname)
if [ "$BUILD_PLATFORM" = windows ]; then
  build mingw64 win64 "" win64
  publish_library ssl64-mingw64-win64.a ssl64.la libssl.a libcrypto.a
elif [ "$PLATFORM" = 'Linux' ]; then
  build linux-x86_64 generic "" l64
  cp -f ssl64-linux-x86_64-generic.a "${LIB}/ssl64.la"
else
  build darwin64-x86_64 generic -mmacosx-version-min=10.15 o32
  build darwin64-arm64 apple-m1 -mmacosx-version-min=11.0 o64
  lipo ssl64-*.a -create -output "${LIB}/ssl64.ma"
fi

if [ $? -ne 0 ]; then
  exit 13
fi

install_headers "$INCLUDE_ROOT/openssl" "$BASE/$FILE/include/openssl" || exit 14
if [ "$BUILD_PLATFORM" = windows ]; then
  OPENSSL_CONFIG=win64
elif [ "$PLATFORM" = 'Linux' ]; then
  OPENSSL_CONFIG=l64
elif [ "$(uname -m)" = 'arm64' ]; then
  OPENSSL_CONFIG=o64
else
  OPENSSL_CONFIG=o32
fi
cp -f "$INCLUDE_ROOT/openssl/configuration-${OPENSSL_CONFIG}.h" \
  "$INCLUDE_ROOT/openssl/configuration.h" || exit 15
if [ "$BUILD_PLATFORM" = windows ]; then
  cp -f "$INCLUDE_ROOT/openssl/configuration.h" \
    "$MINGW_PREFIX/include/openssl/configuration.h" || exit 16
fi
