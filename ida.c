/* IDA* solver for the 2x2x2 cube, host version for stage 3. */
#define main solver_main
#include "solver.c"
#undef main

static uint16_t perm_move[3][PERMUTATIONS], orient_move[3][ORIENTATIONS];
static uint8_t perm_pdb[PERMUTATIONS];
static uint8_t orient_pdb[ORIENTATIONS];
static unsigned long long nodes;

/* Factored quarter-turn tables, built the same way as in build_table. */
static void build_transitions(void)
{
    state_t state;
    for (uint16_t rank = 0; rank < PERMUTATIONS; ++rank) {
        unrank_state((uint32_t) rank * ORIENTATIONS, &state);
        for (uint8_t face = 0; face < 3; ++face) {
            state_t next = quarter_turn(state, face);
            perm_move[face][rank] = (uint16_t) (rank_state(&next) / ORIENTATIONS);
        }
    }
    for (uint16_t rank = 0; rank < ORIENTATIONS; ++rank) {
        unrank_state(rank, &state);
        for (uint8_t face = 0; face < 3; ++face) {
            state_t next = quarter_turn(state, face);
            orient_move[face][rank] = (uint16_t) (rank_state(&next) % ORIENTATIONS);
        }
    }
}

/* Apply move m (0..8) to the rank pair (p, o). */
static void apply_move_rank(uint16_t p, uint16_t o, uint8_t m,
                            uint16_t *np, uint16_t *no)
{
    uint8_t face = m / 3, turns = m % 3 + 1;
    for (uint8_t t = 0; t < turns; ++t) {
        p = perm_move[face][p];
        o = orient_move[face][o];
    }
    *np = p;
    *no = o;
}

/* Permutation pattern database: BFS over the 5,040 permutations only. */
static void build_perm_pdb(void)
{
    memset(perm_pdb, 0xFF, sizeof perm_pdb);
    perm_pdb[0] = 0;                              /* (7) */
    for (uint8_t d = 0;; ++d) {
        int changed = 0;
        for (uint16_t r = 0; r < PERMUTATIONS; ++r) {
            if (perm_pdb[r] != d)                 /* (8) */
                continue;
            for (uint8_t f = 0; f < 3; ++f) {
                uint16_t x = r;
                for (uint8_t t = 0; t < 3; ++t) {
                    x = perm_move[f][x];
                    if (perm_pdb[x] == 0xFF) {
                        perm_pdb[x] = d+1 ;          /* (9) */
                        changed = 1;
                    }
                }
            }
        }
        if (!changed)
            break;
    }
}
static void build_orient_pdb(void)
{
    memset(orient_pdb, 0xFF, sizeof orient_pdb);
    orient_pdb[0] = 0;                              /* (7) */
    for (uint8_t d = 0;; ++d) {
        int changed = 0;
        for (uint16_t r = 0; r < ORIENTATIONS; ++r) {
            if (orient_pdb[r] != d)                 /* (8) */
                continue;
            for (uint8_t f = 0; f < 3; ++f) {
                uint16_t x = r;
                for (uint8_t t = 0; t < 3; ++t) {
                    x = orient_move[f][x];
                    if (orient_pdb[x] == 0xFF) {
                        orient_pdb[x] = d+1 ;          /* (9) */
                        changed = 1;
                    }
                }
            }
        }
        if (!changed)
            break;
    }
}
static uint8_t h(uint16_t p, uint16_t o)
{
    uint8_t hp = perm_pdb[p], ho = orient_pdb[o];
    return hp>ho?hp:ho;
}

static int ida_star(uint16_t p0, uint16_t o0, uint8_t moves[11])
{
    uint16_t ps[12], os[12];
    uint8_t next[12];

    for (int bound = h(p0, o0); bound <= 11; ++bound) {
        int depth = 0;
        ps[0] = p0;
        os[0] = o0;
        next[0] = 0;

        while (depth >= 0) {
            if (ps[depth] == 0 && os[depth] == 0)
                return depth;
            if (next[depth] > 8) {
                --depth;
                continue;
            }
            uint8_t m = next[depth]++;
            uint8_t face = m / 3;
            if (depth > 0 && face == moves[depth - 1] / 3)
                continue;

            uint16_t np, no;
            apply_move_rank(ps[depth], os[depth], m, &np, &no);
            if (depth + 1 + h(np, no) > bound)
                continue;

            moves[depth] = m;
            ++depth;
            ps[depth] = np;
            os[depth] = no;
            next[depth] = 0;
            ++nodes;
        }
    }
    return -1;
}

#ifndef IDA_NO_MAIN
int main(int argc, char **argv)
{
    state_t s;
    if (argc != 2 || !parse_state(argv[1], &s)) {
        fprintf(stderr, "usage: %s PPPPPPPOOOOOOO\n", argv[0]);
        return 2;
    }
    build_transitions();
    build_perm_pdb();
    build_orient_pdb();

    uint32_t r = rank_state(&s);
    uint8_t moves[11];
    int n = ida_star((uint16_t) (r / ORIENTATIONS), (uint16_t) (r % ORIENTATIONS), moves);
    for (int i = 0; i < n; ++i)
        printf("%s%s", i ? " " : "", move_names[moves[i]]);
    putchar('\n');
    fprintf(stderr, "length %d, nodes %llu\n", n, nodes);
    return n < 0;
}
#endif
