# Optimal 2x2x2 solver in RV32I. See build.sh for how this file becomes
# a Ripes source: the search tables are appended from gen_tables.c.

        .data
input:  .string "12345671111111"       # the state to solve
expected: .byte 11                     # optimal length; test.sh rewrites this
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
        addi  s3, s3, -1
        bnez  s3, c_turn
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

        .data
face_name:   .byte 82, 66, 68          # 'R', 'B', 'D'
turn_name:   .byte 0, 0, 50, 39        # by turn count: -, none, '2', '\''
        .align 2
frames:      .zero 192                 # 12 depths x 16 bytes
