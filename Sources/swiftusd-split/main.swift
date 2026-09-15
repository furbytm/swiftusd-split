import Foundation

// splits an apple/SwiftUsd checkout into a layered top level swift package.
// usage: swiftusd-split <apple/SwiftUsd-directory> --to <output-directory>

func usageAndExit(_ code: Int32) -> Never
{
  print(Term.bold("Usage: ") + "swiftusd-split <apple/SwiftUsd-directory> --to <output-directory>")
  print(Term.dim("  <apple/SwiftUsd-directory>  path to the apple/SwiftUsd checkout to split"))
  print(Term.dim("  --to <output-directory>     where to generate the split package"))
  print(Term.dim(""))
  print(Term.dim("  The output directory is created if it doesn't exist; existing generated"))
  print(Term.dim("  content there is overwritten, hand-written content is preserved. The"))
  print(Term.dim("  generated SwiftPM package takes its name from the output directory."))
  exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("-h") || args.contains("--help") { usageAndExit(0) }
guard let toIndex = args.firstIndex(of: "--to"), toIndex == 1, args.count == 3,
      !args[0].isEmpty, !args[2].isEmpty
else
{
  usageAndExit(1)
}

let sourceDir = args[0]
let outputDir = args[2]

let sourceMarker = "\(sourceDir)/swift-package/Sources/_OpenUSD_SwiftBindingHelpers"
guard FileManager.default.fileExists(atPath: (sourceMarker as NSString).expandingTildeInPath)
else
{
  Term.fail("\(sourceDir) doesn't look like an apple/SwiftUsd checkout (missing swift-package/Sources/_OpenUSD_SwiftBindingHelpers)")
  exit(1)
}

Paths.configure(sourceDir: sourceDir, outputDir: outputDir)

let startTime = Date()

print(Term.bold(Term.magenta("swiftusd-split")) + Term.dim(" - apple/SwiftUsd module splitter"))
Term.info("source: \(Paths.swiftUsdRoot)")
Term.info("output: \(Paths.splitPackage) (package \"\(Paths.packageName)\")")
print(Term.dim(String(repeating: "─", count: 60)))

let reporter = Reporter()

do
{
  let nameDir = TypeMap.build()
  try TypeMap.write(nameDir, to: Paths.typeMapOut)
  reporter.typeMapIndexed(nameDir.count, path: Paths.typeMapOut)
  let classifier = Classifier(nameDir: nameDir)

  try Scaffold.run(classifier: classifier, reporter: reporter)
  try ModuleMapGenerator.run(classifier: classifier, reporter: reporter)
  try Scaffold.symlinkGeneratedSwiftPieces()
  Term.ok("symlinked generated Swift pieces into each module's Sources/ directory")
  reporter.printWrittenTree()

  let elapsed = Date().timeIntervalSince(startTime)
  print("\n" + Term.dim(String(repeating: "─", count: 60)))
  Term.ok(Term.bold("done") + Term.dim(String(format: " in %.1fs", elapsed)))
}
catch
{
  Term.fail("swiftusd-split failed: \(error)")
  exit(1)
}
