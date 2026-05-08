import Foundation
import Testing

@Test
func localizableCatalogTracksRuntimeLocalizationKeys() throws {
    let root = try repositoryRoot()
    let sourceURL = root.appendingPathComponent("Sources/PitcherPlantApp/Support/LocalizationStrings.swift")
    let catalogURL = root.appendingPathComponent("Resources/Localizable.xcstrings")

    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let runtimeKeys = try runtimeLocalizationKeys(in: source)
    let catalogData = try Data(contentsOf: catalogURL)
    let catalog = try JSONDecoder().decode(StringCatalog.self, from: catalogData)

    #expect(runtimeKeys == Set(catalog.strings.keys))
}

private func repositoryRoot() throws -> URL {
    var candidate = URL(fileURLWithPath: #filePath)
    for _ in 0..<8 {
        let root = candidate.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("Resources/Localizable.xcstrings").path) {
            return root
        }
        candidate = root
    }
    throw CocoaError(.fileNoSuchFile)
}

private func runtimeLocalizationKeys(in source: String) throws -> Set<String> {
    let zhHans = try dictionaryBody(named: "zhHans", in: source)
    let english = try dictionaryBody(named: "english", in: source)
    return parsedKeys(in: zhHans).union(parsedKeys(in: english))
}

private func dictionaryBody(named name: String, in source: String) throws -> String {
    let pattern = #"private static let \#(name): \[String: String\] = \[(.*?)\n    \]"#
    let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    guard let match = regex.firstMatch(in: source, range: range),
          let bodyRange = Range(match.range(at: 1), in: source) else {
        throw CocoaError(.coderReadCorrupt)
    }
    return String(source[bodyRange])
}

private func parsedKeys(in dictionaryBody: String) -> Set<String> {
    Set(dictionaryBody.split(separator: "\n").compactMap { line in
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""), let end = trimmed.dropFirst().firstIndex(of: "\"") else {
            return nil
        }
        return String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
    })
}

private struct StringCatalog: Decodable {
    let strings: [String: StringCatalogEntry]
}

private struct StringCatalogEntry: Decodable {}
