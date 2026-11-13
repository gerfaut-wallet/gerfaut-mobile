import Flutter
import UIKit
import flutter_local_notifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The background check (lib/src/background.dart). iOS only runs a
    // task whose identifier was registered before launch ends, and
    // listed under BGTaskSchedulerPermittedIdentifiers in Info.plist;
    // when it runs, and whether, is the system's call. Fifteen minutes
    // is the earliest it may start again, as on Android.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "gerfaut.check",
      earliestBeginInSeconds: 900
    )
    // The check runs in an engine of its own, which needs the plugins
    // too: the secure storage for the vault key, the notifications.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // A transaction found while Gerfaut is on screen is told too, as
    // on Android: the plugin answers the system's foreground question.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The channels no plugin answers, served as on Android: the window,
    // the files, the biometric prompt (PlatformChannels.swift).
    PlatformChannels.register(with: engineBridge.pluginRegistry)
  }
}
