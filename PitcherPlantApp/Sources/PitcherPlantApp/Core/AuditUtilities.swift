import AppKit
import CoreGraphics
import Foundation
import NaturalLanguage
import Vision

enum XMLTextExtractor {
    static func plainText(from data: Data) -> String {
        guard let xml = String(data: data, encoding: .utf8) else { return "" }
        let text = xml.replacingOccurrences(of: #"</w:p>"#, with: "\n", options: .regularExpression)
        let withoutTags = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return withoutTags.replacingOccurrences(of: "&amp;", with: "&")
    }

    static func metadataValue(named tag: String, in data: Data) -> String {
        guard let xml = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: "<\(tag)>(.*?)</\(tag)>", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return ""
        }
        return String(xml[range])
    }
}

enum ImageHashing {
    static func perceptualHash(for data: Data) -> String {
        guard let image = NSImage(data: data), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return String(repeating: "0", count: 16)
        }
        let size = 32
        let lowSize = 8
        let pixels = grayscalePixels(cgImage: cgImage, width: size, height: size)
        guard pixels.count == size * size else {
            return String(repeating: "0", count: 16)
        }
        var coefficients = Array(repeating: CGFloat(0), count: lowSize * lowSize)
        for u in 0..<lowSize {
            for v in 0..<lowSize {
                var sum = CGFloat(0)
                for x in 0..<size {
                    for y in 0..<size {
                        let pixel = pixels[y * size + x]
                        let cosX = cos(((2 * CGFloat(x) + 1) * CGFloat(u) * .pi) / CGFloat(2 * size))
                        let cosY = cos(((2 * CGFloat(y) + 1) * CGFloat(v) * .pi) / CGFloat(2 * size))
                        sum += pixel * cosX * cosY
                    }
                }
                coefficients[u * lowSize + v] = sum
            }
        }
        let acCoefficients = Array(coefficients.dropFirst())
        let median = acCoefficients.sorted()[acCoefficients.count / 2]
        let bits = coefficients.map { $0 >= median ? "1" : "0" }.joined()
        return binaryStringToHex(bits)
    }

    static func averageHash(for data: Data) -> String {
        guard let image = NSImage(data: data), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return String(repeating: "0", count: 16)
        }
        let size = 8
        let pixels = grayscalePixels(cgImage: cgImage, width: size, height: size)
        guard !pixels.isEmpty else {
            return String(repeating: "0", count: 16)
        }
        let average = pixels.reduce(0, +) / CGFloat(pixels.count)
        let bits = pixels.map { $0 >= average ? "1" : "0" }.joined()
        return binaryStringToHex(bits)
    }

    static func differenceHash(for data: Data) -> String {
        guard let image = NSImage(data: data), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return String(repeating: "0", count: 16)
        }
        let pixels = grayscalePixels(cgImage: cgImage, width: 9, height: 8)
        guard !pixels.isEmpty else {
            return String(repeating: "0", count: 16)
        }
        var bits = ""
        for row in 0..<8 {
            for col in 0..<8 {
                let left = pixels[row * 9 + col]
                let right = pixels[row * 9 + col + 1]
                bits.append(left > right ? "1" : "0")
            }
        }
        return binaryStringToHex(bits)
    }

    static func thumbnailBase64(for data: Data) -> String {
        guard let image = NSImage(data: data),
              let resized = resizedJPEGData(from: image, maxSide: 280) else {
            return ""
        }
        return resized.base64EncodedString()
    }

    static func encodedImageData(for cgImage: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func grayscalePixels(cgImage: CGImage, width: Int, height: Int) -> [CGFloat] {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var raw = Array(repeating: UInt8(0), count: width * height)
        guard let context = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return []
        }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return raw.map { CGFloat($0) }
    }

    private static func binaryStringToHex(_ bits: String) -> String {
        let value = UInt64(bits, radix: 2) ?? 0
        return String(format: "%016llx", value)
    }

    private static func resizedJPEGData(from image: NSImage, maxSide: CGFloat) -> Data? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }
        let ratio = min(maxSide / sourceSize.width, maxSide / sourceSize.height, 1)
        let targetSize = CGSize(width: sourceSize.width * ratio, height: sourceSize.height * ratio)
        let result = NSImage(size: targetSize)
        result.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        result.unlockFocus()
        return result.jpegData(compressionQuality: 0.78)
    }
}

enum ImageOCRService {
    static func previewText(from data: Data) -> String {
        guard let image = NSImage(data: data), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            return String(text.prefix(120))
        } catch {
            return ""
        }
    }
}

extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}

enum CodeBlockExtractor {
    static func extract(from text: String) -> [String] {
        let regex = try? NSRegularExpression(pattern: #"```(?:\w+)?\s*([\s\S]*?)```"#)
        let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        var blocks = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if blocks.isEmpty {
            let lines = text.components(separatedBy: .newlines)
            var current: [String] = []
            for line in lines {
                if line.range(of: #"(def |class |for |while |if |import |curl|bash|sh|gcc|let |const )"#, options: .regularExpression) != nil {
                    current.append(line)
                } else if current.count >= 2 {
                    blocks.append(current.joined(separator: "\n"))
                    current.removeAll()
                } else {
                    current.removeAll()
                }
            }
            if current.count >= 2 {
                blocks.append(current.joined(separator: "\n"))
            }
        }
        return blocks.filter { $0.count > 20 }
    }

    static func candidates(from blocks: [String]) -> [CodeBlockCandidate] {
        blocks.enumerated().map { index, block in
            let lexicalTokens = block
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 }
            return CodeBlockCandidate(
                label: "片段 \(index + 1)",
                rawText: block,
                lexicalSignature: lexicalSignature(for: block),
                lexicalTokens: lexicalTokens,
                structuralSignature: structureSignature(for: block),
                preview: block
                    .components(separatedBy: .newlines)
                    .prefix(10)
                    .joined(separator: "\n")
            )
        }
    }

    private static func lexicalSignature(for text: String) -> String {
        normalizedCodeTokens(
            from: text,
            includePunctuation: false
        ).joined(separator: " ")
    }

    private static func structureSignature(for text: String) -> String {
        normalizedCodeTokens(
            from: text,
            includePunctuation: true
        ).joined(separator: " ")
    }

    private static func normalizedCodeTokens(from text: String, includePunctuation: Bool) -> [String] {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: #"//[^\n\r]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #""[^"]*"|'[^']*'"#, with: " str ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d+\b"#, with: " num ", options: .regularExpression)

        let pattern = includePunctuation
            ? #"[a-z_][a-z0-9_]*|\{|\}|\(|\)|\[|\]|;|,|\.|=|:|\+|\-|\*|/|<|>"#
            : #"[a-z_][a-z0-9_]*"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return regex?.matches(in: normalized, range: range).compactMap { match -> String? in
            guard let tokenRange = Range(match.range, in: normalized) else {
                return nil
            }
            let token = String(normalized[tokenRange])
            if codeKeywords.contains(token) {
                return token
            }
            if includePunctuation, punctuationTokens.contains(token) {
                return token
            }
            if token == "str" || token == "num" {
                return token
            }
            return "id"
        } ?? []
    }

    private static let codeKeywords: Set<String> = [
        "if", "else", "for", "while", "switch", "case", "class", "def", "func", "return",
        "import", "from", "try", "catch", "except", "let", "var", "const", "public",
        "private", "static", "struct", "enum", "async", "await", "with", "using"
    ]

    private static let punctuationTokens: Set<String> = [
        "{", "}", "(", ")", "[", "]", ";", ",", ".", "=", ":", "+", "-", "*", "/", "<", ">"
    ]
}

struct CodeBlockCandidate: Hashable, Sendable {
    let label: String
    let rawText: String
    let lexicalSignature: String
    let lexicalTokens: [String]
    let structuralSignature: String
    let preview: String
}

struct CodeMatch: Hashable, Sendable {
    let score: Double
    let lexicalScore: Double
    let structuralScore: Double
    let sharedTokenCount: Int
    let sharedTokenRatio: Double
    let summary: String
    let left: CodeBlockCandidate
    let right: CodeBlockCandidate
}

struct TextEvidence: Hashable, Sendable {
    let summary: String
    let leftContext: String
    let rightContext: String
    let longestCommonLength: Int
}

enum TextEvidenceBuilder {
    static func build(left: String, right: String) -> TextEvidence {
        let match = longestCommonSubstring(left: left, right: right)
        if match.length > 20 {
            let summary = String(left[match.leftRange]).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return TextEvidence(
                summary: String(summary.prefix(160)) + (summary.count > 160 ? "..." : ""),
                leftContext: context(in: left, range: match.leftRange),
                rightContext: context(in: right, range: match.rightRange),
                longestCommonLength: match.length
            )
        }
        let leftTerms = Set(terms(in: left))
        let rightTerms = Set(terms(in: right))
        let commonTerms = leftTerms
            .intersection(rightTerms)
            .sorted { $0.count > $1.count }
            .prefix(10)
            .joined(separator: " ")
        let summary = commonTerms.isEmpty ? "全文语义高度相似，未发现显著连续长句（可能是洗稿）" : commonTerms
        return TextEvidence(summary: summary, leftContext: "", rightContext: "", longestCommonLength: match.length)
    }

    private static func context(in text: String, range: Range<String.Index>) -> String {
        let start = text.index(range.lowerBound, offsetBy: -min(120, text.distance(from: text.startIndex, to: range.lowerBound)), limitedBy: text.startIndex) ?? text.startIndex
        let trailing = text.distance(from: range.upperBound, to: text.endIndex)
        let end = text.index(range.upperBound, offsetBy: min(120, trailing), limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end]).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func terms(in text: String) -> [String] {
        text.lowercased().split { character in
            !character.isLetter && !character.isNumber
        }.map(String.init)
    }

    private static func longestCommonSubstring(left: String, right: String) -> (leftRange: Range<String.Index>, rightRange: Range<String.Index>, length: Int) {
        let leftChars = Array(left)
        let rightChars = Array(right)
        guard !leftChars.isEmpty, !rightChars.isEmpty else {
            return (left.startIndex..<left.startIndex, right.startIndex..<right.startIndex, 0)
        }
        var previous = Array(repeating: 0, count: rightChars.count + 1)
        var bestLength = 0
        var bestLeftEnd = 0
        var bestRightEnd = 0
        for leftIndex in 1...leftChars.count {
            var current = Array(repeating: 0, count: rightChars.count + 1)
            for rightIndex in 1...rightChars.count {
                if leftChars[leftIndex - 1] == rightChars[rightIndex - 1] {
                    current[rightIndex] = previous[rightIndex - 1] + 1
                    if current[rightIndex] > bestLength {
                        bestLength = current[rightIndex]
                        bestLeftEnd = leftIndex
                        bestRightEnd = rightIndex
                    }
                }
            }
            previous = current
        }
        let leftStart = left.index(left.startIndex, offsetBy: bestLeftEnd - bestLength)
        let leftEnd = left.index(left.startIndex, offsetBy: bestLeftEnd)
        let rightStart = right.index(right.startIndex, offsetBy: bestRightEnd - bestLength)
        let rightEnd = right.index(right.startIndex, offsetBy: bestRightEnd)
        return (leftStart..<leftEnd, rightStart..<rightEnd, bestLength)
    }
}

enum TextNormalizer {
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(flag|ctf|cyber|key)\{.*?\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[a-fA-F0-9]{32,}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[a-zA-Z0-9+/]{50,}={0,2}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\w\s\u4e00-\u9fa5]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TFIDFVectorizer {
    let wordVectors: [[String: Double]]
    let charVectors: [[String: Double]]
    let wordWeight: Double
    let charWeight: Double

    init(documents: [String], wordNGramRange: ClosedRange<Int> = 1...1, charNGramRange: ClosedRange<Int> = 3...5, wordWeight: Double = 0.6, charWeight: Double = 0.4) {
        self.wordVectors = TFIDFVectorizer.buildVectors(for: documents, ngramRange: wordNGramRange, tokenizeWords: true)
        self.charVectors = TFIDFVectorizer.buildVectors(for: documents, ngramRange: charNGramRange, tokenizeWords: false)
        self.wordWeight = wordWeight
        self.charWeight = charWeight
    }

    func combinedCosineSimilarity(left: Int, right: Int) -> Double {
        let word = cosine(lhs: wordVectors[left], rhs: wordVectors[right])
        let char = cosine(lhs: charVectors[left], rhs: charVectors[right])
        return (wordWeight * word) + (charWeight * char)
    }

    private func cosine(lhs: [String: Double], rhs: [String: Double]) -> Double {
        let keys = Set(lhs.keys).union(rhs.keys)
        let dot = keys.reduce(0.0) { $0 + ((lhs[$1] ?? 0) * (rhs[$1] ?? 0)) }
        let lhsNorm = sqrt(lhs.values.reduce(0.0) { $0 + ($1 * $1) })
        let rhsNorm = sqrt(rhs.values.reduce(0.0) { $0 + ($1 * $1) })
        guard lhsNorm > 0, rhsNorm > 0 else { return 0 }
        return dot / (lhsNorm * rhsNorm)
    }

    private static func buildVectors(for documents: [String], ngramRange: ClosedRange<Int>, tokenizeWords: Bool) -> [[String: Double]] {
        let tokenized = documents.map { doc in
            tokenizeWords ? wordNGrams(in: doc, range: ngramRange) : charNGrams(in: doc, range: ngramRange)
        }
        let docCount = Double(max(documents.count, 1))
        var documentFrequency: [String: Double] = [:]
        for tokens in tokenized {
            for token in Set(tokens) {
                documentFrequency[token, default: 0] += 1
            }
        }

        return tokenized.map { tokens in
            let grouped = Dictionary(grouping: tokens, by: { $0 })
            let counts = grouped.mapValues(\.count)
            let total = Double(max(tokens.count, 1))
            var vector: [String: Double] = [:]
            for (token, count) in counts {
                let tf = Double(count) / total
                let idf = log((docCount + 1) / ((documentFrequency[token] ?? 0) + 1)) + 1
                vector[token] = tf * idf
            }
            return vector
        }
    }

    private static func tokenizeWordsIn(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).lowercased()
            if token.count > 1 {
                result.append(token)
            }
            return true
        }
        return result
    }

    private static func wordNGrams(in text: String, range: ClosedRange<Int>) -> [String] {
        let words = tokenizeWordsIn(text)
        guard words.count >= range.lowerBound else { return [] }
        var grams: [String] = []
        for n in range {
            guard words.count >= n else { continue }
            for index in 0...(words.count - n) {
                grams.append(words[index..<(index + n)].joined(separator: " "))
            }
        }
        return grams
    }

    private static func charNGrams(in text: String, range: ClosedRange<Int>) -> [String] {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        let chars = Array(cleaned)
        guard chars.count >= range.lowerBound else { return [] }
        var grams: [String] = []
        for n in range {
            guard chars.count >= n else { continue }
            for idx in 0...(chars.count - n) {
                grams.append(String(chars[idx..<(idx + n)]))
            }
        }
        return grams
    }
}

enum JaccardSimilarity {
    static func score(left: String, right: String, shingleSize: Int) -> Double {
        let lhs = shingles(in: left, size: shingleSize)
        let rhs = shingles(in: right, size: shingleSize)
        let union = lhs.union(rhs)
        guard !union.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(union.count)
    }

    private static func shingles(in text: String, size: Int) -> Set<String> {
        guard text.count >= size else { return [] }
        let chars = Array(text)
        return Set((0...(chars.count - size)).map { idx in
            String(chars[idx..<(idx + size)])
        })
    }
}

enum SimHasher {
    static func hexHash(for text: String) -> String {
        let tokens = text.split(separator: " ").map(String.init)
        var weights = Array(repeating: 0, count: 64)
        for token in tokens {
            let hash = stableHash(token)
            for bit in 0..<64 {
                if (hash >> bit) & 1 == 1 {
                    weights[bit] += 1
                } else {
                    weights[bit] -= 1
                }
            }
        }
        var result: UInt64 = 0
        for bit in 0..<64 where weights[bit] > 0 {
            result |= (1 << bit)
        }
        return String(format: "%016llx", result)
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }
}

enum HashDistance {
    static func hamming(_ left: String, _ right: String) -> Int {
        guard let lhs = UInt64(left, radix: 16), let rhs = UInt64(right, radix: 16) else { return 64 }
        return (lhs ^ rhs).nonzeroBitCount
    }
}

extension DateFormatter {
    static let pitcherPlantFileName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
