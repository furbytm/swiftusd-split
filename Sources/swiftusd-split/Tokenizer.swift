import Foundation

/// one #if/#ifdef/#ifndef condition on the guard stack.
struct GuardCondition
{
  var negated: Bool
  var raw: String
}

typealias GuardStack = [GuardCondition]

func renderGuard(_ stack: GuardStack) -> String
{
  stack.map { $0.negated ? "!(\($0.raw))" : $0.raw }.joined(separator: " && ")
}

/// one flattened top-level item: its guard stack plus source text.
struct SourceItem
{
  var guardStack: GuardStack
  var text: String
}

enum Tok
{
  // strip leading @attributes so the real keyword decides the item boundary.
  static let leadingAttrs = try! NSRegularExpression(pattern: #"^(?:@\w+(?:\([^)]*\))?\s+)+"#)
  static let itemStartRegex = try! NSRegularExpression(pattern:
    #"^(?:public\s+)?(?:extension|struct|class|enum|protocol|typealias|func|"# +
      #"fileprivate\s+func|static\s+func|let|var|"# +
      #"template\s*[<\[]|using\s+|typedef\s+|[A-Za-z_][\w:<>,\s*&]*\s+[A-Za-z_~][\w]*\s*\(|"# +
      #"inline\b|constexpr\b|extern\b)"#)

  static func isItemStart(_ s: String) -> Bool
  {
    let stripped = leadingAttrs.stringByReplacingMatches(
      in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: ""
    )
    let ns = stripped as NSString
    return itemStartRegex.firstMatch(in: stripped, range: NSRange(location: 0, length: ns.length)) != nil
  }

  /// flattens #if/#else/#endif blocks, returns ordered items with their guard stack.
  static func guardedItems(_ source: String) -> [SourceItem]
  {
    var stack: GuardStack = []
    var out: [SourceItem] = []
    var braceDepth = 0
    var pending: [String] = []

    func flush()
    {
      defer { pending = [] }
      let text = pending.joined()
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      let g = stack
      var cur: [String] = []
      var depth = 0
      let lines = text.splitKeepingEnds()
      for line in lines
      {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let at0 = depth == 0
        if at0, !cur.isEmpty, isItemStart(s), !s.hasPrefix("//")
        {
          out.append(SourceItem(guardStack: g, text: cur.joined()))
          cur = []
        }
        cur.append(line)
        depth += line.count(where: { $0 == "{" }) - line.count(where: { $0 == "}" })
      }
      if cur.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
      {
        out.append(SourceItem(guardStack: g, text: cur.joined()))
      }
    }

    for line in source.splitKeepingEnds()
    {
      let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if braceDepth == 0, s.hasPrefix("#if") || s.hasPrefix("#else") || s.hasPrefix("#elif") || s.hasPrefix("#endif")
      {
        flush()
        if s.hasPrefix("#endif")
        {
          if !stack.isEmpty { stack.removeLast() }
        }
        else if s.hasPrefix("#ifndef")
        {
          // handle separately so slicing after "#if" doesn't mangle it.
          let cond = String(s.dropFirst("#ifndef".count)).trimmingCharacters(in: .whitespaces)
          stack.append(GuardCondition(negated: true, raw: "defined(\(cond))"))
        }
        else if s.hasPrefix("#ifdef")
        {
          let cond = String(s.dropFirst("#ifdef".count)).trimmingCharacters(in: .whitespaces)
          stack.append(GuardCondition(negated: false, raw: "defined(\(cond))"))
        }
        else if s.hasPrefix("#if")
        {
          let cond = String(s.dropFirst("#if".count)).trimmingCharacters(in: .whitespaces)
          stack.append(GuardCondition(negated: false, raw: cond))
        }
        else if s.hasPrefix("#elif")
        {
          if !stack.isEmpty
          {
            let top = stack.removeLast()
            stack.append(GuardCondition(negated: true, raw: top.raw))
            let cond = String(s.dropFirst("#elif".count)).trimmingCharacters(in: .whitespaces)
            stack.append(GuardCondition(negated: false, raw: cond))
          }
        }
        else
        { // #else
          if !stack.isEmpty
          {
            stack[stack.count - 1].negated.toggle()
          }
        }
        continue
      }
      pending.append(line)
      braceDepth += line.count(where: { $0 == "{" }) - line.count(where: { $0 == "}" })
      if braceDepth < 0 { braceDepth = 0 }
    }
    flush()
    return out
  }
}

extension String
{
  /// like python's splitlines(keepends=True).
  func splitKeepingEnds() -> [String]
  {
    var out: [String] = []
    var current = ""
    for ch in self
    {
      current.append(ch)
      if ch == "\n"
      {
        out.append(current)
        current = ""
      }
    }
    if !current.isEmpty { out.append(current) }
    return out
  }
}

/// one top-level namespace __Overlay/Overlay/SwiftUsd { ... } block
struct NamespaceBlock
{
  var name: String
  var body: String
}

enum NamespaceScanner
{
  static let blockStartRegex = try! NSRegularExpression(pattern: #"namespace\s+(__Overlay|Overlay|SwiftUsd)\s*\{"#)

  /// finds every top level namespace block, in order (some headers reopen
  /// it hundreds of times). prologue = before the first block, epilogue =
  /// after the last, both guard-stripped. nil prologue means no blocks at
  /// all, fall back to treating the file as flat top level items.
  static func scan(_ src: String) -> (prologue: String?, blocks: [NamespaceBlock], epilogue: String)
  {
    let ns = src as NSString
    var blocks: [NamespaceBlock] = []
    var firstStart: Int?
    var pos = 0
    for m in blockStartRegex.matches(in: src, range: NSRange(location: 0, length: ns.length))
    {
      if m.range.location < pos { continue } // already inside a consumed block
      if firstStart == nil { firstStart = m.range.location }
      let name = ns.substring(with: m.range(at: 1))
      var depth = 1
      var i = m.range.location + m.range.length
      let chars = ns
      while i < chars.length, depth > 0
      {
        let c = chars.character(at: i)
        if c == UInt16(UnicodeScalar("{").value) { depth += 1 }
        else if c == UInt16(UnicodeScalar("}").value) { depth -= 1 }
        i += 1
      }
      let bodyRange = NSRange(location: m.range.location + m.range.length,
                              length: (i - 1) - (m.range.location + m.range.length))
      blocks.append(NamespaceBlock(name: name, body: chars.substring(with: bodyRange)))
      pos = i
    }
    guard let firstStart else { return (nil, [], "") }
    let prologueRange = NSRange(location: 0, length: firstStart)
    let epilogueRange = NSRange(location: pos, length: ns.length - pos)
    let epilogue = HeaderGuard.stripTrailingEndif(ns.substring(with: epilogueRange))
    return (HeaderGuard.strip(ns.substring(with: prologueRange)), blocks, epilogue)
  }
}

enum HeaderGuard
{
  static let anyGuardRegex = try! NSRegularExpression(pattern: #"#ifndef [A-Za-z0-9_]+_H\n#define [A-Za-z0-9_]+_H\n"#)

  static func strip(_ prologue: String) -> String
  {
    let ns = prologue as NSString
    guard let m = anyGuardRegex.firstMatch(in: prologue, range: NSRange(location: 0, length: ns.length))
    else
    {
      return prologue
    }
    return ns.substring(to: m.range.location) + ns.substring(from: m.range.location + m.range.length)
  }

  /// drops the file's own trailing #endif, each domain writes its own.
  static func stripTrailingEndif(_ text: String) -> String
  {
    var lines = text.splitKeepingEnds()
    guard let lastIdx = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    else
    {
      return text
    }
    let trimmed = lines[lastIdx].trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("#endif") else { return text }
    lines.remove(at: lastIdx)
    return lines.joined()
  }
}
