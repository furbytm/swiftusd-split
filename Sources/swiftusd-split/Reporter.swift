import Foundation

/// prints progress as the pipeline runs: per file counts, glue residue, preview tree.
final class Reporter
{
  private var writtenPaths: [(path: String, annotation: String)] = []

  func typeMapIndexed(_ count: Int, path: String)
  {
    Term.ok("indexed \(Term.bold(String(count))) type names -> \(Term.dim(path))")
  }

  func typeMapUnresolved(_ names: [String])
  {
    guard !names.isEmpty else { return }
    Term.warn("\(names.count) name(s) still unresolved (fall through to base by default):")
    for n in names.prefix(20)
    {
      print("    " + Term.dim("? " + n))
    }
  }

  func section(_ title: String)
  {
    Term.heading(title)
  }

  func fileCounts(_ label: String, _ counts: [(domain: String, count: Int)])
  {
    DomainRow.render(label, counts.map { ($0.domain, $0.count) })
    for c in counts
    {
      writtenPaths.append((path: "_Generated/\(c.domain)/\(labelSlug(label))+\(c.domain).swift", annotation: Term.dim("(\(c.count))")))
    }
  }

  func cxxFileCounts(_ label: String, _ counts: [(domain: String, lines: Int)])
  {
    DomainRow.render(label, counts.map { ($0.domain, $0.lines) })
    for c in counts
    {
      writtenPaths.append((path: "_OpenUSD_SwiftBindingHelpers/.../generated/\(labelSlug(label))+\(c.domain).h", annotation: Term.dim("(\(c.lines) lines)")))
    }
  }

  private func labelSlug(_ label: String) -> String
  {
    label.hasSuffix(".swift") ? String(label.dropLast(6)) : (label.hasSuffix(".h") ? String(label.dropLast(2)) : label)
  }

  func glueResidue(_ files: [String])
  {
    guard !files.isEmpty else { return }
    Term.warn("glue residue (no single domain covers these): \(files.joined(separator: ", "))")
  }

  func noGlueResidue()
  {
    Term.ok("no glue residue - every declaration resolved to exactly one domain")
  }

  func parsedHeaderCount(_ n: Int)
  {
    Term.info("parsed \(n) headers from the monolithic module map")
  }

  func moduleHeaderCount(_ module: String, _ n: Int)
  {
    let colorize = DomainRow.domainColor[module.replacingOccurrences(of: "_OpenUSD_", with: "").lowercasedFirst()] ?? Term.gray
    print("  " + colorize(module.padding(toLength: 24, withPad: " ", startingAt: 0)) + " \(n) headers")
  }

  /// prints the preview tree of every file this run wrote.
  func printWrittenTree()
  {
    guard !writtenPaths.isEmpty else { return }
    Term.heading("Files written this run")
    let tree = TreeNode.build(paths: writtenPaths)
    tree.printTree()
  }
}

private extension String
{
  func lowercasedFirst() -> String
  {
    guard let f = first else { return self }
    return f.lowercased() + dropFirst()
  }

  func padding(toLength length: Int, withPad pad: String, startingAt _: Int) -> String
  {
    if count >= length { return self }
    return self + String(repeating: pad, count: length - count)
  }
}
