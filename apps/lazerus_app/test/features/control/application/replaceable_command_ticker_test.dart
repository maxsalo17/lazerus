import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/control/application/replaceable_command_ticker.dart';

void main() {
  test(
    'coalesces stale values while a write is in flight and flushes the last',
    () async {
      final emitted = <int>[];
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final ticker = ReplaceableCommandTicker<int>(
        interval: const Duration(milliseconds: 5),
        onEmit: (value) async {
          emitted.add(value);
          if (value == 1) {
            firstStarted.complete();
            await releaseFirst.future;
          }
        },
      );

      ticker.push(1);
      await firstStarted.future;
      ticker.push(2);
      ticker.push(3);
      releaseFirst.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emitted, <int>[1, 3]);

      ticker.push(4);
      await ticker.flush();
      expect(emitted, <int>[1, 3, 4]);
      ticker.dispose();
    },
  );
}
