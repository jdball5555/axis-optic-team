import 'package:flutter/material.dart';

class AppTheme {
  // Main Colors
  static const Color sideBar = Color(0xFF1F1F1F);
  static const Color border = Color(0xFF333333); // Lightened from 0xFF262626
  static const Color mainBackground = Color(0xFF141414); // Darkened from 0xFF181818
  static const Color gray = Color(0xFFC9C9C9);
  static const Color primaryText = Color(0xFFD7D7D7);
  
  // ---------------------------------------------------------------------------
  // Palette: every color has a dark-mode and a light-mode shade.
  // ---------------------------------------------------------------------------
  static const Color redDark = Color(0xFFAA4848);
  static const Color redLight = Color(0xFFFF6C6C);
  static const Color tealDark = Color(0xFF3F8F88);
  static const Color tealLight = Color(0xFF61D3CA);
  static const Color greenDark = Color(0xFF6B9657);
  static const Color greenLight = Color(0xFF96D37A);
  static const Color purpleDark = Color(0xFF705C8A);
  static const Color purpleLight = Color(0xFFD2AEFF);
  static const Color yellowDark = Color(0xFFAC9962);
  static const Color yellowLight = Color(0xFFF5DB90);
  static const Color orangeDark = Color(0xFFAD6A47);
  static const Color orangeLight = Color(0xFFFF9E6C);
  static const Color pinkDark = Color(0xFFCFA3C6);
  static const Color pinkLight = Color(0xFFFFC8F4);
  static const Color blueDark = Color(0xFF8AA5BB);
  static const Color blueLight = Color(0xFFBEE2FF);

  /// Appearance → "Bright colors": the bright shades when on, the dim ones
  /// when off (in either light or dark mode). Set by the app (main.dart).
  static bool brightColors = false;

  static Color _pick(Color dim, Color bright) => brightColors ? bright : dim;

  /// Whether the light theme is showing (set by the app). Colored tiles are
  /// drawn stronger on light backgrounds, where faint tints disappear.
  static bool isLightTheme = false;

  /// Fill for a colored tile, pill or badge.
  static Color tint(Color c) => c.withValues(alpha: isLightTheme ? 0.26 : 0.14);

  /// Border for a colored tile: solid enough to actually see the color.
  static Color edge(Color c) => isLightTheme ? c : c.withValues(alpha: 0.9);

  /// Border width for colored tiles.
  static const double edgeWidth = 2;

  /// Text drawn in a color on a tinted tile (darker on light backgrounds so
  /// it stays readable).
  static Color onTint(Color c) =>
      isLightTheme ? Color.lerp(c, Colors.black, 0.35)! : c;

  static Color get red => _pick(redDark, redLight);
  static Color get teal => _pick(tealDark, tealLight);
  static Color get green => _pick(greenDark, greenLight);
  static Color get purple => _pick(purpleDark, purpleLight);
  static Color get yellow => _pick(yellowDark, yellowLight);
  static Color get orange => _pick(orangeDark, orangeLight);
  static Color get pink => _pick(pinkDark, pinkLight);
  static Color get blue => _pick(blueDark, blueLight);

  /// Primary accent: buttons, highlights, selected items.
  static Color get accent => red;

  /// Secondary accent: selected toggles / chips and supporting highlights.
  static Color get accent2 => teal;

  // Older names, kept so existing code reads the new palette.
  static Color get lightBlue => blue;
  static Color get darkBlue => blue;
  static Color get primaryRed => red;
  static const Color slate = gray;
  static const Color background = mainBackground;

  /// Colors offered wherever you pick a color (titles, tags, checklists).
  static const List<String> colorNames = [
    'Red',
    'Teal',
    'Green',
    'Purple',
    'Yellow',
    'Orange',
    'Pink',
    'Blue',
  ];

  /// Older saved color names → the closest new one.
  static const Map<String, String> _legacyColorNames = {
    'Warm Cream': 'Yellow',
    'Vibrant Orange': 'Orange',
    'Sky Cyan': 'Teal',
    'Primary Blue': 'Blue',
    'Dusty Rose': 'Pink',
    'Emerald Green': 'Green',
    'Deep Plum': 'Purple',
  };

  /// A saved color name in today's terms ('Color' = none picked).
  static String normalizeColorName(String? name) {
    if (name == null || name.isEmpty) return 'Color';
    if (colorNames.contains(name)) return name;
    return _legacyColorNames[name] ?? 'Color';
  }

  static ThemeData darkTheme({required bool bright}) {
    final primary = bright ? redLight : redDark;
    final secondary = bright ? tealLight : tealDark;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        onSecondary: bright ? const Color(0xFF111111) : Colors.white,
        // Selected/pressed states for chips, toggles, segmented buttons.
        secondaryContainer: Color(0xFF2A3F3D),
        onSecondaryContainer: tealLight,
        surface: sideBar,
        background: mainBackground,
        onSurface: primaryText,
        onBackground: primaryText,
        outline: border,
      ),
      scaffoldBackgroundColor: mainBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: sideBar,
        foregroundColor: primaryText,
        elevation: 0,
      ),
      cardColor: sideBar,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: primaryText),
        bodyMedium: TextStyle(color: primaryText),
        bodySmall: TextStyle(color: gray),
        titleLarge: TextStyle(color: primaryText, fontWeight: FontWeight.bold),
      ),
      dividerColor: border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: mainBackground,
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: border),
          borderRadius: BorderRadius.circular(4),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: border),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: primary),
          borderRadius: BorderRadius.circular(4),
        ),
        labelStyle: const TextStyle(color: gray, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      chipTheme: ChipThemeData(
        selectedColor: secondary.withValues(alpha: 0.3),
        checkmarkColor: tealLight,
        pressElevation: 0,
        side: const BorderSide(color: border),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: sideBar,
        contentTextStyle: TextStyle(color: primaryText),
        actionTextColor: redLight,
      ),
    );
  }

  static ThemeData lightTheme({required bool bright}) {
    final primary = bright ? redLight : redDark;
    final secondary = bright ? tealLight : tealDark;
    const Color lightTile = Color(0xFFFAFAFA);
    const Color lightBackground = Color(0xFFEBEBEB);
    const Color lightTopBar = Color(0xFFACACAC);
    const Color lightText = Color(0xFF111111);
    const Color lightGray = Color(0xFF555555);
    const Color lightBorder = Color(0xFFD6D6D6); // Lightened from 0xFFACACAC

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        onSecondary: bright ? const Color(0xFF111111) : Colors.white,
        // See note in darkTheme. Deeper teal for text on light backgrounds.
        secondaryContainer: Color(0xFFD6F4F1),
        onSecondaryContainer: tealDark,
        surface: lightTile,
        background: lightBackground,
        onSurface: lightText,
        onBackground: lightText,
        outline: lightBorder,
      ),
      scaffoldBackgroundColor: lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: lightTopBar,
        foregroundColor: lightText,
        elevation: 0,
      ),
      cardColor: lightTile,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: lightText),
        bodyMedium: TextStyle(color: lightText),
        bodySmall: TextStyle(color: lightGray),
        titleLarge: TextStyle(color: lightText, fontWeight: FontWeight.bold),
      ),
      dividerColor: lightBorder,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightTile,
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: lightBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: lightBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: primary),
          borderRadius: BorderRadius.circular(4),
        ),
        labelStyle: const TextStyle(color: lightGray, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      chipTheme: ChipThemeData(
        selectedColor: secondary.withValues(alpha: 0.3),
        checkmarkColor: Color(0xFF1F7F78),
        pressElevation: 0,
        side: const BorderSide(color: lightBorder),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: lightTile,
        contentTextStyle: TextStyle(color: lightText),
        actionTextColor: redDark,
      ),
    );
  }

  /// The color for a saved color name (grey when none is picked).
  static Color getColorFromName(String name) =>
      switch (normalizeColorName(name)) {
        'Red' => red,
        'Teal' => teal,
        'Green' => green,
        'Purple' => purple,
        'Yellow' => yellow,
        'Orange' => orange,
        'Pink' => pink,
        'Blue' => blue,
        _ => Colors.grey,
      };
}
