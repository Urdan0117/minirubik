#!/bin/sh
# Build, then run the CLI build in Ripes and report retired instructions.
#
# Usage: ./run.sh [processor]      default RV32_ISS; e.g. ./run.sh RV32_5S
set -e
cd "$(dirname "$0")"
./build.sh > /dev/null
RIPES=${RIPES:-"/mnt/c/Users/user/OneDrive/桌面/課程資料/114-1/計算機結構/Ripes/Ripes.exe"}
# Ripes.exe is a GUI-subsystem program: run straight in a terminal, its
# output never reaches the screen. Piping it through cat makes it appear.
"$RIPES" --mode cli --src "$(wslpath -w build/rubik_cli.s)" -t asm \
    --proc "${1:-RV32_ISS}" --iret | cat
