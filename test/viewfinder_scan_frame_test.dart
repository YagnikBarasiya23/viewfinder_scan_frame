import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viewfinder_scan_frame/viewfinder_scan_frame.dart';

Widget _app(ViewfinderStatus status, {Rect? target, bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduceMotion),
    child: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: Viewfinder(
          status: status,
          target: target,
          hint: 'Centre the plate',
          child: const ColoredBox(color: Colors.grey),
        ),
      ),
    ),
  ),
);

ViewfinderPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(of: find.byType(Viewfinder), matching: find.byType(CustomPaint)))
    .map((p) => p.painter)
    .whereType<ViewfinderPainter>()
    .single;

void main() {
  group('geometry', () {
    test('the resting frame is centred and respects the height limit', () {
      final square = viewfinderRect(const Size(400, 800));
      expect(square.center, const Offset(200, 400));
      expect(square.width, closeTo(288, 1e-9));
      expect(square.height, closeTo(288, 1e-9));
      final wide = viewfinderRect(const Size(1000, 400), widthFactor: 0.8, aspectRatio: 1);
      expect(wide.height, closeTo(248, 1e-9));
      expect(wide.width, closeTo(248, 1e-9));
    });

    test('fractions become pixels', () {
      expect(denormalize(const Rect.fromLTRB(.25, .5, .75, 1), const Size(400, 200)), const Rect.fromLTRB(100, 100, 300, 200));
    });

    test('the shake starts and ends at rest and decays', () {
      expect(shakeOffset(0), 0);
      expect(shakeOffset(1), 0);
      final early = List.generate(20, (i) => shakeOffset(i / 80).abs()).reduce((a, b) => a > b ? a : b);
      final late = List.generate(20, (i) => shakeOffset(0.75 + i / 80).abs()).reduce((a, b) => a > b ? a : b);
      expect(early, greaterThan(late));
    });

    test('corner brackets stay inside the frame and scale down for small frames', () {
      const rect = Rect.fromLTWH(10, 10, 200, 120);
      final bounds = cornerPath(rect).getBounds();
      expect(bounds.left, closeTo(10, 0.5));
      expect(bounds.right, closeTo(210, 0.5));
      expect(bounds.top, closeTo(10, 0.5));
      expect(bounds.bottom, closeTo(130, 0.5));
      final tiny = cornerPath(const Rect.fromLTWH(0, 0, 20, 20), length: 40).computeMetrics().fold<double>(0, (sum, m) => sum + m.length);
      expect(tiny, lessThanOrEqualTo(4 * 20 + 0.5));
    });
  });

  group('Viewfinder', () {
    testWidgets('searching loops the sweep and announces it', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(ViewfinderStatus.searching));
      final first = _painter(tester).loop;
      await tester.pump(const Duration(milliseconds: 500));
      expect(_painter(tester).loop, isNot(first));
      expect(tester.hasRunningAnimations, isTrue);
      expect(find.bySemanticsLabel('Scanning'), findsOneWidget);
      expect(find.text('Centre the plate'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('locking springs the frame onto the target and stops the loop', (tester) async {
      await tester.pumpWidget(_app(ViewfinderStatus.searching));
      await tester.pump(const Duration(milliseconds: 300));
      const target = Rect.fromLTRB(.2, .3, .7, .6);
      await tester.pumpWidget(_app(ViewfinderStatus.locked, target: target));
      await tester.pump(const Duration(milliseconds: 150));
      final mid = _painter(tester).lock;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1.2));
      await tester.pumpAndSettle();
      final painter = _painter(tester);
      expect(painter.lock, 1);
      expect(painter.loop, 0);
      expect(painter.target, target);
      expect(painter.color, const Color(0xFF86EFAC));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('failing shakes once and turns the failure colour', (tester) async {
      await tester.pumpWidget(_app(ViewfinderStatus.searching));
      await tester.pumpWidget(_app(ViewfinderStatus.failed));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_painter(tester).shake, isNot(0));
      await tester.pumpAndSettle();
      expect(_painter(tester).shake, 0);
      expect(_painter(tester).color, const Color(0xFFFCA5A5));
    });

    testWidgets('going back to searching releases the lock', (tester) async {
      await tester.pumpWidget(_app(ViewfinderStatus.locked, target: const Rect.fromLTRB(.1, .1, .5, .5)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_app(ViewfinderStatus.searching));
      await tester.pump(const Duration(seconds: 1));
      expect(_painter(tester).lock, 0);
    });

    testWidgets('reduced motion shows each state without animating', (tester) async {
      await tester.pumpWidget(_app(ViewfinderStatus.searching, reduceMotion: true));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(_app(ViewfinderStatus.locked, target: const Rect.fromLTRB(.2, .2, .6, .6), reduceMotion: true));
      await tester.pump();
      expect(_painter(tester).lock, 1);
      await tester.pumpWidget(_app(ViewfinderStatus.failed, reduceMotion: true));
      await tester.pump();
      expect(_painter(tester).shake, 0);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
