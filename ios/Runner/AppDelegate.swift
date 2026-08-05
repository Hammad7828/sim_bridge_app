import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Enable background audio session to keep socket CPU thread active
    do {
      try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Failed to set AVAudioSession category: \(error)")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    
    // Request extended background runtime from iOS
    self.backgroundTaskID = application.beginBackgroundTask(withName: "InfinixHotspotKeepAlive") {
      application.endBackgroundTask(self.backgroundTaskID)
      self.backgroundTaskID = .invalid
    }
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    
    if self.backgroundTaskID != .invalid {
      application.endBackgroundTask(self.backgroundTaskID)
      self.backgroundTaskID = .invalid
    }
  }
}