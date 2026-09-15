import Foundation

/// parses apple/SwiftUsd's own Package.swift for its xcframework list,
/// instead of hand-copying it, so a version bump is picked up automatically.
enum Xcframeworks
{
  struct Entry
  {
    var target: String // e.g. "_Usd_Usd_xcframework"
    var xcframeworkFile: String // e.g. "Usd_Usd.xcframework"
    var platforms: Set<String>
  }

  static let binaryTargetRegex = try! NSRegularExpression(
    pattern: #"\.binaryTarget\(name:\s*"(_[A-Za-z0-9_]+_xcframework)",\s*path:\s*"swift-package/Libraries/([^"]+\.xcframework)"\)"#
  )
  static let depRegex = try! NSRegularExpression(
    pattern: #"\.target\(name:\s*"(_[A-Za-z0-9_]+_xcframework)"\s*,\s*condition:\s*\.when\(platforms:\s*\[([^\]]*)\]\)\)"#
  )

  /// every xcframework with a macOS slice, sorted for deterministic output.
  static func macOSEntries() throws -> [Entry]
  {
    let path = "\(Paths.swiftUsdRoot)/Package.swift"
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let ns = text as NSString
    let full = NSRange(location: 0, length: ns.length)

    var files: [String: String] = [:]
    for m in binaryTargetRegex.matches(in: text, range: full)
    {
      files[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
    }

    var entries: [Entry] = []
    for m in depRegex.matches(in: text, range: full)
    {
      let name = ns.substring(with: m.range(at: 1))
      let platformsRaw = ns.substring(with: m.range(at: 2))
      let platforms = Set(platformsRaw.split(separator: ",").map
      {
        $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "")
      })
      guard platforms.contains("macOS"), let file = files[name] else { continue }
      entries.append(Entry(target: name, xcframeworkFile: file, platforms: platforms))
    }
    return entries.sorted { $0.target < $1.target }
  }
}
