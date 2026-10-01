import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../widgets/ghost_sprite.dart';
import '../widgets/hud_widgets.dart';
import 'scanner_screen.dart';

/// Эхлэлийн дэлгэц: Blender-ийн 3D утааны сүнс + утсыг хазайлгахад
/// параллакс (гүнзгий 3D мэдрэмж).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<AccelerometerEvent>? _acc;
  Offset _tilt = Offset.zero;
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();

  @override
  void initState() {
    super.initState();
    _acc = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
      (e) {
        final target = Offset((-e.x / 9.81).clamp(-1.0, 1.0), ((e.y - 7) / 9.81).clamp(-1.0, 1.0));
        setState(() => _tilt = Offset.lerp(_tilt, target, 0.15)!);
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _acc?.cancel();
    _intro.dispose();
    super.dispose();
  }

  void _start({bool measure = false}) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (_, __, ___) => ScannerScreen(measure: measure),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF040807),
      body: AnimatedBuilder(
        animation: _intro,
        builder: (context, _) {
          final appear = Curves.easeOut.transform(_intro.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Арын манан (холын давхарга — бага хөдөлнө)
              Transform.translate(
                offset: _tilt * 10,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.1),
                      radius: 0.9,
                      colors: [Color(0xFF0F2A22), Color(0xFF040807)],
                    ),
                  ),
                ),
              ),
              // Сүнс (ойрын давхарга — их хөдөлнө)
              Positioned(
                left: 0,
                right: 0,
                top: size.height * 0.04,
                height: size.height * 0.62,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..translate(_tilt.dx * 28, _tilt.dy * 18)
                    ..rotateY(_tilt.dx * 0.25)
                    ..rotateX(-_tilt.dy * 0.15),
                  child: Opacity(
                    opacity: appear,
                    child: const Center(child: AnimatedGhost(glow: 0.7)),
                  ),
                ),
              ),
              // Газрын манан
              Positioned(
                left: 0,
                right: 0,
                top: size.height * 0.5,
                height: size.height * 0.2,
                child: IgnorePointer(
                  child: Transform.translate(
                    offset: _tilt * 40,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00040807), Color(0xCC040807), Color(0xFF040807)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Column(
                    children: [
                      const Spacer(),
                      Opacity(
                        opacity: appear,
                        child: Column(children: [
                          Text(
                            'СҮНС ИЛРҮҮЛЭГЧ',
                            style: TextStyle(
                              color: kCyan,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              shadows: [Shadow(color: kCyan.withOpacity(0.6), blurRadius: 18)],
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('AI GHOST • EMF RADAR',
                              style: TextStyle(color: Colors.white54, letterSpacing: 4, fontSize: 12)),
                          const SizedBox(height: 18),
                          const _Feature(Icons.explore, 'Соронзон мэдрэгчээр сүнсний чиглэлийг заана'),
                          const _Feature(Icons.face_retouching_natural,
                              'Ойртоход нас, хүйс, уур, ярьж буйг илрүүлнэ'),
                          const _Feature(Icons.nightlight_round, 'Шөнийн / бүрэн спектр горим, лазер тор'),
                          const _Feature(Icons.cameraswitch, 'Урд, арын камер хоёуланд ажиллана'),
                        ]),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: kCyan,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => _start(),
                          icon: const Icon(Icons.radar),
                          label: const Text('СКАН ЭХЛҮҮЛЭХ',
                              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kCyan,
                            side: const BorderSide(color: kCyan, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => _start(measure: true),
                          icon: const Icon(Icons.straighten),
                          label: const Text('ХЭМЖИЛТИЙН ГОРИМ',
                              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Зөвхөн зугаа цэнгэлийн зориулалттай. Соронзон болон хөдөлгөөн мэдрэгч '
                        'бодит хэмжилт хийдэг ч сүнс илрүүлэх шинжлэх ухааны үндэслэлгүй; '
                        'сүнсний дүр, профайл нь санамсаргүйгээр үүсгэгдэнэ.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Feature(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, color: kCyan.withOpacity(0.8), size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        ]),
      );
}
