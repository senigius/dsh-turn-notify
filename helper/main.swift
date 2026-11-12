import AppKit
import Foundation
import UserNotifications

// Notification poster for macOS. Legacy NSUserNotification (osascript,
// terminal-notifier) is authorized but never rendered on macOS 26, so this
// bundle uses UNUserNotificationCenter. It must live in a real app bundle and
// be launched through LaunchServices for macOS to show the authorization prompt.
//
// Request payload (JSON): {"title": "...", "body": "...", "sound": "Glass"}
// Read from $DSH_NOTIFY_REQUEST, else ~/Library/Caches/dsh-turn-notify/request.json.
// Diagnostics: append to $DSH_NOTIFY_LOG, else
// ~/Library/Caches/dsh-turn-notify/helper.log.

struct Request: Decodable {
    var title: String?
    var body: String?
    var sound: String?
}

let cacheDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Caches/dsh-turn-notify", isDirectory: true)
try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

let env = ProcessInfo.processInfo.environment
let logPath = env["DSH_NOTIFY_LOG"] ?? cacheDir.appendingPathComponent("helper.log").path
let requestPath = env["DSH_NOTIFY_REQUEST"]
    ?? cacheDir.appendingPathComponent("request.json").path

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(stamp)] \(message)\n"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

var request = Request()
if let data = FileManager.default.contents(atPath: requestPath),
   let decoded = try? JSONDecoder().decode(Request.self, from: data) {
    request = decoded
} else {
    log("no readable request at \(requestPath)")
}

let title = request.title ?? "DeepSeek Harness"
let body = request.body ?? "Turn finished"
let sound = request.sound ?? "Glass"

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let center = UNUserNotificationCenter.current()

func statusName(_ raw: Int) -> String {
    switch raw {
    case 0: return "notDetermined"
    case 1: return "denied"
    case 2: return "authorized"
    case 3: return "provisional"
    case 4: return "ephemeral"
    default: return "unknown(\(raw))"
    }
}

func finish(_ code: Int32) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(code) }
}

func post() {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    if sound == "default" {
        content.sound = .default
    } else if sound != "none" && !sound.isEmpty {
        content.sound = UNNotificationSound(named: UNNotificationSoundName(sound + ".aiff"))
    }
    content.interruptionLevel = .timeSensitive
    let notification = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
    )
    log("post title=\(title) body=\(body) sound=\(sound)")
    center.add(notification) { error in
        if let error {
            log("add error: \(error)")
        } else {
            log("add ok")
        }
        finish(error == nil ? 0 : 6)
    }
}

log("launch bundle=\(Bundle.main.bundleIdentifier ?? "nil") request=\(requestPath)")
center.getNotificationSettings { settings in
    log("settings status=\(statusName(settings.authorizationStatus.rawValue)) "
        + "alertStyle=\(settings.alertStyle.rawValue) alert=\(settings.alertSetting.rawValue) "
        + "sound=\(settings.soundSetting.rawValue) center=\(settings.notificationCenterSetting.rawValue) "
        + "lock=\(settings.lockScreenSetting.rawValue) timeSensitive=\(settings.timeSensitiveSetting.rawValue)")
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
        post()
    case .denied:
        log("denied: enable notifications for this app in System Settings")
        finish(2)
    case .notDetermined:
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            log("requestAuthorization granted=\(granted) error=\(String(describing: error))")
            if granted {
                post()
            } else {
                finish(2)
            }
        }
    @unknown default:
        finish(4)
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
    log("timeout")
    exit(5)
}

RunLoop.main.run()
