import 'package:flutter/material.dart';

import 'theme.dart';

/// Flat obsidian with one faint accent bloom at the top. Static on purpose:
/// no moving backdrop to redraw, nothing competing with the content.
class AnimatedBackground extends StatelessWidget {
  const AnimatedBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child:
          CustomPaint(painter: _BackgroundPainter(), child: SizedBox.expand()),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = AppColors.bgTop);
    final center = Offset(size.width * 0.5, -size.shortestSide * 0.15);
    final radius = size.shortestSide * 0.95;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.11),
            AppColors.accent.withValues(alpha: 0)
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) => false;
}
