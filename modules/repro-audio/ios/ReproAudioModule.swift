import AVFoundation
import ExpoModulesCore
import UIKit

/// Plain AVFoundation version of expo-audio's session lifecycle, with no expo-audio code involved.
/// Runs entirely on native queues, so React Native timing can't influence it.
public class ReproAudioModule: Module {
  private let sessionQueue = DispatchQueue(label: "repro.audio.session")
  private var sessionIsActive = false
  private var logHandle: FileHandle?

  public func definition() -> ModuleDefinition {
    Name("ReproAudio")

    Function("launchArguments") { () -> [String] in
      ProcessInfo.processInfo.arguments
    }

    Function("openLog") { (name: String) in
      let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      let url = dir.appendingPathComponent(name)
      FileManager.default.createFile(atPath: url.path, contents: nil)
      self.logHandle = try FileHandle(forWritingTo: url)
    }

    Function("appendLog") { (line: String) in
      self.logHandle?.write(Data((line + "\n").utf8))
      try? self.logHandle?.synchronize()
    }

    AsyncFunction("keepScreenOn") { () in
      UIApplication.shared.isIdleTimerDisabled = true
    }.runOnQueue(.main)

    AsyncFunction("configurePlainSession") { () in
      try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
    }

    AsyncFunction("runPlainTrial") { (uri: String, scenario: String, gapMs: Int, deactivate: Bool, promise: Promise) in
      guard let url = URL(string: uri) else {
        promise.reject("E_URL", "Invalid clip URI")
        return
      }
      DispatchQueue.main.async {
        self.runTrial(url: url, scenario: scenario, gapMs: gapMs, deactivate: deactivate, promise: promise)
      }
    }
  }

  private func activate() {
    sessionQueue.async {
      guard !self.sessionIsActive else { return }
      do {
        try AVAudioSession.sharedInstance().setActive(true)
        self.sessionIsActive = true
      } catch {
        NSLog("[repro] activate failed: \(error)")
      }
    }
  }

  private func runTrial(url: URL, scenario: String, gapMs: Int, deactivate: Bool, promise: Promise) {
    let first = AVPlayer(url: url)
    let second = AVPlayer(url: url)
    var deactivatedAtMs: Double?
    var deactivateError: String?
    var endedAt: DispatchTime = .now()

    let startSecond = {
      second.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
        DispatchQueue.main.async {
          let gapActualMs = Self.ms(since: endedAt)
          let requestedAt = DispatchTime.now()
          second.play()
          self.activate()
          self.poll(
            player: second,
            requestedAt: requestedAt,
            result: { progressMs in
              first.pause()
              second.pause()
              self.sessionQueue.async {
                promise.resolve([
                  "progressMs": progressMs as Any,
                  "gapActualMs": gapActualMs,
                  "deactivatedAtMs": deactivatedAtMs as Any,
                  "deactivateError": deactivateError as Any,
                  "timeControlStatus": second.timeControlStatus.rawValue,
                  "reason": second.reasonForWaitingToPlay?.rawValue as Any
                ])
              }
            }
          )
        }
      }
    }

    let didEnd = {
      endedAt = .now()
      // Same as expo-audio's deactivateSession(): 100 ms later, unless a player is playing.
      if deactivate {
        self.sessionQueue.asyncAfter(deadline: .now() + .milliseconds(100)) {
          guard self.sessionIsActive,
            first.timeControlStatus != .playing,
            second.timeControlStatus != .playing else {
            return
          }
          do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            self.sessionIsActive = false
            deactivatedAtMs = Self.ms(since: endedAt)
          } catch {
            deactivateError = "\(error)"
          }
        }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(gapMs), execute: startSecond)
    }

    waitUntilReady(first, second) {
      first.play()
      self.activate()
      if scenario == "finish" {
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
          forName: .AVPlayerItemDidPlayToEndTime,
          object: first.currentItem,
          queue: .main
        ) { _ in
          if let token { NotificationCenter.default.removeObserver(token) }
          didEnd()
        }
      } else {
        self.waitForProgress(first, atLeast: 0.1) {
          first.pause()
          didEnd()
        }
      }
    }
  }

  private func waitUntilReady(_ a: AVPlayer, _ b: AVPlayer, then: @escaping () -> Void) {
    if a.currentItem?.status == .readyToPlay, b.currentItem?.status == .readyToPlay {
      then()
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
      self.waitUntilReady(a, b, then: then)
    }
  }

  private func waitForProgress(_ player: AVPlayer, atLeast: Double, then: @escaping () -> Void) {
    if player.currentTime().seconds >= atLeast {
      then()
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
      self.waitForProgress(player, atLeast: atLeast, then: then)
    }
  }

  private func poll(player: AVPlayer, requestedAt: DispatchTime, result: @escaping (Double?) -> Void) {
    let elapsed = Self.ms(since: requestedAt)
    if player.currentTime().seconds > 0 {
      result(elapsed)
      return
    }
    if elapsed > 2500 {
      result(nil)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(5)) {
      self.poll(player: player, requestedAt: requestedAt, result: result)
    }
  }

  private static func ms(since: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - since.uptimeNanoseconds) / 1_000_000
  }
}
