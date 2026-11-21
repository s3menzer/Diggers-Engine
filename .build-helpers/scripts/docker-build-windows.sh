#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELPER_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd -- "${HELPER_ROOT}/.." && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: .build-helpers/scripts/docker-build-windows.sh [-- COMMAND [ARGS...]]
       .build-helpers/scripts/docker-build-windows.sh clean-image

With no arguments, builds Windows dependencies, cross-compiles the Diggers
executable with `.build-helpers/make/makefile.windows`, and creates the Windows distro package.
USAGE
  exit 0
fi

if [[ -n "${CONTAINER_ENGINE:-}" ]]; then
  ENGINE="$CONTAINER_ENGINE"
elif command -v podman >/dev/null 2>&1; then
  ENGINE=podman
elif command -v docker >/dev/null 2>&1; then
  ENGINE=docker
else
  echo "Error: install Docker or Podman, or set CONTAINER_ENGINE." >&2
  exit 2
fi

if ! command -v "$ENGINE" >/dev/null 2>&1; then
  echo "Error: container engine '$ENGINE' was not found in PATH." >&2
  exit 2
fi

ENGINE_PATH="$(command -v "$ENGINE")"
ENGINE_NAME="$(basename -- "$ENGINE_PATH")"
ENGINE_IS_PODMAN=0
if [[ "$ENGINE_NAME" == podman* ]] || grep -qi podman "$ENGINE_PATH" 2>/dev/null; then
  ENGINE_IS_PODMAN=1
fi

IMAGE="${WINDOWS_BUILDER_IMAGE:-mhatxotic-engine-windows-builder:trixie-mingw64-native-2026.11}"

if [[ "${1:-}" == "clean-image" ]]; then
  "$ENGINE" image rm "$IMAGE" || true
  exit 0
fi

if [[ "${WINDOWS_IMAGE_PULL:-0}" == "1" ]]; then
  "$ENGINE" pull "$IMAGE"
fi

if [[ "${WINDOWS_REBUILD_IMAGE:-0}" == "1" ]] || \
   ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Building Windows MinGW-w64 builder image '$IMAGE'..."
  "$ENGINE" build --tag "$IMAGE" \
    --file "${PROJECT_ROOT}/.build-helpers/docker/Dockerfile.windows" \
    "${PROJECT_ROOT}/.build-helpers/docker"
fi

if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Error: builder image '$IMAGE' is not available." >&2
  exit 3
fi

if [[ -n "${CONTAINER_VOLUME_SUFFIX+x}" ]]; then
  VOLUME_SUFFIX="$CONTAINER_VOLUME_SUFFIX"
elif [[ "$ENGINE_IS_PODMAN" == 1 ]]; then
  VOLUME_SUFFIX=:Z
else
  VOLUME_SUFFIX=
fi

RUN_ARGS=()
if [[ "${CONTAINER_USE_HOST_USER:-1}" == 1 ]]; then
  if [[ "$ENGINE_IS_PODMAN" == 1 ]]; then
    RUN_ARGS+=(--userns=keep-id)
  fi
  RUN_ARGS+=(--user "$(id -u):$(id -g)")
elif [[ -n "${CONTAINER_USER_SPEC:-}" ]]; then
  RUN_ARGS+=(--user "$CONTAINER_USER_SPEC")
fi

TTY_ARGS=(-i)
if [[ -t 0 && -t 1 ]]; then
  TTY_ARGS=(-it)
fi

if [[ "${1:-}" == "--" ]]; then
  shift
  if (($# == 0)); then
    echo "Error: provide a container command after --." >&2
    exit 2
  fi
  CONTAINER_COMMAND=("$@")
elif (($#)); then
  cat >&2 <<'USAGE'
Usage: .build-helpers/scripts/docker-build-windows.sh [clean-image | -- COMMAND [ARGS...]]

With no arguments, builds Windows dependencies, cross-compiles the Diggers
executable with `.build-helpers/make/makefile.windows`, and creates the Windows distro package.
USAGE
  exit 2
else
CONTAINER_BUILD_SCRIPT=$(cat <<'BUILD'
set -euo pipefail
mkdir -p "$HOME"
mkdir -p ./bin ./debug
BUILD_TARGET=windows python3 ./.build-helpers/scripts/download-linux-dependencies.py
make --jobs="${JOBS:-8}" -f .build-helpers/make/makefile.windows windows \
  BUILD_TYPE="${BUILD_TYPE:-Release}" JOBS="${JOBS:-8}"
test -s ./bin/engine64.exe
test -s ./Diggers/Diggers.adb
mkdir -p ./distro
cat > ./distro/start.cmd <<'START_CMD'
set LC_ALL=C
set LANG=C
Diggers.exe
START_CMD
find ./distro -maxdepth 1 -type f -name "Diggers-*-Windows-X64.7z" \
  -print -quit | grep -q .
BUILD
)
  CONTAINER_COMMAND=(bash -euo pipefail -c "$CONTAINER_BUILD_SCRIPT")
fi

exec "$ENGINE" run --rm "${TTY_ARGS[@]}" "${RUN_ARGS[@]}" \
  --env HOME="${WINDOWS_CONTAINER_HOME:-/tmp/engine-windows-build-home}" \
  --env BUILD_TYPE="${BUILD_TYPE:-Release}" \
  --env JOBS="${JOBS:-8}" \
  --env BUILD_DEFINE="${BUILD_DEFINE:-BETA}" \
  --env BUILD_TARGET=windows \
  --env MINGW_TARGET="${MINGW_TARGET:-x86_64-w64-mingw32}" \
  --env MINGW_THREAD_MODEL=posix \
  --env MINGW_CXX="${MINGW_CXX:-${MINGW_TARGET:-x86_64-w64-mingw32}-g++-posix}" \
  --env MINGW_WINDRES="${MINGW_WINDRES:-${MINGW_TARGET:-x86_64-w64-mingw32}-windres}" \
  --env SEVEN_ZIP="${SEVEN_ZIP:-7zz}" \
  --volume "${PROJECT_ROOT}:/workspace${VOLUME_SUFFIX}" \
  --workdir /workspace \
  "$IMAGE" "${CONTAINER_COMMAND[@]}"
