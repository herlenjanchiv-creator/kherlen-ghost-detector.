import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_detector/services/magnetometer_service.dart';

class FakeSource implements MagSource {
  final controller = StreamController<MagSample>.broadcast();
  @override
  String get id => 'test';
  @override
  String get label => 'test';
  @override
  Stream<MagSample> samples() => controller.stream;
  void sample(DateTime now, double x, double y, double z) => controller.add(MagSample(now, x, y, z, MagAccuracy.high, 'test'));
}

void main() {
  test('finite vector, stale data and recovery; no invented values', () async {
    final primary = FakeSource(), fallback = FakeSource();
    var now = DateTime.utc(2026);
    final service = MagnetometerService(primary: primary, fallback: fallback, clock: () => now);
    await service.start();
    expect(service.total, isNull);
    primary.sample(now, double.nan, 4, 0);
    await Future<void>.delayed(const Duration(milliseconds: 10));expect(service.total, isNull);
    primary.sample(now, 3, 4, 0);
    await Future<void>.delayed(const Duration(milliseconds: 10));expect(service.total, 5);expect(service.status, MagStatus.live);
    now = now.add(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(service.total, isNull);expect(service.status, MagStatus.unavailable);
    primary.sample(now, 0, 0, 40);await Future<void>.delayed(const Duration(milliseconds: 10));expect(service.total, 40);
    primary.controller.addError(StateError('lost'));await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(service.total, isNull);expect(service.status, MagStatus.unavailable);
    service.dispose();await primary.controller.close();await fallback.controller.close();
  });
  test('timeout fallback then explicit unavailable, dispose cancels timers', () async {
    final primary = FakeSource(), fallback = FakeSource();
    final service = MagnetometerService(primary: primary, fallback: fallback);
    await service.start();await Future<void>.delayed(const Duration(milliseconds: 3100));await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(service.source, fallback);
    await Future<void>.delayed(const Duration(milliseconds: 3100));expect(service.status, MagStatus.unavailable);
    expect(service.total, isNull);
    service.dispose();await Future<void>.delayed(const Duration(milliseconds: 10));
    await primary.controller.close();await fallback.controller.close();
  });
  test('stop and reconnect cannot reuse old samples', () async {
    final source = FakeSource();
    final service = MagnetometerService(primary: source, fallback: FakeSource());
    await service.start();source.sample(DateTime.now(), 10, 0, 0);await Future<void>.delayed(const Duration(milliseconds: 10));expect(service.total, 10);
    await service.stop();source.sample(DateTime.now(), 50, 0, 0);await Future<void>.delayed(const Duration(milliseconds: 10));expect(service.total, isNull);
    await service.start();expect(service.total, isNull);
    source.sample(DateTime.now(), 20, 0, 0);await Future<void>.delayed(const Duration(milliseconds: 10));expect(service.total, 20);
    service.dispose();await source.controller.close();
  });
  test('baseline uses observed samples and cancels when stopped', () async {
    final source=FakeSource();final service=MagnetometerService(primary:source,fallback:source);
    await service.start();source.sample(DateTime.now(),0,0,40);await Future<void>.delayed(const Duration(milliseconds:10));
    final timer=Timer.periodic(const Duration(milliseconds:20),(_)=>source.sample(DateTime.now(),0,0,40));
    final baseline=await service.measureBaseline(seconds:.6);
    expect(baseline,isNotNull);expect(baseline!.total,40);expect(baseline.sigma,0);expect(baseline.samples,greaterThanOrEqualTo(5));
    final pending=service.measureBaseline(seconds:.6);await Future<void>.delayed(const Duration(milliseconds:50));await service.stop();expect(await pending,isNull);
    timer.cancel();service.dispose();await source.controller.close();
  });

}
