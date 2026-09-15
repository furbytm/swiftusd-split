import Foundation

/// ANSI styling for terminal output, disabled automatically when not a TTY.
enum Term
{
  static let colorEnabled: Bool = isatty(fileno(stdout)) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

  static func wrap(_ s: String, _ code: String) -> String
  {
    colorEnabled ? "\u{001B}[\(code)m\(s)\u{001B}[0m" : s
  }

  static func bold(_ s: String) -> String
  {
    wrap(s, "1")
  }

  static func dim(_ s: String) -> String
  {
    wrap(s, "2")
  }

  static func red(_ s: String) -> String
  {
    wrap(s, "31")
  }

  static func green(_ s: String) -> String
  {
    wrap(s, "32")
  }

  static func yellow(_ s: String) -> String
  {
    wrap(s, "33")
  }

  static func blue(_ s: String) -> String
  {
    wrap(s, "34")
  }

  static func magenta(_ s: String) -> String
  {
    wrap(s, "35")
  }

  static func cyan(_ s: String) -> String
  {
    wrap(s, "36")
  }

  static func gray(_ s: String) -> String
  {
    wrap(s, "90")
  }

  static func heading(_ s: String)
  {
    print("\n" + bold(cyan("== \(s) ==")))
  }

  static func ok(_ s: String)
  {
    print(green("✓ ") + s)
  }

  static func warn(_ s: String)
  {
    print(yellow("! ") + s)
  }

  static func fail(_ s: String)
  {
    print(red("✗ ") + s)
  }

  static func info(_ s: String)
  {
    print(dim("  " + s))
  }
}

/// per domain counts rendered as a compact color coded row.
enum DomainRow
{
  static let domainColor: [String: (String) -> String] = [
    "base": Term.blue, "usd": Term.green, "exec": Term.magenta,
    "imaging": Term.cyan, "usdImaging": Term.yellow, "usdValidation": Term.red,
    "glue": Term.gray,
  ]

  static func render(_ label: String, _ counts: [(String, Int)])
  {
    let pad = String(repeating: " ", count: max(1, 36 - label.count))
    let parts = counts.map
    { domain, n -> String in
      let colorize = domainColor[domain] ?? Term.gray
      return colorize("\(domain):\(n)")
    }
    print("  " + label + pad + parts.joined(separator: " "))
  }
}

/// directory tree built from flat relative paths, printed with box-drawing.
final class TreeNode
{
  let name: String
  var children: [String: TreeNode] = [:]
  var annotation: String?

  init(name: String)
  {
    self.name = name
  }

  static func build(paths: [(path: String, annotation: String)]) -> TreeNode
  {
    let root = TreeNode(name: "")
    for (path, annotation) in paths
    {
      var node = root
      let parts = path.split(separator: "/").map(String.init)
      for (i, part) in parts.enumerated()
      {
        if let existing = node.children[part]
        {
          node = existing
        }
        else
        {
          let child = TreeNode(name: part)
          node.children[part] = child
          node = child
        }
        if i == parts.count - 1
        {
          node.annotation = annotation
        }
      }
    }
    return root
  }

  func printTree(prefix: String = "", isLast: Bool = true, isRoot: Bool = true)
  {
    let sortedChildren = children.values.sorted { $0.name < $1.name }
    if !isRoot
    {
      let connector = isLast ? "└── " : "├── "
      var line = prefix + Term.gray(connector) + name
      if let annotation
      {
        line += "  " + annotation
      }
      print(line)
    }
    let childPrefix = isRoot ? "" : prefix + (isLast ? "    " : Term.gray("│   "))
    for (i, child) in sortedChildren.enumerated()
    {
      child.printTree(prefix: childPrefix, isLast: i == sortedChildren.count - 1, isRoot: false)
    }
  }
}
