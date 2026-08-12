import 'package:flutter/material.dart';

import 'technical_trace.dart';

/// 面向演示与联调的技术轨迹抽屉；学生主流程默认隐藏这些工程信息。
final class TechnicalTraceDrawer extends StatelessWidget {
  const TechnicalTraceDrawer({super.key, required this.trace});

  final TechnicalTraceSnapshot trace;

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    return Drawer(
      key: const ValueKey('technical-trace-drawer'),
      width: viewportWidth < 480 ? viewportWidth * 0.94 : 420,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(sessionId: trace.sessionId),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (trace.isMock) const _MockBanner(),
                  const SizedBox(height: 16),
                  if (!trace.hasGuidedDecision)
                    const _OpenExplorationEmptyState()
                  else ...[
                    _TraceSection(
                      key: const ValueKey('technical-trace-context'),
                      icon: Icons.account_tree_outlined,
                      title: '会话与教学上下文',
                      children: [
                        _TraceField(label: 'Session', value: trace.sessionId),
                        _TraceField(
                          label: '当前会话节点',
                          value: trace.currentNodeId,
                        ),
                        _TraceField(
                          label: 'Lesson plan',
                          value: trace.lessonPlanId,
                        ),
                        _TraceField(
                          label: 'Knowledge atom',
                          value: trace.atomId,
                        ),
                        _TraceField(label: '当前阶段', value: trace.stageLabel),
                        _TraceField(label: '教学目标', value: trace.goal),
                      ],
                    ),
                    _TraceSection(
                      key: const ValueKey('technical-trace-evidence'),
                      icon: Icons.fact_check_outlined,
                      title: '可观察证据',
                      children: [
                        if (trace.latestEvidence case final evidence?) ...[
                          _TraceField(label: '最新证据', value: evidence.code),
                          _TraceField(
                            label: '强度 / 来源',
                            value:
                                '${evidence.strengthLabel} · ${evidence.sourceType}',
                          ),
                          _TraceField(
                            label: '记录时间',
                            value: evidence.recordedAt,
                          ),
                        ] else
                          const _TraceField(label: '最新证据', value: '尚未记录'),
                        _TraceField(
                          label: '仍需收集',
                          value: trace.missingEvidenceCodes.isEmpty
                              ? '无'
                              : trace.missingEvidenceCodes.join('\n'),
                        ),
                      ],
                    ),
                    _TraceSection(
                      key: const ValueKey('technical-trace-action'),
                      icon: Icons.psychology_alt_outlined,
                      title: 'Teacher Agent 动作',
                      children: [
                        _TraceField(
                          label: '对学生的动作',
                          value: trace.teacherAction,
                        ),
                        _TraceField(
                          label: '教学意图',
                          value: trace.pedagogicalIntent,
                        ),
                        _TraceField(label: '决策原因码', value: trace.reasonCode),
                      ],
                    ),
                    _TraceSection(
                      key: const ValueKey('technical-trace-mcp'),
                      icon: Icons.extension_outlined,
                      title: '素材选择（模拟）',
                      badge: 'Mock',
                      children: [
                        if (trace.mcpSelection.selectedMaterialId.isEmpty)
                          const _TraceField(label: '调用状态', value: '当前教学动作未调用素材')
                        else ...[
                          _TraceField(
                            label: 'MCP Tool',
                            value: trace.mcpSelection.toolName,
                          ),
                          _TraceField(
                            label: '请求摘要',
                            value: trace.mcpSelection.requestSummary,
                          ),
                          _TraceField(
                            label: '候选数量',
                            value: '${trace.mcpSelection.candidateCount}',
                          ),
                          _TraceField(
                            label: '过滤原因',
                            value: trace.mcpSelection.filteredReasons.join(
                              '\n',
                            ),
                          ),
                          _TraceField(
                            label: '选中素材',
                            value: trace.mcpSelection.selectedMaterialId,
                          ),
                          _TraceField(
                            label: '素材版本',
                            value: trace.mcpSelection.selectedVersion,
                          ),
                        ],
                      ],
                    ),
                    _TraceSection(
                      key: const ValueKey('technical-trace-timing'),
                      icon: Icons.timer_outlined,
                      title: '执行耗时（模拟）',
                      badge: 'Mock',
                      children: [
                        _TraceField(
                          label: 'Agent',
                          value: '${trace.timing.agentMs} ms',
                        ),
                        _TraceField(
                          label: 'MCP',
                          value: '${trace.timing.mcpMs} ms',
                        ),
                        _TraceField(
                          label: '校验',
                          value: '${trace.timing.validationMs} ms',
                        ),
                        _TraceField(
                          label: '总耗时',
                          value: '${trace.timing.totalMs} ms',
                        ),
                        _TraceField(
                          label: '故障回退',
                          value: trace.fallbackUsed
                              ? trace.fallbackReason
                              : '未触发',
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '这里只展示输入、动作、工具结果和证据等可审计事实，不展示模型内部思维过程。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            Icons.schema_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('技术轨迹', style: Theme.of(context).textTheme.titleLarge),
                Text(
                  sessionId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('close-technical-trace'),
            tooltip: '关闭技术轨迹',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

final class _MockBanner extends StatelessWidget {
  const _MockBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('technical-trace-mock-banner'),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, color: colors.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mock 演示数据',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'MCP 候选、素材版本与耗时为模拟数据；教学动作和证据来自当前会话快照。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OpenExplorationEmptyState extends StatelessWidget {
  const _OpenExplorationEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(
            Icons.explore_outlined,
            size: 42,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 14),
          Text(
            '当前为开放探索，暂无引导式技术轨迹',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

final class _TraceSection extends StatelessWidget {
  const _TraceSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.badge,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 19, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (badge case final value?)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.tertiaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

final class _TraceField extends StatelessWidget {
  const _TraceField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value.isEmpty ? '—' : value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}
