#!/usr/bin/env bash

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

set -euo pipefail

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname -- "$SCRIPT_PATH")"
PROJECT_ROOT="$(dirname -- "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

BUILD_DIR=${BUILD_DIR:-build-windows}
if [[ "$BUILD_DIR" = /* ]]; then
  BUILD_ROOT="$BUILD_DIR"
else
  BUILD_ROOT="$PROJECT_ROOT/$BUILD_DIR"
fi

MINGW_TARGET=${MINGW_TARGET:-x86_64-w64-mingw32}
CXX=${CXX:-${MINGW_TARGET}-g++}
WINDRES=${WINDRES:-${MINGW_TARGET}-windres}
MODE=${1:-${BUILD_TYPE:-Release}}

if (($# > 1)); then
  echo "Usage: $0 [Release|Debug|res]" >&2
  exit 2
fi

case "${MODE,,}" in
  release|ms64)
    BUILD_DEFINE=RELEASE
    OPT_FLAGS=(-O2 -ffunction-sections -fdata-sections)
    BUILD_MODE=release
    ;;
  debug|ms64d)
    BUILD_DEFINE=ALPHA
    OPT_FLAGS=(-O0 -fno-omit-frame-pointer -ffunction-sections -fdata-sections)
    BUILD_MODE=debug
    ;;
  res)
    BUILD_DEFINE=RELEASE
    OPT_FLAGS=()
    BUILD_MODE=resources
    ;;
  *)
    echo "Error: unknown build mode '$MODE'." >&2
    echo "Usage: $0 [Release|Debug|res] (aliases: ms64, ms64d)" >&2
    exit 2
    ;;
esac

# The native Windows game makefile builds the beta game directly, while still
# reusing this script's case-correct resource include setup.
if [[ "$BUILD_MODE" == resources && -n "${RESOURCE_DEFINE:-}" ]]; then
  case "$RESOURCE_DEFINE" in
    RELEASE|ALPHA|BETA) BUILD_DEFINE="$RESOURCE_DEFINE" ;;
    *)
      echo "Error: RESOURCE_DEFINE must be RELEASE, ALPHA, or BETA." >&2
      exit 2
      ;;
  esac
fi

for tool in "$CXX" "$WINDRES"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required Windows cross-tool '$tool' is not in PATH." >&2
    exit 2
  fi
done

ACTUAL_TARGET=$("$CXX" -dumpmachine 2>/dev/null || true)
if [[ "$ACTUAL_TARGET" != "$MINGW_TARGET" ]]; then
  echo "Error: '$CXX' targets '$ACTUAL_TARGET'; expected '$MINGW_TARGET'." >&2
  exit 2
fi

mkdir -p "$BUILD_ROOT/bin" "$BUILD_ROOT/rc/include" \
  "$BUILD_ROOT/rc/assets/WIN32" "$PROJECT_ROOT/bin"

# The upstream .rc uses Windows case-insensitive include and asset paths.
# Provide case-correct aliases in the build directory. `include_next` is
# required because the compiler's case-sensitive filesystem lookup can match
# the differently-cased alias itself when it forwards to the real system header.
ln -sfn "$PROJECT_ROOT/src/engine.hpp" "$BUILD_ROOT/rc/include/Engine.HPP"
printf '#include_next <windows.h>\n' > "$BUILD_ROOT/rc/include/Windows.H"
# Remove any lowercase copy from an earlier/manual setup; on Windows it aliases
# the same path as Windows.H and causes the same recursive include.
rm -f "$BUILD_ROOT/rc/include/windows.h"
while IFS=: read -r upper lower; do
  [[ -n "$upper" ]] || continue
  printf '#include_next <%s>\n' "$lower" > "$BUILD_ROOT/rc/include/$upper"
done <<'EOF'
TChar.H:tchar.h
ImageHlp.H:imagehlp.h
TlHelp32.H:tlhelp32.h
ShlObj.H:shlobj.h
RTCapi.H:rtcapi.h
WinSock.H:winsock.h
AccCtrl.H:accctrl.h
AclApi.H:aclapi.h
PsApi.H:psapi.h
EOF
ln -sfn "$PROJECT_ROOT/win32/engine64.ico" \
  "$BUILD_ROOT/rc/assets/WIN32/ENGINE64.ICO"
ln -sfn "$PROJECT_ROOT/win32/engine.xml" \
  "$BUILD_ROOT/rc/assets/WIN32/ENGINE.XML"

RES_OBJECT="$BUILD_ROOT/engine.res"
"$WINDRES" -O coff -i "$PROJECT_ROOT/win32/engine.rc" -o "$RES_OBJECT" \
  -I "$BUILD_ROOT/rc/include" \
  -I "$BUILD_ROOT/rc/assets" \
  -I "$PROJECT_ROOT/src" \
  --preprocessor-arg=-Wno-trigraphs \
  -D RC_INVOKED=1 -D X64=1 -D "$BUILD_DEFINE=1"

if [[ "$BUILD_MODE" == resources ]]; then
  echo "Windows x64 resource object: $RES_OBJECT"
  exit 0
fi

WINLIB="$PROJECT_ROOT/lib/win64"
for lib in lua64.la ssl64.la lzma64.la zlib64.la; do
  if [[ ! -s "$WINLIB/$lib" ]]; then
    echo "Error: missing Windows dependency '$WINLIB/$lib'." >&2
    echo "Build dependencies in the Windows container with:" >&2
    echo "  BUILD_TARGET=windows python3 .build-helpers/scripts/download-linux-dependencies.py" >&2
    exit 3
  fi
done

COMMON_FLAGS=(-std=c++20 -fmax-errors=1 -g
  -I"$BUILD_ROOT/rc/include"
  -I"$PROJECT_ROOT/include/win64"
  -I"$PROJECT_ROOT/include/win64/ft"
  -I"$PROJECT_ROOT/include"
  -I"$PROJECT_ROOT/include/ft"
  "-D$BUILD_DEFINE")
OBJECT="$BUILD_ROOT/build.o"
OUTPUT="$BUILD_ROOT/bin/build.exe"

echo "Compiling Engine build utility for $MINGW_TARGET ($BUILD_MODE)..."
"$CXX" "${COMMON_FLAGS[@]}" "${OPT_FLAGS[@]}" \
  -c "$PROJECT_ROOT/src/build.cpp" -o "$OBJECT"

echo "Linking $OUTPUT..."
# The POSIX MinGW toolchain otherwise leaves a libwinpthread-1.dll runtime
# dependency on Windows hosts.
"$CXX" -municode -mconsole -o "$OUTPUT" "$OBJECT" "$RES_OBJECT" \
  "$WINLIB/lua64.la" "$WINLIB/ssl64.la" \
  "$WINLIB/lzma64.la" "$WINLIB/zlib64.la" \
  -Wl,--gc-sections -Wl,--stack,2097152 \
  -static-libgcc -static-libstdc++ \
  -Wl,-Bstatic -lwinpthread -Wl,-Bdynamic \
  -lkernel32 -luser32 -lgdi32 -lole32 -lversion -limagehlp \
  -ldbghelp -ladvapi32 -lpsapi -lwinmm -lcomctl32 -lshell32 \
  -lws2_32 -lcrypt32 -lbcrypt

# Keep the historical executable path used by the project on Windows, while
# retaining the authoritative cross-build output under build-windows/.
cp -f "$OUTPUT" "$PROJECT_ROOT/bin/build.exe"
echo "Built: $OUTPUT"
echo "Compatibility copy: $PROJECT_ROOT/bin/build.exe"
