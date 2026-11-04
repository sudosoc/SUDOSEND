import 'package:flutter/material.dart';

import 'theme.dart';

/// Solid card on the obsidian background: flat fill, hairline border.
/// (Still called Glass so every screen picks the new look up; [blur] and
/// [tint] are accepted for compatibility and ignored. [glow] draws a faint
/// accent hairline instead of a halo.)
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.blur = 0,
    this.tint = 0,
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
    final border = borderColor ??
        (glow != null ? glow!.withValues(alpha: 0.28) : AppColors.line);
    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: r,
        color: AppColors.surface,
        border: Border.all(color: border),
      ),
      child: child,
    );
    if (onTap == null) return surface;
    return Material(
      color: Colors.transparent,
      borderRadius: r,
      child: InkWell(
        onTap: onTap,
        borderRadius: r,
        splashColor: AppColors.accent.withValues(alpha: 0.10),
        highlightColor: Colors.white.withValues(alpha: 0.03),
        // Clearly visible focus for TV remotes (D-pad) and keyboards.
        focusColor: AppColors.accent.withValues(alpha: 0.18),
        child: surface,
      ),
    );
  }
}

/// Primary action: solid accent, no glow.
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
    final r = BorderRadius.circular(14);
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 19, color: AppColors.ink),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 15),
          ),
        ),
      ],
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.4,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient, borderRadius: r),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: r,
            focusColor: Colors.white.withValues(alpha: 0.35),
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

/// Secondary action: outlined, quiet.
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
    final quiet = color == AppColors.text;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Glass(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderColor: quiet ? AppColors.line : color.withValues(alpha: 0.35),
        onTap: onPressed,
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded icon tile with a tinted halo.
class IconBadge extends StatelessWidget {
  const IconBadge(
      {super.key, required this.icon, required this.color, this.size = 46});

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
        color: color.withValues(alpha: 0.12),
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
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Dialog shell: solid raised surface.
class GlassDialog extends StatelessWidget {
  const GlassDialog({super.key, required this.child, this.maxWidth = 440});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final tiny = MediaQuery.sizeOf(context).width < 300;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: tiny
          ? const EdgeInsets.all(6)
          : const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: EdgeInsets.all(tiny ? 12 : 22),
          decoration: BoxDecoration(
            color: AppColors.surfaceHi,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.line),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x80000000),
                  blurRadius: 40,
                  offset: Offset(0, 16))
            ],
          ),
          // Scrolls on small screens (watches, landscape phones) instead of overflowing.
          child: SingleChildScrollView(child: child),
        ),
      ),
    );
  }
}
