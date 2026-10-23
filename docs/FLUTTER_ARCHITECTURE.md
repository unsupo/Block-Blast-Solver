# Block Blast Flutter Client Architecture

This document specifies the software architecture, state management, and native FFI integration to build a pixel-perfect, high-performance mobile client for **Block Blast!** in Flutter, powered by the exact same 64-bit Bitboard C++ core used by the PPO RL engine.

---

## 1. System Overview & Technology Stack

```
┌─────────────────────────────────────────────────────────────┐
│                       Flutter UI Layer                      │
│   ScoreBoard | 8x8 BoardView | DragAnchor | DockView        │
└──────────────────────────────┬──────────────────────────────┘
                               │ State / Controller
┌──────────────────────────────▼──────────────────────────────┐
│                    GameController (Notifier)                │
│    - Drag state, Ghost coordinates, Combo animations        │
│    - Audio & Haptics trigger hooks                          │
└──────────────────────────────┬──────────────────────────────┘
                               │ dart:ffi
┌──────────────────────────────▼──────────────────────────────┐
│             Native C++ Bitboard Core (bitboard.h)           │
│   - uint64_t board bitboard                                 │
│   - 43 reverse-engineered shapes precomputed masks         │
│   - Simultaneous row/col clears & combo scoring            │
│   - Solvability & termination checks                        │
└─────────────────────────────────────────────────────────────┘
```

- **Framework**: Flutter 3.x+ (Dart 3.x)
- **Platforms**: iOS, Android, macOS, Web (via pure Dart bitboard fallback)
- **Native Backend**: C++17 Bitboard Core (`bitboard.h` / `block_blast_c.cpp`) linked via `dart:ffi`
- **State Management**: `flutter_riverpod` (or `ChangeNotifier` / `Bloc`)
- **Rendering & Animation**: CustomPainter for grid & particles, `flutter_animate` for juice

---

## 2. Directory Structure

```text
flutter_block_blast/
├── pubspec.yaml
├── ios/
│   └── Classes/              # Houses bitboard.h & block_blast_c.cpp for iOS
├── android/
│   └── CMakeLists.txt        # Compiles bitboard.h & block_blast_c.cpp via NDK
├── lib/
│   ├── main.dart             # Entry point, theme, app wrapper
│   ├── core/
│   │   ├── bitboard_ffi.dart # dart:ffi bindings to libblockblast
│   │   ├── bitboard_dart.dart# 100% pure Dart fallback bitboard implementation
│   │   ├── shapes.dart       # All 43 shape definitions & color palettes
│   │   └── constants.dart    # Grid sizes, spacing, animation timings
│   ├── controllers/
│   │   └── game_controller.dart # Riverpod / ChangeNotifier managing game state
│   ├── models/
│   │   ├── game_state.dart   # Immutable state (board, dock, score, combo)
│   │   └── drag_state.dart   # Active drag piece, finger position, hover cell
│   ├── ui/
│   │   ├── screens/
│   │   │   └── game_screen.dart # Main screen scaffold
│   │   ├── widgets/
│   │   │   ├── header_bar.dart  # Score, high score, combo badge
│   │   │   ├── board_view.dart  # 8x8 interactive grid with ghost overlay
│   │   │   ├── cell_widget.dart # Glossy 3D jelly block rendering
│   │   │   ├── dock_view.dart   # 3-slot piece dock container
│   │   │   ├── draggable_piece.dart # Touch interaction with finger offset
│   │   │   └── blast_particles.dart # Particle bursting system for clears
│   │   └── effects/
│   │       ├── haptic_service.dart # Tactile vibration feedback
│   │       └── audio_service.dart  # Sound effects engine (pitch-scaled combos)
```

---

## 3. Native Integration via `dart:ffi`

To guarantee 100% fidelity with the RL environment, Flutter invokes the exact same C ABI exported by `block_blast_c.cpp`.

### Dart FFI Bindings (`lib/core/bitboard_ffi.dart`)

```dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Typedefs matching block_blast_c.cpp
typedef CCreate = Pointer<Void> Function(Uint64 seed);
typedef DartCreate = Pointer<Void> Function(int seed);

typedef CDestroy = Void Function(Pointer<Void> ptr);
typedef DartDestroy = void Function(Pointer<Void> ptr);

typedef CReset = Void Function(Pointer<Void> ptr, Uint64 seed);
typedef DartReset = void Function(Pointer<Void> ptr, int seed);

typedef CStep = Int32 Function(Pointer<Void> ptr, Int32 action);
typedef DartStep = int Function(Pointer<Void> ptr, int action);

typedef CGetBoard = Uint64 Function(Pointer<Void> ptr);
typedef DartGetBoard = int Function(Pointer<Void> ptr);

typedef CGetDock = Void Function(Pointer<Void> ptr, Pointer<Int32> outDock);
typedef DartGetDock = void Function(Pointer<Void> ptr, Pointer<Int32> outDock);

typedef CGetActionMask = Void Function(Pointer<Void> ptr, Pointer<Uint8> outMask);
typedef DartGetActionMask = void Function(Pointer<Void> ptr, Pointer<Uint8> outMask);

class NativeBitboard {
  late DynamicLibrary _lib;
  late DartCreate _create;
  late DartDestroy _destroy;
  late DartReset _reset;
  late DartStep _step;
  late DartGetBoard _getBoard;
  late DartGetDock _getDock;
  late DartGetActionMask _getActionMask;
  
  Pointer<Void>? _enginePtr;
  final Pointer<Int32> _dockBuffer = calloc<Int32>(3);
  final Pointer<Uint8> _maskBuffer = calloc<Uint8>(192);

  NativeBitboard() {
    _lib = Platform.isIOS || Platform.isMacOS
        ? DynamicLibrary.process()
        : DynamicLibrary.open('libblockblast.so');

    _create = _lib.lookupFunction<CCreate, DartCreate>('bb_create');
    _destroy = _lib.lookupFunction<CDestroy, DartDestroy>('bb_destroy');
    _reset = _lib.lookupFunction<CReset, DartReset>('bb_reset');
    _step = _lib.lookupFunction<CStep, DartStep>('bb_step');
    _getBoard = _lib.lookupFunction<CGetBoard, DartGetBoard>('bb_get_board');
    _getDock = _lib.lookupFunction<CGetDock, DartGetDock>('bb_get_dock');
    _getActionMask = _lib.lookupFunction<CGetActionMask, DartGetActionMask>('bb_get_action_mask');

    _enginePtr = _create(DateTime.now().millisecondsSinceEpoch);
  }

  void reset([int? seed]) {
    _reset(_enginePtr!, seed ?? DateTime.now().millisecondsSinceEpoch);
  }

  int step(int action) => _step(_enginePtr!, action);

  int get board => _getBoard(_enginePtr!);

  List<int> get dock {
    _getDock(_enginePtr!, _dockBuffer);
    return [_dockBuffer[0], _dockBuffer[1], _dockBuffer[2]];
  }

  List<int> get actionMask {
    _getActionMask(_enginePtr!, _maskBuffer);
    return List<int>.generate(192, (i) => _maskBuffer[i]);
  }

  void dispose() {
    if (_enginePtr != null) {
      _destroy(_enginePtr!);
      _enginePtr = null;
    }
    calloc.free(_dockBuffer);
    calloc.free(_maskBuffer);
  }
}
```

---

## 4. Pure Dart 64-Bit Bitboard (Cross-Platform Fallback)

For Flutter Web or environments without native compilers, Dart's native `int` is an arbitrary-precision or 64-bit integer, executing bitboard operations identically:

```dart
class DartBitboard {
  int board = 0; // 64-bit unsigned integer
  List<int> dock = [-1, -1, -1];
  int score = 0;
  int combo = 0;

  bool canPlace(int shapeId, int r, int c) {
    final mask = precomputedMasks[shapeId][r][c];
    if (mask == 0) return false; // Out of bounds
    return (board & mask) == 0;  // Collision check
  }

  int place(int slot, int r, int c) {
    final shapeId = dock[slot];
    final mask = precomputedMasks[shapeId][r][c];
    board |= mask;
    dock[slot] = -1;

    // Check rows & cols
    int clearMask = 0;
    int clearedLines = 0;

    for (int row = 0; row < 8; row++) {
      int rowMask = 0xFF << (row * 8);
      if ((board & rowMask) == rowMask) {
        clearMask |= rowMask;
        clearedLines++;
      }
    }
    for (int col = 0; col < 8; col++) {
      int colMask = 0x0101010101010101 << col;
      if ((board & colMask) == colMask) {
        clearMask |= colMask;
        clearedLines++;
      }
    }

    if (clearedLines > 0) {
      board &= ~clearMask;
      combo++;
      score += shapes[shapeId].fill + 10 * (clearedLines * clearedLines) * combo;
    } else {
      combo = 0;
      score += shapes[shapeId].fill;
    }
    return clearedLines;
  }
}
```
