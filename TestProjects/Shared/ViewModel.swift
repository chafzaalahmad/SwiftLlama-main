import Foundation
import SwiftUI
import Combine
import SwiftLlama
import PDFKit

// MARK: - PDFQAViewModel with batching / streaming
@MainActor
final class PDFQAViewModel: ObservableObject {

    // MARK: - UI State
    @Published var result: String = ""
    @Published var logs: String = ""
    @Published var showPDFImporter = false
    @Published var showModelImporter = false
    @Published var isIndexing: Bool = false
    @Published var isLoadingModel: Bool = false

    // MARK: - Services
    private let extractor = PDFTextExtractor()
    private let chunker = Chunker()
    private let retriever = Retriever()

    // MARK: - LLaMA / Mistral
    private var llama: SwiftLlama?

    // MARK: - PDF Handling
    func handlePDF(_ result: Result<URL, Error>) {
        guard let url = try? result.get() else { return }
        isIndexing = true

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let text = try self.extractor.extract(from: url)
                let chunks = self.chunker.chunk(text, size: 150) // smaller chunks for memory
                self.retriever.buildIndex(chunks)

                self.isIndexing = false
                logs += "✅ PDF indexed, chunks: \(chunks.count)\n"
                print("✅ PDF indexed, chunks:", chunks.count)
            } catch {
                self.isIndexing = false
                logs += "❌ PDF extraction error: \(error)\n"
                print("❌ PDF extraction error:", error)
            }
        }
    }
    
    func handleModel(_ result: Result<URL, Error>) {
        // mistral-7b-instruct-v0.3-q8_0.gguf use for testing
        guard let url = try? result.get() else { return }
        Task {
            do {
                isLoadingModel = true
                try await loadModel(at: url)
                isLoadingModel = false
            } catch {
                isLoadingModel = false
                print("Error:", error)
            }
        }
    }
    
    /// Load a GGUF model safely (sandboxed on macOS)
    private func loadModel(at url: URL) async throws {
        // Start security-scoped access
        guard url.startAccessingSecurityScopedResource() else {
            logs += "Cannot access llm model file (sandbox)\n"
            throw NSError(domain: "LLMActor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access file (sandbox)"])
        }

        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let config = Configuration(
                seed: 42,
                topK: 40,
                topP: 0.9,
                nCTX: 2048,        // Mistral handles longer context
                temperature: 0.2,
                batchSize: 128,    // Safe for 7B
                stopSequence: nil,
                maxTokenCount: 512,
                stopTokens: []
            )

            llama = try SwiftLlama(modelPath: url.path, modelConfiguration: config)
            
            logs += "✅ Model loaded successfully\n"
            print("✅ Model loaded successfully")
        } catch {
            logs += "❌ Failed to load model: \(error)\n"
            print("❌ Failed to load model:", error)
            throw error
        }
    }
    
    // MARK: - Run QA with batching + streaming
    func ask(_ question: String) {
        result = ""

        guard !retriever.chunks.isEmpty else {
            result = "Failed to load model"
            return
        }
        
        guard let llama = self.llama else {
            result = "No PDF content indexed."
            return
        }
        
        
        // 🔹 Batch: process chunks sequentially
        let chunksToProcess = retriever.chunks
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var finalAnswer = ""

            for chunk in chunksToProcess {
                let context = chunk.text

                let prompt = Prompt(
                    type: .mistral,
                    systemPrompt: "You are a helpful assistant that extracts structured information from text.",
                    userMessage: """
                    \(question)
                    
                    Document:
                    \(context)
                    """
                )

                var chunkAnswer = ""

                do {
                    // 🔹 Streaming tokens from model
                    for try await token in await llama.start(for: prompt) {
                        chunkAnswer += token
                        await MainActor.run { self.result = finalAnswer + chunkAnswer }
                    }

                    // 🔹 Append chunk answer to final
                    finalAnswer += chunkAnswer + "\n"
                } catch {
                    print("❌ LLM chunk error:", error)
                }
            }

            // 🔹 Ensure fallback
            await MainActor.run {
                self.result = finalAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                if self.result.isEmpty { self.result = "Not found in document." }
            }

            print("✅ Full QA output length:", self.result.count)
        }
    }
}

// MARK: - PDF Extraction
struct PDFTextExtractor {
    func extract(from url: URL) throws -> String {
        guard url.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "PDF", code: 1)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let doc = PDFDocument(url: url) else { return "" }
        var text = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                text += pageText + "\n\n"
            }
        }
        print("✅ Extracted PDF length:", text.count)
        return text
    }
}

// MARK: - Chunking
struct Chunk {
    let id: Int
    let text: String
}

struct Chunker {
    func chunk(_ text: String, size: Int = 150) -> [Chunk] {
        let words = text.split { $0 == " " || $0 == "\n" }
        var chunks: [Chunk] = []
        var index = 0
        var id = 0
        while index < words.count {
            let end = min(index + size, words.count)
            let content = words[index..<end].joined(separator: " ")
            chunks.append(Chunk(id: id, text: content))
            id += 1
            index = end
        }
        return chunks
    }
}

// MARK: - Retriever (TF-IDF)
final class Retriever {
    var chunks: [Chunk] = []
    private var vectors: [[String: Double]] = []
    private var idf: [String: Double] = [:]

    func buildIndex(_ chunks: [Chunk]) {
        self.chunks = chunks

        let tokenized = chunks.map { TFIDF.tokenize($0.text) }
        let docCount = Double(tokenized.count)

        var df: [String: Double] = [:]
        for tokens in tokenized {
            Set(tokens).forEach { df[$0, default: 0] += 1 }
        }

        idf = df.mapValues { log((docCount + 1) / ($0 + 1)) + 1 }
        vectors = tokenized.map { TFIDF.vector(tokens: $0, idf: idf) }
    }
}

// MARK: - TF-IDF Math
struct TFIDF {
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func vector(tokens: [String], idf: [String: Double]) -> [String: Double] {
        var tf: [String: Double] = [:]
        tokens.forEach { tf[$0, default: 0] += 1 }

        let total = Double(tokens.count)
        return Dictionary(uniqueKeysWithValues:
            tf.map { key, value in
                (key, (value / total) * (idf[key] ?? 0))
            }
        )
    }
}
