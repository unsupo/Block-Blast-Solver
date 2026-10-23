#include "bitboard.h"

using namespace block_blast;

extern "C" {

struct CEngine {
    BitboardEngine engine;
};

CEngine* bb_create(uint64_t seed) {
    return new CEngine{BitboardEngine(seed)};
}

void bb_destroy(CEngine* ptr) {
    if (ptr) delete ptr;
}

void bb_reset(CEngine* ptr, uint64_t seed) {
    if (ptr) ptr->engine.reset(seed);
}

void bb_set_state(CEngine* ptr, uint64_t board, int d0, int d1, int d2, int combo, int score) {
    if (!ptr) return;
    ptr->engine.board = board;
    ptr->engine.dock[0] = d0;
    ptr->engine.dock[1] = d1;
    ptr->engine.dock[2] = d2;
    ptr->engine.combo = combo;
    ptr->engine.score = score;
    ptr->engine.checkTermination();
}

int bb_step(CEngine* ptr, int action) {
    if (!ptr) return 0;
    return ptr->engine.step(action);
}

void bb_get_action_mask(const CEngine* ptr, uint8_t* out_mask) {
    if (ptr) ptr->engine.getActionMask(out_mask);
}

void bb_get_observation(const CEngine* ptr, float* out_obs) {
    if (ptr) ptr->engine.getObservation(out_obs);
}

uint64_t bb_get_board(const CEngine* ptr) {
    return ptr ? ptr->engine.board : 0;
}

void bb_get_dock(const CEngine* ptr, int* out_dock) {
    if (ptr && out_dock) {
        out_dock[0] = ptr->engine.dock[0];
        out_dock[1] = ptr->engine.dock[1];
        out_dock[2] = ptr->engine.dock[2];
    }
}

int bb_get_score(const CEngine* ptr) {
    return ptr ? ptr->engine.score : 0;
}

int bb_get_combo(const CEngine* ptr) {
    return ptr ? ptr->engine.combo : 0;
}

int bb_get_lines_cleared(const CEngine* ptr) {
    return ptr ? ptr->engine.lines_cleared_total : 0;
}

int bb_get_moves(const CEngine* ptr) {
    return ptr ? ptr->engine.moves : 0;
}

int bb_is_terminated(const CEngine* ptr) {
    return ptr ? (ptr->engine.terminated ? 1 : 0) : 1;
}

int bb_get_best_action(const CEngine* ptr) {
    return ptr ? ptr->engine.getBestActionSearch() : -1;
}

uint64_t bb_simulate_placement(uint64_t b, int sid, int r, int c) {
    return BitboardEngine::simulatePlacement(b, sid, r, c);
}

float bb_evaluate_topology(uint64_t b, int combo) {
    return BitboardEngine::evaluateBoardTopology(b, combo);
}

}
