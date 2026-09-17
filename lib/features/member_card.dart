import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../core/models.dart';
import '../core/util.dart';
import '../widgets/avatar.dart';
import '../widgets/chrome.dart';
import '../widgets/relative_time.dart';
import 'providers.dart';

/// How wide the card sits beside the rail. Two lines of a notification fit
/// across it at the size they are drawn, which is what sets the number.
const _cardWidth = 272.0;

/// The gap between the rail and the card. It belongs to the card rather than
/// the rail, so crossing it counts as staying on the card — a pointer
/// travelling through dead space would otherwise close what it is reaching
/// for.
const _reach = 10.0;

/// The card's own inset, held by each section rather than by the card.
///
/// A section that can be clicked reaches past it, so its hover wash has room
/// to breathe while its text still lines up with the sections that cannot.
const _inset = EdgeInsets.symmetric(horizontal: 8);

/// Who the reader is on a site, slid out from its block on the rail.
///
/// Built only while the pointer is on the block or the card, which is also
/// what starts the fetch: nothing here is read until someone looks.
class MemberCard extends ConsumerWidget {
  const MemberCard({super.key, required this.site});

  final SiteId site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(memberProvider(site));
    // A profile already read stays on screen while the next read is in
    // flight. The card refreshes itself on a timer, and a spinner every hour
    // in place of a perfectly good profile would be worse than slightly old
    // numbers.
    final profile = member.valueOrNull;
    return Padding(
      padding: const EdgeInsets.only(left: _reach),
      child: _SlideIn(
        child: SizedBox(
          width: _cardWidth,
          child: Panel(
            radius: Radii.card,
            padding: const EdgeInsets.fromLTRB(6, 13, 6, 12),
            child: switch ((profile, member.error)) {
              (final Member found, _) => _Profile(site: site, member: found),
              (_, final Object failure?) => _Failed(errorText(failure)),
              _ => const _Loading(),
            },
          ),
        ),
      ),
    );
  }
}

class _Profile extends ConsumerWidget {
  const _Profile({required this.site, required this.member});

  final SiteId site;
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final images = ref.watch(siteImagesProvider(site));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: _inset,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            UserAvatar(
              url: member.avatarUrl,
              name: member.name,
              size: 44,
              images: images,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              color: p.ink)),
                    ),
                    if (member.badge case final badge?) ...[
                      const SizedBox(width: 6),
                      Pill(label: badge, tone: p.cream, filled: true),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(_standing(member),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, height: 1.2, color: p.inkFaint)),
                ],
              ),
            ),
          ]),
        ),
        if (member.tagline case final tagline?) ...[
          const SizedBox(height: 10),
          Padding(
            padding: _inset,
            child: Text(tagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5, height: 1.35, color: p.inkMuted)),
          ),
        ],
        const _Rule(),
        _Inbox(site: site, member: member),
        if (member.note case final note?) ...[
          const _Rule(),
          Padding(
            padding: _inset,
            child: Text(note,
                style:
                    TextStyle(fontSize: 10.5, height: 1.3, color: p.inkFaint)),
          ),
        ],
      ],
    );
  }

  /// The two things a forum knows about someone before they have written
  /// anything: which number they signed up as, and when.
  String _standing(Member m) => [
        if (m.number case final n?) '第 $n 号会员',
        if (m.joinedAt case final t?) '${t.year} 年加入',
      ].join(' · ');
}

/// The inbox, as one row that opens the real list.
///
/// A site that numbers its notifications but does not track which have been
/// read — V2EX is one — leaves the app to remember where the reader got to.
/// Until they have opened the list from here there is no mark to count
/// against, so the row reports how big the inbox is rather than announcing a
/// decade of history as unread.
class _Inbox extends ConsumerWidget {
  const _Inbox({required this.site, required this.member});

  final SiteId site;
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final seen =
        ref.watch(settingsProvider.select((s) => s.seenNotification(site)));
    // A site that counts its own unread is believed. Only the ones that do
    // not fall back to the mark this app keeps, and only those can saturate.
    final tracked = member.unread;
    final unread = tracked ?? member.unreadSince(seen);
    final counted = tracked != null || seen > 0;
    final saturated = tracked == null && member.saturated(unread);
    final newest = member.notifications.firstOrNull;

    return _Row(
      onTap: member.notificationsUrl == null
          ? null
          : () {
              launchUrl(member.notificationsUrl!);
              // Opening the list is what counts as having seen it; nothing
              // else moves the mark. A site that keeps its own count needs no
              // mark and is left alone.
              if (member.unread == null) {
                ref.read(settingsProvider.notifier).patch((s) =>
                    s.withNotificationsSeen(site, member.newestNotification));
              }
            },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.mail_outline_rounded, size: 13, color: p.inkFaint),
          const SizedBox(width: 6),
          Text(counted ? '未读消息' : '消息',
              style: TextStyle(fontSize: 12, height: 1.2, color: p.inkMuted)),
          const Spacer(),
          Pill(
            label: counted
                ? '$unread${saturated ? '+' : ''}'
                : compactCount(member.notificationTotal),
            tone: counted && unread > 0 ? p.badge : p.inkMuted,
            filled: counted && unread > 0,
          ),
          const SizedBox(width: 4),
          Icon(Icons.north_east_rounded, size: 12, color: p.inkFaint),
        ]),
        if (newest != null) ...[
          const SizedBox(height: 6),
          Text(newest.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 11.5, height: 1.35, color: p.inkMuted)),
          const SizedBox(height: 2),
          RelativeTime(newest.createdAt,
              style: TextStyle(fontSize: 10.5, color: p.inkFaint)),
        ],
      ]),
    );
  }
}

/// A block of the card that does something when clicked, washed on hover the
/// same way the top bar's buttons are.
class _Row extends StatefulWidget {
  const _Row({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final live = widget.onTap != null;
    return MouseRegion(
      cursor: live ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: live ? (_) => setState(() => _hover = true) : null,
      onExit: live ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.quick,
          curve: Motion.curve,
          padding: _inset.add(const EdgeInsets.symmetric(vertical: 7)),
          decoration: BoxDecoration(
            color: _hover ? p.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.block),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A hairline with the air the card gives every divider, so the sections are
/// spaced identically without each one restating it.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(height: 1, color: context.palette.line),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: _inset,
      child: SizedBox(
        height: 44,
        child: Row(children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.inkFaint),
          ),
          const SizedBox(width: 10),
          Text('读取中', style: TextStyle(fontSize: 12, color: p.inkFaint)),
        ]),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: _inset,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: 14, color: p.rose),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.35, color: p.inkMuted)),
        ),
      ]),
    );
  }
}

/// Arrives from the rail rather than appearing on top of it, at the rate
/// every other panel in the app opens at.
class _SlideIn extends StatefulWidget {
  const _SlideIn({required this.child});

  final Widget child;

  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: Motion.swap)..forward();

  late final Animation<double> _curved =
      CurvedAnimation(parent: _controller, curve: Motion.curve);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.06, 0),
            end: Offset.zero,
          ).animate(_curved),
          child: widget.child,
        ),
      );
}
