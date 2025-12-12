import Foundation

final class UniversalBleLogger {
  static let shared = UniversalBleLogger()

  private init() {}

  private lazy var dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  private var currentLogLevel: UniversalBleLogLevel = .none

  func setLogLevel(_ logLevel: UniversalBleLogLevel) {
    currentLogLevel = logLevel
  }

  func logError(_ message: String) {
    guard allows(.error) else { return }
    print("UniversalBle:ERROR \(withTimestamp(message))")
  }

  func logWarning(_ message: String) {
    guard allows(.warning) else { return }
    print("UniversalBle:WARN \(withTimestamp(message))")
  }

  func logInfo(_ message: String) {
    guard allows(.info) else { return }
    print("UniversalBle:INFO \(withTimestamp(message))")
  }

  func logDebug(_ message: String) {
    guard allows(.debug) else { return }
    print("UniversalBle:DEBUG \(withTimestamp(message))")
  }

  func logVerbose(_ message: String) {
    guard allows(.verbose) else { return }
    print("UniversalBle:VERBOSE \(withTimestamp(message))")
  }

  private func allows(_ level: UniversalBleLogLevel) -> Bool {
    return currentLogLevel != .none && level.rawValue <= currentLogLevel.rawValue
  }

  private func withTimestamp(_ message: String) -> String {
    let time = dateFormatter.string(from: Date())
    return "[\(time)] \(message)"
  }
}
