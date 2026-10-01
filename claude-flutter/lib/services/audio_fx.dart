import 'package:audioplayers/audioplayers.dart';

/// Дууны эффектүүд. Алдаа гарвал аппыг унагахгүйгээр чимээгүй ажиллана.
class AudioFx {
  final AudioPlayer _hum = AudioPlayer();
  final AudioPlayer _tick = AudioPlayer();
  final AudioPlayer _voice = AudioPlayer();
  final AudioPlayer _fx = AudioPlayer();
  final AudioPlayer _alert = AudioPlayer();

  bool enabled = true;
  bool _ready = false;
  double _humVol = 0;

  Future<void> init() async {
    try {
      // Олон тоглуулагч зэрэг дуугарах (бие биенээ зогсоохгүй)
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
    } catch (_) {}
    try {
      await _tick.setPlayerMode(PlayerMode.lowLatency);
      await _hum.setReleaseMode(ReleaseMode.loop);
      await _hum.play(AssetSource('sfx/hum.wav'), volume: 0);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  void setEnabled(bool v) {
    enabled = v;
    _safe(() => _hum.setVolume(v ? _humVol : 0));
  }

  /// EMF түвшингээр (0..1) суурь дууны хүчийг тохируулна
  void setLevel(double level) {
    if (!_ready) return;
    final v = (0.05 + level * 0.55).clamp(0.0, 1.0);
    if ((v - _humVol).abs() < 0.03) return;
    _humVol = v;
    if (enabled) _safe(() => _hum.setVolume(v));
  }

  void tick() => _play(_tick, 'sfx/tick.wav', 0.55);
  void whisper() => _play(_voice, 'sfx/whisper.wav', 0.9);
  void growl() => _play(_voice, 'sfx/growl.wav', 1.0);
  void sting() => _play(_fx, 'sfx/sting.wav', 1.0);
  void flag() => _play(_alert, 'sfx/flag.wav', 1.0);

  void _play(AudioPlayer p, String asset, double vol) {
    if (!enabled || !_ready) return;
    _safe(() => p.play(AssetSource(asset), volume: vol));
  }

  void _safe(Future<void> Function() f) {
    f().catchError((_) {});
  }

  Future<void> pause() async {
    try {
      await _hum.pause();
    } catch (_) {}
  }

  Future<void> resume() async {
    try {
      if (_ready) await _hum.resume();
    } catch (_) {}
  }

  void dispose() {
    for (final p in [_hum, _tick, _voice, _fx, _alert]) {
      p.dispose();
    }
  }
}
