/// Viewfinder — a scan-frame overlay. MIT © 2026 Yagnik Barasiya.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// What the scanner is doing.
enum ViewfinderStatus {
  /// Frame shown, no motion — e.g. before the camera is ready.
  idle,

  /// Looking for something: brackets breathe and a line sweeps the frame.
  searching,

  /// Found it: the frame springs onto [Viewfinder.target] and shows a check.
  locked,

  /// Couldn't read it: the frame shakes and flashes the failure colour.
  failed,
}

/// The default frame: centred, [widthFactor] of the width, with [aspectRatio],
/// never taller than [maxHeightFactor] of the height.
Rect viewfinderRect(Size size, {double widthFactor = 0.72, double aspectRatio = 1, double maxHeightFactor = 0.62}) {
  var width = size.width * widthFactor;
  var height = width / aspectRatio;
  final maxHeight = size.height * maxHeightFactor;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * aspectRatio;
  }
  return Rect.fromCenter(center: size.center(Offset.zero), width: width, height: height);
}

/// Converts a region given as fractions of the child (0–1) to pixels.
Rect denormalize(Rect fraction, Size size) =>
    Rect.fromLTRB(fraction.left * size.width, fraction.top * size.height, fraction.right * size.width, fraction.bottom * size.height);

/// Horizontal shake at progress [t] (0–1): a few decaying swings back to rest.
double shakeOffset(double t, {double amplitude = 12, int swings = 4}) {
  if (t <= 0 || t >= 1) return 0;
  return math.sin(t * swings * 2 * math.pi) * amplitude * (1 - t);
}

/// The four L-shaped corner brackets of [rect] as one path.
Path cornerPath(Rect rect, {double length = 28, double radius = 14}) {
  final l = math.min(length, math.min(rect.width, rect.height) / 2);
  final r = math.min(radius, l);
  final path = Path();
  void corner(Offset o, double sx, double sy) {
    path
      ..moveTo(o.dx, o.dy + sy * l)
      ..lineTo(o.dx, o.dy + sy * r)
      ..arcToPoint(Offset(o.dx + sx * r, o.dy), radius: Radius.circular(r), clockwise: sx * sy > 0)
      ..lineTo(o.dx + sx * l, o.dy);
  }

  corner(rect.topLeft, 1, 1);
  corner(rect.topRight, -1, 1);
  corner(rect.bottomRight, -1, -1);
  corner(rect.bottomLeft, 1, -1);
  return path;
}

/// Wraps a camera preview (or any child) with a scanning frame.
///
/// ```dart
/// Viewfinder(
///   status: status,
///   target: detected,          // e.g. Rect.fromLTRB(.2, .3, .8, .7)
///   hint: 'Centre the whole plate',
///   child: CameraPreview(controller),
/// )
/// ```
class Viewfinder extends StatefulWidget {
  const Viewfinder({
    super.key,
    required this.status,
    this.child,
    this.target,
    this.widthFactor = 0.72,
    this.aspectRatio = 1,
    this.color = const Color(0xFFFFFFFF),
    this.lockedColor = const Color(0xFF86EFAC),
    this.failedColor = const Color(0xFFFCA5A5),
    this.scrimColor = const Color(0x8C000000),
    this.strokeWidth = 4,
    this.cornerLength = 34,
    this.cornerRadius = 16,
    this.hint,
    this.hintStyle = const TextStyle(color: Color(0xFFFFFFFF), fontSize: 15, fontWeight: FontWeight.w600),
    this.semanticLabels = const {
      ViewfinderStatus.idle: 'Camera ready',
      ViewfinderStatus.searching: 'Scanning',
      ViewfinderStatus.locked: 'Found',
      ViewfinderStatus.failed: 'Could not read it. Try again.',
    },
  });

  final ViewfinderStatus status;

  /// What's under the frame, usually a camera preview.
  final Widget? child;

  /// Where the found object is, as fractions of the child's size. The frame
  /// springs onto it when [status] is [ViewfinderStatus.locked].
  final Rect? target;

  /// Width of the resting frame as a share of the overlay's width.
  final double widthFactor;

  /// Width / height of the resting frame.
  final double aspectRatio;

  final Color color;
  final Color lockedColor;
  final Color failedColor;

  /// Dims everything outside the frame. Use a transparent colour to turn it off.
  final Color scrimColor;

  final double strokeWidth;
  final double cornerLength;
  final double cornerRadius;

  /// Short instruction under the frame.
  final String? hint;
  final TextStyle hintStyle;

  /// Announced to screen readers when the status changes.
  final Map<ViewfinderStatus, String> semanticLabels;

  @override
  State<Viewfinder> createState() => _ViewfinderState();
}

class _ViewfinderState extends State<Viewfinder> with TickerProviderStateMixin {
  // Breathing brackets and the sweep line loop while searching.
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  // 0 = resting frame, 1 = locked onto the target.
  late final AnimationController _lock = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  // The colour cross-fades between states.
  late final AnimationController _tint = AnimationController(vsync: this, duration: const Duration(milliseconds: 240), value: 1);
  Color _from = const Color(0xFFFFFFFF);
  Rect? _lastTarget;

  bool get _reduced => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _from = _colorFor(widget.status);
    _apply(null);
  }

  @override
  void didUpdateWidget(Viewfinder old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status || old.target != widget.target) _apply(old.status);
  }

  Color _colorFor(ViewfinderStatus status) => switch (status) {
    ViewfinderStatus.locked => widget.lockedColor,
    ViewfinderStatus.failed => widget.failedColor,
    _ => widget.color,
  };

  void _apply(ViewfinderStatus? previous) {
    final status = widget.status;
    if (widget.target != null) _lastTarget = widget.target;

    if (status == ViewfinderStatus.searching && !_reduced) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop
        ..stop()
        ..value = 0;
    }

    final lockTo = status == ViewfinderStatus.locked && widget.target != null ? 1.0 : 0.0;
    if (_reduced) {
      _lock.value = lockTo;
    } else if (_lock.value != lockTo) {
      // Overshoot on the way in so the frame "catches" the object.
      _lock.animateTo(lockTo, curve: lockTo == 1 ? Curves.easeOutBack : Curves.easeOutCubic);
    }

    if (status == ViewfinderStatus.failed && previous != ViewfinderStatus.failed && !_reduced) {
      _shake.forward(from: 0);
    }

    if (previous != null && previous != status) {
      _from = Color.lerp(_from, _colorFor(previous), _tint.value) ?? _colorFor(previous);
      _reduced ? _tint.value = 1 : _tint.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _lock.dispose();
    _shake.dispose();
    _tint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.semanticLabels[widget.status];
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ?widget.child,
        Positioned.fill(
          child: Semantics(
            liveRegion: true,
            label: label,
            child: AnimatedBuilder(
              animation: Listenable.merge([_loop, _lock, _shake, _tint]),
              builder: (context, _) => CustomPaint(
                painter: ViewfinderPainter(
                  status: widget.status,
                  loop: _loop.value,
                  lock: _lock.value,
                  shake: shakeOffset(_shake.value),
                  target: _lastTarget,
                  color: Color.lerp(_from, _colorFor(widget.status), Curves.easeOut.transform(_tint.value))!,
                  scrimColor: widget.scrimColor,
                  strokeWidth: widget.strokeWidth,
                  cornerLength: widget.cornerLength,
                  cornerRadius: widget.cornerRadius,
                  widthFactor: widget.widthFactor,
                  aspectRatio: widget.aspectRatio,
                ),
                child: widget.hint == null
                    ? null
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final frame = viewfinderRect(
                            constraints.biggest,
                            widthFactor: widget.widthFactor,
                            aspectRatio: widget.aspectRatio,
                          );
                          return Stack(
                            children: [
                              Positioned(
                                left: 16,
                                right: 16,
                                top: frame.bottom + 20,
                                child: ExcludeSemantics(
                                  child: Text(widget.hint!, textAlign: TextAlign.center, style: widget.hintStyle),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Draws the scrim, brackets, sweep line and lock badge.
class ViewfinderPainter extends CustomPainter {
  ViewfinderPainter({
    required this.status,
    required this.loop,
    required this.lock,
    required this.shake,
    required this.target,
    required this.color,
    required this.scrimColor,
    required this.strokeWidth,
    required this.cornerLength,
    required this.cornerRadius,
    required this.widthFactor,
    required this.aspectRatio,
  });

  final ViewfinderStatus status;
  final double loop;
  final double lock;
  final double shake;
  final Rect? target;
  final Color color;
  final Color scrimColor;
  final double strokeWidth;
  final double cornerLength;
  final double cornerRadius;
  final double widthFactor;
  final double aspectRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final rest = viewfinderRect(size, widthFactor: widthFactor, aspectRatio: aspectRatio);
    final locked = target == null ? rest : denormalize(target!, size).inflate(strokeWidth * 2);
    var frame = Rect.lerp(rest, locked, lock)!;

    // Breathing: the brackets drift in by a few pixels and back.
    if (status == ViewfinderStatus.searching) {
      final breathe = (1 - math.cos(loop * 2 * math.pi)) / 2;
      frame = frame.deflate(6 * breathe);
    }
    frame = frame.shift(Offset(shake, 0));

    // Scrim with a rounded hole where the frame is.
    if (scrimColor.a > 0) {
      final hole = RRect.fromRectAndRadius(frame, Radius.circular(cornerRadius));
      final scrim = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(hole);
      canvas.drawPath(scrim, Paint()..color = scrimColor);
    }

    // Sweep line with a fading trail, only while searching.
    if (status == ViewfinderStatus.searching) {
      final t = Curves.easeInOut.transform(loop);
      final y = frame.top + frame.height * t;
      final trail = Rect.fromLTRB(frame.left + 10, math.max(frame.top, y - frame.height * 0.28), frame.right - 10, y);
      canvas.drawRect(
        trail,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.22)],
          ).createShader(trail),
      );
      canvas.drawLine(
        Offset(frame.left + 10, y),
        Offset(frame.right - 10, y),
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Brackets get bolder as they lock.
    final width = strokeWidth * (1 + lock * 0.35);
    canvas.drawPath(
      cornerPath(frame, length: cornerLength * (1 + lock * 0.2), radius: cornerRadius),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );

    // Lock badge pops in at the top-right corner.
    if (status == ViewfinderStatus.locked && lock > 0.4) {
      final pop = ((lock - 0.4) / 0.6).clamp(0.0, 1.2);
      final center = frame.topRight;
      final radius = 15 * pop;
      canvas.drawCircle(center, radius, Paint()..color = color);
      final check = Path()
        ..moveTo(center.dx - radius * 0.42, center.dy + radius * 0.02)
        ..lineTo(center.dx - radius * 0.1, center.dy + radius * 0.34)
        ..lineTo(center.dx + radius * 0.45, center.dy - radius * 0.3);
      canvas.drawPath(
        check,
        Paint()
          ..color = const Color(0xFF0A0A0A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, 2.6 * pop)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(ViewfinderPainter old) =>
      old.status != status ||
      old.loop != loop ||
      old.lock != lock ||
      old.shake != shake ||
      old.target != target ||
      old.color != color ||
      old.scrimColor != scrimColor ||
      old.strokeWidth != strokeWidth ||
      old.cornerLength != cornerLength ||
      old.cornerRadius != cornerRadius ||
      old.widthFactor != widthFactor ||
      old.aspectRatio != aspectRatio;
}
