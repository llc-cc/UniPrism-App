# SenseVoice local runtime

```powershell
pwsh -NoProfile -File tool/sensevoice/setup.ps1
pwsh -NoProfile -File tool/sensevoice/start.ps1
pwsh -NoProfile -File tool/sensevoice/benchmark.ps1
```

Weights, caches, audio, and generated results are kept outside Git under
`D:\dev\local-ai\sensevoice`.

## Latency diagnostics

`POST /v1/audio/transcriptions` returns a standard `Server-Timing` header with
`read`, `prepare`, `queue`, `inference`, and `total` durations in milliseconds.
The server log records only these durations plus original/trimmed audio length;
it never records audio, filenames, or transcripts.

For decodable audio, the adapter trims only leading and trailing low-energy
audio before inference. It keeps a small boundary padding, retains quieter
speech after a louder phrase, and uses a fixed very-low amplitude floor rather
than a speech-derived percentile. Thus background noise can reduce trimming,
but valid quiet speech cannot raise its own silence threshold and be dropped.
Unsupported formats preserve the original upload, so this optimization does
not silently truncate spoken content. The CPU inference worker is serial and
keeps only the latest pending request: a client-disconnected retry waiting in
the queue is cancelled before it reaches the model and receives JSON `409`
with `error.code=request_replaced`.
`verbose_json` continues to report the original upload duration and offsets
trimmed segment timestamps back to the original audio timeline.

FunASR's synchronous CPU `model.generate` cannot be safely interrupted after
it has started on Windows. The running request therefore still completes in
the worker, but obsolete queued work cannot extend the next retry's wait.
Service shutdown blocks the model-start gate, then waits for that running
worker to finish before returning. The
adapter does not raise process priority by default; `High` and `Realtime` can
starve development tools and should not be set implicitly.
