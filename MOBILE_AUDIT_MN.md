# Ghost Lens v12 — шаардлагын аудит

2026-10-01, Улаанбаатар

| Шаардлага | Дүгнэлт | Баримт |
|---|---|---|
| Браузер/HTTPS мэдээллийн хайрцаг харуулахгүй | PASS — код | index/lab-аас панел ба холбогдох UI handler-уудыг авсан |
| Бүртгэлийг өмнөх хэвээр болгох | PASS — код | Өмнөх нэр/session/микрофон бичлэг/тэмдэглэгээ/бүх түүх интерфейсийг буцаасан; object/last-five өөрчлөлт цуцлагдсан |
| iPhone/iPad дээр бодит соронзон µT хэмжих | FAIL — блокер | Веб нь Magnetometer API шаарддаг. Safari дэмждэггүй. Native эх код бол суулгасан build биш |
| Android утас дээр µT ажиллах | UNVERIFIED | Браузер/төхөөрөмжийн дэмжлэг хамаарна; native Android build, төхөөрөмжийн хэмжилт хийгдээгүй |
| Камер/микрофон/хөдөлгөөн/зураг бүх утсанд ажиллах | UNVERIFIED — бүх төхөөрөмжийн баталгаа өгөхгүй | Кодын mocked API шалгалт PASS; бодит утас/iPad шалгалт хийгдээгүй |

## Function test — хийсэн

`npm run build` PASS: камер асаах/унтраах/зөвшөөрөл татгалзах/fallback/далд үеийн цэвэрлэгээ; зураг preview/encoding алдаа/дахин авах сэргэлт; dBFS тооцоо; хөдөлгөөний зөвшөөрөл/null/timeout; CSV escaping ба бодит/демо гарал; сесс ба speech annotation логик; MN/EN persistence; бүртгэлийн өмнөх UI ба өгөгдөлгүй үед буруу flag үүсэхгүй байх.

Соронзон мэдрэгчийн тусгай mocked test: API байхгүй, HTTPS байхгүй, policy блок, бодит векторын тооцоо, null sample, хуучирсан өгөгдлийг — болгох, 5 секундийн timeout, алдааны cleanup, хуучин callback шинэ sensor-ийг салгахгүй байх — PASS. Энэ нь утасны бодит хэмжилтийн баримт биш.

## Live шалгалтаар илэрсэн алдаа

Микрофон унтраалттай `audio=null` утгыг `audio > -25` гэж харьцуулснаар null нь 0 болж, буруу автомат дууны flag үүсдэг байсан. Number.isFinite guard нэмсэн; өгөгдөлгүй tick хоёр удаа ажиллуулахад flag үүсэхгүй, бодит audio/motion босго давбал хэвийн trigger хийх regression test PASS. Засвараас өмнөх QA v11 Door A тестийн сесс буруу flag агуулж болох тул хэмжилтийн баримт гэж ашиглахгүй.

## Native эх кодын аудит ба засвар

- `setup.ps1`: iOS NSMotionUsageDescription дутуу байсныг нэмсэн. Camera/Microphone/Photos/Motion түлхүүрийг тус тусад нь шалгаж оруулна; өмнө camera түлхүүр байвал бусад нь алгасагддаг байсан.
- iOS CoreMotion callback-ийн алдааг үл тоодог байсныг Flutter channel-д мэдээлдэг болгосон.
- Android registerListener false буцаавал төхөөрөмжийн алдаа мэдээлдэг болгосон.
- Flutter/Dart/Xcode toolchain байхгүй. Native compile/static analyzer болон физик төхөөрөмжийн test хийгдээгүй. Эдгээр native засваруудыг ажиллаж байгаа build гэж тооцохгүй.

## Үлдсэн бодит төхөөрөмжийн acceptance test

iPhone/iPad-д macOS + Xcode + signing ашиглан native build суулгана. Android-д Flutter build суулгана. Төхөөрөмж бүр magnetometer байгаа эсэх, x/y/z ба |B| µT бодит sample ирэх, суурь/σ/Δ, timestamp/frequency, мэдрэгч салгах/дахин холбох, background/foreground, өгөгдөлгүй timeout-ыг шалгана. Камер урд/арын солих, зураг share/save, микрофон playback, хөдөлгөөн болон сессийн экспорттой хамт шалгана. Соронзон хэмжилтийн өөрчлөлтийг сүнсний нотолгоо гэж тайлбарлахгүй.

## Шийдвэр

**NO-GO: “бүх утсан дээр бодит соронзон хэмжилт ажиллах эцсийн апп” шаардлага хангагдаагүй.** Веб UI засвар болон автомат function test дууссан; native build + төхөөрөмжийн acceptance test нээлттэй. Vercel deployment хийгдээгүй; public хувилбар Sites дээр.

## Эх сурвалж

- https://developer.mozilla.org/en-US/docs/Web/API/Magnetometer — browser compatibility, HTTPS болон permission policy.
- https://developer.apple.com/documentation/coremotion/cmmagnetometerdata — native magnetometer readings.
- https://developer.apple.com/documentation/coremotion/cmmagneticfield — x/y/z microteslas.
