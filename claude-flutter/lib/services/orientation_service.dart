import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Энгийн 3D вектор
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);

  double get length => math.sqrt(x * x + y * y + z * z);
  V3 normalized() {
    final l = length;
    return l < 1e-9 ? this : V3(x / l, y / l, z / l);
  }

  V3 cross(V3 o) =>
      V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  V3 lerpTo(V3 o, double k) => this + (o - this) * k;
}

/// -180..180 хооронд өнцгийн зөрүү (a - b)
double angleDiff(double a, double b) => ((a - b + 540) % 360) - 180;

/// Хурдатгал + соронзон мэдрэгчээс утасны чиглэл (азимут), налуу,
/// соронзон орны хүч, алхам, сэгсрэлтийг тооцно.
///
/// Тооцоолол нь Android-ын SensorManager.getRotationMatrix-тай ижил:
///   H = E × A,  M = A × H  →  дэлхийн (Зүүн, Хойд, Дээш) тэнхлэгүүд
/// Арын камер утасны -Z тэнхлэг рүү харна.
class OrientationService {
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<MagnetometerEvent>? _magSub;

  V3 _g = const V3(0, 0, 9.81);
  V3 _m = const V3(0, 25, -40);
  bool _hasAcc = false, _hasMag = false;
  bool sensorError = false;

  /// Арын камерын харж буй азимут (0 = хойд, 90 = зүүн), градус
  double heading = 0;

  /// Арын камерын хэвтээ шугамаас дээш/доош налуу, градус
  double pitch = 0;

  /// Соронзон орны нийт хүч, µT
  double magnitude = 0;

  bool get ready => _hasAcc && _hasMag;

  final _steps = StreamController<void>.broadcast();
  final _shakes = StreamController<void>.broadcast();

  /// Алхам хийх бүрт (хурдатгалын оргил)
  Stream<void> get steps => _steps.stream;

  /// Утсыг хүчтэй сэгсрэх үед
  Stream<void> get shakes => _shakes.stream;

  int _lastStepMs = 0, _lastShakeMs = 0;
  bool _aboveStep = false;
  int _stillSinceMs = 0;
  double _vibPeak = 0;

  /// Тэнцвэржүүлсэн хүндийн хүчний вектор (хазайлт тооцоход)
  V3 get gravity => _g;

  /// Сүүлд уншснаас хойших хамгийн их чичиргээ (м/с²), уншмагц тэглэнэ
  double takeVibration() {
    final v = _vibPeak;
    _vibPeak = 0;
    return v;
  }

  /// Утас тогтвортой (гуравхөл дээр эсвэл тавиад) 1.5 сек+ байгаа эсэх.
  /// Хөдөлгөөн мэдрэгч зөвхөн энэ үед зөв ажиллана.
  bool get isStill =>
      ready && DateTime.now().millisecondsSinceEpoch - _stillSinceMs > 1500;

  void start() {
    _accSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onAcc, onError: (_) => sensorError = true, cancelOnError: false);

    _magSub = magnetometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onMag, onError: (_) => sensorError = true, cancelOnError: false);
  }

  void _onAcc(AccelerometerEvent e) {
    final raw = V3(e.x, e.y, e.z);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!_hasAcc || (raw - _g).length > 0.35) _stillSinceMs = now;
    _g = _hasAcc ? _g.lerpTo(raw, 0.12) : raw;
    _hasAcc = true;

    final dyn = raw.length - 9.81;
    if (dyn.abs() > _vibPeak) _vibPeak = dyn.abs();

    if (dyn.abs() > 14 && now - _lastShakeMs > 900) {
      _lastShakeMs = now;
      _shakes.add(null);
    } else if (!_aboveStep && dyn > 1.6 && now - _lastStepMs > 320 &&
        now - _lastShakeMs > 900) {
      _aboveStep = true;
      _lastStepMs = now;
      _steps.add(null);
    }
    if (dyn < 0.5) _aboveStep = false;

    _compute();
  }

  void _onMag(MagnetometerEvent e) {
    final raw = V3(e.x, e.y, e.z);
    _m = _hasMag ? _m.lerpTo(raw, 0.18) : raw;
    magnitude = raw.length;
    _hasMag = true;
    _compute();
  }

  void _compute() {
    if (!ready) return;
    final a = _g.normalized();
    final h0 = _m.cross(a);
    if (h0.length < 1e-3) return; // чөлөөт уналт эсвэл соронзон туйлд
    final h = h0.normalized();
    final m = a.cross(h);

    // Төхөөрөмжийн (0,0,-1) вектор дэлхийн координатад
    final east = -h.z, north = -m.z, up = -a.z;

    var hd = math.atan2(east, north) * 180 / math.pi;
    if (hd < 0) hd += 360;
    heading = (heading + angleDiff(hd, heading) * 0.5 + 360) % 360;
    pitch = math.asin(up.clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  /// Идэвхтэй камерын харах чиглэл
  double viewHeading({required bool front}) =>
      front ? (heading + 180) % 360 : heading;

  double viewPitch({required bool front}) => front ? -pitch : pitch;

  void dispose() {
    _accSub?.cancel();
    _magSub?.cancel();
    _steps.close();
    _shakes.close();
  }
}
