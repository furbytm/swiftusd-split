import Foundation

/// splits the monolithic module.modulemap into six top level clang modules,
/// routed by header dir or by LUB of a bridge header's transitive includes.
enum ModuleMapGenerator
{
  static func moduleName(_ top: String) -> String
  {
    "_OpenUSD_" + top.prefix(1).uppercased() + top.dropFirst()
  }

  /// narrower than Classifier.lub - only real bridge-header #include combos
  /// are named, anything else has no single module that can see it all.
  static func lub(_ dirs: Set<String>) -> String?
  {
    if dirs.isEmpty { return "base" }
    if dirs.isSubset(of: ["base"]) { return "base" }
    if dirs.isSubset(of: ["base", "usd"]) { return "usd" }
    if dirs.isSubset(of: ["base", "usd", "exec"]) { return "exec" }
    if dirs.isSubset(of: ["base", "imaging"]) { return "imaging" }
    if dirs.isSubset(of: ["base", "usd", "usdValidation"]) { return "usdValidation" }
    if dirs.isSubset(of: ["base", "exec", "imaging", "usd", "usdImaging"]) { return "usdImaging" }
    return nil
  }

  static let includeRegex = try! NSRegularExpression(pattern: #"#\s*include\s*[<"]((?:pxr|swiftUsd)/[^">]+)[>"]"#)

  /// follows a bridge header's #includes transitively, collects every pxr top it reaches.
  static func transitivePxrTops(_ rel: String, incRoot: String, memo: inout [String: Set<String>], stack: inout Set<String>) -> Set<String>
  {
    if let cached = memo[rel] { return cached }
    if stack.contains(rel) { return [] } // cycle guard
    let path = (incRoot as NSString).appendingPathComponent(rel)
    guard FileManager.default.fileExists(atPath: path), let text = try? String(contentsOfFile: path, encoding: .utf8)
    else
    {
      memo[rel] = []
      return []
    }
    stack.insert(rel)
    var tops = Set<String>()
    for line in text.splitKeepingEnds()
    {
      let ns = line as NSString
      guard let m = includeRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
      let inc = ns.substring(with: m.range(at: 1))
      if inc == "pxr/pxr.h"
      {
        tops.insert("base")
      }
      else if inc.hasPrefix("pxr/")
      {
        let top = inc.split(separator: "/").dropFirst().first.map(String.init) ?? ""
        if TOPS.contains(top) { tops.insert(top) }
      }
      else if inc.hasPrefix("swiftUsd/")
      {
        tops.formUnion(transitivePxrTops(inc, incRoot: incRoot, memo: &memo, stack: &stack))
      }
    }
    stack.remove(rel)
    memo[rel] = tops
    return tops
  }

  static let generatedDomainRegex = try! NSRegularExpression(pattern: #"swiftUsd/generated/[^/]+\+([A-Za-z]+)\.h$"#)

  static func routeSwiftUsd(_ header: String, incRoot: String, memo: inout [String: Set<String>]) -> String
  {
    let ns = header as NSString
    if let m = generatedDomainRegex.firstMatch(in: header, range: NSRange(location: 0, length: ns.length))
    {
      let top = ns.substring(with: m.range(at: 1))
      if TOPS.contains(top) { return top }
      if top == "glue" { return "glue" }
      fatalError("unknown generated domain in \(header)")
    }
    if header.hasPrefix("swiftUsd/generated/")
    {
      return "exclude" // monolithic headers, kept for .cpp's, not in any module.
    }
    let rel = String(header.dropFirst("swiftUsd/".count))
    var stack = Set<String>()
    let tops = transitivePxrTops(rel, incRoot: "\(incRoot)/swiftUsd", memo: &memo, stack: &stack)
    return lub(tops) ?? "glue"
  }

  static func route(_ header: String, incRoot: String, memo: inout [String: Set<String>]) -> String
  {
    if header == "pxr/pxr.h" { return "base" }
    if header.hasPrefix("pxr/")
    {
      let top = header.split(separator: "/").dropFirst().first.map(String.init) ?? ""
      if TOPS.contains(top) { return top }
      fatalError("unroutable pxr header: \(header)")
    }
    if header.hasPrefix("swiftUsd/") { return routeSwiftUsd(header, incRoot: incRoot, memo: &memo) }
    fatalError("unroutable header: \(header)")
  }

  /// parses the monolithic module body into its header list + everything else as an opaque tail.
  static func parseMap(_ path: String) throws -> (headers: [String], tail: [String])
  {
    let content = try String(contentsOfFile: path, encoding: .utf8)
    var headers: [String] = []
    var tail: [String] = []
    var inBinding = false
    for line in content.split(separator: "\n", omittingEmptySubsequences: false)
    {
      let s = line.trimmingCharacters(in: .whitespaces)
      if s == "module _OpenUSD_SwiftBindingHelpers {"
      {
        inBinding = true
        continue
      }
      if inBinding
      {
        if s == "}" { inBinding = false; continue }
        if s.hasPrefix("//") || s.isEmpty { continue }
        guard s.hasPrefix("header ") else { fatalError("unhandled line in module body: \(line)") }
        var h = String(s.dropFirst("header ".count)).trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("\""), h.hasSuffix("\"") { h = String(h.dropFirst().dropLast()) }
        headers.append(h)
        continue
      }
      tail.append(String(line))
    }
    return (headers, tail)
  }

  static func genMap(headers: [String], routes: [String: String], glueList: inout [String], tail: [String]) -> String
  {
    var buckets: [String: [String]] = Dictionary(uniqueKeysWithValues: TOPS.map { ($0, []) })
    var excluded: [String] = []
    for h in headers
    {
      switch routes[h]
      {
        case "exclude": excluded.append(h)
        case "glue": glueList.append(h)
        case let .some(r): buckets[r, default: []].append(h)
        case .none: break
      }
    }
    var out: [String] = []
    out.append("// Generated by swiftusd-split. Do not edit!\n")
    out.append("// Six top level C++ modules replacing the monolithic _OpenUSD_SwiftBindingHelpers module.\n")
    out.append("// Header partition: " + TOPS.map { "\(moduleName($0))=\(buckets[$0]?.count ?? 0)" }.joined(separator: ", ") + "\n")
    if !excluded.isEmpty
    {
      out.append("// Excluded from modules (compiled textually by the .cpp/.mm sources): " + excluded.joined(separator: ", ") + "\n")
    }
    if !glueList.isEmpty
    {
      out.append("// _OpenUSD_Glue (no LUB in the module DAG): " + glueList.joined(separator: ", ") + "\n")
    }
    for top in TOPS
    {
      out.append("module \(moduleName(top)) {\n")
      for h in (buckets[top] ?? []).sorted()
      {
        out.append("    header \"\(h)\"\n")
      }
      out.append("    export *\n")
      out.append("}\n")
    }
    if !glueList.isEmpty
    {
      out.append("module _OpenUSD_Glue {\n")
      for h in glueList.sorted()
      {
        out.append("    header \"\(h)\"\n")
      }
      out.append("    export *\n")
      out.append("}\n")
    }
    out.append("module _OpenUSD_SwiftBindingHelpers {\n")
    for top in TOPS
    {
      out.append("    export \(moduleName(top))\n")
    }
    if !glueList.isEmpty
    {
      out.append("    export _OpenUSD_Glue\n")
    }
    out.append("}\n")
    out.append("\n// Swift can detect Usd feature flags at compile time by using `#if canImport(SwiftUsd_PXR_ENABLE_<flag>_SUPPORT)`\n")
    out.append(tail.joined(separator: "\n"))
    return out.joined()
  }

  static func writeApinotes(destDir: String, tops: [String]) throws
  {
    let content = try String(contentsOfFile: Paths.monoApinotes, encoding: .utf8)
    let nameRegex = try! NSRegularExpression(pattern: #"^Name: .*$"#, options: [.anchorsMatchLines])
    for top in tops
    {
      let name = moduleName(top)
      let ns = content as NSString
      let range = nameRegex.rangeOfFirstMatch(in: content, range: NSRange(location: 0, length: ns.length))
      var replaced = content
      if range.location != NSNotFound
      {
        replaced = ns.replacingCharacters(in: range, with: "Name: \(name)")
      }
      try replaced.write(toFile: "\(destDir)/\(name).apinotes", atomically: true, encoding: .utf8)
    }
  }

  /// sets up _OpenUSD_SwiftBindingHelpers: symlinked to the monolithic
  /// package except include/swiftUsd, copied fresh so splitters can write there.
  static func setupTargetDir(_ destRoot: String) throws
  {
    let fm = FileManager.default
    if let attrs = try? fm.attributesOfItem(atPath: destRoot), attrs[.type] as? FileAttributeType == .typeSymbolicLink
    {
      try fm.removeItem(atPath: destRoot)
    }
    try fm.createDirectory(atPath: destRoot, withIntermediateDirectories: true)
    let inc = "\(destRoot)/include"
    try fm.createDirectory(atPath: inc, withIntermediateDirectories: true)
    let monoInc = "\(Paths.monoHelpers)/include"

    for entry in try fm.contentsOfDirectory(atPath: monoInc).sorted()
    {
      let link = "\(inc)/\(entry)"
      let target = "\(monoInc)/\(entry)"
      if entry == "swiftUsd"
      {
        if fm.fileExists(atPath: link) || isSymlink(link)
        {
          try? fm.removeItem(atPath: link)
        }
        try fm.copyItem(atPath: target, toPath: link)
        try rebindDanglingSymlinks(under: link, monoTarget: target)
        continue
      }
      if entry == "module.modulemap" { continue } // we generate our own.
      if entry == "_OpenUSD_SwiftBindingHelpers.apinotes" { continue } // superseded by our per module copies.
      if !fm.fileExists(atPath: link), !isSymlink(link)
      {
        try fm.createSymbolicLink(atPath: link, withDestinationPath: target)
      }
    }
    for entry in ["SwiftOverlay", "TfNotice", "Util", "Work", "Wrappers", "generated"]
    {
      let link = "\(destRoot)/\(entry)"
      let target = "\(Paths.monoHelpers)/\(entry)"
      if !fm.fileExists(atPath: link), !isSymlink(link)
      {
        try fm.createSymbolicLink(atPath: link, withDestinationPath: target)
      }
    }
  }

  private static func isSymlink(_ path: String) -> Bool
  {
    (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
  }

  private static func rebindDanglingSymlinks(under link: String, monoTarget: String) throws
  {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(atPath: link) else { return }
    for case let rel as String in enumerator
    {
      let p = "\(link)/\(rel)"
      guard isSymlink(p), !fm.fileExists(atPath: p) else { continue } // dangling symlink only.
      let monoP = "\(monoTarget)/\(rel)"
      let dest: String
      if let monoLinkDest = try? fm.destinationOfSymbolicLink(atPath: monoP)
      {
        let resolved = ((monoP as NSString).deletingLastPathComponent as NSString).appendingPathComponent(monoLinkDest)
        dest = ((resolved as NSString).resolvingSymlinksInPath)
      }
      else
      {
        dest = (monoP as NSString).resolvingSymlinksInPath
      }
      try fm.removeItem(atPath: p)
      try fm.createSymbolicLink(atPath: p, withDestinationPath: dest)
    }
  }

  /// full pipeline: sets up the target dir, runs the splitters, regenerates the module map.
  static func run(classifier: Classifier, reporter: Reporter) throws
  {
    let dest = "\(Paths.splitPackage)/Sources/_OpenUSD_SwiftBindingHelpers"
    let (headers, tail) = try parseMap(Paths.monoModuleMap)
    reporter.parsedHeaderCount(headers.count)

    try setupTargetDir(dest)
    try Splitters.runAll(classifier: classifier, reporter: reporter)

    let incRoot = "\(dest)/include"
    let genDir = "\(incRoot)/swiftUsd/generated"
    let fm = FileManager.default

    /// swap a header for its partitioned +Domain files, if any exist.
    func expand(_ h: String) -> [String]
    {
      guard h.hasPrefix("swiftUsd/"), h.hasSuffix(".h") else { return [h] }
      let conf = ((h as NSString).lastPathComponent as NSString).deletingPathExtension
      var parts: [String] = []
      for top in ["glue"] + TOPS
      {
        let p = "\(conf)+\(top).h"
        if fm.fileExists(atPath: "\(genDir)/\(p)")
        {
          parts.append("swiftUsd/generated/\(p)")
        }
      }
      return parts.isEmpty ? [h] : parts
    }

    let expanded = headers.flatMap(expand)
    var memo: [String: Set<String>] = [:]
    var routes: [String: String] = [:]
    for h in expanded
    {
      routes[h] = route(h, incRoot: incRoot, memo: &memo)
    }
    var glueList: [String] = []
    let mapText = genMap(headers: expanded, routes: routes, glueList: &glueList, tail: tail)
    try mapText.write(toFile: "\(incRoot)/module.modulemap", atomically: true, encoding: .utf8)
    let modTops = TOPS + (glueList.isEmpty ? [] : ["glue"])
    try writeApinotes(destDir: incRoot, tops: modTops)

    for top in modTops
    {
      let n = expanded.count(where: { routes[$0] == top })
      reporter.moduleHeaderCount(moduleName(top), n)
    }
  }
}
