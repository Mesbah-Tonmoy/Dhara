import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The app's dark theme, built from the design tokens.
///
/// Interface text uses Inter; display, headline and title styles use
/// Plus Jakarta Sans.
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
  );
}
