import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../application/speech_formula_controller.dart';

/// 公式键盘上方的语音输入面板；确认前只展示候选，不触碰学生答案。
final class PracticeFormulaVoicePanel extends StatelessWidget {
  const PracticeFormulaVoicePanel({
    super.key,
    required this.controller,
    required this.onInsert,
  });

  final SpeechFormulaController controller;
  final ValueChanged<String> onInsert;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Container(
          key: const ValueKey('practice-formula-voice-panel'),
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F3FF),
            border: Border.all(color: const Color(0xFFD9CCFA)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _content(context, state),
        );
      },
    );
  }

  Widget _content(BuildContext context, SpeechFormulaState state) {
    return switch (state.status) {
      SpeechFormulaStatus.idle => Wrap(
        alignment: WrapAlignment.start,
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('practice-formula-voice-start'),
            onPressed: controller.startListening,
            icon: const Icon(Icons.mic_none_rounded),
            label: const Text('语音输入公式'),
          ),
          Text(
            '识别方式：${controller.sourceLabel}',
            style: const TextStyle(color: Color(0xFF6D6875), fontSize: 12),
          ),
        ],
      ),
      SpeechFormulaStatus.requestingPermission => const _ProgressMessage(
        message: '正在请求麦克风权限…',
      ),
      SpeechFormulaStatus.listening => _listening(state),
      SpeechFormulaStatus.transcribing => const _ProgressMessage(
        message: '正在识别语音…',
      ),
      SpeechFormulaStatus.resolving => const _ProgressMessage(
        message: '正在转换为数学公式…',
      ),
      SpeechFormulaStatus.resolved ||
      SpeechFormulaStatus.choosingCandidate => _preview(context, state),
      SpeechFormulaStatus.clarifying => Text(
        state.resolution!.clarification!.question,
      ),
      SpeechFormulaStatus.infrastructureError => _error(state),
    };
  }

  Widget _listening(SpeechFormulaState state) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.graphic_eq_rounded, color: Color(0xFFD32F2F)),
        Text(
          state.transcript.isEmpty ? '正在听，请说一个短公式…' : state.transcript,
          key: const ValueKey('practice-formula-voice-transcript'),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey('practice-formula-voice-stop'),
          onPressed: controller.stopListening,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('停止'),
        ),
        TextButton(
          key: const ValueKey('practice-formula-voice-cancel'),
          onPressed: controller.reset,
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _preview(BuildContext context, SpeechFormulaState state) {
    final resolution = state.resolution!;
    final candidates = resolution.candidates;
    final selected = state.selectedCandidate;
    final displayedCandidate = selected ?? candidates.first;
    return Column(
      key: const ValueKey('practice-formula-voice-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('识别内容：${resolution.recognizedText}'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                displayedCandidate.latex,
                textStyle: const TextStyle(fontSize: 24),
              ),
            ),
          ),
        ),
        if (candidates.length > 1) ...[
          const SizedBox(height: 10),
          const Text('请选择符合原意的公式：'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (var index = 0; index < candidates.length; index++)
                ChoiceChip(
                  key: ValueKey('practice-formula-voice-alternative-$index'),
                  selected: state.selectedCandidateId == candidates[index].id,
                  label: Math.tex(candidates[index].latex),
                  onSelected: (_) =>
                      controller.selectCandidate(candidates[index].id),
                ),
            ],
          ),
        ],
        for (final warning in resolution.warnings) ...[
          const SizedBox(height: 8),
          Text(
            warning,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              key: const ValueKey('practice-formula-voice-cancel'),
              onPressed: controller.reset,
              child: const Text('取消'),
            ),
            OutlinedButton(
              key: const ValueKey('practice-formula-voice-retry'),
              onPressed: () async {
                await controller.reset();
                await controller.startListening();
              },
              child: const Text('重新说'),
            ),
            FilledButton.icon(
              key: const ValueKey('practice-formula-voice-insert'),
              onPressed: selected == null
                  ? null
                  : () {
                      final latex = controller.confirmSelectedCandidate();
                      if (latex != null) onInsert(latex);
                    },
              icon: const Icon(Icons.add_rounded),
              label: const Text('插入公式'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _error(SpeechFormulaState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.transcript.isNotEmpty) ...[
          Text(
            '识别内容：${state.transcript}',
            key: const ValueKey('practice-formula-voice-error-transcript'),
            style: const TextStyle(color: Color(0xFF5F5968)),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          state.errorMessage ?? '语音输入失败，请重试。',
          style: const TextStyle(color: Color(0xFF9A3412)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('practice-formula-voice-retry'),
              onPressed: state.transcript.isEmpty
                  ? controller.startListening
                  : controller.retryResolution,
              child: const Text('重试'),
            ),
            TextButton(
              key: const ValueKey('practice-formula-voice-cancel'),
              onPressed: controller.reset,
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    );
  }
}

final class _ProgressMessage extends StatelessWidget {
  const _ProgressMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Flexible(child: Text(message)),
      ],
    );
  }
}
