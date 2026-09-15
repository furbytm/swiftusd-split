import Foundation

/// runs the swift and C++ splitters over every generated + handwritten source.
enum Splitters
{
  static func runAll(classifier: Classifier, reporter: Reporter) throws
  {
    let fm = FileManager.default
    try? fm.removeItem(atPath: Paths.swiftOut)

    let swiftSplitter = SwiftSplitter(classifier: classifier)
    let cxxSplitter = CxxSplitter(classifier: classifier)

    reporter.section("Swift generated files")
    let swiftFiles = try fm.contentsOfDirectory(atPath: Paths.monoGenSwift)
      .filter { $0.hasSuffix(".swift") }.sorted()
    for f in swiftFiles
    {
      let counts = try swiftSplitter.splitSwiftFile(filename: f, srcDir: Paths.monoGenSwift, outSlug: nil)
      reporter.fileCounts(f, counts)
    }

    reporter.section("Swift hand-written sources")
    for entry in EXTRA_SWIFT
    {
      let counts = try swiftSplitter.splitSwiftFile(filename: entry.filename, srcDir: entry.srcDir, outSlug: entry.outSlug)
      reporter.fileCounts(entry.filename, counts)
    }

    reporter.section("C++ generated headers")
    let cxxFiles = try fm.contentsOfDirectory(atPath: Paths.monoGenCxx)
      .filter { $0.hasSuffix(".h") }.sorted()
    for f in cxxFiles
    {
      let counts = try cxxSplitter.splitCxxFile(filename: f)
      reporter.cxxFileCounts(f, counts)
    }

    reporter.section("C++ hand-written bridge headers")
    for entry in EXTRA_CXX
    {
      let counts = try cxxSplitter.splitCxxHandFile(filename: entry.filename, srcDir: entry.srcDir, outSlug: entry.outSlug)
      reporter.cxxFileCounts(entry.filename, counts)
    }

    let glue = (try? fm.contentsOfDirectory(atPath: Paths.cxxOut).filter { $0.hasSuffix("+glue.h") }) ?? []
    if glue.isEmpty
    {
      reporter.noGlueResidue()
    }
    else
    {
      reporter.glueResidue(glue)
    }
  }
}
