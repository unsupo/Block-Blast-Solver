#include "bitboard.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <thread>
#include <atomic>
#include <chrono>
#include <iomanip>
#include <sstream>

using namespace block_blast;

// Configuration
static const int DEFAULT_GAMES = 1000;
static const int TARGET_SCORE = 100000;

// 7 Exact DDA Stages
// 0: 0 - 500       (Warmup / Safe)
// 1: 500 - 1400    (DDA Tier 1: 12% Hard)
// 2: 1400 - 3800   (DDA Tier 2: 20% Hard)
// 3: 3800 - 8400   (DDA Tier 3: 30% Hard - Max Ramp)
// 4: 8400 - 25000  (Post-8.4k DDA Ceiling: 40% Hard Initial)
// 5: 25000 - 50000 (Post-8.4k DDA Ceiling: 40% Hard Mid)
// 6: 50000+        (Post-8.4k DDA Ceiling: 40% Hard Deep)
static const int NUM_STAGES = 7;

// 8 Discrete Combo Bins: 0, 1, 2, 3, 4, 5, 6, 7+
static const int NUM_COMBOS = 8;
static const int NUM_OCC = 8;

struct WipeEvent {
    int game_id;
    int step;
    int score;
    int combo;
    int filled;
};

// Global thread-safe counters
std::atomic<int> g_completed_games{0};
std::atomic<uint64_t> g_total_moves{0};
std::atomic<int> g_all_clear_count{0};
std::atomic<int> g_near_miss_count{0};
std::vector<WipeEvent> g_wipe_events;
std::mutex g_wipe_mutex;

struct Histogram {
    uint64_t occ[NUM_STAGES][NUM_OCC] = {{0}};
    uint64_t combo[NUM_STAGES][NUM_COMBOS] = {{0}};
    uint64_t runs_reached[NUM_STAGES] = {0};
    uint64_t stage_moves[NUM_STAGES] = {0};
    uint64_t stage_clears[NUM_STAGES] = {0};
    uint64_t stage_near_misses[NUM_STAGES] = {0};
};

static inline int getDDAStage(int s) {
    if (s < 500) return 0;
    if (s < 1400) return 1;
    if (s < 3800) return 2;
    if (s < 8400) return 3;
    if (s < 25000) return 4;
    if (s < 50000) return 5;
    return 6;
}

static inline int getOccTier(int filled) {
    if (filled == 0) return 0;
    if (filled <= 4) return 1;
    if (filled <= 10) return 2;
    if (filled <= 18) return 3;
    if (filled <= 26) return 4;
    if (filled <= 34) return 5;
    if (filled <= 42) return 6;
    return 7;
}

static inline int getComboBin(int c) {
    if (c <= 0) return 0;
    if (c == 1) return 1;
    if (c == 2) return 2;
    if (c == 3) return 3;
    if (c == 4) return 4;
    if (c == 5) return 5;
    if (c == 6) return 6;
    return 7; // 7+
}

void workerThread(int start_game, int end_game, Histogram* out_hist) {
    for (int g = start_game; g < end_game; ++g) {
        uint64_t seed = 2000003ULL + (uint64_t)g * 7919ULL;
        BitboardEngine engine(seed);
        int step = 0;
        bool stage_visited[NUM_STAGES] = {false};

        while (!engine.terminated && engine.score < TARGET_SCORE) {
            int act = engine.getBestActionSearch();
            if (act < 0) break;

            engine.step(act);
            step++;

            int s = engine.score;
            int c = engine.combo;
            int filled = __builtin_popcountll(engine.board);

            int stage = getDDAStage(s);
            int o_tier = getOccTier(filled);
            int c_bin = getComboBin(c);

            if (!stage_visited[stage]) {
                stage_visited[stage] = true;
                out_hist->runs_reached[stage]++;
            }

            out_hist->occ[stage][o_tier]++;
            out_hist->combo[stage][c_bin]++;
            out_hist->stage_moves[stage]++;

            if (filled == 0) {
                g_all_clear_count++;
                out_hist->stage_clears[stage]++;
                std::lock_guard<std::mutex> lock(g_wipe_mutex);
                g_wipe_events.push_back({g, step, s, c, filled});
                std::cout << "\n>>> [ALL CLEAR DETECTED] Game #" << g + 1 << " | Step " << step << " | Score " << s << " | Combo " << c << std::endl;
            } else if (filled <= 3) {
                g_near_miss_count++;
                out_hist->stage_near_misses[stage]++;
            }
        }

        g_completed_games++;
        g_total_moves += step;
    }
}

int main(int argc, char* argv[]) {
    int total_games = DEFAULT_GAMES;
    if (argc >= 2) {
        total_games = std::atoi(argv[1]);
    }

    int num_threads = std::thread::hardware_concurrency();
    if (num_threads < 1) num_threads = 8;

    std::cout << "================================================================" << std::endl;
    std::cout << "  BLOCK BLAST DDA-STAGE & STACKED COMBO SIMULATION ENGINE" << std::endl;
    std::cout << "  Target Games: " << total_games << " to " << TARGET_SCORE << " points" << std::endl;
    std::cout << "  DDA Stages: 0-500, 500-1.4k, 1.4k-3.8k, 3.8k-8.4k, 8.4k-25k, 25k-50k, 50k-100k+" << std::endl;
    std::cout << "  Threads: " << num_threads << " hardware cores" << std::endl;
    std::cout << "================================================================" << std::endl;

    std::vector<Histogram> thread_hists(num_threads);
    std::vector<std::thread> threads;
    int chunk = total_games / num_threads;

    auto t_start = std::chrono::high_resolution_clock::now();

    for (int t = 0; t < num_threads; ++t) {
        int start_g = t * chunk;
        int end_g = (t == num_threads - 1) ? total_games : start_g + chunk;
        threads.emplace_back(workerThread, start_g, end_g, &thread_hists[t]);
    }

    // Monitor thread
    while (g_completed_games.load() < total_games) {
        std::this_thread::sleep_for(std::chrono::seconds(5));
        int done = g_completed_games.load();
        uint64_t moves = g_total_moves.load();
        auto now = std::chrono::high_resolution_clock::now();
        double elapsed = std::chrono::duration<double>(now - t_start).count();
        double moves_per_sec = elapsed > 0 ? (moves / elapsed) : 0;
        double games_per_sec = elapsed > 0 ? (done / elapsed) : 0;
        double pct = (double)done / total_games * 100.0;
        double eta_sec = games_per_sec > 0 ? (total_games - done) / games_per_sec : 0;

        std::cout << "[" << std::fixed << std::setprecision(1) << pct << "%] "
                  << done << "/" << total_games << " games | "
                  << moves << " moves (" << (int)moves_per_sec << " moves/s) | "
                  << "Clears: " << g_all_clear_count.load() << " | "
                  << "Near-misses: " << g_near_miss_count.load() << " | "
                  << "ETA: " << (int)(eta_sec / 60) << "m " << ((int)eta_sec % 60) << "s"
                  << std::endl;
    }

    for (auto& th : threads) {
        if (th.joinable()) th.join();
    }

    auto t_end = std::chrono::high_resolution_clock::now();
    double total_sec = std::chrono::duration<double>(t_end - t_start).count();

    std::cout << "\n================ SIMULATION FINISHED ================" << std::endl;
    std::cout << "Total Games: " << total_games << std::endl;
    std::cout << "Total Moves: " << g_total_moves.load() << std::endl;
    std::cout << "Total Time: " << total_sec << "s (" << (g_total_moves.load() / total_sec) << " moves/sec)" << std::endl;
    std::cout << "Total All-Clears: " << g_all_clear_count.load() << std::endl;

    // Combine thread histograms
    Histogram total_hist;
    for (int t = 0; t < num_threads; ++t) {
        for (int s = 0; s < NUM_STAGES; ++s) {
            total_hist.runs_reached[s] += thread_hists[t].runs_reached[s];
            total_hist.stage_moves[s] += thread_hists[t].stage_moves[s];
            total_hist.stage_clears[s] += thread_hists[t].stage_clears[s];
            total_hist.stage_near_misses[s] += thread_hists[t].stage_near_misses[s];
            for (int o = 0; o < NUM_OCC; ++o) total_hist.occ[s][o] += thread_hists[t].occ[s][o];
            for (int c = 0; c < NUM_COMBOS; ++c) total_hist.combo[s][c] += thread_hists[t].combo[s][c];
        }
    }

    // Write to JSON for plotting
    std::ofstream ofs("stacked_combos_data.json");
    ofs << "{\n";
    ofs << "  \"total_games\": " << total_games << ",\n";
    ofs << "  \"total_moves\": " << g_total_moves.load() << ",\n";
    ofs << "  \"total_all_clears\": " << g_all_clear_count.load() << ",\n";
    ofs << "  \"total_near_misses\": " << g_near_miss_count.load() << ",\n";
    ofs << "  \"elapsed_seconds\": " << total_sec << ",\n";
    ofs << "  \"stages\": [\"0-500\", \"500-1.4k\", \"1.4k-3.8k\", \"3.8k-8.4k\", \"8.4k-25k\", \"25k-50k\", \"50k-100k+\"],\n";
    ofs << "  \"combo_names\": [\"Combo 0\", \"Combo 1\", \"Combo 2\", \"Combo 3\", \"Combo 4\", \"Combo 5\", \"Combo 6\", \"Combo 7+\"],\n";
    
    // Runs reached per stage
    ofs << "  \"runs_reached\": [";
    for (int s = 0; s < NUM_STAGES; ++s) {
        ofs << total_hist.runs_reached[s] << (s == NUM_STAGES - 1 ? "" : ", ");
    }
    ofs << "],\n";

    // Stage moves
    ofs << "  \"stage_moves\": [";
    for (int s = 0; s < NUM_STAGES; ++s) {
        ofs << total_hist.stage_moves[s] << (s == NUM_STAGES - 1 ? "" : ", ");
    }
    ofs << "],\n";

    // Stage clears
    ofs << "  \"stage_clears\": [";
    for (int s = 0; s < NUM_STAGES; ++s) {
        ofs << total_hist.stage_clears[s] << (s == NUM_STAGES - 1 ? "" : ", ");
    }
    ofs << "],\n";

    // Stage near misses
    ofs << "  \"stage_near_misses\": [";
    for (int s = 0; s < NUM_STAGES; ++s) {
        ofs << total_hist.stage_near_misses[s] << (s == NUM_STAGES - 1 ? "" : ", ");
    }
    ofs << "],\n";

    // Combo table [stage][combo_bin]
    ofs << "  \"combo_table\": [\n";
    for (int s = 0; s < NUM_STAGES; ++s) {
        ofs << "    [";
        for (int c = 0; c < NUM_COMBOS; ++c) {
            ofs << total_hist.combo[s][c] << (c == NUM_COMBOS - 1 ? "" : ", ");
        }
        ofs << "]" << (s == NUM_STAGES - 1 ? "" : ",\n");
    }
    ofs << "\n  ],\n";

    // Occupancy table [stage][occ_tier]
    ofs << "  \"occupancy_table\": [\n";
    for (int s = 0; s < NUM_STAGES; ++s) {
        ofs << "    [";
        for (int o = 0; o < NUM_OCC; ++o) {
            ofs << total_hist.occ[s][o] << (o == NUM_OCC - 1 ? "" : ", ");
        }
        ofs << "]" << (s == NUM_STAGES - 1 ? "" : ",\n");
    }
    ofs << "\n  ]\n";
    ofs << "}\n";
    ofs.close();

    std::cout << "Data saved to stacked_combos_data.json" << std::endl;
    return 0;
}
