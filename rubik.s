# Optimal 2x2x2 solver in RV32I. See build.sh for how this file becomes
# a Ripes source: the search tables are appended from gen_tables.c.

        .data
input:  .string "51673422313211"       # the state to solve
expected: .byte 3                     # optimal length; test.sh rewrites this
perm:   .zero 7                        # cubie digits as 0..6

# Register allocation:
#   s0  address of the input string
#   s1  permutation rank p (result of part A)
#   s2  orientation rank o (result of part A)
#   s3  address of perm[], the 7 cubie digits as 0..6
#   t0-t6  scratch, clobbered freely

        .text
main:
# ---------- A. Parse the input and rank it ----------
# Leaves the permutation rank in s1 and the orientation rank in s2.
        la    s0, input
        la    s3, perm

# A1. Copy the 7 cubie digits to perm[] as 0..6; reject out-of-range
#     digits and repeated cubies (seen is a bitmask, one bit per cubie).
        li    t1, 0                    # i
        li    t2, 0                    # seen
        li    t6, 7
a1_loop:
        add   t3, s0, t1
        lbu   t3, 0(t3)                # c = input[i]
        addi  t3, t3, -49            # (A1) c = c - '1'
        bgeu  t3, t6, bad_input        # c > 6, or c < 0 seen as unsigned
        srl   t4, t2, t3
        andi  t4, t4, 1
        bnez  t4, bad_input            # cubie c already seen
        li    t4, 1
        sll   t4, t4, t3             # (A2) t4 = 1 << c
        or    t2, t2, t4               # seen |= 1 << c
        add   t4, s3, t1
        sb    t3, 0(t4)                # perm[i] = c
        addi  t1, t1, 1
        blt   t1, t6, a1_loop

# A2. Orientation rank: the first six twists as a base-3 number.
#     All seven twists must be 0..2 and sum to 0 mod 3.
        li    s2, 0                    # o
        li    t5, 0                    # twist sum
        li    t1, 0
        li    t6, 3
a2_loop:
        add   t3, s0, t1
        lbu   t3, 7(t3)                # twist digit input[7 + i]
        addi  t3, t3, -49
        bgeu  t3, t6, bad_input
        add   t5, t5, t3
        li    t4, 6
        beq   t1, t4, a2_next          # the seventh twist is not ranked
        slli  t4, s2, 1             # (A3) together with the next line:
        add   s2, s2, t4               #      s2 = s2 * 3
        add   s2, s2, t3               # s2 = s2 * 3 + twist
a2_next:
        addi  t1, t1, 1
        li    t4, 7
        blt   t1, t4, a2_loop
a2_mod:                                # sum is 0..14: subtract 3 until < 3
        blt   t5, t6, a2_done
        addi  t5, t5, -3             # (A4)
        j     a2_mod
a2_done:
        bnez  t5, bad_input            # sum not divisible by 3

# A3. Permutation rank by Horner's rule: p = p * (7 - i) + c_i, where
#     c_i counts the entries after i that are smaller than perm[i].
        li    s1, 0                    # p
        li    t1, 0                    # i
a3_outer:
        add   t4, s3, t1
        lbu   t4, 0(t4)                # perm[i]
        li    t5, 0                    # c_i
        addi  t2, t1, 1                # j = i + 1
a3_inner:
        li    t0, 7
        bge   t2, t0, a3_count_done
        add   t0, s3, t2
        lbu   t0, 0(t0)                # perm[j]
        bgeu  t0, t4, a3_not_smaller   # (A5) skip unless perm[j] < perm[i]
        addi  t5, t5, 1
a3_not_smaller:
        addi  t2, t2, 1
        j     a3_inner
a3_count_done:
        li    t0, 7
        sub   t0, t0, t1             # (A6) t0 = 7 - i
        mv    t3, s1                   # multiply s1 by t0 by repeated
a3_mul:                                # addition: add the old p t0-1 times
        addi  t0, t0, -1
        beqz  t0, a3_mul_done
        add   s1, s1, t3
        j     a3_mul
a3_mul_done:
        add   s1, s1, t5             # (A7) p = p * (7 - i) + c_i
        addi  t1, t1, 1
        li    t0, 7
        blt   t1, t0, a3_outer

# ---------- B. IDA* search ----------
# Frame layout, 16 bytes per depth: +0 p, +2 o (the state at this depth),
# +4 cp, +6 co (the child being turned), +8 face, +9 turn.
# The current depth's cp, co, face and turn live in registers:
#   a3 cp   a4 co   a5 face (0..2, 3 = done)   a6 turn (0..3)
# They go to the frame only when the search descends, and come back
# from it when the search backs up.
        la    s7, frames
        la    s8, perm_base
        la    s9, orient_base
        la    s10, perm_pdb
        la    s11, orient_pdb
        mv    a0, s1
        mv    a1, s2
        jal   h
        mv    s4, a0                   # bound starts at h(root)
b_bound:
        li    s5, 0                    # depth = 0
        mv    s6, s7
        sh    s1, 0(s6)
        sh    s2, 2(s6)
        mv    a3, s1                   # cp, co start at the root state
        mv    a4, s2
        jal   enter
b_loop:
        or    t0, a3, a4           # (V1) the state at this depth is
        beqz  t0, b_found              #      still in cp, co: solved?
b_next:
        li    t3, 3
        bne   a6, t3, b_turn         # (V2) this face still has turns left
        addi  a5, a5, 1                # all three turns tried: next face
        li    a6, 0
        lhu   a3, 0(s6)             # (V3) restart cp from this depth's p
        lhu   a4, 2(s6)                #      and co from its o
        jal   skip_last
b_turn:
        li    t3, 3
        beq   a5, t3, b_back
        mv    a0, a3                   # one more quarter turn on cp, co
        mv    a1, a4
        mv    a2, a5
        jal   qturn
        mv    a3, a0
        mv    a4, a1
        addi  a6, a6, 1
        jal   h                        # a0 = h(child); a0, a1 still hold it
        add   a0, a0, s5
        addi  a0, a0, 1
        bgt   a0, s4, b_next           # prune
        sh    a3, 4(s6)                # descend: save this depth's progress
        sh    a4, 6(s6)
        sb    a5, 8(s6)             # (V4)
        sb    a6, 9(s6)
        addi  s5, s5, 1
        addi  s6, s6, 16
        sh    a3, 0(s6)                # the child is the new depth's state,
        sh    a4, 2(s6)                # and a3, a4 already hold it
        jal   enter
        j     b_loop
b_back:
        addi  s5, s5, -1               # back up one depth
        addi  s6, s6, -16
        bltz  s5, b_raise              # (V5) depth < 0: the whole tree failed
        lhu   a3, 4(s6)             # (V6) restore the parent's progress
        lhu   a4, 6(s6)
        lbu   a5, 8(s6)
        lbu   a6, 9(s6)
        j     b_next
b_raise:
        addi  s4, s4, 1                # raise the bound and start over
        j     b_bound

# enter: start trying children at the current depth.
enter:
        li    a5, 0
        li    a6, 0
# skip_last: skip the face of the move that led here.
skip_last:
        beqz  s5, skip_done            # depth 0 has no previous move
        lbu   t0, -8(s6)               # the previous depth's face
        bne   t0, a5, skip_done      # (V7)
        addi  a5, a5, 1
skip_done:
        ret
# qturn: one quarter turn of face a2 applied to (a0, a1) = (p, o).
# Indexes perm_base / orient_base by face, so no multiply by the block size.
qturn:
        slli  t0, a2, 2                # face * 4: one .word per face
        add   t1, s8, t0
        lw    t1, 0(t1)                # this face's permutation table
        slli  t4, a0, 1                # p * 2: one .half per entry
        add   t1, t1, t4
        lhu   a0, 0(t1)
        add   t1, s9, t0
        lw    t1, 0(t1)                # this face's orientation table
        slli  t4, a1, 1
        add   t1, t1, t4
        lhu   a1, 0(t1)
        ret

# h: a0 = max(perm_pdb[a0], orient_pdb[a1]).
h:
        add   t0, s10, a0
        lbu   t0, 0(t0)
        add   t1, s11, a1
        lbu   t1, 0(t1)
        bgeu   t0, t1, h_done           # (B8) keep t0 if it is already the max
        mv    t0, t1
h_done:
        mv    a0, t0
        ret

# ---------- C. Replay the path (T5) and D. print it ----------
# The frames hold the moves: at each depth below the solution length,
# face and turn are the move that led one level down.
b_found:
        mv    s4, s5                   # solution length
        #@render-begin
        jal   r_init                   # draw the input state
        #@render-end
        mv    a0, s1                   # replay from the input state
        mv    a1, s2
        mv    s6, s7
        li    s5, 0
c_level:
        beq   s5, s4, c_done
        lbu   a2, 8(s6)                # face
        lbu   s3, 9(s6)                # quarter turns
c_turn:
        jal   qturn
        #@render-begin
        jal   r_qturn                  # turn the renderer's copy too
        #@render-end
        addi  s3, s3, -1
        bnez  s3, c_turn
        #@render-begin
        jal   r_show                   # one frame per move
        #@render-end
        mv    t5, a0                   # keep the state across the prints
        mv    t6, a1
        la    t0, face_name
        add   t0, t0, a2
        lbu   a0, 0(t0)
        li    a7, 11                   # PrintChar
        ecall
        lbu   t1, 9(s6)
        la    t0, turn_name
        add   t0, t0, t1
        lbu   a0, 0(t0)
        beqz  a0, c_space              # a quarter turn has no suffix
        ecall
c_space:
        li    a0, 32
        ecall
        mv    a0, t5
        mv    a1, t6
        addi  s5, s5, 1
        addi  s6, s6, 16
        j     c_level
c_done:
        or    a0, a0, a1
        bnez  a0, bad_path             # T5: the path must reach solved
        la    t0, expected
        lbu   t0, 0(t0)
        bne  s4, t0, bad_length     # (T1) the length must match
        li    a0, 10                   # '\n'
        li    a7, 11
        ecall
        li    a0, 0
        li    a7, 93                   # Exit with status 0
        ecall
bad_path:
        li    a0, 1
        li    a7, 93
        ecall
bad_length:
        li    a0, 3                 # (T2) exit status for a wrong length
        li    a7, 93
        ecall
bad_input:
        li    a0, 2
        li    a7, 93
        ecall


#@render-begin
# ---------- E. LED renderer (GUI build only) ----------
# The search works on ranks, but drawing needs the cubie and the twist at
# each position. The renderer keeps its own copy of the state, r_perm and
# r_twist, starts it from the parsed input, and turns it with the same
# source and twist tables as solver.c's quarter_turn, one quarter turn for
# every quarter turn the replay applies. The frames therefore follow the
# solver's actual output. Clobbers t0-t6 and a3-a6; preserves a0-a2.

        .equ  DELAY, 200000            # busy-wait per frame, in iterations

# r_init: copy the parsed input into r_perm, r_twist and draw it.
r_init:
        la    t0, perm
        la    t1, r_perm
        la    t2, input
        la    t3, r_twist
        li    t4, 7
r_init_loop:
        lbu   t5, 0(t0)                # cubie digit, 0..6
        sb    t5, 0(t1)
        lbu   t5, 7(t2)                # twist digit '1'..'3'
        addi  t5, t5, -49
        sb    t5, 0(t3)
        addi  t0, t0, 1
        addi  t1, t1, 1
        addi  t2, t2, 1
        addi  t3, t3, 1
        addi  t4, t4, -1
        bnez  t4, r_init_loop
        j     r_show                   # draw; r_show returns to our caller

# r_qturn: one quarter turn of face a2 on r_perm, r_twist.
# new_perm[i] = perm[src[i]], new_twist[i] = (twist[src[i]] + tw[i]) mod 3
r_qturn:
        slli  t0, a2, 3                # each table row is padded to 8 bytes
        la    t1, src_tab
        add   t1, t1, t0               # this face's source row
        la    t2, tw_tab
        add   t2, t2, t0               # this face's twist row
        la    a3, r_perm
        la    a4, r_twist
        la    a5, r_tmp
        li    t3, 0                    # i
r_q_loop:
        add   t4, t1, t3
        lbu   t4, 0(t4)                # from = src[i]
        add   t5, a3, t4
        lbu   t5, 0(t5)
        add   t6, a5, t3
        sb    t5, 0(t6)                # r_tmp[i] = perm[from]
        add   t5, a4, t4
        lbu   t5, 0(t5)                # twist[from]
        add   t4, t2, t3
        lbu   t4, 0(t4)                # tw[i]
        add   t5, t5, t4
        li    t4, 3
        blt   t5, t4, r_q_mod
        addi  t5, t5, -3             # (L1) sum is at most 4: one subtract is exact
r_q_mod:
        sb    t5, 7(t6)                # r_tmp[7 + i] = new twist
        addi  t3, t3, 1
        li    t4, 7
        blt   t3, t4, r_q_loop
        li    t3, 0                    # copy r_tmp back
r_q_copy:
        add   t6, a5, t3
        lbu   t4, 0(t6)
        add   t5, a3, t3
        sb    t4, 0(t5)
        lbu   t4, 7(t6)
        add   t5, a4, t3
        sb    t4, 0(t5)
        addi  t3, t3, 1
        li    t4, 7
        blt   t3, t4, r_q_copy
        ret

# r_show: draw the 24 facelets of r_perm, r_twist, then wait.
# The facelet at seat s, sticker k shows sticker (k + twist[s]) mod 3 of
# the cubie at seat s. Pixel (x, y) is at BASE + (y * WIDTH + x) * 4; the
# row stride WIDTH * 4 is a shift, and y rows are added one at a time.
r_show:
        la    t0, facelets
        li    t1, 24
        li    a5, LED_MATRIX_0_WIDTH
        slli  a5, a5, 2             # (L4) row stride in bytes = WIDTH * 4
r_d_loop:
        lbu   t2, 0(t0)                # seat
        lbu   t3, 1(t0)                # sticker k
        li    t4, 0                    # seat 0 holds cubie 0, twist 0
        li    t5, 0
        beqz  t2, r_d_color
        la    t6, r_perm
        add   t6, t6, t2
        lbu   t4, -1(t6)               # seat s is r_perm[s - 1]
        addi  t4, t4, 1                # digits 0..6 name cubies 1..7
        la    t6, r_twist
        add   t6, t6, t2
        lbu   t5, -1(t6)
r_d_color:
        add   t3, t3, t5
        li    t6, 3
        blt   t3, t6, r_d_mod
        addi  t3, t3, -3             # (L2) (k + twist) mod 3
r_d_mod:
        slli  t6, t4, 1             # (L3) together with the next line:
        add   t6, t6, t4               #      cubie * 3
        add   t6, t6, t3
        la    a3, home
        add   a3, a3, t6
        lbu   a3, 0(a3)                # face colour index 0..5
        slli  a3, a3, 2
        la    a4, palette
        add   a4, a4, a3
        lw    a4, 0(a4)                # 0x00RRGGBB
        lbu   t2, 2(t0)                # x
        lbu   t3, 3(t0)                # y
        li    a6, LED_MATRIX_0_BASE
        slli  t2, t2, 2
        add   a6, a6, t2
r_d_row:
        beqz  t3, r_d_fill
        add   a6, a6, a5               # down one row
        addi  t3, t3, -1
        j     r_d_row
r_d_fill:
        li    t3, 3                 # (L5) a facelet is 4 wide, 3 tall: rows to fill
r_d_px:
        sw    a4, 0(a6)
        sw    a4, 4(a6)
        sw    a4, 8(a6)
        sw    a4, 12(a6)
        add   a6, a6, a5
        addi  t3, t3, -1
        bnez  t3, r_d_px
        addi  t0, t0, 4             # (L6) next facelet entry: how many bytes each?
        addi  t1, t1, -1               #.byte seat, k, x, y 4 byte
        bnez  t1, r_d_loop
        li    t0, DELAY                # keep the frame on screen
r_wait:
        addi  t0, t0, -1
        bnez  t0, r_wait
        ret
#@render-end


        .data
face_name:   .byte 82, 66, 68          # 'R', 'B', 'D'
turn_name:   .byte 0, 0, 50, 39        # by turn count: -, none, '2', '\''
        .align 2
frames:      .zero 192                 # 12 depths x 16 bytes


#@render-begin
        .data
# Facelets of the unfolded net: seat, sticker k at that seat (0 = the
# up/down sticker, then clockwise), and the top-left pixel (x, y).
# Face slot (column c, row r) starts at x = 9c, y = 7r; a facelet is
# 4 x 3 pixels. Derived from the sticker model checked against solver.c.
facelets:
        .byte 7, 0, 9, 0               # U
        .byte 4, 0, 13, 0
        .byte 0, 0, 9, 3
        .byte 1, 0, 13, 3
        .byte 7, 1, 0, 7               # L
        .byte 0, 2, 4, 7
        .byte 6, 2, 0, 10
        .byte 3, 1, 4, 10
        .byte 0, 1, 9, 7               # F
        .byte 1, 2, 13, 7
        .byte 3, 2, 9, 10
        .byte 2, 1, 13, 10
        .byte 1, 1, 18, 7              # R
        .byte 4, 2, 22, 7
        .byte 2, 2, 18, 10
        .byte 5, 1, 22, 10
        .byte 4, 1, 27, 7              # B
        .byte 7, 2, 31, 7
        .byte 5, 2, 27, 10
        .byte 6, 1, 31, 10
        .byte 3, 0, 9, 14              # D
        .byte 2, 0, 13, 14
        .byte 6, 0, 9, 17
        .byte 5, 0, 13, 17
# Colours of each cubie, sticker 0 (up/down colour) then clockwise,
# as indices into palette: 0 U, 1 D, 2 F, 3 B, 4 L, 5 R.
home:
        .byte 0, 2, 4                  # cubie 0
        .byte 0, 5, 2                  # cubie 1
        .byte 1, 2, 5                  # cubie 2
        .byte 1, 4, 2                  # cubie 3
        .byte 0, 3, 5                  # cubie 4
        .byte 1, 5, 3                  # cubie 5
        .byte 1, 3, 4                  # cubie 6
        .byte 0, 4, 3                  # cubie 7
# solver.c's source and twist, one row per face, padded to 8 bytes.
src_tab:
        .byte 1, 4, 2, 0, 3, 5, 6, 0   # R
        .byte 0, 1, 2, 4, 5, 6, 3, 0   # B
        .byte 0, 2, 5, 3, 1, 4, 6, 0   # D
tw_tab:
        .byte 1, 2, 0, 2, 1, 0, 0, 0   # R
        .byte 0, 0, 0, 1, 2, 1, 2, 0   # B
        .byte 0, 0, 0, 0, 0, 0, 0, 0   # D
r_perm:  .zero 7
r_twist: .zero 7
r_tmp:   .zero 14
        .align 2
palette:
        .word 0xFFFF00                 # U yellow
        .word 0xFFFFFF                 # D white
        .word 0x0050FF                 # F blue
        .word 0x00C000                 # B green
        .word 0xFF8000                 # L orange
        .word 0xFF0000                 # R red
#@render-end