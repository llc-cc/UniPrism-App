import 'package:flutter/material.dart';

import '../adapters/remote_exploration_dto.dart';
import '../core/teacher_agent_test_seed.dart';

const _brand = Color(0xFF6B23FF);

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
          : ListView(
              children: [
                // 验收引导卡只服务于显式开启的联调构建，避免在正式目录中挤出真实章节。
                if (TeacherAgentTestSeed.shouldAutoLoadChapter)
                  _TestFlowGuideCard(
                    chapterId: TeacherAgentTestSeed.chapterId,
                    onStart: () => onSelect(TeacherAgentTestSeed.chapterId),
                  ),
                ...chapters.indexed.map((entry) {
                  final chapter = entry.$2;
                  final isTestChapter =
                      chapter.chapterId == TeacherAgentTestSeed.chapterId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      elevation: isTestChapter ? 3 : 1,
                      shape: isTestChapter
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: _brand, width: 2),
                            )
                          : null,
                      child: ListTile(
                        key: ValueKey('chapter-catalog-${chapter.chapterId}'),
                        enabled: !busy,
                        title: Text(
                          chapter.title,
                          style: isTestChapter
                              ? const TextStyle(fontWeight: FontWeight.w800)
                              : null,
                        ),
                        subtitle: Text(chapter.description),
                        trailing: isTestChapter
                            ? const Chip(
                                label: Text(
                                  '验收测试',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                                backgroundColor: _brand,
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: busy ? null : () => onSelect(chapter.chapterId),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

final class _TestFlowGuideCard extends StatelessWidget {
  const _TestFlowGuideCard({required this.chapterId, required this.onStart});

  final String chapterId;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('test-flow-guide-card'),
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF0E8FF), Color(0xFFE8F4FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brand.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.science_outlined, color: _brand, size: 20),
              SizedBox(width: 8),
              Text(
                '全流程验收测试指引',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '点击「开始验收测试」进入北师大 1.1.1《集合的概念与表示》，完整走通以下功能：',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _flowStepList(),
          const SizedBox(height: 12),
          const Text(
            '测试数据（诊断回答）',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 6),
          _testDataBlock(),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey('test-flow-start-button'),
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('开始验收测试'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _flowStepList() {
    const steps = [
      '0. 进入章节 → AI 老师真实对话寒暄（多轮）',
      '1. 概念诊断（∈/∉ 与三大特性）',
      '2. 模式选择 → 互动素材（∈/∉ 判断）',
      '3. 素材完成 → 理解检查（无序性练习）',
      '4. 练习失败 → 额外辅导 EXTRA_SUPPORT',
      '5. 点击/等待继续 → 完成确定性补救练习 → G1 掌握',
      '6. G2 诊断 → 沿用或重新选择学习方式',
      '7. 完成当前列举法/描述法练习 → 本章 GOAL_COMPLETE',
      '8. 点击左侧历史节点 → 核对对话、素材、练习与返回当前进度',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: steps
          .map(
            (step) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                step,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _testDataBlock() {
    const entries = [
      ('G1 诊断回答', TeacherAgentTestSeed.g1DiagnosticAnswer),
      ('练习失败(G1)', '顺序不同就不是同一个集合 → 不是同一个集合'),
      ('补救练习通过(G1)', '“高个子”标准不明确，违反确定性 → 不能构成集合'),
      ('G2 诊断回答', TeacherAgentTestSeed.g2DiagnosticAnswer),
      ('列举法练习(G2)', '{1,2,3,4,5,6,7,8,9}'),
      ('描述法练习(G2)', '{x | 0<x<10, x∈N*}'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0D8EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF27222D),
                      height: 1.5,
                    ),
                    children: [
                      TextSpan(
                        text: '${entry.$1}：',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: entry.$2),
                    ],
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}
