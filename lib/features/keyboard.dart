import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme.dart';
import '../core/models.dart';
import 'providers.dart';

/// What the keyboard can ask of the topic list.
enum ListCommand { next, previous, refresh }

/// What the keyboard can ask of the reading pane.
enum DetailCommand { pageDown, pageUp, top, bottom, reload, copyLink, openInBrowser }

/// One press of a key, as a command.
///
/// Numbered so that pressing the same key twice is two commands: a provider
/// holding only the command would see the second press as no change at all.
class Command<T> {
  const Command(this.kind, this.serial);
  final T kind;
  final int serial;
}

/// The last command for each site's list. The list listens and carries it
/// out; the keyboard only has to say which site it meant.
final listCommandProvider =
    StateProvider.family<Command<ListCommand>?, SiteId>((_, _) => null);

/// The last command for each site's reading pane, which listens the same way.
final detailCommandProvider =
    StateProvider.family<Command<DetailCommand>?, SiteId>((_, _) => null);

int _serial = 0;

void sendListCommand(WidgetRef ref, SiteId site, ListCommand kind) =>
    ref.read(listCommandProvider(site).notifier).state =
        Command(kind, ++_serial);

void sendDetailCommand(WidgetRef ref, SiteId site, DetailCommand kind) =>
    ref.read(detailCommandProvider(site).notifier).state =
        Command(kind, ++_serial);

/// Every shortcut, in the order the help sheet lists them.
const kShortcuts = <(String keys, String what)>[
  ('J / K', '下一篇 / 上一篇'),
  ('↓ / ↑', '列表里下一篇 / 上一篇'),
  ('空格 / ⇧ 空格', '正文向下 / 向上翻一屏'),
  ('G G / ⇧ G', '正文回到顶部 / 跳到底部'),
  ('R', '刷新列表'),
  ('⇧ R', '重新加载正在读的帖子'),
  ('O', '在浏览器中打开正在读的帖子'),
  ('C', '复制正在读的帖子的链接'),
  ('⌘ 1 – 9', '切换到第几个站点'),
  ('⌘ ,', '打开设置'),
  ('?', '显示这张快捷键表'),
];

/// How close together the two presses of `g g` have to be.
const kChordWindow = Duration(milliseconds: 600);

/// The app's keyboard, above every page and route.
///
/// It sits above the navigator rather than inside the shell so that it still
/// hears keys while a thread is open as a page of its own in a narrow window.
/// Keys arrive here only after whatever has focus has passed on them, and a
/// text field is skipped outright: typing an `r` into a reply is not asking
/// for a refresh.
class AppKeyboard extends ConsumerStatefulWidget {
  const AppKeyboard({super.key, required this.navigatorKey, required this.child});

  /// For the help sheet, which is a dialog and needs a navigator under it.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<AppKeyboard> createState() => _AppKeyboardState();
}

class _AppKeyboardState extends ConsumerState<AppKeyboard> {
  final _focus = FocusNode(debugLabel: 'app-keyboard');
  DateTime? _lastG;
  bool _helpOpen = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  static bool get _typing {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Whether what has focus is something the space bar presses — a button,
  /// a switch — rather than somewhere the reader is reading.
  static bool get _onControl {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null && Actions.maybeFind<ActivateIntent>(context) != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_typing) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isMetaPressed || keyboard.isControlPressed;
    final shift = keyboard.isShiftPressed;
    if (keyboard.isAltPressed) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (command) {
      if (key == LogicalKeyboardKey.comma) {
        ref.read(navProvider.notifier).state = NavTarget.settings;
        return KeyEventResult.handled;
      }
      final digit = _digits.indexOf(key);
      if (digit >= 0) {
        final sites = ref.read(visibleSiteIdsProvider);
        if (digit < sites.length) {
          ref.read(navProvider.notifier).state = sites[digit].target;
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.character == '?' ||
        (shift && key == LogicalKeyboardKey.slash)) {
      _showHelp();
      return KeyEventResult.handled;
    }

    // A focused button takes the space bar to press itself.
    if (key == LogicalKeyboardKey.space && _onControl) {
      return KeyEventResult.ignored;
    }

    final site = ref.read(currentNavProvider).site;
    // Repeats are only worth following for keys that move through things.
    final repeat = event is KeyRepeatEvent;
    if (site == null) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.keyJ) {
      sendListCommand(ref, site, ListCommand.next);
    } else if (key == LogicalKeyboardKey.keyK) {
      sendListCommand(ref, site, ListCommand.previous);
    } else if (key == LogicalKeyboardKey.space) {
      sendDetailCommand(
          ref, site, shift ? DetailCommand.pageUp : DetailCommand.pageDown);
    } else if (repeat) {
      return KeyEventResult.ignored;
    } else if (key == LogicalKeyboardKey.keyG) {
      if (shift) {
        sendDetailCommand(ref, site, DetailCommand.bottom);
      } else {
        final now = DateTime.now();
        final last = _lastG;
        if (last != null && now.difference(last) <= kChordWindow) {
          _lastG = null;
          sendDetailCommand(ref, site, DetailCommand.top);
        } else {
          _lastG = now;
        }
      }
    } else if (key == LogicalKeyboardKey.keyR) {
      if (shift) {
        sendDetailCommand(ref, site, DetailCommand.reload);
      } else {
        sendListCommand(ref, site, ListCommand.refresh);
      }
    } else if (key == LogicalKeyboardKey.keyO) {
      sendDetailCommand(ref, site, DetailCommand.openInBrowser);
    } else if (key == LogicalKeyboardKey.keyC) {
      sendDetailCommand(ref, site, DetailCommand.copyLink);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  Future<void> _showHelp() async {
    final context = widget.navigatorKey.currentContext;
    if (context == null || _helpOpen) return;
    _helpOpen = true;
    try {
      await showDialog<void>(
          context: context, builder: (_) => const ShortcutSheet());
    } finally {
      _helpOpen = false;
      // The dialog took focus with it; take it back so the next key lands.
      if (mounted && FocusManager.instance.primaryFocus == null) {
        _focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}

/// The shortcuts, as a sheet over the app.
class ShortcutSheet extends StatelessWidget {
  const ShortcutSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Dialog(
      backgroundColor: p.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: p.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('快捷键', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('在回复框里打字时不会触发。',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              for (final (keys, what) in kShortcuts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(
                      width: 128,
                      child: Text(keys,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: p.ink,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ),
                    Expanded(
                      child: Text(what,
                          style: TextStyle(fontSize: 12.5, color: p.inkMuted)),
                    ),
                  ]),
                ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
