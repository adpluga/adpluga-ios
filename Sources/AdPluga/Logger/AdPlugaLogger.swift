import Foundation

public enum AdPlugaLogger {
    public static var enabled: Bool = false

    public static func debug(_ message: String, error: Error? = nil) {
        guard enabled else { return }
        emit("[AdPluga][DEBUG] \(message)", error: error)
    }

    public static func info(_ message: String) {
        guard enabled else { return }
        emit("[AdPluga][INFO] \(message)", error: nil)
    }

    public static func warn(_ message: String, error: Error? = nil) {
        guard enabled else { return }
        emit("[AdPluga][WARN] \(message)", error: error)
    }

    public static func error(_ message: String, error: Error? = nil) {
        emit("[AdPluga][ERROR] \(message)", error: error)
    }

    private static func emit(_ line: String, error: Error?) {
        if let err = error {
            NSLog("%@: %@", line, String(describing: err))
        } else {
            NSLog("%@", line)
        }
    }
}
