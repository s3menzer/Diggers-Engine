# Engine_2 Linux build and run

Run build commands from the `Engine_2` project root unless noted otherwise.

## 1. Download and build third-party dependencies

Download and build missing dependencies from the pinned archives:

```sh
python3 ./.build-helpers/scripts/download-linux-dependencies.py
```

The script stores archives in `archive/`, then invokes the per-library build
scripts from the project root with arguments from `versions-linux.json`. It
skips build scripts only when both the library and declared headers exist.
SimpleWebP and RapidJSON are header-only dependencies, installed by
`scripts/simplewebp.sh` and `scripts/rapidjson.sh`. `--download-only` fetches
archives without running install/build scripts. Options and versions are in
[`README-linux-dependencies.md`](README-linux-dependencies.md).

## 2. Build the project helper

After the dependencies are built, compile the helper executable:

```sh
./scripts/build-linux.sh
```

This creates `bin/build.elf`.

## 3. Build Diggers

Generate `build.json` from the engine version macros, then build Diggers:

```sh
python3 .build-helpers/scripts/create-build-json.py
./bin/build.elf
```

The helper reads `VER_MAJOR`, `VER_MINOR`, `VER_BUILD`, and `VER_REV` from
`src/engine.hpp` (included by `src/engine.cpp`) and writes `build.json` in the
project root. It uses the project name `Diggers`.

## 4. Launch the game

Run the game from the `Diggers` directory:

```sh
cd Diggers
env -u DISPLAY \
  XDG_SESSION_TYPE=wayland \
  XCURSOR_THEME=Adwaita \
  XCURSOR_SIZE=24 \
  ALSOFT_DRIVERS=pipewire,pulse,alsa \
  ./engine64.elf 'log_file=+'
```

### Current audio note

The current OpenAL log reports only `oss` and `null` as supported backends.
Therefore the launch command above cannot open PipeWire, PulseAudio, or ALSA
until OpenAL is rebuilt with one or more of those backends enabled and
`engine64.elf` is relinked against that build. `null` produces no audible
output.
