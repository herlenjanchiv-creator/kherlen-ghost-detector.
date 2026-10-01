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
    await _use(PlatformMagSource(), fallback: true);
  }

  Future<void> _use(MagSource src, {bool fallback = false}) async {
    await _sub?.cancel();
    source = src;
    status = MagStatus.starting;
    var got = false;
    _sub = src.samples().listen((s) {
      got = true;
      _onSample(s);
    }, onError: (Object e) {
      if (!got && fallback) {
        _use(SensorsPlusMagSource()); // native код байхгүй/алдаатай
      } else if (!got) {
        status = MagStatus.unavailable;
        error = 'Энэ төхөөрөмжид соронзон мэдрэгч олдсонгүй';
        notifyListeners();
      }
    }, cancelOnError: true);
    // 3 секундэд өгөгдөл ирэхгүй бол дараагийн эх үүсвэр
    Future.delayed(const Duration(seconds: 3), () {
      if (!got && source == src) {
        if (fallback) {
          _use(SensorsPlusMagSource());
        } else {
          status = MagStatus.unavailable;
          error = 'Соронзон мэдрэгчээс өгөгдөл ирсэнгүй';
          notifyListeners();
        }
      }
    });
  }

  final List<MagSample> _measureBuf = [];

  void _onSample(MagSample s) {
    latest = s;
    status = MagStatus.live;
    final ms = DateTime.now().millisecondsSinceEpoch;
    _stamps.add(ms);
    while (_stamps.isNotEmpty && ms - _stamps.first > 2000) {
      _stamps.removeAt(0);
    }
    hz = _stamps.length / 2.0;
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
      notifyListeners();
    }
  }

  /// [seconds] секундын турш суурь хэмжинэ. Утсаа хөдөлгөөнгүй барих хэрэгтэй.
  Future<MagBaseline?> measureBaseline({double seconds = 3}) async {
    if (measuring || status != MagStatus.live) return null;
    measuring = true;
    baselineWarning = null;
    _measureBuf.clear();
    var stillAll = true;
    final steps = (seconds * 10).round();
    for (var i = 0; i < steps; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      measureProgress = (i + 1) / steps;
      if (isStill != null && !isStill!()) stillAll = false;
      notifyListeners();
    }
    measuring = false;
    final buf = List<MagSample>.from(_measureBuf);
    if (buf.length < 5) {
      baselineWarning = 'Хэмжилт хангалтгүй (${buf.length} утга)';
      notifyListeners();
      return null;
    }
    double mean(double Function(MagSample) f) => buf.map(f).reduce((a, b) => a + b) / buf.length;
    final mx = mean((s) => s.x), my = mean((s) => s.y), mz = mean((s) => s.z), mt = mean((s) => s.total);
    final sigma = math.sqrt(buf.map((s) => math.pow(s.total - mt, 2)).reduce((a, b) => a + b) / buf.length);
    baseline = MagBaseline(DateTime.now().toUtc(), mx, my, mz, mt, sigma, buf.length, stillAll);
    if (!stillAll) baselineWarning = 'Хэмжилтийн үеэр утас хөдөлсөн — дахин хэмжих нь зүйтэй';
    if (sigma > 3) baselineWarning = 'Хэлбэлзэл их (σ ${sigma.toStringAsFixed(1)} µT) — ойр цахилгаан хэрэгсэл байж магадгүй';
    if (mt < 20 || mt > 70) {
      baselineWarning = (baselineWarning == null ? '' : '$baselineWarning. ') +
          'Нийт хүч ${mt.toStringAsFixed(0)} µT — дэлхийн ердийн 25–65 µT-ээс гадуур (төмөр ойр эсвэл тохируулга хэрэгтэй)';
    }
    notifyListeners();
    return baseline;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
