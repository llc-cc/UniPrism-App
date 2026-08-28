import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../application/speech_formula_controller.dart';
import '../core/spoken_formula.dart';

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
          child: _content(state),
        );
      },
    );
  }

  Widget _content(SpeechFormulaState state) {
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
      SpeechFormulaStatus.resolved => _ResolvedFormula(
        state: state,
        controller: controller,
        onInsert: onInsert,
      ),
      SpeechFormulaStatus.choosingCandidate => _CandidatePicker(
        state: state,
        controller: controller,
        onInsert: onInsert,
      ),
      SpeechFormulaStatus.clarifying => _ClarificationPrompt(
        resolution: state.resolution!,
        controller: controller,
      ),
      SpeechFormulaStatus.infrastructureError => _InfrastructureError(
        state: state,
        controller: controller,
      ),
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
}

/// 唯一结果仅负责预览；答案写入仍需用户点击确认按钮。
final class _ResolvedFormula extends StatelessWidget {
  const _ResolvedFormula({
    required this.state,
    required this.controller,
    required this.onInsert,
  });

  final SpeechFormulaState state;
  final SpeechFormulaController controller;
  final ValueChanged<String> onInsert;

  @override
  Widget build(BuildContext context) {
    final resolution = state.resolution!;
    final candidate = state.selectedCandidate!;
    return Column(
      key: const ValueKey('practice-formula-voice-resolved'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('识别内容：${resolution.recognizedText}'),
        const SizedBox(height: 10),
        _FormulaCandidateView(candidate: candidate),
        _ResolutionWarnings(warnings: resolution.warnings),
        const SizedBox(height: 10),
        _ResultActions(
          controller: controller,
          canInsert: true,
          onInsert: onInsert,
        ),
      ],
    );
  }
}

/// 多候选结果展示完整公式和反向朗读，并等待一次显式选择。
final class _CandidatePicker extends StatelessWidget {
  const _CandidatePicker({
    required this.state,
    required this.controller,
    required this.onInsert,
  });

  final SpeechFormulaState state;
  final SpeechFormulaController controller;
  final ValueChanged<String> onInsert;

  @override
  Widget build(BuildContext context) {
    final resolution = state.resolution!;
    return Column(
      key: const ValueKey('practice-formula-voice-candidates'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('识别内容：${resolution.recognizedText}'),
        const SizedBox(height: 10),
        const Text('请选择符合原意的公式：'),
        const SizedBox(height: 8),
        for (final candidate in resolution.candidates) ...[
          _SelectableFormulaCandidate(
            candidate: candidate,
            isSelected: state.selectedCandidateId == candidate.id,
            onSelected: () => controller.selectCandidate(candidate.id),
          ),
          const SizedBox(height: 8),
        ],
        _ResolutionWarnings(warnings: resolution.warnings),
        const SizedBox(height: 2),
        _ResultActions(
          controller: controller,
          canInsert: state.selectedCandidate != null,
          onInsert: onInsert,
        ),
      ],
    );
  }
}

/// 语义澄清是可继续操作的成功态，使用中性紫色而不是错误色。
final class _ClarificationPrompt extends StatelessWidget {
  const _ClarificationPrompt({
    required this.resolution,
    required this.controller,
  });

  final SpokenFormulaResolution resolution;
  final SpeechFormulaController controller;

  @override
  Widget build(BuildContext context) {
    final clarification = resolution.clarification!;
    return Container(
      key: const ValueKey('practice-formula-voice-clarification'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2ECFF),
        border: Border.all(color: const Color(0xFFB8A1E8)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clarification.question,
            style: const TextStyle(
              color: Color(0xFF4F2D7F),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '需要确认：${clarification.focusText}',
            style: const TextStyle(color: Color(0xFF655A73)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (controller.canContinueRecording)
                OutlinedButton.icon(
                  key: const ValueKey(
                    'practice-formula-voice-continue-recording',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF5E35A8),
                    side: const BorderSide(color: Color(0xFF9B7BD1)),
                  ),
                  onPressed: () {
                    unawaited(controller.continueRecording());
                  },
                  icon: const Icon(Icons.mic_none_rounded),
                  label: const Text('继续补充语音'),
                ),
              for (final option in clarification.options)
                OutlinedButton(
                  key: ValueKey<String>(
                    'practice-formula-voice-clarification-${option.id}',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF5E35A8),
                    side: const BorderSide(color: Color(0xFF9B7BD1)),
                  ),
                  onPressed: () {
                    unawaited(controller.answerClarification(option));
                  },
                  child: Text(option.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 基础设施错误保留安全错误文案和已识别文本，供用户重试或改用键盘。
final class _InfrastructureError extends StatelessWidget {
  const _InfrastructureError({required this.state, required this.controller});

  final SpeechFormulaState state;
  final SpeechFormulaController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('practice-formula-voice-infrastructure-error'),
      width: double.infinity,
      child: Column(
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
              if (controller.canContinueRecording)
                OutlinedButton.icon(
                  key: const ValueKey(
                    'practice-formula-voice-continue-recording',
                  ),
                  onPressed: () {
                    unawaited(controller.continueRecording());
                  },
                  icon: const Icon(Icons.mic_none_rounded),
                  label: const Text('继续补充语音'),
                ),
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
      ),
    );
  }
}

/// 解析或识别阶段的紧凑进度提示，允许文案在窄屏换行。
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

final class _SelectableFormulaCandidate extends StatelessWidget {
  const _SelectableFormulaCandidate({
    required this.candidate,
    required this.isSelected,
    required this.onSelected,
  });

  final SpokenFormulaCandidate candidate;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>(
          'practice-formula-voice-candidate-${candidate.id}',
        ),
        borderRadius: BorderRadius.circular(10),
        onTap: onSelected,
        child: _FormulaCandidateView(
          candidate: candidate,
          isSelected: isSelected,
        ),
      ),
    );
  }
}

final class _FormulaCandidateView extends StatelessWidget {
  const _FormulaCandidateView({required this.candidate, this.isSelected});

  final SpokenFormulaCandidate candidate;
  final bool? isSelected;

  @override
  Widget build(BuildContext context) {
    final selected = isSelected;
    return Semantics(
      selected: selected,
      button: selected == null ? null : true,
      label: selected == null ? '公式预览' : '选择公式：${candidate.spokenBack}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected == true ? const Color(0xFFEDE4FF) : Colors.white,
          border: Border.all(
            color: selected == true
                ? const Color(0xFF7A4CC2)
                : const Color(0xFFDDD5E8),
            width: selected == true ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  candidate.latex,
                  textStyle: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '反向朗读：${candidate.spokenBack}',
              key: ValueKey<String>(
                'practice-formula-voice-spoken-back-${candidate.id}',
              ),
              style: const TextStyle(color: Color(0xFF5F5968), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ResolutionWarnings extends StatelessWidget {
  const _ResolutionWarnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final warning in warnings)
            Text(warning, style: const TextStyle(color: Color(0xFF6C5585))),
        ],
      ),
    );
  }
}

final class _ResultActions extends StatelessWidget {
  const _ResultActions({
    required this.controller,
    required this.canInsert,
    required this.onInsert,
  });

  final SpeechFormulaController controller;
  final bool canInsert;
  final ValueChanged<String> onInsert;

  void _retry() {
    // controller 用一个新 operation 完成取消与重录，UI 不串联两个可被打断的异步动作。
    unawaited(controller.startListening());
  }

  void _insertSelectedCandidate() {
    // 点击时只读取 controller 当前选中态；confirm 会同步 reset 并失效迟到回调。
    final candidate = controller.state.selectedCandidate;
    if (candidate == null) return;
    if (controller.confirmSelectedCandidate() == null) return;
    onInsert(candidate.latex);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
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
          onPressed: _retry,
          child: const Text('重新说'),
        ),
        FilledButton.icon(
          key: const ValueKey('practice-formula-voice-insert'),
          onPressed: canInsert ? _insertSelectedCandidate : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('插入公式'),
        ),
      ],
    );
  }
}
