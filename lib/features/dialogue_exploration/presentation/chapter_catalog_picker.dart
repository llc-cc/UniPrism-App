import 'package:flutter/material.dart';

import '../adapters/remote_exploration_dto.dart';

/// 展示服务端已审核章节目录；客户端不补造课程事实，也不自动选择首个章节。
final class ChapterCatalogPicker extends StatelessWidget {
  const ChapterCatalogPicker({
    super.key,
    required this.chapters,
    required this.busy,
    required this.onSelect,
  });

  final List<LearningChapterCatalogItem> chapters;
  final bool busy;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chapter-catalog-picker'),
      padding: const EdgeInsets.all(24),
      child: busy && chapters.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : chapters.isEmpty
          ? const Center(child: Text('当前暂无已审核的预习章节'))
          : ListView.separated(
              itemCount: chapters.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                return Card(
                  child: ListTile(
                    key: ValueKey('chapter-catalog-${chapter.chapterId}'),
                    enabled: !busy,
                    title: Text(chapter.title),
                    subtitle: Text(chapter.description),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: busy ? null : () => onSelect(chapter.chapterId),
                  ),
                );
              },
            ),
    );
  }
}
