import 'dart:async';
import 'package:flutter/material.dart';
import '../services/magnetometer_service.dart';
import 'splash_screen.dart';

/// Native measurement entry; no camera permission is required for magnetic readings.
class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});
  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> with WidgetsBindingObserver {
  final _mag = MagnetometerService();
  bool _english = false, _milligauss = false;
  String tr(String mn, String en) => _english ? en : mn;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_mag.start());
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(_mag.stop());
    if (state == AppLifecycleState.resumed) unawaited(_mag.start());
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mag.dispose();
    super.dispose();
  }
  String value(double? v) => v == null ? '—' : (v * (_milligauss ? 10 : 1)).toStringAsFixed(2);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ghost Lens'), actions: [
      TextButton(onPressed: () => setState(() => _english = !_english), child: Text(_english ? 'MN' : 'EN')),
    ]),
    body: SafeArea(child: AnimatedBuilder(animation: _mag, builder: (context, _) {
      final sample = _mag.latest;
      final unit = _milligauss ? 'mG' : 'µT';
      final ready = sample != null && _mag.status == MagStatus.live;
      return ListView(padding: const EdgeInsets.all(20), children: [
        Text(tr('БОДИТ СОРОНЗОН ХЭМЖИЛТ', 'REAL MAGNETIC MEASUREMENT')),
        const SizedBox(height: 16),
        Text('${value(ready ? _mag.total : null)} $unit', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold)),
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
          await _mag.stop();
          if (!context.mounted) return;
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SplashScreen()));
          if (mounted) unawaited(_mag.start());
        }, child: Text(tr('Камер / AR тоглоом нээх', 'Open camera / AR game'))),
      ]);
    })),
  );
}
