#!/usr/bin/env bash
# tests/device_build.sh — builds the two device programs, tests/device_read.nv
# and examples/mlc_activity.nv, for three boards and reports the image sizes.
#
# A program is a firmware `main`, so each is built as the `main` of a scratch
# package that depends on this one by path, the way a program on a device
# depends on it.  The MLC program reads the text of ST's configuration file
# as a package asset, which the scratch package declares.  The boards are the
# Nordic nRF52840-DK and nRF54LM20-DK and the NXP FRDM-MCXN947.  Nothing is
# flashed.  The emulated board's image (nrf52-qemu) of the MLC program is then
# run under QEMU, where no device answers on the I2C bus, and its first line
# must be the program's refusal.
#
# Run from anywhere:  bash tests/device_build.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$HERE/.." && pwd)"
NOVO="${NOVO:-$HOME/.novo/bin/novo}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lsm6dso-nv-dev.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail=0

# build NAME SOURCE ASSET TARGETS...
#   NAME is the label of the program, SOURCE its file in the package, ASSET
#   `yes` when it needs the `st_ucf` asset, TARGETS the boards.
build() {
  local name="$1" source="$2" asset="$3"
  shift 3
  local dir="$WORK/$name"
  mkdir -p "$dir/src" "$dir/data"
  cp "$PKG/$source" "$dir/src/main.nv"
  {
    echo '[package]'
    echo "name    = \"lsm6dso-nv-$name\""
    echo 'version = "0.1.0"'
    echo 'main    = "src/main.nv"'
    echo
    echo '[dependencies]'
    echo "lsm6dso-nv      = { path = \"$PKG\" }"
    echo 'devices-nv      = "^0.3.2"'
    echo 'embedded-hal-nv = "^0.3.2"'
    if [ "$asset" = yes ]; then
      cp "$PKG/tests/data/lsm6dsox_activity_recognition_for_mobile.ucf" "$dir/data/activity.ucf"
      echo
      echo '[assets]'
      echo 'module   = "st_ucf"'
      echo 'activity = "data/activity.ucf"'
    fi
  } > "$dir/novo.toml"
  for target in "$@"; do
    rm -f "$dir/main.elf"
    ( cd "$dir" && NOVO_LEAK_CHECK=0 timeout 900 "$NOVO" build --target="$target" src/main.nv ) \
      > "$dir/$target.log" 2>&1
    if [ -f "$dir/main.elf" ]; then
      flash=$(grep -m1 '^  flash ' "$dir/$target.log" | sed 's/^  flash *//')
      ram=$(grep -m1 '^  .data + .bss' "$dir/$target.log" | sed 's/^  .data + .bss *//')
      echo "  ✓ $source builds for --target=$target: flash $flash"
      echo "      RAM at start (.data and .bss): $ram"
      cp "$dir/main.elf" "$dir/$target.elf"
    else
      echo "  ✗ $source does not build for --target=$target"
      grep -vE '^novo:' "$dir/$target.log" | head -20 | sed 's/^/      /'
      fail=1
    fi
  done
}

build read tests/device_read.nv no nrf52840-dk nrf54lm20-dk frdm-mcxn947
build mlc examples/mlc_activity.nv yes nrf52840-dk nrf54lm20-dk frdm-mcxn947 nrf52-qemu

# The emulated board: an MPS2 AN386 Cortex-M4, whose UART output reaches the
# host through semihosting and whose I2C bus is a stub that no part is on.
if ! command -v qemu-system-arm >/dev/null 2>&1; then
  echo "  - the image is not run: qemu-system-arm is not installed"
elif [ -f "$WORK/mlc/nrf52-qemu.elf" ]; then
  out=$(timeout "${QEMU_SECONDS:-15}" qemu-system-arm -machine mps2-an386 -nographic -semihosting \
          -kernel "$WORK/mlc/nrf52-qemu.elf" 2>&1 | grep -v '^\[gpio\]' | head -20)
  if printf '%s\n' "$out" | tr -d '\r' | grep -qx 'lsm6dsox: no answer'; then
    echo "  ✓ the image runs under QEMU and reports that the part does not answer"
  else
    echo "  ✗ the image under QEMU did not report that the part does not answer"
    printf '%s\n' "$out" | head -10 | sed 's/^/      /'
    fail=1
  fi
fi
exit "$fail"
