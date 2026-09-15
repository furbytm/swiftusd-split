import Foundation

/// classifies pxr type names and source items into one of the six top level modules.
final class Classifier
{
  let nameDir: [String: String]
  /// ABBR keys sorted longest first, classify always wants longest prefix.
  private let abbrByLength: [(prefix: String, domain: String)]

  init(nameDir: [String: String])
  {
    self.nameDir = nameDir.filter { $0.key.count >= 3 && $0.key.first?.isUppercase == true }
    abbrByLength = ABBR.sorted { $0.key.count > $1.key.count }.map { ($0.key, $0.value) }
  }

  /// resolve a possibly qualified name to its module, longest prefix wins.
  func classify(_ name: String) -> String?
  {
    let outer = String(name.split(separator: ".", maxSplits: 1).first ?? Substring(name))
      .split(separator: ":", maxSplits: 1).first.map(String.init) ?? name
    var best = ""
    var bestDomain: String?
    for (nm, d) in nameDir where outer.hasPrefix(nm) && nm.count > best.count
    {
      best = nm
      bestDomain = d
    }
    if let bestDomain { return bestDomain }
    for (prefix, domain) in abbrByLength where outer.hasPrefix(prefix)
    {
      return domain
    }
    return nil
  }

  /// matches pxr.X / pxr::X, and Overlay.X / Overlay::X wrapper refs,
  /// needs both separators since this scans generated swift AND C++ text.
  static let pxrRefRegex = try! NSRegularExpression(
    pattern: #"pxr(?:_half)?(?:\.|::)[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*|(?:__Overlay|Overlay|__OverlaySwift)(?:\.|::)[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*"#
  )
  static let pxrRefPrefixStrip = try! NSRegularExpression(
    pattern: #"^(?:pxr_half|pxr|__Overlay|Overlay|__OverlaySwift)(?:\.|::)"#
  )

  /// every distinct outer type name referenced anywhere in text.
  func pxrRefs(_ text: String) -> Set<String>
  {
    let ns = text as NSString
    let full = NSRange(location: 0, length: ns.length)
    var out = Set<String>()
    for m in Self.pxrRefRegex.matches(in: text, range: full)
    {
      let raw = ns.substring(with: m.range)
      let rawNS = raw as NSString
      let stripped = Self.pxrRefPrefixStrip.stringByReplacingMatches(
        in: raw, range: NSRange(location: 0, length: rawNS.length), withTemplate: ""
      )
      out.insert(String(stripped.split(separator: ".", maxSplits: 1).first ?? Substring(stripped)))
    }
    return out
  }

  func dirsOf(_ text: String) -> Set<String>
  {
    Set(pxrRefs(text).compactMap { classify($0) })
  }

  /// smallest module that can see everything in dirs, empty defaults to base.
  func lub(_ dirs: Set<String>) -> String?
  {
    if dirs.isEmpty { return "base" }
    var best: String?
    var bestSize = Int.max
    for top in TOPS + ["glue"]
    {
      guard let cover = COVER[top], dirs.isSubset(of: cover), cover.count < bestSize else { continue }
      best = top
      bestSize = cover.count
    }
    return best
  }

  static let overlayPrefixes = ["__Overlay.", "Overlay.", "__OverlaySwift."]
  static let extensionTargetRegex = try! NSRegularExpression(
    pattern: #"extension\s+(pxr(?:_half)?[.:][A-Za-z0-9_:.]+|(?:__Overlay|Overlay|__OverlaySwift)\.[A-Za-z0-9_]+)"#
  )

  /// classify one item: prefer its own extension target, else LUB the body.
  func classifyItem(text: String) -> String
  {
    let ns = text as NSString
    let full = NSRange(location: 0, length: ns.length)
    if let m = Self.extensionTargetRegex.firstMatch(in: text, range: full)
    {
      var key = ns.substring(with: m.range(at: 1))
      if let prefix = Self.overlayPrefixes.first(where: { key.hasPrefix($0) })
      {
        let rest = String(key.dropFirst(prefix.count))
        let name = String(rest.split(separator: ".", maxSplits: 1).first ?? Substring(rest))
        if let d = classify(name) { return d }
      }
      else
      {
        key = String(key.split(separator: ":", maxSplits: 1).first ?? Substring(key))
        let parts = key.split(separator: ".", maxSplits: 1)
        let name = parts.count > 1 ? String(parts[1]) : String(parts[0])
        if let d = classify(name) { return d }
      }
    }
    return lub(dirsOf(text)) ?? "glue"
  }
}
