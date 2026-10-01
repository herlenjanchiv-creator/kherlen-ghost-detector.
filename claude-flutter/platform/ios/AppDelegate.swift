import Flutter
import UIKit
import CoreMotion

/// Сүнс илрүүлэгч — iOS
/// "acs/magnetometer" EventChannel: CoreMotion-ийн ТОХИРУУЛСАН соронзон орон (µT)
/// ба нарийвчлалын түвшинг Dart руу секундэд 20 удаа илгээнэ.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
  private let motion = CMMotionManager()
  private var sink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "AcsMagnetometer") {
      let channel = FlutterEventChannel(name: "acs/magnetometer", binaryMessenger: registrar.messenger())
      channel.setStreamHandler(self)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard motion.isDeviceMotionAvailable, motion.isMagnetometerAvailable else {
      return FlutterError(code: "unavailable", message: "Magnetometer not available", details: nil)
    }
    sink = events
    motion.deviceMotionUpdateInterval = 1.0 / 20.0
    motion.showsDeviceMovementDisplay = true // iOS-ийн "8 дүрс" тохируулгын цонхыг зөвшөөрнө
    let frames = CMMotionManager.availableAttitudeReferenceFrames()
    let frame: CMAttitudeReferenceFrame = frames.contains(.xMagneticNorthZVertical)
      ? .xMagneticNorthZVertical : .xArbitraryCorrectedZVertical
    motion.startDeviceMotionUpdates(using: frame, to: OperationQueue.main) { [weak self] dm, error in
      guard let self = self, let sink = self.sink else { return }
      if let error = error {
        self.motion.stopDeviceMotionUpdates()
        sink(FlutterError(code: "motion_error", message: error.localizedDescription, details: nil))
        return
      }
      guard let dm = dm else { return }
      let f = dm.magneticField
      let acc: Int
      switch f.accuracy {
      case .uncalibrated: acc = 0
      case .low: acc = 1
      case .medium: acc = 2
      case .high: acc = 3
      @unknown default: acc = -1
      }
      // Тохируулга хийгдээгүй үед iOS 0,0,0 буцааж болно — илгээхгүй
      if acc == 0 && f.field.x == 0 && f.field.y == 0 && f.field.z == 0 { return }
      sink(["x": f.field.x, "y": f.field.y, "z": f.field.z, "acc": acc, "ts": dm.timestamp, "src": "ios_coremotion_calibrated"])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    motion.stopDeviceMotionUpdates()
    sink = nil
    return nil
  }
}
