// Colour choices are easy to make and easy to break. These check the pairings
// people actually read, in both themes, rather than describing the palette.
import 'dart:math' as math;

import 'package:codora/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Hue in degrees, for checking a palette stays in one colour family.
double hueOf(Color c) => HSLColor.fromColor(c).hue;

void main() {
  final themes = {'dark': Palette.dark, 'light': Palette.light};

  group('text stays readable', () {
    themes.forEach((name, p) {
      test('body and secondary text in $name', () {
        expect(contrast(p.ink, p.panel), greaterThanOrEqualTo(4.5));
        expect(contrast(p.ink, p.canvas), greaterThanOrEqualTo(4.5));
        expect(contrast(p.inkMuted, p.panel), greaterThanOrEqualTo(4.5));
        // Faint text is for timestamps and slugs, held to the large-text bar.
        expect(contrast(p.inkFaint, p.panel), greaterThanOrEqualTo(3.0));
      });

      test('buttons and selection in $name', () {
        expect(contrast(p.accentInk, p.accent), greaterThanOrEqualTo(4.5));
        expect(contrast(p.ink, p.accentSoft), greaterThanOrEqualTo(4.5));
      });

      test('status colours in $name', () {
        for (final entry in {'cream': p.cream, 'mint': p.mint, 'rose': p.rose}
            .entries) {
          expect(contrast(entry.value, p.panel), greaterThanOrEqualTo(4.5),
              reason: '${entry.key} on a card');
        }
      });
    });
  });

  group('surfaces stay distinguishable', () {
    themes.forEach((name, p) {
      test('in $name', () {
        // A card must not vanish into the page behind it, and a rule must be
        // visible on a card without becoming a line of text.
        expect(contrast(p.canvas, p.panel), greaterThan(1.03));
        expect(contrast(p.line, p.panel), greaterThan(1.15));
        expect(contrast(p.raised, p.panel), greaterThan(1.02));
      });
    });
  });

  group('the light theme is white and purple', () {
    final p = Palette.light;

    test('the page is white, with only a hint of colour', () {
      // Near enough to white to read as white paper.
      expect(contrast(p.canvas, const Color(0xFFFFFFFF)), lessThan(1.1));
      expect(p.panel, const Color(0xFFFFFFFF));
    });

    test('every surface and rule is the same purple family', () {
      for (final entry in {
        'canvas': p.canvas,
        'raised': p.raised,
        'line': p.line,
        'accentSoft': p.accentSoft,
        'ink': p.ink,
        'inkMuted': p.inkMuted,
        'accent': p.accent,
      }.entries) {
        expect(hueOf(entry.value), inInclusiveRange(245, 285),
            reason: '${entry.key} drifts out of the violet range');
      }
    });

    test('nothing is the old warm paper', () {
      // The palette used to be cream with warm grey rules.
      for (final surface in [p.canvas, p.raised, p.line]) {
        expect(hueOf(surface), isNot(inInclusiveRange(20, 60)),
            reason: 'a warm hue would read as the previous design');
      }
    });

    test('saturated purple is reserved, not the background', () {
      final accentSaturation = HSLColor.fromColor(p.accent).saturation;
      final canvasSaturation = HSLColor.fromColor(p.canvas).saturation;
      expect(accentSaturation, greaterThan(0.6));
      expect(HSLColor.fromColor(p.canvas).lightness, greaterThan(0.95),
          reason: 'the page stays paper, not a purple wash');
      expect(canvasSaturation, lessThan(accentSaturation));
    });
  });

  test('the badge purple is shared by both themes', () {
    expect(Palette.light.badge, Palette.dark.badge);
    expect(Palette.light.badge, isNot(Palette.light.accent),
        reason: 'a badge must not be mistaken for a selection');
    expect(Palette.dark.badge, isNot(Palette.dark.accent));
  });
}
