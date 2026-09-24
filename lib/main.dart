import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app_theme.dart';
import 'core/disk_cache.dart';
import 'core/last_place.dart';
import 'core/linuxdo_session.dart';
import 'core/read_log.dart';
import 'core/settings.dart';
import 'core/window_place.dart';
import 'features/providers.dart';
import 'features/shell.dart';

/// Size the window first opens at. Wide enough for the list and the reading
/// pane side by side, which the shell switches to at 940. After that it opens
/// wherever and however large the reader last left it.
const kInitialWindowSize = Size(1200, 640);

const kMinimumWindowSize = Size(880, 560);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppSettings.bootstrap = await AppSettings.load();
  ReadLog.bootstrap = await ReadLog.load();
  LastPlace.bootstrap = await LastPlace.load();
  // Opened before the first frame so the first avatar already has somewhere
  // to look, and trimmed now in case the budget was lowered last time.
  await DiskCache.instance.prepare(budget: AppSettings.bootstrap.cacheLimit);
  // The browser linux.do is read through starts each launch with whatever
  // WebKit persisted, and that is what actually goes out — so the two copies
  // are brought into agreement, the browser's winning where it has one. A
  // launch failing to do so must not stop the app opening.
  try {
    final header = await adoptLinuxDoCookies(AppSettings.bootstrap.linuxdoCookie);
    if (header != AppSettings.bootstrap.linuxdoCookie) {
      AppSettings.bootstrap =
          AppSettings.bootstrap.copyWith(linuxdoCookie: header);
      await AppSettings.bootstrap.save();
    }
  } catch (_) {}
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    final saved = LastPlace.bootstrap.window;
    final frame = saved == null
        ? null
        : restorableFrame(saved, await visibleDisplays(),
            minimum: kMinimumWindowSize);
    final options = WindowOptions(
      size: frame?.size ?? kInitialWindowSize,
      minimumSize: kMinimumWindowSize,
      center: frame?.position == null,
      title: 'Codora',
      // The traffic lights sit inside our own top bar rather than a separate
      // title bar, so the rail and the feed start at the top of the window.
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: const Color(0xFF121016),
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (frame?.position case final position?) {
        await windowManager.setPosition(position);
      }
      await windowManager.show();
      await windowManager.focus();
    });
    WindowPlaceKeeper.instance.start();
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
