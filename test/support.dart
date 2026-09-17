// Shared scaffolding for tests that touch stored settings.
import 'package:codora/app_theme.dart';
import 'package:codora/core/read_log.dart';
import 'package:codora/core/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clears the process-wide state the app loads before its first frame.
///
/// `AppSettings.bootstrap` and `ReadLog.bootstrap` are statics, so a test that
/// left one set would decide where the next file starts. Call once per `main`.
void resetBootstrapState() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettings.bootstrap = const AppSettings();
    ReadLog.bootstrap = ReadLog.bootstrap.cleared();
  });
  tearDown(() => AppSettings.bootstrap = const AppSettings());
}

/// A container reading [settings], disposed when the test ends.
ProviderContainer containerWith([AppSettings settings = const AppSettings()]) {
  AppSettings.bootstrap = settings;
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

/// Pumps [child] as the app would, and hands back the container behind it so a
/// test can read what the widgets read.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget child, {
  AppSettings settings = const AppSettings(),
  Size? size,
}) async {
  final container = containerWith(settings);
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: child),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}
