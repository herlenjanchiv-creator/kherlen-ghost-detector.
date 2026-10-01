package mn.acs.ghost_detector

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * Сүнс илрүүлэгч — Android
 * "acs/magnetometer" EventChannel: Sensor.TYPE_MAGNETIC_FIELD (тохируулсан, µT)
 * ба мэдрэгчийн нарийвчлалыг (SENSOR_STATUS_*) Dart руу ~20 Гц-ээр илгээнэ.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "acs/magnetometer")
            .setStreamHandler(MagnetometerHandler(applicationContext))
    }
}

class MagnetometerHandler(context: Context) : EventChannel.StreamHandler, SensorEventListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var sink: EventChannel.EventSink? = null
    private var accuracy = -1

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val sensor = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
        if (sensor == null) {
            events.error("unavailable", "Magnetometer not available", null)
            return
        }
        sink = events
        if (!sensorManager.registerListener(this, sensor, 50_000)) {
            sink = null
            events.error("unavailable", "Magnetometer listener could not start", null)
        } // 50 мс = 20 Гц
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        sink = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        val s = sink ?: return
        val acc = if (event.accuracy in 0..3) event.accuracy else accuracy
        s.success(
            mapOf(
                "x" to event.values[0].toDouble(),
                "y" to event.values[1].toDouble(),
                "z" to event.values[2].toDouble(),
                "acc" to acc,
                "ts" to event.timestamp / 1e9,
                "src" to "android_magnetic_field",
            )
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, newAccuracy: Int) {
        accuracy = newAccuracy
    }
}
