import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'native_strings.dart';
class LanguagePreferences {
  LanguagePreferences({Future<Directory> Function()? directory}) : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  Future<String?> read() async {
    try { final dir = await _directory(); final value = (await File('${dir.path}/ghost_lens_language.txt').readAsString()).trim(); return nativeLanguages.containsKey(value) ? value : null; } catch (_) { return null; }
  }
  Future<bool> write(String language) async {
    if (!nativeLanguages.containsKey(language)) return false;
    try { final dir = await _directory(); await dir.create(recursive: true); await File('${dir.path}/ghost_lens_language.txt').writeAsString(language, flush: true); return true; } catch (_) { return false; }
  }
}
