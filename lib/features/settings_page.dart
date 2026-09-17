import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../core/forum_source.dart';
import '../core/models.dart';
import '../core/proxy.dart';
import '../core/read_log.dart';
import '../core/settings.dart';
import '../widgets/chrome.dart';
import '../widgets/site_icon.dart';
import '../widgets/swap.dart';
import 'linuxdo_auth_page.dart';
import 'providers.dart';

/// Settings in two halves: the forums, one card each, and everything that is
/// about the app rather than a site.
///
/// One card per site, built from the same [SiteCard] for all of them. What
/// differs per site is declared as data in [_fieldsFor].
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final tab = ref.watch(settingsTabProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 34, 34, 48),
      children: [
        Text('设置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text('凭据只存在这台电脑上，不会离开本机。',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 22),
        _Tabs(
          current: tab,
          onSelect: (t) => ref.read(settingsTabProvider.notifier).state = t,
        ),
        const SizedBox(height: 18),
        Swap(
          swapKey: tab,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (tab) {
              SettingsTab.forums => _forums(settings, notifier),
              SettingsTab.general => _general(settings, notifier),
            },
          ),
        ),
      ],
    );
  }

  // ---------- 论坛 ----------

  List<Widget> _forums(AppSettings settings, SettingsNotifier notifier) {
    return [
      for (final source in ref.watch(allSourcesProvider))
        SiteCard(
          source: source,
          shown: settings.shows(source.id),
          onShownChanged: (v) =>
              notifier.patch((s) => s.withSiteShown(source.id, v)),
          fields: _fieldsFor(source, settings, notifier),
          extra: source.id == SiteId.v2ex
              ? _V2exProxy(
                  settings: settings,
                  notifier: notifier,
                  onChanged: () => _reload(SiteId.v2ex),
                )
              : null,
          onOpenBrowser: source.id == SiteId.linuxdo && !Platform.isLinux
              ? () => _openBrowser(source.id)
              : null,
          onClear: _clearFor(source, settings, notifier),
        ),
    ];
  }

  Future<void> _openBrowser(SiteId site) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => const LinuxDoAuthPage()));
    if (ok == true) _reload(site);
  }

  VoidCallback? _clearFor(
      ForumSource source, AppSettings s, SettingsNotifier notifier) {
    return switch (source.id) {
      SiteId.linuxdo => s.linuxdoCookie.isEmpty
          ? null
          : () {
              notifier.patch((v) => v.copyWith(linuxdoCookie: ''));
              _reload(source.id);
            },
      SiteId.v2ex => s.v2exToken.isEmpty
          ? null
          : () {
              notifier.patch((v) => v.copyWith(v2exToken: ''));
              _reload(source.id);
            },
      SiteId.juejin => s.juejinCookie.isEmpty
          ? null
          : () {
              notifier.patch((v) => v.copyWith(juejinCookie: ''));
              _reload(source.id);
            },
    };
  }

  List<SettingField> _fieldsFor(
      ForumSource source, AppSettings s, SettingsNotifier notifier) {
    void save(AppSettings Function(AppSettings) f) {
      notifier.patch(f);
      _reload(source.id);
    }

    return switch (source.id) {
      SiteId.v2ex => [
          SettingField(
            label: 'Personal Access Token',
            value: s.v2exToken,
            onSave: (v) => save((x) => x.copyWith(v2exToken: v.trim())),
            helpLabel: '到 v2ex.com 创建 Token',
            helpUrl: Uri.parse('https://www.v2ex.com/settings/tokens'),
          ),
        ],
      SiteId.juejin => [
          SettingField(
            label: 'Cookie',
            value: s.juejinCookie,
            onSave: (v) => save((x) => x.copyWith(juejinCookie: v.trim())),
          ),
        ],
      SiteId.linuxdo => [
          SettingField(
            label: 'Cookie（需包含 cf_clearance）',
            value: s.linuxdoCookie,
            lines: 3,
            advanced: true,
            onSave: (v) => save((x) => x.copyWith(linuxdoCookie: v.trim())),
          ),
          SettingField(
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

  // ---------- 常规 ----------

  List<Widget> _general(AppSettings settings, SettingsNotifier notifier) {
    final readLog = ref.watch(readLogProvider);
    return [
      Panel(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('主题', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          Row(children: [
            for (final (value, label) in const [
              ('system', '跟随系统'),
              ('dark', '深色'),
              ('light', '浅色'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Choice(
                  label: label,
                  selected: settings.themeMode == value,
                  onTap: () =>
                      notifier.patch((s) => s.copyWith(themeMode: value)),
                ),
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
    ];
  }

  void _reload(SiteId site) {
    ref.invalidate(sectionsProvider(site));
    ref.read(detailStackProvider(site).notifier).state = const [];
  }
}

/// The two halves of the page, as one segmented control.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onSelect});

  final SettingsTab current;
  final ValueChanged<SettingsTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(Radii.block + 4),
          border: Border.all(color: p.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final tab in SettingsTab.values)
            _Choice(
              label: tab.label,
              selected: tab == current,
              onTap: () => onSelect(tab),
              idle: Colors.transparent,
              height: kControlHeight - 6,
              padding: 26,
              fontSize: 13.5,
            ),
        ]),
      ),
    );
  }
}

/// V2EX's proxy block: where to send its traffic, and whether the pictures
/// posts link to go the same way.
class _V2exProxy extends StatelessWidget {
  const _V2exProxy({
    required this.settings,
    required this.notifier,
    required this.onChanged,
  });

  final AppSettings settings;
  final SettingsNotifier notifier;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final typed = settings.v2exProxy.trim();
    final proxy = SiteProxy.parse(typed);
    final hasProxy = proxy != null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      const Divider(),
      const SizedBox(height: 16),
      Text('代理', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        '能直连就留空。填上以后 V2EX 的接口、网页和图片都从这里走。'
        '常见的是本机或局域网的代理，写成 127.0.0.1:7890 这样的地址就行；'
        '如果用的是替你转发的服务，用 {url} 或 {encoded_url} 指明目标地址放在哪。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 14),
      _FieldRow(
        field: SettingField(
          label: '代理地址',
          value: settings.v2exProxy,
          secret: false,
          onSave: (v) {
            notifier.patch((x) => x.copyWith(v2exProxy: v.trim()));
            onChanged();
          },
        ),
      ),
      if (typed.isNotEmpty && proxy == null) ...[
        const SizedBox(height: 8),
        Text('这个地址用不了，V2EX 还在直连。支持 host:port，或带 http:// 的地址。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.palette.rose)),
      ],
      const SizedBox(height: 14),
      _ToggleRow(
        title: '图片也走代理',
        // The pictures in a V2EX thread come from whichever host the author
        // used, so this is a separate decision from proxying the forum.
        subtitle: hasProxy
            ? '帖子里的图片和头像也通过代理加载，包括 v2ex.com 以外的图床。'
            : '先填一个能用的代理地址，才能让图片也走代理。',
        value: hasProxy && settings.v2exProxyImages,
        onChanged: hasProxy
            ? (v) => notifier.patch((x) => x.copyWith(v2exProxyImages: v))
            : null,
      ),
    ]);
  }
}

class SettingField {
  const SettingField({
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
    required this.fields,
    required this.shown,
    required this.onShownChanged,
    this.extra,
    this.onOpenBrowser,
    this.onClear,
  });

  final ForumSource source;
  final List<SettingField> fields;

  /// Whether the site is on the rail. A site switched off keeps its settings
  /// and its credentials; it just stops being one of the tabs.
  final bool shown;
  final ValueChanged<bool> onShownChanged;

  /// Anything only this site has, below its fields.
  final Widget? extra;

  final VoidCallback? onOpenBrowser;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final access = source.access;
    final plain = fields.where((c) => !c.advanced).toList();
    final advanced = fields.where((c) => c.advanced).toList();

    // Clearing a credential is the other half of saving it, so it sits beside
    // whichever control sets it: the field's own 保存 when the reader types
    // the credential, and the verify button when a browser earns it instead.
    final clearBesideField = onClear != null && plain.isNotEmpty;

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
          const SizedBox(width: 6),
          Tooltip(
            message: shown ? '在左侧显示' : '不在左侧显示',
            child: Switch(value: shown, onChanged: onShownChanged),
          ),
        ]),
        // A site that is off keeps everything it had, so its settings stay
        // editable; they just recede, the way the site itself has.
        AnimatedOpacity(
          duration: Motion.quick,
          curve: Motion.curve,
          opacity: shown ? 1 : 0.55,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 10),
            Text(source.accessNote,
                style: Theme.of(context).textTheme.bodySmall),
            if (onOpenBrowser != null || (onClear != null && !clearBesideField)) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: kControlHeight,
                child: Row(children: [
                  if (onOpenBrowser != null)
                    FilledButton(
                      onPressed: onOpenBrowser,
                      child: Text(access.level == AccessLevel.blocked
                          ? '开始验证'
                          : '重新验证'),
                    ),
                  if (onOpenBrowser != null && !clearBesideField)
                    const SizedBox(width: 8),
                  if (!clearBesideField)
                    OutlinedButton(
                        onPressed: onClear, child: const Text('清除凭据')),
                ]),
              ),
            ],
            for (final (i, field) in plain.indexed) ...[
              const SizedBox(height: 16),
              _FieldRow(
                field: field,
                onClear: i == 0 && clearBesideField ? onClear : null,
              ),
            ],
            if (advanced.isNotEmpty) ...[
              const SizedBox(height: 6),
              Theme(
                data:
                    Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text('手动填写',
                      style: TextStyle(fontSize: 13, color: p.inkMuted)),
                  tilePadding: EdgeInsets.zero,
                  // A floating label sits astride its field's top border, so
                  // it reaches above the field's own box. The disclosure clips
                  // its body to animate open, which would cut the first
                  // field's label in half without room above it.
                  childrenPadding: const EdgeInsets.only(top: 8, bottom: 6),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final field in advanced)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _FieldRow(field: field),
                      ),
                  ],
                ),
              ),
            ],
            ?extra,
          ]),
        ),
      ]),
    );
  }
}

/// A labelled setting and the button that stores it.
class _FieldRow extends StatefulWidget {
  const _FieldRow({required this.field, this.onClear});
  final SettingField field;

  /// Shown after 保存 when this field is the one holding the credential.
  final VoidCallback? onClear;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  late final _ctl = TextEditingController(text: widget.field.value);
  late bool _hidden = widget.field.secret;

  @override
  void didUpdateWidget(covariant _FieldRow old) {
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
        // The field's floor is the shared control height, set on the theme's
        // decoration, so it starts out exactly as tall as the button beside it
        // and grows downward from that same top edge — when it holds several
        // lines, and when the reader's text is scaled up. Pinning it to an
        // exact height instead would squash the latter.
        Expanded(child: field),
        const SizedBox(width: 8),
        SizedBox(
          height: kControlHeight,
          child: FilledButton(
            onPressed: () => f.onSave(_ctl.text),
            child: const Text('保存'),
          ),
        ),
        if (widget.onClear != null) ...[
          const SizedBox(width: 8),
          SizedBox(
            height: kControlHeight,
            child: OutlinedButton(
              onPressed: widget.onClear,
              child: const Text('清除凭据'),
            ),
          ),
        ],
      ]),
      if (f.helpUrl != null)
        TextButton(
          onPressed: () => launchUrl(f.helpUrl!),
          child: Text(f.helpLabel ?? '了解更多'),
        ),
    ]);
  }
}

/// A switch with the sentence explaining what it does beside it.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;

  /// Null disables the switch, which is how [Switch] already says it.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: context.palette.ink)),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      const SizedBox(width: 16),
      Switch(value: value, onChanged: onChanged),
    ]);
  }
}

/// The one pill toggle on this page: the tab strip at the top and the theme
/// picker under 常规 are the same control at two sizes.
class _Choice extends StatefulWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.idle,
    this.height = kControlHeight,
    this.padding = 18,
    this.fontSize = 13,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Unselected fill. Defaults to the raised surface; a pill sitting inside a
  /// track of its own passes transparent so the track shows through.
  final Color? idle;

  final double height;
  final double padding;
  final double fontSize;

  @override
  State<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends State<_Choice> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final selected = widget.selected;
    final idle = widget.idle ?? p.raised;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.quick,
          curve: Motion.curve,
          height: widget.height,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: widget.padding),
          decoration: BoxDecoration(
            color: selected ? p.accent : (_hover ? p.raised : idle),
            borderRadius: BorderRadius.circular(Radii.block),
          ),
          child: Text(widget.label,
              style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w600,
                  color: selected ? p.accentInk : p.inkMuted)),
        ),
      ),
    );
  }
}
