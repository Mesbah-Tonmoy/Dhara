import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The app's dark theme, built from the design tokens.
///
/// Interface text uses Inter; display, headline and title styles use
/// Plus Jakarta Sans. The app has this one theme only, so widgets read the
/// tokens (`DharaColors`, `DharaType`, ...) directly; what is set here is
/// what Material's own widgets need to fit in.
ThemeData buildDharaTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: DharaColors.accent,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: DharaColors.bg,
    fontFamily: DharaFonts.ui,
  );

  TextStyle? display(TextStyle? style) =>
      style?.copyWith(fontFamily: DharaFonts.display);

  final text = base.textTheme;
  return base.copyWith(
    textTheme: text.copyWith(
      displayLarge: display(text.displayLarge),
      displayMedium: display(text.displayMedium),
      displaySmall: display(text.displaySmall),
      headlineLarge: display(text.headlineLarge),
      headlineMedium: display(text.headlineMedium),
      headlineSmall: display(text.headlineSmall),
      titleLarge: display(text.titleLarge),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: DharaColors.accent,
      selectionColor: Color(0x668B6CFF),
    ),
    // Thin and quiet, as in the prototype.
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(.55 * rem),
      radius: Radius.circular(rem),
      thumbColor: WidgetStatePropertyAll(DharaColors.surface2),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(
        horizontal: .6 * rem,
        vertical: .3 * rem,
      ),
      decoration: BoxDecoration(
        color: DharaColors.bgElev,
        borderRadius: BorderRadius.circular(DharaRadii.sm),
        border: Border.all(color: DharaColors.stroke),
      ),
      textStyle: const TextStyle(
        fontFamily: DharaFonts.ui,
        fontSize: DharaType.xs,
        color: DharaColors.text,
      ),
    ),
  );
}
