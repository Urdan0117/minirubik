/* Host-side correctness gates H1-H4 for the IDA* solver in ida.c. */
#define IDA_NO_MAIN
#include "ida.c"
#include <time.h>

static uint8_t dist[STATES];

/* Exact distance of every state: layer-by-layer sweep, as in build_perm_pdb. */
static void build_distances(void)
{
    memset(dist, 0xFF, sizeof dist);
    dist[0] = 0;
    for (uint8_t d = 0;; ++d) {
        int changed = 0;
        for (uint32_t r = 0; r < STATES; ++r) {
            if (dist[r] != d)
                continue;
            for (uint8_t m = 0; m < 9; ++m) {
                uint16_t np, no;
                apply_move_rank(r / ORIENTATIONS, r % ORIENTATIONS, m, &np, &no);
                uint32_t q = (uint32_t) np * ORIENTATIONS + no;
                if (dist[q] == 0xFF) {
                    dist[q] = d + 1;
                    changed = 1;
                }
            }
        }
        if (!changed)
            break;
    }
}

int main(void)
{
    clock_t start = clock();
    build_transitions();
    build_perm_pdb();
    build_orient_pdb();
    build_distances();

    /* H2: every table fully populated, solved entry and maximum verified. */
    uint8_t pmax = 0;
    for (uint16_t r = 0; r < PERMUTATIONS; ++r) {
        if (perm_pdb[r] == 0xFF) { printf("H2 FAIL: perm_pdb[%u] unset\n", r); return 1; }
        if (perm_pdb[r] > pmax) pmax = perm_pdb[r];
    }
    uint8_t omax = 0;
    for (uint16_t r = 0; r < ORIENTATIONS; ++r) {
        if (orient_pdb[r] == 0xFF) { printf("H2 FAIL: orient_pdb[%u] unset\n", r); return 1; }
        if (orient_pdb[r] > omax) omax = orient_pdb[r];
    }
    uint8_t dmax = 0;
    for (uint32_t r = 0; r < STATES; ++r) {
        if (dist[r] == 0xFF) { printf("H2 FAIL: dist[%u] unset\n", r); return 1; }
        if (dist[r] > dmax) dmax = dist[r];
    }
    printf("H2 pass: perm_pdb[0] = %u, max %u; orient_pdb[0] = %u, max %u; exact distances max %u\n",
           perm_pdb[0], pmax, orient_pdb[0], omax, dmax);

    /* H1: admissibility over every state. */
    for (uint32_t r = 0; r < STATES; ++r) {
        uint16_t p = r / ORIENTATIONS, o = r % ORIENTATIONS;
        if (h(p, o) > dist[r]) {                                           /* (10) */
            printf("H1 FAIL at rank %u: h = %u, d = %u\n", r, h(p, o), dist[r]);
            return 1;
        }
    }
    printf("H1 pass: h(s) <= d(s) for all %u states\n", (unsigned) STATES);

    /* H3: optimal length for every state, and every path really solves it. */
    unsigned long long worst = 0, sum11 = 0;
    uint32_t worst_rank = 0, count11 = 0;
    for (uint32_t r = 0; r < STATES; ++r) {
	uint16_t p = r / ORIENTATIONS, o = r % ORIENTATIONS;
        uint8_t moves[11];
        nodes = 0;
        int n = ida_star(p, o, moves);
        if (n != dist[r]) {                                           /* (11) */
            printf("H3 FAIL at rank %u: length %d, exact %u\n", r, n, dist[r]);
            return 1;
        }
        for (int i = 0; i < n; ++i)
            apply_move_rank(p, o, moves[i], &p, &o);
        if (p != 0 || o != 0) {                                           /* (12) */
            printf("H3 FAIL at rank %u: path does not reach solved\n", r);
            return 1;
        }
        if (dist[r] == 11) {
            ++count11;
            sum11 += nodes;
            if (nodes > worst) { worst = nodes; worst_rank = r; }
        }
    }
    printf("H3 pass: optimal length and valid path for all %u states\n", (unsigned) STATES);
    printf("distance-11 states: %u, nodes avg %.0f, worst %llu (rank %u)\n",
           count11, (double) sum11 / count11, worst, worst_rank);
    printf("H4: not applicable (no packed table yet)\n");
    printf("wall clock %.1f s\n", (double) (clock() - start) / CLOCKS_PER_SEC);
    return 0;
}
