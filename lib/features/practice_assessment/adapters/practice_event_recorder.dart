import 'dart:async';

import '../core/practice_models.dart';

typedef PracticeEventBatchSender =
    Future<void> Function(List<PracticeEvent> events);

/// 高频修改事件只记录长度档，不持有每次按键文本；失败批次原样留在队首供重试。
final class PracticeEventRecorder {
  factory PracticeEventRecorder({
    required PracticeEventBatchSender sendBatch,
    Duration flushInterval = const Duration(seconds: 5),
    bool scheduleFlush = true,
  }) => PracticeEventRecorder._(sendBatch, flushInterval, scheduleFlush);

  PracticeEventRecorder._(
    this._sendBatch,
    this.flushInterval,
    this._scheduleFlush,
  );

  final PracticeEventBatchSender _sendBatch;
  final Duration flushInterval;
  final bool _scheduleFlush;
  final List<PracticeEvent> _pending = [];
  Timer? _timer;
  Future<void>? _activeFlush;
  int _sequence = 0;

  List<PracticeEvent> get pending => List.unmodifiable(_pending);

  void record({
    required String questionId,
    required PracticeEventType eventType,
    Map<String, Object?> payload = const {},
  }) {
    final now = DateTime.now().toUtc();
    _pending.add(
      PracticeEvent(
        clientEventId:
            'evt_${now.microsecondsSinceEpoch}_${_sequence++}_${questionId.hashCode.abs()}',
        questionId: questionId,
        eventType: eventType,
        payload: payload,
        clientOccurredAt: now,
      ),
    );
    if (_scheduleFlush) {
      _timer ??= Timer(flushInterval, () {
        _timer = null;
        unawaited(flush().catchError((Object _) {}));
      });
    }
  }

  Future<void> flush() {
    final running = _activeFlush;
    if (running != null) return running;
    final operation = _flushPending();
    _activeFlush = operation;
    return operation.whenComplete(() => _activeFlush = null);
  }

  Future<void> _flushPending() async {
    _timer?.cancel();
    _timer = null;
    while (_pending.isNotEmpty) {
      final batch = List<PracticeEvent>.of(_pending.take(50));
      await _sendBatch(batch);
      _pending.removeRange(0, batch.length);
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
