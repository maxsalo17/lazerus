import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/control/presentation/hold_value_control.dart';

void main() {
  testWidgets(
    'anchors the rounded popup to its control and adjusts from the start value',
    (tester) async {
      final previews = <double>[];
      double? committed;
      const controlKey = Key('hold-control');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HoldValueControl(
                key: controlKey,
                kind: HoldValueKind.brightness,
                value: 0.5,
                label: '50%',
                onPreview: previews.add,
                onCommit: (value) => committed = value,
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(controlKey)),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final controlRect = tester.getRect(find.byKey(controlKey));
      final popupRect = tester.getRect(
        find.byKey(const Key('hold-value-popup')),
      );
      expect(popupRect.center.dx, closeTo(controlRect.center.dx, 0.1));
      expect(popupRect.bottom, lessThanOrEqualTo(controlRect.top));
      expect(find.byKey(const Key('hold-value-gradient')), findsOneWidget);

      await gesture.moveBy(const Offset(0, 80));
      await tester.pump();
      expect(
        previews,
        isEmpty,
        reason: 'Vertical motion must not affect value.',
      );

      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(previews.single, closeTo(0.5 + 80 / 240, 0.01));

      await gesture.up();
      await tester.pump();

      expect(committed, closeTo(0.5 + 80 / 240, 0.01));
      expect(find.byKey(const Key('hold-value-popup')), findsNothing);
    },
  );
}
