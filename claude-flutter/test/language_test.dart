import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_detector/localization/native_strings.dart';
import 'package:ghost_detector/localization/language_preferences.dart';
void main() {
  test('all measurement labels have five language coverage', () {
    expect(nativeLanguages.keys.toSet(), {'MN','EN','ES','ID','JA'});
    for (final entry in nativeTranslations.entries) {
      expect(entry.value.length, 4);
      for (final language in nativeLanguages.keys) {
        expect(nativeText(entry.key, language).trim(), isNotEmpty);
        if (language != 'EN') expect(nativeText(entry.key, language), isNot(entry.key));
      }
    }
  });
  test('language choice persists; corrupt and invalid values recover', () async {
    final directory = await Directory.systemTemp.createTemp('ghost_language_test');
    addTearDown(() => directory.delete(recursive: true));
    final preferences = LanguagePreferences(directory: () async => directory);
    expect(await preferences.read(), isNull);
    for (final language in nativeLanguages.keys) {
      expect(await preferences.write(language), isTrue);
      expect(await LanguagePreferences(directory: () async => directory).read(), language);
    }
    expect(await preferences.write('invalid'), isFalse);
    await File('${directory.path}/ghost_lens_language.txt').writeAsString('invalid');
    expect(await preferences.read(), isNull);
  });
}
