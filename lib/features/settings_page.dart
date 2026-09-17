import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../core/forum_source.dart';
import '../core/models.dart';
import '../core/read_log.dart';
import '../core/settings.dart';
import '../widgets/chrome.dart';
import '../widgets/site_icon.dart';
import 'linuxdo_auth_page.dart';
import 'providers.dart';

/// One card per site, built from the same [SiteCard] for all of them. What
/// differs per site is declared as data in [_credentialsFor].
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final sources = ref.watch(allSourcesProvider);
    final readLog = ref.watch(readLogProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 34, 34, 48),
      children: [
        Text('设置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text('凭据只存在这台电脑上，不会离开本机。',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 26),
        Panel(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('外观', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            Row(children: [
              for (final (value, label) in const [
                ('system', '跟随系统'),
                ('dark', '深色'),
                ('light', '浅色'),
              ])
                _Choice(
                  label: label,
                  selected: settings.themeMode == value,
                  onTap: () => notifier.patch((s) => s.copyWith(themeMode: value)),
                ),
            ]),
          ]),
        ),
        Panel(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('阅读记录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              readLog.length == 0
                  ? '还没有读过的帖子。读过的帖子会在列表里变暗。'
                  : '记住了 ${readLog.length} 篇读过的帖子，最多保留 ${ReadLog.limit} 篇。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: kControlHeight,
              child: OutlinedButton(
                onPressed: readLog.length == 0
                    ? null
                    : () => ref.read(readLogProvider.notifier).clear(),
                child: const Text('清除阅读记录'),
              ),
            ),
          ]),
        ),
        for (final source in sources)
          SiteCard(
            source: source,
            credentials: _credentialsFor(source, settings, notifier, ref),
            onOpenBrowser: source.id == SiteId.linuxdo && !Platform.isLinux
                ? () => _openBrowser(context, ref, source.id)
                : null,
            onClear: _clearFor(source, settings, notifier, ref),
          ),
        const SizedBox(height: 10),
        Text('Codora · 只读聚合，不会代替你发帖或点赞',
            style: TextStyle(fontSize: 11.5, color: p.inkFaint)),
      ],
    );
  }

  Future<void> _openBrowser(BuildContext context, WidgetRef ref, SiteId site) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => const LinuxDoAuthPage()));
    if (ok == true) _reload(ref, site);
  }

  VoidCallback? _clearFor(ForumSource source, AppSettings s,
      SettingsNotifier notifier, WidgetRef ref) {
    return switch (source.id) {
      SiteId.linuxdo => s.linuxdoCookie.isEmpty
          ? null
          : () {
              notifier.patch((v) => v.copyWith(linuxdoCookie: ''));
              _reload(ref, source.id);
            },
      SiteId.v2ex => s.v2exToken.isEmpty
          ? null
          : () {
              notifier.patch((v) => v.copyWith(v2exToken: ''));
              _reload(ref, source.id);
            },
      SiteId.juejin => s.juejinCookie.isEmpty
          ? null
          : () {
              notifier.patch((v) => v.copyWith(juejinCookie: ''));
              _reload(ref, source.id);
            },
    };
  }

  List<CredentialField> _credentialsFor(ForumSource source, AppSettings s,
      SettingsNotifier notifier, WidgetRef ref) {
    void save(AppSettings Function(AppSettings) f) {
      notifier.patch(f);
      _reload(ref, source.id);
    }

    return switch (source.id) {
      SiteId.v2ex => [
          CredentialField(
            label: 'Personal Access Token',
            value: s.v2exToken,
            onSave: (v) => save((x) => x.copyWith(v2exToken: v.trim())),
            helpLabel: '到 v2ex.com 创建 Token',
            helpUrl: Uri.parse('https://www.v2ex.com/settings/tokens'),
          ),
        ],
      SiteId.juejin => [
          CredentialField(
            label: 'Cookie',
            value: s.juejinCookie,
            onSave: (v) => save((x) => x.copyWith(juejinCookie: v.trim())),
          ),
        ],
      SiteId.linuxdo => [
          CredentialField(
            label: 'Cookie（需包含 cf_clearance）',
            value: s.linuxdoCookie,
            lines: 3,
            advanced: true,
            onSave: (v) => save((x) => x.copyWith(linuxdoCookie: v.trim())),
          ),
          CredentialField(
            label: 'User-Agent（要和取 Cookie 的浏览器一致）',
            value: s.linuxdoUserAgent,
            secret: false,
            advanced: true,
            onSave: (v) => save((x) => x.copyWith(
                linuxdoUserAgent: v.trim().isEmpty ? kDesktopUserAgent : v.trim())),
          ),
        ],
    };
  }

  void _reload(WidgetRef ref, SiteId site) {
    ref.invalidate(sectionsProvider(site));
    ref.read(detailStackProvider(site).notifier).state = const [];
  }
}

class CredentialField {
  const CredentialField({
    required this.label,
    required this.value,
    required this.onSave,
    this.secret = true,
    this.lines = 1,
    this.advanced = false,
    this.helpLabel,
    this.helpUrl,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSave;
  final bool secret;
  final int lines;

  /// Advanced fields are collapsed behind a disclosure, for sites where the
  /// normal path is a button rather than typing.
  final bool advanced;
  final String? helpLabel;
  final Uri? helpUrl;
}

class SiteCard extends StatelessWidget {
  const SiteCard({
    super.key,
    required this.source,
    required this.credentials,
    this.onOpenBrowser,
    this.onClear,
  });

  final ForumSource source;
  final List<CredentialField> credentials;
  final VoidCallback? onOpenBrowser;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final access = source.access;
    final plain = credentials.where((c) => !c.advanced).toList();
    final advanced = credentials.where((c) => c.advanced).toList();

    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.raised,
              borderRadius: BorderRadius.circular(Radii.block),
            ),
            child: SiteIcon(
                asset: source.iconAsset, glyph: source.glyph, size: 22),
          ),
          const SizedBox(width: 12),
          Text(source.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 10),
          Pill(
            label: access.label,
            tone: switch (access.level) {
              AccessLevel.full => p.mint,
              AccessLevel.limited => p.cream,
              AccessLevel.blocked => p.rose,
              AccessLevel.open => p.inkMuted,
            },
            filled: access.level != AccessLevel.open,
          ),
          const Spacer(),
          QuietIconButton(
            icon: Icons.north_east_rounded,
            tooltip: '打开 ${source.name}',
            onPressed: () => launchUrl(source.homeUrl),
          ),
        ]),
        const SizedBox(height: 10),
        Text(source.accessNote, style: Theme.of(context).textTheme.bodySmall),
        if (onOpenBrowser != null || onClear != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: kControlHeight,
            child: Row(children: [
              if (onOpenBrowser != null)
                FilledButton(
                  onPressed: onOpenBrowser,
                  child:
                      Text(access.level == AccessLevel.blocked ? '开始验证' : '重新验证'),
                ),
              if (onOpenBrowser != null && onClear != null)
                const SizedBox(width: 8),
              if (onClear != null)
                OutlinedButton(onPressed: onClear, child: const Text('清除凭据')),
            ]),
          ),
        ],
        for (final field in plain) ...[
          const SizedBox(height: 16),
          _CredentialRow(field: field),
        ],
        if (advanced.isNotEmpty) ...[
          const SizedBox(height: 6),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text('手动填写',
                  style: TextStyle(fontSize: 13, color: p.inkMuted)),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 6),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final field in advanced)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CredentialRow(field: field),
                  ),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}

class _CredentialRow extends StatefulWidget {
  const _CredentialRow({required this.field});
  final CredentialField field;

  @override
  State<_CredentialRow> createState() => _CredentialRowState();
}

class _CredentialRowState extends State<_CredentialRow> {
  late final _ctl = TextEditingController(text: widget.field.value);
  late bool _hidden = widget.field.secret;

  @override
  void didUpdateWidget(covariant _CredentialRow old) {
    super.didUpdateWidget(old);
    if (old.field.value != widget.field.value && _ctl.text != widget.field.value) {
      _ctl.text = widget.field.value;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final singleLineSecret = _hidden && f.lines == 1;

    final field = TextField(
      controller: _ctl,
      obscureText: singleLineSecret,
      maxLines: singleLineSecret ? 1 : f.lines,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: f.label,
        suffixIcon: f.secret && f.lines == 1
            ? IconButton(
                icon: Icon(
                    _hidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 17),
                onPressed: () => setState(() => _hidden = !_hidden),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                    minWidth: kControlHeight, minHeight: kControlHeight),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(
            minWidth: kControlHeight, minHeight: kControlHeight),
      ),
      onSubmitted: f.onSave,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // A single-line field is pinned to the shared control height so it and
        // the button beside it are exactly the same size; a multi-line field
        // grows downward from that same top edge.
        Expanded(
          child: f.lines == 1
              ? SizedBox(height: kControlHeight, child: field)
              : field,
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: kControlHeight,
          child: FilledButton(
            onPressed: () => f.onSave(_ctl.text),
            child: const Text('保存'),
          ),
        ),
      ]),
      if (f.helpUrl != null)
        TextButton(
          onPressed: () => launchUrl(f.helpUrl!),
          child: Text(f.helpLabel ?? '了解更多'),
        ),
    ]);
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: kControlHeight,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
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
      ),
    );
  }
}
