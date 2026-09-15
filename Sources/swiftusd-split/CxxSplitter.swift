import Foundation

final class CxxSplitter
{
  let classifier: Classifier
  init(classifier: Classifier)
  {
    self.classifier = classifier
  }

  static let includeRegex = try! NSRegularExpression(pattern: #"#\s*include\s*[<"](pxr/[^">]+|swiftUsd/[^">]+)[>"]"#)
  /// also catches stdlib includes with no pxr/swiftUsd path, so they get pulled out too.
  static let anyIncludeRegex = try! NSRegularExpression(pattern: #"^\s*#\s*include\b"#)

  /// where setupTargetDir already copied include/swiftUsd before we run.
  static var cxxIncludeRoot: String
  {
    "\(Paths.splitPackage)/Sources/_OpenUSD_SwiftBindingHelpers/include"
  }

  /// keeps only #include lines a module's COVER set can see. pxr/pxr.h
  /// always kept. a swiftUsd/ bridge header is kept only if its own
  /// transitive pxr top footprint fits inside module's COVER.
  func rebuildIncludes(_ text: String, domain: String) -> String
  {
    let keep = COVER[domain] ?? []
    var out: [String] = []
    var memo: [String: Set<String>] = [:]
    for line in text.splitKeepingEnds()
    {
      let ns = line as NSString
      if let m = Self.includeRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
      {
        let inc = ns.substring(with: m.range(at: 1))
        if inc == "pxr/pxr.h"
        {
          out.append(line)
        }
        else if inc.hasPrefix("swiftUsd/")
        {
          var stack = Set<String>()
          let tops = ModuleMapGenerator.transitivePxrTops(inc, incRoot: Self.cxxIncludeRoot, memo: &memo, stack: &stack)
          if let d = ModuleMapGenerator.lub(tops), !keep.contains(d)
          {
            // needs a module we can't see, drop it.
          }
          else
          {
            out.append(line)
          }
        }
        else
        {
          let top = inc.split(separator: "/").dropFirst().first.map(String.init) ?? ""
          if keep.contains(top) { out.append(line) }
        }
        continue
      }
      out.append(line)
    }
    return out.joined()
  }

  /// pulls every #include out of src into one block, returns the rest with
  /// those lines removed, otherwise a file with no namespace wrapping has
  /// no prologue and every include glues onto whatever item follows it.
  static func extractIncludes(_ src: String) -> (includes: String, stripped: String)
  {
    var includeLines: [String] = []
    var strippedLines: [String] = []
    for line in src.splitKeepingEnds()
    {
      let ns = line as NSString
      if anyIncludeRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
      {
        includeLines.append(line)
      }
      else
      {
        strippedLines.append(line)
      }
    }
    return (includeLines.joined(), strippedLines.joined())
  }

  /// safety net: drops any #endif/#else/#elif with no matching #if left.
  static func dropStrayGuardLines(_ text: String) -> String
  {
    var out: [String] = []
    var depth = 0
    for line in text.splitKeepingEnds()
    {
      let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if t.hasPrefix("#if")
      {
        depth += 1
        out.append(line)
      }
      else if t.hasPrefix("#endif")
      {
        if depth > 0 { depth -= 1; out.append(line) }
      }
      else if t.hasPrefix("#else") || t.hasPrefix("#elif")
      {
        if depth > 0 { out.append(line) }
      }
      else
      {
        out.append(line)
      }
    }
    return out.joined()
  }

  /// splits a C++ bridge header by module, writes {baseSlug}+{domain}.h.
  @discardableResult
  func splitSource(_ src: String, baseSlug: String, hguard: String) throws -> [(domain: String, lines: Int)]
  {
    let fm = FileManager.default
    try fm.createDirectory(atPath: Paths.cxxOut, withIntermediateDirectories: true)
    for old in try fm.contentsOfDirectory(atPath: Paths.cxxOut) where old.hasPrefix(baseSlug + "+")
    {
      try? fm.removeItem(atPath: "\(Paths.cxxOut)/\(old)")
    }

    // pull includes out before namespace/item scanning, see extractIncludes.
    let (masterIncludes, strippedSrc) = Self.extractIncludes(src)

    var (prologueOpt, blocks, epilogue) = NamespaceScanner.scan(strippedSrc)
    let wrapOverlay = prologueOpt != nil
    var prologue = prologueOpt ?? ""
    if !wrapOverlay
    {
      // no namespace wrapping, everything is one flat block
      blocks = [NamespaceBlock(name: "", body: HeaderGuard.strip(strippedSrc))]
      prologue = ""
      epilogue = ""
    }
    _ = prologueOpt // silence unused warning when wrapOverlay is false

    // module -> namespace name -> accumulated body text.
    var buckets: [String: [String: String]] = [:]
    // bare marker namespaces (no decls, no pxr refs) still need to exist
    // somewhere, default them to base so they're visible everywhere.
    var forceEmit = Set<String>() // "domain\u{0}name"

    for block in blocks
    {
      let items = Tok.guardedItems(block.body)
      if wrapOverlay, items.isEmpty, block.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        buckets["base", default: [:]][block.name, default: ""] += ""
        forceEmit.insert("base\u{0}\(block.name)")
        continue
      }
      for item in items
      {
        let d = classifier.classifyItem(text: item.text)
        let wraps = item.guardStack.isEmpty ? item.text : "#if \(renderGuard(item.guardStack))\n\(item.text)#endif\n"
        buckets[d, default: [:]][block.name, default: ""] += wraps
      }
    }

    var counts: [(String, Int)] = []
    for (d, nsBodies) in buckets
    {
      let hasContent = nsBodies.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      let hasForced = nsBodies.keys.contains { forceEmit.contains("\(d)\u{0}\($0)") }
      guard hasContent || hasForced else { continue }

      let parts: String = if wrapOverlay
      {
        nsBodies
          .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || forceEmit.contains("\(d)\u{0}\($0.key)") }
          .map { "namespace \($0.key) {\n\($0.value)\n}\n" }
          .joined()
      }
      else
      {
        nsBodies.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined()
      }
      var fileText = "// Partition of \(baseSlug).h, domain \(d).\n\n"
      fileText += "#ifndef \(hguard)_\(d.uppercased())_H\n#define \(hguard)_\(d.uppercased())_H\n\n"
      fileText += masterIncludes
      fileText += prologue
      fileText += "\n" + parts
      fileText += epilogue
      fileText += "#endif /* \(hguard)_\(d.uppercased())_H */\n"
      fileText = rebuildIncludes(fileText, domain: d)
      fileText = Self.dropStrayGuardLines(fileText)
      try fileText.write(toFile: "\(Paths.cxxOut)/\(baseSlug)+\(d).h", atomically: true, encoding: .utf8)
      let lineCount = nsBodies.values.reduce(0) { $0 + $1.components(separatedBy: "\n").count }
      counts.append((d, lineCount))
    }
    return counts
  }

  @discardableResult
  func splitCxxFile(filename: String) throws -> [(domain: String, lines: Int)]
  {
    let path = "\(Paths.monoGenCxx)/\(filename)"
    let baseSlug = String(filename.dropLast(".h".count))
    let hguard = "SWIFTUSD_GENERATED_\(baseSlug.uppercased())"
    let src = try String(contentsOfFile: path, encoding: .utf8)
    return try splitSource(src, baseSlug: baseSlug, hguard: hguard)
  }

  @discardableResult
  func splitCxxHandFile(filename: String, srcDir: String, outSlug: String) throws -> [(domain: String, lines: Int)]
  {
    let path = (srcDir as NSString).appendingPathComponent(filename)
    let hguard = "SWIFTUSD_GENERATED_\(outSlug.uppercased())"
    let src = try String(contentsOfFile: path, encoding: .utf8)
    return try splitSource(src, baseSlug: outSlug, hguard: hguard)
  }
}
