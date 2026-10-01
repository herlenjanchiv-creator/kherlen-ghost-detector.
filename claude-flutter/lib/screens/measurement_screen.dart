import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/magnetometer_service.dart';
import 'splash_screen.dart';

/// Native measurement entry; no camera permission is required for magnetic readings.
class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});
  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _mag = MagnetometerService();
  bool _milligauss = false;
  String _language = 'MN';
  late final AnimationController _radar;
  final Stopwatch _alertClock = Stopwatch()..start();
  int _lastAlert = -10000;
  bool _aboveThreshold = false;
  bool _inAR = false;
  String tr(String mn, String en) => _language == 'MN' ? mn : _translations[_language]?[en] ?? en;
  static const _translations = {
    'ES': {'REAL MAGNETIC MEASUREMENT': 'MEDICIÓN MAGNÉTICA REAL', 'Baseline': 'Referencia', 'Accuracy': 'Precisión', 'Reconnect': 'Reconectar', 'Measure baseline · 3 seconds': 'Medir referencia · 3 segundos', 'Open camera / AR game': 'Abrir cámara / juego AR', 'Waiting for sensor data…': 'Esperando datos del sensor…', 'Magnetic field increase': 'Aumento del campo magnético', 'Magnetic reading': 'Lectura magnética', 'Visual effect · no source location': 'Efecto visual · sin ubicación de fuente'},
    'ID': {'REAL MAGNETIC MEASUREMENT': 'PENGUKURAN MAGNETIK NYATA', 'Baseline': 'Acuan', 'Accuracy': 'Akurasi', 'Reconnect': 'Hubungkan ulang', 'Measure baseline · 3 seconds': 'Ukur acuan · 3 detik', 'Open camera / AR game': 'Buka kamera / game AR', 'Waiting for sensor data…': 'Menunggu data sensor…', 'Magnetic field increase': 'Peningkatan medan magnet', 'Magnetic reading': 'Pembacaan magnetik', 'Visual effect · no source location': 'Efek visual · bukan lokasi sumber'},
  };
  void _onMeasurement() {
    final elevated = _mag.status == MagStatus.live && (_mag.total ?? 0) > 120;
    if (elevated && !_aboveThreshold && _alertClock.elapsedMilliseconds - _lastAlert >= 5000) {
      _lastAlert = _alertClock.elapsedMilliseconds;
      unawaited(HapticFeedback.mediumImpact());
    }
    _aboveThreshold = elevated;
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _radar = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _mag.addListener(_onMeasurement);
    unawaited(_mag.start());
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(_mag.stop());
    if (state == AppLifecycleState.resumed && !_inAR) unawaited(_mag.start());
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mag.removeListener(_onMeasurement);
    _radar.dispose();
    _mag.dispose();
    super.dispose();
  }
  String value(double? v) => v == null ? '—' : (v * (_milligauss ? 10 : 1)).toStringAsFixed(2);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ghost Lens'), actions: [
      PopupMenuButton<String>(icon: const Icon(Icons.language), initialValue: _language,
        onSelected: (v) => setState(() => _language = v), itemBuilder: (_) => const [
          PopupMenuItem(value: 'MN', child: Text('Монгол')),
          PopupMenuItem(value: 'EN', child: Text('English')),
          PopupMenuItem(value: 'ES', child: Text('Español')),
          PopupMenuItem(value: 'ID', child: Text('Bahasa Indonesia')),
        ]),
    ]),
    body: SafeArea(child: AnimatedBuilder(animation: _mag, builder: (context, _) {
      final sample = _mag.latest;
      final unit = _milligauss ? 'mG' : 'µT';
      final ready = sample != null && _mag.status == MagStatus.live;
      final color = !ready ? Colors.grey : (_mag.total! > 120 ? Colors.redAccent : (_mag.total! >= 60 ? Colors.orangeAccent : Colors.greenAccent));
      return ListView(padding: const EdgeInsets.all(20), children: [
        Text(tr('БОДИТ СОРОНЗОН ХЭМЖИЛТ', 'REAL MAGNETIC MEASUREMENT')),
        const SizedBox(height: 16),
        Center(child: SizedBox(width: 280, height: 280, child: Stack(alignment: Alignment.center, children: [
          AnimatedBuilder(animation: _radar, builder: (_, _) => Transform.rotate(angle: _radar.value * 2 * math.pi,
            child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color),
              gradient: SweepGradient(colors: [color.withValues(alpha: 0.25), Colors.transparent]))))),
          Container(width: 180, height: 180, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.4)))),
          Column(mainAxisSize: MainAxisSize.min, children: [Text(value(ready ? _mag.total : null),
            style: TextStyle(color: color, fontSize: 48, fontWeight: FontWeight.bold)), Text(unit)]),
        ]))),
        Text(tr('Дүрслэлийн эффект · үүсгэгчийн байршил биш', 'Visual effect · no source location'), textAlign: TextAlign.center),
        if (ready) Text(_mag.total! > 120 ? tr('Соронзон орны өсөлт', 'Magnetic field increase') : tr('Соронзон хэмжилт', 'Magnetic reading'), style: TextStyle(color: color), textAlign: TextAlign.center),
        Text(ready ? 'LIVE · ${sample.source}' : (_mag.status == MagStatus.starting
          ? tr('Мэдрэгчийн өгөгдөл хүлээж байна…', 'Waiting for sensor data…')
          : tr(_mag.error ?? 'Мэдрэгч байхгүй', 'Sensor unavailable. Reconnect or check device support.'))),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('µT / mG'), value: _milligauss,
          onChanged: (v) => setState(() => _milligauss = v)),
        Wrap(spacing: 20, runSpacing: 12, children: [
          Text('X ${value(ready ? sample.x : null)} $unit'),
          Text('Y ${value(ready ? sample.y : null)} $unit'),
          Text('Z ${value(ready ? sample.z : null)} $unit'),
        ]),
        const SizedBox(height: 20),
        Text('${tr('Суурь', 'Baseline')}: ${value(_mag.baseline?.total)} $unit'),
        Text('σ: ${value(_mag.baseline?.sigma)} $unit · Δ: ${value(_mag.delta)} $unit'),
        Text('${_mag.hz.toStringAsFixed(1)} Hz · ${tr('Нарийвчлал', 'Accuracy')}: ${sample?.accuracy.name ?? '—'}'),
        const SizedBox(height: 12),
        FilledButton(onPressed: ready && !_mag.measuring ? () => _mag.measureBaseline() : null,
          child: Text(_mag.measuring ? '${(_mag.measureProgress * 100).round()}%' : tr('Суурь хэмжих · 3 секунд', 'Measure baseline · 3 seconds'))),
        if (_mag.baselineWarning != null) Text(_mag.baselineWarning!),
        OutlinedButton(onPressed: _mag.start, child: Text(tr('Дахин холбох', 'Reconnect'))),
        const SizedBox(height: 20),
        Text(tr('X/Y/Z нь утасны тэнхлэгүүд. Эдгээр нь үүсгэгчийн байршил, сүнс эсвэл RF алдагдлыг тогтоохгүй.',
          'X/Y/Z are device axes. They do not locate a source, detect spirits or measure RF leakage.')),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: () async {
          _inAR = true;
          await _mag.stop();
          if (!context.mounted) return;
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SplashScreen()));
          if (mounted) {
            _inAR = false;
            unawaited(_mag.start());
          }
        }, child: Text(tr('Камер / AR тоглоом нээх', 'Open camera / AR game'))),
      ]);
    })),
  );
}
