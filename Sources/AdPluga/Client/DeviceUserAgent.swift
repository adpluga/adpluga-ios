import Foundation

/// The User-Agent a WKWebView on this device sends. An SSP prices an in-app
/// impression on device.ua and drops the CFNetwork UA URLSession would send,
/// so the string is built in WebKit's own format rather than read from a
/// WKWebView, which would need the main thread and a web process.
enum DeviceUserAgent {
    static let current: String = make(
        machine: hardwareMachine(),
        version: ProcessInfo.processInfo.operatingSystemVersion
    )

    static func make(machine: String, version: OperatingSystemVersion) -> String {
        var os = "\(version.majorVersion)_\(version.minorVersion)"
        if version.patchVersion > 0 { os += "_\(version.patchVersion)" }
        let device = machine.hasPrefix("iPad") ? "iPad; CPU OS" : "iPhone; CPU iPhone OS"
        return "Mozilla/5.0 (\(device) \(os) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    }

    private static func hardwareMachine() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
