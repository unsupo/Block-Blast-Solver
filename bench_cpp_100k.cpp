#include "bitboard.h"
#include <iostream>
#include <chrono>

using namespace block_blast;

int main() {
    auto t0 = std::chrono::high_resolution_clock::now();
    BitboardEngine engine(42);
    int steps = 0;
    while (!engine.terminated && engine.score < 100000) {
        int act = engine.getBestActionSearch();
        if (act < 0) break;
        engine.step(act);
        steps++;
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    std::cout << "Pure C++: " << steps << " steps to score " << engine.score << " in " << ms << " ms (" << (steps / (ms / 1000.0)) << " steps/sec)" << std::endl;
    return 0;
}
