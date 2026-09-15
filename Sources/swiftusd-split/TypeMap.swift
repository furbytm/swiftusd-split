import Foundation

/// pxr type name -> domain, scanned from each domain's pxr/<top>/ tree.
enum TypeMap
{
  /// class|struct|enum Name, tolerates an export macro and trailing final.
  static let declRegex = try! NSRegularExpression(
    pattern: #"\b(?:class|struct|enum)(?:\s+class)?\s+(?:[A-Z][A-Z0-9_]*\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:final\s*)?(?::[^;{]*)?\{"#
  )
  static let fwdRegex = try! NSRegularExpression(
    pattern: #"\b(?:class|struct|enum)(?:\s+class)?\s+([A-Za-z_][A-Za-z0-9_]*)\s*;"#
  )
  static let usingRegex = try! NSRegularExpression(
    pattern: #"\busing\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]+);"#
  )
  /// typedef OldType NewName; - new name comes last, unlike using.
  static let typedefRegex = try! NSRegularExpression(
    pattern: #"\btypedef\s+([^;{]+?)\s+([A-Za-z_][A-Za-z0-9_]*)\s*;"#
  )
  /// a pure alias just reexports, don't let it steal the real decl's domain.
  static let pureAliasRegex = try! NSRegularExpression(pattern: #"^(?:pxr::)?[A-Za-z_][A-Za-z0-9_:]*$"#)
  /// TF_DECLARE_PUBLIC_TOKENS macro-expands with no literal class/struct text.
  static let tokenMacroRegex = try! NSRegularExpression(pattern: #"\bTF_DECLARE_PUBLIC_TOKENS\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)"#)

  static func build() -> [String: String]
  {
    var nameDir: [String: String] = [:]
    var fwdDir: [String: String] = [:]

    for top in TOPS
    {
      let root = URL(fileURLWithPath: Paths.include).appendingPathComponent("pxr/\(top)")
      guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
      for case let fileURL as URL in enumerator
      {
        let ext = fileURL.pathExtension
        guard ext == "h" || ext == "hpp" else { continue }
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        // forward decls are low priority, the real decl should win.
        for m in fwdRegex.matches(in: text, range: full)
        {
          let ident = ns.substring(with: m.range(at: 1))
          if fwdDir[ident] == nil { fwdDir[ident] = top }
        }
        for m in declRegex.matches(in: text, range: full)
        {
          let ident = ns.substring(with: m.range(at: 1))
          nameDir[ident] = top
        }
        for m in usingRegex.matches(in: text, range: full)
        {
          let ident = ns.substring(with: m.range(at: 1))
          let rhs = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
          let rhsRange = NSRange(location: 0, length: (rhs as NSString).length)
          if pureAliasRegex.firstMatch(in: rhs, range: rhsRange) != nil { continue }
          nameDir[ident] = top
        }
        for m in typedefRegex.matches(in: text, range: full)
        {
          let rhs = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
          let ident = ns.substring(with: m.range(at: 2))
          let rhsRange = NSRange(location: 0, length: (rhs as NSString).length)
          if pureAliasRegex.firstMatch(in: rhs, range: rhsRange) != nil { continue }
          nameDir[ident] = top
        }
        for m in tokenMacroRegex.matches(in: text, range: full)
        {
          let ident = ns.substring(with: m.range(at: 1))
          nameDir[ident] = top
          nameDir[ident + "_StaticTokenType"] = top
        }
      }
    }
    for (k, v) in fwdDir where nameDir[k] == nil
    {
      nameDir[k] = v
    }
    return nameDir
  }

  static func write(_ nameDir: [String: String], to path: String) throws
  {
    let sorted = nameDir.sorted { $0.key < $1.key }
    var obj: [String: String] = [:]
    for (k, v) in sorted
    {
      obj[k] = v
    }
    let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    try data.write(to: URL(fileURLWithPath: path))
  }

  static func load(from path: String) throws -> [String: String]
  {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONSerialization.jsonObject(with: data) as? [String: String] ?? [:]
  }
}
