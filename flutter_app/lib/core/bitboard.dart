// 64-bit Bitboard Game Engine for Block Blast
// 100% faithful to the reverse-engineered C++ libtask.so core

import 'dart:math' as math;

class ShapeDef {
  final int id;
  final int kind;
  final int fill;
  final int w;
  final int h;
  final List<int> masks;

  const ShapeDef({
    required this.id,
    required this.kind,
    required this.fill,
    required this.w,
    required this.h,
    required this.masks,
  });
}

// All 43 reverse-engineered shapes from AlgorithmCore::g_arrShape
const List<ShapeDef> allShapes = [
  ShapeDef(id: 0, kind: 0, fill: 1, w: 1, h: 1, masks: [1]),
  ShapeDef(id: 1, kind: 0, fill: 1, w: 1, h: 1, masks: [1]),
  ShapeDef(id: 2, kind: 1, fill: 2, w: 1, h: 2, masks: [1, 1]),
  ShapeDef(id: 3, kind: 0, fill: 2, w: 2, h: 1, masks: [3]),
  ShapeDef(id: 4, kind: 1, fill: 3, w: 1, h: 3, masks: [1, 1, 1]),
  ShapeDef(id: 5, kind: 0, fill: 3, w: 3, h: 1, masks: [7]),
  ShapeDef(id: 6, kind: 3, fill: 3, w: 2, h: 2, masks: [3, 2]),
  ShapeDef(id: 7, kind: 1, fill: 4, w: 1, h: 4, masks: [1, 1, 1, 1]),
  ShapeDef(id: 8, kind: 3, fill: 4, w: 3, h: 2, masks: [4, 7]),
  ShapeDef(id: 9, kind: 2, fill: 4, w: 2, h: 2, masks: [3, 3]),
  ShapeDef(id: 10, kind: 3, fill: 4, w: 3, h: 2, masks: [2, 7]),
  ShapeDef(id: 11, kind: 0, fill: 5, w: 5, h: 1, masks: [31]),
  ShapeDef(id: 12, kind: 3, fill: 5, w: 3, h: 3, masks: [7, 1, 1]),
  ShapeDef(id: 13, kind: 2, fill: 9, w: 3, h: 3, masks: [7, 7, 7]),
  ShapeDef(id: 14, kind: 3, fill: 4, w: 3, h: 2, masks: [3, 6]),
  ShapeDef(id: 15, kind: 3, fill: 3, w: 2, h: 2, masks: [3, 1]),
  ShapeDef(id: 16, kind: 3, fill: 4, w: 2, h: 3, masks: [2, 3, 1]),
  ShapeDef(id: 17, kind: 0, fill: 4, w: 4, h: 1, masks: [15]),
  ShapeDef(id: 18, kind: 3, fill: 4, w: 3, h: 2, masks: [6, 3]),
  ShapeDef(id: 19, kind: 3, fill: 4, w: 2, h: 3, masks: [1, 3, 2]),
  ShapeDef(id: 20, kind: 3, fill: 4, w: 2, h: 3, masks: [2, 3, 2]),
  ShapeDef(id: 21, kind: 3, fill: 5, w: 3, h: 3, masks: [7, 4, 4]),
  ShapeDef(id: 22, kind: 1, fill: 5, w: 1, h: 5, masks: [1, 1, 1, 1, 1]),
  ShapeDef(id: 23, kind: 3, fill: 5, w: 3, h: 3, masks: [4, 4, 7]),
  ShapeDef(id: 24, kind: 3, fill: 5, w: 3, h: 3, masks: [1, 1, 7]),
  ShapeDef(id: 25, kind: 3, fill: 4, w: 2, h: 3, masks: [1, 3, 1]),
  ShapeDef(id: 26, kind: 3, fill: 4, w: 3, h: 2, masks: [7, 2]),
  ShapeDef(id: 27, kind: 3, fill: 3, w: 2, h: 2, masks: [2, 3]),
  ShapeDef(id: 28, kind: 3, fill: 3, w: 2, h: 2, masks: [1, 3]),
  ShapeDef(id: 29, kind: 3, fill: 4, w: 2, h: 3, masks: [1, 1, 3]),
  ShapeDef(id: 30, kind: 3, fill: 4, w: 3, h: 2, masks: [7, 1]),
  ShapeDef(id: 31, kind: 3, fill: 4, w: 2, h: 3, masks: [3, 2, 2]),
  ShapeDef(id: 32, kind: 3, fill: 4, w: 2, h: 3, masks: [3, 1, 1]),
  ShapeDef(id: 33, kind: 3, fill: 4, w: 3, h: 2, masks: [1, 7]),
  ShapeDef(id: 34, kind: 3, fill: 4, w: 3, h: 2, masks: [7, 4]),
  ShapeDef(id: 35, kind: 2, fill: 6, w: 3, h: 2, masks: [7, 7]),
  ShapeDef(id: 36, kind: 2, fill: 6, w: 2, h: 3, masks: [3, 3, 3]),
  ShapeDef(id: 37, kind: 3, fill: 2, w: 2, h: 2, masks: [2, 1]),
  ShapeDef(id: 38, kind: 3, fill: 2, w: 2, h: 2, masks: [1, 2]),
  ShapeDef(id: 39, kind: 3, fill: 3, w: 3, h: 3, masks: [4, 2, 1]),
  ShapeDef(id: 40, kind: 3, fill: 3, w: 3, h: 3, masks: [1, 2, 4]),
  ShapeDef(id: 41, kind: 3, fill: 3, w: 3, h: 3, masks: [1, 2, 4]),
  ShapeDef(id: 42, kind: 3, fill: 4, w: 2, h: 3, masks: [2, 2, 3]),
];

// Precomputed 64-bit bitmasks: [shapeId][row][col]
final List<List<List<int>>> precomputedMasks = _initPrecomputedMasks();

// Reverse-engineered shape pools from libtask.so
const List<int> poolSafe = [6, 27, 28, 15, 3, 2, 5, 4, 37, 38, 39, 40, 41];
const List<int> poolHard = [11, 13, 22, 12, 24, 21, 23, 14, 16, 18, 19];
const List<int> poolStandard = [
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  29,
  30,
  31,
  32,
  33,
  34,
  35,
  36,
  42,
];

int _simulatePlacement(int b, int sid, int r, int c) {
  final mask = precomputedMasks[sid][r][c];
  if (mask == 0 || (b & mask) != 0) return 0;
  int nb = b | mask;
  int clearMask = 0;
  for (int row = 0; row < 8; row++) {
    final rowMask = 0xFF << (row * 8);
    if ((nb & rowMask) == rowMask) clearMask |= rowMask;
  }
  const colBase = 0x0101010101010101;
  for (int col = 0; col < 8; col++) {
    final colMask = colBase << col;
    if ((nb & colMask) == colMask) clearMask |= colMask;
  }
  return nb & ~clearMask;
}

bool _checkLiveWayRecursive(
  int b,
  List<int> candidate,
  int usedMask,
  int placedCount,
) {
  if (placedCount == 3) return true;

  for (int i = 0; i < 3; i++) {
    if ((usedMask & (1 << i)) == 0) {
      final sid = candidate[i];
      final s = allShapes[sid];

      for (int r = 0; r <= 8 - s.h; r++) {
        for (int c = 0; c <= 8 - s.w; c++) {
          final mask = precomputedMasks[sid][r][c];
          if ((b & mask) == 0) {
            if (placedCount == 2) return true;
            final nb = _simulatePlacement(b, sid, r, c);
            if (_checkLiveWayRecursive(
              nb,
              candidate,
              usedMask | (1 << i),
              placedCount + 1,
            )) {
              return true;
            }
          }
        }
      }
    }
  }
  return false;
}

bool hasLiveWay(int b, List<int> candidate) {
  return _checkLiveWayRecursive(b, candidate, 0, 0);
}

List<List<List<int>>> _initPrecomputedMasks() {
  final tables = List.generate(
    43,
    (_) => List.generate(8, (_) => List.filled(8, 0)),
  );

  for (final s in allShapes) {
    for (int r = 0; r <= 8 - s.h; r++) {
      for (int c = 0; c <= 8 - s.w; c++) {
        int mask = 0;
        for (int dr = 0; dr < s.h; dr++) {
          final rowBits = s.masks[dr];
          for (int dc = 0; dc < s.w; dc++) {
            if (((rowBits >> (s.w - 1 - dc)) & 1) == 1) {
              final bitIdx = (r + dr) * 8 + (c + dc);
              mask |= (1 << bitIdx);
            }
          }
        }
        tables[s.id][r][c] = mask;
      }
    }
  }
  return tables;
}

class StepResult {
  final int points;
  final int linesCleared;
  final List<int> clearedRows;
  final List<int> clearedCols;
  final bool isGameOver;

  StepResult({
    required this.points,
    required this.linesCleared,
    required this.clearedRows,
    required this.clearedCols,
    required this.isGameOver,
  });
}

class BitboardGame {
  int board = 0; // 64-bit bitboard
  List<int> dock = [-1, -1, -1];
  int score = 0;
  int combo = 0;
  int linesClearedTotal = 0;
  int moves = 0;
  bool isGameOver = false;

  BitboardGame() {
    reset();
  }

  void reset() {
    board = 0;
    score = 0;
    combo = 0;
    linesClearedTotal = 0;
    moves = 0;
    isGameOver = false;
    refillDock();
  }

  void refillDock() {
    final rng = math.Random();
    int filledCells = 0;
    for (int i = 0; i < 64; i++) {
      if (((board >> i) & 1) == 1) filledCells++;
    }
    final coverRate = filledCells / 64.0;

    double hardProb = 0.05;
    if (score >= 8400) {
      hardProb = 0.40;
    } else if (score >= 3800) {
      hardProb = 0.30;
    } else if (score >= 1400) {
      hardProb = 0.20;
    } else if (score >= 500) {
      hardProb = 0.12;
    }

    List<int> candidate = [0, 0, 0];
    bool valid = false;

    for (int attempt = 0; attempt < 8; attempt++) {
      for (int i = 0; i < 3; i++) {
        if (coverRate >= 0.58) {
          // Congested board: safe clearing pieces
          if (rng.nextDouble() < 0.75) {
            candidate[i] = poolSafe[rng.nextInt(poolSafe.length)];
          } else {
            candidate[i] = poolStandard[rng.nextInt(poolStandard.length)];
          }
        } else if (coverRate <= 0.28) {
          // Open board: bigWeightStrategy
          if (rng.nextDouble() < 0.35) {
            candidate[i] = poolHard[rng.nextInt(poolHard.length)];
          } else {
            candidate[i] = poolStandard[rng.nextInt(poolStandard.length)];
          }
        } else {
          final r = rng.nextDouble();
          if (r < hardProb) {
            candidate[i] = poolHard[rng.nextInt(poolHard.length)];
          } else if (r < hardProb + 0.35) {
            candidate[i] = poolSafe[rng.nextInt(poolSafe.length)];
          } else {
            candidate[i] = rng.nextInt(43);
          }
        }
      }

      if (hasLiveWay(board, candidate)) {
        valid = true;
        break;
      }
    }

    if (!valid) {
      for (int i = 0; i < 3; i++) {
        candidate[i] = poolSafe[rng.nextInt(poolSafe.length)];
      }
    }

    dock = candidate;
    checkGameOver();
  }

  bool canPlace(int shapeId, int r, int c) {
    if (shapeId < 0 || shapeId >= 43) return false;
    final s = allShapes[shapeId];
    if (r < 0 || c < 0 || r + s.h > 8 || c + s.w > 8) return false;
    final mask = precomputedMasks[shapeId][r][c];
    if (mask == 0) return false;
    return (board & mask) == 0;
  }

  StepResult? place(int slot, int r, int c) {
    if (slot < 0 || slot >= 3 || dock[slot] < 0) return null;
    final shapeId = dock[slot];
    if (!canPlace(shapeId, r, c)) return null;

    final mask = precomputedMasks[shapeId][r][c];
    board |= mask;
    dock[slot] = -1;
    moves++;

    int points = allShapes[shapeId].fill;

    // Check completed rows & cols simultaneously
    int clearMask = 0;
    final clearedRows = <int>[];
    final clearedCols = <int>[];

    for (int row = 0; row < 8; row++) {
      final rowMask = 0xFF << (row * 8);
      if ((board & rowMask) == rowMask) {
        clearMask |= rowMask;
        clearedRows.add(row);
      }
    }

    const colBase = 0x0101010101010101;
    for (int col = 0; col < 8; col++) {
      final colMask = colBase << col;
      if ((board & colMask) == colMask) {
        clearMask |= colMask;
        clearedCols.add(col);
      }
    }

    final linesCleared = clearedRows.length + clearedCols.length;
    if (linesCleared > 0) {
      board &= ~clearMask;
      combo++;
      linesClearedTotal += linesCleared;
      points += 10 * (linesCleared * linesCleared) * combo;
    } else {
      combo = 0;
    }

    score += points;

    if (dock[0] < 0 && dock[1] < 0 && dock[2] < 0) {
      refillDock();
    } else {
      checkGameOver();
    }

    return StepResult(
      points: points,
      linesCleared: linesCleared,
      clearedRows: clearedRows,
      clearedCols: clearedCols,
      isGameOver: isGameOver,
    );
  }

  void checkGameOver() {
    for (int slot = 0; slot < 3; slot++) {
      final shapeId = dock[slot];
      if (shapeId < 0) continue;
      final s = allShapes[shapeId];
      for (int r = 0; r <= 8 - s.h; r++) {
        for (int c = 0; c <= 8 - s.w; c++) {
          final mask = precomputedMasks[shapeId][r][c];
          if ((board & mask) == 0) {
            isGameOver = false;
            return;
          }
        }
      }
    }
    isGameOver = true;
  }

  static final List<int> _masks3x3 = _initMasks3x3();
  static final List<int> _masks5x1H = _initMasks5x1H();
  static final List<int> _masks5x1V = _initMasks5x1V();

  static List<int> _initMasks3x3() {
    final list = <int>[];
    for (int r = 0; r <= 5; r++) {
      for (int c = 0; c <= 5; c++) {
        final m =
            (7 << (r * 8 + c)) |
            (7 << ((r + 1) * 8 + c)) |
            (7 << ((r + 2) * 8 + c));
        list.add(m);
      }
    }
    return list;
  }

  static List<int> _initMasks5x1H() {
    final list = <int>[];
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c <= 3; c++) {
        list.add(31 << (r * 8 + c));
      }
    }
    return list;
  }

  static List<int> _initMasks5x1V() {
    final list = <int>[];
    const col5 = 0x0101010101;
    for (int r = 0; r <= 3; r++) {
      for (int c = 0; c < 8; c++) {
        list.add(col5 << (r * 8 + c));
      }
    }
    return list;
  }

  static int _popcount(int x) {
    int count = 0;
    int v = x;
    for (int i = 0; i < 64; i++) {
      if (((v >> i) & 1) == 1) count++;
    }
    return count;
  }

  static double evaluateBoardTopology(int b, int currCombo) {
    bool fit3x3 = false;
    for (int i = 0; i < _masks3x3.length; i++) {
      if ((b & _masks3x3[i]) == 0) {
        fit3x3 = true;
        break;
      }
    }

    bool fit5h = false;
    for (int i = 0; i < _masks5x1H.length; i++) {
      if ((b & _masks5x1H[i]) == 0) {
        fit5h = true;
        break;
      }
    }

    bool fit5v = false;
    for (int i = 0; i < _masks5x1V.length; i++) {
      if ((b & _masks5x1V[i]) == 0) {
        fit5v = true;
        break;
      }
    }

    int filled = _popcount(b);
    double eval = 0.0;

    // 3x3 Space Reserve Rule (Anti-DDA Defense)
    if (fit3x3) {
      eval += 2500.0;
    } else {
      eval -= 6000.0;
    }

    // 5-bar Line Reserve
    if (fit5h || fit5v) {
      eval += 800.0;
    } else {
      eval -= 2500.0;
    }

    // Congestion penalty
    eval -= filled * 18.0;

    // Combo preservation reward
    if (currCombo > 0) {
      eval += currCombo * 150.0;
    }

    // Isolated 1x1 holes penalty
    int holes = 0;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        int bit = r * 8 + c;
        if (((b >> bit) & 1) == 0) {
          bool up = (r == 0) || (((b >> (bit - 8)) & 1) == 1);
          bool down = (r == 7) || (((b >> (bit + 8)) & 1) == 1);
          bool left = (c == 0) || (((b >> (bit - 1)) & 1) == 1);
          bool right = (c == 7) || (((b >> (bit + 1)) & 1) == 1);
          if (up && down && left && right) {
            holes++;
          }
        }
      }
    }
    eval -= holes * 1200.0;

    // Almost-cleared lines bonus (6 or 7 filled cells in row or col)
    int almostCleared = 0;
    for (int r = 0; r < 8; r++) {
      int cnt = _popcount(b & (0xFF << (r * 8)));
      if (cnt >= 6 && cnt <= 7) almostCleared++;
    }
    for (int c = 0; c < 8; c++) {
      int cnt = _popcount(b & (0x0101010101010101 << c));
      if (cnt >= 6 && cnt <= 7) almostCleared++;
    }
    eval += almostCleared * 150.0;

    return eval;
  }

  static int _countLinesCleared(int bBefore, int bAfter, int sid) {
    int oldCnt = _popcount(bBefore) + allShapes[sid].fill;
    int newCnt = _popcount(bAfter);
    int clearedCells = oldCnt - newCnt;
    return (clearedCells >= 8) ? (clearedCells ~/ 8) : 0;
  }

  static int _calcStepPoints(int bBefore, int bAfter, int sid, int currCombo) {
    int lines = _countLinesCleared(bBefore, bAfter, sid);
    int pts = allShapes[sid].fill;
    if (lines > 0) {
      pts += 10 * lines * lines * (currCombo + 1);
    }
    return pts;
  }

  // On-Device 3-Ply Permutation Search Engine
  static int getBestActionFromState(int board, List<int> dock, int combo) {
    final validActions = <int>[];
    for (int slot = 0; slot < 3; slot++) {
      if (slot >= dock.length) continue;
      final sid = dock[slot];
      if (sid < 0) continue;
      final s = allShapes[sid];
      for (int r = 0; r <= 8 - s.h; r++) {
        for (int c = 0; c <= 8 - s.w; c++) {
          final m = precomputedMasks[sid][r][c];
          if ((board & m) == 0) {
            validActions.add(slot * 64 + r * 8 + c);
          }
        }
      }
    }

    if (validActions.isEmpty) return -1;
    int bestAction = validActions[0];
    double bestVal = -1e9;

    for (final a1 in validActions) {
      final slot1 = a1 ~/ 64;
      final cell1 = a1 % 64;
      final r1 = cell1 ~/ 8;
      final c1 = cell1 % 8;
      final sid1 = dock[slot1];

      final b1 = _simulatePlacement(board, sid1, r1, c1);
      final pts1 = _calcStepPoints(board, b1, sid1, combo);
      final c1Lines = _countLinesCleared(board, b1, sid1);
      final nextCombo1 = (c1Lines > 0) ? (combo + 1) : 0;

      final remSlots = <int>[];
      for (int s = 0; s < 3; s++) {
        if (s != slot1 && s < dock.length && dock[s] >= 0) {
          remSlots.add(s);
        }
      }

      double branchScore = -1e9;

      if (remSlots.isEmpty) {
        branchScore = pts1 + evaluateBoardTopology(b1, nextCombo1);
      } else if (remSlots.length == 1) {
        final slot2 = remSlots[0];
        final sid2 = dock[slot2];
        final s2 = allShapes[sid2];
        double best2 = -1e9;

        for (int r2 = 0; r2 <= 8 - s2.h; r2++) {
          for (int c2 = 0; c2 <= 8 - s2.w; c2++) {
            final m2 = precomputedMasks[sid2][r2][c2];
            if ((b1 & m2) == 0) {
              final b2 = _simulatePlacement(b1, sid2, r2, c2);
              final pts2 = _calcStepPoints(b1, b2, sid2, nextCombo1);
              final c2Lines = _countLinesCleared(b1, b2, sid2);
              final nextCombo2 = (c2Lines > 0) ? (nextCombo1 + 1) : 0;
              final eval2 = pts2 + evaluateBoardTopology(b2, nextCombo2);
              if (eval2 > best2) best2 = eval2;
            }
          }
        }
        branchScore = (best2 > -1e8) ? (pts1 + best2) : -50000.0;
      } else {
        double bestHand = -1e9;
        for (int order = 0; order < 2; order++) {
          final slot2 = remSlots[order];
          final slot3 = remSlots[1 - order];
          final sid2 = dock[slot2];
          final sid3 = dock[slot3];
          final s2 = allShapes[sid2];
          final s3 = allShapes[sid3];

          for (int r2 = 0; r2 <= 8 - s2.h; r2++) {
            for (int c2 = 0; c2 <= 8 - s2.w; c2++) {
              final m2 = precomputedMasks[sid2][r2][c2];
              if ((b1 & m2) == 0) {
                final b2 = _simulatePlacement(b1, sid2, r2, c2);
                final pts2 = _calcStepPoints(b1, b2, sid2, nextCombo1);
                final c2Lines = _countLinesCleared(b1, b2, sid2);
                final nextCombo2 = (c2Lines > 0) ? (nextCombo1 + 1) : 0;

                double best3 = -1e9;
                for (int r3 = 0; r3 <= 8 - s3.h; r3++) {
                  for (int c3 = 0; c3 <= 8 - s3.w; c3++) {
                    final m3 = precomputedMasks[sid3][r3][c3];
                    if ((b2 & m3) == 0) {
                      final b3 = _simulatePlacement(b2, sid3, r3, c3);
                      final pts3 = _calcStepPoints(b2, b3, sid3, nextCombo2);
                      final c3Lines = _countLinesCleared(b2, b3, sid3);
                      final nextCombo3 = (c3Lines > 0) ? (nextCombo2 + 1) : 0;
                      final eval3 =
                          pts3 + evaluateBoardTopology(b3, nextCombo3);
                      if (eval3 > best3) best3 = eval3;
                    }
                  }
                }

                if (best3 > -1e8) {
                  final seqVal = pts2 + best3;
                  if (seqVal > bestHand) bestHand = seqVal;
                }
              }
            }
          }
        }
        branchScore = (bestHand > -1e8) ? (pts1 + bestHand) : -50000.0;
      }

      if (branchScore > bestVal) {
        bestVal = branchScore;
        bestAction = a1;
      }
    }

    return bestAction;
  }
}
