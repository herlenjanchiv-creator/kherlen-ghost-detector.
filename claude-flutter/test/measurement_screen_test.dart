import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_detector/localization/language_preferences.dart';
import 'package:ghost_detector/localization/native_strings.dart';
import 'package:ghost_detector/services/magnetometer_service.dart';
import 'package:ghost_detector/screens/measurement_screen.dart';
class FakeSource implements MagSource {
  final controller = StreamController<MagSample>.broadcast(sync: true);
  @override String get id => 'test';
  @override String get label => 'test';
  @override Stream<MagSample> samples() => controller.stream;
}
class MemoryPreferences extends LanguagePreferences {
  String? saved;
  @override Future<String?> read() async => saved;
  @override Future<bool> write(String language) async { saved = language; return true; }
}
void main() {
  testWidgets('five-language menu, values, units, stale data and phone layout', (tester) async {
    tester.view.physicalSize = const Size(390,844);tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    var now=DateTime.utc(2026);final source=FakeSource();final preferences=MemoryPreferences();
    final service=MagnetometerService(primary:source, fallback:source, clock:()=>now);
    await tester.pumpWidget(MaterialApp(home:MeasurementScreen(magnetometer:service,languagePreferences:preferences,initialLanguage:'EN')));
    await tester.pump();expect(find.text('—'), findsWidgets);
    source.controller.add(MagSample(now,24,32,0,MagAccuracy.high,'test'));await tester.pump();
    expect(find.text('40.00'),findsOneWidget);
    await tester.ensureVisible(find.text('µT / mG'));await tester.tap(find.text('µT / mG'));await tester.pump();
    expect(find.text('400.00'),findsOneWidget);
    await tester.drag(find.byType(ListView),const Offset(0,600));await tester.pump();await tester.pump(const Duration(milliseconds:300));
    for(final language in nativeLanguages.entries){
      await tester.tap(find.byIcon(Icons.language));await tester.pump();await tester.pump(const Duration(milliseconds:300));
      await tester.tap(find.text(language.value));await tester.pump();await tester.pump(const Duration(milliseconds:300));await tester.pump();
      expect(preferences.saved,language.key);
      expect(find.text(nativeText('REAL MAGNETIC MEASUREMENT',language.key)),findsOneWidget);
      expect(tester.takeException(),isNull);
    }
    now=now.add(const Duration(seconds:2));await tester.pump(const Duration(seconds:2));
    expect(find.text('400.00'),findsNothing);expect(service.total,isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);await tester.pump();
    expect(service.status,MagStatus.unavailable);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pump();
    expect(service.latest,isNull);
    await tester.pumpWidget(const SizedBox());unawaited(source.controller.close());await tester.pump();
  });
  testWidgets('first launch Japanese selection and tablet large text', (tester) async {
    tester.view.physicalSize=const Size(768,1024);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final source=FakeSource();final preferences=MemoryPreferences();
    await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(2)),child:child!),home:MeasurementScreen(magnetometer:MagnetometerService(primary:source,fallback:source),languagePreferences:preferences)));
    await tester.pump();await tester.pump(const Duration(milliseconds:300));
    expect(find.byType(AlertDialog),findsOneWidget);
    await tester.tap(find.text('日本語'));await tester.pump(const Duration(milliseconds:300));
    expect(preferences.saved,'JA');expect(find.text('実際の磁場測定'),findsOneWidget);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());unawaited(source.controller.close());await tester.pump();
  });
}
