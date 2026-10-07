#!/bin/bash
# Compare rubik.s with the gcc -O2 reference build of ida_rv32.c.
#
# Both solve the same state on the same Ripes model; the script reports
# retired instructions and the bytes of .text. The assembly's .text is
# measured by assembling the CLI build with GNU as, so the renderer is
# excluded and both numbers come from the same toolchain.
#
# Usage: ./compare.sh [state] [processor]
#        default 21345671111111 on RV32_ISS
set -e
cd "$(dirname "$0")"
STATE=${1:-21345671111111}
PROC=${2:-RV32_ISS}
RIPES=${RIPES:-"/mnt/c/Users/user/OneDrive/桌面/課程資料/114-1/計算機結構/Ripes/Ripes.exe"}
LEN=$(./solver "$STATE" | wc -w)

./build.sh > /dev/null
./gen_tables c > build/tables.h

# Assembly: the CLI build with this state and its optimal length.
sed -e "s/^input:.*/input:  .string \"$STATE\"/" \
    -e "s/^expected:.*/expected: .byte $LEN/" build/rubik_cli.s > build/cmp_asm.s
riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 -o build/cmp_asm.o build/cmp_asm.s
asm_text=$(riscv64-unknown-elf-size -A build/cmp_asm.o | awk '$1 == ".text" {print $2}')
asm_out=$("$RIPES" --mode cli --src "$(wslpath -w build/cmp_asm.s)" -t asm \
          --proc "$PROC" --iret < /dev/null | tr -d '\r')

# C reference: the same state compiled into ida_rv32.c.
sed -e "s/^static const char input\[15\] = .*/static const char input[15] = \"$STATE\";/" \
    -e "s/^static const unsigned expected = .*/static const unsigned expected = $LEN;/" \
    ida_rv32.c > build/cmp_c.c
riscv64-unknown-elf-gcc -O2 -march=rv32i -mabi=ilp32 -ffreestanding -fno-builtin \
    -nostdlib -nostartfiles -static -mno-relax -I. -Wl,-Ttext=0 -Wl,-e,_start \
    -o build/cmp_c.elf build/cmp_c.c
if riscv64-unknown-elf-nm build/cmp_c.elf | grep -q "__mulsi3\|__divsi3\|__udivsi3\|__modsi3\|__umodsi3"; then
    echo "error: the gcc build calls a libgcc multiply or divide routine" >&2
    exit 1
fi
c_text=$(riscv64-unknown-elf-size -A build/cmp_c.elf | awk '$1 == ".text" {print $2}')
c_out=$("$RIPES" --mode cli --src "$(wslpath -w build/cmp_c.elf)" -t elf \
        --proc "$PROC" --iret < /dev/null | tr -d '\r')

field() { echo "$1" | sed -n "s/^Program exited with code: //p"; }
echo "state $STATE (optimal length $LEN) on $PROC"
printf "%-22s %12s %10s %8s  %s\n" build iret ".text (B)" status solution
printf "%-22s %12s %10s %8s  %s\n" "rubik.s" "$(echo "$asm_out" | tail -1)" \
    "$asm_text" "$(field "$asm_out")" "$(echo "$asm_out" | head -1)"
printf "%-22s %12s %10s %8s  %s\n" "ida_rv32.c (gcc -O2)" "$(echo "$c_out" | tail -1)" \
    "$c_text" "$(field "$c_out")" "$(echo "$c_out" | head -1)"
