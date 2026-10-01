const nativeLanguages = {'MN': 'Монгол', 'EN': 'English', 'ES': 'Español', 'ID': 'Bahasa Indonesia', 'JA': '日本語'};
const nativeTranslations = {
  'REAL MAGNETIC MEASUREMENT': ['БОДИТ СОРОНЗОН ХЭМЖИЛТ','MEDICIÓN MAGNÉTICA REAL','PENGUKURAN MAGNETIK NYATA','実際の磁場測定'],
  'Baseline': ['Суурь','Referencia','Acuan','基準値'],
  'Accuracy': ['Нарийвчлал','Precisión','Akurasi','精度'],
  'Reconnect': ['Дахин холбох','Reconectar','Hubungkan ulang','再接続'],
  'Measure baseline · 3 seconds': ['Суурь хэмжих · 3 секунд','Medir referencia · 3 segundos','Ukur acuan · 3 detik','基準値を測定 · 3秒'],
  'Open camera / AR game': ['Камер / AR тоглоом нээх','Abrir cámara / juego AR','Buka kamera / game AR','カメラ / ARゲームを開く'],
  'Waiting for sensor data…': ['Мэдрэгчийн өгөгдөл хүлээж байна…','Esperando datos del sensor…','Menunggu data sensor…','センサーデータを待っています…'],
  'Magnetic field increase': ['Соронзон орны өсөлт','Aumento del campo magnético','Peningkatan medan magnet','磁場の強さが上昇'],
  'Magnetic reading': ['Соронзон хэмжилт','Lectura magnética','Pembacaan magnetik','磁場の測定値'],
  'Visual effect · no source location': ['Дүрслэлийн эффект · үүсгэгчийн байршил биш','Efecto visual · sin ubicación de fuente','Efek visual · bukan lokasi sumber','視覚効果・発生源の位置を示すものではありません'],
  'Sensor unavailable. Reconnect or check device support.': ['Мэдрэгчийн өгөгдөл байхгүй. Дахин холбох эсвэл төхөөрөмжийн дэмжлэгийг шалгана уу.','Sensor no disponible. Reconecta o verifica la compatibilidad.','Sensor tidak tersedia. Hubungkan ulang atau periksa dukungan perangkat.','センサーを利用できません。再接続または端末の対応状況を確認してください。'],
  'X/Y/Z are device axes. They do not locate a source, detect spirits or measure RF leakage.': ['X/Y/Z нь утасны тэнхлэгүүд. Эдгээр нь үүсгэгчийн байршил, сүнс эсвэл RF алдагдлыг тогтоохгүй.','X/Y/Z son ejes del dispositivo. No localizan fuentes, detectan espíritus ni miden fugas de radiofrecuencia.','X/Y/Z adalah sumbu perangkat. Tidak menentukan lokasi sumber, mendeteksi roh, atau mengukur kebocoran RF.','X/Y/Zは端末の軸です。発生源の位置や霊を検出したり、RF漏れを測定したりするものではありません。'],
  'Review baseline conditions and repeat if needed.': ['Суурь хэмжилтийн нөхцөлийг шалгаж, шаардлагатай бол давтана уу.','Revisa las condiciones de referencia y repite si es necesario.','Periksa kondisi acuan dan ulangi jika diperlukan.','基準値の測定条件を確認し、必要に応じて再測定してください。'],
  'Alerts · sound / vibration': ['Дохио · дуу / чичиргээ','Alertas · sonido / vibración','Peringatan · suara / getaran','通知 · 音 / 振動'],
  'Choose language': ['Хэл сонгох','Elegir idioma','Pilih bahasa','言語を選択'],
  'unknown': ['тодорхойгүй','desconocida','tidak diketahui','不明'],
  'unreliable': ['тохируулаагүй','sin calibrar','belum dikalibrasi','未校正'],
  'low': ['бага','baja','rendah','低'],
  'medium': ['дунд','media','sedang','中'],
  'high': ['өндөр','alta','tinggi','高'],
};
String nativeText(String key, String language) {
  if (language == 'EN') return key;
  final index = const {'MN': 0, 'ES': 1, 'ID': 2, 'JA': 3}[language];
  final row = nativeTranslations[key];
  return index == null || row == null ? key : row[index];
}
