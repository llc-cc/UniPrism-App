import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "uniprism/auth_storage",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      let defaults = UserDefaults.standard
      let keys = ["uniprism.token", "uniprism.user", "uniprism.anonymousId", "uniprism.anonymousCookie", "uniprism.exploreSessionId"]

      switch call.method {
      case "read":
        var values: [String: Any?] = [:]
        for key in keys {
          values[key] = defaults.string(forKey: key)
        }
        result(values)
      case "write":
        let values = call.arguments as? [String: Any] ?? [:]
        for key in keys {
          guard values.keys.contains(key) else { continue }
          if let value = values[key] as? String, !value.isEmpty {
            defaults.set(value, forKey: key)
          } else {
            defaults.removeObject(forKey: key)
          }
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
