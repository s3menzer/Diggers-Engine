# Windows MinGW-w64 builder

From the Engine_2 root:

```sh
./.build-helpers/scripts/docker-build-windows.sh
./.build-helpers/scripts/docker-shell-windows.sh
```

The build command creates the image if needed, builds Windows-target
dependencies and the helper, then runs the helper under Wine to rebuild the
Diggers assets, compile the 64-bit beta executable, and create the Windows
distributable. GitHub Actions calls this same entry point. Set `BUILD_TYPE`
to `Debug` to change the helper build mode. Use the shell command for manual
work; it only starts Bash and does not run build steps. To execute a different
container command directly, pass it after `--` to `docker-build-windows.sh`.

The builder uses `x86_64-w64-mingw32`. `scripts/build-windows.sh` is the
container equivalent of the 64-bit `ms64`, `ms64d`, and `res` modes from
`scripts/build-win32.bat`; the batch file remains available for native MSVC.
Release is the default; Debug builds the alpha/debug variant. MinGW keeps
debug symbols in the executable/object instead of creating an MSVC `.pdb`.

The full build script compiles the pinned Windows dependencies automatically.
To run that step manually in the shell:

```sh
BUILD_TARGET=windows python3 .build-helpers/scripts/download-linux-dependencies.py
```

The resulting Windows libraries and headers stay separate from native Linux
outputs in `lib/win64/` and `include/win64/`. The builder executable is written
to `build-windows/bin/build.exe` and copied to the historical `bin/build.exe`
path. Object and resource files are kept in `build-windows/`.

The image includes 64-bit Wine to run the builder executable in the Linux
container. The project is mounted at `/workspace` and linked as
`$WINEPREFIX/drive_c/src` (Wine path `C:\src`). Keeping the bind mount outside
the prefix lets the container user own the Wine prefix. A fresh temporary
prefix is used for each run; set `WINEPREFIX_CONTAINER` to override its
container path. `WINE_PROJECT_DIR` can override the link path but must remain
below `${WINEPREFIX}/drive_c/`.

Rebuild the image and open a shell with:

```sh
WINDOWS_REBUILD_IMAGE=1 ./.build-helpers/scripts/docker-shell-windows.sh
wine ./bin/build.exe G8b
```

The builder defaults to MSVC, which is not installed in this container. `G`
selects the separate Windows-native MinGW toolchain bundled for Wine; `8b`
selects the 64-bit beta build. The original MSVC environment (`1`) remains
available for native Windows use. Windows dependency archives should first be
built with `BUILD_TARGET=windows python3 .build-helpers/scripts/download-linux-dependencies.py`;
the MinGW profile links the resulting archives from `lib/win64/` and uses
headers in `include/win64/` ahead of the shared `include/` tree.

The Windows-hosted compiler is WinLibs MinGW-w64 GCC 14.2.0 (MSVCRT), pinned
to a release archive and SHA-256 in `.build-helpers/docker/Dockerfile.windows`.
Debian's Linux-hosted MinGW tools remain installed for dependency builds; Wine
cannot launch those Linux executables.

Use the `wine` launcher for the 64-bit executable; this avoids relying on a
separate `wine64` command name. Wine32 is not needed. `BUILD_DIR`, `BUILD_TYPE`,
and `JOBS` are configurable. `CONTAINER_ENGINE`
selects Docker or Podman (Podman is preferred when available); volume suffix
and container user can be set with `CONTAINER_VOLUME_SUFFIX`,
`CONTAINER_USE_HOST_USER`, and `CONTAINER_USER_SPEC`. Override the image with
`WINDOWS_BUILDER_IMAGE`, pull it with `WINDOWS_IMAGE_PULL=1`, or rebuild it with
`WINDOWS_REBUILD_IMAGE=1`. The `debian:trixie-slim` base tag is intentionally
movable, so rebuilding may update installed package versions.
