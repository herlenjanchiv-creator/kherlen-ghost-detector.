# Ghost Lens — preferred dashboard + real magnetic measurement

Primary route: original user-selected dark/cyan dashboard. AR simulation is `ar.html`; `lab.html` remains compatible with the primary dashboard. Device-local histories retain their original database names.

Magnetic measurement: capability-detected Generic Sensor Magnetometer (20Hz requested; not guaranteed), actual X/Y/Z µT and Euclidean magnitude. No synthetic fallback in live mode. Stale readings after 1.5s display null. User-requested 3s median baseline requires >=20 valid samples, absolute delta and adjustable 5–100µT threshold with 80% hysteresis rearm. CSV includes axes, baseline, delta and source. Magnetic line displayed with fixed 0–150µT chart scale. Baseline measurement is relative reference setting, not laboratory calibration. Browser permissions/hardware can prevent access; Safari does not expose Magnetometer. Real iPhone live measurement requires a native Core Motion app or identified external hardware. No RF/AC frequency or spirit detection inferred.

Camera: persistent error explanation, HTTPS guard and constraint fallback. AR camera diagnostics preserve tested cancellation/cleanup.

Tests: node test.mjs; node test-camera.mjs; node test-ar.mjs; node --check dist/app.mjs. These validate code with synthetic fixtures and mocked APIs. Physical iPhone/magnetometer/browser QA remains outstanding.

Claude Flutter source is preserved unchanged in claude-flutter; not built/validated as native. Asset provenance claims are supplied by Claude, not independently verified.

## Audio meaning + latest Claude update
Main dashboard has browser speech recognition (explicit opt-in, selectable mn-MN/en-US/ru-RU; support varies; service may upload audio) and device-local waveform event descriptors. Acoustic labels are rule-based and tentative, with no fabricated confidence percentage. No trained sound-event model or spirit interpretation. Speech confidence is only the optional browser-provided score, not validated probability. Final transcripts/event descriptions are included in session journal/CSV via flags. UI sound history is ephemeral unless a session is active.

Latest supplied Claude source adds native iOS/Android magnetometer channels, sigma baseline and magnetic source metadata. These replace the earlier claude-flutter source unchanged. AR web magnetic improvements are merged with existing camera diagnostics and explicit simulation labels. Native builds, iPhone hardware and end-to-end speech-service QA remain outstanding.

## v5 local automatic multilingual transcription
Explicit model-download button initializes a dedicated Worker with pinned Transformers.js 3.0.0, Xenova/whisper-tiny multilingual q8 and single-thread WASM. Downloads runtime/model assets from jsDelivr/Hugging Face; microphone audio stays in the browser for this local mode. Records up to 15 seconds, decodes/downmixes/resamples to 16kHz, invokes task=transcribe with language=null for automatic source-language inference. Text is not translated. No language-name label or calibrated confidence returned. Tiny is lightweight and can be poor for Mongolian, mixed languages and noise; check against the recording. Quiet clips are skipped to reduce hallucinations.

Local mode is clip-based, not continuous realtime transcription. Browser SpeechRecognition remains a separate explicitly enabled server-capable alternative. Session flags capture transcript callback times, not sample-accurate speech boundaries. Cancellation/background stops microphone and terminates loading/inference. User must retry. Tests cover control flow with mocks, not actual model download/inference or live Mongolian accuracy.

Measurement contract: demo never displays/exports µT. Baseline median, sigma of calibration samples, sample count and observed update rate are computed from real received samples. Observed Hz is not OS calibration accuracy; web browser provides no equivalent native accuracy level. Native platform code remains unbuilt here.

## v6 latest Claude measurement mode merge
Latest uploaded ZIP (2) merged into AR route and its four updated Flutter source files. Original primary dashboard remains unchanged in layout. AR measurement mode hides fictional profile/radar/speech and halts fictional engine/sound/ghost capture. Nullable actual channels remain nullable. Capture watermark is mandatory and mode-specific; demo magnetic values remain null. CSV fictional columns are empty in measurement mode. Mode switching awaits session save and is blocked while video recording or saving; session data/mode snapshot precedes async audio flush.

Local multilingual panel now replays/downloads the last original short clip, allowing comparison with transcription. Last clip is memory-only and replaced by the next clip; download to keep it. Session JSON contains structured soundEvents with UTC, text, source and optional service score, in addition to CSV journal flags. Source replay works even if transcription subsequently fails.

Verification: node checks plus core, AR DOM/camera, sound, multilingual mocks and v6 measurement/export/playback tests. No physical camera/microphone, real model inference or native Flutter build performed in this environment.

## v7 user-marked speech question/reply journal
Final browser/local transcripts have explicit user annotation buttons. Mark own utterance as a question, then mark a later transcript as a reply to that question. No automatic inference of a human identity, conversational intent, spirit speech or confirmed meaning. Acoustic heuristic events cannot be annotated as speech. Closing question linkage prevents subsequent replies. Active session CSV includes annotation flags; JSON soundEvents and interactions include text, IDs, question reference, utterance/annotation UTC and source, with meaningConfirmed=false. Audio recording remains opt-in; local clip playback is the last short clip only. Past saved sessions are not edited by annotations in later sessions.
