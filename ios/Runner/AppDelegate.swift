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
    
    // Activate VoIP/Call audio category so iOS keeps the CPU awake in background
    setupAudioSession()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupAudioSession() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .mixWithOthers, .defaultToSpeaker])
      try audioSession.setActive(true)
    } catch {
      print("Failed to set AVAudioSession category: \(error)")
    }
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    
    // Request extended background processing time from iOS
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