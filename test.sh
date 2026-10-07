#!/bin/bash
# Run every test vector through the CLI build in Ripes.
#
# Each case is "state|solution" (tests/solutions.txt and tests/rv32i.txt).
# The expected length is the number of moves in the solution. For each case
# the script rewrites the input: and expected: lines of build/rubik_cli.s,
# runs it, and requires exit status 0: rubik.s exits 1 if its path does not
# reach solved (T5) and 3 if its length differs from the expected one.
#
# Usage: ./test.sh [processor]      default RV32_ISS; e.g. ./test.sh RV32_5S
set -e
cd "$(dirname "$0")"
PROC=${1:-RV32_ISS}
RIPES=${RIPES:-"/mnt/c/Users/user/OneDrive/桌面/課程資料/114-1/計算機結構/Ripes/Ripes.exe"}
./build.sh > /dev/null
mkdir -p build
fail=0
printf "%-16s %3s  %-36s %6s %12s\n" state len solution status iret
for file in tests/solutions.txt tests/rv32i.txt; do
    [ -f "$file" ] || continue
    while IFS='|' read -r state solution; do
        case "$state" in ""|\#*) continue ;; esac
        len=$(echo $solution | wc -w)
        sed -e "s/^input:.*/input:  .string \"$state\"/" \
            -e "s/^expected:.*/expected: .byte $len/" \
            build/rubik_cli.s > build/case.s
        # < /dev/null: otherwise Ripes reads the rest of the case list
        out=$("$RIPES" --mode cli --src "$(wslpath -w build/case.s)" -t asm \
              --proc "$PROC" --iret < /dev/null | tr -d '\r')
        got=$(echo "$out" | head -1 | sed 's/ *$//')
        status=$(echo "$out" | sed -n 's/^Program exited with code: //p')
        iret=$(echo "$out" | tail -1)
        printf "%-16s %3s  %-36s %6s %12s\n" "$state" "$len" "$got" "$status" "$iret"
        [ "$status" = 0 ] || fail=1
    done < "$file"
done
[ $fail = 0 ] && echo "all cases pass on $PROC" || { echo "FAILURES on $PROC"; exit 1; }
