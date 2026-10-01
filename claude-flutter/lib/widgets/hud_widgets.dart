import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/ghost_engine.dart';
import '../services/data_logger.dart';
import '../services/magnetometer_service.dart';

const kCyan = Color(0xFF39FFC8);
const kRed = Color(0xFFFF3B3B);
const kAmber = Color(0xFFFFC23B);

/// Хагас тунгалаг самбар
class HudPanel extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  const HudPanel(
      {super.key,
      required this.child,
      this.color = kCyan,
      this.padding = const EdgeInsets.all(12)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.8), width: 1.2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.18), blurRadius: 12)],
        ),
        child: child,
      );
}

/// Радар: дээд тал = камерын харж буй чиглэл
class GhostRadar extends StatefulWidget {
  final GhostEngine engine;
  const GhostRadar({super.key, required this.engine});

  @override
  State<GhostRadar> createState() => _GhostRadarState();
}

class _GhostRadarState extends State<GhostRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([_sweep, widget.engine]),
        builder: (_, __) => CustomPaint(
          painter: _RadarPainter(widget.engine, _sweep.value),
        ),
      );
}

class _RadarPainter extends CustomPainter {
  final GhostEngine e;
  final double sweep;
  _RadarPainter(this.e, this.sweep);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final angry = e.mood == Mood.angry && e.phase == Phase.encounter;
    final col = angry ? kRed : kCyan;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = col.withOpacity(0.35)
      ..strokeWidth = 1;

    canvas.drawCircle(c, r, Paint()..color = Colors.black.withOpacity(0.5));
    for (final k in [0.33, 0.66, 1.0]) {
      canvas.drawCircle(c, r * k, line);
    }
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), line);
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), line);

    // Камерын харах өнцөг (FOV)
    final fov = GhostEngine.hfov * math.pi / 180;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2 - fov / 2,
        fov, true, Paint()..color = col.withOpacity(0.10));

    // Эргэдэг шүүрдэлт
    final a = sweep * 2 * math.pi - math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      a - 0.6,
      0.6,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: a - 0.6,
          endAngle: a,
          colors: [col.withOpacity(0), col.withOpacity(0.35)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    if (e.phase == Phase.searching || e.phase == Phase.encounter) {
      // Тодорхой бус байдал: EMF бага үед цэг "сэгсэрнэ"
      final fuzz = (1 - e.emf) * 18;
      final ang = (e.delta + math.sin(sweep * 13) * fuzz) * math.pi / 180 - math.pi / 2;
      final dist = (e.distance / 20).clamp(0.08, 1.0) * r;
      final p = c + Offset(math.cos(ang), math.sin(ang)) * dist;
      final pulse = 0.6 + 0.4 * math.sin(sweep * 2 * math.pi * 2);
      canvas.drawCircle(p, 9 * pulse + 3,
          Paint()..color = (angry ? kRed : kAmber).withOpacity(0.25));
      canvas.drawCircle(p, 4, Paint()..color = angry ? kRed : kAmber);
    }
    canvas.drawCircle(c, 3, Paint()..color = col);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => true;
}

/// K-II маягийн 5 LED-тэй EMF хэмжигч
class EmfLeds extends StatelessWidget {
  final double level; // 0..1
  const EmfLeds({super.key, required this.level});

  static const _colors = [
    Color(0xFF3BFF6A),
    Color(0xFFB6FF3B),
    Color(0xFFFFE53B),
    Color(0xFFFF9A3B),
    Color(0xFFFF3B3B),
  ];

  @override
  Widget build(BuildContext context) {
    final n = (level * 5).ceil().clamp(1, 5);
    return Row(
      children: List.generate(5, (i) {
        final on = i < n;
        return Expanded(
          child: Container(
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: on ? _colors[i] : _colors[i].withOpacity(0.12),
              borderRadius: BorderRadius.circular(3),
              boxShadow: on
                  ? [BoxShadow(color: _colors[i].withOpacity(0.7), blurRadius: 8)]
                  : null,
            ),
          ),
        );
      }),
    );
  }
}

/// Үсэг үсгээр гарч ирэх текст (сүнсний яриа)
class TypewriterText extends StatefulWidget {
  final String text;
  final int serial;
  final TextStyle style;
  const TypewriterText(
      {super.key, required this.text, required this.serial, required this.style});

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
    _run();
  }

  void _run() {
    _c.duration = Duration(milliseconds: 40 * math.max(1, widget.text.length));
    _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(TypewriterText old) {
    super.didUpdateWidget(old);
    if (old.serial != widget.serial) _run();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final n = (widget.text.length * _c.value).round();
          return Text(widget.text.substring(0, n), style: widget.style);
        },
      );
}

/// Solus маягийн шууд график: соронзон зөрүү, чичиргээ, хөдөлгөөн + flag-ууд
class LiveGraph extends StatelessWidget {
  final DataLogger logger;
  const LiveGraph({super.key, required this.logger});

  static const magColor = kCyan;
  static const vibColor = kAmber;
  static const motColor = Color(0xFFFF5CA8);
  static const tiltColor = Color(0xFFB9B9FF);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: logger,
        builder: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              _legend(magColor, 'Соронзон |Δ| µT'),
              _legend(vibColor, 'Чичиргээ'),
              _legend(motColor, 'Хөдөлгөөн'),
              _legend(tiltColor, 'Хазайлт'),
              const Spacer(),
              Text('${logger.rows} мөр',
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ]),
            const SizedBox(height: 4),
            SizedBox(
              height: 92,
              child: CustomPaint(
                size: Size.infinite,
                painter: _GraphPainter(logger),
              ),
            ),
            if (logger.lastFlag != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '⚑ ${logger.lastFlag!.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: logger.lastFlag!.auto ? kRed : Colors.white, fontSize: 11),
                ),
              ),
          ],
        ),
      );

  Widget _legend(Color c, String t) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 3, color: c),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ]),
      );
}

class _GraphPainter extends CustomPainter {
  final DataLogger l;
  _GraphPainter(this.l);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.black.withOpacity(0.35);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)), bg);
    final grid = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var s = 10; s < 60; s += 10) {
      final x = size.width * s / 60;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    if (l.samples.length < 2) return;

    final tNow = l.samples.last.t;
    double xOf(double t) => size.width * (1 - (tNow - t) / 60);

    // Flag-ууд
    for (final f in l.flags) {
      final x = xOf(f.t);
      if (x < 0) continue;
      final p = Paint()
        ..color = (f.auto ? kRed : Colors.white).withOpacity(0.8)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      final flagPath = Path()
        ..moveTo(x, 2)
        ..lineTo(x + 8, 6)
        ..lineTo(x, 10)
        ..close();
      canvas.drawPath(flagPath, Paint()..color = p.color);
    }

    final magMax = l.maxOf((s) => s.dev?.abs(), 10);
    final vibMax = l.maxOf((s) => s.vib, 5);
    final motMax = l.maxOf((s) => s.motion, 0.2);
    final tiltMax = l.maxOf((s) => s.tilt, 5);

    void series(double? Function(Sample) f, double max, Color c) {
      final path = Path();
      var first = true;
      for (final s in l.samples) {
        final x = xOf(s.t);
        final v = f(s);
        if (x < 0 || v == null) {
          first = true; // утга байхгүй хэсэгт зураас тасарна
          continue;
        }
        final y = size.height - (v / max).clamp(0.0, 1.0) * (size.height - 4) - 2;
        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = c);
    }

    series((s) => s.tilt, tiltMax, LiveGraph.tiltColor);
    series((s) => s.motion, motMax, LiveGraph.motColor);
    series((s) => s.vib, vibMax, LiveGraph.vibColor);
    series((s) => s.dev?.abs(), magMax, LiveGraph.magColor);
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}


/// Бодит соронзон хэмжилтийн самбар: |B|, Δ, X/Y/Z, суурь ± σ, босго, давтамж,
/// нарийвчлал. Мэдрэгч байхгүй бол тоо харуулахгүй.
class MagPanel extends StatelessWidget {
  final MagnetometerService mag;
  final VoidCallback onBaseline;
  const MagPanel({super.key, required this.mag, required this.onBaseline});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: mag,
        builder: (_, __) {
          const dim = TextStyle(color: Colors.white60, fontSize: 11);
          if (mag.status == MagStatus.unavailable) {
            return Text('Соронзон: ${mag.error ?? 'мэдрэгч байхгүй'} — утга харуулахгүй',
                style: const TextStyle(color: kAmber, fontSize: 11));
          }
          final s = mag.latest;
          if (s == null) {
            return const Text('Соронзон мэдрэгч эхэлж байна…', style: dim);
          }
          final d = mag.delta, b = mag.baseline, anomaly = mag.anomaly;
          String f(double v) => v.toStringAsFixed(1);
          final warn = mag.baselineWarning ??
              (s.accuracy.needsCalibration ? 'Нарийвчлал ${s.accuracy.label}: утсаа агаарт "8" дүрсээр эргүүлж тохируулна уу' : null);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Text('Соронзон орон ', style: TextStyle(color: Colors.white70, fontSize: 11)),
                Text('${f(s.total)} µT',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                if (d != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: (anomaly ? kRed : kCyan).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(d.abs() < 0.05 ? 'Δ±0.0' : 'Δ${d > 0 ? '+' : ''}${f(d)}',
                        style: TextStyle(color: anomaly ? kRed : kCyan, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: mag.measuring ? null : onBaseline,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white38),
                    ),
                    child: Text(
                        mag.measuring ? 'Хэмжиж… ${(mag.measureProgress * 100).round()}%' : (b == null ? 'Суурь хэмжих' : 'Суурь дахин'),
                        style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
              ]),
              Text('X ${f(s.x)}  Y ${f(s.y)}  Z ${f(s.z)} µT', style: dim),
              Text(
                b == null
                    ? 'Суурь хэмжээгүй • ${mag.hz.toStringAsFixed(0)} Гц • нарийвчлал: ${s.accuracy.label}'
                    : 'Суурь ${f(b.total)} ±${b.sigma.toStringAsFixed(2)} • босго ${f(mag.threshold)} • ${mag.hz.toStringAsFixed(0)} Гц • ${s.accuracy.label}',
                style: dim,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (warn != null)
                Text(warn, style: const TextStyle(color: kAmber, fontSize: 10), maxLines: 2),
            ],
          );
        },
      );
}
