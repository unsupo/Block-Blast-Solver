import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'bitboard.dart';

class AiPrediction {
  final bool valid;
  final int action;
  final int slot;
  final int row;
  final int col;
  final int shapeId;
  final String model;

  const AiPrediction({
    required this.valid,
    required this.action,
    required this.slot,
    required this.row,
    required this.col,
    required this.shapeId,
    required this.model,
  });
}

class AiClient {
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2);
  static bool _spawning = false;

  static Future<AiPrediction?> getBestMove({
    required int board,
    required List<int> dock,
    required int combo,
  }) async {
    try {
      final request = await _client.postUrl(
        Uri.parse('http://127.0.0.1:8765/predict'),
      );
      request.headers.contentType = ContentType.json;

      final unsignedBoardStr = BigInt.from(board).toUnsigned(64).toString();
      final body = utf8.encode(
        jsonEncode({'board': unsignedBoardStr, 'dock': dock, 'combo': combo}),
      );
      request.contentLength = body.length;
      request.add(body);

      final response = await request.close();
      if (response.statusCode == 200) {
        final respStr = await response.transform(utf8.decoder).join();
        final json = jsonDecode(respStr) as Map<String, dynamic>;
        if (json['valid'] == true) {
          return AiPrediction(
            valid: true,
            action: json['action'] as int,
            slot: json['slot'] as int,
            row: json['row'] as int,
            col: json['col'] as int,
            shapeId: json['shape_id'] as int? ?? -1,
            model: json['model'] as String? ?? 'best',
          );
        }
      }
    } catch (_) {
      _ensureDaemon();
    }

    // High-performance on-device 3-ply engine (zero network required, works offline on phone)
    final localAction = BitboardGame.getBestActionFromState(board, dock, combo);
    if (localAction >= 0) {
      final slot = localAction ~/ 64;
      final cell = localAction % 64;
      return AiPrediction(
        valid: true,
        action: localAction,
        slot: slot,
        row: cell ~/ 8,
        col: cell % 8,
        shapeId: (slot >= 0 && slot < dock.length) ? dock[slot] : -1,
        model: 'On-Device 3-Ply (300k+ Engine)',
      );
    }
    return null;
  }

  static void _ensureDaemon() {
    if (_spawning) return;
    _spawning = true;
    Process.start('/tmp/venv/bin/python3', [
          '/Users/jonathanarndt/dev/block_blast/ai_service.py',
        ])
        .then((_) {
          _spawning = false;
        })
        .catchError((_) {
          _spawning = false;
        });
  }
}
