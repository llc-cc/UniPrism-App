import '../core/practice_models.dart';
import '../core/practice_ports.dart';
import 'practice_api_client.dart';
import 'practice_dto_mapper.dart';

final class RemotePracticeRepository implements PracticeRepository {
  RemotePracticeRepository({
    required this.api,
    this.paperCode = 'cn-gaokao-2026-new-i-math-v1',
  });

  final PracticeApiClient api;
  final String paperCode;
  PracticeSessionSnapshot? _snapshot;

  @override
  PracticeConnectionMode get connectionMode => PracticeConnectionMode.remote;

  @override
  Future<PracticeSessionSnapshot> loadOrCreateSession() async {
    final data = await api.request(
      'POST',
      '/api/practice/sessions',
      body: {'paperCode': paperCode},
    );
    final participantToken = data['participantToken']?.toString();
    if (participantToken != null && participantToken.isNotEmpty) {
      await api.participantTokenStore.write(participantToken);
    }
    return _snapshot = mapSessionSnapshot(data['session']);
  }

  @override
  Future<PracticePaper> loadPaper() async =>
      (_snapshot ?? await loadOrCreateSession()).paper;

  @override
  Future<PracticeDraft> saveDraft({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required int currentQuestionNumber,
  }) async {
    final data = await api.request(
      'PUT',
      '/api/practice/sessions/$sessionId/drafts/${question.id}',
      body: {
        'answer': draft.answer,
        'reasoning': draft.reasoning,
        'draftVersion': draft.serverVersion,
        'currentQuestionNumber': currentQuestionNumber,
      },
    );
    return draft.copyWith(serverVersion: int.tryParse('${data['draftVersion']}') ?? draft.serverVersion);
  }

  @override
  Future<void> recordEvents({
    required String sessionId,
    required List<PracticeEvent> events,
  }) async {
    if (events.isEmpty) return;
    await api.request(
      'POST',
      '/api/practice/sessions/$sessionId/events',
      body: {
        'events': events.map((event) => {
          'clientEventId': event.clientEventId,
          'questionId': event.questionId,
          'eventType': _eventType(event.eventType),
          'payload': event.payload,
          'clientOccurredAt': event.clientOccurredAt.toIso8601String(),
        }).toList(growable: false),
      },
    );
  }

  @override
  Future<AttemptAssessment> submitAttempt({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  }) async {
    final key = 'attempt_${sessionId}_${question.id}_${draft.serverVersion}';
    final data = await api.request(
      'POST',
      '/api/practice/sessions/$sessionId/attempts',
      body: {
        'questionId': question.id,
        'draftVersion': draft.serverVersion,
      },
      idempotencyKey: key,
    );
    return mapStudentAttempt(data);
  }

  @override
  Future<void> completeSession(String sessionId) async {
    await api.request(
      'POST',
      '/api/practice/sessions/$sessionId/complete',
      body: const {},
    );
  }
}

String _eventType(PracticeEventType value) => switch (value) {
  PracticeEventType.questionViewed => 'QUESTION_VIEWED',
  PracticeEventType.answerStarted => 'ANSWER_STARTED',
  PracticeEventType.answerChanged => 'ANSWER_CHANGED',
  PracticeEventType.reasoningStarted => 'REASONING_STARTED',
  PracticeEventType.reasoningChanged => 'REASONING_CHANGED',
  PracticeEventType.hintRequested => 'HINT_REQUESTED',
  PracticeEventType.questionRevisited => 'QUESTION_REVISITED',
  PracticeEventType.attemptSubmitted => 'ATTEMPT_SUBMITTED',
};
