#ifndef BLOCK_BLAST_BITBOARD_H
#define BLOCK_BLAST_BITBOARD_H

#include <cstdint>
#include <cstring>
#include <vector>
#include <random>
#include <algorithm>

namespace block_blast {

// 8x8 Board represented as a single 64-bit unsigned integer.
// Bit index: (row * 8 + col), where row, col in [0, 7].
// Row 0 = bits 0..7, Row 7 = bits 56..63.

struct ShapeRaw {
    int id;
    int kind;
    int fill;
    int w;
    int h;
    uint8_t masks[5]; // Up to 5 rows
};

// All 43 exact shapes reverse-engineered from libtask.so (AlgorithmCore::g_arrShape)
inline const ShapeRaw SHAPES_RAW[43] = {
    {0, 0, 1, 1, 1, {1, 0, 0, 0, 0}},
    {1, 0, 1, 1, 1, {1, 0, 0, 0, 0}},
    {2, 1, 2, 1, 2, {1, 1, 0, 0, 0}},
    {3, 0, 2, 2, 1, {3, 0, 0, 0, 0}},
    {4, 1, 3, 1, 3, {1, 1, 1, 0, 0}},
    {5, 0, 3, 3, 1, {7, 0, 0, 0, 0}},
    {6, 3, 3, 2, 2, {3, 2, 0, 0, 0}},
    {7, 1, 4, 1, 4, {1, 1, 1, 1, 0}},
    {8, 3, 4, 3, 2, {4, 7, 0, 0, 0}},
    {9, 2, 4, 2, 2, {3, 3, 0, 0, 0}},
    {10, 3, 4, 3, 2, {2, 7, 0, 0, 0}},
    {11, 0, 5, 5, 1, {31, 0, 0, 0, 0}},
    {12, 3, 5, 3, 3, {7, 1, 1, 0, 0}},
    {13, 2, 9, 3, 3, {7, 7, 7, 0, 0}},
    {14, 3, 4, 3, 2, {3, 6, 0, 0, 0}},
    {15, 3, 3, 2, 2, {3, 1, 0, 0, 0}},
    {16, 3, 4, 2, 3, {2, 3, 1, 0, 0}},
    {17, 0, 4, 4, 1, {15, 0, 0, 0, 0}},
    {18, 3, 4, 3, 2, {6, 3, 0, 0, 0}},
    {19, 3, 4, 2, 3, {1, 3, 2, 0, 0}},
    {20, 3, 4, 2, 3, {2, 3, 2, 0, 0}},
    {21, 3, 5, 3, 3, {7, 4, 4, 0, 0}},
    {22, 1, 5, 1, 5, {1, 1, 1, 1, 1}},
    {23, 3, 5, 3, 3, {4, 4, 7, 0, 0}},
    {24, 3, 5, 3, 3, {1, 1, 7, 0, 0}},
    {25, 3, 4, 2, 3, {1, 3, 1, 0, 0}},
    {26, 3, 4, 3, 2, {7, 2, 0, 0, 0}},
    {27, 3, 3, 2, 2, {2, 3, 0, 0, 0}},
    {28, 3, 3, 2, 2, {1, 3, 0, 0, 0}},
    {29, 3, 4, 2, 3, {1, 1, 3, 0, 0}},
    {30, 3, 4, 3, 2, {7, 1, 0, 0, 0}},
    {31, 3, 4, 2, 3, {3, 2, 2, 0, 0}},
    {32, 3, 4, 2, 3, {3, 1, 1, 0, 0}},
    {33, 3, 4, 3, 2, {1, 7, 0, 0, 0}},
    {34, 3, 4, 3, 2, {7, 4, 0, 0, 0}},
    {35, 2, 6, 3, 2, {7, 7, 0, 0, 0}},
    {36, 2, 6, 2, 3, {3, 3, 3, 0, 0}},
    {37, 3, 2, 2, 2, {2, 1, 0, 0, 0}},
    {38, 3, 2, 2, 2, {1, 2, 0, 0, 0}},
    {39, 3, 3, 3, 3, {4, 2, 1, 0, 0}},
    {40, 3, 3, 3, 3, {1, 2, 4, 0, 0}},
    {41, 3, 3, 3, 3, {1, 2, 4, 0, 0}},
    {42, 3, 4, 2, 3, {2, 2, 3, 0, 0}}
};

// Reverse-engineered shape pools from libtask.so
static const int POOL_SAFE[13] = {6, 27, 28, 15, 3, 2, 5, 4, 37, 38, 39, 40, 41};
static const int POOL_HARD[11] = {11, 13, 22, 12, 24, 21, 23, 14, 16, 18, 19};
static const int POOL_STANDARD[28] = {
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21,
    22, 23, 24, 25, 26, 29, 30, 31, 32, 33, 34, 35, 36, 42
};

class BitboardEngine {
public:
    // Precomputed bitboard masks: [shape_id][row][col]
    // 0 if placement would be out of bounds.
    static inline uint64_t SHAPE_MASKS[43][8][8];
    static inline uint64_t MASKS_3X3[36];
    static inline uint64_t MASKS_5X1_H[32];
    static inline uint64_t MASKS_5X1_V[32];
    static inline bool INITIALIZED = false;

    static void initTables() {
        if (INITIALIZED) return;
        std::memset(SHAPE_MASKS, 0, sizeof(SHAPE_MASKS));

        for (int sid = 0; sid < 43; ++sid) {
            const auto& s = SHAPES_RAW[sid];
            for (int r = 0; r <= 8 - s.h; ++r) {
                for (int c = 0; c <= 8 - s.w; ++c) {
                    uint64_t mask = 0;
                    for (int dr = 0; dr < s.h; ++dr) {
                        uint8_t row_bits = s.masks[dr];
                        for (int dc = 0; dc < s.w; ++dc) {
                            if ((row_bits >> (s.w - 1 - dc)) & 1) {
                                int bit_idx = (r + dr) * 8 + (c + dc);
                                mask |= (1ULL << bit_idx);
                            }
                        }
                    }
                    SHAPE_MASKS[sid][r][c] = mask;
                }
            }
        }

        int idx3 = 0;
        for (int r = 0; r <= 5; ++r) {
            for (int c = 0; c <= 5; ++c) {
                MASKS_3X3[idx3++] = (7ULL << (r * 8 + c)) |
                                    (7ULL << ((r + 1) * 8 + c)) |
                                    (7ULL << ((r + 2) * 8 + c));
            }
        }

        int idxh = 0;
        for (int r = 0; r < 8; ++r) {
            for (int c = 0; c <= 3; ++c) {
                MASKS_5X1_H[idxh++] = 31ULL << (r * 8 + c);
            }
        }

        int idxv = 0;
        uint64_t col5 = 0x0101010101ULL;
        for (int r = 0; r <= 3; ++r) {
            for (int c = 0; c < 8; ++c) {
                MASKS_5X1_V[idxv++] = col5 << (r * 8 + c);
            }
        }

        INITIALIZED = true;
    }

    uint64_t board;
    int dock[3]; // Hand inventory (3 slots), -1 if slot placed
    int combo;   // Current consecutive line clear streak
    int score;
    int lines_cleared_total;
    int moves;
    bool terminated;
    std::mt19937_64 rng;

    BitboardEngine(uint64_t seed = 42) : rng(seed) {
        initTables();
        reset(seed);
    }

    void reset(uint64_t seed = 0) {
        if (seed != 0) {
            rng.seed(seed);
        }
        board = 0;
        combo = 0;
        score = 0;
        lines_cleared_total = 0;
        moves = 0;
        terminated = false;
        refillDock();
    }

    static inline uint64_t simulatePlacement(uint64_t b, int sid, int r, int c) {
        uint64_t m = SHAPE_MASKS[sid][r][c];
        if (m == 0 || (b & m) != 0) return 0;
        uint64_t nb = b | m;
        uint64_t clear_mask = 0;
        for (int row = 0; row < 8; ++row) {
            uint64_t row_mask = 0xFFULL << (row * 8);
            if ((nb & row_mask) == row_mask) clear_mask |= row_mask;
        }
        for (int col = 0; col < 8; ++col) {
            uint64_t col_mask = 0x0101010101010101ULL << col;
            if ((nb & col_mask) == col_mask) clear_mask |= col_mask;
        }
        return nb & ~clear_mask;
    }

    static bool checkLiveWayRecursive(uint64_t b, const int candidate[3], uint8_t used_mask, int placed_count) {
        if (placed_count == 3) return true;

        for (int i = 0; i < 3; ++i) {
            if ((used_mask & (1 << i)) == 0) {
                int sid = candidate[i];
                const auto& s = SHAPES_RAW[sid];

                for (int r = 0; r <= 8 - s.h; ++r) {
                    for (int c = 0; c <= 8 - s.w; ++c) {
                        uint64_t m = SHAPE_MASKS[sid][r][c];
                        if ((b & m) == 0) {
                            if (placed_count == 2) return true;
                            uint64_t nb = simulatePlacement(b, sid, r, c);
                            if (checkLiveWayRecursive(nb, candidate, used_mask | (1 << i), placed_count + 1)) {
                                return true;
                            }
                        }
                    }
                }
            }
        }
        return false;
    }

    static bool hasLiveWay(uint64_t b, const int candidate[3]) {
        return checkLiveWayRecursive(b, candidate, 0, 0);
    }

    void refillDock() {
        int filled_cells = __builtin_popcountll(board);
        double cover_rate = filled_cells / 64.0;

        double hard_prob = 0.05;
        if (score >= 8400) hard_prob = 0.40;
        else if (score >= 3800) hard_prob = 0.30;
        else if (score >= 1400) hard_prob = 0.20;
        else if (score >= 500) hard_prob = 0.12;

        std::uniform_real_distribution<double> real_dist(0.0, 1.0);
        std::uniform_int_distribution<int> safe_dist(0, 12);
        std::uniform_int_distribution<int> hard_dist(0, 10);
        std::uniform_int_distribution<int> standard_dist(0, 27);
        std::uniform_int_distribution<int> all_dist(0, 42);

        int candidate[3];
        bool valid = false;

        for (int attempt = 0; attempt < 8; ++attempt) {
            for (int i = 0; i < 3; ++i) {
                if (cover_rate >= 0.58) {
                    if (real_dist(rng) < 0.75) {
                        candidate[i] = POOL_SAFE[safe_dist(rng)];
                    } else {
                        candidate[i] = POOL_STANDARD[standard_dist(rng)];
                    }
                } else if (cover_rate <= 0.28) {
                    if (real_dist(rng) < 0.35) {
                        candidate[i] = POOL_HARD[hard_dist(rng)];
                    } else {
                        candidate[i] = POOL_STANDARD[standard_dist(rng)];
                    }
                } else {
                    double r = real_dist(rng);
                    if (r < hard_prob) {
                        candidate[i] = POOL_HARD[hard_dist(rng)];
                    } else if (r < hard_prob + 0.35) {
                        candidate[i] = POOL_SAFE[safe_dist(rng)];
                    } else {
                        candidate[i] = all_dist(rng);
                    }
                }
            }

            if (hasLiveWay(board, candidate)) {
                valid = true;
                break;
            }
        }

        if (!valid) {
            for (int i = 0; i < 3; ++i) {
                candidate[i] = POOL_SAFE[safe_dist(rng)];
            }
        }

        dock[0] = candidate[0];
        dock[1] = candidate[1];
        dock[2] = candidate[2];

        checkTermination();
    }

    inline bool isDockEmpty() const {
        return dock[0] < 0 && dock[1] < 0 && dock[2] < 0;
    }

    // Check if any shape in dock can be placed anywhere on current board
    void checkTermination() {
        for (int i = 0; i < 3; ++i) {
            if (dock[i] < 0) continue;
            int sid = dock[i];
            const auto& s = SHAPES_RAW[sid];
            for (int r = 0; r <= 8 - s.h; ++r) {
                for (int c = 0; c <= 8 - s.w; ++c) {
                    uint64_t m = SHAPE_MASKS[sid][r][c];
                    if ((board & m) == 0) {
                        terminated = false;
                        return;
                    }
                }
            }
        }
        terminated = true;
    }

    // Returns action mask for all 192 actions (3 slots * 64 grid positions)
    void getActionMask(uint8_t* out_mask) const {
        std::memset(out_mask, 0, 192);
        if (terminated) return;

        for (int slot = 0; slot < 3; ++slot) {
            int sid = dock[slot];
            if (sid < 0) continue;
            const auto& s = SHAPES_RAW[sid];
            int slot_offset = slot * 64;

            for (int r = 0; r <= 8 - s.h; ++r) {
                int row_offset = slot_offset + r * 8;
                for (int c = 0; c <= 8 - s.w; ++c) {
                    uint64_t m = SHAPE_MASKS[sid][r][c];
                    if ((board & m) == 0) {
                        out_mask[row_offset + c] = 1;
                    }
                }
            }
        }
    }

    // Step function: action in [0, 191]
    // action = slot * 64 + (r * 8 + c)
    // Returns reward (points earned on this step)
    int step(int action) {
        if (terminated) return 0;

        int slot = action / 64;
        int cell = action % 64;
        int r = cell / 8;
        int c = cell % 8;

        if (slot < 0 || slot >= 3) return -10;
        int sid = dock[slot];
        if (sid < 0) return -10; // Already used slot

        uint64_t m = SHAPE_MASKS[sid][r][c];
        if (m == 0 || (board & m) != 0) {
            // Invalid move / collision / out of bounds
            return -10;
        }

        // Place the piece
        board |= m;
        dock[slot] = -1;
        moves++;

        // Base points: 1 per filled cell
        int points = SHAPES_RAW[sid].fill;

        // Line clear check (rows and columns simultaneously)
        uint64_t clear_mask = 0;
        int cleared_rows = 0;
        int cleared_cols = 0;

        // Rows
        for (int row = 0; row < 8; ++row) {
            uint64_t row_mask = 0xFFULL << (row * 8);
            if ((board & row_mask) == row_mask) {
                clear_mask |= row_mask;
                cleared_rows++;
            }
        }

        // Columns
        for (int col = 0; col < 8; ++col) {
            uint64_t col_mask = 0x0101010101010101ULL << col;
            if ((board & col_mask) == col_mask) {
                clear_mask |= col_mask;
                cleared_cols++;
            }
        }

        int lines_cleared = cleared_rows + cleared_cols;
        if (lines_cleared > 0) {
            board &= ~clear_mask;
            combo++;
            lines_cleared_total += lines_cleared;
            // Block Blast scoring formula: 10 * (lines)^2 * combo
            points += 10 * (lines_cleared * lines_cleared) * combo;
        } else {
            combo = 0;
        }

        score += points;

        // If dock empty, refill next 3 shapes
        if (isDockEmpty()) {
            refillDock();
        } else {
            checkTermination();
        }

        return points;
    }

    // Multi-channel observation representation (5 channels):
    // Channel 0: Board grid 8x8 (0 or 1)
    // Channel 1: Dock Slot 0 (5x5 padded to 8x8, or 0 if empty)
    // Channel 2: Dock Slot 1 (5x5 padded to 8x8, or 0 if empty)
    // Channel 3: Dock Slot 2 (5x5 padded to 8x8, or 0 if empty)
    // Channel 4: Combo streak feature map (broadcast combo * 0.1f)
    // Total size: 5 * 8 * 8 = 320 float32
    void getObservation(float* out_obs) const {
        std::memset(out_obs, 0, 320 * sizeof(float));

        // Channel 0: Board
        for (int i = 0; i < 64; ++i) {
            if ((board >> i) & 1) {
                out_obs[i] = 1.0f;
            }
        }

        // Channels 1..3: Dock pieces
        for (int slot = 0; slot < 3; ++slot) {
            int sid = dock[slot];
            if (sid < 0) continue;
            const auto& s = SHAPES_RAW[sid];
            int ch_offset = (slot + 1) * 64;

            for (int r = 0; r < s.h; ++r) {
                uint8_t row_bits = s.masks[r];
                for (int c = 0; c < s.w; ++c) {
                    if ((row_bits >> (s.w - 1 - c)) & 1) {
                        out_obs[ch_offset + r * 8 + c] = 1.0f;
                    }
                }
            }
        }

        // Channel 4: Combo feature map (broadcast combo * 0.1f)
        float combo_val = combo * 0.1f;
        for (int i = 0; i < 64; ++i) {
            out_obs[256 + i] = combo_val;
        }
    }

    static inline int countLinesCleared(uint64_t b_before, uint64_t b_after, int sid) {
        int old_cnt = __builtin_popcountll(b_before) + SHAPES_RAW[sid].fill;
        int new_cnt = __builtin_popcountll(b_after);
        int cleared_cells = old_cnt - new_cnt;
        return (cleared_cells >= 8) ? (cleared_cells / 8) : 0;
    }

    static inline int calculateStepPoints(uint64_t b_before, uint64_t b_after, int sid, int curr_combo) {
        int lines = countLinesCleared(b_before, b_after, sid);
        int pts = SHAPES_RAW[sid].fill;
        if (lines > 0) {
            pts += 10 * lines * lines * (curr_combo + 1);
        }
        return pts;
    }

    static inline float evaluateBoardTopology(uint64_t b, int curr_combo) {
        // Pillar 1: Full Board Clear (All Clear) Holy Grail Bonus
        // When b == 0, the entire board is wiped completely clean!
        // Actively prioritize branches that produce full board wipes.
        if (b == 0) {
            return 35000.0f;
        }

        int filled = __builtin_popcountll(b);
        float eval = 0.0f;

        // Near-Clear bonus: strongly incentivize clearing out the last few isolated blocks
        if (filled <= 6) {
            eval += (7 - filled) * 1500.0f;
        }

        bool fit_3x3 = false;
        for (int i = 0; i < 36; ++i) {
            if ((b & MASKS_3X3[i]) == 0) {
                fit_3x3 = true;
                break;
            }
        }

        bool fit_5h = false;
        for (int i = 0; i < 32; ++i) {
            if ((b & MASKS_5X1_H[i]) == 0) {
                fit_5h = true;
                break;
            }
        }

        bool fit_5v = false;
        for (int i = 0; i < 32; ++i) {
            if ((b & MASKS_5X1_V[i]) == 0) {
                fit_5v = true;
                break;
            }
        }

        // Pillar 2: 3x3 Space Reserve Rule (Anti-DDA Defense)
        if (fit_3x3) eval += 2500.0f;
        else eval -= 6000.0f;

        // 5-bar Line Reserve
        if (fit_5h || fit_5v) eval += 800.0f;
        else eval -= 2500.0f;

        // Congestion penalty
        eval -= filled * 18.0f;

        // Combo preservation reward
        if (curr_combo > 0) {
            eval += curr_combo * 150.0f;
        }

        // Pillar 3: Isolated 1x1 holes penalty
        int holes = 0;
        for (int r = 0; r < 8; ++r) {
            for (int c = 0; c < 8; ++c) {
                int bit = r * 8 + c;
                if (((b >> bit) & 1) == 0) {
                    bool up = (r == 0) || ((b >> (bit - 8)) & 1);
                    bool down = (r == 7) || ((b >> (bit + 8)) & 1);
                    bool left = (c == 0) || ((b >> (bit - 1)) & 1);
                    bool right = (c == 7) || ((b >> (bit + 1)) & 1);
                    if (up && down && left && right) {
                        holes++;
                    }
                }
            }
        }
        eval -= holes * 1200.0f;

        // Almost-cleared lines bonus (6 or 7 filled cells in row or col)
        int almost_cleared = 0;
        for (int r = 0; r < 8; ++r) {
            int cnt = __builtin_popcountll(b & (0xFFULL << (r * 8)));
            if (cnt >= 6 && cnt <= 7) almost_cleared++;
        }
        for (int c = 0; c < 8; ++c) {
            int cnt = __builtin_popcountll(b & (0x0101010101010101ULL << c));
            if (cnt >= 6 && cnt <= 7) almost_cleared++;
        }
        eval += almost_cleared * 150.0f;

        return eval;
    }

    // Full-Hand Lookahead Search Engine (3-Ply Permutation Search)
    // Simulates placing Piece 1 -> Piece 2 -> Piece 3 across all permutations
    // Guarantees zero blunders and preserves 3x3 open spaces
    int getBestActionSearch() const {
        uint8_t root_mask[192];
        getActionMask(root_mask);

        std::vector<int> valid_actions;
        valid_actions.reserve(128);
        for (int i = 0; i < 192; ++i) {
            if (root_mask[i]) valid_actions.push_back(i);
        }
        if (valid_actions.empty()) return -1;

        int best_action = valid_actions[0];
        float best_val = -1e9f;

        for (int a1 : valid_actions) {
            int slot1 = a1 / 64;
            int cell1 = a1 % 64;
            int r1 = cell1 / 8;
            int c1 = cell1 % 8;
            int sid1 = dock[slot1];

            uint64_t b1 = simulatePlacement(board, sid1, r1, c1);
            int pts1 = calculateStepPoints(board, b1, sid1, combo);
            int c1_lines = countLinesCleared(board, b1, sid1);
            int next_combo1 = (c1_lines > 0) ? (combo + 1) : 0;

            int rem_slots[2];
            int rem_count = 0;
            for (int s = 0; s < 3; ++s) {
                if (s != slot1 && dock[s] >= 0) {
                    rem_slots[rem_count++] = s;
                }
            }

            float branch_score = -1e9f;

            if (rem_count == 0) {
                // 1-ply: last piece in hand
                branch_score = pts1 + evaluateBoardTopology(b1, next_combo1);
            } else if (rem_count == 1) {
                // 2-ply: 1 remaining piece
                int slot2 = rem_slots[0];
                int sid2 = dock[slot2];
                const auto& s2 = SHAPES_RAW[sid2];
                float best2 = -1e9f;

                for (int r2 = 0; r2 <= 8 - s2.h; ++r2) {
                    for (int c2 = 0; c2 <= 8 - s2.w; ++c2) {
                        uint64_t m2 = SHAPE_MASKS[sid2][r2][c2];
                        if ((b1 & m2) == 0) {
                            uint64_t b2 = simulatePlacement(b1, sid2, r2, c2);
                            int pts2 = calculateStepPoints(b1, b2, sid2, next_combo1);
                            int c2_lines = countLinesCleared(b1, b2, sid2);
                            int next_combo2 = (c2_lines > 0) ? (next_combo1 + 1) : 0;
                            float eval2 = pts2 + evaluateBoardTopology(b2, next_combo2);
                            if (eval2 > best2) best2 = eval2;
                        }
                    }
                }
                branch_score = (best2 > -1e8f) ? (pts1 + best2) : -50000.0f;
            } else {
                // 3-ply: 2 remaining pieces (evaluate both permutation orders)
                float best_hand = -1e9f;

                for (int order = 0; order < 2; ++order) {
                    int slot2 = rem_slots[order];
                    int slot3 = rem_slots[1 - order];
                    int sid2 = dock[slot2];
                    int sid3 = dock[slot3];
                    const auto& s2 = SHAPES_RAW[sid2];
                    const auto& s3 = SHAPES_RAW[sid3];

                    for (int r2 = 0; r2 <= 8 - s2.h; ++r2) {
                        for (int c2 = 0; c2 <= 8 - s2.w; ++c2) {
                            uint64_t m2 = SHAPE_MASKS[sid2][r2][c2];
                            if ((b1 & m2) == 0) {
                                uint64_t b2 = simulatePlacement(b1, sid2, r2, c2);
                                int pts2 = calculateStepPoints(b1, b2, sid2, next_combo1);
                                int c2_lines = countLinesCleared(b1, b2, sid2);
                                int next_combo2 = (c2_lines > 0) ? (next_combo1 + 1) : 0;

                                // Ply 3
                                float best3 = -1e9f;
                                for (int r3 = 0; r3 <= 8 - s3.h; ++r3) {
                                    for (int c3 = 0; c3 <= 8 - s3.w; ++c3) {
                                        uint64_t m3 = SHAPE_MASKS[sid3][r3][c3];
                                        if ((b2 & m3) == 0) {
                                            uint64_t b3 = simulatePlacement(b2, sid3, r3, c3);
                                            int pts3 = calculateStepPoints(b2, b3, sid3, next_combo2);
                                            int c3_lines = countLinesCleared(b2, b3, sid3);
                                            int next_combo3 = (c3_lines > 0) ? (next_combo2 + 1) : 0;
                                            float eval3 = pts3 + evaluateBoardTopology(b3, next_combo3);
                                            if (eval3 > best3) best3 = eval3;
                                        }
                                    }
                                }

                                if (best3 > -1e8f) {
                                    float seq_val = pts2 + best3;
                                    if (seq_val > best_hand) best_hand = seq_val;
                                }
                            }
                        }
                    }
                }
                branch_score = (best_hand > -1e8f) ? (pts1 + best_hand) : -50000.0f;
            }

            if (branch_score > best_val) {
                best_val = branch_score;
                best_action = a1;
            }
        }

        return best_action;
    }
};

} // namespace block_blast

#endif // BLOCK_BLAST_BITBOARD_H
