import SwiftUI

struct ContentView: View {
    @State private var isPdfLoaded = false
    @StateObject private var viewModel = PDFQAViewModel()
    @State private var question: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background Gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.18),
                        Color(red: 0.15, green: 0.20, blue: 0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        actionCards
                        questionCard
                        answerCard
                        logsCard
                    }
                    .padding()
                }
            }
            .navigationTitle("SwiftLLaMA PDF QA")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: Binding(
                    get: { viewModel.showPDFImporter || viewModel.showModelImporter },
                    set: { if !$0 { viewModel.showPDFImporter = false; viewModel.showModelImporter = false } }
                ),
                allowedContentTypes: [.data, .pdf],
                allowsMultipleSelection: false
            ) { result in
                guard let url = try? result.get().first else { return }
                if isPdfLoaded {
                    viewModel.handlePDF(.success(url))
                } else {
                    viewModel.handleModel(.success(url))
                }
                isPdfLoaded = false
            }
        }
    }
}

// MARK: - Sections
private extension ContentView {

    var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(.white)
            Text("Ask Your PDF")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("On-device LLM powered Q&A")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.top, 20)
    }

    var actionCards: some View {
        HStack(spacing: 12) {
            actionButton(
                title: "Import PDF",
                icon: "doc.fill",
                color: .blue
            ) {
                isPdfLoaded = true
                viewModel.showPDFImporter = true
            }
            
            actionButton(
                title: "Load Model",
                icon: "brain.head.profile",
                color: .purple
            ) {
                isPdfLoaded = false
                viewModel.showModelImporter = true
            }
        }
        .overlay(statusOverlay, alignment: .bottom)
    }

    var questionCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Your Question", systemImage: "questionmark.circle")
                    .font(.headline)
                
                TextField("Ask something about the PDF…", text: $question, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                Button {
                    askQuestion()
                } label: {
                    Label("Ask", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    var answerCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Answer", systemImage: "sparkles")
                    .font(.headline)
                
                Text(viewModel.result.isEmpty ? "Answer will appear here…" : viewModel.result)
                    .font(.body)
                    .foregroundStyle(.white.opacity(viewModel.result.isEmpty ? 0.6 : 1))
            }
        }
    }

    var logsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Logs", systemImage: "terminal")
                    .font(.headline)
                
                Text(viewModel.logs.isEmpty ? "Logs will appear here…" : viewModel.logs)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    var statusOverlay: some View {
        VStack(spacing: 4) {
            if viewModel.isLoadingModel {
                ProgressView("Loading LLM Model…")
            }
            if viewModel.isIndexing {
                ProgressView("Indexing PDF…")
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Reusable UI
private extension ContentView {

    func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.subheadline.bold())
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.gradient)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 8)
    }
}

// MARK: - Actions
private extension ContentView {
    func askQuestion() {
        guard !question.isEmpty else { return }
        viewModel.ask(question)
    }
}

#Preview {
    ContentView()
}
