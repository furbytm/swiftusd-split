import Foundation

/// builds Package.swift, each domain's Preamble.swift, the umbrella
/// target, and places every hand-written source file into its domain.
enum Scaffold
{
  /// C++ import DAG, narrower than the swift dependency chain below,
  /// e.g. imaging's C++ headers never need exec's, so no point
  /// importing that submodule.
  static let cxxImportDAG: [String: [String]] = [
    "base": [],
    "usd": ["base"],
    "exec": ["usd", "base"],
    "imaging": ["usd", "base"],
    "usdImaging": ["imaging", "usd", "base"],
    "usdValidation": ["usd", "base"],
  ]

  /// small content patches beyond the generic self-import rewrite.
  static let contentPatches: [(relPath: String, why: String, patch: (String) -> String)] = []

  static let ownedSubdirs = ["SwiftOverlay", "Wrappers", "TfNotice", "Util", "Work"]

  struct Placement
  {
    /// relative to OpenUSD/, e.g. "SwiftOverlay/Math.swift"
    var relPath: String
    var domain: String
  }

  /// classifies every handwritten .swift file to one domain by LUB over its
  /// own content, skipping EXTRA_SWIFT files (those split per declaration).
  static func classifyHandFiles(classifier: Classifier) throws -> [Placement]
  {
    let fm = FileManager.default
    let root = "\(Paths.swiftUsdRoot)/swift-package/Sources/OpenUSD"
    let extraSwiftNames = Set(EXTRA_SWIFT.map(\.filename))
    var placements: [Placement] = []

    var relPaths: [String] = []
    for entry in try fm.contentsOfDirectory(atPath: root) where entry.hasSuffix(".swift")
    {
      relPaths.append(entry)
    }
    for sub in ownedSubdirs
    {
      let dir = "\(root)/\(sub)"
      guard fm.fileExists(atPath: dir) else { continue }
      for entry in try fm.contentsOfDirectory(atPath: dir) where entry.hasSuffix(".swift")
      {
        relPaths.append("\(sub)/\(entry)")
      }
    }

    for rel in relPaths.sorted()
    {
      let filename = (rel as NSString).lastPathComponent
      if extraSwiftNames.contains(filename) { continue }
      if filename == "OpenUSD.swift", !rel.contains("/")
      {
        placements.append(Placement(relPath: rel, domain: "base"))
        continue
      }
      let content = try String(contentsOfFile: "\(root)/\(rel)", encoding: .utf8)
      let domain = classifier.lub(classifier.dirsOf(content)) ?? "base"
      placements.append(Placement(relPath: rel, domain: domain))
    }
    return placements
  }

  /// symlinks a file into its domain dir, or copies+rewrites it if it
  /// self references the monolithic C++ module or does `import OpenUSD`.
  static func placeFile(_ placement: Placement) throws
  {
    let fm = FileManager.default
    let root = "\(Paths.swiftUsdRoot)/swift-package/Sources/OpenUSD"
    let srcPath = "\(root)/\(placement.relPath)"
    let filename = (placement.relPath as NSString).lastPathComponent
    let domainDir = "\(Paths.splitPackage)/Sources/\(placement.domain)"
    try fm.createDirectory(atPath: domainDir, withIntermediateDirectories: true)
    let dst = "\(domainDir)/\(filename)"
    if fm.fileExists(atPath: dst) || isSymlink(dst)
    {
      try fm.removeItem(atPath: dst)
    }

    var text = try String(contentsOfFile: srcPath, encoding: .utf8)
    let ownModule = "_OpenUSD_" + placement.domain.prefix(1).uppercased() + placement.domain.dropFirst()
    let matchingPatches = contentPatches.filter { $0.relPath == placement.relPath }
    let needsSelfImportFix = text.contains("_OpenUSD_SwiftBindingHelpers") || text.contains("import OpenUSD")
    if needsSelfImportFix || !matchingPatches.isEmpty
    {
      if needsSelfImportFix
      {
        text = text.replacingOccurrences(of: "@_exported import _OpenUSD_SwiftBindingHelpers", with: "@_exported import \(ownModule)")
        text = text.replacingOccurrences(of: "import _OpenUSD_SwiftBindingHelpers", with: "import \(ownModule)")
        text = text.splitKeepingEnds()
          .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines) != "import OpenUSD" }
          .joined()
      }
      for (_, _, patch) in matchingPatches
      {
        text = patch(text)
      }
      try text.write(toFile: dst, atomically: true, encoding: .utf8)
    }
    else
    {
      try fm.createSymbolicLink(atPath: dst, withDestinationPath: srcPath)
    }
  }

  /// removes stale files left over from a previous, differently configured run.
  static func pruneStaleFiles(currentPlacements: [Placement]) throws
  {
    let fm = FileManager.default
    let keep = Set(currentPlacements.map { "\($0.domain)/\(($0.relPath as NSString).lastPathComponent)" })
    for domain in TOPS
    {
      let dir = "\(Paths.splitPackage)/Sources/\(domain)"
      guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
      for entry in entries
      {
        guard entry.hasSuffix(".swift"), entry != "Preamble.swift" else { continue }
        if entry.contains("+") { continue } // generated splitter output, not ours to prune.
        if !keep.contains("\(domain)/\(entry)")
        {
          Term.warn("pruning stale \(domain)/\(entry) (no longer placed here)")
          try? fm.removeItem(atPath: "\(dir)/\(entry)")
        }
      }
    }
  }

  /// extra imports a domain needs beyond its C++ module + parent reexports.
  static let extraImports: [String: [String]] = [
    "base": ["import CxxStdlib"],
    "usdImaging": ["import CxxStdlib"],
  ]

  static func writePreamble(domain: String, index: Int) throws
  {
    let parents = Array(TOPS.prefix(index)) // every earlier domain
    let ownModule = "_OpenUSD_" + domain.prefix(1).uppercased() + domain.dropFirst()
    var lines: [String] = []
    lines.append("@_exported import \(ownModule)")
    for p in cxxImportDAG[domain] ?? []
    {
      lines.append("@_exported import _OpenUSD_" + p.prefix(1).uppercased() + p.dropFirst())
    }
    lines.append(contentsOf: extraImports[domain] ?? [])
    if index > 0
    {
      lines.append("public typealias pxr = pxrInternal_v0_26_8__pxrReserved__")
    }
    for p in parents
    {
      lines.append("@_exported import \(p)")
    }
    let dir = "\(Paths.splitPackage)/Sources/\(domain)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(toFile: "\(dir)/Preamble.swift", atomically: true, encoding: .utf8)
  }

  /// symlinks the xcframework binaries in place instead of copying gigabytes.
  static func symlinkLibraries() throws
  {
    let fm = FileManager.default
    let link = "\(Paths.splitPackage)/Libraries"
    let target = "\(Paths.swiftUsdRoot)/swift-package/Libraries"
    if fm.fileExists(atPath: link) || isSymlink(link) { try? fm.removeItem(atPath: link) }
    try fm.createSymbolicLink(atPath: link, withDestinationPath: target)
  }

  /// symlinks the TF_REGISTRY_FUNCTION/SWIFTUSD_PLUGIN macro plugin sources.
  static func symlinkMacroImplementations() throws
  {
    let fm = FileManager.default
    let link = "\(Paths.splitPackage)/Sources/_OpenUSD_MacroImplementations"
    let target = "\(Paths.swiftUsdRoot)/swift-package/Sources/_OpenUSD_MacroImplementations"
    try fm.createDirectory(atPath: "\(Paths.splitPackage)/Sources", withIntermediateDirectories: true)
    if fm.fileExists(atPath: link) || isSymlink(link) { try? fm.removeItem(atPath: link) }
    try fm.createSymbolicLink(atPath: link, withDestinationPath: target)
  }

  /// symlinks the SPM plugin targets.
  static func symlinkPlugins() throws
  {
    let fm = FileManager.default
    let link = "\(Paths.splitPackage)/Plugins"
    let target = "\(Paths.swiftUsdRoot)/swift-package/Plugins"
    if fm.fileExists(atPath: link) || isSymlink(link) { try? fm.removeItem(atPath: link) }
    try fm.createSymbolicLink(atPath: link, withDestinationPath: target)
  }

  /// mirrors the two hioPpm example SPM packages, symlinking
  /// every entry except SwiftUsd/Package.resolved/.swiftpm.
  static func symlinkExamples() throws
  {
    let fm = FileManager.default
    let srcParent = "\(Paths.swiftUsdRoot)/Examples/Plugins/HioImage"
    guard fm.fileExists(atPath: srcParent) else { return }
    let dstParent = "\(Paths.splitPackage)/Examples/Plugins/HioImage"
    try fm.createDirectory(atPath: dstParent, withIntermediateDirectories: true)

    let packages = ["hioPpm_Swift", "hioPpm_Cxx"]
    let skip = Set([".DS_Store"] + packages)
    for entry in try fm.contentsOfDirectory(atPath: srcParent).sorted() where !skip.contains(entry)
    {
      let link = "\(dstParent)/\(entry)"
      if fm.fileExists(atPath: link) || isSymlink(link) { try? fm.removeItem(atPath: link) }
      try fm.createSymbolicLink(atPath: link, withDestinationPath: "\(srcParent)/\(entry)")
    }

    let pkgSkip: Set<String> = ["SwiftUsd", "Package.resolved", ".swiftpm", ".DS_Store"]
    for pkg in packages
    {
      let srcPkg = "\(srcParent)/\(pkg)"
      guard fm.fileExists(atPath: srcPkg) else { continue }
      try? fm.removeItem(atPath: "\(dstParent)/\(pkg)")
      try fm.createDirectory(atPath: "\(dstParent)/\(pkg)", withIntermediateDirectories: true)
      for entry in try fm.contentsOfDirectory(atPath: srcPkg).sorted() where !pkgSkip.contains(entry)
      {
        let link = "\(dstParent)/\(pkg)/\(entry)"
        try fm.createSymbolicLink(atPath: link, withDestinationPath: "\(srcPkg)/\(entry)")
      }
      try fm.createSymbolicLink(atPath: "\(dstParent)/\(pkg)/SwiftUsd", withDestinationPath: Paths.splitPackage)
    }
  }

  static func writePackageSwift() throws
  {
    // every module gets the macro target + its two swift-syntax products,
    // since classifyHandFiles decides at runtime which domain ends up hosting
    // PluginAndTfMacros.swift's `#externalMacro(...)` declarations.
    let macroDeps = ["\"_OpenUSD_MacroImplementations\"",
                      ".product(name: \"SwiftSyntaxMacros\", package: \"swift-syntax\")",
                      ".product(name: \"SwiftCompilerPlugin\", package: \"swift-syntax\")"]

    var targets: [String] = []
    for (i, top) in TOPS.enumerated()
    {
      let parents = Array(TOPS.prefix(i))
      let deps = (["\"_OpenUSD_SwiftBindingHelpers\""] + macroDeps + parents.map { "\"\($0)\"" }).joined(separator: ", ")
      targets.append("""
                .target(name: "\(top)",
                        dependencies: [\(deps)],
                        path: "Sources/\(top)",
                        swiftSettings: [
                            .interoperabilityMode(.Cxx),
                            .define("OPENUSD_SWIFT_BUILD_FROM_CLI")
                        ])
        """)
    }
    let umbrellaDeps = TOPS.map { "\"\($0)\"" }.joined(separator: ", ")
    targets.append("""
                  .target(name: "OpenUSD",
                          dependencies: [\(umbrellaDeps)],
                          path: "Sources/OpenUSD",
                          swiftSettings: [
                              .interoperabilityMode(.Cxx),
                              .define("OPENUSD_SWIFT_BUILD_FROM_CLI")
                          ])
      """)
    targets.append("""
                  .macro(name: "_OpenUSD_MacroImplementations",
                          dependencies: [
                              .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                              .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
                          ],
                          path: "Sources/_OpenUSD_MacroImplementations")
      """)
    let xcframeworks = try Xcframeworks.macOSEntries()
    let cxxDepsBlock = xcframeworks.map { "                                \"\($0.target)\"" }.joined(separator: ",\n")
    targets.append("""
                  .target(name: "_OpenUSD_SwiftBindingHelpers",
                          dependencies: [
      \(cxxDepsBlock)
                          ],
                          path: "Sources/_OpenUSD_SwiftBindingHelpers",
                          cxxSettings: [
                              .define("OPENUSD_SWIFT_BUILD_FROM_CLI")
                          ])
      """)
    for x in xcframeworks
    {
      targets.append("        .binaryTarget(name: \"\(x.target)\", path: \"Libraries/\(x.xcframeworkFile)\")")
    }
    targets.append("""
                  .testTarget(name: "SplitPackageSmokeTests",
                          dependencies: ["OpenUSD"],
                          path: "Tests/SplitPackageSmokeTests",
                          swiftSettings: [
                              .interoperabilityMode(.Cxx),
                              .define("OPENUSD_SWIFT_BUILD_FROM_CLI")
                          ])
      """)
    targets.append("""
                  .plugin(name: "generate-plug-info-json",
                          capability: .buildTool(),
                          path: "Plugins/generate-plug-info-json")
      """)
    targets.append("""
                  .plugin(name: "build-vanilla-openusd-plugin",
                          capability: .command(
                              intent: .custom(verb: "build-vanilla-openusd-plugin", description: "Builds an OpenUSD plugin for use with vanilla OpenUSD installs")
                          ),
                          path: "Plugins/build-vanilla-openusd-plugin")
      """)
    let manifest = """
      // swift-tools-version: 6.1
      // Split-OpenUSD benchmark package: layered Swift targets over a shared
      // monolithic C++ module, re-exported through an umbrella `OpenUSD` target.
      // Generated by swiftusd-split - do not hand-edit.
      import PackageDescription
      import CompilerPluginSupport

      let package = Package(
          name: "\(Paths.packageName)",
          platforms: [.macOS(.v14)],
          products: [
              .library(name: "OpenUSD", targets: ["OpenUSD"]),
              .plugin(name: "build-vanilla-openusd-plugin", targets: ["build-vanilla-openusd-plugin"]),
              .plugin(name: "generate-plug-info-json", targets: ["generate-plug-info-json"])
          ],
          dependencies: [
              .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0-latest"..."603.0.0")
          ],
          targets: [
      \(targets.joined(separator: ",\n"))
          ],
          cxxLanguageStandard: .gnucxx17
      )

      """
    try manifest.write(toFile: "\(Paths.splitPackage)/Package.swift", atomically: true, encoding: .utf8)
  }

  static let smokeTestSource = """
    // Generated by swiftusd-split - do not hand-edit.
    //
    // forces a real link, not just a type-check - a pure static library
    // build never resolves external symbols, so a missing xcframework dep
    // would otherwise pass silently. usage pattern from SwiftUsd's own docs.
    import XCTest
    import OpenUSD

    final class SplitPackageSmokeTests: XCTestCase {
        func testCreateStageAndDefinePrim() {
            let stage = Overlay.Dereference(pxr.UsdStage.CreateInMemory())
            let prim = stage.DefinePrim("/hello", .UsdGeomTokens.Xform)
            XCTAssertTrue(Bool(prim))
        }
    }

    """

  static func writeSmokeTest() throws
  {
    let dir = "\(Paths.splitPackage)/Tests/SplitPackageSmokeTests"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try smokeTestSource.write(toFile: "\(dir)/SplitPackageSmokeTests.swift", atomically: true, encoding: .utf8)
  }

  static func writeUmbrella() throws
  {
    let dir = "\(Paths.splitPackage)/Sources/OpenUSD"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var umbrella = ""
    for mod in TOPS
    {
      umbrella += "@_exported import \(mod)\n"
    }
    try umbrella.write(toFile: "\(dir)/OpenUSD.swift", atomically: true, encoding: .utf8)
  }

  /// symlinks generated <slug>+<domain>.swift pieces into each target's own
  /// Sources/<domain>/ - swiftpm only compiles files physically inside path:
  static func symlinkGeneratedSwiftPieces() throws
  {
    let fm = FileManager.default
    for domain in TOPS
    {
      let genDir = "\(Paths.swiftOut)/\(domain)"
      let domainDir = "\(Paths.splitPackage)/Sources/\(domain)"
      try fm.createDirectory(atPath: domainDir, withIntermediateDirectories: true)

      // prune stale symlinks left over from a renamed/removed entry
      if let existing = try? fm.contentsOfDirectory(atPath: domainDir)
      {
        for entry in existing where entry.hasSuffix("+\(domain).swift")
        {
          let path = "\(domainDir)/\(entry)"
          if isSymlink(path), !fm.fileExists(atPath: path)
          {
            try? fm.removeItem(atPath: path)
          }
        }
      }

      guard let pieces = try? fm.contentsOfDirectory(atPath: genDir) else { continue }
      for piece in pieces where piece.hasSuffix(".swift")
      {
        let dst = "\(domainDir)/\(piece)"
        if fm.fileExists(atPath: dst) || isSymlink(dst) { continue }
        try fm.createSymbolicLink(atPath: dst, withDestinationPath: "\(genDir)/\(piece)")
      }
    }
  }

  private static func isSymlink(_ path: String) -> Bool
  {
    (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
  }

  /// full scaffolding pass, run before the generated content splitters.
  static func run(classifier: Classifier, reporter: Reporter) throws
  {
    reporter.section("Scaffolding (Package.swift, Preamble.swift, hand-written file placement)")
    try symlinkLibraries()
    try symlinkMacroImplementations()
    try symlinkPlugins()
    try symlinkExamples()
    try writePackageSwift()
    let xcframeworkCount = (try? Xcframeworks.macOSEntries().count) ?? 0
    Term.ok("wrote Package.swift (\(TOPS.count) domain targets + umbrella + \(xcframeworkCount) xcframework deps, linear dependency chain)")
    for (i, top) in TOPS.enumerated()
    {
      try writePreamble(domain: top, index: i)
    }
    try writeUmbrella()
    try writeSmokeTest()
    Term.ok("wrote Preamble.swift x\(TOPS.count) + umbrella OpenUSD.swift + smoke test")

    let placements = try classifyHandFiles(classifier: classifier)
    try pruneStaleFiles(currentPlacements: placements)
    var perDomain: [String: Int] = [:]
    for p in placements
    {
      try placeFile(p)
      perDomain[p.domain, default: 0] += 1
    }
    DomainRow.render("hand-written files placed", TOPS.compactMap { d in perDomain[d].map { (d, $0) } })
    for (relPath, why, _) in contentPatches
    {
      Term.info("patched \(relPath): \(why)")
    }
  }
}
