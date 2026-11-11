import 'dart:io';
import 'dart:ui';

import 'package:dhara/theme/theme.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fontFiles = {
  DharaFonts.ui: 'assets/fonts/Inter/Inter-Variable.ttf',
  DharaFonts.display:
      'assets/fonts/PlusJakartaSans/PlusJakartaSans-Variable.ttf',
};

void main() {
  test('every bundled font is declared in pubspec.yaml and ships a licence',
      () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    for (final MapEntry(key: family, value: path) in _fontFiles.entries) {
      expect(pubspec, contains('family: $family'));
      expect(pubspec, contains('asset: $path'));
      expect(File(path).existsSync(), isTrue, reason: path);
      final licence = File('${File(path).parent.path}/OFL.txt');
      expect(licence.existsSync(), isTrue, reason: licence.path);
      expect(licence.readAsStringSync(), contains('SIL Open Font License'));
    }
  });

  test('no font is fetched at runtime', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, isNot(contains('google_fonts')));
  });

  test('theme uses Inter for the interface and Plus Jakarta Sans for titles',
      () {
    final text = buildDharaTheme().textTheme;

    expect(text.bodyMedium?.fontFamily, 'Inter');
    expect(text.labelLarge?.fontFamily, 'Inter');
    expect(text.displaySmall?.fontFamily, 'Plus Jakarta Sans');
    expect(text.headlineMedium?.fontFamily, 'Plus Jakarta Sans');
    expect(text.titleLarge?.fontFamily, 'Plus Jakarta Sans');
  });

  // The fonts are variable fonts with a single file per family, so bold text
  // depends on Flutter mapping FontWeight onto the font's weight axis.
  testWidgets('heavier weights really render heavier', (tester) async {
    for (final MapEntry(key: family, value: path) in _fontFiles.entries) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await tester.runAsync(loader.load);

      Future<int> ink(FontWeight weight) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: Colors.white,
                  child: Text(
                    'Hamburgefonstiv 0123456789',
                    style: TextStyle(
                      fontFamily: family,
                      fontWeight: weight,
                      fontSize: 40,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await tester.runAsync(boundary.toImage);
        final data = await tester.runAsync(
          () => image!.toByteData(format: ImageByteFormat.rawRgba),
        );
        final bytes = data!.buffer.asUint8List();
        var dark = 0;
        for (var i = 0; i < bytes.length; i += 4) {
          if (bytes[i] < 128) dark++;
        }
        return dark;
      }

      final regular = await ink(FontWeight.w400);
      final semiBold = await ink(FontWeight.w600);
      final extraBold = await ink(FontWeight.w800);

      expect(regular, greaterThan(1000), reason: '$family draws glyphs');
      expect(semiBold, greaterThan(regular * 1.15), reason: family);
      expect(extraBold, greaterThan(semiBold * 1.15), reason: family);
    }
  });
}
