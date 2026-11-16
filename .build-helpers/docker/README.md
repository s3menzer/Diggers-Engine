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

