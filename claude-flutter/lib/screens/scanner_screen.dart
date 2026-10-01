import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../game/ghost_engine.dart';
import '../services/audio_fx.dart';
import '../services/camera_manager.dart';
import '../services/data_logger.dart';
import '../services/evidence.dart';
import '../services/magnetometer_service.dart';
import '../services/orientation_service.dart';
import '../widgets/ghost_sprite.dart';
import '../widgets/hud_widgets.dart';

/// Камерын харагдах горим (GhostStop-ийн камерууд шиг)
enum VisionMode { normal, night, spectrum }

extension VisionText on VisionMode {
  String get label => switch (this) {
        VisionMode.normal => 'Энгийн',
        VisionMode.night => 'Шөнийн',
        VisionMode.spectrum => 'Бүрэн спектр',
      };

  /// Өнгөний матриц. Утасны камерт IR шүүлтүүр байдаг тул энэ нь
  /// жинхэнэ IR / full-spectrum биш, харин тухайн хэв маягийн дүрслэл.
  List<double>? get matrix => switch (this) {
        VisionMode.normal => null,
        VisionMode.night => const [
            0.10, 0.20, 0.04, 0, 0,
            0.55, 1.10, 0.22, 0, 18,
            0.10, 0.20, 0.04, 0, 0,
            0, 0, 0, 1, 0,
          ],
        VisionMode.spectrum => const [
            1.25, 0.25, 0.00, 0, 12,
            0.10, 0.55, 0.10, 0, 0,
            0.35, 0.20, 1.15, 0, 18,
            0, 0, 0, 1, 0,
          ],
      };
}

class ScannerScreen extends StatefulWidget {
  /// true бол хэмжилтийн горимоор эхэлнэ (сүнсний тоглоомгүй)
  final bool measure;
  const ScannerScreen({super.key, this.measure = false});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final CameraManager _cam = CameraManager();
  final OrientationService _orient = OrientationService();
  final GhostEngine _engine = GhostEngine();
  final AudioFx _audio = AudioFx();
  final DataLogger _logger = DataLogger();
  final MagnetometerService _mag = MagnetometerService();
  late bool _measure = widget.measure;
  bool _autoBaselineTried = false;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final _GhostPose _pose = _GhostPose();
  final math.Random _rnd = math.Random();

  late final Ticker _ticker;
  StreamSubscription<void>? _stepSub, _shakeSub;
  GhostSpriteSheet? _sheet;

  Duration _last = Duration.zero;
  double _nextTick = 0, _noSensorTime = 0;
  int _seenSpeech = 0, _seenRage = 0;
  double _flash = 0; // дайралтын гэрэлтэлт 0..1
  bool _permDenied = false;
  bool _soundOn = true;
  VisionMode _vision = VisionMode.normal;
  bool _laser = false;
  bool _stampOn = true; // цагийн тэмдэг
  bool _saving = false;
  double _shutter = 0; // зураг авах үеийн цагаан анивчилт
  bool _showGraph = true;
  bool _torchAlert = false; // spike үед гар чийдэн анивчуулах
  double _alertBar = 0; // дээд талын цагаан гэрлэн самбар
  double _logAcc = 0;
  V3? _prevG;
  int _seenFlag = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GhostSpriteSheet.load().then((s) {
      if (mounted) setState(() => _sheet = s);
    });
    _orient.start();
    _stepSub = _orient.steps.listen((_) {
      if (!_measure) _engine.onStep();
    });
    _shakeSub = _orient.shakes.listen((_) {
      if (_measure) return;
      _engine.onShake();
      HapticFeedback.mediumImpact();
    });
    _audio.init();
    _logger.start();
    _mag.isStill = () => _orient.isStill;
    _engine.mag = _mag;
    _mag.start();
    _ticker = createTicker(_onTick)..start();
    _startCamera();
  }

  Future<void> _startCamera() async {
    final st = await Permission.camera.request();
    if (!mounted) return;
    if (!st.isGranted) {
      setState(() => _permDenied = true);
      return;
    }
    setState(() => _permDenied = false);
    await _cam.init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Зөвхөн "paused" үед камерыг суллана. "inactive" нь зөвшөөрлийн цонх
    // (микрофон, галерей) гарахад ч ирдэг тул бичлэг тасрахаас сэргийлнэ.
    if (state == AppLifecycleState.paused) {
      if (_cam.recording) {
        _stopAndSaveVideo().whenComplete(_cam.suspend);
      } else {
        _cam.suspend();
      }
      _audio.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (_permDenied) {
        _startCamera(); // тохиргооноос зөвшөөрөл өгөөд буцаж ирсэн байж болно
      } else {
        _cam.resume();
      }
      _audio.resume();
    }
  }

  void _onTick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.016
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1).toDouble();
    _last = now;
    _time.value = now.inMicroseconds / 1e6;

    if (!_orient.ready) {
      _noSensorTime += dt;
    }
    if (_measure) {
      _engine.updateViewOnly(_orient, front: _cam.isFront);
    } else {
      _engine.update(dt, _orient, front: _cam.isFront);
    }

    // Хөдөлгөөн мэдрэгч: утас тогтвортой үед л (эс бөгөөс бүх дүрс хөдөлнө)
    _cam.motionEnabled = _cam.ready && _orient.isStill;
    if (_cam.motionEnabled) {
      if (_measure) {
        _engine.motionLevel = _cam.motionLevel;
      } else {
        _engine.onMotion(_cam.motionLevel, _cam.motionX);
      }
    } else {
      _engine.motionLevel = 0;
    }

    // EMF товшилт (хэмжигчийн дуу) — EMF өндөр байх тусам хурдан
    final t = _time.value;
    if (!_measure && (_engine.phase == Phase.searching || _engine.phase == Phase.encounter)) {
      if (t >= _nextTick) {
        _audio.tick();
        _nextTick = t + (1.1 - _engine.emf * 1.04).clamp(0.06, 1.1);
      }
    }
    _audio.setLevel(_measure ? 0 : _engine.emf);

    // Сүнс шинэ үг хэлэх
    if (!_measure && _engine.speechSerial != _seenSpeech) {
      _seenSpeech = _engine.speechSerial;
      if (_engine.mood == Mood.angry) {
        _audio.growl();
        HapticFeedback.heavyImpact();
      } else {
        _audio.whisper();
        HapticFeedback.lightImpact();
      }
    }

    // Дайралт
    if (!_measure && _engine.rageSerial != _seenRage) {
      _seenRage = _engine.rageSerial;
      _flash = 1;
      _audio.sting();
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 180), HapticFeedback.heavyImpact);
      Future.delayed(const Duration(milliseconds: 380), HapticFeedback.heavyImpact);
    }
    if (_flash > 0) _flash = math.max(0, _flash - dt * 0.9);
    if (_shutter > 0) _shutter = math.max(0, _shutter - dt * 4);
    if (_alertBar > 0) _alertBar = math.max(0, _alertBar - dt * 1.2);

    // ---- Өгөгдөл бүртгэл: секундэд 10 удаа ----
    // Соронзон мэдрэгч анх ажиллахад суурийг автоматаар хэмжинэ
    if (!_autoBaselineTried && _mag.status == MagStatus.live && _mag.baseline == null && _orient.isStill) {
      _autoBaselineTried = true;
      _measureBaseline();
    }

    _logAcc += dt;
    if (_logAcc >= 0.1 && _orient.ready) {
      _logAcc = 0;
      final g = _orient.gravity.normalized();
      final prev = _prevG;
      _prevG = g;
      final dot = prev == null ? 1.0 : (g.x * prev.x + g.y * prev.y + g.z * prev.z).clamp(-1.0, 1.0);
      final tilt = math.acos(dot) * 180 / math.pi;
      final ms = _mag.latest, mb = _mag.baseline;
      final auto = _logger.add(
        mag: ms == null
            ? null
            : MagRow(
                x: ms.x,
                y: ms.y,
                z: ms.z,
                total: ms.total,
                baseline: mb?.total,
                delta: _mag.delta,
                sigma: mb?.sigma,
                threshold: mb == null ? null : _mag.threshold,
                accuracy: ms.accuracy.name,
                source: ms.source,
              ),
        magAnomaly: _mag.anomaly,
        mode: _measure ? 'measure' : 'live',
        ghost: _measure ? null : _engine.emf,
        vib: _orient.takeVibration(),
        motion: _cam.motionEnabled ? _cam.motionLevel : 0,
        tilt: tilt,
        heading: _engine.viewHeading,
        ghostDistance: _measure ? null : _engine.distance,
        mood: _measure ? null : _engine.mood.name,
      );
      if (auto != null) _engine.addLog('⚑ $auto');
    }

    // ---- Spike flag: гэрэл + дуу + чичиргээ ----
    if (_logger.flagSerial != _seenFlag) {
      _seenFlag = _logger.flagSerial;
      _alertBar = 1;
      _audio.flag();
      HapticFeedback.heavyImpact();
      if (_torchAlert && !_cam.isFront && !_cam.torch && !_cam.busy) {
        _cam.setTorch(true);
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _cam.setTorch(false);
        });
      }
    }
  }

  Future<void> _measureBaseline() async {
    final b = await _mag.measureBaseline();
    if (b == null) {
      _toast(_mag.baselineWarning ?? 'Суурь хэмжиж чадсангүй');
      return;
    }
    _logger.note('BASELINE: ${b.total.toStringAsFixed(2)} µT ±${b.sigma.toStringAsFixed(2)} (${b.samples} утга${b.wasStill ? '' : ', утас хөдөлсөн'})');
    _engine.addLog('Суурь: ${b.total.toStringAsFixed(1)} µT ±${b.sigma.toStringAsFixed(2)}');
    if (_mag.baselineWarning != null) _toast(_mag.baselineWarning!);
  }

  Future<void> _shareLog() async {
    final f = await _logger.flush();
    if (f == null) {
      _toast('Лог файл үүсээгүй байна');
      return;
    }
    try {
      await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')],
          text: 'Сүнс илрүүлэгч — өгөгдлийн лог (${_logger.rows} мөр)');
    } catch (e) {
      _toast('Хуваалцаж чадсангүй: $e');
    }
  }

  // ======================= Бичлэг / зураг =======================

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _stampNow() {
    final d = DateTime.now();
    return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
  }

  Future<void> _takePhoto() async {
    if (_saving || _cam.busy || _cam.recording || !_cam.ready) return;
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    // Товчлуур дарсан мөчийн байдлыг хадгална
    final e = _engine;
    final ghost = (!_measure && _pose.viewW > 0 && _pose.opacity > 0.02)
        ? GhostSnapshot(
            cx: _pose.x / _pose.viewW,
            cy: _pose.y / _pose.viewH,
            h: _pose.h / _pose.viewH,
            opacity: _pose.opacity,
            rage: e.rageVisual,
            glow: 0.35 + 0.4 * e.rageVisual,
            time: _time.value,
          )
        : null;
    final stamp = _stampOn
        ? [
            '● ${_stampNow()}',
            _mag.latest == null
                ? 'Соронзон: мэдрэгч байхгүй  •  ${e.viewHeading.toStringAsFixed(0)}°'
                : '|B| ${_mag.latest!.total.toStringAsFixed(1)} µT${_mag.delta == null ? '' : '  Δ${_mag.delta! >= 0 ? '+' : ''}${_mag.delta!.toStringAsFixed(1)} µT'}  •  ${e.viewHeading.toStringAsFixed(0)}°',
            if (!_measure && e.phase == Phase.encounter && e.encounterReady)
              '${e.profile.name}, ${e.profile.gender}, ~${e.profile.age} нас — ${e.mood.label}',
          ]
        : null;
    final mirror = _cam.isFront;
    final orientation = _cam.controller?.description.sensorOrientation ?? 90;
    final matrix = _vision.matrix;

    final file = await _cam.takePhoto();
    _shutter = 1;
    if (file == null) {
      _toast('Зураг авч чадсангүй');
    } else {
      final ok = await EvidenceSaver.savePhoto(
        file: file,
        mirror: mirror,
        sensorOrientation: orientation,
        colorMatrix: matrix,
        sheet: _sheet,
        ghost: ghost,
        stampLines: stamp,
      );
      _toast(ok ? 'Зураг галерейд хадгалагдлаа (GhostDetector)' : 'Хадгалж чадсангүй — галерейн зөвшөөрлийг шалгана уу');
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _toggleRecord() async {
    if (_saving || (_cam.busy && !_cam.recording)) return;
    if (_cam.recording) {
      await _stopAndSaveVideo();
      return;
    }
    HapticFeedback.mediumImpact();
    if (!_cam.audioEnabled) {
      // Видеонд дуу (EVP) бичих — татгалзвал дуугүй бичнэ
      final st = await Permission.microphone.request();
      if (st.isGranted) await _cam.enableAudio();
    }
    final ok = await _cam.startRecording();
    if (!ok) _toast('Бичлэг эхлүүлж чадсангүй');
  }

  Future<void> _stopAndSaveVideo() async {
    setState(() => _saving = true);
    final f = await _cam.stopRecording();
    if (f != null) {
      final ok = await EvidenceSaver.saveVideo(f.path);
      _toast(ok ? 'Видео галерейд хадгалагдлаа (GhostDetector)' : 'Видео хадгалж чадсангүй');
    } else {
      _toast('Бичлэг хадгалагдсангүй');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xF0101614),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => AnimatedBuilder(
        animation: _cam,
        builder: (ctx, _) {
          const presets = {
            ResolutionPreset.high: '720p',
            ResolutionPreset.veryHigh: '1080p',
            ResolutionPreset.ultraHigh: '4K',
          };
          final maxBoost = math.min(2.0, _cam.maxExposure);
          final canBoost = _cam.canExpose && maxBoost > 0;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
              child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Камерын тохиргоо',
                      style: TextStyle(color: kCyan, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  const Text('Нягтрал (зураг ба видео)', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    for (final p in presets.entries)
                      ChoiceChip(
                        label: Text(p.value),
                        selected: _cam.preset == p.key,
                        onSelected: _cam.recording ? null : (_) => _cam.setPreset(p.key),
                      ),
                  ]),
                  const Text('Өндөр нягтрал илүү их зай, батарей зарцуулна',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 14),
                  Row(children: [
                    const Text('Гэрэлтүүлэг нэмэх', style: TextStyle(color: Colors.white70)),
                    const Spacer(),
                    Text('+${_cam.exposure.toStringAsFixed(1)}',
                        style: const TextStyle(color: Colors.white)),
                  ]),
                  Slider(
                    value: _cam.exposure.clamp(0.0, canBoost ? maxBoost : 0.0).toDouble(),
                    min: 0,
                    max: canBoost ? maxBoost : 1,
                    divisions: canBoost ? (maxBoost * 10).round().clamp(1, 20) : null,
                    onChanged: canBoost ? (v) => _cam.setExposure(v) : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Гар чийдэн'),
                    subtitle: Text(_cam.isFront ? 'Урд камерт байхгүй' : 'Харанхуйд гэрэлтүүлнэ',
                        style: const TextStyle(fontSize: 11)),
                    value: _cam.torch,
                    onChanged: _cam.isFront ? null : (v) => _cam.setTorch(v),
                  ),
                  StatefulBuilder(
                    builder: (ctx, setLocal) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Хэмжилтийн горим'),
                      subtitle: const Text('Сүнс, профайл, тоглоомын дууг нууж зөвхөн бодит утга харуулна',
                          style: TextStyle(fontSize: 11)),
                      value: _measure,
                      onChanged: (v) {
                        setState(() {
                          _measure = v;
                          _pose.opacity = 0;
                        });
                        if (!v) _engine.recalibrate();
                        _logger.note(v ? 'MODE: measure' : 'MODE: live');
                        setLocal(() {});
                      },
                    ),
                  ),
                  StatefulBuilder(
                    builder: (ctx, setLocal) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Цагийн тэмдэг'),
                      subtitle: const Text('Огноо, цаг, EMF-ийг зураг дээр бичнэ',
                          style: TextStyle(fontSize: 11)),
                      value: _stampOn,
                      onChanged: (v) {
                        setState(() => _stampOn = v);
                        setLocal(() {});
                      },
                    ),
                  ),
                  const Divider(color: Colors.white12),
                  const Text('Өгөгдөл бүртгэл ба анхааруулга',
                      style: TextStyle(color: kCyan, fontSize: 14, fontWeight: FontWeight.bold)),
                  StatefulBuilder(
                    builder: (ctx, setLocal) => Column(children: [
                      Row(children: [
                        const Text('Spike мэдрэмж', style: TextStyle(color: Colors.white70)),
                        const Spacer(),
                        Text('${(_logger.sensitivity * 100).round()}%',
                            style: const TextStyle(color: Colors.white)),
                      ]),
                      Slider(
                        value: _logger.sensitivity,
                        onChanged: (v) => setLocal(() => _logger.sensitivity = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Гар чийдэнгээр анхааруулах'),
                        subtitle: const Text('Утсаа холдуулж тавихад spike бүрт гэрэл анивчина',
                            style: TextStyle(fontSize: 11)),
                        value: _torchAlert,
                        onChanged: (v) {
                          setState(() => _torchAlert = v);
                          setLocal(() {});
                        },
                      ),
                    ]),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.table_chart, color: kCyan),
                    title: const Text('Лог файл хуваалцах (CSV)'),
                    subtitle: Text('${_logger.rows} мөр • Excel, Google Sheets-д нээгдэнэ',
                        style: const TextStyle(fontSize: 11)),
                    onTap: _shareLog,
                  ),
                  if (_cam.canCycleLens)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.camera, color: kCyan),
                      title: Text('Линз солих (${_cam.lensIndex + 1}/${_cam.lensCount})'),
                      subtitle: const Text('Өргөн өнцгийн линз байвал түүгээр харна',
                          style: TextStyle(fontSize: 11)),
                      onTap: _cam.recording ? null : _cam.cycleLens,
                    ),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _stepSub?.cancel();
    _shakeSub?.cancel();
    _orient.dispose();
    _cam.dispose();
    _audio.dispose();
    _logger.dispose();
    _mag.dispose();
    _engine.dispose();
    _time.dispose();
    super.dispose();
  }

  // ======================= UI =======================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: Listenable.merge([_cam, _engine]),
        builder: (context, _) {
          final e = _engine;
          final angry = !_measure && e.phase == Phase.encounter && e.mood == Mood.angry;
          final shake = (angry ? 3.0 : 0.0) + _flash * 14;
          final offset = shake > 0
              ? Offset((_rnd.nextDouble() - 0.5) * shake, (_rnd.nextDouble() - 0.5) * shake)
              : Offset.zero;

          return Stack(
            fit: StackFit.expand,
            children: [
              Transform.translate(offset: offset, child: _cameraLayer()),
              _vignette(angry),
              if (_flash > 0)
                IgnorePointer(
                  child: Container(
                    color: Color.lerp(Colors.white, kRed, 1 - _flash)!
                        .withOpacity((_flash * 0.85).clamp(0.0, 1.0)),
                  ),
                ),
              if (_alertBar > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(_alertBar),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.white.withOpacity(_alertBar * 0.9),
                              blurRadius: 30,
                              spreadRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_shutter > 0)
                IgnorePointer(
                  child: ColoredBox(color: Colors.white.withOpacity(_shutter * 0.8)),
                ),
              if (!_measure) _offscreenHint(),
              SafeArea(
                child: Column(
                  children: [
                    _topBar(),
                    _modeRow(),
                    if (!_measure && e.phase == Phase.encounter)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: _profileCard(),
                      ),
                    const Spacer(),
                    if (!_measure && e.phase == Phase.encounter && e.speech.isNotEmpty && e.encounterReady)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: _speechBox(),
                      ),
                    // Жижиг дэлгэцэнд багтаахын тулд сүнстэй уулзах үед графикийг нууна (бүртгэл үргэлжилнэ)
                    if (_showGraph && (_measure || e.phase != Phase.encounter))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: HudPanel(
                          padding: const EdgeInsets.all(8),
                          child: LiveGraph(logger: _logger),
                        ),
                      ),
                    _captureRow(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: _bottomHud(),
                    ),
                  ],
                ),
              ),
              if (!_measure && e.phase == Phase.calibrating) _calibrationOverlay(),
              if (_cam.error != null || _permDenied) _errorOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _cameraLayer() {
    final c = _cam.controller;
    if (c == null || !c.value.isInitialized || c.value.previewSize == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: kCyan)),
      );
    }
    final p = c.value.previewSize!; // landscape хэмжээ
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: p.height,
          height: p.width,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_vision.matrix != null)
                ColorFiltered(
                  colorFilter: ColorFilter.matrix(_vision.matrix!),
                  child: CameraPreview(c),
                )
              else
                CameraPreview(c),
              // Камерын дүрсийг бага зэрэг харанхуй, хүйтэн өнгөтэй болгоно
              if (_vision == VisionMode.normal)
                const IgnorePointer(
                  child: ColoredBox(color: Color(0x33001A12)),
                ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _ScenePainter(
                    engine: _engine,
                    cam: _cam,
                    sheet: _sheet,
                    time: _time,
                    pose: _pose,
                    mirror: _cam.isFront,
                    measure: _measure,
                    vision: _vision,
                    laser: _laser,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vignette(bool angry) => IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.0,
              colors: [
                Colors.transparent,
                (angry ? kRed : Colors.black).withOpacity(angry ? 0.45 : 0.55),
              ],
              stops: const [0.55, 1.0],
            ),
          ),
        ),
      );

  Widget _topBar() {
    final e = _engine;
    final (String text, Color col) = _measure
        ? (_mag.anomaly ? 'ХЭМЖИЛТ · ӨӨРЧЛӨЛТ' : 'ХЭМЖИЛТИЙН ГОРИМ', _mag.anomaly ? kRed : kCyan)
        : switch (e.phase) {
      Phase.calibrating => ('ТОХИРУУЛЖ БАЙНА', kAmber),
      Phase.searching => ('ХАЙЖ БАЙНА', kCyan),
      Phase.encounter => (e.mood == Mood.angry ? 'АЮУЛ!' : 'СҮНС ИЛЭРСЭН', e.mood == Mood.angry ? kRed : kAmber),
      Phase.vanished => ('АЛГА БОЛОВ', kRed),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          _iconBtn(Icons.arrow_back, () => Navigator.of(context).maybePop()),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: col),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 9, color: col),
              const SizedBox(width: 6),
              Text(text,
                  style: TextStyle(
                      color: col, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ]),
          ),
          const Spacer(),
          _iconBtn(_soundOn ? Icons.volume_up : Icons.volume_off, () {
            setState(() => _soundOn = !_soundOn);
            _audio.setEnabled(_soundOn);
          }),
          _iconBtn(Icons.tune, () {
            _engine.recalibrate();
            _measureBaseline();
          }),
          if (_cam.canSwitch)
            _iconBtn(
              _cam.busy ? Icons.hourglass_top : Icons.cameraswitch,
              _cam.busy ? null : _cam.switchCamera,
            ),
        ],
      ),
    );
  }

  Widget _captureRow() {
    final rec = _cam.recording;
    final start = _cam.recordStart;
    final secs = start == null ? 0 : DateTime.now().difference(start).inSeconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_stampOn || rec)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              rec ? '● REC ${_two(secs ~/ 60)}:${_two(secs % 60)}   ${_stampNow()}' : _stampNow(),
              style: TextStyle(
                color: rec ? kRed : const Color(0xFFFFB000),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _iconBtn(Icons.settings, _openSettings),
            _iconBtn(Icons.flag, () {
              _logger.manualFlag();
              _engine.addLog('⚑ Гар тэмдэг тавив');
            }),
            // Зураг
            GestureDetector(
              onTap: _takePhoto,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  color: (_saving || rec) ? Colors.white24 : Colors.white.withOpacity(0.15),
                ),
                child: _saving && !rec
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                      )
                    : const Icon(Icons.photo_camera, color: Colors.white),
              ),
            ),
            // Видео
            GestureDetector(
              onTap: _toggleRecord,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kRed, width: 3),
                  color: Colors.black45,
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: rec ? 20 : 34,
                    height: rec ? 20 : 34,
                    decoration: BoxDecoration(
                      color: kRed,
                      borderRadius: BorderRadius.circular(rec ? 4 : 17),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ]),
    );
  }

  Widget _modeRow() {
    final still = _cam.motionEnabled;
    final moving = still && _engine.motionLevel > 0.015;
    Widget chip(VisionMode m) {
      final on = _vision == m;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () => setState(() => _vision = m),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: on ? kCyan.withOpacity(0.25) : Colors.black45,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? kCyan : Colors.white24),
            ),
            child: Text(m.label,
                style: TextStyle(
                    color: on ? kCyan : Colors.white70,
                    fontSize: 11,
                    fontWeight: on ? FontWeight.bold : FontWeight.normal)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
      child: Row(children: [
        for (final m in VisionMode.values) chip(m),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _showGraph = !_showGraph),
          child: Container(
            padding: const EdgeInsets.all(6),
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: _showGraph ? kCyan.withOpacity(0.25) : Colors.black45,
              shape: BoxShape.circle,
              border: Border.all(color: _showGraph ? kCyan : Colors.white24),
            ),
            child: const Icon(Icons.show_chart, size: 16, color: Colors.white),
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => _laser = !_laser),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _laser ? const Color(0x5539FF6A) : Colors.black45,
              shape: BoxShape.circle,
              border: Border.all(color: _laser ? const Color(0xFF39FF6A) : Colors.white24),
            ),
            child: const Icon(Icons.grid_on, size: 16, color: Colors.white),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: still
              ? 'Хөдөлгөөн мэдрэгч идэвхтэй'
              : 'Утсаа тогтвортой тавьбал хөдөлгөөн мэдрэгч асна',
          child: Icon(
            Icons.directions_run,
            size: 20,
            color: moving ? kRed : (still ? const Color(0xFF39FF6A) : Colors.white30),
          ),
        ),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        style: IconButton.styleFrom(backgroundColor: Colors.black45),
      );

  Widget _profileCard() {
    final e = _engine;
    final p = e.profile;
    final angry = e.mood == Mood.angry;
    final col = angry ? kRed : kCyan;
    const label = TextStyle(color: Colors.white54, fontSize: 11);
    const value = TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600);

    Widget field(String l, String v, {TextStyle? style}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: label),
            const SizedBox(height: 2),
            Text(v, style: style ?? value),
          ]),
        );

    final steps = [
      'Энергийн спектр',
      'Дүрс бүтэц',
      'Дуу хоолойн давтамж',
    ];

    return HudPanel(
      color: col,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.blur_on, color: col, size: 18),
            const SizedBox(width: 6),
            Text('СҮНСНИЙ ПРОФАЙЛ',
                style: TextStyle(color: col, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const Spacer(),
            Text('${e.distance.toStringAsFixed(1)} м',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
          const Divider(color: Colors.white24, height: 14),
          if (!e.encounterReady) ...[
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${e.reveal > (i + 1) / (steps.length + 0.5) ? "✓" : "…"}  ${steps[i]} шинжилж байна',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: e.reveal,
              color: col,
              backgroundColor: Colors.white12,
              minHeight: 4,
            ),
          ] else ...[
            Row(children: [field('Нэр', p.name), field('Хүйс', p.gender)]),
            const SizedBox(height: 8),
            Row(children: [field('Нас', '~${p.age}'), field('Амьдарч байсан үе', p.era)]),
            const SizedBox(height: 8),
            Row(children: [
              field('Сэтгэл санаа', e.mood.label,
                  style: TextStyle(
                      color: angry ? kRed : (e.mood == Mood.irritated ? kAmber : Colors.white),
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Уурын түвшин', style: label),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: e.anger,
                      minHeight: 7,
                      backgroundColor: Colors.white12,
                      color: Color.lerp(kAmber, kRed, e.anger),
                    ),
                  ),
                ]),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _speechBox() {
    final angry = _engine.mood == Mood.angry;
    return HudPanel(
      color: angry ? kRed : Colors.white70,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Icon(Icons.graphic_eq, color: angry ? kRed : Colors.white70),
        const SizedBox(width: 10),
        Expanded(
          child: TypewriterText(
            text: '«${_engine.speech}»',
            serial: _engine.speechSerial,
            style: TextStyle(
              color: angry ? kRed : Colors.white,
              fontSize: angry ? 19 : 16,
              fontStyle: FontStyle.italic,
              fontWeight: angry ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _bottomHud() {
    final e = _engine;
    return HudPanel(
      color: e.anomaly ? kAmber : kCyan,
      child: Row(
        children: [
          if (_measure)
            SizedBox(width: 112, child: _measureReadouts())
          else
            SizedBox(width: 104, height: 104, child: GhostRadar(engine: e)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Бодит хэмжилт
                MagPanel(mag: _mag, onBaseline: _measureBaseline),
                const SizedBox(height: 6),
                // Тоглоомын үзүүлэлт — физик нэгжгүй
                if (!_measure) ...[
                  const Text('Сүнсний дохио (тоглоом)', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  const SizedBox(height: 3),
                  EmfLeds(level: e.emf),
                ],
                const SizedBox(height: 4),
                Text(
                  'Чиглэл: ${e.viewHeading.toStringAsFixed(0)}°  •  ${_cam.isFront ? "Урд камер" : "Арын камер"}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  e.log.isEmpty ? '' : '› ${e.log.first}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kCyan, fontSize: 11),
                ),
                Text(_measure ? 'Хэмжилтийн горим — зөвхөн бодит мэдрэгчийн утга' : 'Зугаа цэнгэлийн зориулалттай',
                    style: TextStyle(color: Colors.white24, fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Хэмжилтийн горимын бодит утгууд (мэдрэгч байхгүй бол "—")
  Widget _measureReadouts() {
    final last = _logger.samples.isEmpty ? null : _logger.samples.last;
    Widget cell(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        );
    final ok = _orient.ready;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      cell('Чиглэл', ok ? '${_engine.viewHeading.toStringAsFixed(0)}°' : '—'),
      cell('Налуу', ok ? '${_engine.viewPitch.toStringAsFixed(0)}°' : '—'),
      cell('Чичиргээ', last == null ? '—' : '${last.vib.toStringAsFixed(2)} м/с²'),
      cell('Хөдөлгөөн', _cam.motionEnabled ? '${(_cam.motionLevel * 100).toStringAsFixed(1)}%' : 'тогтворжуул'),
    ]);
  }

  Widget _offscreenHint() {
    final e = _engine;
    if (!(e.phase == Phase.searching || e.phase == Phase.encounter) || e.inView) {
      return const SizedBox.shrink();
    }
    final front = _cam.isFront;
    final screenDelta = front ? -e.delta : e.delta;
    final right = screenDelta > 0;
    final behind = e.delta.abs() > 130;
    String hint = '${e.delta.abs().round()}°';
    if (behind && !front && _cam.hasFront) hint = 'Таны АРД!\nурд камер руу шилж';
    if (behind && front) hint = 'Таны ӨМНӨ!\nарын камер руу шилж';

    return Align(
      alignment: Alignment(right ? 0.95 : -0.95, -0.1),
      child: IgnorePointer(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(right ? Icons.arrow_forward_ios : Icons.arrow_back_ios,
              color: kAmber.withOpacity(0.5 + 0.5 * e.emf), size: 34),
          const SizedBox(height: 4),
          Text(hint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kAmber, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _calibrationOverlay() {
    final noSensor = !_orient.ready && _noSensorTime > 4;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: HudPanel(
          color: noSensor ? kRed : kAmber,
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(noSensor ? Icons.sensors_off : Icons.explore,
                color: noSensor ? kRed : kAmber, size: 36),
            const SizedBox(height: 10),
            Text(
              noSensor
                  ? 'Энэ утсанд соронзон мэдрэгч (компас) олдсонгүй. Радар ажиллахгүй.'
                  : 'Орчны соронзон орныг хэмжиж байна.\nУтсаа хөдөлгөлгүй барина уу...',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            if (!noSensor) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                  value: _engine.calibProgress, color: kAmber, backgroundColor: Colors.white12),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _errorOverlay() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: HudPanel(
            color: kRed,
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.no_photography, color: kRed, size: 36),
              const SizedBox(height: 10),
              Text(
                _permDenied
                    ? 'Камерын зөвшөөрөл олгогдоогүй байна.'
                    : (_cam.error ?? 'Камерын алдаа'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kRed),
                onPressed: () async {
                  if (_permDenied) {
                    final st = await Permission.camera.request();
                    if (st.isPermanentlyDenied) {
                      await openAppSettings();
                    } else {
                      _startCamera();
                    }
                  } else {
                    _cam.retry();
                  }
                },
                child: Text(_permDenied ? 'Зөвшөөрөл өгөх' : 'Дахин оролдох'),
              ),
            ]),
          ),
        ),
      );
}

/// Сүнсний дэлгэц дээрх байрлалыг зөөлөн шилжүүлэхэд хадгална
class _GhostPose {
  double x = double.nan, y = 0, h = 0, opacity = 0;
  double viewW = 0, viewH = 0; // preview координатын хэмжээ (зураг авахад)
}

/// Камерын (preview) координатад царай болон сүнсийг зурна
class _ScenePainter extends CustomPainter {
  final GhostEngine engine;
  final CameraManager cam;
  final GhostSpriteSheet? sheet;
  final ValueNotifier<double> time;
  final _GhostPose pose;
  final bool mirror;
  final VisionMode vision;
  final bool laser;
  final bool measure;

  _ScenePainter({
    required this.engine,
    required this.cam,
    required this.sheet,
    required this.time,
    required this.pose,
    required this.mirror,
    required this.vision,
    required this.laser,
    this.measure = false,
  }) : super(repaint: time);

  static final math.Random _noise = math.Random();

  @override
  void paint(Canvas canvas, Size size) {
    final e = engine;
    final t = time.value;
    pose
      ..viewW = size.width
      ..viewH = size.height;

    // ---- Шөнийн горимын "шуугиан" ----
    if (vision == VisionMode.night) {
      final np = Paint()..color = const Color(0x55B6FFB6);
      for (var i = 0; i < 140; i++) {
        canvas.drawCircle(
            Offset(_noise.nextDouble() * size.width, _noise.nextDouble() * size.height),
            _noise.nextDouble() * 1.6 + 0.4,
            np);
      }
    }

    // ---- Хөдөлгөөн илэрсэн нүднүүд ----
    final cols = CameraManager.motionCols, rows = CameraManager.motionRows;
    final cellW = size.width / cols, cellH = size.height / rows;
    final moving = <int>{...cam.motionCells};
    if (moving.isNotEmpty) {
      final mp = Paint()..color = kRed.withOpacity(0.22);
      for (final i in moving) {
        var cx = i % cols;
        if (mirror) cx = cols - 1 - cx;
        canvas.drawRect(
            Rect.fromLTWH(cx * cellW, (i ~/ cols) * cellH, cellW, cellH).deflate(1), mp);
      }
    }

    // ---- Лазер тор (SLS маягийн цэгэн тор) ----
    if (laser) {
      const gx = 14, gy = 24;
      final green = Paint()..color = const Color(0xFF6BFF6B);
      final glowP = Paint()
        ..color = const Color(0x5539FF6A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      for (var r = 0; r < gy; r++) {
        for (var c = 0; c < gx; c++) {
          var p = Offset((c + 0.5) * size.width / gx, (r + 0.5) * size.height / gy);
          var cx = (p.dx / cellW).floor().clamp(0, cols - 1).toInt();
          if (mirror) cx = cols - 1 - cx;
          final cell = (p.dy / cellH).floor().clamp(0, rows - 1).toInt() * cols + cx;
          final hit = moving.contains(cell);
          if (hit) {
            p += Offset((_noise.nextDouble() - 0.5) * 10, (_noise.nextDouble() - 0.5) * 10);
          }
          canvas.drawCircle(p, 6, hit ? (Paint()..color = kRed.withOpacity(0.5)) : glowP);
          canvas.drawCircle(p, 2.2, hit ? (Paint()..color = kRed) : green);
        }
      }
    }

    // ---- Царайнууд (ML Kit) ----
    Rect? anchor;
    final img = cam.imageSize;
    if (img != null && cam.faces.isNotEmpty) {
      final sx = size.width / img.width, sy = size.height / img.height;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kCyan.withOpacity(0.7);
      for (final f in cam.faces) {
        final b = f.boundingBox;
        var l = b.left * sx, r = b.right * sx;
        if (mirror) {
          final nl = size.width - r;
          r = size.width - l;
          l = nl;
        }
        final rect = Rect.fromLTRB(l, b.top * sy, r, b.bottom * sy);
        _brackets(canvas, rect, paint);
        if (anchor == null || rect.width > anchor.width) anchor = rect;
      }
    }

    // ---- Сүнс (хэмжилтийн горимд зурахгүй) ----
    final s = sheet;
    if (s == null || measure) return;

    double targetOpacity = 0;
    if (e.phase == Phase.encounter) {
      targetOpacity = e.inView ? 0.45 + 0.55 * e.reveal : 0;
    } else if (e.phase == Phase.searching && e.distance < 7 && e.inView) {
      targetOpacity = (7 - e.distance) / 7 * 0.35; // бүдэг "сүүдэр"
    }

    var x = size.width / 2 + (mirror ? -1 : 1) * e.delta / GhostEngine.hfov * size.width;
    var y = size.height / 2 - (e.elevation - e.viewPitch) / GhostEngine.vfov * size.height;
    var h = size.height * (1.7 / e.distance).clamp(0.22, 1.05);

    // Урд/арын камерт хүн байвал сүнсийг тэр хүний мөрөн дээгүүр ард нь байрлуулна
    if (anchor != null && e.phase == Phase.encounter && e.inView) {
      final side = anchor.center.dx < size.width / 2 ? 1.0 : -1.0;
      x = anchor.center.dx + side * anchor.width * 0.95;
      h = math.max(h, anchor.height * 3.4);
      y = anchor.bottom + anchor.height * 1.3 - h / 2;
    }

    // Зөөлөн шилжилт
    if (pose.x.isNaN) {
      pose
        ..x = x
        ..y = y
        ..h = h;
    }
    pose.x += (x - pose.x) * 0.15;
    pose.y += (y - pose.y) * 0.15;
    pose.h += (h - pose.h) * 0.1;
    pose.opacity += (targetOpacity - pose.opacity) * 0.08;

    if (pose.opacity < 0.02) return;
    // Анивчих, сүнс шиг тогтворгүй байдал
    final flicker = 0.85 + 0.15 * math.sin(t * 17) * math.sin(t * 5.3);
    final w = pose.h * s.aspect;
    final dst = Rect.fromCenter(
      center: Offset(pose.x + math.sin(t * 0.9) * w * 0.05, pose.y),
      width: w,
      height: pose.h,
    );
    s.paint(canvas, dst, t,
        opacity: (pose.opacity * flicker).clamp(0.0, 1.0),
        rage: e.rageVisual,
        glow: 0.35 + 0.4 * e.rageVisual);
  }

  void _brackets(Canvas c, Rect r, Paint p) {
    final k = r.width * 0.2;
    final path = Path()
      ..moveTo(r.left, r.top + k)..lineTo(r.left, r.top)..lineTo(r.left + k, r.top)
      ..moveTo(r.right - k, r.top)..lineTo(r.right, r.top)..lineTo(r.right, r.top + k)
      ..moveTo(r.right, r.bottom - k)..lineTo(r.right, r.bottom)..lineTo(r.right - k, r.bottom)
      ..moveTo(r.left + k, r.bottom)..lineTo(r.left, r.bottom)..lineTo(r.left, r.bottom - k);
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_ScenePainter old) => true;
}
