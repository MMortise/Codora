import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme.dart';
import '../core/forum_source.dart';
import '../core/models.dart';
import '../core/util.dart';
import '../widgets/avatar.dart';
import '../widgets/chrome.dart';
import '../widgets/error_view.dart';
import '../widgets/relative_time.dart';
import 'providers.dart';

/// The middle column: one card per topic, identical for every site. Sites
/// differ only in which optional fields they populate.
class TopicListPane extends ConsumerStatefulWidget {
  const TopicListPane({
    super.key,
    required this.site,
    required this.sectionId,
    required this.onOpen,
  });
  final SiteId site;
  final String sectionId;
  final ValueChanged<TopicSummary> onOpen;

  @override
  ConsumerState<TopicListPane> createState() => _TopicListPaneState();
}

class _TopicListPaneState extends ConsumerState<TopicListPane> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'topic-list');

  FeedKey get _key => FeedKey(widget.site, widget.sectionId);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 600) {
      ref.read(feedProvider(_key).notifier).loadMore();
    }
  }

  void _move(int delta) {
    final items = ref.read(feedProvider(_key)).valueOrNull?.items;
    if (items == null || items.isEmpty) return;
    final stack = ref.read(detailStackProvider(widget.site));
    final currentId = stack.isEmpty ? null : stack.first.id;
    var idx = items.indexWhere((t) => t.id == currentId);
    idx = (idx + delta).clamp(0, items.length - 1);
    widget.onOpen(items[idx]);
    _scroll.animateTo(
      (idx * 96.0 - 180).clamp(0, _scroll.position.maxScrollExtent),
      duration: Motion.swap,
      curve: Motion.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider(_key));
    final stack = ref.watch(detailStackProvider(widget.site));
    final selectedId = stack.isEmpty ? null : stack.first.id;
    final images = ref.watch(siteImagesProvider(widget.site));
    final readLog = ref.watch(readLogProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.keyJ): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.keyK): () => _move(-1),
      },
      child: Focus(
        focusNode: _focus,
        child: feed.when(
          skipLoadingOnReload: true,
          loading: () => const Panel(
              child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          error: (e, _) => Panel(
            child: ErrorView(
              error: e,
              onRetry: () => ref.invalidate(feedProvider(_key)),
            ),
          ),
          data: (state) {
            if (state.items.isEmpty) {
              return Panel(
                child: Center(
                  child: Text('这个板块现在没有帖子',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              );
            }
            return Stack(children: [
              ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.zero,
                itemCount: state.items.length + 1,
                itemBuilder: (context, i) {
                  if (i == state.items.length) {
                    return _FeedFooter(
                      state: state,
                      onMore: () => ref.read(feedProvider(_key).notifier).loadMore(),
                    );
                  }
                  final t = state.items[i];
                  final fresh =
                      readLog.newReplies(widget.site, t.id, t.replyCount);
                  return TopicCard(
                    topic: t,
                    selected: t.id == selectedId,
                    // A thread with something new in it is worth reading
                    // again, so it is not dimmed like one that has nothing.
                    read: readLog.contains(widget.site, t.id) && fresh == 0,
                    newReplies: fresh,
                    images: images,
                    onTap: () {
                      _focus.requestFocus();
                      widget.onOpen(t);
                    },
                  );
                },
              ),
              if (feed.isLoading)
                const Positioned(
                    left: 0, right: 0, top: 0, child: LinearProgressIndicator()),
            ]);
          },
        ),
      ),
    );
  }
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter({required this.state, required this.onMore});
  final FeedState state;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final Widget child;
    if (state.loadingMore) {
      child = SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: p.inkFaint));
    } else if (state.moreError != null) {
      child = TextButton(onPressed: onMore, child: const Text('没加载成功，再试一次'));
    } else if (state.hasMore) {
      child = TextButton(onPressed: onMore, child: const Text('加载更多'));
    } else {
      child = Text('到底了', style: Theme.of(context).textTheme.labelSmall);
    }
    return Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 26), child: Center(child: child));
  }
}

/// One topic. Selection is the lavender fill; nothing else in the list uses it.
class TopicCard extends StatefulWidget {
  const TopicCard({
    super.key,
    required this.topic,
    required this.selected,
    required this.onTap,
    this.read = false,
    this.newReplies = 0,
    this.images = SiteImages.plain,
  });
  final TopicSummary topic;
  final bool selected;

  /// Replies that arrived since the reader last opened this topic.
  final int newReplies;

  /// Already opened. Shown by dimming, the way a read message list does it.
  final bool read;
  final VoidCallback onTap;
  final SiteImages images;

  @override
  State<TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<TopicCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = widget.topic;
    final selected = widget.selected;
    final excerpt = t.excerpt?.trim() ?? '';
    final ink = selected
        ? p.accentInk
        : (widget.read ? p.inkMuted : p.ink);
    final muted = selected ? p.accentInk.withValues(alpha: 0.66) : p.inkMuted;
    final faint = selected ? p.accentInk.withValues(alpha: 0.55) : p.inkFaint;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.quick,
          curve: Motion.curve,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          decoration: BoxDecoration(
            color: selected ? p.accent : (_hover ? p.raised : p.panel),
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: selected ? p.accent : p.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!widget.read && !selected) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: p.badge, shape: BoxShape.circle),
                  ),
                ),
              ],
              Expanded(
                child: Text(t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        fontWeight:
                            widget.read ? FontWeight.w500 : FontWeight.w600,
                        letterSpacing: -0.1,
                        color: ink)),
              ),
              if (widget.newReplies > 0) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '+${compactCount(widget.newReplies)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: selected ? p.accentInk : p.mint,
                    ),
                  ),
                ),
              ],
              if (t.replyCount != null) ...[
                SizedBox(width: widget.newReplies > 0 ? 6 : 12),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: _Count(
                    value: t.replyCount!,
                    selected: selected,
                  ),
                ),
              ],
            ]),
            if (excerpt.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: muted)),
            ],
            const SizedBox(height: 10),
            Row(children: [
              // Author and board share one flexible slot so the timestamp can
              // hold the right edge. Giving each of them their own Flex slot
              // would split the leftover width three ways and strand the time
              // in the middle.
              Expanded(
                child: Row(children: [
                  if (t.author != null) ...[
                    UserAvatar(
                        url: t.author!.avatarUrl,
                        name: t.author!.name,
                        size: 18,
                        images: widget.images),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(t.author!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: muted)),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (t.sectionLabel != null)
                    Flexible(
                      child: Text(t.sectionLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: faint)),
                    ),
                ]),
              ),
              const SizedBox(width: 10),
              RelativeTime(t.lastActiveAt ?? t.createdAt,
                  style: TextStyle(fontSize: 11.5, color: faint)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Reply count. Lavender on the card, so the busiest threads read first; on a
/// selected card the fill is already lavender, so it inverts instead.
class _Count extends StatelessWidget {
  const _Count({required this.value, required this.selected});
  final int value;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? p.accentInk.withValues(alpha: 0.12) : p.badge,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        compactCount(value),
        style: TextStyle(
          fontSize: 11.5,
          height: 1.1,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: selected ? p.accentInk : p.onBadge,
        ),
      ),
    );
  }
}
