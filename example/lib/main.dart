import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:viewfinder_scan_frame/viewfinder_scan_frame.dart';

import 'controls.dart';

void main() => runApp(const ViewfinderDemo());

const _bg = Color(0xFF050505);
const _panel = Color(0xFF0E0E10);
const _line = Color(0x1AFFFFFF);
const _muted = Color(0xFFA1A1AA);
const _accent = Color(0xFFD9F99D);

class ViewfinderDemo extends StatelessWidget {
  const ViewfinderDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Viewfinder — scan frame for Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(primary: _accent, surface: _panel),
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  ViewfinderStatus _status = ViewfinderStatus.searching;
  Timer? _timer;
  // Where the plate sits in the drawn scene, as fractions of the preview.
  static const _plate = Rect.fromLTRB(0.17, 0.26, 0.83, 0.64);

  void _scan({required bool succeed}) {
    _timer?.cancel();
    setState(() => _status = ViewfinderStatus.searching);
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _status = succeed ? ViewfinderStatus.locked : ViewfinderStatus.failed);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _statusText => switch (_status) {
    ViewfinderStatus.idle => 'Idle',
    ViewfinderStatus.searching => 'Looking for food…',
    ViewfinderStatus.locked => 'Plate found — 3 items',
    ViewfinderStatus.failed => 'Too dark to read. Try again.',
  };

  @override
  Widget build(BuildContext context) {
    final phone = ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Viewfinder(
          status: _status,
          target: _plate,
          hint: 'Centre the whole plate',
          child: const CustomPaint(painter: _TablePainter()),
        ),
      ),
    );

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'VIEWFINDER · FLUTTER',
          style: TextStyle(color: Color(0xFF71717A), letterSpacing: 3.5, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          'A scan frame\nthat looks alive.',
          style: TextStyle(fontSize: 44, height: 1.02, fontWeight: FontWeight.w800, letterSpacing: -1.8),
        ),
        const SizedBox(height: 14),
        const Text(
          'Brackets breathe and a line sweeps while scanning. When something is found the frame springs onto it; when it fails, it shakes. Drop it over any camera preview.',
          style: TextStyle(color: _muted, fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                switch (_status) {
                  ViewfinderStatus.locked => Icons.check_circle,
                  ViewfinderStatus.failed => Icons.error,
                  _ => Icons.center_focus_weak,
                },
                size: 18,
                color: switch (_status) {
                  ViewfinderStatus.locked => const Color(0xFF86EFAC),
                  ViewfinderStatus.failed => const Color(0xFFFCA5A5),
                  _ => _muted,
                },
              ),
              const SizedBox(width: 10),
              Text(_statusText),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PillButton(label: 'Scan', primary: true, onPressed: () => _scan(succeed: true)),
            PillButton(label: 'Scan and fail', onPressed: () => _scan(succeed: false)),
          ],
        ),
        const SizedBox(height: 12),
        Segmented<ViewfinderStatus>(
          segments: const {
            ViewfinderStatus.idle: 'Idle',
            ViewfinderStatus.locked: 'Found',
            ViewfinderStatus.failed: 'Failed',
          },
          selected: _status,
          onChanged: (status) => setState(() => _status = status),
        ),
        const SizedBox(height: 28),
        const SizedBox(
          width: double.infinity,
          child: Text(
            'MIT © 2026 Yagnik Barasiya · github.com/YagnikBarasiya23/viewfinder_scan_frame',
            style: TextStyle(color: _muted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 28, 20, 40 + MediaQuery.paddingOf(context).bottom),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth > 720
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(width: 360, child: phone),
                          const SizedBox(width: 48),
                          Expanded(child: controls),
                        ],
                      )
                    : Column(
                        children: [
                          controls,
                          const SizedBox(height: 28),
                          SizedBox(width: 360, child: phone),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A table seen from above with a plate on it, drawn so the demo needs no camera.
class _TablePainter extends CustomPainter {
  const _TablePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.5),
          radius: 1.2,
          colors: [Color(0xFF6B5A48), Color(0xFF3B3026), Color(0xFF1C1712)],
        ).createShader(rect),
    );
    // Wood grain.
    final grain = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1.2;
    for (var y = 0.0; y < size.height; y += 9) {
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 20) {
        path.lineTo(x, y + math.sin((x + y * 3) / 40) * 2.5);
      }
      canvas.drawPath(path, grain..style = PaintingStyle.stroke);
    }

    final plate = Rect.fromLTRB(size.width * .17, size.height * .26, size.width * .83, size.height * .64);
    final c = plate.center;
    final r = plate.shortestSide / 2;
    canvas.drawCircle(
      c.translate(6, 10),
      r,
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFF1EDE6));
    canvas.drawCircle(c, r * .78, Paint()..color = const Color(0xFFFAF8F4));

    // Rice
    final rice = Paint()..color = const Color(0xFFFFFDF7);
    final rng = math.Random(3);
    for (var i = 0; i < 90; i++) {
      final a = rng.nextDouble() * 2 * math.pi;
      final d = math.sqrt(rng.nextDouble()) * r * .28;
      final p = c.translate(-r * .28 + math.cos(a) * d, r * .18 + math.sin(a) * d);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-3, -1.2, 6, 2.4), const Radius.circular(2)),
        rice..color = i.isEven ? const Color(0xFFFFFDF7) : const Color(0xFFEDE6D6),
      );
      canvas.restore();
    }
    // Salmon
    final fish = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c.translate(r * .22, -r * .1), width: r * .7, height: r * .42),
      Radius.circular(r * .12),
    );
    canvas.drawRRect(fish, Paint()..color = const Color(0xFFE9895B));
    for (var i = 0; i < 5; i++) {
      final x = fish.left + fish.width * (0.15 + i * .18);
      canvas.drawLine(
        Offset(x, fish.top + 6),
        Offset(x - 10, fish.bottom - 6),
        Paint()
          ..color = const Color(0xFF7A3B1E)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    // Greens
    final leaf = Paint()..color = const Color(0xFF5E9E4B);
    for (var i = 0; i < 7; i++) {
      final a = -2.4 + i * 0.28;
      final p = c.translate(math.cos(a) * r * .5, math.sin(a) * r * .5);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a + math.pi / 2);
      canvas.drawOval(
        const Rect.fromLTWH(-7, -16, 14, 32),
        leaf..color = i.isEven ? const Color(0xFF5E9E4B) : const Color(0xFF7DB85F),
      );
      canvas.restore();
    }
    // Tomatoes
    for (final (dx, dy) in [(0.18, 0.42), (0.36, 0.3)]) {
      final p = c.translate(r * dx, r * dy);
      canvas.drawCircle(p, r * .1, Paint()..color = const Color(0xFFD9412F));
      canvas.drawCircle(p.translate(-3, -3), r * .03, Paint()..color = const Color(0x66FFFFFF));
    }
    // A lemon slice off the plate
    final lemon = Offset(size.width * .82, size.height * .82);
    canvas.drawCircle(lemon, 30, Paint()..color = const Color(0xFFF4D35E));
    canvas.drawCircle(lemon, 25, Paint()..color = const Color(0xFFFBE89A));
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawLine(
        lemon,
        lemon + Offset(math.cos(a), math.sin(a)) * 24,
        Paint()
          ..color = const Color(0xFFF4D35E)
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_TablePainter oldDelegate) => false;
}
