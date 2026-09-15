import Foundation

/// filesystem locations, set once from the CLI args in main.swift.
enum Paths
{
  private(set) static var swiftUsdRoot = ""
  private(set) static var include = ""
  private(set) static var monoGenSwift = ""
  private(set) static var monoGenCxx = ""
  private(set) static var monoHelpers = ""
  private(set) static var monoModuleMap = ""
  private(set) static var monoApinotes = ""

  private(set) static var splitPackage = ""
  // last path component of --to, used as the generated package's name.
  private(set) static var packageName = ""
  private(set) static var cxxOut = ""
  private(set) static var swiftOut = ""
  private(set) static var typeMapOut = ""

  private static func resolve(_ path: String) -> String
  {
    let expanded = (path as NSString).expandingTildeInPath
    let absolute = expanded.hasPrefix("/") ? expanded : FileManager.default.currentDirectoryPath + "/" + expanded
    return (absolute as NSString).standardizingPath
  }

  /// call once before anything else touches paths.
  static func configure(sourceDir: String, outputDir: String)
  {
    swiftUsdRoot = resolve(sourceDir)
    include = "\(swiftUsdRoot)/swift-package/Sources/_OpenUSD_SwiftBindingHelpers/include"
    monoGenSwift = "\(swiftUsdRoot)/swift-package/Sources/OpenUSD/generated"
    monoGenCxx = "\(include)/swiftUsd/generated"
    monoHelpers = "\(swiftUsdRoot)/swift-package/Sources/_OpenUSD_SwiftBindingHelpers"
    monoModuleMap = "\(monoHelpers)/include/module.modulemap"
    monoApinotes = "\(monoHelpers)/include/_OpenUSD_SwiftBindingHelpers.apinotes"

    splitPackage = resolve(outputDir)
    packageName = (splitPackage as NSString).lastPathComponent
    cxxOut = "\(splitPackage)/Sources/_OpenUSD_SwiftBindingHelpers/include/swiftUsd/generated"
    swiftOut = "\(splitPackage)/Sources/_Generated"
    typeMapOut = "\(splitPackage)/type_map.json"
    try? FileManager.default.createDirectory(atPath: splitPackage, withIntermediateDirectories: true)
  }
}

/// base to broadest, also the real dependency chain order.
let TOPS = ["base", "usd", "exec", "imaging", "usdImaging", "usdValidation"]

/// module -> everything it can see, for the LUB picker.
let COVER: [String: Set<String>] = [
  "base": ["base"],
  "usd": ["base", "usd"],
  "exec": ["base", "usd", "exec"],
  "imaging": ["base", "usd", "imaging"],
  "usdValidation": ["base", "usd", "usdValidation"],
  "usdImaging": ["base", "usd", "imaging", "usdImaging"],
  "glue": ["base", "exec", "imaging", "usd", "usdImaging", "usdValidation"],
]

/// fallback for names the type map scan misses, longest prefix wins.
let ABBR: [String: String] = [
  "Tf": "base", "Gf": "base", "Arch": "base", "Vt": "base", "Js": "base",
  "Plug": "base", "Work": "base", "Trace": "base", "Ts": "base",
  "PxOsd": "imaging", "Glf": "imaging", "Garch": "imaging", "Hd": "imaging",
  "Hdsi": "imaging", "Hdx": "imaging", "Hgi": "imaging", "Hio": "imaging",
  "CameraUtil": "imaging",
  "Ar": "usd", "Sdf": "usd", "Sdr": "usd", "Ndr": "usd",
  "Pcp": "usd", "Kind": "usd", "Usd": "usd",
  "exec_registration": "exec",
  "Exec": "exec", "Vio": "exec", "Ef": "exec", "Vdf": "exec",
  "UsdValidator": "usdValidation", "UsdGeomValidators": "usdValidation",
  "UsdImaging": "usdImaging", "UsdAppUtils": "usdImaging",
  "UsdHydra": "usdImaging", "UsdSkelImaging": "usdImaging",
  "UsdVolImaging": "usdImaging", "UsdRenderUtil": "usdImaging",
]

/// handwritten swift files that also span multiple modules and need splitting.
let EXTRA_SWIFT: [(srcDir: String, filename: String, outSlug: String)] = [
  ("\(Paths.swiftUsdRoot)/swift-package/Sources/OpenUSD/SwiftOverlay", "MethodsReturningRefererences.swift", "MethodsReturningReferences"),
  ("\(Paths.swiftUsdRoot)/swift-package/Sources/OpenUSD/SwiftOverlay", "TypeConversionInitializers.swift", "TypeConversionInitializers"),
  ("\(Paths.swiftUsdRoot)/swift-package/Sources/OpenUSD/SwiftOverlay", "Codable.swift", "Codable"),
  ("\(Paths.swiftUsdRoot)/swift-package/Sources/OpenUSD/SwiftOverlay", "VtArrayProtocol.swift", "VtArrayProtocol"),
  ("\(Paths.swiftUsdRoot)/swift-package/Sources/OpenUSD/SwiftOverlay", "SwiftSubclassCxx_handwritten.swift", "SwiftSubclassCxx_handwritten"),
  ("\(Paths.swiftUsdRoot)/swift-package/Sources/OpenUSD/SwiftOverlay", "Sequence.swift", "Sequence"),
  ("\(Paths.swiftUsdRoot)/swift-package/Sources/OpenUSD/SwiftOverlay", "operatorBool.swift", "operatorBool"),
]

/// same deal for hand-written C++ bridge headers.
let EXTRA_CXX: [(srcDir: String, filename: String, outSlug: String)] = [
  ("\(Paths.include)/swiftUsd/SwiftOverlay", "Typedefs.h", "Typedefs"),
  ("\(Paths.include)/swiftUsd/SwiftOverlay", "VtDictionary.h", "VtDictionary"),
  ("\(Paths.include)/swiftUsd/SwiftOverlay", "Miscellaneous.h", "Miscellaneous"),
  ("\(Paths.include)/swiftUsd/SwiftOverlay", "operatorBool.h", "operatorBool"),
]
