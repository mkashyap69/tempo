import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'icons.dart';
import 'tokens.dart';
import 'type.dart';

/// TempoHaptics → HapticFeedback. Quiet by default.
abstract final class TempoHaptics {
  static void selection() => HapticFeedback.selectionClick();
  static void light() => HapticFeedback.lightImpact();
  static void medium() => HapticFeedback.mediumImpact();
  static void success() => HapticFeedback.heavyImpact();
  static Future<void> warning() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.heavyImpact();
  }
}

/// Tap target with a fast opacity response instead of an ink ripple.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.label,
    this.button = true,
    this.selected,
  });
  final Widget child;
  final VoidCallback? onTap;
  final String? label;
  final bool button;
  final bool? selected;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: widget.button,
    label: widget.label,
    selected: widget.selected,
    enabled: widget.onTap != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedOpacity(
        duration: TempoMotion.fast,
        opacity: _down ? .6 : 1,
        child: widget.child,
      ),
    ),
  );
}

enum ButtonKind { primary, secondary, ghost, text, danger, inverse }

/// TempoButton: monochrome. 52 high, 44 small, 64/72 live.
class TempoButton extends StatelessWidget {
  const TempoButton(
    this.label, {
    super.key,
    this.onTap,
    this.kind = ButtonKind.primary,
    this.small = false,
    this.icon,
    this.expand = false,
    this.height,
    this.radius,
    this.fontSize,
  });
  final String label;
  final VoidCallback? onTap;
  final ButtonKind kind;
  final bool small, expand;
  final String? icon;
  final double? height, radius, fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg) = switch (kind) {
      ButtonKind.primary => (c.text1, c.textInverse),
      ButtonKind.secondary => (c.surface3, c.text1),
      ButtonKind.ghost => (Colors.transparent, c.text1),
      ButtonKind.text => (Colors.transparent, c.text2),
      ButtonKind.danger => (context.s.recLow, const Color(0xFF0A0B0D)),
      ButtonKind.inverse => (c.textInverse, c.text1),
    };
    final h = height ?? (small ? 44.0 : 52.0);
    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          TempoIcon(
            icon!,
            size: small ? 16 : 18,
            color: fg,
            fill: icon == TempoIcons.play,
            stroke: 2,
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: TempoType.family,
              fontSize: fontSize ?? (small ? 14 : 15),
              fontWeight: FontWeight.w500,
              letterSpacing: -0.075,
              color: fg,
            ),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: onTap == null ? .38 : 1,
      child: Pressable(
        onTap: onTap == null
            ? null
            : () {
                TempoHaptics.selection();
                onTap!();
              },
        label: label,
        child: Container(
          constraints: BoxConstraints(minHeight: h),
          padding: EdgeInsets.symmetric(horizontal: small ? 16 : 22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius ?? TempoRadii.pill),
            border: kind == ButtonKind.ghost
                ? Border.all(color: c.lineStrong)
                : null,
          ),
          alignment: Alignment.center,
          child: row,
        ),
      ),
    );
  }
}

/// 44 × 44 icon button.
class TempoIconButton extends StatelessWidget {
  const TempoIconButton(
    this.icon, {
    super.key,
    required this.label,
    this.onTap,
    this.size = 22,
    this.color,
    this.filled = false,
    this.stroke = 2,
  });
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final double size, stroke;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? .3 : 1,
    child: Pressable(
      onTap: onTap,
      label: label,
      child: Container(
        width: 44,
        height: 44,
        decoration: filled
            ? BoxDecoration(color: context.c.surface2, shape: BoxShape.circle)
            : null,
        alignment: Alignment.center,
        child: TempoIcon(
          icon,
          size: size,
          color: color ?? context.c.text1,
          stroke: stroke,
        ),
      ),
    ),
  );
}

/// Data-honesty badge: Est. · ≈ proxy · General · Personal · PB · Live.
class TempoBadge extends StatelessWidget {
  const TempoBadge(
    this.text, {
    super.key,
    this.small = false,
    this.color,
    this.background,
  });
  final String text;
  final bool small;
  final Color? color, background;

  @override
  Widget build(BuildContext context) => Container(
    height: small ? 18 : 22,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(TempoRadii.pill),
      border: Border.all(color: context.c.lineStrong),
    ),
    child: Center(
      widthFactor: 1,
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontFamily: TempoType.family,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: .22,
          color: color ?? context.c.text2,
        ).tnum,
      ),
    ),
  );
}

/// Upper-case overline in text-3.
class Overline extends StatelessWidget {
  const Overline(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TempoType.overline.c(color ?? context.c.text3),
  );
}

class Hair extends StatelessWidget {
  const Hair({super.key, this.indent = 0});
  final double indent;
  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: EdgeInsets.symmetric(horizontal: indent),
    color: context.c.line,
  );
}

/// surface-1 card, r-lg, s-4 padding. Tappable when [onTap] is set.
class TempoCard extends StatelessWidget {
  const TempoCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.radius = TempoRadii.lg,
    this.label,
    this.border,
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;
  final double radius;
  final String? label;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.c.surface1,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: child,
    );
    return onTap == null
        ? box
        : Pressable(onTap: onTap, label: label, child: box);
  }
}

/// A list inside one card, rows separated by hairlines (border-top).
class CardList extends StatelessWidget {
  const CardList({
    super.key,
    required this.children,
    this.color,
    this.radius = TempoRadii.lg,
  });
  final List<Widget> children;
  final Color? color;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color ?? context.c.surface1,
      borderRadius: BorderRadius.circular(radius),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, ch) in children.indexed)
          DecoratedBox(
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : Border(top: BorderSide(color: context.c.line)),
            ),
            child: ch,
          ),
      ],
    ),
  );
}

/// Section title (overline) above content.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Overline(title)),
          ?trailing,
        ],
      ),
      const SizedBox(height: 10),
      child,
    ],
  );
}

/// TempoStatusBanner: neutral surface-2, never tinted; exactly one action.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });
  final String icon, title, body;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(TempoRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.surface3,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: TempoIcon(icon, size: 18, color: c.text1),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TempoType.label.c(c.text1)),
                const SizedBox(height: 4),
                Text(body, style: TempoType.bodyS.c(c.text2)),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            TempoButton(
              action!,
              kind: ButtonKind.secondary,
              small: true,
              onTap: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

/// TempoSegmented: pill track, selected = surface-3.
class TempoSegmented<T> extends StatelessWidget {
  const TempoSegmented({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.height = 40,
    this.inverse = false,
    this.width,
  });
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  /// Selected segment uses text-1 fill (the yes/no and card-style toggles).
  final bool inverse;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: width,
      padding: EdgeInsets.all(inverse ? 3 : 4),
      decoration: BoxDecoration(
        color: inverse ? c.surface2 : c.surface2,
        borderRadius: BorderRadius.circular(TempoRadii.pill),
      ),
      child: Row(
        mainAxisSize: width == null ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final (i, v) in values.indexed)
            Expanded(
              child: Pressable(
                selected: v == selected,
                label: labels[i],
                onTap: () {
                  if (v != selected) TempoHaptics.selection();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: TempoMotion.fast,
                  curve: TempoMotion.easeOut,
                  height: height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == selected
                        ? (inverse ? c.text1 : c.surface3)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(TempoRadii.pill),
                  ),
                  child: Text(
                    labels[i],
                    style: TempoType.label.copyWith(
                      color: v == selected
                          ? (inverse ? c.textInverse : c.text1)
                          : c.text2,
                      fontWeight: v == selected
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Yes/No toggle used by the journal. null = unanswered.
class YesNo extends StatelessWidget {
  const YesNo({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final bool? value;
  final ValueChanged<bool> onChanged;
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget opt(String t, bool v) => Pressable(
      label: '$label: $t',
      selected: value == v,
      onTap: () {
        TempoHaptics.selection();
        onChanged(v);
      },
      child: AnimatedContainer(
        duration: TempoMotion.fast,
        width: 56,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: value == v ? c.text1 : Colors.transparent,
          borderRadius: BorderRadius.circular(TempoRadii.pill),
        ),
        child: Text(
          t,
          style: TempoType.label.c(value == v ? c.textInverse : c.text2),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(TempoRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [opt('Yes', true), opt('No', false)],
      ),
    );
  }
}

/// Selection chip: selected = text-1 fill.
class TempoChip extends StatelessWidget {
  const TempoChip(
    this.label, {
    super.key,
    required this.selected,
    required this.onTap,
    this.height = 44,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      selected: selected,
      label: label,
      onTap: () {
        TempoHaptics.selection();
        onTap();
      },
      child: AnimatedContainer(
        duration: TempoMotion.fast,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: selected ? c.text1 : Colors.transparent,
          borderRadius: BorderRadius.circular(TempoRadii.pill),
          border: selected ? null : Border.all(color: c.lineStrong),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TempoType.body.copyWith(
            fontWeight: FontWeight.w500,
            color: selected ? c.textInverse : c.text1,
          ),
        ),
      ),
    );
  }
}

class TempoSwitch extends StatelessWidget {
  const TempoSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      toggled: value,
      label: label,
      child: GestureDetector(
        onTap: () {
          TempoHaptics.selection();
          onChanged(!value);
        },
        child: AnimatedContainer(
          duration: TempoMotion.fast,
          width: 52,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? c.text1 : c.trackOff,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: value ? c.textInverse : c.text3,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// TempoTextField: surface-2, r-sm, 52 high, focus ring text-1, error ring rec-low.
class TempoField extends StatefulWidget {
  const TempoField({
    super.key,
    required this.controller,
    this.label,
    this.suffix,
    this.error = false,
    this.keyboardType,
    this.mono = false,
    this.trailing,
    this.onChanged,
    this.estimate = false,
    this.fontSize = 17,
    this.hint,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String? label, suffix, hint;
  final bool error, mono, estimate, autofocus;
  final TextInputType? keyboardType;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final double fontSize;

  @override
  State<TempoField> createState() => _TempoFieldState();
}

class _TempoFieldState extends State<TempoField> {
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ring = widget.error
        ? context.s.recLow
        : (_focus.hasFocus ? c.text1 : null);
    final field = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: EdgeInsets.only(
        left: 14,
        right: widget.trailing == null ? 14 : 6,
      ),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(TempoRadii.sm),
        border: ring == null
            ? Border.all(color: Colors.transparent, width: 1.5)
            : Border.all(color: ring, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              keyboardType: widget.keyboardType,
              onChanged: widget.onChanged,
              autocorrect: false,
              enableSuggestions: false,
              style:
                  (widget.mono
                          ? TempoType.monoS
                          : TempoType.body
                                .copyWith(fontSize: widget.fontSize)
                                .tnum)
                      .copyWith(
                        color: c.text1,
                        decoration: widget.estimate
                            ? TextDecoration.underline
                            : null,
                        decorationStyle: TextDecorationStyle.dotted,
                        decorationColor: c.text3,
                      ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: TempoType.body.c(c.text3),
              ),
            ),
          ),
          if (widget.suffix != null)
            Text(widget.suffix!, style: TempoType.bodyS.c(c.text3)),
          ?widget.trailing,
        ],
      ),
    );
    if (widget.label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label!, style: TempoType.label.c(c.text1)),
        const SizedBox(height: 6),
        field,
      ],
    );
  }
}

/// TempoToast: inverse surface, 4 s, above the tab bar.
void showTempoToast(
  BuildContext context,
  String message, {
  String? action,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) {
      final c = context.c;
      return Positioned(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(ctx).padding.bottom + 49 + 16,
        child: Material(
          type: MaterialType.transparency,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: TempoMotion.base,
            curve: TempoMotion.easeOut,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - t)),
                child: child,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              decoration: BoxDecoration(
                color: c.text1,
                borderRadius: BorderRadius.circular(TempoRadii.md),
                boxShadow: c.shadowFloat,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      message,
                      style: TempoType.label.c(c.textInverse),
                    ),
                  ),
                  if (action != null)
                    Pressable(
                      onTap: () {
                        remove();
                        onAction?.call();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          action,
                          style: TempoType.label.copyWith(
                            color: c.textInverse,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: c.textInverse,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(entry);
  Timer(const Duration(seconds: 4), remove);
}

/// TempoSheet: grabber, title, plain-language answer, evidence.
Future<T?> showTempoSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: context.c.scrim,
  sheetAnimationStyle: const AnimationStyle(
    duration: TempoMotion.slow,
    reverseDuration: TempoMotion.base,
  ),
  builder: (ctx) => Container(
    decoration: BoxDecoration(
      color: ctx.c.surface2,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(TempoRadii.xl),
      ),
      boxShadow: ctx.c.shadowSheet,
    ),
    padding: EdgeInsets.fromLTRB(
      20,
      10,
      20,
      28 +
          MediaQuery.of(ctx).viewInsets.bottom +
          MediaQuery.of(ctx).padding.bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: ctx.c.lineStrong,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 16),
          builder(ctx),
        ],
      ),
    ),
  ),
);

/// Pick one of [options] in a sheet.
Future<T?> pickOption<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) label,
  T? selected,
}) => showTempoSheet<T>(
  context,
  builder: (ctx) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: TempoType.titleM.c(ctx.c.text1)),
      const SizedBox(height: 12),
      CardList(
        color: ctx.c.surface1,
        children: [
          for (final o in options)
            Pressable(
              selected: o == selected,
              onTap: () => Navigator.pop(ctx, o),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label(o),
                        style: TempoType.body.c(ctx.c.text1),
                      ),
                    ),
                    if (o == selected)
                      TempoIcon(
                        TempoIcons.check,
                        size: 18,
                        color: ctx.c.text1,
                        stroke: 2.25,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ],
  ),
);

Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool danger = false,
}) async =>
    await showTempoSheet<bool>(
      context,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: TempoType.titleL.c(ctx.c.text1)),
          const SizedBox(height: 8),
          Text(body, style: TempoType.body.c(ctx.c.text2)),
          const SizedBox(height: 20),
          TempoButton(
            action,
            kind: danger ? ButtonKind.danger : ButtonKind.primary,
            expand: true,
            onTap: () => Navigator.pop(ctx, true),
          ),
          const SizedBox(height: 4),
          TempoButton(
            'Cancel',
            kind: ButtonKind.text,
            expand: true,
            onTap: () => Navigator.pop(ctx, false),
          ),
        ],
      ),
    ) ??
    false;

/// Empty state drawn with the meter's own strokes.
class TempoEmpty extends StatelessWidget {
  const TempoEmpty(this.text, {super.key, this.kind = EmptyKind.ticks});
  final String text;
  final EmptyKind kind;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(TempoRadii.md),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 40,
            child: CustomPaint(painter: _EmptyPainter(kind, c.text3)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: TempoType.bodyS.c(c.text1))),
        ],
      ),
    );
  }
}

enum EmptyKind { ticks, trend, journal }

class _EmptyPainter extends CustomPainter {
  _EmptyPainter(this.kind, this.color);
  final EmptyKind kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final solid = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    void dashed(Offset a, Offset b) {
      final d = b - a;
      final len = d.distance;
      final u = d / len;
      for (var t = 0.0; t < len; t += 6) {
        canvas.drawLine(a + u * t, a + u * (t + 2 > len ? len : t + 2), solid);
      }
    }

    switch (kind) {
      case EmptyKind.ticks:
        canvas.drawLine(const Offset(4, 36), const Offset(4, 4), solid);
        for (final x in const <double>[14, 24, 34, 54, 64]) {
          dashed(Offset(x, 36), Offset(x, 26));
        }
        dashed(const Offset(44, 36), const Offset(44, 4));
      case EmptyKind.trend:
        canvas.drawPath(
          Path()
            ..moveTo(4, 30)
            ..lineTo(16, 22)
            ..lineTo(26, 26)
            ..lineTo(36, 14),
          solid,
        );
        dashed(const Offset(36, 14), const Offset(48, 18));
        dashed(const Offset(48, 18), const Offset(58, 8));
        dashed(const Offset(58, 8), const Offset(68, 12));
      case EmptyKind.journal:
        dashed(const Offset(10, 4), const Offset(32, 4));
        dashed(const Offset(32, 4), const Offset(32, 36));
        dashed(const Offset(32, 36), const Offset(10, 36));
        dashed(const Offset(10, 36), const Offset(10, 4));
        for (final (y, w) in [(12.0, 10.0), (18.0, 10.0), (24.0, 6.0)]) {
          canvas.drawLine(Offset(16, y), Offset(16 + w, y), solid);
        }
        dashed(const Offset(44, 20), const Offset(64, 20));
    }
  }

  @override
  bool shouldRepaint(_EmptyPainter o) => o.color != color || o.kind != kind;
}

/// Tempo mark: one accented stroke, three measured ones. [beats] dims strokes
/// (splash count-in); null = all solid.
class TempoMark extends StatelessWidget {
  const TempoMark({super.key, this.size = 48, this.color, this.opacities});
  final double size;
  final Color? color;
  final List<double>? opacities;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: MarkPainter(
        color ?? context.c.text1,
        opacities ?? const [1, 1, 1, 1],
      ),
    ),
  );
}

class MarkPainter extends CustomPainter {
  MarkPainter(this.color, this.opacities);
  final Color color;
  final List<double> opacities;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48);
    const rects = [
      Rect.fromLTWH(5.5, 8, 5.5, 32),
      Rect.fromLTWH(16, 27, 5.5, 13),
      Rect.fromLTWH(26.5, 27, 5.5, 13),
      Rect.fromLTWH(37, 27, 5.5, 13),
    ];
    for (final (i, r) in rects.indexed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2.75)),
        Paint()..color = color.withValues(alpha: color.a * opacities[i]),
      );
    }
  }

  @override
  bool shouldRepaint(MarkPainter o) =>
      o.color != color || o.opacities != opacities;
}

/// Lockup: mark + "tempo" wordmark.
class TempoLockup extends StatelessWidget {
  const TempoLockup({super.key, this.size = 52, this.color});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final col = color ?? context.c.text1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TempoMark(size: size, color: col),
        SizedBox(width: size * .23),
        Padding(
          padding: EdgeInsets.only(bottom: size * .06),
          child: Text(
            'tempo',
            style: TextStyle(
              fontFamily: TempoType.family,
              fontSize: size * 1.23,
              height: .82,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.06 * size * 1.23,
              color: col,
            ),
          ),
        ),
      ],
    );
  }
}

/// Screen header for detail pages: back · title (+ subtitle) · trailing.
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leadingIcon = TempoIcons.back,
    this.onBack,
    this.center,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String leadingIcon;
  final VoidCallback? onBack;
  final Widget? center;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Row(
      children: [
        Transform.translate(
          offset: const Offset(-10, 0),
          child: TempoIconButton(
            leadingIcon,
            label: leadingIcon == TempoIcons.close ? 'Close' : 'Back',
            onTap: onBack ?? () => Navigator.maybePop(context),
          ),
        ),
        Expanded(
          child: Center(
            child:
                center ??
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: TempoType.label.c(context.c.text1)),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TempoType.caption.c(context.c.text3).tnum,
                      ),
                  ],
                ),
          ),
        ),
        Transform.translate(
          offset: Offset(
            trailing is TempoBadge || trailing is Center ? 0 : 10,
            0,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44),
            child: trailing ?? const SizedBox(width: 44),
          ),
        ),
      ],
    ),
  );
}

/// Scrolling page with the screen gutter, safe-area top + 12, and gap
/// between sections.
class TempoPage extends StatelessWidget {
  const TempoPage({
    super.key,
    required this.children,
    this.gap = 20,
    this.bottom = 48,
    this.footer,
    this.onRefresh,
    this.overlay,
  });
  final List<Widget> children;
  final double gap, bottom;
  final Widget? footer;
  final Future<void> Function()? onRefresh;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 12;
    Widget list = ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        top,
        20,
        bottom + (footer == null ? MediaQuery.of(context).padding.bottom : 0),
      ),
      children: [
        for (final (i, w) in children.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          w,
        ],
      ],
    );
    if (onRefresh != null) {
      list = RefreshIndicator(
        onRefresh: onRefresh!,
        color: context.c.text1,
        backgroundColor: context.c.surface2,
        edgeOffset: top,
        child: list,
      );
    }
    return Scaffold(
      backgroundColor: context.c.bg,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(child: list),
              if (footer != null)
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: context.c.bg,
                    border: Border(top: BorderSide(color: context.c.line)),
                  ),
                  child: footer,
                ),
            ],
          ),
          ?overlay,
        ],
      ),
    );
  }
}

/// Label/value column used in stat grids.
class Stat extends StatelessWidget {
  const Stat(
    this.label,
    this.value, {
    super.key,
    this.unit,
    this.color,
    this.sub,
    this.estimate = false,
    this.valueStyle,
  });
  final String label, value;
  final String? unit, sub;
  final Color? color;
  final bool estimate;
  final TextStyle? valueStyle;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TempoType.caption.c(c.text3)),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            text: value,
            style: (valueStyle ?? TempoType.scoreS).copyWith(
              color: color ?? c.text1,
              decoration: estimate ? TextDecoration.underline : null,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: c.text3,
            ),
            children: [
              if (unit != null)
                TextSpan(text: unit, style: TempoType.caption.c(c.text3)),
            ],
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub!, style: TempoType.caption.c(c.text2)),
        ],
      ],
    );
  }
}

/// A row in a settings-style list: key, value, chevron.
class ListRow extends StatelessWidget {
  const ListRow(
    this.k, {
    super.key,
    this.value,
    this.onTap,
    this.color,
    this.trailing,
    this.chevron = true,
    this.sub,
  });
  final String k;
  final String? value, sub;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? trailing;
  final bool chevron;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      label: k,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: TempoType.body.c(color ?? c.text1)),
                if (sub != null)
                  Text(sub!, style: TempoType.caption.c(c.text3)),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: value == null || value!.isEmpty
                  ? const SizedBox()
                  : Text(
                      value!,
                      textAlign: TextAlign.right,
                      style: TempoType.bodyS.c(c.text2),
                    ),
            ),
            ?trailing,
            if (chevron && onTap != null) ...[
              const SizedBox(width: 6),
              TempoIcon(
                TempoIcons.chevron,
                size: 16,
                color: c.text3,
                stroke: 2,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small coloured legend chip + text.
class Legend extends StatelessWidget {
  const Legend(
    this.color,
    this.text, {
    super.key,
    this.width = 10,
    this.height = 10,
    this.dashed = false,
    this.outline = false,
  });
  final Color color;
  final String text;
  final double width, height;
  final bool dashed, outline;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: width,
        height: dashed ? 1.5 : height,
        decoration: BoxDecoration(
          color: outline ? null : color,
          border: outline ? Border.all(color: color, width: 1.5) : null,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(text, style: TempoType.caption.c(context.c.text2).tnum),
    ],
  );
}

/// Privacy line with the lock icon.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote(this.text, {super.key, this.sub});
  final String text;
  final String? sub;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(TempoRadii.md),
      ),
      child: Row(
        children: [
          TempoIcon(TempoIcons.private, size: 20, color: c.text1),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: (sub == null ? TempoType.bodyS : TempoType.label).c(
                    c.text1,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!, style: TempoType.caption.c(c.text2)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
