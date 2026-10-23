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
static const int DEFAULT_GAMES = 1000; // Can be 100000 via command line
static const int TARGET_SCORE = 100000;

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

// Histograms: [score_bracket (0..7)][occupancy_tier (0..7)]
// Score brackets: 0-1k, 1k-5k, 5k-15k, 15k-30k, 30k-50k, 50k-75k, 75k-100k, 100k+
// Occupancy tiers: 0 (All Clear), 1-4 (Near Miss), 5-10, 11-18, 19-26, 27-34, 35-42, 43+
struct Histogram {
    uint64_t occ[8][8] = {{0}};
    uint64_t combo[8][7] = {{0}}; // combo tiers: 0, 1x, 2-3x, 4-5x, 6-8x, 9-12x, 13x+
};

static inline int getScoreTier(int s) {
    if (s < 1000) return 0;
    if (s < 5000) return 1;
    if (s < 15000) return 2;
    if (s < 30000) return 3;
    if (s < 50000) return 4;
    if (s < 75000) return 5;
    if (s < 100000) return 6;
    return 7;
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

static inline int getComboTier(int c) {
    if (c == 0) return 0;
    if (c == 1) return 1;
    if (c <= 3) return 2;
    if (c <= 5) return 3;
    if (c <= 8) return 4;
    if (c <= 12) return 5;
    return 6;
}

void workerThread(int start_game, int end_game, Histogram* out_hist) {
    for (int g = start_game; g < end_game; ++g) {
        uint64_t seed = 1000003ULL + (uint64_t)g * 7919ULL;
        BitboardEngine engine(seed);
        int step = 0;

        while (!engine.terminated && engine.score < TARGET_SCORE) {
            int act = engine.getBestActionSearch();
            if (act < 0) break;

            engine.step(act);
            step++;

            int s = engine.score;
            int c = engine.combo;
            int filled = __builtin_popcountll(engine.board);

            int s_tier = getScoreTier(s);
            int o_tier = getOccTier(filled);
            int c_tier = getComboTier(c);

            out_hist->occ[s_tier][o_tier]++;
            out_hist->combo[s_tier][c_tier]++;

            if (filled == 0) {
                g_all_clear_count++;
                std::lock_guard<std::mutex> lock(g_wipe_mutex);
                g_wipe_events.push_back({g, step, s, c, filled});
                std::cout << "\n>>> [ALL CLEAR DETECTED] Game #" << g + 1 << " | Step " << step << " | Score " << s << " | Combo " << c << std::endl;
            } else if (filled <= 3) {
                g_near_miss_count++;
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
    std::cout << "  BLOCK BLAST MASSIVE MONTE CARLO SIMULATION ENGINE" << std::endl;
    std::cout << "  Target: " << total_games << " games reaching " << TARGET_SCORE << " points" << std::endl;
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

    // Monitor thread with periodic snapshot saves
    int last_saved_games = 0;
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

        // Periodic snapshot save every 250 games
        if (done - last_saved_games >= 250) {
            last_saved_games = done;
            Histogram snap_hist;
            for (int t = 0; t < num_threads; ++t) {
                for (int s = 0; s < 8; ++s) {
                    for (int o = 0; o < 8; ++o) snap_hist.occ[s][o] += thread_hists[t].occ[s][o];
                    for (int c = 0; c < 7; ++c) snap_hist.combo[s][c] += thread_hists[t].combo[s][c];
                }
            }
            std::ofstream snap_ofs("monte_carlo_results.json");
            snap_ofs << "{\n";
            snap_ofs << "  \"total_games\": " << done << ",\n";
            snap_ofs << "  \"total_moves\": " << moves << ",\n";
            snap_ofs << "  \"total_all_clears\": " << g_all_clear_count.load() << ",\n";
            snap_ofs << "  \"total_near_misses\": " << g_near_miss_count.load() << ",\n";
            snap_ofs << "  \"elapsed_seconds\": " << elapsed << ",\n";
            snap_ofs << "  \"occupancy_table\": [\n";
            for (int s = 0; s < 8; ++s) {
                snap_ofs << "    [";
                for (int o = 0; o < 8; ++o) snap_ofs << snap_hist.occ[s][o] << (o == 7 ? "" : ", ");
                snap_ofs << "]" << (s == 7 ? "" : ",\n");
            }
            snap_ofs << "\n  ],\n";
            snap_ofs << "  \"combo_table\": [\n";
            for (int s = 0; s < 8; ++s) {
                snap_ofs << "    [";
                for (int c = 0; c < 7; ++c) snap_ofs << snap_hist.combo[s][c] << (c == 6 ? "" : ", ");
                snap_ofs << "]" << (s == 7 ? "" : ",\n");
            }
            snap_ofs << "\n  ]\n";
            snap_ofs << "}\n";
            snap_ofs.close();
        }
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
    std::cout << "Total Near-Misses: " << g_near_miss_count.load() << std::endl;

    // Combine histograms
    Histogram total_hist;
    for (int t = 0; t < num_threads; ++t) {
        for (int s = 0; s < 8; ++s) {
            for (int o = 0; o < 8; ++o) total_hist.occ[s][o] += thread_hists[t].occ[s][o];
            for (int c = 0; c < 7; ++c) total_hist.combo[s][c] += thread_hists[t].combo[s][c];
        }
    }

    // Save summary results to JSON for plotting
    std::ofstream ofs("monte_carlo_results.json");
    ofs << "{\n";
    ofs << "  \"total_games\": " << total_games << ",\n";
    ofs << "  \"total_moves\": " << g_total_moves.load() << ",\n";
    ofs << "  \"total_all_clears\": " << g_all_clear_count.load() << ",\n";
    ofs << "  \"total_near_misses\": " << g_near_miss_count.load() << ",\n";
    ofs << "  \"elapsed_seconds\": " << total_sec << ",\n";
    ofs << "  \"occupancy_table\": [\n";
    for (int s = 0; s < 8; ++s) {
        ofs << "    [";
        for (int o = 0; o < 8; ++o) {
            ofs << total_hist.occ[s][o] << (o == 7 ? "" : ", ");
        }
        ofs << "]" << (s == 7 ? "" : ",\n");
    }
    ofs << "\n  ],\n";
    ofs << "  \"combo_table\": [\n";
    for (int s = 0; s < 8; ++s) {
        ofs << "    [";
        for (int c = 0; c < 7; ++c) {
            ofs << total_hist.combo[s][c] << (c == 6 ? "" : ", ");
        }
        ofs << "]" << (s == 7 ? "" : ",\n");
    }
    ofs << "\n  ],\n";
    ofs << "  \"wipe_events\": [\n";
    for (size_t i = 0; i < g_wipe_events.size(); ++i) {
        const auto& w = g_wipe_events[i];
        ofs << "    {\"game_id\": " << w.game_id << ", \"step\": " << w.step
            << ", \"score\": " << w.score << ", \"combo\": " << w.combo << "}"
            << (i + 1 == g_wipe_events.size() ? "" : ",\n");
    }
    ofs << "\n  ]\n";
    ofs << "}\n";
    ofs.close();

    std::cout << "Data saved to monte_carlo_results.json" << std::endl;
    return 0;
}
