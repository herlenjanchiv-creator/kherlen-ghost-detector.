# Ghost Lens Native — бодит соронзон хэмжилт

Эхлэхэд native magnetometer-ээс |B|, X/Y/Z µT; mG сонголт (1 µT = 10 mG), суурь/σ/Δ, бодитоор ажигласан Hz харагдана. Өгөгдөлгүй бол —; 1.5 секунд тасарвал LIVE унтарна. Камерын зөвшөөрөлгүйгээр соронзон хэмжиж болно. Камер/AR хэсэг тусдаа товчоор нээгдэнэ; AR тоглоомын утгууд зохиомол.

## Build

Flutter 3.35.7, Python 3 шаардлагатай.

```sh
python claude-flutter/prepare_native.py ./ghost_detector
cd ghost_detector
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
```

Windows: `claude-flutter/setup.ps1` мөн адил project үүсгэж, шалгалт хийнэ. Өмнөх project хавтас байвал өөр хоосон destination сонгоно; эх файлыг дарж устгахгүй.

iPhone/iPad: macOS + Xcode + CocoaPods хэрэгтэй. `flutter build ios --release --no-codesign` нь зөвхөн compile шалгана; unsigned Runner.app нь утсанд суулгах файл биш. Xcode Runner target дээр өөрийн Apple team сонгоод төхөөрөмжөө холбоод `flutter run --release` ашиглана. TestFlight/App Store-д Apple Developer signing болон тусдаа distribution шаардлагатай.

## Автомат шалгалт

`.github/workflows/native-build.yml` Android debug APK, iOS unsigned compile, magnetometer regression tests хийнэ. Амжилттай run-ийн artifact-ыг авна. Workflow нэмэгдсэн нь build PASS гэсэн үг биш. Физик мэдрэгчийн acceptance test заавал үлдэнэ.

## Төхөөрөмжөөр шалгах

- µT X/Y/Z бодит утга ирэх; сул соронзон биетийг алсаас ойртуулахад өөрчлөгдөх.
- Соронзтой утасны гэрийг салгаж, суурь 3 секунд хэмжих; хөдөлгөөнгүй байлгах.
- Өгөгдөл тасрах, background/foreground, reconnect, camera/AR-аас буцах.
- RF/Wi-Fi/микроволновкийн алдагдал хэмждэг багаж биш; сүнсийг нотлохгүй.
