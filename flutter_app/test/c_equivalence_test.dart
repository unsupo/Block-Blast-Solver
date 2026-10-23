import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bitboard.dart';

void main() {
  test(
    'BitboardGame Dart engine 100% matches C++ native engine across all steps',
    () async {
      final file = File('/tmp/c_audit_trace.json');
      expect(file.existsSync(), true, reason: 'Trace file must exist');

      final jsonStr = await file.readAsString();
      final List<dynamic> trace = jsonDecode(jsonStr);

      int verifiedSteps = 0;
      int lineClearEvents = 0;

      final game = BitboardGame();

      for (final rawStep in trace) {
        final step = rawStep as Map<String, dynamic>;
        final int slot = step['slot'] as int;
        final int row = step['row'] as int;
        final int col = step['col'] as int;

        // Set game state before move
        final BigInt bBeforeBig = BigInt.parse(step['board_before'] as String);
        game.board = bBeforeBig.toSigned(64).toInt();
        final List<dynamic> rawDockBefore =
            step['dock_before'] as List<dynamic>;
        game.dock = rawDockBefore.map((e) => e as int).toList();
        game.score = step['score_before'] as int;
        game.combo = step['combo_before'] as int;
        game.isGameOver = false;

        // Perform placement in Dart engine
        final res = game.place(slot, row, col);
        expect(
          res,
          isNotNull,
          reason:
              'Valid C++ move must be valid in Dart at ep ${step['ep']} step ${step['step']}',
        );

        // 1. Verify points earned
        expect(
          res!.points,
          equals(step['points_earned'] as int),
          reason: 'Points mismatch at ep ${step['ep']} step ${step['step']}',
        );

        // 2. Verify score
        expect(
          game.score,
          equals(step['score_after'] as int),
          reason: 'Score mismatch at ep ${step['ep']} step ${step['step']}',
        );

        // 3. Verify combo
        expect(
          game.combo,
          equals(step['combo_after'] as int),
          reason: 'Combo mismatch at ep ${step['ep']} step ${step['step']}',
        );

        // 4. Verify resulting 64-bit board bitmask
        final String dartBoardStr = BigInt.from(
          game.board,
        ).toUnsigned(64).toString();
        final String expectedBoardStr = BigInt.parse(
          step['board_after'] as String,
        ).toUnsigned(64).toString();
        expect(
          dartBoardStr,
          equals(expectedBoardStr),
          reason:
              'Board bitboard mismatch at ep ${step['ep']} step ${step['step']}',
        );

        if (res.linesCleared > 0) {
          lineClearEvents++;
        }

        verifiedSteps++;
      }

      // ignore: avoid_print
      print(
        'Successfully verified $verifiedSteps steps with $lineClearEvents line-clearing events!',
      );
      expect(verifiedSteps, greaterThan(300));
      expect(lineClearEvents, greaterThan(15));
    },
  );
}
