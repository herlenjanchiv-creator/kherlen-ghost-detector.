# Ghost Lens — function test audit

Огноо: 2026-10-02, Asia/Ulaanbaatar.

## Баталгаажсан автомат шалгалт

Веб v15: 15 тест файл, таван хэлний өргөтгөсөн шалгалт PASS.
Live: https://ghost-lens-live-lab.herlenjanchiv.chatgpt.site

| Функц | Шалгасан нөхцөл | Нотолгооны хүрээ |
|---|---|---|
| MN/EN/ES/ID/JA | анхны сонголт, хэл солих, хадгалах, дахин нээх, storage алдаа | автомат DOM mock |
| Орчуулгын сан | ES/ID/JA тус бүр 139 түлхүүр; countdown, камерын төлөв | бүх бүртгэгдсэн түлхүүр; хэлний чанарыг native speaker шалгаагүй |
| Радар | орчуулсан LIVE төлөв, өгөгдөлгүй үед —, µT × 10 = mG | synthetic sensor inputs |
| Камер | зөвшөөрөлгүй/татгалзсан, fallback, stream cleanup, background cancellation | browser API mocks; бодит камер биш |
| Зураг | frame readiness, preview, processing failure cleanup | browser API mocks; бодит iPhone photo save биш |
| Хөдөлгөөн | permission, timeout, stale data, reconnect | mocked motion events |
| Соронзон | бодит векторын тооцоо, finite/stale/error, unsupported API, obsolete callback | mocked magnetic events |
| Бүртгэл | CSV escaping, missing sensors blank, simulated provenance, manual flags | automated regression |
| Яриа/хариу | текст rendering, language error, explicit question/reply linkage | mocked recognition callbacks |
| Whisper | opt-in loading, cancellation, original language pipeline | бодит model inference/ярианы чанар шалгаагүй |

## Native Android/iOS

Шинэ тестийн run: https://github.com/herlenjanchiv-creator/kherlen-ghost-detector./actions/runs/36890024120
- Таван хэлний хэмжилтийн дэлгэцийн орчуулгын бүх түлхүүр.
- Хэлний сонголт файлд хадгалах, дахин унших, invalid/corrupt утга.
- Эхлэх үед хэл сонгох; Япон хэл; 390×844 phone, 768×1024 tablet ба 200% text.
- µT/mG солих, stale data, pause/resume.
- finite vector, sensor timeout/fallback, reconnect, baseline болон cancel.
- CSV actual values, unavailable blanks, Unicode/quotes, measurement/game provenance.

Android: analyze PASS, 9 tests PASS, debug APK build/upload PASS.
iOS: 9 tests PASS, release unsigned compile/upload PASS.
Run conclusion: SUCCESS.

Энэ нотолгоо native commit 6d0c47cab069d2f8c5933947f36d45097bf545de-д хамаарна.

## Дуусаагүй болон төхөөрөмж дээр шалгах зүйлс

| Зүйл | Төлөв |
|---|---|
| iPhone Safari µT | платформын API байхгүй; веб дээр ажиллахгүй |
| iOS суулгах | unsigned build; Apple signing/TestFlight дуусаагүй |
| Бодит Android/iPhone/iPad µT | физик төхөөрөмжийн acceptance нотолгоо байхгүй |
| Native урд/арын камер, photo/video, gallery save | compile нь тоног төхөөрөмжийн ажиллагааг нотлохгүй; физик тест үлдсэн |
| OS/browser ярианы танилт бүх хэлэнд | дэмжлэг болон чанар баталгаажаагүй; Монгол хэлний model чанар сул байж болно |
| Native яриа → текст, асуулт/хариу бүртгэл | вебийн энэ функц native хувилбарт бүрэн порт хийгдээгүй |
| Native legacy AR бүх текстийн орчуулга | хэмжилтийн үндсэн дэлгэц таван хэлтэй; хуучин AR дэлгэц бүрэн олон хэлгүй |
| Гадаад Bluetooth/USB мэдрэгч | протоколын хэрэгжилт байхгүй |
| Бүх утас/бүх OS дээр ажилладаг баталгаа | байхгүй; тухайн төхөөрөмжийн мэдрэгч, OS болон зөвшөөрлөөс хамаарна |

## Шийдвэр

Автомат тестийн дууссан хэсгийг PASS гэж тэмдэглэнэ. Бодит утасны function test DONE болон production-ready гэж батлахгүй. iOS signing, камер/мэдрэгчийн физик acceptance, native дутуу функцүүд үлдсэн.
