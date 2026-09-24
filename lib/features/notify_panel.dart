import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme.dart';
import '../core/models.dart';
import '../widgets/chrome.dart';
import '../widgets/site_icon.dart';
import 'providers.dart';

/// Which sites announce new notices, one switch each.
///
/// A site can only announce what the app can read of its inbox, so each row
/// says whether that is possible now and, where it is not, what would make it
/// so.
class NotifyPanel extends ConsumerWidget {
  const NotifyPanel({super.key});

  static String _unavailable(SiteId site) => switch (site) {
        SiteId.v2ex => '在「论坛」里填上 V2EX 的 Token 才读得到消息',
        SiteId.linuxdo => '登录 linux.do 之后才读得到消息',
        SiteId.juejin => '掘金的消息还读不到',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final settings = ref.watch(settingsProvider);
    final small = Theme.of(context).textTheme.bodySmall;

    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('通知', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('有人回复或提到你时，在系统通知里说一声，并在程序坞图标上标出未读数。'
            '应用在前台时不弹通知。开着的站点每 10 分钟看一次消息。',
            style: small),
        const SizedBox(height: 8),
        for (final source in ref.watch(allSourcesProvider))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SiteIcon(
                  asset: source.iconAsset, glyph: source.glyph, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.name,
                          style: TextStyle(fontSize: 13, color: p.ink)),
                      if (source.member == null)
                        Text(_unavailable(source.id), style: small),
                    ]),
              ),
              Switch(
                value: source.member != null && settings.announces(source.id),
                onChanged: source.member == null
                    ? null
                    : (on) => ref
                        .read(settingsProvider.notifier)
                        .patch((s) => s.withAnnouncing(source.id, on)),
              ),
            ]),
          ),
      ]),
    );
  }
}
