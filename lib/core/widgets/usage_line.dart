import 'package:flutter/material.dart';

class UsageLine extends StatelessWidget {
  const UsageLine({
    required this.label,
    required this.value,
    required this.text,
    this.isLoading = false,
    super.key,
  });

  final String label;
  final double value;
  final String text;
  final bool isLoading;

  static const double _edgeTextWidth = 128;
  static const double _rightAlignedBreakpoint = 520;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final alignRight = constraints.maxWidth < _rightAlignedBreakpoint;

        return Column(
          children: [
            Row(
              children: [
                if (alignRight)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          (constraints.maxWidth - 12).clamp(
                            0,
                            double.infinity,
                          ) /
                          2,
                    ),
                    child: _label(),
                  )
                else
                  SizedBox(width: _edgeTextWidth, child: _label()),
                const SizedBox(width: 12),
                Expanded(
                  child: isLoading
                      ? _InlineUsageLoadingIndicator(alignRight: alignRight)
                      : Text(
                          text,
                          textAlign: alignRight
                              ? TextAlign.right
                              : TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                if (!alignRight) const SizedBox(width: _edgeTextWidth),
              ],
            ),
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: isLoading
                  ? null
                  : (value.isFinite ? value.clamp(0, 1) : 0),
            ),
          ],
        );
      },
    );
  }

  Widget _label() => Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
}

class _InlineUsageLoadingIndicator extends StatelessWidget {
  const _InlineUsageLoadingIndicator({required this.alignRight});

  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 72),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 3,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}
