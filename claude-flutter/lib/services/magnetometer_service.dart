import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Мэдрэгчийн нарийвчлал (iOS CMMagneticFieldCalibrationAccuracy /
/// Android SENSOR_STATUS_*). -1 = мэдэгдэхгүй.
enum MagAccuracy { unknown, unreliable, low, medium, high }

extension MagAccuracyText on MagAccuracy {
  String get label => switch (this) {
        MagAccuracy.unknown => 'тодорхойгүй',
        MagAccuracy.unreliable => 'тохируулаагүй',
        MagAccuracy.low => 'бага',
        MagAccuracy.medium => 'дунд',
        MagAccuracy.high => 'өндөр',
      };
  bool get needsCalibration => this == MagAccuracy.unreliable || this == MagAccuracy.low;
}

MagAccuracy _acc(int v) => switch (v) {
      0 => MagAccuracy.unreliable,
      1 => MagAccuracy.low,
      2 => MagAccuracy.medium,
      3 => MagAccuracy.high,
      _ => MagAccuracy.unknown,
    };

/// Нэг хэмжилт. x/y/z нь утасны тэнхлэгийн дагуу, µT.
class MagSample {
  final DateTime utc;
  final double x, y, z;
  final MagAccuracy accuracy;
  final String source;
  const MagSample(this.utc, this.x, this.y, this.z, this.accuracy, this.source);
  double get total => math.sqrt(x * x + y * y + z * z);
}

/// Суурь хэмжилт: тайван орчинд хэдэн секундын дундаж ба хэлбэлзэл.
class MagBaseline {
  final DateTime utc;
  final double x, y, z, total, sigma;
  final int samples;
  final bool wasStill;
  const MagBaseline(this.utc, this.x, this.y, this.z, this.total, this.sigma, this.samples, this.wasStill);
}

/// Соронзон хэмжилтийн эх үүсвэр. Утасны дотоод мэдрэгч эсвэл гадаад
/// хэмжигч (Bluetooth г.м.) энэ интерфейсийг хэрэгжүүлнэ.
abstract class MagSource {
  String get id;
  String get label;
  Stream<MagSample> samples();
}

/// iOS: CoreMotion deviceMotion.magneticField (тохируулсан, нарийвчлалтай)
/// Android: Sensor.TYPE_MAGNETIC_FIELD (тохируулсан) + accuracy
/// Native код: ios/Runner/AppDelegate.swift, android/.../MainActivity.kt
class PlatformMagSource implements MagSource {
  static const _channel = EventChannel('acs/magnetometer');
  @override
  String get id => 'phone';
  @override
  String get label => defaultTargetPlatform == TargetPlatform.iOS
      ? 'iPhone магнитометр (CoreMotion, тохируулсан)'
      : 'Утасны магнитометр (тохируулсан)';

  @override
  Stream<MagSample> samples() => _channel.receiveBroadcastStream().map((e) {
        final m = Map<Object?, Object?>.from(e as Map);
        double d(String k) => (m[k] as num).toDouble();
        return MagSample(DateTime.now().toUtc(), d('x'), d('y'), d('z'),
            _acc((m['acc'] as num?)?.toInt() ?? -1), (m['src'] as String?) ?? 'phone');
      });
}

/// Native код суугаагүй үед: sensors_plus (iOS дээр тохируулаагүй түүхий утга
/// байж болох тул нарийвчлал "тодорхойгүй" гэж тэмдэглэнэ).
class SensorsPlusMagSource implements MagSource {
  @override
  String get id => 'sensors_plus';
  @override
  String get label => 'Утасны магнитометр (sensors_plus)';
  @override
  Stream<MagSample> samples() =>
      magnetometerEventStream(samplingPeriod: SensorInterval.gameInterval).map((e) =>
          MagSample(DateTime.now().toUtc(), e.x, e.y, e.z, MagAccuracy.unknown, 'sensors_plus'));
}

/// Гадаад хэмжигч холбох цэг. Төхөөрөмжийн загвар, Bluetooth протоколоос
/// хамаарч хэрэгжүүлнэ (жишээ нь flutter_blue_plus-ээр GATT характеристик унших).
/// Хэрэгжүүлэх хүртэл ашиглагдахгүй — хиймэл утга гаргахгүй.
abstract class ExternalMagSource implements MagSource {}

enum MagStatus { starting, live, unavailable }

/// Бодит соронзон хэмжилт: шууд утга, суурь, Δ, босго, давтамж, 60 сек цонх.
class MagnetometerService extends ChangeNotifier {
  MagnetometerService({MagSource? primary, MagSource? fallback, DateTime Function()? clock})
      : _primary = primary ?? PlatformMagSource(),
        _fallback = fallback ?? SensorsPlusMagSource(),
        _now = clock ?? DateTime.now;
  final MagSource _primary, _fallback;
  final DateTime Function() _now;
  Timer? _timeout, _staleTimer;
  bool _disposed = false;
  int _generation = 0;
  DateTime? _lastSampleAt;
  void _notify() { if (!_disposed) notifyListeners(); }

  MagStatus status = MagStatus.starting;
  String? error;
  MagSource? source;
  MagSample? latest;
  MagBaseline? baseline;
  double hz = 0;

  /// Мэдрэмж 0..1: босго = max(минимум, k·σ)
  double sensitivity = 0.5;

  bool measuring = false;
  double measureProgress = 0;
  String? baselineWarning;

  StreamSubscription<MagSample>? _sub;
  final List<int> _stamps = [];
  int _lastNotify = 0;
  bool Function()? isStill; // гаднаас: утас хөдөлгөөнгүй эсэх

  /// Сүүлийн 60 секундын (≈10 Гц) утга графикт
  final List<(double t, double total, double? delta)> window = [];
  final Stopwatch _clock = Stopwatch()..start();
  double _lastWin = -1;

  double get now => _clock.elapsedMilliseconds / 1000;

  double? get total => latest?.total;

  /// Суурь утгаас зөрүү (нийт хүч). Утсыг эргүүлэхэд нийт хүч өөрчлөгдөхгүй
  /// тул энэ нь чиглэлээс үл хамаарах үзүүлэлт.
  double? get delta => (latest != null && baseline != null) ? latest!.total - baseline!.total : null;

  /// Бүрэлдэхүүн тус бүрийн зөрүү — зөвхөн утас суурь хэмжилтийн үеийн
  /// байрлалдаа хөдөлгөөнгүй байхад утга учиртай.
  (double, double, double)? get deltaXYZ => (latest != null && baseline != null)
      ? (latest!.x - baseline!.x, latest!.y - baseline!.y, latest!.z - baseline!.z)
      : null;

  double get threshold {
    final sigma = baseline?.sigma ?? 1.0;
    final k = 8 - 5 * sensitivity; // 8σ (бага мэдрэмж) .. 3σ (өндөр)
    final floor = 6 - 4 * sensitivity; // 6 µT .. 2 µT
    return math.max(floor, k * sigma);
  }

  bool get anomaly => delta != null && delta!.abs() > threshold;

  Future<void> start() async {
    if (_disposed) return;
    baseline = null;
    window.clear();
    _lastWin = -1;
    await _use(_primary, fallback: true);
  }

  Future<void> stop() async {
    _generation++;
    _timeout?.cancel();
    _staleTimer?.cancel();
    final sub = _sub;
    _sub = null;
    latest = null;
    hz = 0;
    measuring = false;
    status = MagStatus.unavailable;
    error = 'Мэдрэгч зогссон';
    await sub?.cancel();
    _notify();
  }

  Future<void> _use(MagSource src, {bool fallback = false}) async {
    if (_disposed) return;
    final token = ++_generation;
    _timeout?.cancel();
    _staleTimer?.cancel();
    final old = _sub;
    _sub = null;
    await old?.cancel();
    if (_disposed || token != _generation) return;
    source = src;
    latest = null;
    _lastSampleAt = null;
    _stamps.clear();
    hz = 0;
    error = null;
    status = MagStatus.starting;
    _notify();
    var got = false;
    void fail(String message) {
      if (_disposed || token != _generation) return;
      _timeout?.cancel();
      _staleTimer?.cancel();
      if (!got && fallback) {
        unawaited(Future<void>.microtask(() async {
          if (!_disposed && token == _generation) await _use(_fallback);
        }));
        return;
      }
      latest = null;
      hz = 0;
      status = MagStatus.unavailable;
      error = message;
      _notify();
    }
    try {
      _sub = src.samples().listen((s) {
        if (_disposed || token != _generation) return;
        if (![s.x, s.y, s.z].every((v) => v.isFinite)) return;
        got = true;
        _timeout?.cancel();
        _lastSampleAt = _now();
        _onSample(s);
      }, onError: (Object e) => fail('Соронзон мэдрэгчийн алдаа: $e'),
         onDone: () => fail('Соронзон мэдрэгчийн өгөгдөл зогссон'), cancelOnError: true);
      _timeout = Timer(const Duration(seconds: 3), () {
        if (!got) fail('Соронзон мэдрэгчээс өгөгдөл ирсэнгүй');
      });
      _staleTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_disposed || token != _generation || _lastSampleAt == null) return;
        if (_now().difference(_lastSampleAt!).inMilliseconds > 1500 && latest != null) {
          latest = null;
          hz = 0;
          status = MagStatus.unavailable;
          error = 'Өгөгдөл тасарсан — дахин холбох';
          _notify();
        }
      });
    } catch (e) {
      fail('Соронзон мэдрэгч нээгдсэнгүй: $e');
    }
  }

  final List<MagSample> _measureBuf = [];

  void _onSample(MagSample s) {
    latest = s;
    status = MagStatus.live;
    error = null;
    final ms = _now().millisecondsSinceEpoch;
    _stamps.add(ms);
    while (_stamps.isNotEmpty && ms - _stamps.first > 2000) {
      _stamps.removeAt(0);
    }
    final span = _stamps.length > 1 ? (_stamps.last - _stamps.first) / 1000 : 0.0;
    hz = span >= 0.5 ? (_stamps.length - 1) / span : 0;
    if (measuring) _measureBuf.add(s);

    final t = now;
    if (t - _lastWin >= 0.1) {
      _lastWin = t;
      window.add((t, s.total, delta));
      while (window.isNotEmpty && t - window.first.$1 > 60) {
        window.removeAt(0);
      }
    }
    if (ms - _lastNotify > 100) {
      _lastNotify = ms;
      _notify();
    }
  }

  /// [seconds] секундын турш суурь хэмжинэ. Утсаа хөдөлгөөнгүй барих хэрэгтэй.
  Future<MagBaseline?> measureBaseline({double seconds = 3}) async {
    if (measuring || status != MagStatus.live) return null;
    final token = _generation;
    measuring = true;
    measureProgress = 0;
    baselineWarning = null;
    _measureBuf.clear();
    var stillAll = true;
    final steps = (seconds * 10).round();
    for (var i = 0; i < steps; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_disposed || token != _generation || status != MagStatus.live) {
        measuring = false;
        return null;
      }
      measureProgress = (i + 1) / steps;
      if (isStill != null && !isStill!()) stillAll = false;
      _notify();
    }
    measuring = false;
    final buf = List<MagSample>.from(_measureBuf);
    if (buf.length < 5) {
      baselineWarning = 'Хэмжилт хангалтгүй (${buf.length} утга)';
      _notify();
      return null;
    }
    double mean(double Function(MagSample) f) => buf.map(f).reduce((a, b) => a + b) / buf.length;
    final mx = mean((s) => s.x), my = mean((s) => s.y), mz = mean((s) => s.z), mt = mean((s) => s.total);
    final sigma = math.sqrt(buf.map((s) => math.pow(s.total - mt, 2)).reduce((a, b) => a + b) / buf.length);
    baseline = MagBaseline(_now().toUtc(), mx, my, mz, mt, sigma, buf.length, stillAll);
    if (!stillAll) baselineWarning = 'Хэмжилтийн үеэр утас хөдөлсөн — дахин хэмжих нь зүйтэй';
    if (sigma > 3) baselineWarning = 'Хэлбэлзэл их (σ ${sigma.toStringAsFixed(1)} µT) — ойр цахилгаан хэрэгсэл байж магадгүй';
    if (mt < 20 || mt > 70) {
      baselineWarning = (baselineWarning == null ? '' : '$baselineWarning. ') +
          'Нийт хүч ${mt.toStringAsFixed(0)} µT — дэлхийн ердийн 25–65 µT-ээс гадуур (төмөр ойр эсвэл тохируулга хэрэгтэй)';
    }
    _notify();
    return baseline;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timeout?.cancel();
    _staleTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    latest = null;
    super.dispose();
  }
}
