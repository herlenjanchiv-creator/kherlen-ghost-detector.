import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/magnetometer_service.dart';
import '../services/orientation_service.dart';

enum Phase { calibrating, searching, encounter, vanished }

enum Mood { calm, sad, irritated, angry }

extension MoodText on Mood {
  String get label => switch (this) {
        Mood.calm => 'Тайван',
        Mood.sad => 'Гунигтай',
        Mood.irritated => 'Бухимдсан',
        Mood.angry => 'УУРЛАСАН',
      };
}

/// Сүнсний "профайл" — санамсаргүйгээр үүсгэгддэг зохиомол дүр.
class GhostProfile {
  final String name;
  final int age;
  final bool male;
  final String era;
  final Mood baseMood;

  const GhostProfile({
    required this.name,
    required this.age,
    required this.male,
    required this.era,
    required this.baseMood,
  });

  String get gender => male ? 'Эрэгтэй' : 'Эмэгтэй';

  static const _maleNames = [
    'Батболд', 'Дорж', 'Ганбаатар', 'Пүрэв', 'Төмөр', 'Очир', 'Самбуу',
    'Дамдин', 'Лхагва', 'Жамсран',
  ];
  static const _femaleNames = [
    'Должин', 'Цэцэг', 'Сарантуяа', 'Ханд', 'Оюун', 'Балжид', 'Дулам',
    'Норжмаа', 'Пагма', 'Сэлэнгэ',
  ];
  static const _eras = [
    '1920-иод он', '1930-аад он', '1940-өөд он', '1950-иад он',
    '1960-аад он', '1970-аад он', '1980-аад он', '1990-ээд он',
  ];

  factory GhostProfile.random(math.Random r) {
    final male = r.nextBool();
    final names = male ? _maleNames : _femaleNames;
    final roll = r.nextDouble();
    return GhostProfile(
      name: names[r.nextInt(names.length)],
      age: 18 + r.nextInt(75),
      male: male,
      era: _eras[r.nextInt(_eras.length)],
      baseMood: roll < 0.4 ? Mood.calm : (roll < 0.75 ? Mood.sad : Mood.irritated),
    );
  }
}

const Map<Mood, List<String>> kPhrases = {
  Mood.calm: [
    'Би энд олон жил амьдарсан...',
    'Чи намайг харж байна уу?',
    'Энэ байшин миний гэр байсан.',
    'Айх хэрэггүй... би зүгээр л ажиглаж байна.',
    'Цонхоор гэрэл тусахыг харах дуртай.',
    'Хэн нэгэн намайг санаж байгаа болов уу...',
  ],
  Mood.sad: [
    'Би гэртээ харьж чадахгүй байна...',
    'Миний гэр бүл хаана байна?',
    'Хүйтэн байна... их хүйтэн.',
    'Намайг мартчихсан уу?',
    'Би хүлээсээр л байна...',
    'Ганцаараа байхаас залхаж байна.',
  ],
  Mood.irritated: [
    'Чи яагаад энд ирсэн юм?',
    'Тэр утсаа холдуул...',
    'Чимээгүй бай!',
    'Энэ миний газар.',
    'Намайг бүү шагай.',
    'Яв... одоохон.',
  ],
  Mood.angry: [
    'ЯВ ЭНДЭЭС!',
    'НАМАЙГ ОРХИ!',
    'ЧИ ЭНД БАЙХ ЁСГҮЙ!',
    'БҮҮ ОЙРТ!',
    'ГАР!!!',
  ],
};

/// Тоглоомын үндсэн логик.
///
/// Сүнс нь орон зайд ВИРТУАЛ байрлалтай (азимут + зай). Утасны чиглэл
/// (соронзон мэдрэгч + хурдатгал мэдрэгч) сүнс рүү ойртох тусам EMF
/// заалт өснө. Бодит соронзон аномали (жишээ нь төмөр, цахилгаан хэрэгсэл)
/// илэрвэл сүнсийг "татаж" ойртуулна.
class GhostEngine extends ChangeNotifier {
  final math.Random _r = math.Random();

  Phase phase = Phase.calibrating;
  GhostProfile profile = GhostProfile.random(math.Random());

  // Сүнсний виртуал байрлал
  double bearing = 0; // азимут, градус
  double distance = 15; // метр
  final double elevation = -2; // хэвтээ шугамаас бага зэрэг доор

  // Камерын тухай
  double viewHeading = 0, viewPitch = 0;
  double delta = 0; // сүнс − харах чиглэл (−180..180)

  // Заалтууд
  double emf = 0; // 0..1 (K-II маягийн 5 LED)
  double anger = 0; // 0..1
  double reveal = 0; // профайл шинжилгээний явц 0..1
  double magBaseline = 0, magDeviation = 0;

  /// Бодит соронзон хэмжилт (тохируулсан µT, суурь, босго). Байвал түүнийг ашиглана.
  MagnetometerService? mag;
  bool anomaly = false;

  String speech = '';
  int speechSerial = 0; // шинэ үг бүрт нэмэгдэнэ (UI/дуунд)
  int rageSerial = 0; // уурлаж дайрах бүрт
  final List<String> log = [];

  double _time = 0, _calibTime = 0, _speechTimer = 0, _lostTimer = 0;
  double _vanishTimer = 0;
  bool _spawned = false;
  final List<double> _calib = [];
  final List<String> _usedPhrases = [];

  Mood get mood {
    if (anger >= 0.6) return Mood.angry;
    if (anger >= 0.3) return Mood.irritated;
    return profile.baseMood == Mood.irritated ? Mood.sad : profile.baseMood;
  }

  /// Камерын хэвтээ харах өнцөг (portrait, cover тайрсны дараа ойролцоогоор)
  static const double hfov = 58;
  static const double vfov = 78;

  bool get inView => delta.abs() < hfov / 2 + 4;
  double get calibProgress => (_calibTime / 2.0).clamp(0.0, 1.0);

  /// Уурын түвшинг зурагт (улаан өнгө, нүд) хөрвүүлэх 0..1
  double get rageVisual => ((anger - 0.3) / 0.7).clamp(0.0, 1.0);
  bool get encounterReady => reveal >= 1;

  void addLog(String s) => _addLog(s);

  void _addLog(String s) {
    log.insert(0, s);
    if (log.length > 4) log.removeLast();
  }

  void recalibrate() {
    phase = Phase.calibrating;
    _calib.clear();
    _calibTime = 0;
    anomaly = false;
    notifyListeners();
  }

  void _spawn({bool fresh = true}) {
    if (fresh) {
      profile = GhostProfile.random(_r);
      anger = switch (profile.baseMood) {
        Mood.irritated => 0.22,
        Mood.sad => 0.08,
        _ => 0.0,
      };
    }
    // Хэрэглэгчийн ардуур эсвэл хажуугаар гарч ирнэ
    bearing = (viewHeading + 70 + _r.nextDouble() * 220) % 360;
    distance = 12 + _r.nextDouble() * 8;
    reveal = 0;
    speech = '';
    _usedPhrases.clear();
    phase = Phase.searching;
    _addLog('Шинэ энергийн эх үүсвэр илэрлээ (~${distance.toStringAsFixed(0)} м)');
  }

  void onStep() {
    if (phase != Phase.searching && phase != Phase.encounter) return;
    // Сүнс рүү харж алхвал ойртоно
    if (delta.abs() < 35) distance = math.max(1.3, distance - 0.8);
  }

  double motionLevel = 0;
  double _motionCooldown = 0;

  /// Камер тогтвортой үед бодит хөдөлгөөн илэрвэл (хүн, амьтан, юм унах г.м.)
  /// сүнсийг тэр чиглэл рүү татна. [xNorm] — дүрсэн дэх хэвтээ байрлал.
  void onMotion(double level, double xNorm) {
    motionLevel = level;
    if (level < 0.015 || phase == Phase.calibrating || phase == Phase.vanished) return;
    emf = math.min(1, emf + level * 0.6);
    if (_motionCooldown <= 0) {
      _motionCooldown = 2.5;
      _addLog('Хөдөлгөөн илэрлээ (${(level * 100).toStringAsFixed(0)}% талбай)');
      final b = (viewHeading + (xNorm - 0.5) * hfov + 360) % 360;
      bearing = (bearing + angleDiff(b, bearing) * 0.5 + 360) % 360;
      distance = math.max(1.3, distance - 1.0);
    }
  }

  void onShake() {
    if (phase == Phase.encounter || phase == Phase.searching) {
      anger = math.min(1, anger + 0.3);
      _addLog('Сэгсрэлт сүнсийг бухимдуулав');
    }
  }

  /// Хэмжилтийн горим: сүнсний логикгүйгээр зөвхөн чиглэл ба бодит соронзон
  /// зөрүүг шинэчилнэ.
  void updateViewOnly(OrientationService o, {required bool front}) {
    viewHeading = o.viewHeading(front: front);
    viewPitch = o.viewPitch(front: front);
    final m = mag;
    magDeviation = (m?.delta ?? 0).abs();
    anomaly = m?.anomaly ?? false;
    notifyListeners();
  }

  void update(double dt, OrientationService o, {required bool front}) {
    _time += dt;
    if (_motionCooldown > 0) _motionCooldown -= dt;
    viewHeading = o.viewHeading(front: front);
    viewPitch = o.viewPitch(front: front);
    delta = angleDiff(bearing, viewHeading);

    switch (phase) {
      case Phase.calibrating:
        if (o.ready) {
          if (mag == null) _calib.add(o.magnitude);
          _calibTime += dt;
        }
        if (_calibTime >= 2.0 && (_calib.isNotEmpty || mag != null)) {
          if (mag == null) {
            magBaseline = _calib.reduce((a, b) => a + b) / _calib.length;
            _addLog('Суурь соронзон орон: ${magBaseline.toStringAsFixed(1)} µT');
          }
          if (_spawned) {
            phase = Phase.searching; // дахин тохируулсны дараа үргэлжлүүлнэ
          } else {
            _spawned = true;
            _spawn();
          }
        }
        emf = 0.05 + _r.nextDouble() * 0.05;
        break;

      case Phase.searching:
      case Phase.encounter:
        _updateActive(dt, o);
        break;

      case Phase.vanished:
        emf = math.max(0, emf - dt * 0.8);
        _vanishTimer -= dt;
        if (_vanishTimer <= 0) _spawn();
        break;
    }
    notifyListeners();
  }

  void _updateActive(double dt, OrientationService o) {
    // --- Бодит соронзон орон ---
    final wasAnomaly = anomaly;
    final m = mag;
    if (m != null) {
      // Бодит: суурь хэмжилтээс гарсан зөрүү ба хэлбэлзэлд суурилсан босго
      magDeviation = (m.delta ?? 0).abs();
      anomaly = m.anomaly;
    } else {
      magDeviation = (o.magnitude - magBaseline).abs();
      anomaly = magDeviation > 20;
    }
    if (anomaly && !wasAnomaly) {
      _addLog('Соронзон аномали: Δ${magDeviation.toStringAsFixed(0)} µT');
    }
    if (anomaly) {
      // Аномали сүнсийг өөр рүүгээ татна
      bearing = (bearing + angleDiff(viewHeading, bearing) * dt * 0.8 + 360) % 360;
      distance = math.max(1.3, distance - dt * 1.2);
      anger = math.min(1, anger + dt * 0.06);
    }

    final align = math.exp(-math.pow(delta / 35, 2).toDouble());
    final proximity = ((20 - distance) / 18.7).clamp(0.0, 1.0);

    // --- Хөдөлгөөн ---
    if (align > 0.55) {
      distance = math.max(1.3, distance - dt * 0.35); // харж байвал ойртоно
    } else {
      // Харахгүй байхад сүнс тэнүүчилнэ
      bearing = (bearing + math.sin(_time * 0.37) * dt * 6 + 360) % 360;
    }
    distance = math.max(1.3, distance - dt * 0.05); // аажмаар өөрөө ойртоно

    // --- EMF ---
    final target = (0.06 +
            0.5 * align * (0.35 + 0.65 * proximity) +
            0.35 * proximity * proximity +
            (magDeviation / 90) +
            (_r.nextDouble() - 0.5) * 0.06)
        .clamp(0.0, 1.0);
    emf += (target - emf) * math.min(1, dt * 6);

    // --- Уур ---
    if (distance < 2.2) anger += dt * 0.025;
    if (phase == Phase.encounter && align > 0.8) anger += dt * 0.01;
    if (distance > 4 && !anomaly) anger -= dt * 0.015;
    anger = anger.clamp(0.0, 1.0);

    // --- Үе шат ---
    if (phase == Phase.searching) {
      if (distance < 3.6 && inView) {
        phase = Phase.encounter;
        _speechTimer = 1.0;
        _lostTimer = 0;
        _addLog('СҮНС ИЛЭРЛЭЭ — шинжилгээ эхэллээ');
      }
    } else {
      // encounter
      reveal = math.min(1, reveal + dt / 2.8);
      if (!inView) {
        _lostTimer += dt;
        if (_lostTimer > 5) {
          phase = Phase.searching;
          distance = 6 + _r.nextDouble() * 3;
          _addLog('Сүнс холдлоо...');
        }
      } else {
        _lostTimer = 0;
      }

      if (encounterReady) {
        _speechTimer -= dt;
        if (_speechTimer <= 0) {
          _say();
          _speechTimer = mood == Mood.angry ? 3.0 : 4.6;
        }
      }

      if (anger >= 0.97) {
        // Уурласан сүнс дайраад алга болно
        rageSerial++;
        phase = Phase.vanished;
        _vanishTimer = 4;
        speech = '';
        _addLog('Сүнс дайраад алга болов!');
      }
    }
  }

  void _say() {
    final list = kPhrases[mood]!;
    final fresh = list.where((p) => !_usedPhrases.contains(p)).toList();
    final pool = fresh.isEmpty ? list : fresh;
    final pick = pool[_r.nextInt(pool.length)];
    _usedPhrases.add(pick);
    if (_usedPhrases.length > 6) _usedPhrases.removeAt(0);
    speech = pick;
    speechSerial++;
  }
}
