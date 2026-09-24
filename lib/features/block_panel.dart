import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme.dart';
import '../core/block_list.dart';
import '../core/models.dart';
import '../widgets/chrome.dart';
import 'providers.dart';

/// Everything the reader has blocked, where it can be looked over and taken
/// back — and where a word is added, since a word has no card to right-click.
class BlockPanel extends ConsumerStatefulWidget {
  const BlockPanel({super.key});

  @override
  ConsumerState<BlockPanel> createState() => _BlockPanelState();
}

class _BlockPanelState extends ConsumerState<BlockPanel> {
  final _word = TextEditingController();

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  void _patch(BlockList Function(BlockList) f) => ref
      .read(settingsProvider.notifier)
      .patch((s) => s.copyWith(blocks: f(s.blocks)));

  void _addWord() {
    final word = _word.text.trim();
    if (word.isEmpty) return;
    _patch((b) => b.withKeyword(word));
    _word.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final blocks = ref.watch(settingsProvider.select((s) => s.blocks));
    final small = Theme.of(context).textTheme.bodySmall;

    List<Widget> perSite(Set<String> entries,
        BlockList Function(BlockList, SiteId, String) remove) {
      final parsed = [
        for (final e in entries) ?BlockList.parse(e),
      ]..sort((a, b) => a.$1.index != b.$1.index
          ? a.$1.index - b.$1.index
          : a.$2.compareTo(b.$2));
      return [
        for (final (site, name) in parsed)
          InputChip(
            label: Text('${site.label} · $name'),
            onDeleted: () => _patch((b) => remove(b, site, name)),
            deleteButtonTooltipMessage: '不再屏蔽',
          ),
      ];
    }

    Widget group(String title, List<Widget> chips, String empty) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: p.inkMuted)),
            const SizedBox(height: 8),
            if (chips.isEmpty)
              Text(empty, style: small)
            else
              Wrap(spacing: 6, runSpacing: 6, children: chips),
          ]),
        );

    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('屏蔽', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('屏蔽的帖子不会出现在任何列表里。节点和作者在帖子卡片上右键屏蔽；关键词在这里添加，对所有站点的标题生效。',
            style: small),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _word,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: '标题里含有这个词就屏蔽'),
              onSubmitted: (_) => _addWord(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: kControlHeight,
            child: FilledButton(onPressed: _addWord, child: const Text('添加')),
          ),
        ]),
        group(
          '关键词',
          [
            for (final word in blocks.keywords.toList()..sort())
              InputChip(
                label: Text(word),
                onDeleted: () =>
                    _patch((b) => b.withKeyword(word, blocked: false)),
                deleteButtonTooltipMessage: '不再屏蔽',
              ),
          ],
          '还没有屏蔽任何关键词',
        ),
        group(
          '节点',
          perSite(blocks.sections,
              (b, site, name) => b.withSection(site, name, blocked: false)),
          '还没有屏蔽任何节点',
        ),
        group(
          '作者',
          perSite(blocks.authors,
              (b, site, name) => b.withAuthor(site, name, blocked: false)),
          '还没有屏蔽任何作者',
        ),
      ]),
    );
  }
}
