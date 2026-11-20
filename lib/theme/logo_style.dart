/// The drawings of the app's mark. All are a play triangle and a wave
/// ("dhara": a stream) in a rounded square. Which one the app shows is a
/// setting; the program's icon in Windows is always [darkWater].
enum DharaLogoStyle {
  /// A rounded play triangle over water that fills the lower part, on a
  /// deep gradient.
  water('Water'),

  /// The first mark: a sharp triangle over one wave, on the accent gradient.
  classic('Classic'),

  /// The first mark in the accent colours on a dark square.
  dark('Dark'),

  /// A rounded triangle over two waves, on the accent gradient.
  rounded('Rounded'),

  /// [dark] with the triangle's corners rounded.
  darkRounded('Dark, rounded'),

  /// [water] in the accent colours on a dark square.
  darkWater('Dark water');

  const DharaLogoStyle(this.label);

  /// What Settings calls it.
  final String label;
}

/// The drawing the app shows until another is chosen in Settings:
/// [DharaLogoStyle.darkWater], or the one a build names with
/// `--dart-define=DHARA_LOGO=<name>` (`tool/package.ps1 -Logo`).
final DharaLogoStyle defaultLogoStyle =
    DharaLogoStyle.values.asNameMap()[const String.fromEnvironment(
      'DHARA_LOGO',
    )] ??
    DharaLogoStyle.darkWater;
