# Docker

## Refresh image
```
  podman build --pull --no-cache \
    -t mhatxotic-engine-linux-builder:trixie-gcc14-deps-2026.11.16 \
    -f .build-helpers/docker/Dockerfile.linux \
    .build-helpers/docker
```

## Start shell
```
    ./.build-helpers/scripts/docker-shell-linux.sh
```

## Full Linux build
```sh
./.build-helpers/scripts/docker-build-linux.sh
```

The build entry point creates the image if needed, then downloads/builds the
Linux dependencies, builds the helper, Diggers assets and executable, and
packages the game. GitHub Actions uses the same script.
