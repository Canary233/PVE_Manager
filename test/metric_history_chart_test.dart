import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/core/widgets/cpu_history_chart.dart';
import 'package:pve_manager/core/widgets/usage_line.dart';

String _label(double value) => value.round().toString();

void main() {
  testWidgets('chart paints within narrow constraints', (tester) async {
    await tester.pumpWidget(_chart(width: 48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart handles invalid samples and an infinite scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _chart(
        values: const [
          double.nan,
          double.infinity,
          double.negativeInfinity,
          -2,
          1,
        ],
        maxValue: double.infinity,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('identical chart data does not request a repaint', (
    tester,
  ) async {
    await tester.pumpWidget(_chart(values: [0.2, 0.4]));
    final original = _painter(tester);
    await tester.pumpWidget(_chart(values: [0.2, 0.4]));

    expect(_painter(tester).shouldRepaint(original), isFalse);
  });

  testWidgets('chart retains a snapshot when the input list is mutated', (
    tester,
  ) async {
    final values = [0.2, 0.4];
    await tester.pumpWidget(_chart(values: values, maxValue: 1));
    final original = _painter(tester);
    values[0] = 0.8;
    await tester.pumpWidget(_chart(values: values, maxValue: 1));

    expect(_painter(tester).shouldRepaint(original), isTrue);
  });

  testWidgets('chart repaints when the label style changes', (tester) async {
    await tester.pumpWidget(_chart());
    final original = _painter(tester);
    await tester.pumpWidget(
      _chart(
        theme: ThemeData(
          textTheme: const TextTheme(labelSmall: TextStyle(fontSize: 15)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_painter(tester).shouldRepaint(original), isTrue);
  });

  testWidgets(
    'short usage labels keep the value aligned to the trailing edge',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: UsageLine(label: 'CPU', value: 0.5, text: '50%'),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getBottomRight(find.text('50%')).dx,
        tester.getBottomRight(find.byType(LinearProgressIndicator)).dx,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long usage labels fit compact layouts', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 140,
              child: UsageLine(
                label: 'A long translated memory usage label',
                value: double.nan,
                text: '1 / 2 GiB',
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
  });
}

Widget _chart({
  double width = 400,
  List<double> values = const [0.2, 0.4],
  double? maxValue,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: MetricHistoryChart(
          values: values,
          timestamps: [1700000000, 1700000060],
          valueLabelBuilder: _label,
          maxValue: maxValue,
        ),
      ),
    ),
  ),
);

CustomPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.descendant(
        of: find.byType(MetricHistoryChart),
        matching: find.byType(CustomPaint),
      ),
    )
    .painter!;
