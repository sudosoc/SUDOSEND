import 'dart:ui';

import 'package:flutter/material.dart';

import '../app/scope.dart';
import 'theme.dart';

/// Frosted-glass surface: backdrop blur + translucent gradient + hairline border.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.blur = 24,
    this.tint = 0.07,
    this.borderColor,
    this.glow,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final double tint;
  final Color? borderColor;
  final Color? glow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    Widget surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: tint + 0.06),
            Colors.white.withValues(alpha: tint * 0.35),
          ],
        ),
        border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.14)),
      ),
      child: child,
    );
    if (onTap != null) {
      surface = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: r,
          splashColor: AppColors.cyan.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          child: surface,
        ),
      );
    }
    final g = glow;
    final reduced = context.reducedEffects;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        // Reduced effects: an opaque panel instead of a live blur.
        color: reduced ? const Color(0xE6101631) : null,
        boxShadow: g == null || reduced
            ? const []
            : [BoxShadow(color: g.withValues(alpha: 0.28), blurRadius: 40, spreadRadius: -10)],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: reduced
            ? surface
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: surface,
              ),
      ),
    );
  }
}

/// Primary action: gradient pill with a soft neon glow.
class GlowButton extends StatelessWidget {
  const GlowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.gradient = kAccentGradient,
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Gradient gradient;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final r = BorderRadius.circular(16);
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: AppColors.ink),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ],
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: r,
          boxShadow: [
            BoxShadow(color: AppColors.cyan.withValues(alpha: 0.35), blurRadius: 24, spreadRadius: -6),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: r,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action: glass outline button.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.text,
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 16,
      blur: 12,
      tint: 0.04,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      borderColor: color.withValues(alpha: 0.28),
      onTap: onPressed,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 8),
          ],
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14.5)),
        ],
      ),
    );
  }
}

/// Rounded icon tile with a tinted halo.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 46});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.08)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Glass dialog shell.
class GlassDialog extends StatelessWidget {
  const GlassDialog({super.key, required this.child, this.maxWidth = 440});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Glass(
          tint: 0.10,
          blur: 34,
          radius: 28,
          padding: const EdgeInsets.all(22),
          glow: AppColors.violet,
          child: child,
        ),
      ),
    );
  }
}
