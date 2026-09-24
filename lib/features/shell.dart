import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../app_theme.dart';
import '../core/models.dart';
import '../widgets/chrome.dart';
import '../widgets/hover_flyout.dart';
import '../widgets/site_icon.dart';
import '../widgets/swap.dart';
import 'library_page.dart';
import 'member_card.dart';
import 'providers.dart';
import 'settings_page.dart';
import 'topic_detail.dart';
import 'topic_list.dart';

/// Breathing room between the rail and everything in the content column.
const kGutter = 18.0;

/// Height of a board row in the dropdown. A line of text measures 16, so this
/// is that plus 10 of air above and below.
const kMenuRowHeight = 36.0;

/// How many boards the dropdown shows before it starts scrolling. Sites list
/// a dozen or more, and a menu that runs the height of the window is harder
/// to aim at than one that scrolls.
const kMenuVisibleRows = 10;

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(currentNavProvider);
    final sites = ref.watch(visibleSiteIdsProvider);
    ref.watch(rememberPlaceProvider);

    // Only the sites on the rail are built. A stack holding all of them would
    // keep a switched-off site fetching its boards in the background, which is
    // most of the reason to switch one off. Settings is always last.
    return Scaffold(
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _Rail(),
        Expanded(
          child: IndexedStack(
            index: switch (nav) {
              NavTarget.library => sites.length,
              NavTarget.settings => sites.length + 1,
              _ => sites.indexOf(nav.site!),
            },
            children: [
              for (final site in sites) _pageFor(site),
              const LibraryPage(),
              const SettingsPage(),
            ],
          ),
        ),
      ]),
    );
  }
}

/// The one page per site, as a canonical `const`.
///
/// Every page in the stack stays mounted, so handing `IndexedStack` the
/// identical widget on an unrelated rebuild — a rail click, say — lets Flutter
/// skip all of their subtrees instead of rebuilding the lot. The key is what
/// stops a site leaving the rail from handing its scroll position to whichever
/// one slides into its place.
Widget _pageFor(SiteId site) => switch (site) {
      SiteId.v2ex =>
        const SitePage(key: ValueKey(SiteId.v2ex), site: SiteId.v2ex),
      SiteId.linuxdo =>
        const SitePage(key: ValueKey(SiteId.linuxdo), site: SiteId.linuxdo),
      SiteId.juejin =>
        const SitePage(key: ValueKey(SiteId.juejin), site: SiteId.juejin),
    };

/// Narrow left rail. Each site is a square block with its own glyph, so the
/// current site is readable at a glance without a label column.
///
/// Only the sites switched on in settings appear here; settings itself always
/// does, so a rail emptied of forums is still a way back.
class _Rail extends ConsumerWidget {
  const _Rail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(currentNavProvider);
    final p = context.palette;
    final sources = ref.watch(visibleSourcesProvider);
    // The rail is the one thing always on screen, so it is what holds the
    // profiles open: they load as the app comes up and stay current, rather
    // than making whoever hovers first wait for a request.
    ref.watch(loadedMembersProvider);
    ref.watch(inboxWatcherProvider);

    return Container(
      width: 64,
      color: p.canvas,
      child: Column(children: [
        // Clears the macOS traffic lights, which sit over the rail.
        const SizedBox(height: 52),
        for (final source in sources)
          _RailBlock(
            icon: SiteIcon(
              asset: source.iconAsset,
              glyph: source.glyph,
              size: 24,
              dimmed: nav.site != source.id,
            ),
            label: '${source.name} · ${source.access.label}',
            selected: nav.site == source.id,
            status: _statusColor(p, source.access.level),
            // Sites that can say who the reader is get a card instead of a
            // tooltip; the rest keep the tooltip. Reading the same field the
            // card fetches through means a token typed in settings puts the
            // card here on the next frame, with nothing fetched until hover.
            flyout: source.member == null
                ? null
                : MemberCard(site: source.id),
            onTap: () =>
                ref.read(navProvider.notifier).state = source.id.target,
          ),
        const Spacer(),
        _RailBlock(
          icon: const Icon(Icons.bookmark_outline_rounded, size: 18),
          label: '收藏和历史',
          selected: nav == NavTarget.library,
          onTap: () => ref.read(navProvider.notifier).state = NavTarget.library,
        ),
        _RailBlock(
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: '设置',
          selected: nav == NavTarget.settings,
          onTap: () => ref.read(navProvider.notifier).state = NavTarget.settings,
        ),
        const SizedBox(height: 14),
      ]),
    );
  }

  /// Only a site that needs attention gets a dot; "open" sites stay quiet.
  Color? _statusColor(Palette p, AccessLevel level) => switch (level) {
        AccessLevel.open => null,
        AccessLevel.full => p.mint,
        AccessLevel.limited => p.cream,
        AccessLevel.blocked => p.rose,
      };
}

class _RailBlock extends StatelessWidget {
  const _RailBlock({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.status,
    this.flyout,
  });

  final Widget icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? status;

  /// Panel shown to the right while the pointer rests here, in place of the
  /// tooltip. Mounted only while open, so a block with one costs nothing
  /// until someone looks at it.
  final Widget? flyout;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return HoverFlyout(
      panel: flyout,
      builder: (context, hovered) {
        final block = MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.quick,
              curve: Motion.curve,
              width: 40,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                // The logos bring their own colours, so the current site is
                // marked by the surface and ring, never by the mark itself.
                color: selected ? p.accentSoft : (hovered ? p.raised : p.panel),
                borderRadius: BorderRadius.circular(Radii.block),
                border: Border.all(
                  color: selected ? p.accent : p.line,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Stack(children: [
                Center(
                  child: IconTheme(
                    data: IconThemeData(
                        size: 18, color: selected ? p.ink : p.inkMuted),
                    child: icon,
                  ),
                ),
                if (status != null)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: status,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.panel, width: 1),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        );
        // A block with a panel has no tooltip: the panel names the site and
        // says more about it than the label could, and two of them arriving
        // at once is one too many.
        return flyout == null
            ? Tooltip(message: label, preferBelow: false, child: block)
            : block;
      },
    );
  }
}

class SitePage extends ConsumerWidget {
  const SitePage({super.key, required this.site});
  final SiteId site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(sectionsProvider(site));
    final selected = ref.watch(selectedSectionProvider(site));
    final sections = sectionsAsync.valueOrNull ?? const <Section>[];
    // A board remembered from last time is only used once the site confirms
    // it still has one by that name; until the list is in, nothing is asked
    // for rather than a board that may be gone.
    final sectionId = sections.any((s) => s.id == selected)
        ? selected
        : (sections.isNotEmpty ? sections.first.id : null);
    // A search, while there is one, stands in the list's place; the board
    // underneath is still the one to go back to.
    final query = ref.watch(searchQueryProvider(site));
    final listId = query == null ? sectionId : searchSectionId(query);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(left: kGutter),
        child: _TopBar(site: site, sectionId: listId),
      ),
      _SectionBlocks(
        site: site,
        sections: sections,
        selectedId: query == null ? sectionId : null,
        loading: sectionsAsync.isLoading,
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 940;
          final sectionId = listId;
          if (sectionId == null) {
            return Center(
              child: sectionsAsync.isLoading
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : Text('这个站点还没有可用的板块',
                      style: Theme.of(context).textTheme.bodySmall),
            );
          }
          final list = Swap(
            swapKey: 'list-$site-$sectionId',
            child: TopicListPane(
              key: ValueKey('list-$site-$sectionId'),
              site: site,
              sectionId: sectionId,
              onOpen: (t) => _open(context, ref, t, pushRoute: !wide),
            ),
          );
          if (!wide) {
            return Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, kGutter),
                child: list);
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, kGutter),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 392, child: list),
              const SizedBox(width: 14),
              Expanded(child: Panel(child: DetailPane(site: site))),
            ]),
          );
        }),
      ),
    ]);
  }

  void _open(BuildContext context, WidgetRef ref, TopicSummary t,
      {required bool pushRoute}) {
    final target = TopicRef(site, t.id);
    ref.read(readLogProvider.notifier).markRead(site, t.id);
    ref.read(detailStackProvider(site).notifier).state = [target];
    if (pushRoute) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TopicDetailPage(topic: target, title: t.title)));
    }
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.site, required this.sectionId});
  final SiteId site;
  final String? sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final source = ref.watch(sourceProvider(site));

    return DragToMoveArea(
      child: SizedBox(
        height: 62,
        child: Row(children: [
          Text('codora',
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  height: 1,
                  color: p.ink)),
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(left: 3, bottom: 3),
            alignment: Alignment.bottomCenter,
            decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 20),
          Container(width: 1, height: 18, color: p.line),
          const SizedBox(width: 20),
          Swap(
            swapKey: source.name,
            drift: 0,
            child: Text(source.name,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: p.inkMuted)),
          ),
          const Spacer(),
          if (source.search != null || source.searchPage('') != null)
            _SearchBox(site: site),
          QuietIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '刷新列表',
            onPressed: sectionId == null
                ? null
                : () => ref
                    .read(feedProvider(FeedKey(site, sectionId!)).notifier)
                    .refresh(),
          ),
          QuietIconButton(
            icon: Icons.north_east_rounded,
            tooltip: '在浏览器中打开 ${source.name}',
            onPressed: () => launchUrl(source.homeUrl),
          ),
          const SizedBox(width: 12),
        ]),
      ),
    );
  }
}

/// A search field that stays a button until it is wanted.
///
/// A site the app can search shows the results in place of the board; one it
/// cannot — V2EX has no search to call — hands the words to a search engine
/// in the browser instead.
class _SearchBox extends ConsumerStatefulWidget {
  const _SearchBox({required this.site});
  final SiteId site;

  @override
  ConsumerState<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends ConsumerState<_SearchBox> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'search');
  bool _open = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    final source = ref.read(sourceProvider(widget.site));
    if (source.search != null) {
      ref.read(searchQueryProvider(widget.site).notifier).state = query;
    } else if (source.searchPage(query) case final page?) {
      launchUrl(page);
    }
  }

  void _close() {
    _text.clear();
    ref.read(searchQueryProvider(widget.site).notifier).state = null;
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final query = ref.watch(searchQueryProvider(widget.site));
    final source = ref.watch(sourceProvider(widget.site));
    if (!_open && query == null) {
      return QuietIconButton(
        icon: Icons.search_rounded,
        tooltip: '搜索 ${source.name}',
        onPressed: () {
          setState(() => _open = true);
          _focus.requestFocus();
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: SizedBox(
        width: 240,
        height: kControlHeight,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _close,
          },
          child: TextField(
            controller: _text,
            focusNode: _focus,
            style: const TextStyle(fontSize: 13),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: source.search != null
                  ? '搜索 ${source.name}'
                  : '用必应搜索 ${source.name}',
              prefixIcon: Icon(Icons.search_rounded, size: 16, color: p.inkFaint),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
              suffixIcon: IconButton(
                tooltip: '关闭搜索',
                icon: const Icon(Icons.close_rounded, size: 15),
                onPressed: _close,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
            onSubmitted: _submit,
            // Stays in the field, so the words can be changed and searched
            // again — or the search closed with escape.
            onEditingComplete: () {},
          ),
        ),
      ),
    );
  }
}

/// Two-line section blocks: Chinese name over the board's own latin slug.
/// Boards beyond the first few live in a dropdown so the row never wraps.
class _SectionBlocks extends ConsumerWidget {
  const _SectionBlocks({
    required this.site,
    required this.sections,
    required this.selectedId,
    required this.loading,
  });
  final SiteId site;
  final List<Section> sections;
  final String? selectedId;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final primary = sections.where((s) => s.group == null).toList();
    final groups = <String, List<Section>>{};
    for (final s in sections) {
      if (s.group != null) groups.putIfAbsent(s.group!, () => []).add(s);
    }
    void select(String id) {
      // Picking a board is leaving the search for it.
      ref.read(searchQueryProvider(site).notifier).state = null;
      ref.read(selectedSectionProvider(site).notifier).state = id;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 14),
      child: SizedBox(
        height: 58,
        child: Row(children: [
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: false, overscroll: false),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in primary)
                    _SectionBlock(
                      section: s,
                      selected: s.id == selectedId,
                      onTap: () => select(s.id),
                    ),
                  for (final e in groups.entries)
                    SectionGroupMenu(
                      label: e.key,
                      sections: e.value,
                      selectedId: selectedId,
                      onSelect: select,
                    ),
                  if (loading)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: p.inkFaint),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SectionBlock extends StatefulWidget {
  const _SectionBlock({
    required this.section,
    required this.selected,
    required this.onTap,
  });
  final Section section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SectionBlock> createState() => _SectionBlockState();
}

class _SectionBlockState extends State<_SectionBlock> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final selected = widget.selected;
    final title = selected ? p.accentInk : p.ink;
    final sub = selected ? p.accentInk.withValues(alpha: 0.62) : p.inkFaint;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.quick,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          constraints: const BoxConstraints(minWidth: 68),
          decoration: BoxDecoration(
            color: selected ? p.accent : (_hover ? p.raised : p.panel),
            borderRadius: BorderRadius.circular(Radii.block),
            border: Border.all(color: selected ? p.accent : p.line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.section.title,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, height: 1.15, color: title)),
              const SizedBox(height: 1),
              Text(widget.section.subtitle ?? ' ',
                  style: TextStyle(fontSize: 10.5, height: 1.15, color: sub)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dropdown holding a site's boards.
class SectionGroupMenu extends StatefulWidget {
  const SectionGroupMenu({
    super.key,
    required this.label,
    required this.sections,
    required this.selectedId,
    required this.onSelect,
  });
  final String label;
  final List<Section> sections;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<SectionGroupMenu> createState() => _SectionGroupMenuState();
}

class _SectionGroupMenuState extends State<SectionGroupMenu> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final current =
        widget.sections.where((s) => s.id == widget.selectedId).firstOrNull;
    final selected = current != null;
    final title = selected ? p.accentInk : p.ink;
    final sub = selected ? p.accentInk.withValues(alpha: 0.62) : p.inkFaint;

    return MenuAnchor(
      // The surface is handed over to _MenuPanel so the whole thing can
      // animate in; a menu that simply appears is the one switch in the app
      // that still snaps.
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
      ),
      menuChildren: [
        _MenuPanel(
          selectedIndex:
              widget.sections.indexWhere((s) => s.id == widget.selectedId),
          children: [
        for (final s in widget.sections)
          MenuItemButton(
            style: MenuItemButton.styleFrom(
              // A line of text is 16 high, so 36 leaves exactly 10 above and
              // below it.
              minimumSize: const Size(0, kMenuRowHeight),
              maximumSize: const Size.fromHeight(kMenuRowHeight),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => widget.onSelect(s.id),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              // A minimum width lines the slugs up into a column without
              // pushing them to the far edge, which is what spacing them apart
              // did. A longer name simply grows past it.
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 74),
                child: Text(
                  s.title,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: s.id == widget.selectedId
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: s.id == widget.selectedId ? p.accent : p.ink,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              if (s.subtitle != null)
                Text(
                  s.subtitle!,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    color: s.id == widget.selectedId
                        ? p.accent.withValues(alpha: 0.7)
                        : p.inkFaint,
                  ),
                ),
            ]),
          ),
        ]),
      ],
      builder: (context, controller, _) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: AnimatedContainer(
            duration: Motion.quick,
            curve: Motion.curve,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.fromLTRB(15, 8, 9, 8),
            decoration: BoxDecoration(
              color: selected ? p.accent : (_hover ? p.raised : p.panel),
              borderRadius: BorderRadius.circular(Radii.block),
              border: Border.all(color: selected ? p.accent : p.line),
            ),
            child: Row(children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(current?.title ?? widget.label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                          color: title)),
                  const SizedBox(height: 1),
                  Text(current?.subtitle ?? '${widget.sections.length} 个${widget.label}',
                      style: TextStyle(fontSize: 10.5, height: 1.15, color: sub)),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded,
                  size: 16, color: selected ? p.accentInk : p.inkFaint),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The dropdown's own surface, so it can arrive rather than appear.
///
/// It grows from its top edge, which is where it is anchored, and fades in at
/// the same rate as every other content switch in the app.
class _MenuPanel extends StatefulWidget {
  const _MenuPanel({required this.children, this.selectedIndex = -1});

  final List<Widget> children;

  /// Scrolled into view on open, so a board picked earlier is not hidden
  /// below the fold. Negative when nothing is selected.
  final int selectedIndex;

  @override
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.swap,
  )..forward();

  late final Animation<double> _curved =
      CurvedAnimation(parent: _controller, curve: Motion.curve);

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  /// Centres the selected board in the visible window, when there is one and
  /// the list is long enough to scroll.
  void _revealSelected() {
    if (!mounted || widget.selectedIndex < 0 || !_scroll.hasClients) return;
    final viewport = _scroll.position.viewportDimension;
    final target = widget.selectedIndex * kMenuRowHeight -
        (viewport - kMenuRowHeight) / 2;
    _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.04),
          end: Offset.zero,
        ).animate(_curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(_curved),
          alignment: Alignment.topCenter,
          child: Container(
            decoration: BoxDecoration(
              color: p.panel,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: p.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: kMenuRowHeight * kMenuVisibleRows,
              ),
              child: Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
