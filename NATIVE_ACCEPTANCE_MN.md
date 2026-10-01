# Ghost Lens native — acceptance

## Build нотолгоо

Мэдрэгчийн 3 автомат тест Android/iOS runner дээр PASS:
- finite vector / stale sample / recovery
- primary timeout / fallback / unavailable
- stop / reconnect / old sample rejection

Flutter analyze: PASS (Android runner).
Тестийн нотолгоо: https://github.com/herlenjanchiv-creator/kherlen-ghost-detector./actions/runs/36881207073
Энэ run-ийн iOS compile камерын сан/Xcode нийцлээс FAILED.
Шинэ Xcode 26.3 build: https://github.com/herlenjanchiv-creator/kherlen-ghost-detector./actions/runs/36881758197
iOS release unsigned compile: PASS, artifact үүссэн.
Android debug APK: PASS — run 36881207073, artifact 11170704627.
APK: https://github.com/herlenjanchiv-creator/kherlen-ghost-detector./actions/runs/36881207073/artifacts/11170704627

Радар нь дүрслэлийн эффект; 60/120 µT өнгөний босго нь орчны аюулгүй байдал эсвэл сүнсийг нотлохгүй.
EN/MN/ES/ID хэлний цэс, µT/mG, X/Y/Z, baseline, reconnect, өндөр заалтын cooldown-той haptic дохио нэмэгдсэн.

## Бодит төхөөрөмжийн шалгалт (дуусаагүй)

| Шалгалт | Хүлээгдэх үр дүн |
|---|---|
| Апп эхлэх | Камерын зөвшөөрөлгүйгээр magnetic sensor эхэлнэ; өгөгдөлгүй бол — |
| Мэдрэгч | X/Y/Z ба нийт хүч бодит µT; sample source ба accuracy харагдана |
| Нэгж | mG = µT × 10 |
| Суурь | 3 секунд хангалттай өгөгдлөөр baseline/σ/Δ тооцно |
| Тасралт | 1.5 секунд шинэ өгөгдөлгүй бол LIVE унтарч — гарна |
| Reconnect | Хуучин callback/утга шинэ хэмжилтэд холилдохгүй |
| Background | Sensor stop; foreground restart |
| Камер/AR | Камер нээгдэх, урд/арын солих, зураг/видео; тоглоомын утга тусдаа |
| Бүртгэл | CSV-ийн magnetic source ба утга бодит sample-тэй таарна |

Android debug APK нь туршилтад зориулсан debug signing-тай; Play Store production signing биш. iOS unsigned compile нь төхөөрөмжид суулгахгүй. iPhone-д macOS/Xcode, өөрийн Apple team signing хэрэглэнэ. Хүний Apple нууц үг/сертификатыг чатад авахгүй.

## Дүгнэлт

CI compile/test PASS болох нь hardware acceptance PASS биш. Физик iPhone/iPad/Android хэмжилтийн нотолгоо бүрдээгүй тул бүх утсан дээр ажилладаг гэж батлахгүй. Энэ апп соронзон орон хэмжинэ; RF/Wi-Fi эсвэл микроволновкийн алдагдал, сүнсний байршил/нас/хүйсийг бодитоор тогтоохгүй.
