# Сүнс илрүүлэгч v2 (Flutter)

Зугаа цэнгэлийн AR апп. Сүнсний дүрс нь таны **Ghost.blend**-ийн
"Animated Ghost Smoke" (BlenderKit) загвараас Blender Cycles-ээр рендерлэсэн
48 фрейм анимейшн (`assets/ghost/ghost_sheet.png`).

## Суулгах

```bash
flutter create --org mn.acs ghost_detector
cd ghost_detector
# Энэ хавтасны lib/, assets/, pubspec.yaml-ийг хуулж, хуучныг дарна
flutter pub get
```

### Android
`android/app/src/main/AndroidManifest.xml` — `<application` -ийн дээр:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>
<uses-feature android:name="android.hardware.camera" android:required="false"/>
<uses-feature android:name="android.hardware.sensor.compass" android:required="false"/>
```
`<application ...>` таг дээр: `android:requestLegacyExternalStorage="true"` (Android 10-д галерейд хадгалахад)

`android/app/build.gradle` (эсвэл `build.gradle.kts`):
```
minSdk = 21
compileSdk = 35
```

### iOS
`ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Орчныг скан хийж сүнс хайхад камер шаардлагатай</string>
<key>NSMicrophoneUsageDescription</key>
<string>Видео бичлэгт дуу (EVP) бичихэд микрофон хэрэгтэй</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Зураг, видеог галерейд хадгална</string>
```
`ios/Podfile` — `platform :ios, '15.5'` болгож, `post_install` дотор:
```ruby
target.build_configurations.each do |config|
  config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)', 'PERMISSION_CAMERA=1', 'PERMISSION_MICROPHONE=1']
end
```

### Ажиллуулах
```bash
flutter analyze
flutter run --release      # бодит утсан дээр (эмулятор соронзон мэдрэгчгүй)
```

## Бүтэц

| Файл | Үүрэг |
|---|---|
| `lib/screens/splash_screen.dart` | Эхлэл: 3D сүнс, утсыг хазайлгахад параллакс |
| `lib/screens/scanner_screen.dart` | Камер, радар, EMF, профайл, горимууд |
| `lib/game/ghost_engine.dart` | Сүнсний байрлал, ойртолт, уур, яриа |
| `lib/services/orientation_service.dart` | Соронзон + хурдатгал → азимут, налуу, алхам, сэгсрэлт, тогтвортой эсэх |
| `lib/services/camera_manager.dart` | Урд/арын камер, lifecycle, ML Kit царай, хөдөлгөөн мэдрэгч |
| `lib/services/audio_fx.dart` | EMF товшилт, шивнээ, архирал, айлгах дуу |
| `lib/services/data_logger.dart` | CSV лог, spike flag, 60 сек буфер |
| `lib/services/evidence.dart` | Зураг нэгтгэх, галерейд хадгалах |
| `lib/widgets/ghost_sprite.dart` | Sprite sheet тоглуулагч (crossfade loop, улаан туяа, нүд) |

## Боломжууд

**Сүнс хайх:** соронзон мэдрэгч + компасаар радар, EMF 5 LED, ойртоход профайл (нас, хүйс, уур), яриа, урд/арын камер.

**Камер (Phasm Cam маягийн):**
- Энгийн / Шөнийн / Бүрэн спектр горим, SLS маягийн лазер тор
- 📷 Зураг — шүүлтүүр, сүнс, цагийн тэмдэг (огноо, EMF, µT, чиглэл) шингээж галерейн `GhostDetector` цомогт хадгална
- ⏺ Видео бичлэг микрофонтой (EVP) — 720p / 1080p / 4K
- Гэрэлтүүлэг нэмэх (+2.0 хүртэл), гар чийдэн, өргөн өнцгийн линз (байвал)

**Өгөгдөл бүртгэгч (Solus маягийн):**
- Секундэд 10 хэмжилт: соронзон орон, зөрүү, EMF, чичиргээ, хазайлт, камерын хөдөлгөөн → CSV файл (огноо/цагтай)
- Сүүлийн 60 секундын шууд график
- Автомат spike flag (мэдрэмж тохируулна) + гараар flag (⚑ товч)
- Spike бүрт: дээд талд цагаан гэрэл, дуут дохио, чичиргээ, сонгосон бол гар чийдэн анивчина
- Тохиргоо → «Лог файл хуваалцах» — Excel / Google Sheets-д нээнэ

**Хөдөлгөөн мэдрэгч:** утсаа гуравхөл дээр эсвэл тавьж тогтворжуулахад автоматаар асна.

## Тохируулах
- `GhostEngine.hfov / vfov` — камерын харах өнцөг (утас бүрт бага зэрэг өөр)
- `anomaly = magDeviation > 20` — соронзон аномалийн босго (µT)
- `kPhrases` — сүнсний хэлэх үгс (сэтгэл санаа тус бүрээр)
- `CameraManager._computeMotion` дахь `th` — хөдөлгөөн мэдрэгчийн мэдрэмж

## Анхааруулга
- Энэ нь зугаа цэнгэлийн апп. Сүнсний нас, хүйс, уур, яриа санамсаргүйгээр үүсгэгддэг.
- "Шөнийн" ба "Бүрэн спектр" горим нь өнгөний шүүлтүүр. Утасны камер IR-cut шүүлтүүртэй тул жинхэнэ IR/full-spectrum (200–900 нм) биш.
- Утсанд агаарын температур мэдрэгч бараг байдаггүй тул температур бүртгэхгүй.
- Видео файлд сүнсний дүрс шингэхгүй (зөвхөн камерын бодит дүрс + дуу). Сүнс, цагийн тэмдэг зөвхөн зурагт шингэнэ.
- Зураг, бичлэг хийх үед ML Kit болон хөдөлгөөн мэдрэгч түр зогсдог (олон утас зэрэг ажиллуулж чаддаггүй).
- Соронзон мэдрэгч, хөдөлгөөн мэдрэгч бодит хэмжилт хийнэ.
- Сүнсний загвар BlenderKit-ийн Royalty Free лицензтэй. Рендерлэсэн зургийг апп дотор ашиглах боломжтой ч эх .blend/.vdb файлыг тараахгүй.
