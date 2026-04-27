import Foundation
import Testing
@testable import PitcherPlantApp

@Test
func codeSimilarityAnalyzerBuildsStructuredEvidence() throws {
    let docA = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/a.swift"),
        filename: "a.swift",
        ext: "swift",
        content: "",
        cleanText: "",
        codeBlocks: [
            """
            func login(user: String, password: String) -> Bool {
                if user.isEmpty || password.isEmpty { return false }
                let digest = user + ":" + password
                return digest.count > 4
            }
            """
        ],
        author: "",
        images: []
    )
    let docB = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/b.swift"),
        filename: "b.swift",
        ext: "swift",
        content: "",
        cleanText: "",
        codeBlocks: [
            """
            func login(name: String, secret: String) -> Bool {
                if name.isEmpty || secret.isEmpty { return false }
                let digest = name + ":" + secret
                return digest.count > 4
            }
            """
        ],
        author: "",
        images: []
    )

    let matches = CodeSimilarityAnalyzer().analyze(documents: [docA, docB])
    let pair = try #require(matches.first)
    #expect(pair.score >= 0.60)
    #expect(pair.detailLines.count >= 4)
    #expect(pair.attachments.count == 3)
    #expect(pair.evidence.contains("片段"))
}

@Test
func textSimilarityBuildsContextEvidenceAndParaphraseMarker() throws {
    let prefixA = String(repeating: "A", count: 140)
    let prefixB = String(repeating: "B", count: 140)
    let shared = "共同利用 SSRF 读取 metadata endpoint 并提取临时凭证"
    let docA = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/a.md"),
        filename: "a.md",
        ext: "md",
        content: "\(prefixA) \(shared) 后续分析",
        cleanText: "共同 利用 ssrf 读取 metadata endpoint 提取 临时 凭证",
        codeBlocks: [],
        author: "",
        images: []
    )
    let docB = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/b.md"),
        filename: "b.md",
        ext: "md",
        content: "\(prefixB) \(shared) 复现过程",
        cleanText: "共同 利用 ssrf 读取 metadata endpoint 提取 临时 凭证",
        codeBlocks: [],
        author: "",
        images: []
    )

    let pair = try #require(TextSimilarityAnalyzer().analyze(documents: [docA, docB], threshold: 0.5).first)

    #expect(pair.evidence.contains("SSRF") || pair.evidence.contains("ssrf"))
    #expect(pair.detailLines.contains(where: { $0.contains("最长公共片段") }))
    #expect(pair.attachments.count >= 2)
}

@Test
func metadataCollisionUsesLastModifiedByAuthor() {
    let docA = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/a.docx"),
        filename: "a.docx",
        ext: "docx",
        content: "alpha",
        cleanText: "alpha",
        codeBlocks: [],
        author: "",
        lastModifiedBy: "SharedEditor",
        images: []
    )
    let docB = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/b.docx"),
        filename: "b.docx",
        ext: "docx",
        content: "beta",
        cleanText: "beta",
        codeBlocks: [],
        author: "SharedEditor",
        images: []
    )

    let collision = MetadataCollisionAnalyzer().analyze(documents: [docA, docB]).first

    #expect(collision?.author == "SharedEditor")
    #expect(collision?.files.sorted() == ["a.docx", "b.docx"])
}

@Test
func fingerprintAnalyzerUsesWrappingStableHash() {
    let document = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/wrapping.md"),
        filename: "wrapping.md",
        ext: "md",
        content: "",
        cleanText: "this token forces fnv hash wrapping during fingerprint generation",
        codeBlocks: [],
        author: "alice",
        images: []
    )

    let record = FingerprintAnalyzer().buildRecords(documents: [document], scanDirectory: "date").first

    #expect(record?.filename == "wrapping.md")
    #expect(record?.simhash.count == 16)
}

@Test
func imageReuseCountsExamplesAndUsesThreeHashes() throws {
    let leftImage = ParsedImage(
        source: "docx word/media/a.png",
        perceptualHash: "0000000000000000",
        averageHash: "ffffffffffffffff",
        differenceHash: "aaaaaaaaaaaaaaaa",
        ocrPreview: "login screenshot",
        thumbnailBase64: "ZmFrZQ=="
    )
    let rightImage = ParsedImage(
        source: "pdf page 1",
        perceptualHash: "0000000000000001",
        averageHash: "fffffffffffffffe",
        differenceHash: "aaaaaaaaaaaaaaab",
        ocrPreview: "login screenshot copy",
        thumbnailBase64: "ZmFrZTI="
    )
    let docA = ParsedDocument(url: URL(fileURLWithPath: "/tmp/a.docx"), filename: "a.docx", ext: "docx", content: "", cleanText: "", codeBlocks: [], author: "", images: [leftImage])
    let docB = ParsedDocument(url: URL(fileURLWithPath: "/tmp/b.pdf"), filename: "b.pdf", ext: "pdf", content: "", cleanText: "", codeBlocks: [], author: "", images: [rightImage])

    let pair = try #require(ImageReuseAnalyzer().analyze(documents: [docA, docB], threshold: 1).first)

    #expect(pair.evidence.contains("命中图片数：1"))
    #expect(pair.detailLines.contains(where: { $0.contains("pHash") }))
    #expect(pair.attachments.count >= 2)
}
