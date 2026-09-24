import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../core/forum_source.dart';
import '../core/linuxdo_session.dart';
import '../core/models.dart';
import '../core/proxy.dart';
import '../core/settings.dart';
import '../core/updates.dart';
import '../core/util.dart';
import '../sources/linuxdo_source.dart';
import '../sources/v2ex_source.dart';
import '../widgets/chrome.dart';
import '../widgets/site_icon.dart';
import '../widgets/swap.dart';
import 'block_panel.dart';
import 'cache_panel.dart';
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
          // Read through the framework rather than `dart:io`, so a test
          // runs as the platform it names and not whichever one it is on.
          onOpenBrowser: source.id == SiteId.linuxdo &&
                  defaultTargetPlatform != TargetPlatform.linux
              ? () => _openBrowser(source.id,
                  // Past the challenge and anonymous: take them straight to
                  // the form instead of the front page they have to find it
                  // from.
                  signIn: source.access.level == AccessLevel.limited)
              : null,
          onSignOut: source.id == SiteId.linuxdo && settings.linuxdoLoggedIn
              ? () => _signOutOfLinuxDo(notifier)
              : null,
          onClear: _clearFor(source, settings, notifier),
        ),
    ];
  }

  Future<void> _openBrowser(SiteId site, {bool signIn = false}) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LinuxDoAuthPage(signIn: signIn)));
    if (ok == true) _reload(site);
  }

  /// Ends the session without throwing away the Cloudflare clearance: reading
  /// anonymously still needs it, and earning it again is the slow part.
  Future<void> _signOutOfLinuxDo(SettingsNotifier notifier) async {
    await signOutOfLinuxDo();
    await notifier.patch((s) => s.withLinuxdoSignedOut());
    if (mounted) _reload(SiteId.linuxdo);
  }

  VoidCallback? _clearFor(
      ForumSource source, AppSettings s, SettingsNotifier notifier) {
    return switch (source.id) {
      // The browser is where this credential actually lives. Emptying the
      // stored header alone would leave the feed signed in to an account the
      // app no longer believes it has — 清除凭据 means all of it, the
      // challenge included. 退出登录, beside it, is the one that keeps that.
      SiteId.linuxdo => s.linuxdoCookie.isEmpty
          ? null
          : () async {
              await clearLinuxDoCookies();
              await notifier.patch((v) => v.copyWith(linuxdoCookie: ''));
              if (mounted) _reload(source.id);
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
      // Pasting a cookie would not help where there is no browser to send
      // it from; the card's note says why instead.
      SiteId.linuxdo when !LinuxDoSource.supported => const [],
      SiteId.linuxdo => [
          SettingField(
            // The clearance is the one cookie worth *not* pasting: it belongs
            // to the browser that earned it. What this is for is a sign-in
            // the embedded browser cannot perform — a passkey, or a provider
            // that refuses to run inside a WebView.
            label: 'Cookie（从别的浏览器带一个已登录的 _t 进来）',
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
    return [
      const AboutPanel(),
      const BlockPanel(),
      const CachePanel(),
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
    ];
  }

  void _reload(SiteId site) {
    ref.invalidate(sectionsProvider(site));
    ref.read(detailStackProvider(site).notifier).state = const [];
  }
}

/// The two halves of the page, as one segmented control.
///
/// The selection is a single pill that slides between the tabs rather than a
/// fill that jumps from one to the other, so the eye follows it across instead
/// of having to find it again.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onSelect});

  final SettingsTab current;
  final ValueChanged<SettingsTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const tabs = SettingsTab.values;
    final index = tabs.indexOf(current);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(Radii.block + 4),
          border: Border.all(color: p.line),
        ),
        // The row sizes the strip; the pill is laid over it at a fraction of
        // that width, which keeps the two in step whatever the labels say.
        child: IntrinsicWidth(
          child: Stack(children: [
            Positioned.fill(
              child: AnimatedAlign(
                duration: Motion.swap,
                curve: Motion.curve,
                alignment: Alignment(
                    tabs.length == 1 ? 0 : -1 + 2 * index / (tabs.length - 1),
                    0),
                child: FractionallySizedBox(
                  widthFactor: 1 / tabs.length,
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(Radii.block),
                    ),
                  ),
                ),
              ),
            ),
            Row(children: [
              for (final tab in tabs)
                Expanded(
                  child: _TabLabel(
                    label: tab.label,
                    selected: tab == current,
                    onTap: () => onSelect(tab),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// One tab's label. The fill behind it belongs to the sliding pill, so this
/// paints only its own hover state and lets its colour cross-fade.
class _TabLabel extends StatefulWidget {
  const _TabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabLabel> createState() => _TabLabelState();
}

class _TabLabelState extends State<_TabLabel> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.quick,
          curve: Motion.curve,
          height: kControlHeight - 6,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          decoration: BoxDecoration(
            // Hovering the selected tab would only paint over its own pill.
            color: !widget.selected && _hover ? p.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.block),
          ),
          child: AnimatedDefaultTextStyle(
            duration: Motion.swap,
            curve: Motion.curve,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: widget.selected ? p.accentInk : p.inkMuted),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

/// V2EX's proxy block: where to send its traffic, whether the pictures posts
/// link to go the same way, and a way to find out whether any of it works.
class _V2exProxy extends StatefulWidget {
  const _V2exProxy({
    required this.settings,
    required this.notifier,
    required this.onChanged,
  });

  final AppSettings settings;
  final SettingsNotifier notifier;
  final VoidCallback onChanged;

  @override
  State<_V2exProxy> createState() => _V2exProxyState();
}

class _V2exProxyState extends State<_V2exProxy> {
  _ProbeResult? _result;
  bool _running = false;

  /// Tries the address that is on screen, saved or not.
  ///
  /// Trying the saved one instead would make the button useless for the thing
  /// it is most wanted for — finding out whether an address works before
  /// committing the forum to it.
  Future<void> _test(String address) async {
    final typed = address.trim();
    // An address the app cannot read is not a route to test: the source would
    // quietly fall back to a direct connection and report on that instead.
    if (typed.isNotEmpty && SiteProxy.parse(typed) == null) {
      setState(() => _result = const _ProbeResult.bad('这个地址读不出来，没法测'));
      return;
    }
    setState(() {
      _running = true;
      _result = null;
    });
    final source = V2exSource(proxy: typed);
    _ProbeResult outcome;
    try {
      outcome = _ProbeResult.ok(await source.probe(), viaProxy: typed.isNotEmpty);
    } catch (e) {
      outcome = _ProbeResult.bad(errorText(e));
    } finally {
      source.close();
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      // Whether it is still the address on screen decides how the result is
      // worded, so it is settled now rather than when it is drawn.
      _result = outcome.against(widget.settings.v2exProxy.trim(), typed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final typed = widget.settings.v2exProxy.trim();
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
        '如果用的是替你转发的服务，用 {url} 或 {encoded_url} 指明目标地址放在哪。'
        '拿不准就按「测试」，它会照着框里的地址真的请求一次 V2EX。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 14),
      _FieldRow(
        field: SettingField(
          label: '代理地址',
          value: widget.settings.v2exProxy,
          secret: false,
          onSave: (v) {
            widget.notifier.patch((x) => x.copyWith(v2exProxy: v.trim()));
            widget.onChanged();
          },
        ),
        action: (read) => OutlinedButton(
          onPressed: _running ? null : () => _test(read()),
          child: Text(_running ? '测试中' : '测试'),
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
      if (_running || _result != null) ...[
        const SizedBox(height: 10),
        _ProbeLine(running: _running, result: _result),
      ],
      const SizedBox(height: 14),
      _ToggleRow(
        title: '图片也走代理',
        // The pictures in a V2EX thread come from whichever host the author
        // used, so this is a separate decision from proxying the forum.
        subtitle: hasProxy
            ? '帖子里的图片和头像也通过代理加载，包括 v2ex.com 以外的图床。'
            : '先填一个能用的代理地址，才能让图片也走代理。',
        value: hasProxy && widget.settings.v2exProxyImages,
        onChanged: hasProxy
            ? (v) => widget.notifier.patch((x) => x.copyWith(v2exProxyImages: v))
            : null,
      ),
    ]);
  }
}

/// What one press of 测试 found.
class _ProbeResult {
  const _ProbeResult.ok(this.took, {this.viaProxy = false})
      : problem = null,
        unsaved = false;
  const _ProbeResult.bad(this.problem)
      : took = null,
        viaProxy = false,
        unsaved = false;
  const _ProbeResult._(this.took, this.problem, this.viaProxy, this.unsaved);

  final Duration? took;
  final String? problem;

  /// Whether the route tested went through an address at all, so a working
  /// direct connection is not reported as a working proxy.
  final bool viaProxy;

  /// Whether the address tried is not the one the forum is currently using.
  final bool unsaved;

  bool get ok => problem == null;

  _ProbeResult against(String saved, String tried) =>
      _ProbeResult._(took, problem, viaProxy, saved != tried);

  String get sentence {
    if (problem != null) return problem!;
    final ms = took!.inMilliseconds;
    return '${viaProxy ? '经代理连上了 V2EX' : '直连 V2EX 没问题'} · $ms ms';
  }
}

class _ProbeLine extends StatelessWidget {
  const _ProbeLine({required this.running, required this.result});

  final bool running;
  final _ProbeResult? result;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final small = Theme.of(context).textTheme.bodySmall;
    if (running || result == null) {
      return Row(children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2, color: p.inkFaint),
        ),
        const SizedBox(width: 8),
        Text('正在按这个地址请求 V2EX…', style: small),
      ]);
    }
    final r = result!;
    final tone = r.ok ? p.mint : p.rose;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(r.ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
          size: 14, color: tone),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          // Saying which address was tried matters most when it is not the
          // one in force: a green line about an address nobody saved would
          // otherwise read as the forum being fixed.
          r.unsaved ? '${r.sentence}（测的是框里还没保存的地址）' : r.sentence,
          style: small?.copyWith(color: tone),
        ),
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
    this.onSignOut,
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

  /// Opens this site's in-app browser. What that is *for* changes with where
  /// the site currently stands, which is why the label is worked out from
  /// [ForumSource.access] rather than fixed.
  final VoidCallback? onOpenBrowser;

  /// Ends the session while keeping whatever else was earned in the browser.
  /// Only offered by a site that can be signed in to, and only once it is.
  final VoidCallback? onSignOut;

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
            if (onOpenBrowser != null ||
                onSignOut != null ||
                (onClear != null && !clearBesideField)) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: kControlHeight,
                child: Row(children: [
                  if (onOpenBrowser != null) ...[
                    FilledButton(
                      onPressed: onOpenBrowser,
                      child: Text(switch (access.level) {
                        // Nothing loads yet, so the challenge is the whole job.
                        AccessLevel.blocked => '开始验证',
                        // Past the door but anonymous: signing in is the next
                        // thing anyone would want, so the button offers it
                        // rather than the step already behind them.
                        AccessLevel.limited => '登录',
                        _ => '重新验证',
                      }),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (onSignOut != null) ...[
                    OutlinedButton(
                        onPressed: onSignOut, child: const Text('退出登录')),
                    const SizedBox(width: 8),
                  ],
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
  const _FieldRow({required this.field, this.onClear, this.action});
  final SettingField field;

  /// Shown after 保存 when this field is the one holding the credential.
  final VoidCallback? onClear;

  /// A further action beside 保存. It is handed a way to read whatever is
  /// currently in the field, rather than the value itself, so that pressing
  /// it acts on what is on screen — an address can be tried before it is
  /// committed, and this row does not have to rebuild on every keystroke.
  final Widget Function(String Function() typed)? action;

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
        if (widget.action case final action?) ...[
          const SizedBox(width: 8),
          SizedBox(height: kControlHeight, child: action(() => _ctl.text)),
        ],
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

/// The theme picker's pill toggle. Its fill is its own, unlike a tab, whose
/// fill is the strip's sliding pill.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
    );
  }
}

/// Which version is running, and whether a newer one has been published.
///
/// Updating is the reader's call: the panel says what there is and takes them
/// to the release page, rather than replacing the app under them.
class AboutPanel extends ConsumerWidget {
  const AboutPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final small = Theme.of(context).textTheme.bodySmall;
    final version = ref.watch(appVersionProvider).valueOrNull;
    final update = ref.watch(updateProvider);
    void recheck() => ref.invalidate(updateProvider);

    final Widget status = update.when(
      skipLoadingOnRefresh: false,
      loading: () => Text('正在检查更新…', style: small),
      error: (_, _) => Row(children: [
        Text('没能检查更新', style: small),
        const SizedBox(width: 8),
        TextButton(onPressed: recheck, child: const Text('再试一次')),
      ]),
      data: (Release? release) => release == null
          ? Row(children: [
              Text('已是最新版本', style: small),
              const SizedBox(width: 8),
              TextButton(onPressed: recheck, child: const Text('检查更新')),
            ])
          : SizedBox(
              height: kControlHeight,
              child: Row(children: [
                Pill(label: '新版本 ${release.version}', tone: p.mint, filled: true),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => launchUrl(release.url),
                  child: const Text('前往下载'),
                ),
              ]),
            ),
    );

    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Codora', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 10),
          if (version != null)
            Text(version, style: TextStyle(fontSize: 13, color: p.inkMuted)),
        ]),
        const SizedBox(height: 12),
        status,
      ]),
    );
  }
}
