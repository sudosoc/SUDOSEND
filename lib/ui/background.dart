import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Slowly drifting neon orbs over a faint cyber grid — the backdrop the
/// glass surfaces blur.
class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 26))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _BackgroundPainter(_controller), child: const SizedBox.expand()),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bgTop, AppColors.bgBottom],
        ).createShader(rect),
    );

    final t = animation.value * 2 * pi;
    final s = size.shortestSide;

    void orb(Color color, double x, double y, double r, double alpha) {
      final center = Offset(x * size.width, y * size.height);
      final radius = r * s;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    orb(AppColors.violet, 0.18 + 0.08 * sin(t), 0.16 + 0.06 * cos(t), 0.85, 0.42);
    orb(AppColors.cyan, 0.88 + 0.07 * cos(t + 1.3), 0.42 + 0.10 * sin(t + 1.3), 0.75, 0.32);
    orb(AppColors.pink, 0.30 + 0.10 * sin(t + 2.6), 0.98 + 0.05 * cos(t + 2.6), 0.65, 0.26);

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1;
    const step = 42.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) => false;
}
