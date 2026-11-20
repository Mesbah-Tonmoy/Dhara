import 'dart:ui' as ui;

import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/logo.dart';
import 'package:dhara/widgets/placeholder_art.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:dhara/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('GlassCard', () {
    testWidgets('is a bordered pane, blurred only when asked', (tester) async {
      await tester.pumpWidget(
        host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassCard(child: Text('plain')),
              GlassCard(blur: true, child: Text('blurred')),
            ],
          ),
        ),
      );

      final box =
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(
                          of: find.text('plain'),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(box.color, DharaColors.surface);
      expect((box.border! as Border).top.color, DharaColors.stroke);
      expect(box.borderRadius, BorderRadius.circular(DharaRadii.lg));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('Skeleton', () {
    testWidgets('has the size it is given and keeps sweeping', (tester) async {
      await tester.pumpWidget(host(const Skeleton(width: 120, height: 180)));

      expect(tester.getSize(find.byType(Skeleton)), const Size(120, 180));
      expect(tester.hasRunningAnimations, isTrue);
      // A second sweep follows the first.
      await tester.pump(Skeleton.period * 1.5);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('stands still when animations are switched off', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const Skeleton(width: 120, height: 180), disableAnimations: true),
      );

      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  testWidgets('EmptyState shows its title, its message and its button', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      host(
        EmptyState(
          icon: DharaIcons.myList,
          title: 'Your list is empty',
          message: 'Press "My List" on any title to save it here.',
          action: DharaButton(
            label: 'Browse',
            small: true,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.text('Your list is empty'), findsOneWidget);
    expect(find.textContaining('Press "My List"'), findsOneWidget);
    await tester.tap(find.text('Browse'));
    expect(pressed, isTrue);
  });

  group('ToastHost', () {
    Widget app() => MaterialApp(
      builder: (context, child) => ToastHost(child: child!),
      home: Builder(
        builder: (context) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => ToastHost.show(
                  context,
                  'added to My List.',
                  lead: 'Harbor <b>Lights</b>',
                ),
                child: const Text('Add'),
              ),
              TextButton(
                onPressed: () => ToastHost.show(context, 'History cleared.'),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
      ),
    );
    double opacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byKey(const Key('toast')),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
    String shown(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('toast')),
            matching: find.byType(Text),
          ),
        )
        .textSpan!
        .toPlainText();

    testWidgets('shows a message for a while, then hides it', (tester) async {
      await tester.pumpWidget(app());
      expect(opacity(tester), 0);

      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(opacity(tester), 1);
      // The title is shown as written: markup in it is just text.
      expect(shown(tester), 'Harbor <b>Lights</b> added to My List.');

      await tester.pump(ToastHost.showFor - const Duration(milliseconds: 1));
      expect(opacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(opacity(tester), 0);
      await tester.pumpAndSettle();
    });

    testWidgets('a new message replaces the old one and gets its full time', (
      tester,
    ) async {
      await tester.pumpWidget(app());

      await tester.tap(find.text('Add'));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Clear'));
      await tester.pump(const Duration(seconds: 2));

      expect(shown(tester), 'History cleared.');
      expect(opacity(tester), 1);
      await tester.pump(const Duration(seconds: 1));
      expect(opacity(tester), 0);
      await tester.pumpAndSettle();
    });

    testWidgets('does not catch clicks meant for the page', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(
        find.ancestor(
          of: find.byKey(const Key('toast')),
          matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring,
          ),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle(ToastHost.showFor);
    });

    testWidgets('showing one without a host does nothing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => ToastHost.show(context, 'Nobody hears this'),
              child: const Text('Say'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Say'));
      await tester.pump();

      expect(find.byKey(const Key('toast')), findsNothing);
    });
  });

  group('placeholder art', () {
    // Numbers from the prototype's own hash() and rng(), run in node.
    test('hashes a name as the prototype does', () {
      expect(artHash(''), 2166136261);
      expect(artHash('a'), 3826002220);
      expect(artHash('Harbor Lights'), 2669025912);
      expect(artHash('Last Train to Meghna'), 3387400244);
      expect(artHash('ধারা'), 4118146946);
    });

    test('draws the same random numbers as the prototype', () {
      final random = ArtRandom(12345);

      expect(random.next(), 0.9797282677609473);
      expect(random.next(), 0.3067522644996643);
      expect(random.next(), 0.484205421525985);
    });

    test('picks colours, scene and focal point as the prototype does', () {
      final (tall, tallRest) = ArtSpec.of('Harbor Lights', wide: false);
      expect([tall.hue1, tall.hue2, tall.hue3], [205, 236, 186]);
      expect(tall.scene, ArtScene.waves);
      expect(tall.focalX, closeTo(0.28361233315430584, 1e-12));
      expect(tall.focalY, closeTo(0.43364213094115256, 1e-12));
      expect(tall.slanted, isFalse);
      expect(tallRest.next(), closeTo(0.8355937546584755, 1e-12));

      final (wide, _) = ArtSpec.of('Harbor Lights', wide: true);
      expect(wide.focalX, closeTo(0.6018061665771529, 1e-12));

      final (bangla, _) = ArtSpec.of('ধারা', wide: false);
      expect([bangla.hue1, bangla.hue2, bangla.hue3], [280, 333, 211]);
      expect(bangla.scene, ArtScene.waves);
      expect(bangla.slanted, isTrue);

      expect(ArtSpec.of('Tidebreaker', wide: false).$1.scene, ArtScene.orbit);
      expect(
        ArtSpec.of('Last Train to Meghna', wide: false).$1.scene,
        ArtScene.horizon,
      );
      expect(ArtSpec.of('Neon Monsoon', wide: false).$1.scene, ArtScene.shards);
    });

    test('never uses the yellow-green hues', () {
      for (var i = 0; i < 400; i++) {
        final (spec, _) = ArtSpec.of('title $i', wide: false);
        for (final hue in [spec.hue1, spec.hue2, spec.hue3]) {
          expect(hue < 50 || hue > 160, isTrue, reason: 'title $i: $hue');
        }
      }
    });

    testWidgets('every scene paints, tall and wide, and fills its box', (
      tester,
    ) async {
      final seeds = <ArtScene, String>{};
      for (var i = 0; seeds.length < ArtScene.values.length; i++) {
        seeds.putIfAbsent(ArtSpec.of('seed $i', wide: false).$1.scene, () {
          return 'seed $i';
        });
      }

      for (final seed in seeds.values) {
        for (final wide in [false, true]) {
          final key = GlobalKey();
          await tester.pumpWidget(
            host(
              RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: wide ? 160 : 90,
                  height: wide ? 90 : 135,
                  child: PlaceholderArt(seed: seed, wide: wide),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull, reason: '$seed wide=$wide');

          // No corner is left unpainted.
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            for (final (x, y) in [
              (0, 0),
              (image.width - 1, 0),
              (0, image.height - 1),
              (image.width - 1, image.height - 1),
            ]) {
              final alpha = bytes.getUint8((y * image.width + x) * 4 + 3);
              expect(alpha, 255, reason: '$seed wide=$wide at $x,$y');
            }
          });
        }
      }
    });

    testWidgets('repaints only for another name or shape', (tester) async {
      CustomPainter painter() => tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(PlaceholderArt),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;
      Future<CustomPainter> pump(String seed, {bool wide = false}) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 90,
              height: 135,
              child: PlaceholderArt(seed: seed, wide: wide),
            ),
          ),
        );
        return painter();
      }

      final first = await pump('Harbor Lights');
      expect((await pump('Harbor Lights')).shouldRepaint(first), isFalse);
      expect((await pump('Neon Monsoon')).shouldRepaint(first), isTrue);
      expect(
        (await pump('Harbor Lights', wide: true)).shouldRepaint(first),
        isTrue,
      );
    });
  });

  testWidgets('DharaLogo is a square of the size asked for', (tester) async {
    await tester.pumpWidget(host(const DharaLogo(size: 48)));

    expect(tester.getSize(find.byType(DharaLogo)), const Size.square(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every drawing of DharaLogo can be drawn', (tester) async {
    for (final style in DharaLogoStyle.values) {
      await tester.pumpWidget(host(DharaLogo(size: 64, style: style)));

      expect(tester.getSize(find.byType(DharaLogo)), const Size.square(64));
      expect(tester.takeException(), isNull, reason: style.name);
    }
  });
}
