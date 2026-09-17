// A missing or unregistered logo degrades silently to the letter fallback,
// which looks fine in a screenshot and is easy to miss. These checks fail loudly.
import 'dart:io';

import 'package:codora/app_theme.dart';
import 'package:codora/core/forum_source.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/sources/juejin_source.dart';
import 'package:codora/sources/linuxdo_source.dart';
import 'package:codora/sources/v2ex_source.dart';
import 'package:codora/widgets/site_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sources = <ForumSource>[
    V2exSource(),
    LinuxDoSource(cookie: '', userAgent: kDesktopUserAgent),
    JuejinSource(),
  ];

  test('every logo file is present and is a PNG', () {
    for (final source in sources) {
      final file = File(source.iconAsset);
      expect(file.existsSync(), isTrue, reason: '${source.name}: ${source.iconAsset}');
      final header = file.openSync().readSync(8);
      expect(header, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
          reason: '${source.name} is not a PNG');
    }
  });

  test('pubspec ships the icons directory', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = pubspec.split(RegExp(r'^\s*assets:\s*$', multiLine: true));
    expect(assets.length, greaterThan(1), reason: 'no assets section');
    expect(assets[1], contains('assets/icons/'));
  });

  test('logos are distinct per site', () {
    final paths = sources.map((s) => s.iconAsset).toSet();
    expect(paths, hasLength(sources.length));
  });

  testWidgets('a broken asset falls back to the letters', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(
        body: SiteIcon(asset: 'assets/icons/does-not-exist.png', glyph: 'V2'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('V2'), findsOneWidget);
  });
}
