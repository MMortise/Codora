import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme.dart';
import '../core/cache_usage.dart';
import '../core/disk_cache.dart';
import '../core/read_log.dart';
import '../widgets/chrome.dart';
import 'providers.dart';

/// What is on disk, measured when the settings page asks.
///
/// Auto-disposing on purpose: this walks directories, so it should happen
/// when someone is looking at the answer and not a moment more often.
final cacheReportProvider = FutureProvider.autoDispose<CacheReport>((ref) {
  final limit = ref.watch(settingsProvider.select((s) => s.cacheLimit));
  return measureCache(limit);
});

/// The sizes a limit can be set to.
///
/// A slider over a range this wide is useless — half a terabyte of travel to
/// pick a gigabyte — so it moves between sensible sizes instead, ending at
/// whatever the disk actually holds.
List<int> limitStops(int capacity) {
  const gb = 1024 * 1024 * 1024;
  const ladder = [
    256 * 1024 * 1024,
    512 * 1024 * 1024,
    gb,
    2 * gb,
    5 * gb,
    10 * gb,
    20 * gb,
    50 * gb,
    100 * gb,
    200 * gb,
    500 * gb,
  ];
  return [
    for (final stop in ladder)
      if (stop < capacity) stop,
    capacity,
  ];
}

class CachePanel extends ConsumerWidget {
  const CachePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final report = ref.watch(cacheReportProvider).valueOrNull;

    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          Text('缓存', style: text.titleMedium),
          const SizedBox(width: 10),
          if (report != null)
            Text('共 ${formatBytes(report.total)}',
                style: text.bodySmall?.copyWith(color: p.inkMuted)),
        ]),
        const SizedBox(height: 4),
        Text(
          '图片存在本地，下次就不用再下一遍。超过上限时，最久没看过的先被丢掉。',
          style: text.bodySmall,
        ),
        const SizedBox(height: 16),
        if (report == null)
          const _Measuring()
        else ...[
          _UsageBar(report: report),
          const SizedBox(height: 14),
          _Legend(report: report),
          const SizedBox(height: 18),
          _LimitSlider(report: report),
          const SizedBox(height: 16),
          // Both clears together: one takes everything, the other takes only
          // the reader's own history, and having them apart made the second
          // read as a different feature rather than a narrower version of the
          // first.
          SizedBox(
            height: kControlHeight,
            child: Row(children: [
              OutlinedButton(
                onPressed:
                    report.total == 0 ? null : () => _confirmClear(context, ref),
                child: const Text('清理缓存'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                // The log is one of the three slices, so the bar has to be
                // told. The legend watches the log itself and would otherwise
                // read 0 篇 beside a slice still holding its old room.
                onPressed: ref.watch(readLogProvider).length == 0
                    ? null
                    : () async {
                        await ref.read(readLogProvider.notifier).clear();
                        ref.invalidate(cacheReportProvider);
                      },
                child: const Text('清除阅读记录'),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  /// Clearing is not undoable and two of the three kinds cost something real
  /// to rebuild, so what goes — and what it costs — is spelled out first.
  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final p = context.palette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.panel,
        title: const Text('清理缓存', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('会清掉这三样：', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            for (final line in const [
              '图片 — 会重新下载，只是慢一点',
              '网页缓存 — linux.do 的页面要重新下载；人机验证和登录都留着',
              '阅读记录 — 读过的帖子会重新变成未读',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('· $line',
                    style: TextStyle(fontSize: 12.5, color: p.inkMuted)),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清理')),
        ],
      ),
    );
    if (ok != true) return;

    await DiskCache.instance.clear();
    // Only the pages. `clearAllCache` takes WebKit's memory, disk, fetch and
    // offline caches and nothing else — cookies, local storage and the
    // Cloudflare clearance stay where they are. That is why the dialog above
    // promises the pages back and not the sign-in: saying otherwise would be
    // a threat this cannot carry out, and 退出登录 is one button away for
    // anyone who means it.
    try {
      await InAppWebViewController.clearAllCache();
    } catch (_) {}
    await ref.read(readLogProvider.notifier).clear();
    ref.invalidate(cacheReportProvider);
  }
}

class _Measuring extends StatelessWidget {
  const _Measuring();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(children: [
      SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(strokeWidth: 2, color: p.inkFaint),
      ),
      const SizedBox(width: 9),
      Text('正在统计…', style: TextStyle(fontSize: 12, color: p.inkFaint)),
    ]);
  }
}

/// One bar, split by kind, drawn against whichever is larger: the limit, or
/// what is actually there. Measuring it against the limit is what makes the
/// empty part mean something — that is the room left.
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.report});

  /// A kind that is present but tiny still gets a sliver, so the bar says
  /// "this exists" rather than rounding it out of the picture.
  static const _minSlice = 3.0;

  final CacheReport report;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.pill),
      child: SizedBox(
        height: 12,
        child: LayoutBuilder(builder: (context, constraints) {
          final widths = _widths(constraints.maxWidth);
          return Stack(children: [
            Positioned.fill(child: ColoredBox(color: p.raised)),
            Row(children: [
              for (final kind in CacheKind.values)
                if (widths[kind] case final width?)
                  SizedBox(
                    key: ValueKey(kind),
                    width: width,
                    child: ColoredBox(color: kind.tone(p)),
                  ),
            ]),
          ]);
        }),
      ),
    );
  }

  /// How wide each present kind is drawn, in pixels rather than flex: a
  /// `Flexible` hands its child an upper bound, and a box with nothing in it
  /// takes that as licence to be nothing at all.
  Map<CacheKind, double> _widths(double full) {
    if (full <= 0) return const {};
    final scale = report.limit > report.total ? report.limit : report.total;
    if (scale <= 0) return const {};

    final widths = <CacheKind, double>{};
    for (final kind in CacheKind.values) {
      final size = report.of(kind);
      if (size <= 0) continue;
      final exact = size / scale * full;
      widths[kind] = exact < _minSlice ? _minSlice : exact;
    }
    // Those slivers can add up to more room than there is, once the cache is
    // full and several kinds are rounding up at once.
    final total = widths.values.fold(0.0, (a, b) => a + b);
    if (total <= full) return widths;
    return {
      for (final entry in widths.entries) entry.key: entry.value / total * full,
    };
  }
}

class _Legend extends ConsumerWidget {
  const _Legend({required this.report});

  final CacheReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    // The read log is the one kind whose count says more than its size: a few
    // kilobytes means nothing, "3000 篇" means something.
    String note(CacheKind kind) => kind == CacheKind.readLog
        ? '${kind.note}。记住了 ${ref.watch(readLogProvider).length} 篇，'
            '最多保留 ${ReadLog.limit} 篇'
        : kind.note;
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        for (final kind in CacheKind.values)
          Tooltip(
            message: note(kind),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: kind.tone(p), shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(kind.label,
                  style: TextStyle(fontSize: 12, color: p.inkMuted)),
              const SizedBox(width: 6),
              Text(formatBytes(report.of(kind)),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: p.ink)),
            ]),
          ),
      ],
    );
  }
}

class _LimitSlider extends ConsumerStatefulWidget {
  const _LimitSlider({required this.report});

  final CacheReport report;

  @override
  ConsumerState<_LimitSlider> createState() => _LimitSliderState();
}

class _LimitSliderState extends ConsumerState<_LimitSlider> {
  /// Where the thumb is while it is being held.
  ///
  /// Nothing is stored until it is let go. A limit is not a preference the
  /// app merely remembers: storing one saves every key, re-measures the whole
  /// disk and runs a real trim, so a drag from 10 GB to 256 MB would delete
  /// pictures four times over to fit budgets the reader was only passing
  /// through on the way somewhere else.
  double? _held;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final capacity = widget.report.capacity;
    // Read from settings rather than from the report: the report is
    // re-measured after a change and would show the old number for as long
    // as that took, which the reader would see as the thumb springing back.
    final limit = ref.watch(settingsProvider.select((s) => s.cacheLimit));
    final stops = limitStops(capacity);
    // The stored limit may not be one of the stops — the disk could have
    // changed size, or the value could predate this ladder — so the slider
    // sits on the nearest one rather than refusing to draw.
    var nearest = 0;
    for (var i = 0; i < stops.length; i++) {
      if ((stops[i] - limit).abs() < (stops[nearest] - limit).abs()) {
        nearest = i;
      }
    }
    final index = (_held?.round() ?? nearest).clamp(0, stops.length - 1);
    // A disk smaller than the smallest rung leaves one stop and nothing to
    // divide between; a Slider asserts on that rather than drawing.
    final movable = stops.length > 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('上限', style: TextStyle(fontSize: 12.5, color: p.inkMuted)),
        const SizedBox(width: 10),
        Text(formatBytes(stops[index]),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: p.ink)),
        const Spacer(),
        Text('这块盘共 ${formatBytes(capacity)}',
            style: TextStyle(fontSize: 11.5, color: p.inkFaint)),
      ]),
      Slider(
        value: index.toDouble(),
        min: 0,
        max: (stops.length - 1).toDouble(),
        divisions: movable ? stops.length - 1 : null,
        label: formatBytes(stops[index]),
        onChanged: movable ? (v) => setState(() => _held = v) : null,
        onChangeEnd: (v) {
          setState(() => _held = null);
          ref
              .read(settingsProvider.notifier)
              .patch((s) => s.copyWith(cacheLimit: stops[v.round()]));
        },
      ),
    ]);
  }
}

extension on CacheKind {
  /// One colour each, from the palette rather than invented, so the bar reads
  /// as part of the app in both themes.
  Color tone(Palette p) => switch (this) {
        CacheKind.images => p.accent,
        CacheKind.web => p.mint,
        CacheKind.readLog => p.cream,
      };
}
