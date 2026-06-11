/// PollWheel — a cosmetic spinning wheel for a closed weighted_random poll. The
/// winner is already decided server-side; this just animates a pointer landing
/// on the winning slice. Slice sizes are proportional to each option's votes.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class PollWheel extends StatefulWidget {
  const PollWheel({
    super.key,
    required this.labels,
    required this.weights,
    required this.winnerIndex,
    this.size = 220,
  });

  final List<String> labels;
  final List<int> weights;
  final int winnerIndex;
  final double size;

  @override
  State<PollWheel> createState() => _PollWheelState();
}

class _PollWheelState extends State<PollWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _turns;

  static const _palette = [
    AppColors.violet,
    AppColors.blue,
    AppColors.teal,
    AppColors.coral,
    AppColors.yellow,
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600));

    // Final rotation so the winning slice's centre lands under the top pointer.
    // Defensive against bad inputs (zero total, out-of-range winner) so a
    // rebuild during scroll can never index past the list or divide by zero.
    final total = widget.weights.fold<int>(0, (a, b) => a + b);
    final n = widget.weights.length;
    final winner =
        (widget.winnerIndex >= 0 && widget.winnerIndex < n) ? widget.winnerIndex : 0;
    double target = 4; // a few full turns even if we can't compute a slice
    if (total > 0 && n > 0) {
      double startFraction = 0;
      for (var i = 0; i < winner; i++) {
        startFraction += widget.weights[i] / total;
      }
      final winnerMidFraction =
          startFraction + (widget.weights[winner] / total) / 2;
      // Slices are painted from the TOP, sweeping clockwise; a positive
      // rotation is also clockwise. The winner's mid sits winnerMidFraction
      // turns past the pointer, so spin (1 - winnerMidFraction) extra turns
      // (plus full turns for show) to bring it back under the pointer.
      target = 4 + (1 - winnerMidFraction);
    }
    _turns = Tween<double>(begin: 0, end: target).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.weights.fold<int>(0, (a, b) => a + b);
    return SizedBox(
      width: widget.size,
      height: widget.size + 16,
      child: Column(
        children: [
          // Pointer.
          const Icon(Icons.arrow_drop_down, color: AppColors.ink, size: 28),
          Expanded(
            child: AnimatedBuilder(
              animation: _turns,
              builder: (context, child) => Transform.rotate(
                angle: _turns.value * 2 * math.pi,
                child: child,
              ),
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _WheelPainter(
                  weights: widget.weights,
                  total: total == 0 ? 1 : total,
                  colors: _palette,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(
      {required this.weights, required this.total, required this.colors});
  final List<int> weights;
  final int total;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2;
    double start = -math.pi / 2; // start at top
    for (var i = 0; i < weights.length; i++) {
      final sweep = (weights[i] / total) * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = colors[i % colors.length];
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }
    // Hub.
    canvas.drawCircle(center, radius * 0.12,
        Paint()..color = AppColors.surface);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.weights != weights || old.total != total;
}
