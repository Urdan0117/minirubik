/* Host-side gates H1-H3 for C v2, the gcc reference build ida_rv32.c.
 *
 * verify_v2.sh turns ida_rv32.c into build/v2_host.c with five mechanical
 * edits that leave the search untouched: the input and the expected length
 * become writable, put_char records characters instead of issuing an
 * ecall, the empty asm barrier is dropped, main is renamed v2_main, and
 * the RISC-V entry point _start is removed.
 *
 * The reference answers come from an independent model: the transition
 * tables are rebuilt from solver.c's quarter_turn, and a BFS over them
 * gives the exact distance of every state. Every path v2 prints is then
 * replayed with solver.c's apply_move, not with v2's own tables.
 */
#define main solver_main
#include "solver.c"
#undef main
#include "build/v2_host.c"
#include <time.h>

static uint16_t ref_perm[3][PERMUTATIONS], ref_orient[3][ORIENTATIONS];
static uint8_t dist[STATES];

static void build_reference(void)
{
    state_t s;
    for (uint32_t r = 0; r < PERMUTATIONS; ++r) {
        unrank_state(r * ORIENTATIONS, &s);
        for (uint8_t f = 0; f < 3; ++f) {
            state_t n = quarter_turn(s, f);
            ref_perm[f][r] = (uint16_t) (rank_state(&n) / ORIENTATIONS);
        }
    }
    for (uint32_t r = 0; r < ORIENTATIONS; ++r) {
        unrank_state(r, &s);
        for (uint8_t f = 0; f < 3; ++f) {
            state_t n = quarter_turn(s, f);
            ref_orient[f][r] = (uint16_t) (rank_state(&n) % ORIENTATIONS);
        }
    }
    uint32_t *queue = malloc((size_t) STATES * sizeof *queue);
    uint32_t head = 0, tail = 1;
    memset(dist, 0xFF, sizeof dist);
    dist[0] = 0;
    queue[0] = 0;
    while (head < tail) {
        uint32_t r = queue[head++];
        for (uint8_t f = 0; f < 3; ++f) {
            uint16_t p = r / ORIENTATIONS, o = r % ORIENTATIONS;
            for (uint8_t t = 0; t < 3; ++t) {
                p = ref_perm[f][p];
                o = ref_orient[f][o];
                uint32_t q = (uint32_t) p * ORIENTATIONS + o;
                if (dist[q] == 0xFF) {
                    dist[q] = dist[r] + 1;
                    queue[tail++] = q;
                }
            }
        }
    }
    free(queue);
}

/* Apply v2's printed solution with solver.c's model; 1 if it solves s. */
static int replay_solves(state_t s, const char *text, int n)
{
    for (int i = 0; i < n; ++i) {
        if (text[i] == ' ' || text[i] == '\n')
            continue;
        uint8_t face = text[i] == 'R' ? 0 : text[i] == 'B' ? 1 : 2;
        uint8_t turn = 0;
        if (i + 1 < n && text[i + 1] == '2')
            turn = 1, ++i;
        else if (i + 1 < n && text[i + 1] == '\'')
            turn = 2, ++i;
        s = apply_move(s, (uint8_t) (face * 3 + turn));
    }
    return rank_state(&s) == 0;
}

int main(int argc, char **argv)
{
    uint32_t stride = argc > 1 ? (uint32_t) atoi(argv[1]) : 1;
    clock_t start = clock();
    build_reference();

    /* H2: v2's pattern databases are fully populated. */
    unsigned pmax = 0, omax = 0;
    for (int r = 0; r < PERMUTATIONS; ++r) {
        if (perm_pdb[r] == 0xFF) { printf("H2 FAIL: perm_pdb[%d]\n", r); return 1; }
        if (perm_pdb[r] > pmax) pmax = perm_pdb[r];
    }
    for (int r = 0; r < ORIENTATIONS; ++r) {
        if (orient_pdb[r] == 0xFF) { printf("H2 FAIL: orient_pdb[%d]\n", r); return 1; }
        if (orient_pdb[r] > omax) omax = orient_pdb[r];
    }
    printf("H2 pass: perm_pdb[0] = %u, max %u; orient_pdb[0] = %u, max %u\n",
           perm_pdb[0], pmax, orient_pdb[0], omax);

    /* H1: v2's heuristic never overestimates. */
    for (uint32_t r = 0; r < STATES; ++r)
        if (h(r / ORIENTATIONS, r % ORIENTATIONS) > dist[r]) {
            printf("H1 FAIL at rank %u\n", r);
            return 1;
        }
    printf("H1 pass: h(s) <= d(s) for all %u states\n", (unsigned) STATES);

    /* H3: run ida_rv32.c's own main on every state. */
    uint32_t checked = 0;
    for (uint32_t r = 0; r < STATES; r += stride) {
        state_t s;
        unrank_state(r, &s);
        for (int i = 0; i < 7; ++i) {
            input[i] = (char) ('1' + s.p[i]);
            input[7 + i] = (char) ('1' + s.o[i]);
        }
        input[14] = '\0';
        expected = dist[r];
        outn = 0;
        int status = v2_main();
        if (status != 0) {
            printf("H3 FAIL at rank %u (%.14s): v2 exit status %d\n", r, input, status);
            return 1;
        }
        if (!replay_solves(s, out, outn)) {
            printf("H3 FAIL at rank %u (%.14s): path does not solve it\n", r, input);
            return 1;
        }
        ++checked;
    }
    printf("H3 pass: ida_rv32.c returns the exact distance and a solving path for %u states%s\n",
           checked, stride == 1 ? " (all)" : " (sampled)");
    printf("CPU time %.1f s\n", (double) (clock() - start) / CLOCKS_PER_SEC);
    return 0;
}
