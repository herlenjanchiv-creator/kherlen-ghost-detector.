import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Blender-ээс (Ghost.blend, Cycles) рендерлэсэн утааны сүнсний
/// sprite sheet. Төгсгөл/эхлэлийг crossfade хийж тасралтгүй давтана.
class GhostSpriteSheet {
  final ui.Image image;
  final int cols, count, frameW, frameH, crossfade;
  final double fps;
  final List<Offset> heads; // фрейм бүрийн "толгой"-н байрлал (0..1)

  GhostSpriteSheet._(this.image, this.cols, this.count, this.frameW,
      this.frameH, this.crossfade, this.fps, this.heads);

  double get aspect => frameW / frameH;

  static GhostSpriteSheet? _cache;
  static Future<GhostSpriteSheet>? _loading;

  static Future<GhostSpriteSheet> load() {
    if (_cache != null) return Future.value(_cache);
    return _loading ??= _load();
  }

  static Future<GhostSpriteSheet> _load() async {
    final meta = jsonDecode(
        await rootBundle.loadString('assets/ghost/ghost_sheet.json')) as Map<String, dynamic>;
    final data = await rootBundle.load('assets/ghost/ghost_sheet.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final img = (await codec.getNextFrame()).image;
    final heads = (meta['heads'] as List)
        .map((h) => Offset((h[0] as num).toDouble(), (h[1] as num).toDouble()))
        .toList();
    return _cache = GhostSpriteSheet._(
      img,
      meta['cols'] as int,
      meta['count'] as int,
      meta['frameW'] as int,
      meta['frameH'] as int,
      meta['crossfade'] as int,
      (meta['fps'] as num).toDouble(),
      heads,
    );
  }

  Rect _src(int i) {
    final c = i % cols, r = i ~/ cols;
    return Rect.fromLTWH((c * frameW).toDouble(), (r * frameH).toDouble(),
        frameW.toDouble(), frameH.toDouble());
  }

  /// [dst] тэгш өнцөгт сүнсийг зурна.
  /// [rage] 0..1 — улаан өнгө, гэрэлтэлт, нүд.
  void paint(Canvas canvas, Rect dst, double t,
      {double opacity = 1, double rage = 0, double glow = 0.5}) {
    if (opacity <= 0.01) return;
    final loop = count - crossfade;
    final f = (t * fps) % loop;
    final i = f.floor();
    final main = i + crossfade;
    double blend = 0;
    int? next;
    if (main >= loop) {
      next = main - loop;
      blend = ((main - loop) + (f - i)) / crossfade;
    }

    final tint = Color.lerp(const Color(0xFFE6FFF8), const Color(0xFFFF3B3B), rage)!;
    final glowColor = Color.lerp(const Color(0xFF39FFC8), const Color(0xFFFF1A1A), rage)!;

    void draw(int idx, double a) {
      if (a <= 0.01) return;
      final src = _src(idx);
      if (glow > 0) {
        canvas.drawImageRect(
          image,
          src,
          dst.inflate(dst.width * 0.04),
          Paint()
            ..color = Colors.white.withOpacity((a * glow).clamp(0.0, 1.0))
            ..colorFilter = ColorFilter.mode(glowColor, BlendMode.srcIn)
            ..imageFilter = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14)
            ..blendMode = BlendMode.plus,
        );
      }
      canvas.drawImageRect(
        image,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withOpacity(a.clamp(0.0, 1.0))
          ..colorFilter = ColorFilter.mode(tint, BlendMode.modulate),
      );
    }

    draw(main, opacity * (1 - blend));
    if (next != null) draw(next, opacity * blend);

    // Уурласан үед гэрэлтэх нүд
    if (rage > 0.25) {
      final h = heads[main.clamp(0, heads.length - 1)];
      final c = Offset(dst.left + h.dx * dst.width, dst.top + h.dy * dst.height);
      final r = dst.width * 0.035;
      final eyeA = ((rage - 0.25) / 0.75).clamp(0.0, 1.0) * opacity;
      for (final dx in [-r * 1.7, r * 1.7]) {
        final p = c + Offset(dx, 0);
        canvas.drawCircle(
          p,
          r * 3,
          Paint()
            ..shader = RadialGradient(colors: [
              const Color(0xFFFF2020).withOpacity(eyeA),
              const Color(0x00FF0000),
            ]).createShader(Rect.fromCircle(center: p, radius: r * 3))
            ..blendMode = BlendMode.plus,
        );
        canvas.drawOval(
          Rect.fromCenter(center: p, width: r * 1.4, height: r * 0.8),
          Paint()..color = const Color(0xFFFFE0E0).withOpacity(eyeA),
        );
      }
    }
  }
}

/// Splash дэлгэцэд ашиглах бие даасан анимейшнтэй сүнс
class AnimatedGhost extends StatefulWidget {
  final double rage;
  final double glow;
  const AnimatedGhost({super.key, this.rage = 0, this.glow = 0.6});

  @override
  State<AnimatedGhost> createState() => _AnimatedGhostState();
}

class _AnimatedGhostState extends State<AnimatedGhost>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _t = ValueNotifier(0);
  GhostSpriteSheet? _sheet;

  @override
  void initState() {
    super.initState();
    GhostSpriteSheet.load().then((s) {
      if (mounted) setState(() => _sheet = s);
    });
    _ticker = createTicker((d) => _t.value = d.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _sheet;
    if (s == null) return const SizedBox.shrink();
    return AspectRatio(
      aspectRatio: s.aspect,
      child: CustomPaint(
        painter: _SinglePainter(s, _t, widget.rage, widget.glow),
      ),
    );
  }
}

class _SinglePainter extends CustomPainter {
  final GhostSpriteSheet sheet;
  final ValueNotifier<double> t;
  final double rage, glow;
  _SinglePainter(this.sheet, this.t, this.rage, this.glow) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) =>
      sheet.paint(canvas, Offset.zero & size, t.value, rage: rage, glow: glow);

  @override
  bool shouldRepaint(_SinglePainter old) => old.rage != rage || old.glow != glow;
}
