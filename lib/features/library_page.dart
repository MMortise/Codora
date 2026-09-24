import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../widgets/chrome.dart';
import 'providers.dart';
import 'shell.dart' show kGutter;
import 'topic_detail.dart';
import 'topic_list.dart';

enum LibraryTab {
  bookmarks('收藏'),
  history('历史');

  const LibraryTab(this.label);
  final String label;
}

final libraryTabProvider =
    StateProvider<LibraryTab>((_) => LibraryTab.bookmarks);

/// Topics from every site the reader has kept or read, in one list, with the
/// same reading pane beside it as a site's.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  /// Opened topics, the last on screen — links followed inside a thread
  /// stack up here, as they do in a site's pane.
  List<TopicRef> _stack = const [];

  void _open(BuildContext context, SavedTopic t, {required bool page}) {
    ref.read(readLogProvider.notifier).markRead(t.site, t.id);
    if (page) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TopicDetailPage(topic: t.ref, title: t.title)));
      return;
    }
    setState(() => _stack = [t.ref]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tab = ref.watch(libraryTabProvider);
    final library = ref.watch(libraryProvider);
    final readLog = ref.watch(readLogProvider);
    final entries =
        tab == LibraryTab.bookmarks ? library.bookmarks : library.history;
    final selected = _stack.isEmpty ? null : _stack.first;

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 940;
      final list = entries.isEmpty
          ? Panel(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    tab == LibraryTab.bookmarks
                        ? '还没有收藏。读帖子时点右上角的书签，就会收在这里。'
                        : '还没有浏览记录。读过的帖子会按时间列在这里。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final t = entries[i];
                return TopicCard(
                  key: ValueKey('${tab.name}-${t.site.name}-${t.id}'),
                  topic: t.toSummary(),
                  selected: t.ref == selected,
                  read: readLog.contains(t.site, t.id),
                  images: ref.watch(siteImagesProvider(t.site)),
                  onTap: () => _open(context, t, page: !wide),
                );
              },
            );

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Clears the traffic lights, and matches a site's top bar.
        SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.only(left: kGutter, right: kGutter),
            child: Row(children: [
              for (final t in LibraryTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Tab(
                    label: t.label,
                    selected: t == tab,
                    onTap: () =>
                        ref.read(libraryTabProvider.notifier).state = t,
                  ),
                ),
              const Spacer(),
              if (tab == LibraryTab.history && library.history.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      ref.read(libraryProvider.notifier).clearHistory(),
                  child: Text('清空历史',
                      style: TextStyle(fontSize: 13, color: p.inkMuted)),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, kGutter),
            child: !wide
                ? list
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 392, child: list),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Panel(
                          child: selected == null
                              ? Center(
                                  child: Text('选一个帖子开始读',
                                      style: TextStyle(
                                          fontSize: 15, color: p.inkMuted)),
                                )
                              : TopicDetailView(
                                  key: ValueKey(_stack.last),
                                  topic: _stack.last,
                                  canGoBack: _stack.length > 1,
                                  onBack: () => setState(() => _stack =
                                      _stack.sublist(0, _stack.length - 1)),
                                  onOpenTopic: (r) =>
                                      setState(() => _stack = [..._stack, r]),
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ]);
    });
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.quick,
          curve: Motion.curve,
          height: kControlHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? p.accent : p.raised,
            borderRadius: BorderRadius.circular(Radii.block),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? p.accentInk : p.inkMuted)),
        ),
      ),
    );
  }
}
