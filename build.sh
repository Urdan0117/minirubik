#!/bin/sh
# Assemble Ripes sources from the hand-written code and the generated tables.
#
# Ripes takes a single source file and has neither .include nor .if, so
# this script does what those directives would: it appends the tables to
# rubik.s, and it produces two builds that differ only in the renderer.
#
#   build/rubik_gui.s   everything, for the GUI with an LED matrix
#   build/rubik_cli.s   lines between "#@render-begin" and "#@render-end"
#                       removed, for `Ripes --mode cli` and --iret
set -e
cd "$(dirname "$0")"
gcc -O2 -std=c99 -Wall -Wno-unused-function -o gen_tables gen_tables.c
mkdir -p build
./gen_tables > build/tables.s
cat rubik.s build/tables.s > build/rubik_gui.s
sed '/#@render-begin/,/#@render-end/d' rubik.s | cat - build/tables.s > build/rubik_cli.s
echo "built build/rubik_gui.s and build/rubik_cli.s"
