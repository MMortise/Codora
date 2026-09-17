import 'package:flutter/material.dart';

/// Codora palette. Dark is the primary mode: a violet-leaning near-black with
/// a lavender accent for anything selected, cream for counts, mint for
/// "signed in", rose for failures. Light mode keeps the same roles on a warm
/// paper canvas.
class Palette {
  const Palette({
    required this.canvas,
    required this.panel,
    required this.raised,
    required this.line,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.cream,
    required this.mint,
    required this.rose,
    required this.badge,
    required this.onBadge,
  });

  final Color canvas;
  final Color panel;
  final Color raised;
  final Color line;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;

  /// Filled selection colour (blocks, chips, primary buttons).
  final Color accent;

  /// Text drawn on top of [accent].
  final Color accentInk;

  /// Low-contrast wash of the accent, for hover and selected rows.
  final Color accentSoft;

  final Color cream;
  final Color mint;
  final Color rose;

  /// Saturated purple for count badges. Deliberately darker than [accent] so a
  /// badge never reads as a selection, and identical in both themes so a card
  /// looks the same whichever theme it is on.
  final Color badge;

  /// Text on [badge]. White sits at 4.47:1 against it, a shade under the 4.5
  /// bar for body text; the gap is not perceptible at this size.
  final Color onBadge;

  static const dark = Palette(
    canvas: Color(0xFF121016),
    panel: Color(0xFF1B1725),
    raised: Color(0xFF251E33),
    line: Color(0xFF322A44),
    ink: Color(0xFFF3F0FA),
    inkMuted: Color(0xFF9B93AE),
    inkFaint: Color(0xFF6C6480),
    accent: Color(0xFFCFC2FF),
    accentInk: Color(0xFF1B1030),
    accentSoft: Color(0xFF2C2340),
    cream: Color(0xFFF5D66B),
    mint: Color(0xFF7EE787),
    rose: Color(0xFFFF5C8A),
    badge: Color(0xFF9856DC),
    onBadge: Color(0xFFFFFFFF),
  );

  /// Blends two palettes so switching theme crossfades rather than snaps.
  static Palette lerp(Palette a, Palette b, double t) {
    Color mix(Color x, Color y) => Color.lerp(x, y, t) ?? y;
    return Palette(
      canvas: mix(a.canvas, b.canvas),
      panel: mix(a.panel, b.panel),
      raised: mix(a.raised, b.raised),
      line: mix(a.line, b.line),
      ink: mix(a.ink, b.ink),
      inkMuted: mix(a.inkMuted, b.inkMuted),
      inkFaint: mix(a.inkFaint, b.inkFaint),
      accent: mix(a.accent, b.accent),
      accentInk: mix(a.accentInk, b.accentInk),
      accentSoft: mix(a.accentSoft, b.accentSoft),
      cream: mix(a.cream, b.cream),
      mint: mix(a.mint, b.mint),
      rose: mix(a.rose, b.rose),
      badge: mix(a.badge, b.badge),
      onBadge: mix(a.onBadge, b.onBadge),
    );
  }

  /// Purple ink on white paper. The canvas carries just enough violet to stop
  /// a white card disappearing into it, every rule and recessed surface is a
  /// tint of the same hue, and text is a near-black violet rather than pure
  /// black. Saturated purple is spent only on selection and primary actions.
  static const light = Palette(
    canvas: Color(0xFFF8F6FD),
    panel: Color(0xFFFFFFFF),
    raised: Color(0xFFF1ECFC),
    line: Color(0xFFE3DBF6),
    ink: Color(0xFF1C1430),
    inkMuted: Color(0xFF5C5378),
    inkFaint: Color(0xFF8E86A6),
    accent: Color(0xFF6D34E8),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFEDE4FF),
    // Darkened from their dark-theme values: the same hues sit on white here,
    // where a light tone would not be readable.
    cream: Color(0xFF936205),
    mint: Color(0xFF177334),
    rose: Color(0xFFCE2F62),
    badge: Color(0xFF9856DC),
    onBadge: Color(0xFFFFFFFF),
  );
}

/// Motion is here to answer an action: it shows what changed and where the
/// new thing came from. One scale for everything, so switches feel like the
/// same app rather than a collection of effects.
class Motion {
  /// Hover, press, colour changes.
  static const quick = Duration(milliseconds: 120);

  /// Content swapping in: a board, a post, a site.
  static const swap = Duration(milliseconds: 180);

  /// Theme changes, which repaint the whole window.
  static const theme = Duration(milliseconds: 240);

  static const curve = Curves.easeOutCubic;

  /// How far content drifts as it fades in. Small enough to read as settling,
  /// not as sliding.
  static const drift = 8.0;
}

/// Every control the user can click or type into is this tall, so buttons and
/// fields sitting on one row line up exactly.
const kControlHeight = 40.0;

/// Corner radii carry hierarchy: panels are the softest, cards sit inside
/// them, pills are fully round. Nothing else gets a radius.
class Radii {
  static const panel = 22.0;
  static const card = 16.0;
  static const block = 12.0;

  /// Every picture inside a post body, whichever renderer drew it.
  static const image = 10.0;
  static const pill = 999.0;
}

@immutable
class CodoraTheme extends ThemeExtension<CodoraTheme> {
  const CodoraTheme({required this.palette});
  final Palette palette;

  @override
  CodoraTheme copyWith({Palette? palette}) =>
      CodoraTheme(palette: palette ?? this.palette);

  @override
  CodoraTheme lerp(CodoraTheme? other, double t) {
    if (other == null) return this;
    return CodoraTheme(palette: Palette.lerp(palette, other.palette, t));
  }
}

extension CodoraThemeContext on BuildContext {
  Palette get palette =>
      Theme.of(this).extension<CodoraTheme>()?.palette ?? Palette.dark;
}

const kDisplayFont = 'Outfit';

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.accentInk,
    primaryContainer: p.accentSoft,
    onPrimaryContainer: p.ink,
    secondary: p.cream,
    onSecondary: p.accentInk,
    secondaryContainer: p.raised,
    onSecondaryContainer: p.ink,
    error: p.rose,
    onError: p.accentInk,
    surface: p.canvas,
    onSurface: p.ink,
    surfaceContainerLowest: p.canvas,
    surfaceContainerLow: p.panel,
    surfaceContainer: p.panel,
    surfaceContainerHigh: p.raised,
    surfaceContainerHighest: p.raised,
    onSurfaceVariant: p.inkMuted,
    outline: p.line,
    outlineVariant: p.line,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: brightness,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    fontFamily: kDisplayFont,
    fontFamilyFallback: const ['PingFang SC', 'Heiti SC', 'Microsoft YaHei'],
  );

  return base.copyWith(
    scaffoldBackgroundColor: p.canvas,
    canvasColor: p.canvas,
    extensions: [CodoraTheme(palette: p)],
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: p.inkMuted, size: 18),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.line),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(Radii.pill),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(Radii.block),
        border: Border.all(color: p.line),
      ),
      textStyle: TextStyle(color: p.ink, fontSize: 12),
    ),
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: p.accent.withValues(alpha: 0.32),
      cursorColor: p.accent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.accentInk,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.block)),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        minimumSize: const Size(0, kControlHeight),
        maximumSize: const Size.fromHeight(kControlHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        // The global compact density would shave 8px off minimumSize.
        visualDensity: VisualDensity.standard,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.line),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.block)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        minimumSize: const Size(0, kControlHeight),
        maximumSize: const Size.fromHeight(kControlHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.inkMuted,
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.canvas,
      isDense: true,
      // Single-line fields land exactly on kControlHeight; a multi-line field
      // grows from the same top and bottom inset.
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      constraints: const BoxConstraints(minHeight: kControlHeight),
      labelStyle: TextStyle(color: p.inkMuted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.block),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.block),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.block),
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearMinHeight: 2,
    ),
    // Material's default switch reads its off-state from `outline`, which is
    // our hairline colour and all but invisible on the surface it sits on.
    // On is the same accent fill every other selected control uses.
    switchTheme: SwitchThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return p.raised.withValues(alpha: 0.5);
        }
        return states.contains(WidgetState.selected) ? p.accent : p.raised;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? p.accent : p.line),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.accentInk;
        return states.contains(WidgetState.disabled) ? p.line : p.inkFaint;
      }),
      overlayColor: WidgetStatePropertyAll(p.accent.withValues(alpha: 0.10)),
    ),
    textTheme: base.textTheme.copyWith(
      headlineMedium: TextStyle(
          fontSize: 27, height: 1.25, fontWeight: FontWeight.w600, color: p.ink, letterSpacing: -0.4),
      titleLarge: TextStyle(
          fontSize: 20, height: 1.3, fontWeight: FontWeight.w600, color: p.ink, letterSpacing: -0.2),
      titleMedium: TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w600, color: p.ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.55, color: p.ink),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.45, color: p.inkMuted),
      labelSmall: TextStyle(fontSize: 11, height: 1.2, color: p.inkFaint, letterSpacing: 0.2),
    ),
  );
}
