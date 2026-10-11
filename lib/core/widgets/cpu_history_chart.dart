import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:pve_manager/core/l10n/l10n_extensions.dart';
import 'package:pve_manager/data/models/node_rrd_point.dart';
import 'package:pve_manager/core/utils/formatters.dart';

class CpuHistoryChart extends StatelessWidget {
  const CpuHistoryChart({required this.points, super.key});

  final List<NodeRrdPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxValue = points
        .map((point) => point.cpu)
        .fold<double>(0, (max, value) => value > max ? value : max)
        .clamp(0.08, 1)
        .toDouble();

    return MetricHistoryChart(
      values: points.map((point) => point.cpu).toList(),
      timestamps: points.map((point) => point.time).toList(),
      maxValue: maxValue,
      valueLabelBuilder: percent,
    );
  }
}

class MetricHistoryChart extends StatelessWidget {
  const MetricHistoryChart({
    required this.values,
    required this.valueLabelBuilder,
    this.timestamps = const <int>[],
    this.maxValue,
    this.lineColor,
    this.fillColor,
    super.key,
  });

  final List<double> values;
  final List<int> timestamps;
  final String Function(double value) valueLabelBuilder;
  final double? maxValue;
  final Color? lineColor;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            context.l10n.noData,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final chartValues = List<double>.unmodifiable(
      values.map((value) => value.isFinite && value >= 0 ? value : 0.0),
    );
    final computedMaxValue = chartValues.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );
    final requestedMaxValue = maxValue;
    final visibleMaxValue =
        (requestedMaxValue != null && requestedMaxValue.isFinite
                ? requestedMaxValue
                : computedMaxValue)
            .clamp(0.0001, double.infinity);
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 210,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _MetricHistoryPainter(
            values: chartValues,
            timestamps: List<int>.unmodifiable(timestamps),
            maxValue: visibleMaxValue,
            valueLabelBuilder: valueLabelBuilder,
            lineColor: lineColor ?? colorScheme.primary,
            fillColor:
                fillColor ??
                (lineColor ?? colorScheme.primary).withValues(alpha: 0.2),
            gridColor: colorScheme.outlineVariant.withValues(alpha: 0.8),
            labelColor: colorScheme.onSurfaceVariant,
            textStyle: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}

class _MetricHistoryPainter extends CustomPainter {
  const _MetricHistoryPainter({
    required this.values,
    required this.timestamps,
    required this.maxValue,
    required this.valueLabelBuilder,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.labelColor,
    required this.textStyle,
  });

  final List<double> values;
  final List<int> timestamps;
  final double maxValue;
  final String Function(double value) valueLabelBuilder;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color labelColor;
  final TextStyle? textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final compact = size.width < 360;
    const bottomPadding = 46.0;
    const topPadding = 12.0;
    final rightPadding = compact ? 2.0 : 10.0;
    const horizontalLines = 4;
    final leftPadding = compact ? 38.0 : 46.0;

    final chartRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      size.width - leftPadding - rightPadding,
      size.height - topPadding - bottomPadding,
    );
    if (chartRect.width <= 0 || chartRect.height <= 0) {
      return;
    }

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= horizontalLines; i++) {
      final y = chartRect.top + chartRect.height * i / horizontalLines;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );

      final value = maxValue * (1 - i / horizontalLines);
      _drawYAxisLabel(
        canvas,
        chartRect,
        y,
        valueLabelBuilder(value),
        compact: compact,
      );
    }

    for (var i = 0; i <= 6; i++) {
      final x = chartRect.left + chartRect.width * i / 6;
      canvas.drawLine(
        Offset(x, chartRect.top),
        Offset(x, chartRect.bottom),
        gridPaint,
      );
    }
    _drawXAxisLabels(canvas, chartRect, compact: compact);

    final path = Path();
    final fillPath = Path();
    final singlePoint = values.length == 1;
    for (var i = 0; i < values.length; i++) {
      final x = singlePoint
          ? chartRect.left
          : chartRect.left + chartRect.width * i / (values.length - 1);
      final ratio = (values[i] / maxValue).clamp(0, 1).toDouble();
      final y = chartRect.bottom - ratio * chartRect.height;
      final point = Offset(x, y);

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
        fillPath.moveTo(point.dx, chartRect.bottom);
        fillPath.lineTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
        fillPath.lineTo(point.dx, point.dy);
      }
    }

    if (singlePoint) {
      final y =
          chartRect.bottom -
          (values.first / maxValue).clamp(0, 1) * chartRect.height;
      path.lineTo(chartRect.right, y);
      fillPath.lineTo(chartRect.right, y);
    }

    fillPath.lineTo(chartRect.right, chartRect.bottom);
    fillPath.close();

    canvas.save();
    canvas.clipRect(chartRect);
    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  void _drawYAxisLabel(
    Canvas canvas,
    Rect chartRect,
    double centerY,
    String text, {
    required bool compact,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style:
            textStyle?.copyWith(
              color: labelColor,
              fontSize: compact ? 10 : textStyle?.fontSize,
            ) ??
            TextStyle(color: labelColor, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: chartRect.left - 8);
    try {
      final y = (centerY - painter.height / 2).clamp(
        0,
        math.max(0, chartRect.bottom - painter.height),
      );
      final offset = Offset(chartRect.left - 8 - painter.width, y.toDouble());
      painter.paint(canvas, offset);
    } finally {
      painter.dispose();
    }
  }

  void _drawXAxisLabels(
    Canvas canvas,
    Rect chartRect, {
    required bool compact,
  }) {
    if (timestamps.isEmpty) {
      return;
    }

    final labelIndexes = _xAxisLabelIndexes();
    for (final index in labelIndexes) {
      final timestampSeconds = timestamps[index];
      if (timestampSeconds <= 0 || timestampSeconds > 8640000000000) {
        continue;
      }

      final ratio = timestamps.length == 1
          ? 0.5
          : index / (timestamps.length - 1);
      final x = chartRect.left + chartRect.width * ratio;
      final text = _timeLabel(timestampSeconds);
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style:
              textStyle?.copyWith(
                color: labelColor,
                fontSize: compact ? 10 : textStyle?.fontSize,
              ) ??
              TextStyle(color: labelColor, fontSize: compact ? 10 : 11),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        textAlign: TextAlign.center,
      )..layout(maxWidth: math.min(compact ? 46 : 58, chartRect.width));
      try {
        final left = (x - painter.width / 2).clamp(
          chartRect.left,
          math.max(chartRect.left, chartRect.right - painter.width),
        );
        painter.paint(canvas, Offset(left.toDouble(), chartRect.bottom + 8));
      } finally {
        painter.dispose();
      }
    }
  }

  List<int> _xAxisLabelIndexes() {
    final lastIndex = timestamps.length - 1;
    if (lastIndex <= 0) {
      return const <int>[0];
    }
    return <int>{0, lastIndex ~/ 2, lastIndex}.toList()..sort();
  }

  String _timeLabel(int seconds) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)}\n'
        '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
  }

  @override
  bool shouldRepaint(covariant _MetricHistoryPainter oldDelegate) {
    return !listEquals(oldDelegate.values, values) ||
        !listEquals(oldDelegate.timestamps, timestamps) ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.valueLabelBuilder != valueLabelBuilder;
  }
}
