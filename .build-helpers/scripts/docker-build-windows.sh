#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELPER_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd -- "${HELPER_ROOT}/.." && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: .build-helpers/scripts/docker-build-windows.sh [-- COMMAND [ARGS...]]
       .build-helpers/scripts/docker-build-windows.sh clean-image

With no arguments, builds Windows dependencies, the Engine build utility,
the Diggers executable, and the Windows distributable package.
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

IMAGE="${WINDOWS_BUILDER_IMAGE:-mhatxotic-engine-windows-builder:trixie-mingw64}"
WINEPREFIX_CONTAINER="${WINEPREFIX_CONTAINER:-/tmp/engine-wineprefix-$(id -u)-$$}"
WINE_PROJECT_DIR="${WINE_PROJECT_DIR:-${WINEPREFIX_CONTAINER}/drive_c/src}"
if [[ "$WINEPREFIX_CONTAINER" != /* ]]; then
  echo "Error: WINEPREFIX must be an absolute container path." >&2
  exit 2
fi
if [[ "$WINE_PROJECT_DIR" != "${WINEPREFIX_CONTAINER}/drive_c/"* ]]; then
  echo "Error: WINE_PROJECT_DIR must be under '${WINEPREFIX_CONTAINER}/drive_c/'." >&2
  exit 2
fi

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

With no arguments, builds Windows dependencies, the Engine build utility,
the Diggers executable, and the Windows distributable package.
USAGE
  exit 2
else
CONTAINER_BUILD_SCRIPT=$(cat <<'BUILD'
set -euo pipefail
mkdir -p ./bin ./debug
BUILD_TARGET=windows python3 ./.build-helpers/scripts/download-linux-dependencies.py
python3 ./.build-helpers/scripts/create-build-json.py
./scripts/build-windows.sh "${BUILD_TYPE:-Release}"
wine ./bin/build.exe G8bV
wine ./bin/build.exe G8bLV
wine ./bin/build.exe G8bfV
test -s ./bin/engine64.exe
test -s ./Diggers/Diggers.adb
find ./distro -maxdepth 1 -type f -name "Diggers-*-Windows-X64.7z" \
  -print -quit | grep -q .
BUILD
)
  CONTAINER_COMMAND=(bash -euo pipefail -c "$CONTAINER_BUILD_SCRIPT")
fi

# Mount the workspace outside the Wine prefix. Docker creates bind-mount
# destination parents as root; mounting below drive_c would make the prefix
# root-owned and Wine would refuse to use it. Expose the workspace to Windows
# processes through C:\\src with a symlink created by the container user.
CONTAINER_COMMAND=(bash -euo pipefail -c '
  if [[ -e "$WINEPREFIX" && "$(stat -c %u -- "$WINEPREFIX")" != "$(id -u)" ]]; then
    echo "Error: Wine prefix is not owned by container user $(id -u): $WINEPREFIX" >&2
    echo "Set WINEPREFIX_CONTAINER to a new writable container path." >&2
    exit 2
  fi
  mkdir -p "$HOME" "$WINEPREFIX/drive_c" "$(dirname -- "$WINE_PROJECT_DIR")"
  if [[ -e "$WINE_PROJECT_DIR" && ! -L "$WINE_PROJECT_DIR" ]]; then
    echo "Error: WINE_PROJECT_DIR exists and is not a symlink: $WINE_PROJECT_DIR" >&2
    echo "Use a fresh WINEPREFIX_CONTAINER or remove that old prefix." >&2
    exit 2
  fi
  ln -sfn /workspace "$WINE_PROJECT_DIR"
  cd /workspace
  exec "$@"
' wine-container "${CONTAINER_COMMAND[@]}")

exec "$ENGINE" run --rm "${TTY_ARGS[@]}" "${RUN_ARGS[@]}" \
  --env BUILD_DIR="${BUILD_DIR:-build-windows}" \
  --env BUILD_TYPE="${BUILD_TYPE:-Release}" \
  --env JOBS="${JOBS:-}" \
  --env HOME="${WINDOWS_CONTAINER_HOME:-/tmp/engine-windows-build-home}" \
  --env WINEPREFIX="$WINEPREFIX_CONTAINER" \
  --env WINE_PROJECT_DIR="$WINE_PROJECT_DIR" \
  --env WINEARCH="${WINEARCH:-win64}" \
  --env WINEDEBUG="${WINEDEBUG:-fixme-all}" \
  --env BUILD_TARGET=windows \
  --env MINGW_TARGET="${MINGW_TARGET:-x86_64-w64-mingw32}" \
  --volume "${PROJECT_ROOT}:/workspace${VOLUME_SUFFIX}" \
  --workdir /workspace \
  "$IMAGE" "${CONTAINER_COMMAND[@]}"
