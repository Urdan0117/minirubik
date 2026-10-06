# Write SIZE bytes of guest memory, one word at a time.

        .equ  BASE,  0x10000000         # 開始寫入的位址（Ripes 的資料區）
        .equ  SIZE,  0x40000          # (1) 要寫入幾個 byte

        .text
main:
        li    t0, BASE                  # t0 = 目前要寫的位址
        li    t1, SIZE
        add   t1, t0, t1           # t1 = 結束位址（寫到這裡就停）
        li    t2, 32                  # (2) 要寫進去的值
loop:
        sw    t2, 0(t0)                 # 把 t2 寫到位址 t0
        addi  t0, t0, 4              # (3) 位址往後移到下一個 word
        bltu  t0, t1, loop              # (4) 還沒到結尾就回到 loop
        li    a7, 10                  # (5) 結束程式的 ecall 編號
        ecall