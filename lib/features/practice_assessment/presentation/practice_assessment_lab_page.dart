import 'package:flutter/material.dart';

import '../adapters/mock_gaokao_math_repository.dart';
import '../application/practice_session_controller.dart';
import '../core/practice_models.dart';

/// 独立练习评分实验室；只展示单次作答事实和证据，不推导长期掌握度。
final class PracticeAssessmentLabPage extends StatefulWidget {
  const PracticeAssessmentLabPage({
    super.key,
    required this.controller,
    this.disposeController = false,
  });

  /// 创建供开发者工具使用的自造题内存版本。
  factory PracticeAssessmentLabPage.mock({Key? key}) {
    return PracticeAssessmentLabPage(
      key: key,
      controller: PracticeSessionController(
        repository: MockGaokaoMathRepository(),
      ),
      disposeController: true,
    );
  }

  final PracticeSessionController controller;
  final bool disposeController;

  @override
  State<PracticeAssessmentLabPage> createState() =>
      _PracticeAssessmentLabPageState();
}

final class _PracticeAssessmentLabPageState
    extends State<PracticeAssessmentLabPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.controller.state.status == PracticeSessionStatus.idle) {
        widget.controller.load();
      }
    });
  }

  @override
  void didUpdateWidget(covariant PracticeAssessmentLabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    if (widget.disposeController) widget.controller.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6FA),
      appBar: AppBar(
        title: const Text('练习评分实验室'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: switch ((state.paper, state.status)) {
        (null, PracticeSessionStatus.failure) => _LoadFailure(
          message: state.errorMessage ?? '试卷加载失败',
          onRetry: widget.controller.load,
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final paper?, _) => _paperBody(paper, state),
      },
    );
  }

  Widget _paperBody(PracticePaper paper, PracticeSessionState state) {
    final question = state.currentQuestion!;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PaperHeader(paper: paper, completed: state.completedCount),
                  const SizedBox(height: 12),
                  _QuestionNavigator(
                    paper: paper,
                    currentIndex: state.currentIndex,
                    completedIds: state.results.keys.toSet(),
                    onSelect: widget.controller.selectQuestion,
                  ),
                  const SizedBox(height: 12),
                  _QuestionCard(
                    question: question,
                    draft: state.currentDraft,
                    isSubmitting:
                        state.status == PracticeSessionStatus.submitting,
                    onOption: widget.controller.toggleOption,
                    onAnswer: widget.controller.updateAnswer,
                    onReasoning: widget.controller.updateReasoning,
                  ),
                  if (state.status == PracticeSessionStatus.failure) ...[
                    const SizedBox(height: 12),
                    _SubmissionFailure(
                      message: state.errorMessage ?? '提交失败',
                      onRetry: widget.controller.retrySubmission,
                    ),
                  ],
                  if (state.resultForCurrent case final result?) ...[
                    const SizedBox(height: 12),
                    _AssessmentCard(assessment: result),
                  ],
                  const SizedBox(height: 16),
                  _ActionBar(
                    currentIndex: state.currentIndex,
                    questionCount: paper.questions.length,
                    isSubmitting:
                        state.status == PracticeSessionStatus.submitting,
                    onPrevious: widget.controller.previousQuestion,
                    onNext: widget.controller.nextQuestion,
                    onSubmit: widget.controller.submitCurrent,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _PaperHeader extends StatelessWidget {
  const _PaperHeader({required this.paper, required this.completed});

  final PracticePaper paper;
  final int completed;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              paper.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('已提交 $completed / ${paper.questions.length}'),
            if (!paper.isAuthorizedOfficialContent) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('practice-paper-disclaimer'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5DC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  paper.subtitle,
                  style: const TextStyle(color: Color(0xFF6D5317), height: 1.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _QuestionNavigator extends StatelessWidget {
  const _QuestionNavigator({
    required this.paper,
    required this.currentIndex,
    required this.completedIds,
    required this.onSelect,
  });

  final PracticePaper paper;
  final int currentIndex;
  final Set<String> completedIds;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            for (var index = 0; index < paper.questions.length; index++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: ValueKey('practice-question-${index + 1}'),
                  selected: currentIndex == index,
                  avatar: completedIds.contains(paper.questions[index].id)
                      ? const Icon(Icons.check_rounded, size: 16)
                      : null,
                  label: Text('${index + 1}'),
                  onSelected: (_) => onSelect(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.draft,
    required this.isSubmitting,
    required this.onOption,
    required this.onAnswer,
    required this.onReasoning,
  });

  final PracticeQuestion question;
  final PracticeDraft draft;
  final bool isSubmitting;
  final ValueChanged<String> onOption;
  final ValueChanged<String> onAnswer;
  final ValueChanged<String> onReasoning;

  @override
  Widget build(BuildContext context) {
    final isChoice =
        question.type == PracticeQuestionType.singleChoice ||
        question.type == PracticeQuestionType.multipleChoice;
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '第 ${question.number} 题 · ${_questionTypeLabel(question.type)}',
              style: const TextStyle(
                color: Color(0xFF6B23FF),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              question.prompt,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                height: 1.55,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            if (isChoice)
              for (final entry in question.options.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CheckboxListTile(
                    key: ValueKey('practice-option-${entry.key}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: draft.answer.contains(entry.key),
                    title: Text('${entry.key}. ${entry.value}'),
                    onChanged: isSubmitting ? null : (_) => onOption(entry.key),
                  ),
                )
            else
              KeyedSubtree(
                key: const ValueKey('practice-answer-input'),
                child: TextFormField(
                  key: ValueKey('practice-answer-field-${question.id}'),
                  initialValue: draft.answer,
                  enabled: !isSubmitting,
                  minLines: question.type == PracticeQuestionType.solution
                      ? 2
                      : 1,
                  maxLines: question.type == PracticeQuestionType.solution
                      ? 5
                      : 2,
                  decoration: InputDecoration(
                    labelText: question.type == PracticeQuestionType.solution
                        ? '最终结论或当前答案'
                        : '填写答案',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: onAnswer,
                ),
              ),
            const SizedBox(height: 14),
            KeyedSubtree(
              key: const ValueKey('practice-reasoning-input'),
              child: TextFormField(
                key: ValueKey('practice-reasoning-field-${question.id}'),
                initialValue: draft.reasoning,
                enabled: !isSubmitting,
                minLines: 2,
                maxLines: 7,
                decoration: const InputDecoration(
                  labelText: '解题依据（客观题可选）',
                  helperText: '填写关键步骤有助于区分理解、计算与技巧证据。',
                  border: OutlineInputBorder(),
                ),
                onChanged: onReasoning,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.assessment});

  final AttemptAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final observed = assessment.observations.values
        .where((item) => item.status == AbilityEvidenceStatus.observed)
        .toList();
    final hasMissing = assessment.observations.values.any(
      (item) => item.status == AbilityEvidenceStatus.insufficientEvidence,
    );
    return Card(
      elevation: 0,
      color: const Color(0xFFF1ECFF),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _outcomeLabel(assessment.outcome),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(assessment.feedback),
            if (observed.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '本次已观察证据',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in observed)
                    Chip(
                      label: Text(
                        '${_abilityLabel(item.dimension)} · ${item.band}档',
                      ),
                    ),
                ],
              ),
            ],
            if (hasMissing) ...[
              const SizedBox(height: 12),
              const Text(
                '过程证据不足',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text('这些维度暂不评分，不会被当作能力较低。'),
            ],
          ],
        ),
      ),
    );
  }
}

final class _SubmissionFailure extends StatelessWidget {
  const _SubmissionFailure({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFFFEDEA),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFB42318)),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            TextButton(
              key: const ValueKey('practice-retry'),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.currentIndex,
    required this.questionCount,
    required this.isSubmitting,
    required this.onPrevious,
    required this.onNext,
    required this.onSubmit,
  });

  final int currentIndex;
  final int questionCount;
  final bool isSubmitting;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton(
          onPressed: currentIndex == 0 || isSubmitting ? null : onPrevious,
          child: const Text('上一题'),
        ),
        const Spacer(),
        FilledButton.icon(
          key: const ValueKey('practice-submit'),
          onPressed: isSubmitting ? null : onSubmit,
          icon: isSubmitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fact_check_outlined),
          label: Text(isSubmitting ? '判定中' : '提交本题'),
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: currentIndex >= questionCount - 1 || isSubmitting
              ? null
              : onNext,
          child: const Text('下一题'),
        ),
      ],
    );
  }
}

final class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}

String _questionTypeLabel(PracticeQuestionType type) => switch (type) {
  PracticeQuestionType.singleChoice => '单项选择',
  PracticeQuestionType.multipleChoice => '多项选择',
  PracticeQuestionType.fillBlank => '填空',
  PracticeQuestionType.solution => '解答',
};

String _outcomeLabel(AttemptOutcome outcome) => switch (outcome) {
  AttemptOutcome.correct => '答案正确',
  AttemptOutcome.partiallyCorrect => '部分步骤有效',
  AttemptOutcome.incorrect => '需要修正',
};

String _abilityLabel(AbilityDimension dimension) => switch (dimension) {
  AbilityDimension.reading => '阅读',
  AbilityDimension.understanding => '理解',
  AbilityDimension.calculation => '计算',
  AbilityDimension.reasoning => '推理',
  AbilityDimension.technique => '技巧',
  AbilityDimension.selfCorrection => '自我纠错',
  AbilityDimension.expression => '表达',
};
