import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/bitboard.dart';
import 'core/ai_client.dart';
import 'ui/theme.dart';
import 'ui/block_widget.dart';
import 'ui/piece_widget.dart';
import 'ui/outlined_text.dart';
import 'ui/board_grid_painter.dart';
import 'ui/combo_shield_painter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Reference footage never shows a status/nav bar — Block Blast runs
  // fully immersive, not just edge-to-edge.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const BlockBlastApp());
}

class BlockBlastApp extends StatelessWidget {
  const BlockBlastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Block Blast',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: GameTheme.backgroundTop,
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final BitboardGame game = BitboardGame();
  final GlobalKey _boardKey = GlobalKey();

  int highScore = 0;
  int currentSkinIndex = 0;
  BoardSkinTheme get currentSkin =>
      GameTheme.skinThemes[currentSkinIndex % GameTheme.skinThemes.length];

  // Track gem color for each board cell (row * 8 + col -> colorIndex)
  final Map<int, int> boardCellShapes = {};

  // Real Block Blast assigns each dock piece its own color independent of
  // shape type (the same tetromino shows up in different colors across
  // refills) — a generation counter + slot/shapeId hash approximates that
  // without touching the reverse-engineered bitboard engine.
  int _dockGen = 0;

  int _dockColorIndex(int slot, int shapeId) {
    return (shapeId * 31 + slot * 7 + _dockGen * 13) %
        GameTheme.colorStyles.length;
  }

  // Drag state
  int? draggedSlot;
  int? draggedShapeId;
  Offset? dragPosition;
  int? hoverRow;
  int? hoverCol;

  // Flash rows and cols
  Set<int> flashingRows = {};
  Set<int> flashingCols = {};

  // Floating score popups
  List<ScorePopup> scorePopups = [];

  // Active praise compliment ("Good!", "Great!", "Amazing!", etc.)
  String? activeCheer;
  Color activeCheerColor = Colors.white;
  Key cheerKey = UniqueKey();

  // AI Mode State
  bool isAiMode = false;
  bool isAiThinking = false;
  String? activeAiModel;
  int? aiHighlightSlot;
  int? aiHighlightRow;
  int? aiHighlightCol;

  // Hint State
  bool isHintLoading = false;
  int? hintSlot;
  int? hintRow;
  int? hintCol;
  int? hintShapeId;

  // Edit Mode State (Custom Board & Dock Sandbox)
  bool isEditMode = false;

  late final AnimationController _hintPulseController;
  late final Animation<double> _hintPulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadState();
    _hintPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _hintPulseAnimation = CurvedAnimation(
      parent: _hintPulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hintPulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveState();
    }
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('high_score', highScore);
      await prefs.setInt('score', game.score);
      await prefs.setString(
        'board',
        BigInt.from(game.board).toUnsigned(64).toString(),
      );
      await prefs.setStringList(
        'dock',
        game.dock.map((e) => e.toString()).toList(),
      );
      await prefs.setInt('combo', game.combo);
      await prefs.setInt('dock_gen', _dockGen);
      await prefs.setInt('skin_index', currentSkinIndex);
      await prefs.setBool('is_game_over', game.isGameOver);
      final cellMapString = jsonEncode(
        boardCellShapes.map((k, v) => MapEntry(k.toString(), v)),
      );
      await prefs.setString('board_cell_shapes', cellMapString);
    } catch (_) {}
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedHighScore = prefs.getInt('high_score') ?? 0;
      final savedScore = prefs.getInt('score') ?? 0;
      final savedBoardStr = prefs.getString('board');
      final savedDockList = prefs.getStringList('dock');
      final savedCombo = prefs.getInt('combo') ?? 0;
      final savedDockGen = prefs.getInt('dock_gen') ?? 0;
      final savedSkinIndex = prefs.getInt('skin_index') ?? 0;
      final savedIsGameOver = prefs.getBool('is_game_over') ?? false;
      final savedCellMapStr = prefs.getString('board_cell_shapes');

      if (!mounted) return;
      setState(() {
        highScore = savedHighScore;
        currentSkinIndex = savedSkinIndex.clamp(0, GameTheme.skinThemes.length - 1);
        if (savedBoardStr != null) {
          final b = BigInt.tryParse(savedBoardStr);
          if (b != null) {
            game.board = b.toSigned(64).toInt();
          }
        }
        if (savedDockList != null && savedDockList.length == 3) {
          for (int i = 0; i < 3; i++) {
            game.dock[i] = int.tryParse(savedDockList[i]) ?? -1;
          }
        }
        game.score = savedScore;
        game.combo = savedCombo;
        game.isGameOver = savedIsGameOver;
        _dockGen = savedDockGen;

        boardCellShapes.clear();
        if (savedCellMapStr != null) {
          try {
            final decoded = jsonDecode(savedCellMapStr) as Map<String, dynamic>;
            for (final entry in decoded.entries) {
              final key = int.tryParse(entry.key);
              final val = entry.value as int?;
              if (key != null && val != null) {
                boardCellShapes[key] = val;
              }
            }
          } catch (_) {}
        }
        // Fill any cells in boardCellShapes that are missing
        for (int i = 0; i < 64; i++) {
          if (((game.board >> i) & 1) == 1 && !boardCellShapes.containsKey(i)) {
            boardCellShapes[i] =
                (i ~/ 8 + i % 8 + _dockGen) % GameTheme.colorStyles.length;
          }
        }
      });
    } catch (_) {}
  }

  void _triggerCheer(String text, Color color) {
    setState(() {
      activeCheer = text;
      activeCheerColor = color;
      cheerKey = UniqueKey();
    });

    Future.delayed(const Duration(milliseconds: 850), () {
      if (mounted && activeCheer == text) {
        setState(() {
          activeCheer = null;
        });
      }
    });
  }

  void _onPanStart(int slot, DragStartDetails details) {
    if (game.dock[slot] < 0) return;
    HapticFeedback.selectionClick();
    setState(() {
      draggedSlot = slot;
      draggedShapeId = game.dock[slot];
      dragPosition = details.globalPosition;
      _updateHoverCoordinates(details.globalPosition);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (draggedSlot == null) return;
    setState(() {
      dragPosition = details.globalPosition;
      _updateHoverCoordinates(details.globalPosition);
    });
  }

  bool _applyPlacement(int slot, int r, int c, {Offset? popupPosition}) {
    if (slot < 0 || slot >= 3 || game.dock[slot] < 0) return false;
    final shapeId = game.dock[slot];
    final shape = allShapes[shapeId];
    final colorIdx = _dockColorIndex(slot, shapeId);
    // If this is the last of the 3 dock pieces, placing it triggers an
    // internal refill — the other (already-placed/-empty) slots are about
    // to be repopulated, so bump the generation for their new colors.
    final willRefill = game.dock.where((s) => s >= 0).length == 1;

    final res = game.place(slot, r, c);
    if (res != null) {
      // Record gem colors for newly placed cells
      for (int dr = 0; dr < shape.h; dr++) {
        final rowBits = shape.masks[dr];
        for (int dc = 0; dc < shape.w; dc++) {
          if (((rowBits >> (shape.w - 1 - dc)) & 1) == 1) {
            boardCellShapes[(r + dr) * 8 + (c + dc)] = colorIdx;
          }
        }
      }
      if (willRefill) {
        _dockGen++;
      }

      // Clean up cleared cells from boardCellShapes
      for (final row in res.clearedRows) {
        for (int col = 0; col < 8; col++) {
          boardCellShapes.remove(row * 8 + col);
        }
      }
      for (final col in res.clearedCols) {
        for (int row = 0; row < 8; row++) {
          boardCellShapes.remove(row * 8 + col);
        }
      }

      // Haptics & effects
      if (res.linesCleared > 0) {
        HapticFeedback.heavyImpact();
        _triggerLineClearAnimation(res.clearedRows, res.clearedCols);

        // All Clear check (BoardClearChangeSkinTrait)
        if (game.board == 0) {
          currentSkinIndex =
              (currentSkinIndex + 1) % GameTheme.skinThemes.length;
          _triggerCheer('ALL CLEAR!', const Color(0xFFFFD700));
        } else {
          // Score milestone skin transition (every 2,000 pts)
          final oldMilestone = (game.score - res.points) ~/ 2000;
          final newMilestone = game.score ~/ 2000;
          if (newMilestone > oldMilestone) {
            currentSkinIndex =
                (currentSkinIndex + (newMilestone - oldMilestone)) %
                GameTheme.skinThemes.length;
          }

          // Reference game shows "Combo N" once a streak is going, otherwise
          // a single compliment word scaled to how many lines cleared at once.
          if (game.combo >= 2) {
            _triggerCheer(
              'COMBO:${game.combo}',
              GameTheme.getComboShieldColor(game.combo),
            );
          } else {
            String? cheer;
            Color cheerColor = const Color(0xFF00E5FF);
            if (res.linesCleared >= 4) {
              cheer = 'Unbelievable!';
              cheerColor = const Color(0xFFFF1744);
            } else if (res.linesCleared == 3) {
              cheer = 'Excellent!';
              cheerColor = const Color(0xFFFF9100);
            } else if (res.linesCleared == 2) {
              cheer = 'Great!';
              cheerColor = const Color(0xFF00E676);
            } else {
              cheer = 'Good!';
              cheerColor = const Color(0xFF00E5FF);
            }
            _triggerCheer(cheer, cheerColor);
          }
        }
      } else {
        HapticFeedback.lightImpact();
      }

      if (popupPosition != null) {
        _addScorePopup(res.points, popupPosition);
      }

      if (game.score > highScore) {
        highScore = game.score;
      }
      _saveState();

      // Clear any active hint once a move is made
      hintSlot = null;
      hintRow = null;
      hintCol = null;
      hintShapeId = null;

      if (res.isGameOver) {
        if (!isAiMode) {
          _showGameOverDialog();
        }
      }
      return true;
    } else {
      HapticFeedback.mediumImpact();
      return false;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (draggedSlot != null && hoverRow != null && hoverCol != null) {
      final slot = draggedSlot!;
      final r = hoverRow!;
      final c = hoverCol!;
      _applyPlacement(slot, r, c, popupPosition: dragPosition);
    }

    setState(() {
      draggedSlot = null;
      draggedShapeId = null;
      dragPosition = null;
      hoverRow = null;
      hoverCol = null;
    });
  }

  void _toggleAiMode() {
    HapticFeedback.mediumImpact();
    setState(() {
      isAiMode = !isAiMode;
      isEditMode = false;
      hintSlot = null;
      hintRow = null;
      hintCol = null;
      hintShapeId = null;
      if (!isAiMode) {
        isAiThinking = false;
        aiHighlightSlot = null;
        aiHighlightRow = null;
        aiHighlightCol = null;
      }
    });

    if (isAiMode) {
      _runAiLoop();
    }
  }

  Future<void> _toggleHint() async {
    if (isAiMode || isEditMode) return;
    if (hintSlot != null) {
      HapticFeedback.selectionClick();
      setState(() {
        hintSlot = null;
        hintRow = null;
        hintCol = null;
        hintShapeId = null;
      });
      return;
    }

    if (game.isGameOver || game.dock.every((s) => s < 0)) return;

    HapticFeedback.lightImpact();
    setState(() {
      isHintLoading = true;
    });

    final pred = await AiClient.getBestMove(
      board: game.board,
      dock: List<int>.from(game.dock),
      combo: game.combo,
    );

    if (!mounted) return;

    setState(() {
      isHintLoading = false;
      if (pred != null && pred.valid) {
        hintSlot = pred.slot;
        hintRow = pred.row;
        hintCol = pred.col;
        hintShapeId = pred.shapeId >= 0
            ? pred.shapeId
            : (pred.slot < game.dock.length ? game.dock[pred.slot] : null);
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _toggleEditMode() {
    HapticFeedback.mediumImpact();
    setState(() {
      isEditMode = !isEditMode;
      if (isEditMode) {
        isAiMode = false;
        isAiThinking = false;
        aiHighlightSlot = null;
        aiHighlightRow = null;
        aiHighlightCol = null;
        hintSlot = null;
        hintRow = null;
        hintCol = null;
        hintShapeId = null;
      } else {
        game.checkGameOver();
      }
    });
    _saveState();
  }

  void _toggleBoardCell(int r, int c) {
    if (!isEditMode) return;
    HapticFeedback.selectionClick();
    final bitIdx = r * 8 + c;
    setState(() {
      final isFilled = ((game.board >> bitIdx) & 1) == 1;
      if (isFilled) {
        game.board &= ~(1 << bitIdx);
        boardCellShapes.remove(bitIdx);
      } else {
        game.board |= (1 << bitIdx);
        boardCellShapes[bitIdx] =
            (r * 3 + c * 5 + _dockGen) % GameTheme.colorStyles.length;
      }
      game.isGameOver = false;
    });
    _saveState();
  }

  void _cycleDockPiece(int slot) {
    if (!isEditMode || slot < 0 || slot >= 3) return;
    HapticFeedback.selectionClick();
    setState(() {
      final current = game.dock[slot];
      if (current < 0) {
        game.dock[slot] = 0;
      } else {
        game.dock[slot] = (current + 1) % allShapes.length;
      }
      game.isGameOver = false;
    });
    _saveState();
  }

  void _showShapePickerSheet(int slot) {
    if (!isEditMode || slot < 0 || slot >= 3) return;
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: GameTheme.boardContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Piece ${slot + 1}',
                      style: GameTheme.display(
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 300,
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: allShapes.length,
                    itemBuilder: (context, idx) {
                      final shape = allShapes[idx];
                      final isSelected = game.dock[slot] == idx;
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            game.dock[slot] = idx;
                            game.isGameOver = false;
                          });
                          _saveState();
                          Navigator.of(ctx).pop();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(
                                    0xFFFF9100,
                                  ).withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFFFF9100)
                                  : Colors.white24,
                              width: isSelected ? 2.5 : 1.0,
                            ),
                          ),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: PieceWidget(
                                shape: shape,
                                cellSize: 10.0,
                                colorIndex: _dockColorIndex(slot, idx),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _runAiLoop() async {
    while (isAiMode && mounted) {
      try {
        if (game.isGameOver) {
          // In AI mode, auto-restart after 1.2s delay to keep playing
          await Future.delayed(const Duration(milliseconds: 1200));
          if (!mounted || !isAiMode) break;
          setState(() {
            boardCellShapes.clear();
            game.reset();
          });
          await Future.delayed(const Duration(milliseconds: 300));
          if (!mounted || !isAiMode) break;
        }

        setState(() {
          isAiThinking = true;
        });

        final pred = await AiClient.getBestMove(
          board: game.board,
          dock: List<int>.from(game.dock),
          combo: game.combo,
        );

        if (!mounted || !isAiMode) break;

        if (pred == null || !pred.valid) {
          if (game.dock.every((s) => s < 0)) {
            setState(() {
              game.refillDock();
            });
            continue;
          }
          await Future.delayed(const Duration(milliseconds: 400));
          continue;
        }

        // Preview move highlight
        setState(() {
          activeAiModel = pred.model;
          isAiThinking = false;
          aiHighlightSlot = pred.slot;
          aiHighlightRow = pred.row;
          aiHighlightCol = pred.col;
        });

        // Brief animation preview cadence
        await Future.delayed(const Duration(milliseconds: 160));
        if (!mounted || !isAiMode) break;

        // Calculate popup position near center of placed shape
        Offset? popupPos;
        final RenderBox? boardBox =
            _boardKey.currentContext?.findRenderObject() as RenderBox?;
        if (boardBox != null && boardBox.hasSize) {
          final boardPos = boardBox.localToGlobal(Offset.zero);
          final cellSize = (boardBox.size.width - 16.0) / 8;
          popupPos =
              boardPos +
              Offset((pred.col + 1.5) * cellSize, (pred.row + 1) * cellSize);
        }

        setState(() {
          _applyPlacement(
            pred.slot,
            pred.row,
            pred.col,
            popupPosition: popupPos,
          );
          aiHighlightSlot = null;
          aiHighlightRow = null;
          aiHighlightCol = null;
        });

        // Cadence between moves for smooth, satisfying playback
        await Future.delayed(const Duration(milliseconds: 260));
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  void _updateHoverCoordinates(Offset globalPos) {
    final RenderBox? boardBox =
        _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (boardBox == null || draggedShapeId == null) {
      hoverRow = null;
      hoverCol = null;
      return;
    }

    final boardPos = boardBox.localToGlobal(Offset.zero);
    final boardSize = boardBox.size.width;
    final cellSize = (boardSize - 16.0) / 8;

    // 65px vertical offset above the finger so piece is visible
    const fingerOffset = Offset(0, -65);
    final anchor = globalPos + fingerOffset - boardPos - const Offset(8.0, 8.0);

    final shape = allShapes[draggedShapeId!];
    final centerAnchor =
        anchor - Offset((shape.w * cellSize) / 2, (shape.h * cellSize) / 2);

    final c = ((centerAnchor.dx + cellSize * 0.5) / cellSize).floor();
    final r = ((centerAnchor.dy + cellSize * 0.5) / cellSize).floor();

    if (game.canPlace(draggedShapeId!, r, c)) {
      hoverRow = r;
      hoverCol = c;
    } else {
      hoverRow = null;
      hoverCol = null;
    }
  }

  void _triggerLineClearAnimation(List<int> rows, List<int> cols) {
    setState(() {
      flashingRows = rows.toSet();
      flashingCols = cols.toSet();
    });

    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) {
        setState(() {
          flashingRows.clear();
          flashingCols.clear();
        });
      }
    });
  }

  void _addScorePopup(int points, Offset pos) {
    final popup = ScorePopup(
      id: UniqueKey(),
      points: points,
      position: pos + const Offset(0, -40),
    );
    setState(() {
      scorePopups.add(popup);
    });

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          scorePopups.remove(popup);
        });
      }
    });
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: GameTheme.boardContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'No More Moves!',
          textAlign: TextAlign.center,
          style: GameTheme.display(
            fontSize: 24,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'SCORE',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${game.score}',
              style: GameTheme.display(
                fontSize: 44,
                color: const Color(0xFFFFE000),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: GameTheme.boardBorder,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.emoji_events,
                    color: Color(0xFFFFD200),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'BEST: $highScore',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  boardCellShapes.clear();
                  isEditMode = false;
                  hintSlot = null;
                  hintRow = null;
                  hintCol = null;
                  hintShapeId = null;
                  game.reset();
                });
                _saveState();
              },
              child: Text(
                'Play Again',
                style: GameTheme.display(fontSize: 16, color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: GameTheme.boardContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Settings',
                  style: GameTheme.display(fontSize: 20, color: Colors.white),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.refresh, color: Colors.white70),
                  title: const Text(
                    'Restart game',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    setState(() {
                      boardCellShapes.clear();
                      isEditMode = false;
                      hintSlot = null;
                      hintRow = null;
                      hintCol = null;
                      hintShapeId = null;
                      game.reset();
                    });
                    _saveState();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: const Color(0xFF00E5FF),
                  secondary: Icon(
                    isAiMode ? Icons.smart_toy : Icons.smart_toy_outlined,
                    color: isAiMode ? const Color(0xFF00E5FF) : Colors.white70,
                  ),
                  title: const Text(
                    'AI autoplay',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    isAiMode
                        ? (isAiThinking
                              ? 'Thinking…'
                              : 'Playing — ${activeAiModel ?? "ppo_block_blast_combo_best.pt"}')
                        : 'Off',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  value: isAiMode,
                  onChanged: (_) {
                    Navigator.of(ctx).pop();
                    _toggleAiMode();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    hintSlot != null
                        ? Icons.lightbulb
                        : Icons.lightbulb_outline,
                    color: hintSlot != null
                        ? const Color(0xFFFFD200)
                        : Colors.white70,
                  ),
                  title: const Text(
                    'Hint',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    hintSlot != null ? 'Showing suggestion' : 'Suggest a move',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _toggleHint();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: const Color(0xFFFF9100),
                  secondary: Icon(
                    isEditMode ? Icons.edit : Icons.edit_outlined,
                    color: isEditMode
                        ? const Color(0xFFFF9100)
                        : Colors.white70,
                  ),
                  title: const Text(
                    'Edit board',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    isEditMode ? 'Tap cells / dock to edit' : 'Off',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  value: isEditMode,
                  onChanged: (_) {
                    Navigator.of(ctx).pop();
                    _toggleEditMode();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.palette_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Theme / Skin',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    currentSkin.name,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white38,
                  ),
                  onTap: () {
                    setState(() {
                      currentSkinIndex =
                          (currentSkinIndex + 1) % GameTheme.skinThemes.length;
                    });
                    _saveState();
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [currentSkin.backgroundTop, currentSkin.backgroundBottom],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;
              final availableWidth = constraints.maxWidth;

              // Responsive scaling
              final isCompact = availableHeight < 720;
              final headerHeight = isCompact ? 135.0 : 155.0;
              final dockHeight = isCompact ? 86.0 : 108.0;
              final verticalSpacing = isCompact ? 48.0 : 64.0;

              final maxBoardFromHeight =
                  (availableHeight -
                  headerHeight -
                  dockHeight -
                  verticalSpacing);
              final maxBoardFromWidth = availableWidth - 32.0;
              final rawBoardDim = math
                  .min(maxBoardFromHeight, maxBoardFromWidth)
                  .clamp(200.0, 420.0);
              final cellSize = ((rawBoardDim - 20.0) / 8).floorToDouble();
              final boardSize = cellSize * 8 + 20.0;
              final dockCardSize = isCompact ? 76.0 : 94.0;
              final dockCellSize = isCompact ? 14.0 : 17.0;

              return Stack(
                children: [
                  Column(
                    // Reference keeps header/board/dock tightly grouped near
                    // the top with small fixed gaps between them — any
                    // leftover space on a tall screen pools below the dock
                    // as bottom margin, not as a big gap between the board
                    // and the dock (which `spaceBetween` was doing here).
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      // Block Blast Top Header & Score Area
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Crown + high score, plain on background (no pill/card).
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      '👑',
                                      style: TextStyle(fontSize: 24),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$highScore',
                                      style: GameTheme.display(
                                        fontSize: 22,
                                        color: GameTheme.scoreOrange,
                                      ),
                                    ),
                                  ],
                                ),

                                // Top Action Buttons: AI Autoplay, Hint, Edit, Settings
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        isAiMode
                                            ? Icons.smart_toy
                                            : Icons.smart_toy_outlined,
                                        color: isAiMode
                                            ? const Color(0xFF00E5FF)
                                            : Colors.white70,
                                        size: 26,
                                      ),
                                      tooltip: 'AI Autoplay',
                                      onPressed: _toggleAiMode,
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        hintSlot != null
                                            ? Icons.lightbulb
                                            : Icons.lightbulb_outline,
                                        color: hintSlot != null
                                            ? const Color(0xFFFFD200)
                                            : Colors.white70,
                                        size: 26,
                                      ),
                                      tooltip: 'Hint',
                                      onPressed: isHintLoading ? null : _toggleHint,
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        isEditMode
                                            ? Icons.edit
                                            : Icons.edit_outlined,
                                        color: isEditMode
                                            ? const Color(0xFFFF9100)
                                            : Colors.white70,
                                        size: 25,
                                      ),
                                      tooltip: 'Edit Mode',
                                      onPressed: () {
                                        setState(() {
                                          isEditMode = !isEditMode;
                                          if (isEditMode && isAiMode) isAiMode = false;
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        Icons.settings,
                                        color: GameTheme.gearIcon,
                                        size: 26,
                                      ),
                                      tooltip: 'Settings',
                                      onPressed: _showSettingsSheet,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Giant centered score with dynamic Combo Blue Diamond Badge
                          Padding(
                            padding: EdgeInsets.only(
                              top: isCompact ? 2 : 4,
                              bottom: isCompact ? 4 : 8,
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                AnimatedOpacity(
                                  opacity: game.combo > 0 ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 300),
                                  child: CustomPaint(
                                    size: Size(
                                      isCompact ? 80 : 96,
                                      isCompact ? 80 : 96,
                                    ),
                                    painter: ComboShieldPainter(
                                      color: GameTheme.getComboShieldColor(
                                        game.combo,
                                      ),
                                      combo: game.combo,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${game.score}',
                                  style: GameTheme.display(
                                    fontSize: isCompact ? 44 : 56,
                                    color: Colors.white,
                                    shadows: const [
                                      Shadow(
                                        color: Color(0x88000000),
                                        blurRadius: 12,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(
                            height: isCompact ? 22 : 26,
                            child: Center(
                              child: isEditMode
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFFF9100,
                                        ).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(
                                            0xFFFF9100,
                                          ).withValues(alpha: 0.5),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.touch_app,
                                            size: 13,
                                            color: Color(0xFFFF9100),
                                          ),
                                          SizedBox(width: 5),
                                          Text(
                                            'Tap cells to toggle • Tap dock to cycle shape',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFFF9100),
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : (isAiMode
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.4,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: const Color(
                                                0xFF00E5FF,
                                              ).withValues(alpha: 0.45),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            '🤖 ${activeAiModel ?? "ppo_block_blast_combo_best.pt"}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF00E5FF),
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink()),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: isCompact ? 8 : 16),

                      // 8x8 Board Container
                      Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeInOut,
                          key: _boardKey,
                          width: boardSize,
                          height: boardSize,
                          padding: const EdgeInsets.all(6.0),
                          decoration: BoxDecoration(
                            color: currentSkin.boardContainer,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: game.combo >= 2
                                  ? const Color(0xFFE040FB)
                                  : currentSkin.boardBorder,
                              width: game.combo >= 2 ? 2.5 : 2.0,
                            ),
                            boxShadow: [
                              if (game.combo >= 2)
                                BoxShadow(
                                  color: const Color(
                                    0xFFE040FB,
                                  ).withValues(alpha: 0.45),
                                  blurRadius: 24,
                                  spreadRadius: 2,
                                ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              // Flat fill + faint hairline grid (the real board
                              // is not per-cell embossed, see design doc §4).
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: const BoardGridPainter(),
                                ),
                              ),

                              // 8x8 Grid of 3D Blocks / Empty Slots
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(8, (r) {
                                  final isRowFlashing = flashingRows.contains(
                                    r,
                                  );
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: List.generate(8, (c) {
                                      final isColFlashing = flashingCols
                                          .contains(c);
                                      final bitIdx = r * 8 + c;
                                      final isBitFilled =
                                          ((game.board >> bitIdx) & 1) == 1;

                                      // Line Clear Laser Flash & Implosion Animation
                                      if (isRowFlashing || isColFlashing) {
                                        return TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0.0, end: 1.0),
                                          duration: const Duration(
                                            milliseconds: 260,
                                          ),
                                          builder: (context, val, child) {
                                            // Stage 1 (0 -> 0.4): Flash white + expand slightly (scale 1.0 -> 1.15)
                                            // Stage 2 (0.4 -> 1.0): Implode to center (scale 1.15 -> 0.0)
                                            final scale = val < 0.4
                                                ? 1.0 + (val / 0.4) * 0.15
                                                : (1.0 - (val - 0.4) / 0.6) *
                                                      1.15;
                                            final flashAlpha = (1.0 - val)
                                                .clamp(0.0, 1.0);

                                            return Transform.scale(
                                              scale: scale.clamp(0.0, 1.2),
                                              child: SizedBox(
                                                width: cellSize,
                                                height: cellSize,
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    2.0,
                                                  ),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: flashAlpha,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha:
                                                                    flashAlpha *
                                                                    0.9,
                                                              ),
                                                          blurRadius: 10,
                                                          spreadRadius: 2,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      }

                                      // Occupied or Empty Cell with Edit Mode Tap Interaction
                                      Widget cellWidget;
                                      if (isBitFilled) {
                                        final colorIdx =
                                            boardCellShapes[bitIdx] ??
                                            (r + c) %
                                                GameTheme.colorStyles.length;
                                        cellWidget = SizedBox(
                                          width: cellSize,
                                          height: cellSize,
                                          child: TweenAnimationBuilder<double>(
                                            key: ValueKey(
                                              'placed_${bitIdx}_$colorIdx',
                                            ),
                                            tween: Tween(begin: 0.88, end: 1.0),
                                            duration: const Duration(
                                              milliseconds: 140,
                                            ),
                                            curve: Curves.easeOutBack,
                                            builder: (context, scale, child) {
                                              return Transform.scale(
                                                scale: scale,
                                                child: child,
                                              );
                                            },
                                            child: BlockWidget(
                                              size: cellSize,
                                              colorIndex: colorIdx,
                                            ),
                                          ),
                                        );
                                      } else {
                                        cellWidget = SizedBox(
                                          width: cellSize,
                                          height: cellSize,
                                          child: BlockWidget(
                                            size: cellSize,
                                            isEmpty: true,
                                          ),
                                        );
                                      }

                                      if (isEditMode) {
                                        return GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _toggleBoardCell(r, c),
                                          child: Container(
                                            width: cellSize,
                                            height: cellSize,
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: isBitFilled
                                                    ? Colors.white30
                                                    : Colors.white.withValues(
                                                        alpha: 0.15,
                                                      ),
                                                width: 0.75,
                                              ),
                                            ),
                                            child: cellWidget,
                                          ),
                                        );
                                      }
                                      return cellWidget;
                                    }),
                                  );
                                }),
                              ),

                              // Real-Time Ghost Preview Overlay
                              if (draggedShapeId != null &&
                                  hoverRow != null &&
                                  hoverCol != null)
                                Positioned(
                                  top: (hoverRow! * cellSize).toDouble(),
                                  left: (hoverCol! * cellSize).toDouble(),
                                  child: IgnorePointer(
                                    child: PieceWidget(
                                      shape: allShapes[draggedShapeId!],
                                      cellSize: cellSize,
                                      colorIndex: _dockColorIndex(
                                        draggedSlot!,
                                        draggedShapeId!,
                                      ),
                                      isGhost: true,
                                    ),
                                  ),
                                ),

                              // AI Target Ghost Preview Overlay
                              if (isAiMode &&
                                  aiHighlightSlot != null &&
                                  aiHighlightRow != null &&
                                  aiHighlightCol != null &&
                                  game.dock[aiHighlightSlot!] >= 0)
                                Positioned(
                                  top: (aiHighlightRow! * cellSize).toDouble(),
                                  left: (aiHighlightCol! * cellSize).toDouble(),
                                  child: IgnorePointer(
                                    child: PieceWidget(
                                      shape:
                                          allShapes[game
                                              .dock[aiHighlightSlot!]],
                                      cellSize: cellSize,
                                      colorIndex: _dockColorIndex(
                                        aiHighlightSlot!,
                                        game.dock[aiHighlightSlot!],
                                      ),
                                      isGhost: true,
                                    ),
                                  ),
                                ),

                              // Player Hint Target Highlight Overlay
                              if (!isAiMode &&
                                  hintSlot != null &&
                                  hintRow != null &&
                                  hintCol != null &&
                                  hintShapeId != null &&
                                  hintSlot! < game.dock.length &&
                                  game.dock[hintSlot!] >= 0)
                                Positioned(
                                  top: (hintRow! * cellSize).toDouble(),
                                  left: (hintCol! * cellSize).toDouble(),
                                  child: IgnorePointer(
                                    child: AnimatedBuilder(
                                      animation: _hintPulseAnimation,
                                      builder: (context, child) {
                                        final pulse = _hintPulseAnimation.value;
                                        return Transform.scale(
                                          scale: 1.0 + 0.04 * pulse,
                                          child: Opacity(
                                            opacity: 0.70 + 0.30 * pulse,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                boxShadow: [
                                                  BoxShadow(
                                                    color:
                                                        const Color(
                                                          0xFFFFD200,
                                                        ).withValues(
                                                          alpha:
                                                              0.35 +
                                                              0.30 * pulse,
                                                        ),
                                                    blurRadius: 12 + 6 * pulse,
                                                    spreadRadius: 1 + 2 * pulse,
                                                  ),
                                                ],
                                              ),
                                              child: PieceWidget(
                                                shape: allShapes[hintShapeId!],
                                                cellSize: cellSize,
                                                colorIndex: _dockColorIndex(
                                                  hintSlot!,
                                                  hintShapeId!,
                                                ),
                                                isHint: true,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),

                              // "Combo N" / compliment-word callout: outlined
                              // text straight over the board, no background chip.
                              if (activeCheer != null)
                                Positioned.fill(
                                  child: Center(
                                    child: IgnorePointer(
                                      child: TweenAnimationBuilder<double>(
                                        key: cheerKey,
                                        tween: Tween(begin: 0.0, end: 1.0),
                                        duration: const Duration(
                                          milliseconds: 850,
                                        ),
                                        curve: Curves.easeOutBack,
                                        builder: (context, val, child) {
                                          final scale = val < 0.30
                                              ? 0.5 + (val / 0.30) * 0.75
                                              : 1.25 - (val - 0.30) * 0.36;
                                          final opacity =
                                              (1.0 -
                                                      (val > 0.65
                                                          ? (val - 0.65) / 0.35
                                                          : 0.0))
                                                  .clamp(0.0, 1.0);
                                          final dy = -26.0 * val;
                                          final cheerFontSize = isCompact
                                              ? 30.0
                                              : 38.0;

                                          Widget label;
                                          if (activeCheer!.startsWith(
                                            'COMBO:',
                                          )) {
                                            final n = activeCheer!.substring(6);
                                            label = Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                OutlinedText(
                                                  text: 'Combo',
                                                  fontSize: cheerFontSize,
                                                  fillColor: const Color(
                                                    0xFFEAF6FF,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                OutlinedText(
                                                  text: n,
                                                  fontSize:
                                                      cheerFontSize * 1.15,
                                                  fillColor: activeCheerColor,
                                                ),
                                              ],
                                            );
                                          } else {
                                            label = OutlinedText(
                                              text: activeCheer!,
                                              fontSize: cheerFontSize,
                                              fillColor: activeCheerColor,
                                            );
                                          }

                                          return Opacity(
                                            opacity: opacity,
                                            child: Transform.translate(
                                              offset: Offset(0, dy),
                                              child: Transform.scale(
                                                scale: scale,
                                                child: Transform.rotate(
                                                  angle: -0.05,
                                                  child: label,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: isCompact ? 8 : 16),

                      // 3 Dock Slots at Bottom (Clean transparent layout matching official game)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: isCompact ? 4 : 10,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(3, (slot) {
                            final sid = game.dock[slot];
                            if (sid < 0) {
                              return SizedBox(
                                width: dockCardSize,
                                height: dockCardSize,
                              );
                            }
                            final shape = allShapes[sid];
                            final isBeingDragged = draggedSlot == slot;
                            final isHintSlot = !isAiMode && hintSlot == slot;

                            return GestureDetector(
                              onTap: isEditMode
                                  ? () => _cycleDockPiece(slot)
                                  : null,
                              onLongPress: isEditMode
                                  ? () => _showShapePickerSheet(slot)
                                  : null,
                              onPanStart: isEditMode
                                  ? null
                                  : (details) => _onPanStart(slot, details),
                              onPanUpdate: isEditMode ? null : _onPanUpdate,
                              onPanEnd: isEditMode ? null : _onPanEnd,
                              child: Opacity(
                                opacity: isBeingDragged ? 0.0 : 1.0,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      width: dockCardSize,
                                      height: dockCardSize,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border:
                                            (isAiMode &&
                                                aiHighlightSlot == slot)
                                            ? Border.all(
                                                color: const Color(0xFF00E5FF),
                                                width: 2.5,
                                              )
                                            : isHintSlot
                                            ? Border.all(
                                                color: const Color(0xFFFFD200),
                                                width: 2.8,
                                              )
                                            : isEditMode
                                            ? Border.all(
                                                color: const Color(0xFFFF9100),
                                                width: 2.2,
                                              )
                                            : null,
                                        boxShadow:
                                            (isAiMode &&
                                                aiHighlightSlot == slot)
                                            ? [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFF00E5FF,
                                                  ).withValues(alpha: 0.5),
                                                  blurRadius: 14,
                                                  spreadRadius: 2,
                                                ),
                                              ]
                                            : isHintSlot
                                            ? [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFFFFD200,
                                                  ).withValues(alpha: 0.6),
                                                  blurRadius: 14,
                                                  spreadRadius: 2,
                                                ),
                                              ]
                                            : isEditMode
                                            ? [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFFFF9100,
                                                  ).withValues(alpha: 0.4),
                                                  blurRadius: 10,
                                                  spreadRadius: 1,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Center(
                                        child: PieceWidget(
                                          shape: shape,
                                          cellSize: dockCellSize,
                                          colorIndex: _dockColorIndex(
                                            slot,
                                            sid,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (isHintSlot)
                                      Positioned(
                                        top: -9,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFD200),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black45,
                                                blurRadius: 4,
                                                offset: Offset(0, 1.5),
                                              ),
                                            ],
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.lightbulb,
                                                size: 10,
                                                color: Colors.black87,
                                              ),
                                              SizedBox(width: 3),
                                              Text(
                                                'HINT',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.black87,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else if (isEditMode)
                                      Positioned(
                                        top: -9,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF9100),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black45,
                                                blurRadius: 4,
                                                offset: Offset(0, 1.5),
                                              ),
                                            ],
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.touch_app,
                                                size: 10,
                                                color: Colors.black87,
                                              ),
                                              SizedBox(width: 2),
                                              Text(
                                                'CYCLE',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.black87,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      SizedBox(height: isCompact ? 4 : 8),
                    ],
                  ),

                  // Floating Dragged Piece: Scales to full board cellSize and floats 65px above finger
                  if (draggedShapeId != null && dragPosition != null)
                    Positioned(
                      left:
                          dragPosition!.dx -
                          (allShapes[draggedShapeId!].w * cellSize) / 2,
                      top:
                          dragPosition!.dy -
                          65 -
                          (allShapes[draggedShapeId!].h * cellSize) / 2,
                      child: IgnorePointer(
                        child: Transform.scale(
                          scale: 1.05,
                          child: PieceWidget(
                            shape: allShapes[draggedShapeId!],
                            cellSize: cellSize,
                            colorIndex: _dockColorIndex(
                              draggedSlot!,
                              draggedShapeId!,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Floating Score Delta Popups with Authentic Physics
                  ...scorePopups.map((popup) {
                    return TweenAnimationBuilder<double>(
                      key: popup.id,
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeOutCubic,
                      builder: (context, val, child) {
                        final scale = val < 0.25
                            ? 0.6 + (val / 0.25) * 0.65
                            : 1.25 - (val - 0.25) * 0.33;
                        final opacity =
                            (1.0 - (val > 0.55 ? (val - 0.55) / 0.45 : 0.0))
                                .clamp(0.0, 1.0);
                        final dy = -48.0 * val;

                        return Positioned(
                          left: popup.position.dx - 35,
                          top: popup.position.dy + dy,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: opacity,
                              child: Transform.scale(
                                scale: scale,
                                child: Text(
                                  '+${popup.points}',
                                  style: GameTheme.display(
                                    fontSize: 32,
                                    color: const Color(0xFFFFE000),
                                    shadows: const [
                                      Shadow(
                                        color: Color(0xAA000000),
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class ScorePopup {
  final Key id;
  final int points;
  final Offset position;

  ScorePopup({required this.id, required this.points, required this.position});
}
