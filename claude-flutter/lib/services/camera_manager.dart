import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Урд/арын камерыг найдвартай удирдана:
///  • арын болон урд камерыг lensDirection-оор нь сонгоно (индексээр биш)
///  • солих үед давхар эхлүүлэхээс сэргийлсэн түгжээтэй
///  • апп арын дэвсгэрт ороход камерыг суллаж, буцаж ирэхэд дахин нээнэ
///  • эхлүүлэхэд алдаа гарвал бага нягтралаар дахин оролдоно
///  • NV21 / YUV420 (3 plane) / BGRA8888 форматыг бүгдийг ML Kit-д бэлдэнэ
class CameraManager extends ChangeNotifier {
  CameraController? controller;
  CameraDescription? _front;
  final List<CameraDescription> _backs = []; // үндсэн, өргөн өнцөг, теле г.м.
  int _backIdx = 0;
  bool useFront = false;
  bool busy = false;
  String? error;

  // ---- Бичлэг / зураг / тохиргоо ----
  ResolutionPreset preset = ResolutionPreset.high; // 720p
  bool audioEnabled = false; // микрофон зөвшөөрсний дараа асна
  bool recording = false;
  DateTime? recordStart;
  double exposure = 0, minExposure = 0, maxExposure = 0;
  bool torch = false;

  List<Face> faces = [];
  Size? imageSize; // эргүүлсний дараах (portrait) хэмжээ

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableTracking: true,
      minFaceSize: 0.12,
    ),
  );
  bool _processing = false;
  int _lastDetectMs = 0;

  // ---- Хөдөлгөөн мэдрэгч (фрейм хоорондын ялгаа) ----
  static const int motionCols = 24, motionRows = 32; // portrait тор
  bool motionEnabled = false; // утас тогтвортой үед л асаана
  List<int> motionCells = const [];
  double motionLevel = 0; // хөдөлсөн нүдний хувь 0..1
  double motionX = 0.5; // хөдөлгөөний төв (0..1, толин эргүүлээгүй)
  Float32List? _prevLuma;
  int _lastMotionMs = 0;
  bool _disposed = false;
  int _generation = 0; // хуучин stream-ийн фреймийг хаях

  CameraDescription? get _back => _backs.isEmpty ? null : _backs[_backIdx % _backs.length];
  bool get hasFront => _front != null;
  bool get hasBack => _backs.isNotEmpty;
  bool get canSwitch => _front != null && _backs.isNotEmpty;
  bool get canCycleLens => !isFront && _backs.length > 1;
  int get lensIndex => _backIdx % (_backs.isEmpty ? 1 : _backs.length);
  int get lensCount => _backs.length;
  bool get isFront => controller?.description.lensDirection == CameraLensDirection.front;
  bool get ready => controller?.value.isInitialized ?? false;
  bool get canExpose => maxExposure > minExposure;

  Future<void> init() async {
    try {
      final cams = await availableCameras();
      _backs.clear();
      for (final c in cams) {
        if (c.lensDirection == CameraLensDirection.back) _backs.add(c);
        if (c.lensDirection == CameraLensDirection.front) _front ??= c;
      }
      if (_backs.isEmpty && cams.isNotEmpty && _front == null) _backs.add(cams.first);
      if (_backs.isEmpty && _front == null) {
        error = 'Төхөөрөмжид камер олдсонгүй';
        notifyListeners();
        return;
      }
      if (_backs.isEmpty) useFront = true;
    } catch (e) {
      error = 'Камерын жагсаалт авч чадсангүй: $e';
      notifyListeners();
      return;
    }
    await _open();
  }

  Future<void> switchCamera() async {
    if (!canSwitch || busy || recording) return;
    useFront = !useFront;
    await _open();
  }

  /// Арын камерын линзүүдийг ээлжлэн солино (өргөн өнцөг байвал)
  Future<void> cycleLens() async {
    if (!canCycleLens || busy || recording) return;
    _backIdx = (_backIdx + 1) % _backs.length;
    await _open();
  }

  Future<void> setPreset(ResolutionPreset p) async {
    if (p == preset || busy || recording) return;
    preset = p;
    await _open();
  }

  /// Видеонд дуу бичихийн тулд микрофонтой камер дахин нээнэ
  Future<void> enableAudio() async {
    if (audioEnabled) return;
    audioEnabled = true;
    await _open();
  }

  Future<void> setExposure(double v) async {
    exposure = v.clamp(minExposure, maxExposure).toDouble();
    notifyListeners();
    try {
      await controller?.setExposureOffset(exposure);
    } catch (_) {}
  }

  Future<void> setTorch(bool on) async {
    torch = on;
    notifyListeners();
    try {
      await controller?.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      torch = false; // урд камерт гэрэл байхгүй
      notifyListeners();
    }
  }

  /// Апп арын дэвсгэрт орох үед
  Future<void> suspend() async {
    if (recording) await stopRecording();
    final c = controller;
    controller = null;
    faces = [];
    _generation++;
    notifyListeners();
    await _close(c);
  }

  /// Апп буцаж ирэх үед
  Future<void> resume() async {
    if (controller == null && !busy && (hasBack || hasFront)) {
      await _open();
    }
  }

  Future<void> retry() async {
    error = null;
    notifyListeners();
    if (!hasBack && !hasFront) {
      await init();
    } else {
      await _open();
    }
  }

  Future<void> _close(CameraController? c) async {
    if (c == null) return;
    try {
      if (c.value.isRecordingVideo) await c.stopVideoRecording();
    } catch (_) {}
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
  }

  Future<void> _open() async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    final old = controller;
    controller = null;
    faces = [];
    _generation++;
    notifyListeners();
    await _close(old);

    final desc = (useFront ? _front : _back) ?? _back ?? _front!;
    useFront = desc.lensDirection == CameraLensDirection.front;

    final presets = <ResolutionPreset>{preset, ResolutionPreset.medium, ResolutionPreset.low};
    CameraController? c;
    for (final pr in presets) {
      c = CameraController(
        desc,
        pr,
        enableAudio: audioEnabled,
        imageFormatGroup:
            Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      try {
        await c.initialize();
        break;
      } catch (e) {
        await _close(c);
        c = null;
        error = 'Камер нээгдсэнгүй: $e';
      }
    }

    if (_disposed) {
      await _close(c);
      return;
    }
    if (c == null) {
      busy = false;
      notifyListeners();
      return;
    }

    error = null;
    controller = c;

    // Гэрэлтүүлэг (exposure boost) ба гар чийдэнг сэргээнэ
    try {
      minExposure = await c.getMinExposureOffset();
      maxExposure = await c.getMaxExposureOffset();
      exposure = exposure.clamp(minExposure, maxExposure).toDouble();
      if (exposure != 0) await c.setExposureOffset(exposure);
    } catch (_) {
      minExposure = maxExposure = exposure = 0;
    }
    if (torch) {
      try {
        await c.setFlashMode(FlashMode.torch);
      } catch (_) {
        torch = false;
      }
    }

    await _startStream(c, desc);
    busy = false;
    notifyListeners();
  }

  Future<void> _startStream(CameraController c, CameraDescription desc) async {
    _generation++;
    final gen = _generation;
    _prevLuma = null;
    try {
      if (!c.value.isStreamingImages) {
        await c.startImageStream((img) => _onFrame(img, desc, gen));
      }
    } catch (_) {
      // Stream ажиллахгүй байсан ч preview харагдсаар байна
    }
  }

  Future<void> _stopStream(CameraController c) async {
    _generation++;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
  }

  /// Зураг авна (stream-ийг түр зогсооно — олон төхөөрөмж зэрэг дэмждэггүй)
  Future<XFile?> takePhoto() async {
    final c = controller;
    if (c == null || busy || recording) return null;
    busy = true;
    notifyListeners();
    try {
      await _stopStream(c);
      return await c.takePicture();
    } catch (e) {
      debugPrint('Зураг авах алдаа: $e');
      return null;
    } finally {
      if (controller == c) await _startStream(c, c.description);
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> startRecording() async {
    final c = controller;
    if (c == null || busy || recording) return false;
    busy = true;
    notifyListeners();
    try {
      await _stopStream(c);
      faces = [];
      motionCells = const [];
      motionLevel = 0;
      await c.prepareForVideoRecording();
      await c.startVideoRecording();
      recording = true;
      recordStart = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('Бичлэг эхлүүлэх алдаа: $e');
      await _startStream(c, c.description);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<XFile?> stopRecording() async {
    final c = controller;
    if (c == null || !recording) return null;
    busy = true;
    notifyListeners();
    try {
      return await c.stopVideoRecording();
    } catch (e) {
      debugPrint('Бичлэг зогсоох алдаа: $e');
      return null;
    } finally {
      recording = false;
      recordStart = null;
      if (controller == c) await _startStream(c, c.description);
      busy = false;
      notifyListeners();
    }
  }

  void _onFrame(CameraImage img, CameraDescription desc, int gen) {
    if (_disposed || gen != _generation || recording) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!motionEnabled) {
      _prevLuma = null;
      if (motionCells.isNotEmpty || motionLevel != 0) {
        motionCells = const [];
        motionLevel = 0;
      }
    } else if (now - _lastMotionMs >= 100) {
      _lastMotionMs = now;
      try {
        _computeMotion(img, desc.sensorOrientation);
      } catch (_) {}
    }

    if (_processing) return;
    if (now - _lastDetectMs < 180) return; // ~5 Гц хангалттай
    _lastDetectMs = now;
    _processing = true;
    _detect(img, desc, gen).whenComplete(() => _processing = false);
  }

  Future<void> _detect(CameraImage img, CameraDescription desc, int gen) async {
    try {
      final rotation = InputImageRotationValue.fromRawValue(desc.sensorOrientation) ??
          InputImageRotation.rotation0deg;

      final InputImage input;
      if (Platform.isAndroid) {
        final Uint8List bytes;
        final int bytesPerRow;
        if (img.planes.length == 1) {
          bytes = img.planes.first.bytes; // NV21
          bytesPerRow = img.planes.first.bytesPerRow;
        } else {
          bytes = _yuv420ToNv21(img); // зарим төхөөрөмж 3 plane буцаадаг
          bytesPerRow = img.width;
        }
        input = InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(img.width.toDouble(), img.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: bytesPerRow,
          ),
        );
      } else {
        final p = img.planes.first;
        input = InputImage.fromBytes(
          bytes: p.bytes,
          metadata: InputImageMetadata(
            size: Size(img.width.toDouble(), img.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.bgra8888,
            bytesPerRow: p.bytesPerRow,
          ),
        );
      }

      final result = await _detector.processImage(input);
      if (_disposed || gen != _generation) return;

      final rotated = rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      imageSize = rotated
          ? Size(img.height.toDouble(), img.width.toDouble())
          : Size(img.width.toDouble(), img.height.toDouble());
      faces = result;
      notifyListeners();
    } catch (e) {
      debugPrint('ML Kit алдаа: $e');
    }
  }

  /// Portrait тор бүрийн гэрэлтэлтийг өмнөх фреймтэй харьцуулна.
  void _computeMotion(CameraImage img, int sensorRot) {
    final w = img.width, h = img.height;
    final rot = sensorRot % 360;
    final rotated = rot == 90 || rot == 270;
    final pw = rotated ? h : w, ph = rotated ? w : h;
    final plane = img.planes.first;
    final bytes = plane.bytes;
    final bpr = plane.bytesPerRow;
    final bgra = !Platform.isAndroid;

    double sample(int px, int py) {
      int x, y;
      switch (rot) {
        case 90:
          x = py;
          y = h - 1 - px;
          break;
        case 270:
          x = w - 1 - py;
          y = px;
          break;
        case 180:
          x = w - 1 - px;
          y = h - 1 - py;
          break;
        default:
          x = px;
          y = py;
      }
      if (bgra) {
        final o = y * bpr + x * 4;
        return 0.114 * bytes[o] + 0.587 * bytes[o + 1] + 0.299 * bytes[o + 2];
      }
      return bytes[y * bpr + x].toDouble(); // NV21 / YUV420 Y plane
    }

    const n = motionCols * motionRows;
    final cur = Float32List(n);
    final cw = pw / motionCols, ch = ph / motionRows;
    for (var r = 0; r < motionRows; r++) {
      for (var c = 0; c < motionCols; c++) {
        final x0 = (c * cw + cw * 0.3).toInt(), x1 = (c * cw + cw * 0.7).toInt();
        final y0 = (r * ch + ch * 0.3).toInt(), y1 = (r * ch + ch * 0.7).toInt();
        cur[r * motionCols + c] =
            (sample(x0, y0) + sample(x1, y0) + sample(x0, y1) + sample(x1, y1)) / 4;
      }
    }

    final prev = _prevLuma;
    _prevLuma = cur;
    if (prev == null) return;

    var mean = 0.0;
    final diff = Float32List(n);
    for (var i = 0; i < n; i++) {
      diff[i] = (cur[i] - prev[i]).abs();
      mean += diff[i];
    }
    mean /= n;

    final cells = <int>[];
    var sx = 0.0;
    // Гэрэл бүхэлдээ өөрчлөгдсөн (автомат экспозиция) бол тооцохгүй
    if (mean < 22) {
      final th = 16 + mean * 1.5;
      for (var i = 0; i < n; i++) {
        if (diff[i] > th) {
          cells.add(i);
          sx += (i % motionCols + 0.5) / motionCols;
        }
      }
    }
    motionCells = cells;
    motionLevel = cells.length / n;
    if (cells.isNotEmpty) motionX = sx / cells.length;
  }

  static Uint8List _yuv420ToNv21(CameraImage img) {
    final w = img.width, h = img.height;
    final yP = img.planes[0], uP = img.planes[1], vP = img.planes[2];
    final out = Uint8List(w * h + 2 * (w ~/ 2) * (h ~/ 2));
    var idx = 0;
    for (var r = 0; r < h; r++) {
      out.setRange(idx, idx + w, yP.bytes, r * yP.bytesPerRow);
      idx += w;
    }
    final uPix = uP.bytesPerPixel ?? 1, vPix = vP.bytesPerPixel ?? 1;
    for (var r = 0; r < h ~/ 2; r++) {
      for (var c = 0; c < w ~/ 2; c++) {
        out[idx++] = vP.bytes[r * vP.bytesPerRow + c * vPix];
        out[idx++] = uP.bytes[r * uP.bytesPerRow + c * uPix];
      }
    }
    return out;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    final c = controller;
    controller = null;
    _close(c);
    _detector.close();
    super.dispose();
  }
}
