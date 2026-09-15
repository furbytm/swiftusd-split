import Foundation

/// one domain tagged fragment from splitting an extension block per member.
struct StaticTokenPiece
{
  var domain: String
  var chunk: String
  var guardStack: GuardStack
}

final class SwiftSplitter
{
  let classifier: Classifier
  init(classifier: Classifier)
  {
    self.classifier = classifier
  }

  /// matches a bare fileprivate/implicit internal func or static func
  /// anywhere in an item, not just at the start.
  static let promotableFuncRegex = try! NSRegularExpression(
    pattern: #"(?m)^([ \t]*)(?:fileprivate\s+)?(static\s+func|func)\s+([A-Za-z_][A-Za-z0-9_]*)"#
  )

  /// does this brace open a promotable member body? true for class/struct/
  /// enum/extension only - never protocol (requirements are bare on purpose)
  /// or a function/closure/control-flow body (where public is illegal).
  static let typeHeadRegex = try! NSRegularExpression(
    pattern: #"(?:^|[;{}])\s*(?:@\S+(?:\([^)]*\))?\s+)*(?:public\s+|private\s+|fileprivate\s+|internal\s+|final\s+|open\s+)*(?:class|struct|enum|extension)\b"#
  )

  private enum BraceKind: Equatable { case typeBody, other }

  /// brace kind stack just before target: inside a type body (safe to
  /// promote) or inside a function/closure body (not safe, illegal modifier)
  private static func braceKindStack(in text: String, upTo target: String.Index) -> [BraceKind]
  {
    var stack: [BraceKind] = []
    var stmtStart = text.startIndex
    var i = text.startIndex
    while i < target
    {
      let c = text[i]
      if c == "{"
      {
        let head = String(text[stmtStart ..< i]) as NSString
        let isType = typeHeadRegex.firstMatch(in: head as String, range: NSRange(location: 0, length: head.length)) != nil
        stack.append(isType ? .typeBody : .other)
        stmtStart = text.index(after: i)
      }
      else if c == "}"
      {
        if !stack.isEmpty { stack.removeLast() }
        stmtStart = text.index(after: i)
      }
      else if c == ";"
      {
        stmtStart = text.index(after: i)
      }
      i = text.index(after: i)
    }
    return stack
  }

  /// promotes fileprivate/implicit-internal member funcs to public, splitting
  /// can put a caller and callee in different targets, and neither crosses
  /// a target boundary even through @_exported import
  static func promoteInternalDecls(_ text: String) -> String
  {
    let ns = text as NSString
    let full = NSRange(location: 0, length: ns.length)
    var result = ""
    var last = 0
    for m in promotableFuncRegex.matches(in: text, range: full)
    {
      guard let start = Range(m.range, in: text)?.lowerBound else { continue }
      guard braceKindStack(in: text, upTo: start).last ?? .typeBody == .typeBody else { continue }
      result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
      let indent = ns.substring(with: m.range(at: 1))
      let kind = ns.substring(with: m.range(at: 2))
      let name = ns.substring(with: m.range(at: 3))
      result += "\(indent)public \(kind) \(name)"
      last = m.range.location + m.range.length
    }
    result += ns.substring(from: last)
    return result
  }

  static let tfTokenExtensionRegex = try! NSRegularExpression(pattern: #"extension\s+pxr(?:_half)?[.:]TfToken\s*\{"#)
  static let staticPropRegex = try! NSRegularExpression(pattern: #"public\s+static\s+(?:[A-Za-z0-9_]*)\s?var\s+([A-Za-z0-9_]+)\s*:"#)

  /// StaticTokens.swift is one giant extension with a static property per
  /// token class, resplit per property so each lands in its own domain.
  func splitStaticTokensItem(item: String) -> [StaticTokenPiece]?
  {
    let ns = item as NSString
    let full = NSRange(location: 0, length: ns.length)
    guard let m1 = Self.tfTokenExtensionRegex.firstMatch(in: item, range: full) else { return nil }
    let bodyStart = m1.range.location + m1.range.length
    var depth = 1
    var i = bodyStart
    while i < ns.length, depth > 0
    {
      let c = ns.character(at: i)
      if c == UInt16(UnicodeScalar("{").value) { depth += 1 }
      else if c == UInt16(UnicodeScalar("}").value) { depth -= 1 }
      i += 1
    }
    let body = ns.substring(with: NSRange(location: bodyStart, length: (i - 1) - bodyStart))
    let tail = ns.substring(from: i - 1)
    let bodyNS = body as NSString
    let props = Self.staticPropRegex.matches(in: body, range: NSRange(location: 0, length: bodyNS.length))
    guard props.count >= 2 else { return nil }
    let header = ns.substring(to: bodyStart)

    var closes: [Int] = []
    for pr in props
    {
      var d = 0
      var j = pr.range.location
      while j < bodyNS.length
      {
        let c = bodyNS.character(at: j)
        if c == UInt16(UnicodeScalar("{").value) { d += 1 }
        else if c == UInt16(UnicodeScalar("}").value)
        {
          d -= 1
          if d == 0 { break }
        }
        j += 1
      }
      closes.append(j + 1)
    }

    var ctrlStack: [String] = []
    func applyCtrl(_ line: String)
    {
      let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if t.hasPrefix("#if")
      {
        ctrlStack.append(String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces))
      }
      else if t.hasPrefix("#elif")
      {
        if !ctrlStack.isEmpty { ctrlStack[ctrlStack.count - 1] = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
      }
      else if t.hasPrefix("#else")
      {
        if !ctrlStack.isEmpty { ctrlStack[ctrlStack.count - 1] = "!(\(ctrlStack[ctrlStack.count - 1]))" }
      }
      else if t.hasPrefix("#endif")
      {
        if !ctrlStack.isEmpty { ctrlStack.removeLast() }
      }
    }

    var pieces: [StaticTokenPiece] = []
    var gstart = 0
    for (pi, pr) in props.enumerated()
    {
      let preRange = NSRange(location: gstart, length: pr.range.location - gstart)
      for l in bodyNS.substring(with: preRange).splitKeepingEnds()
      {
        let t = l.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#if") || t.hasPrefix("#elif") || t.hasPrefix("#else") || t.hasPrefix("#endif")
        {
          applyCtrl(l)
        }
      }
      let propRange = NSRange(location: pr.range.location, length: closes[pi] - pr.range.location)
      let propText = bodyNS.substring(with: propRange)
      let wrapOpen = ctrlStack.map { "#if \($0)\n" }.joined()
      let wrapClose = String(repeating: "#endif\n", count: ctrlStack.count)
      let text = wrapOpen + propText + "\n" + wrapClose
      let chunk = header + "\n" + text.trimmingTrailingWhitespace() + "\n" + tail
      let propName = bodyNS.substring(with: pr.range(at: 1))
      let d = classifier.classify(propName) ?? classifier.classifyItem(text: chunk)
      pieces.append(StaticTokenPiece(domain: d, chunk: chunk, guardStack: []))
      gstart = closes[pi]
    }
    return pieces
  }

  static let boolExtensionRegex = try! NSRegularExpression(pattern: #"extension\s+Bool\s*\{"#)
  static let boolInitRegex = try! NSRegularExpression(pattern: #"public\s+init\s*\(\s*_\s+[A-Za-z_][A-Za-z0-9_]*\s*:"#)

  // operatorBool.swift is the same shape: one extension Bool with an
  // init(_:) per pxr handle type, resplit per init same as static tokens.
  func splitBoolInitItem(item: String) -> [StaticTokenPiece]?
  {
    let ns = item as NSString
    let full = NSRange(location: 0, length: ns.length)
    guard let m1 = Self.boolExtensionRegex.firstMatch(in: item, range: full) else { return nil }
    let bodyStart = m1.range.location + m1.range.length
    var depth = 1
    var i = bodyStart
    while i < ns.length, depth > 0
    {
      let c = ns.character(at: i)
      if c == UInt16(UnicodeScalar("{").value) { depth += 1 }
      else if c == UInt16(UnicodeScalar("}").value) { depth -= 1 }
      i += 1
    }
    let body = ns.substring(with: NSRange(location: bodyStart, length: (i - 1) - bodyStart))
    let tail = ns.substring(from: i - 1)
    let bodyNS = body as NSString
    let inits = Self.boolInitRegex.matches(in: body, range: NSRange(location: 0, length: bodyNS.length))
    guard inits.count >= 2 else { return nil }
    let header = ns.substring(to: bodyStart)

    var closes: [Int] = []
    for ir in inits
    {
      var d = 0
      var j = ir.range.location
      while j < bodyNS.length
      {
        let c = bodyNS.character(at: j)
        if c == UInt16(UnicodeScalar("{").value) { d += 1 }
        else if c == UInt16(UnicodeScalar("}").value)
        {
          d -= 1
          if d == 0 { break }
        }
        j += 1
      }
      closes.append(j + 1)
    }

    var ctrlStack: [String] = []
    func applyCtrl(_ line: String)
    {
      let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if t.hasPrefix("#if")
      {
        ctrlStack.append(String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces))
      }
      else if t.hasPrefix("#elif")
      {
        if !ctrlStack.isEmpty { ctrlStack[ctrlStack.count - 1] = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
      }
      else if t.hasPrefix("#else")
      {
        if !ctrlStack.isEmpty { ctrlStack[ctrlStack.count - 1] = "!(\(ctrlStack[ctrlStack.count - 1]))" }
      }
      else if t.hasPrefix("#endif")
      {
        if !ctrlStack.isEmpty { ctrlStack.removeLast() }
      }
    }

    var pieces: [StaticTokenPiece] = []
    var gstart = 0
    for (pi, ir) in inits.enumerated()
    {
      let preRange = NSRange(location: gstart, length: ir.range.location - gstart)
      for l in bodyNS.substring(with: preRange).splitKeepingEnds()
      {
        let t = l.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#if") || t.hasPrefix("#elif") || t.hasPrefix("#else") || t.hasPrefix("#endif")
        {
          applyCtrl(l)
        }
      }
      let initRange = NSRange(location: ir.range.location, length: closes[pi] - ir.range.location)
      let initText = bodyNS.substring(with: initRange)
      let wrapOpen = ctrlStack.map { "#if \($0)\n" }.joined()
      let wrapClose = String(repeating: "#endif\n", count: ctrlStack.count)
      let text = wrapOpen + initText + "\n" + wrapClose
      let chunk = header + "\n" + text.trimmingTrailingWhitespace() + "\n" + tail
      let d = classifier.classifyItem(text: chunk)
      pieces.append(StaticTokenPiece(domain: d, chunk: chunk, guardStack: []))
      gstart = closes[pi]
    }
    return pieces
  }

  /// splits one swift source file into per-domain <slug>+<domain>.swift files.
  @discardableResult
  func splitSwiftFile(filename: String, srcDir: String, outSlug: String?) throws -> [(domain: String, count: Int)]
  {
    let srcPath = (srcDir as NSString).appendingPathComponent(filename)
    let src = try String(contentsOfFile: srcPath, encoding: .utf8)
    let baseSlug = outSlug ?? String(filename.dropLast(".swift".count))
    let label = baseSlug + ".swift"

    var buckets: [String: String] = [:]
    for item in Tok.guardedItems(src)
    {
      if let pieces = splitStaticTokensItem(item: item.text)
      {
        for p in pieces
        {
          let wraps = p.guardStack.isEmpty ? p.chunk : "#if \(renderGuard(p.guardStack))\n\(p.chunk)#endif\n"
          buckets[p.domain, default: ""] += wraps
        }
        continue
      }
      if let pieces = splitBoolInitItem(item: item.text)
      {
        for p in pieces
        {
          let wraps = p.guardStack.isEmpty ? p.chunk : "#if \(renderGuard(p.guardStack))\n\(p.chunk)#endif\n"
          buckets[p.domain, default: ""] += wraps
        }
        continue
      }
      let d = classifier.classifyItem(text: item.text)
      let text = Self.promoteInternalDecls(item.text)
      let wraps = item.guardStack.isEmpty ? text : "#if \(renderGuard(item.guardStack))\n\(text)#endif\n"
      buckets[d, default: ""] += wraps
    }

    let fm = FileManager.default
    var counts: [(String, Int)] = []
    for d in TOPS
    {
      guard let body = buckets[d], !body.isEmpty else { continue }
      var out = "// Partition of \(label), domain \(d).\n\n" + body
      if !out.hasSuffix("\n") { out += "\n" }
      let tgt = "\(Paths.swiftOut)/\(d)"
      try fm.createDirectory(atPath: tgt, withIntermediateDirectories: true)
      try out.write(toFile: "\(tgt)/\(baseSlug)+\(d).swift", atomically: true, encoding: .utf8)
      let count = body.components(separatedBy: "extension").count - 1
        + body.components(separatedBy: "\npublic ").count - 1
      counts.append((d, count))
    }
    return counts
  }
}

extension String
{
  func trimmingTrailingWhitespace() -> String
  {
    var s = Substring(self)
    while let last = s.last, last.isWhitespace
    {
      s.removeLast()
    }
    return String(s)
  }
}
