import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app_theme.dart';
import 'core/read_log.dart';
import 'core/settings.dart';
import 'features/providers.dart';
import 'features/shell.dart';

/// Size the window opens at. Wide enough for the list and the reading pane
/// side by side, which the shell switches to at 940.
const kInitialWindowSize = Size(1200, 640);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppSettings.bootstrap = await AppSettings.load();
  ReadLog.bootstrap = await ReadLog.load();
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: kInitialWindowSize,
      minimumSize: Size(880, 560),
      center: true,
      title: 'Codora',
      // The traffic lights sit inside our own top bar rather than a separate
      // title bar, so the rail and the feed start at the top of the window.
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Color(0xFF121016),
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(const ProviderScope(child: CodoraApp()));
}

class CodoraApp extends ConsumerWidget {
  const CodoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider).themeMode;
    return MaterialApp(
      title: 'Codora',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeAnimationDuration: Motion.theme,
      themeAnimationCurve: Motion.curve,
      themeMode: switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: const AppShell(),
      scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
    );
  }
}
