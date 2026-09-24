import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../core/forum_source.dart';
import '../core/models.dart';
import '../core/read_log.dart';
import '../core/util.dart';
import '../widgets/avatar.dart';
import '../widgets/chrome.dart';
import '../widgets/error_view.dart';
import '../widgets/like_button.dart';
import '../widgets/post_body.dart';
import '../widgets/relative_time.dart';
import '../widgets/reveal.dart';
import '../widgets/swap.dart';
import 'pick_pictures.dart';
import 'keyboard.dart';
import 'providers.dart';
import 'reply_box.dart';

/// Right-hand pane in the wide layout.
class DetailPane extends ConsumerWidget {
  const DetailPane({super.key, required this.site});
  final SiteId site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stack = ref.watch(detailStackProvider(site));
    return Swap(
      swapKey: stack.isEmpty ? 'empty' : stack.last,
      child: stack.isEmpty
          ? const _EmptyDetail()
          : TopicDetailView(
              key: ValueKey(stack.last),
              topic: stack.last,
              canGoBack: stack.length > 1,
              onBack: () => ref.read(detailStackProvider(site).notifier).state =
                  stack.sublist(0, stack.length - 1),
              onOpenTopic: (r) => ref
                  .read(detailStackProvider(site).notifier)
                  .state = [...stack, r],
            ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('选一个帖子开始读',
            style: TextStyle(fontSize: 15, color: p.inkMuted, height: 1.4)),
        const SizedBox(height: 14),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const _Key('J'),
          const SizedBox(width: 5),
          const _Key('K'),
          const SizedBox(width: 9),
          Text('上下切换', style: TextStyle(fontSize: 12, color: p.inkFaint)),
          const SizedBox(width: 16),
          const _Key('?'),
          const SizedBox(width: 9),
          Text('全部快捷键', style: TextStyle(fontSize: 12, color: p.inkFaint)),
        ]),
      ]),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.line),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, height: 1, color: p.inkMuted)),
    );
  }
}

/// Full-screen route used in the narrow layout.
class TopicDetailPage extends StatefulWidget {
  const TopicDetailPage({super.key, required this.topic, required this.title});
  final TopicRef topic;
  final String title;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage> {
  late List<TopicRef> _stack = [widget.topic];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        backgroundColor: p.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink)),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Panel(
          child: TopicDetailView(
            key: ValueKey(_stack.last),
            topic: _stack.last,
            canGoBack: _stack.length > 1,
            onBack: () => setState(() => _stack = _stack.sublist(0, _stack.length - 1)),
            onOpenTopic: (r) => setState(() => _stack = [..._stack, r]),
          ),
        ),
      ),
    );
  }
}

class TopicDetailView extends ConsumerStatefulWidget {
  const TopicDetailView({
    super.key,
    required this.topic,
    required this.canGoBack,
    required this.onBack,
    required this.onOpenTopic,
  });
  final TopicRef topic;
  final bool canGoBack;
  final VoidCallback onBack;
  final ValueChanged<TopicRef> onOpenTopic;

  @override
  ConsumerState<TopicDetailView> createState() => _TopicDetailViewState();
}

class _TopicDetailViewState extends ConsumerState<TopicDetailView> {
  final _scroll = ScrollController();

  /// Which post the box is aimed at, where the reader picked one out of the
  /// thread. Null means the thread itself, which is what a forum takes when
  /// nothing says otherwise.
  ReplyTarget? _replyTo;

  /// Below this the button would scroll almost nowhere, so it stays hidden.
  static const _showTopButtonAfter = 400.0;
  bool _canScrollUp = false;

  /// What had been seen of this topic before it was opened this time, read
  /// before anything here records the new state over it.
  late final ReadProgress? _arrival;

  /// Where the thread offers to take the reader, once its replies are in.
  /// Null when there is nowhere worth offering, or they have gone.
  _Offer? _offer;
  bool _offered = false;

  /// One key per reply, so a reply can be found once it has been laid out.
  final _replyKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _arrival = ref
        .read(readLogProvider)
        .progressOf(widget.topic.site, widget.topic.id);
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      if (_scroll.position.extentAfter < 800) {
        ref.read(repliesProvider(widget.topic).notifier).loadMore();
      }
      final canScrollUp = _scroll.offset > _showTopButtonAfter;
      if (canScrollUp != _canScrollUp) {
        setState(() => _canScrollUp = canScrollUp);
      }
    });
  }

  /// Works out, once, what the thread should offer: the first reply that
  /// arrived since the last visit, or — with nothing new — the reply the
  /// reader was on when they left.
  ///
  /// New replies are only offered where the site numbers its floors, which is
  /// what says the thread is in the order it was written. Juejin sorts its
  /// comments by popularity, so "after the ones you saw" means nothing there.
  void _settleOffer(TopicDetail? detail, RepliesState replies) {
    if (_offered) return;
    _offered = true;
    final arrival = _arrival;
    final current = detail?.replyCount ?? replies.total;
    // Built during a frame: what is recorded, and the pill, wait for the end
    // of it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // What the list compares against from now on: this visit has seen them.
      if (current != null) {
        ref.read(readLogProvider.notifier).recordProgress(
            widget.topic.site, widget.topic.id,
            replies: current);
      }
      if (arrival == null || replies.all.isEmpty) return;
      final chronological = replies.all.any((r) => r.floor != null);
      final fresh = arrival.newSince(current);
      if (fresh > 0 && chronological) {
        setState(() => _offer = _Offer.newReplies(fresh, arrival.replies!));
      } else if (arrival.position case final at? when at > 0) {
        setState(() => _offer = _Offer.resume(at));
      }
    });
  }

  /// Takes the reader to reply [index], loading pages of the thread until it
  /// is there.
  Future<void> _jumpTo(int index) async {
    setState(() => _offer = null);
    final notifier = ref.read(repliesProvider(widget.topic).notifier);
    // A page at a time, and not forever: a thread that stops growing or will
    // not load is taken as far as it goes.
    var pages = 0;
    while (mounted && pages < 50) {
      final r = ref.read(repliesProvider(widget.topic)).valueOrNull;
      if (r == null || index < r.all.length || !r.hasMore) break;
      if (r.moreError != null) break;
      if (r.loadingMore) {
        // The scroll already asked for this page; wait for it to land.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }
      pages++;
      await notifier.loadMore();
    }
    if (!mounted) return;
    final all = ref.read(repliesProvider(widget.topic)).valueOrNull?.all;
    if (all == null || all.isEmpty) return;
    final target = index.clamp(0, all.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => revealItem(
          controller: _scroll,
          count: all.length,
          index: target,
          built: (i) => laidOut(_replyKeys[all[i].id]),
          alignment: 0,
          inset: 12,
        ));
  }

  /// Which reply is at the top of the screen, if the reader is in the
  /// replies at all.
  int? _replyOnScreen() {
    if (!_scroll.hasClients) return null;
    final all = ref.read(repliesProvider(widget.topic)).valueOrNull?.all;
    if (all == null) return null;
    final top = _scroll.position.pixels;
    for (var i = 0; i < all.length; i++) {
      final box = laidOut(_replyKeys[all[i].id]);
      if (box == null) continue;
      final start =
          RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
      if (start + box.size.height > top + 1) return i;
    }
    return null;
  }

  /// Writes down where the reader has stopped whenever a scroll comes to
  /// rest, so closing the thread — or the app — loses nothing.
  ///
  /// Read once the frame after has been laid out: a scroll can end in the
  /// same event that moved it, before the replies it moved to exist.
  bool _onScrollEnd(ScrollEndNotification end) {
    if (end.depth != 0) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final at = _replyOnScreen();
      if (at != null) {
        ref.read(readLogProvider.notifier).recordProgress(
            widget.topic.site, widget.topic.id,
            position: at);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
    return false;
  }

  /// The thread, with the offer floating over its top edge.
  Widget _overlaid(Widget thread) {
    final offer = _offer;
    return Stack(children: [
      Positioned.fill(
        child: NotificationListener<ScrollEndNotification>(
          onNotification: _onScrollEnd,
          child: thread,
        ),
      ),
      if (offer != null)
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: _OfferPill(
              offer: offer,
              onGo: () => _jumpTo(offer.index),
              onDismiss: () => setState(() => _offer = null),
            ),
          ),
        ),
    ]);
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: Motion.swap, curve: Motion.curve);
  }

  /// How much of a screen a page turn moves: most of one, so the last lines
  /// read are still there at the top to pick up from.
  static const _pageTurn = 0.88;

  void _scrollBy(double screens) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target = (position.pixels + position.viewportDimension * screens)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _scroll.animateTo(target, duration: Motion.swap, curve: Motion.curve);
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: Motion.swap, curve: Motion.curve);
  }

  String? get _url => ref.read(topicDetailProvider(widget.topic)).valueOrNull?.url;

  void _copyLink() {
    final url = _url;
    if (url == null) return;
    final p = context.palette;
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('链接已复制'),
      backgroundColor: p.raised,
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
      width: 200,
    ));
  }

  void _openInBrowser() {
    final url = _url;
    if (url == null) return;
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _obey(Command<DetailCommand>? command) {
    switch (command?.kind) {
      case DetailCommand.pageDown:
        _scrollBy(_pageTurn);
      case DetailCommand.pageUp:
        _scrollBy(-_pageTurn);
      case DetailCommand.top:
        _scrollToTop();
      case DetailCommand.bottom:
        _scrollToBottom();
      case DetailCommand.reload:
        _reload();
      case DetailCommand.copyLink:
        _copyLink();
      case DetailCommand.openInBrowser:
        _openInBrowser();
      case null:
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _handleLink(Uri uri) {
    final id = ref.read(sourceProvider(widget.topic.site)).topicIdFromUrl(uri);
    if (id == null) return false;
    widget.onOpenTopic(TopicRef(widget.topic.site, id));
    return true;
  }

  SiteImages get _images => ref.read(siteImagesProvider(widget.topic.site));

  void _reload() {
    ref.invalidate(topicDetailProvider(widget.topic));
    ref.invalidate(repliesProvider(widget.topic));
  }

  /// Likes a post, or takes the like back, and tells the thread about it.
  ///
  /// The opening post is not in the thread's list — it comes from its own
  /// provider — so only a reply is written back; the button there keeps what
  /// the forum answered until the topic is loaded again.
  Future<LikeState> _like(
    ActOnLike act,
    String postId,
    bool wanted, {
    String? replyId,
  }) async {
    final state = await act(postId, like: wanted);
    if (replyId != null) {
      ref.read(repliesProvider(widget.topic).notifier).replaceLike(replyId, state);
    }
    return state;
  }

  /// Aims the box at one post. The box takes the cursor from there.
  void _answer(Reply reply) => setState(() => _replyTo = ReplyTarget(
        postId: reply.id,
        floor: reply.floor,
        author: reply.author?.name,
      ));

  /// Finds the pictures the reader meant and hands them to the site,
  /// answering with what to write into the box for them.
  ///
  /// One at a time rather than all at once: a forum counts uploads against a
  /// limit, and one that says no to the fourth should say so about the fourth
  /// rather than about whichever of four happened to be in flight.
  Future<String?> _attach(UploadImage upload, PictureSource from) async {
    final picked = switch (from) {
      PictureSource.picked => await pickPictures(),
      PictureSource.pasted => [?await clipboardPicture()],
    };
    if (picked.isEmpty) return null;
    final written = <String>[];
    for (final picture in picked) {
      written.add(await upload(picture.name, picture.bytes));
    }
    return written.join('\n');
  }

  /// Sends a reply and puts it at the end of the thread.
  ///
  /// Anything thrown here is the forum explaining why it refused, and the box
  /// is what shows it — so it is left to travel back rather than caught.
  Future<void> _send(SendReply send, String text) async {
    final posted = await send(widget.topic.id, text, to: _replyTo);
    // It went, so the box is answering the thread again.
    if (mounted) setState(() => _replyTo = null);
    if (!ref.read(repliesProvider(widget.topic).notifier).appendSent(posted)) {
      ref.invalidate(repliesProvider(widget.topic));
      return;
    }
    // Their own reply is the one thing they want to see, and it is at the
    // bottom. The list grows this frame, so the move waits for the next one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: Motion.swap, curve: Motion.curve);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(detailCommandProvider(widget.topic.site), (_, c) => _obey(c));
    final p = context.palette;
    final detail = ref.watch(topicDetailProvider(widget.topic));
    final replies = ref.watch(repliesProvider(widget.topic));
    if (replies.valueOrNull case final r?) _settleOffer(detail.valueOrNull, r);
    final source = ref.watch(sourceProvider(widget.topic.site));
    final url = detail.valueOrNull?.url;

    return Column(children: [
      Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.line)),
        ),
        child: Row(children: [
          if (widget.canGoBack)
            QuietIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: '回到上一篇',
                onPressed: widget.onBack),
          const Spacer(),
          QuietIconButton(
              icon: Icons.refresh_rounded, tooltip: '重新加载', onPressed: _reload),
          // Always present, so the toolbar keeps its shape. At the top of a
          // post there is nowhere to go, so it greys out rather than
          // disappearing and leaving a gap where it used to be.
          QuietIconButton(
            icon: Icons.vertical_align_top_rounded,
            tooltip: _canScrollUp ? '回到顶部' : '已经在顶部',
            onPressed: _canScrollUp ? _scrollToTop : null,
          ),
          QuietIconButton(
            icon: Icons.link_rounded,
            tooltip: '复制链接',
            onPressed: url == null ? null : _copyLink,
          ),
          QuietIconButton(
            icon: Icons.north_east_rounded,
            tooltip: '在浏览器中打开',
            onPressed: url == null ? null : _openInBrowser,
          ),
        ]),
      ),
      Expanded(
        child: _overlaid(detail.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => ErrorView(error: e, onRetry: _reload),
          data: (d) => Scrollbar(
            controller: _scroll,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                if (d.savedAt case final savedAt?)
                  SliverToBoxAdapter(
                    child: _OfflineNote(savedAt: savedAt, onRetry: _reload),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(30, 26, 30, 0),
                  sliver: SliverToBoxAdapter(
                    child: PostHeader(
                      detail: d,
                      images: _images,
                      // Only a site that says who may like what, and only a
                      // post it numbers apart from its thread.
                      onLike: source.like == null || d.postId == null
                          ? null
                          : (wanted) =>
                              _like(source.like!, d.postId!, wanted),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(30, 0, 30, 20),
                  sliver: SliverToBoxAdapter(
                    child: SelectionArea(
                      child: PostBody(
                        content: d.content,
                        format: d.format,
                        baseUrl: source.homeUrl,
                        onTopicLink: _handleLink,
                        images: _images,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(30, 10, 30, 2),
                    // Two rules of equal flex put the count in the middle of
                    // the pane, reading as the seam between the post and the
                    // thread rather than as a heading over it.
                    child: Row(children: [
                      Expanded(child: Container(height: 1, color: p.line)),
                      const SizedBox(width: 14),
                      Text(_repliesTitle(d, replies.valueOrNull),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: p.inkMuted)),
                      const SizedBox(width: 14),
                      Expanded(child: Container(height: 1, color: p.line)),
                    ]),
                  ),
                ),
                ..._replySlivers(replies, source),
                const SliverToBoxAdapter(child: SizedBox(height: 36)),
              ],
            ),
          ),
        )),
      ),
      // Only where there is somewhere for it to go: a site the app can write
      // to, signed in, and a post that actually loaded.
      if (detail.hasValue)
        if (source.reply case final send?)
          ReplyBox(
            to: _replyTo,
            onCancelTarget: () => setState(() => _replyTo = null),
            onAttach: source.uploadImage == null
                ? null
                : (from) => _attach(source.uploadImage!, from),
            onSend: (text) => _send(send, text),
          ),
    ]);
  }

  String _repliesTitle(TopicDetail d, RepliesState? r) {
    final n = r?.total ?? d.replyCount;
    if (n == null) return '回复';
    return n == 0 ? '还没有回复' : '$n 条回复';
  }

  List<Widget> _replySlivers(
      AsyncValue<RepliesState> replies, ForumSource source) {
    final baseUrl = source.homeUrl;
    final act = source.like;
    return replies.when(
      loading: () => const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(26),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ],
      error: (e, _) => [
        SliverToBoxAdapter(
          child: ErrorView(
              error: e,
              compact: true,
              onRetry: () => ref.invalidate(repliesProvider(widget.topic))),
        ),
      ],
      data: (r) => [
        SliverList.builder(
          // `all` rather than the page: a reply written here sits at the end
          // of the thread, where its writer left it.
          itemCount: r.all.length,
          itemBuilder: (context, i) => ReplyTile(
            key: _replyKeys.putIfAbsent(r.all[i].id, GlobalKey.new),
            first: i == 0,
            reply: r.all[i],
            baseUrl: baseUrl,
            onTopicLink: _handleLink,
            images: _images,
            onLike: act == null
                ? null
                : (wanted) =>
                    _like(act, r.all[i].id, wanted, replyId: r.all[i].id),
            onReply:
                source.reply == null ? null : () => _answer(r.all[i]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: r.loadingMore
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : r.moreError != null
                      ? TextButton(
                          onPressed: () =>
                              ref.read(repliesProvider(widget.topic).notifier).loadMore(),
                          child: const Text('没加载成功，再试一次'))
                      : r.hasMore
                          ? TextButton(
                              onPressed: () => ref
                                  .read(repliesProvider(widget.topic).notifier)
                                  .loadMore(),
                              child: const Text('加载更多回复'))
                          : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Title, author and stats above a post body.
class PostHeader extends StatelessWidget {
  const PostHeader({
    super.key,
    required this.detail,
    this.images = SiteImages.plain,
    this.onLike,
  });
  final TopicDetail detail;
  final SiteImages images;

  /// Null where the site has no likes to give, or the reader is not signed
  /// in to give one.
  final Future<LikeState> Function(bool like)? onLike;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = detail.author;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SelectableText(detail.title,
          style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 16),
      // Author on one side, stats on the other. Wrap rather than Row so a
      // narrow pane pushes the stats onto their own line instead of
      // overflowing, and so the author block gets a bounded width, which the
      // tagline's Flexible needs.
      LayoutBuilder(builder: (context, constraints) {
        final pills = <Widget>[
          if (detail.sectionLabel != null) Pill(label: detail.sectionLabel!),
          if (detail.viewCount != null)
            Pill(label: '${compactCount(detail.viewCount)} 阅读'),
          if (onLike case final act?)
            LikeButton(
              pill: true,
              state: LikeState(
                count: detail.likeCount ?? 0,
                liked: detail.liked,
                canLike: detail.canLike,
                canUnlike: detail.canUnlike,
              ),
              onLike: act,
            )
          else if (detail.likeCount != null)
            Pill(label: '${compactCount(detail.likeCount)} 赞', tone: p.cream),
        ];
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: a == null
                  ? RelativeTime(detail.createdAt,
                      style: TextStyle(fontSize: 12, color: p.inkFaint))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      UserAvatar(
                          url: a.avatarUrl,
                          name: a.name,
                          size: 30,
                          images: images),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: p.ink)),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              if (a.tagline != null &&
                                  a.tagline!.isNotEmpty) ...[
                                Flexible(
                                  child: Text(a.tagline!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 11.5, color: p.inkFaint)),
                                ),
                                Text('，',
                                    style: TextStyle(
                                        fontSize: 11.5, color: p.inkFaint)),
                              ],
                              RelativeTime(detail.createdAt),
                            ]),
                          ],
                        ),
                      ),
                    ]),
            ),
            if (pills.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: pills),
          ],
        );
      }),
      const SizedBox(height: 20),
    ]);
  }
}

/// One reply. Nested replies (Juejin) reuse this widget inside a raised block.
class ReplyTile extends StatelessWidget {
  const ReplyTile({
    super.key,
    required this.reply,
    required this.baseUrl,
    required this.onTopicLink,
    this.images = SiteImages.plain,
    this.nested = false,
    this.first = false,
    this.onLike,
    this.onReply,
  });

  final Reply reply;
  final Uri baseUrl;
  final bool Function(Uri) onTopicLink;
  final SiteImages images;
  final bool nested;

  /// Null where the site has no likes to give, or the reader is not signed
  /// in to give one.
  final Future<LikeState> Function(bool like)? onLike;

  /// Aims the box at the foot of the thread at this reply. Null where the
  /// thread cannot be answered at all.
  final VoidCallback? onReply;

  /// The first reply in the thread, which the count's own rule already sits
  /// above — a border here would draw a second line right under it.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = reply.author;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        // Everything on the left shares one flexible slot; giving the name its
        // own would split the leftover width and pull the floor number inward.
        Expanded(
          child: Row(children: [
            UserAvatar(
                url: a?.avatarUrl,
                name: a?.name ?? '?',
                size: nested ? 18 : 24,
                images: images),
            const SizedBox(width: 8),
            Flexible(
              child: Text(a?.name ?? '匿名',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: p.ink)),
            ),
            const SizedBox(width: 8),
            RelativeTime(reply.createdAt),
          ]),
        ),
        if (onLike case final act?) ...[
          const SizedBox(width: 10),
          LikeButton(
            state: LikeState(
              count: reply.likeCount ?? 0,
              liked: reply.liked,
              canLike: reply.canLike,
              canUnlike: reply.canUnlike,
            ),
            onLike: act,
          ),
        ] else if (reply.likeCount != null && reply.likeCount! > 0) ...[
          const SizedBox(width: 10),
          Text('${reply.likeCount} 赞',
              style: TextStyle(fontSize: 11.5, color: p.cream)),
        ],
        if (onReply case final answer?) ...[
          const SizedBox(width: 2),
          QuietIconButton(
              icon: Icons.reply_rounded,
              tooltip: '回复 TA',
              size: 13,
              box: 24,
              onPressed: answer),
        ],
        if (reply.floor != null) ...[
          const SizedBox(width: 10),
          Text('#${reply.floor}',
              style: TextStyle(
                  fontSize: 11.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: p.inkFaint)),
        ],
      ]),
      const SizedBox(height: 6),
      if (reply.quote != null && !reply.quote!.isEmpty)
        Padding(
          padding: EdgeInsets.only(left: nested ? 26 : 32, bottom: 8),
          child: _QuotedReply(quote: reply.quote!),
        ),
      Padding(
        padding: EdgeInsets.only(left: nested ? 26 : 32),
        child: SelectionArea(
          child: PostBody(
            content: reply.content,
            format: reply.format,
            baseUrl: baseUrl,
            onTopicLink: onTopicLink,
            images: images,
            fontSize: 13.5,
          ),
        ),
      ),
      for (final child in reply.children)
        Padding(
          padding: EdgeInsets.only(left: nested ? 26 : 32, top: 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: p.raised,
              borderRadius: BorderRadius.circular(Radii.block),
            ),
            child: ReplyTile(
              reply: child,
              baseUrl: baseUrl,
              onTopicLink: onTopicLink,
              images: images,
              nested: true,
            ),
          ),
        ),
    ]);

    if (nested) return body;
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 16, 30, 16),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: p.line)),
      ),
      child: body,
    );
  }
}

/// What a reply is answering, shown above it.
///
/// Forums that thread replies give this for free. V2EX does not, so its source
/// recovers it from how people write; either way it lands here.
class _QuotedReply extends StatelessWidget {
  const _QuotedReply({required this.quote});

  final ReplyQuote quote;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final excerpt = quote.excerpt?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(Radii.block),
        border: Border(left: BorderSide(color: p.line, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.reply_rounded, size: 12, color: p.inkFaint),
          const SizedBox(width: 6),
          if (quote.author != null)
            Flexible(
              child: Text(
                quote.author!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: p.inkMuted),
              ),
            ),
          if (quote.floor != null) ...[
            const SizedBox(width: 6),
            Text('#${quote.floor}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: p.inkFaint)),
          ],
        ]),
        if (excerpt.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            excerpt,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, height: 1.4, color: p.inkFaint),
          ),
        ],
      ]),
    );
  }
}

/// Somewhere in the thread worth going to straight away.
class _Offer {
  const _Offer.newReplies(int this.count, this.index);
  const _Offer.resume(this.index) : count = null;

  /// How many replies are new, for an offer of new replies.
  final int? count;

  /// The reply to go to, counted from zero.
  final int index;
}

/// The offer, as a pill floating over the top of the thread.
class _OfferPill extends StatelessWidget {
  const _OfferPill(
      {required this.offer, required this.onGo, required this.onDismiss});

  final _Offer offer;
  final VoidCallback onGo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fresh = offer.count != null;
    final tone = fresh ? p.mint : p.ink;
    return Material(
      color: p.raised,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.pill),
        side: BorderSide(color: p.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton.icon(
            onPressed: onGo,
            icon: Icon(
                fresh ? Icons.south_rounded : Icons.bookmark_outline_rounded,
                size: 15,
                color: tone),
            label: Text(
                fresh
                    ? '${offer.count} 条新回复'
                    : '回到上次读到的第 ${offer.index + 1} 条回复',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: tone)),
          ),
          QuietIconButton(
            icon: Icons.close_rounded,
            tooltip: '不用了',
            onPressed: onDismiss,
          ),
        ]),
      ),
    );
  }
}

/// Says the thread on screen is the copy saved last time, because the site
/// could not be reached just now.
class _OfflineNote extends StatelessWidget {
  const _OfflineNote({required this.savedAt, required this.onRetry});

  final DateTime savedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(30, 18, 30, 0),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: p.line),
      ),
      child: Row(children: [
        Icon(Icons.cloud_off_rounded, size: 15, color: p.inkMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
              '没能连上站点，这是${relativeTime(savedAt)}保存的版本。'
              '点赞和回复要等连上以后。',
              style: TextStyle(fontSize: 12, height: 1.35, color: p.inkMuted)),
        ),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ]),
    );
  }
}
