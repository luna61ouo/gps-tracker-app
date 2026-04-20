import Flutter
import UIKit
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CLLocationManagerDelegate {
  /// Persistent location manager — keeps significant location change monitoring alive.
  /// When iOS kills the app, it will relaunch it on ~500m movement.
  static let locationManager = CLLocationManager()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AppDelegate.locationManager.delegate = self
    AppDelegate.locationManager.allowsBackgroundLocationUpdates = true
    AppDelegate.locationManager.startMonitoringSignificantLocationChanges()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - CLLocationManagerDelegate

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    // No-op here — Flutter's Geolocator handles actual GPS tracking.
    // This delegate must exist to keep significant location monitoring active.
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // Silently ignore; Flutter handles location errors.
  }
}
