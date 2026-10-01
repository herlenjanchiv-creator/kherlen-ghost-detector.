import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../widgets/ghost_sprite.dart';

const _album = 'GhostDetector';

/// Зураг авах мөчийн сүнсний байрлал (preview-ийн 0..1 координатад)
class GhostSnapshot {
  final double cx, cy, h; // төв ба өндөр (preview өндрийн хувь)
  final double opacity, rage, glow, time;
  const GhostSnapshot({
    required this.cx,
    required this.cy,
    required this.h,
    required this.opacity,
    required this.rage,
    required this.glow,
    required this.time,
  });
}

/// "Нотлох баримт" — зураг, видеог галерейд хадгална.
class EvidenceSaver {
  static Future<bool> ensureAccess() async {
    try {
      if (await Gal.hasAccess(toAlbum: true)) return true;
      return await Gal.requestAccess(toAlbum: true);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> saveVideo(String path) async {
    if (!await ensureAccess()) return false;
    try {
      await Gal.putVideo(path, album: _album);
      return true;
    } catch (e) {
      debugPrint('Видео хадгалах алдаа: $e');
      return false;
    }
  }

  /// Зураг + шүүлтүүр + сүнс + цагийн тэмдгийг нэгтгэж PNG болгоно.
  static Future<bool> savePhoto({
    required XFile file,
    required bool mirror,
    required int sensorOrientation,
    List<double>? colorMatrix,
    GhostSpriteSheet? sheet,
    GhostSnapshot? ghost,
    List<String>? stampLines,
  }) async {
    if (!await ensureAccess()) return false;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final photo = (await codec.getNextFrame()).image;

      // Апп portrait-д түгжигдсэн. Хэрэв зураг хэвтээ (EXIF эргэлтгүй) ирвэл эргүүлнэ.
      final landscape = photo.width > photo.height;
      final rot = landscape ? sensorOrientation % 360 : 0;
      final pw = landscape ? photo.height : photo.width;
      final ph = landscape ? photo.width : photo.height;

      final scale = math.min(1.0, 3000 / math.max(pw, ph));
      final outW = (pw * scale).round(), outH = (ph * scale).round();

      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()));

      // --- Камерын зураг (дэлгэц дээр харсантай ижил: урд камер толин) ---
      canvas.save();
      if (mirror) {
        canvas.translate(outW.toDouble(), 0);
        canvas.scale(-1, 1);
      }
      canvas.translate(outW / 2, outH / 2);
      canvas.rotate(rot * math.pi / 180);
      final dw = (rot == 90 || rot == 270) ? outH : outW;
      final dh = (rot == 90 || rot == 270) ? outW : outH;
      final paint = Paint()..filterQuality = FilterQuality.high;
      if (colorMatrix != null) paint.colorFilter = ColorFilter.matrix(colorMatrix);
      canvas.drawImageRect(
        photo,
        Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: dw.toDouble(), height: dh.toDouble()),
        paint,
      );
      canvas.restore();

      // --- Сүнс ---
      if (sheet != null && ghost != null && ghost.opacity > 0.02) {
        final h = ghost.h * outH;
        sheet.paint(
          canvas,
          Rect.fromCenter(
              center: Offset(ghost.cx * outW, ghost.cy * outH),
              width: h * sheet.aspect,
              height: h),
          ghost.time,
          opacity: ghost.opacity,
          rage: ghost.rage,
          glow: ghost.glow,
        );
      }

      // --- Цагийн тэмдэг ---
      if (stampLines != null && stampLines.isNotEmpty) {
        final fs = outW * 0.032;
        final tp = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: stampLines.join('\n'),
            style: TextStyle(
              color: const Color(0xFFFFB000),
              fontSize: fs,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              height: 1.3,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))],
            ),
          ),
        )..layout(maxWidth: outW * 0.94);
        tp.paint(canvas, Offset(outW * 0.03, outH - tp.height - outH * 0.025));
      }

      final img = await rec.endRecording().toImage(outW, outH);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      photo.dispose();
      img.dispose();
      if (data == null) return false;
      await Gal.putImageBytes(data.buffer.asUint8List(), album: _album);
      return true;
    } catch (e) {
      debugPrint('Зураг хадгалах алдаа: $e');
      return false;
    }
  }
}
