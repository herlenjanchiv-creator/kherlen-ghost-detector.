import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Нэг хэмжилт (секундэд 10 удаа)
class Sample {
  final double t; // сешн эхэлснээс хойш, сек
  final double? magTotal; // соронзон орны нийт хүч µT (бодит; байхгүй бол null)
  final double? dev; // суурь утгаас зөрүү µT (бодит; суурь хэмжээгүй бол null)
  final double? ghost; // тоглоомын "сүнсний дохио" 0..1 (физик нэгжгүй; хэмжилтийн горимд null)
  final double vib; // чичиргээ м/с² (бодит, хурдатгал мэдрэгч)
  final double motion; // камерын хөдөлгөөн 0..1 (бодит)
  final double tilt; // 0.1 сек дэх хазайлтын өөрчлөлт, градус (бодит)
  const Sample(this.t, this.magTotal, this.dev, this.ghost, this.vib, this.motion, this.tilt);
}

/// Бүртгэх үеийн соронзон хэмжилт (MagnetometerService-ээс)
class MagRow {
  final double x, y, z, total;
  final double? baseline, delta, sigma, threshold;
  final String accuracy, source;
  const MagRow({
    required this.x,
    required this.y,
    required this.z,
    required this.total,
    required this.baseline,
    required this.delta,
    required this.sigma,
    required this.threshold,
    required this.accuracy,
    required this.source,
  });
}

class FlagMark {
  final double t;
  final String label;
  final bool auto;
  const FlagMark(this.t, this.label, this.auto);
}

String _cell(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
String _n(double? v, int d) => v == null ? '' : v.toStringAsFixed(d);

/// Solus маягийн өгөгдөл бүртгэгч:
///  • бүх хэмжилтийг тасралтгүй CSV файлд бичнэ (UTC огноо/цагтай)
///  • сүүлийн 60 секундыг график зурахад хадгална
///  • огцом өөрчлөлтийг автоматаар "Spike flag" болгоно (мэдрэмж тохируулна)
///  • гараар, тайлбартай flag тавина
class DataLogger extends ChangeNotifier {
  DataLogger({Future<Directory> Function()? directory}) : _directory = directory ?? getApplicationDocumentsDirectory;
  final Future<Directory> Function() _directory;
  static const int windowSamples = 600; // 60 сек × 10 Гц
  static const header = [
    'utc', 'elapsed_s', 'mode', 'mag_source', 'mag_accuracy', 'bx_uT', 'by_uT', 'bz_uT', 'b_total_uT',
    'baseline_uT', 'delta_uT', 'baseline_sigma_uT', 'threshold_uT', 'vibration_ms2', 'motion_pct',
    'tilt_deg', 'heading_deg', 'ghost_signal_game', 'ghost_distance_m', 'ghost_mood', 'event',
  ];

  final List<Sample> samples = [];
  final List<FlagMark> flags = [];
  double sensitivity = 0.5; // 0 = бага мэдрэмж, 1 = өндөр
  File? file;
  int rows = 0;

  IOSink? _sink;
  final DateTime _start = DateTime.now();
  double _lastAutoFlag = -10;
  bool _wasMagAnomaly = false;
  String _mode = 'live';
  int _flagSerial = 0;
  int get flagSerial => _flagSerial; // шинэ flag бүрт өснө (дуу/гэрэл)
  FlagMark? get lastFlag => flags.isEmpty ? null : flags.last;

  double get now => DateTime.now().difference(_start).inMilliseconds / 1000;

  Future<void> start() async {
    try {
      final dir = await _directory();
      final d = _start;
      String two(int n) => n.toString().padLeft(2, '0');
      final name = 'ghostlog_${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}${two(d.second)}.csv';
      file = File('${dir.path}/$name');
      _sink = file!.openWrite();
      _sink!.write('\uFEFF');
      _sink!.writeln(header.map(_cell).join(','));
    } catch (e) {
      debugPrint('Лог файл нээх алдаа: $e');
    }
  }

  /// Шинэ хэмжилт нэмнэ. Автомат flag тавигдвал түүний тайлбарыг буцаана.
  /// [mag] null бол соронзон мэдрэгч алга — хоосон нүд бичнэ (хиймэл утга бичихгүй).
  String? add({
    required MagRow? mag,
    required bool magAnomaly,
    required String mode, // live | measure
    required double? ghost,
    required double vib,
    required double motion,
    required double tilt,
    required double heading,
    required double? ghostDistance,
    required String? mood,
  }) {
    _mode = mode;
    final t = now;
    final s = Sample(t, mag?.total, mag?.delta, ghost, vib, motion, tilt);

    String? auto;
    final k = sensitivity.clamp(0.0, 1.0);
    // Соронзон: босго давсан мөч (суурь ба σ-д суурилсан)
    if (magAnomaly && !_wasMagAnomaly && mag?.delta != null) {
      auto = 'Соронзон орон Δ${mag!.delta! >= 0 ? '+' : ''}${mag.delta!.toStringAsFixed(1)} µT (босго ${mag.threshold?.toStringAsFixed(1)})';
    }
    _wasMagAnomaly = magAnomaly;
    if (auto == null && samples.length >= 20 && t - _lastAutoFlag > 2.0) {
      final vibTh = 6 - 4.8 * k; // м/с²: 6 .. 1.2
      final motTh = 0.15 - 0.13 * k; // 15% .. 2%
      final tiltTh = 8 - 7 * k; // градус: 8 .. 1
      if (vib > vibTh) {
        auto = 'Чичиргээ ${vib.toStringAsFixed(1)} м/с²';
      } else if (tilt > tiltTh) {
        auto = 'Хазайлт ${tilt.toStringAsFixed(1)}°';
      } else if (motion > motTh) {
        auto = 'Хөдөлгөөн ${(motion * 100).toStringAsFixed(0)}%';
      }
    }

    samples.add(s);
    if (samples.length > windowSamples) samples.removeAt(0);
    flags.removeWhere((f) => t - f.t > 60);

    if (auto != null) {
      _lastAutoFlag = t;
      _addFlag(t, auto, true);
    }

    _writeRow([
      DateTime.now().toUtc().toIso8601String(), t.toStringAsFixed(2), mode,
      mag?.source ?? 'unavailable', mag?.accuracy, _n(mag?.x, 2), _n(mag?.y, 2), _n(mag?.z, 2), _n(mag?.total, 2),
      _n(mag?.baseline, 2), _n(mag?.delta, 2), _n(mag?.sigma, 2), _n(mag?.threshold, 2),
      vib.toStringAsFixed(2), (motion * 100).toStringAsFixed(1), tilt.toStringAsFixed(2),
      heading.toStringAsFixed(0), _n(ghost, 3), _n(ghostDistance, 1), mood,
      auto == null ? null : 'AUTO: $auto',
    ]);
    notifyListeners();
    return auto;
  }

  /// Гараар flag тавих (тайлбартай байж болно)
  void manualFlag([String? note]) {
    final t = now;
    final label = (note == null || note.trim().isEmpty) ? 'Гар тэмдэг' : note.trim();
    _addFlag(t, label, false);
    _writeRow([DateTime.now().toUtc().toIso8601String(), t.toStringAsFixed(2), _mode, ...List.filled(header.length - 4, null), 'MANUAL: $label']);
    notifyListeners();
  }

  /// Суурь хэмжилт гэх мэт тусгай үйл явдлыг бүртгэлд тэмдэглэх
  void note(String text) {
    _writeRow([DateTime.now().toUtc().toIso8601String(), now.toStringAsFixed(2), _mode, ...List.filled(header.length - 4, null), text]);
  }

  void _addFlag(double t, String label, bool auto) {
    flags.add(FlagMark(t, label, auto));
    _flagSerial++;
  }

  void _writeRow(List<Object?> cells) {
    final sink = _sink;
    if (sink == null) return;
    sink.writeln(cells.map(_cell).join(','));
    rows++;
  }

  Future<File?> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
    return file;
  }

  /// Графикт хэрэгтэй хамгийн их утгууд (автомат масштаб)
  double maxOf(double? Function(Sample) f, double floor) {
    var m = floor;
    for (final s in samples) {
      final v = f(s);
      if (v != null && v > m) m = v;
    }
    return m;
  }

  @override
  void dispose() {
    final s = _sink;
    _sink = null;
    s?.flush().then((_) => s.close()).catchError((_) {});
    super.dispose();
  }
}
