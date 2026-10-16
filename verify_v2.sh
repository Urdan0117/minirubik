#!/bin/sh
# Check C v2 (ida_rv32.c) against gates H1-H3 on the host.
#
# ida_rv32.c targets Ripes: it prints through ecall and starts at a naked
# _start. The sed edits below make a host copy without touching the
# search, and verify_v2.c runs that copy's main on every state.
#
#   ./verify_v2.sh          all 3,674,160 states (several minutes)
#   ./verify_v2.sh 1000     every 1000th state, as a quick smoke test
set -e
cd "$(dirname "$0")"
mkdir -p build
gcc -O2 -std=c99 -Wall -Wno-unused-function -o gen_tables gen_tables.c
./gen_tables c > build/tables.h
sed -e 's/^static const char input\[15\] = .*/static char input[15];/' \
    -e 's/^static const unsigned expected = .*/static unsigned expected;/' \
    -e '/^static void put_char(int c)$/,/^}$/c\
static char out[64];\
static int outn;\
static void put_char(int c)\
{\
    out[outn++] = (char) c;\
}' \
    -e '/__asm__("" : "+r"(p));/d' \
    -e 's/^int main(void)$/int v2_main(void)/' \
    -e '/^\/\* Entry point/,$d' \
    ida_rv32.c > build/v2_host.c
gcc -O2 -std=gnu99 -Wall -Wno-unused-function -I. -o verify_v2 verify_v2.c
./verify_v2 "$@"
