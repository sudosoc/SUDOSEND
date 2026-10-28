import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Animated radar: rotating sweep, expanding pulse, and a blip per nearby device.
class Radar extends StatefulWidget {
  const Radar({super.key, this.size = 240, this.blips = const [], this.center});

  final double size;
  final List<String> blips;
  final Widget? center;

  @override
  State<Radar> createState() => _RadarState();
}

class _RadarState extends State<Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _RadarPainter(_controller, widget.blips),
            ),
          ),
          if (widget.center != null) widget.center!,
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.animation, this.blips) : super(repaint: animation);

  final Animation<double> animation;
  final List<String> blips;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.width / 2;
    final v = animation.value;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.09);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(c, radius * i / 3, ring);
    }
    final cross = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx - radius, c.dy), Offset(c.dx + radius, c.dy), cross);
    canvas.drawLine(Offset(c.dx, c.dy - radius), Offset(c.dx, c.dy + radius), cross);

    final sweepRect = Rect.fromCircle(center: c, radius: radius);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            AppColors.cyan.withValues(alpha: 0),
            AppColors.cyan.withValues(alpha: 0),
            AppColors.cyan.withValues(alpha: 0.32),
          ],
          stops: const [0, 0.72, 1],
          transform: GradientRotation(v * 2 * pi),
        ).createShader(sweepRect),
    );

    for (final phase in [0.0, 0.5]) {
      final p = (v + phase) % 1;
      canvas.drawCircle(
        c,
        radius * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.violet.withValues(alpha: (1 - p) * 0.45),
      );
    }

    for (final id in blips) {
      final h = id.hashCode.abs();
      final angle = (h % 360) * pi / 180;
      final dist = radius * (0.45 + ((h >> 9) % 40) / 100);
      final pos = c + Offset(cos(angle) * dist, sin(angle) * dist);
      final pulse = 0.6 + 0.4 * sin(v * 2 * pi + h);
      canvas.drawCircle(pos, 14, Paint()..color = AppColors.mint.withValues(alpha: 0.14 * pulse));
      canvas.drawCircle(pos, 5, Paint()..color = AppColors.mint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => oldDelegate.blips != blips;
}
