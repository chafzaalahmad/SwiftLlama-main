import SwiftUI

struct ContentView: View {
    @State var isPdfLoaded: Bool = false
    
    @StateObject private var viewModel = PDFQAViewModel()
    @State private var question: String = "What programming languages are mentioned?"

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {

                header

                pdfControls

                questionInput

                answerSection

                logSection
                
                Spacer()
                
            }
            .padding()
            .navigationTitle("Swift LLaMA PDF QA")
            .fileImporter(
                isPresented: Binding<Bool>(
                    get: { viewModel.showPDFImporter || viewModel.showModelImporter },
                    set: { newValue in
                        // Only reset both flags when closing
                        if !newValue {
                            viewModel.showPDFImporter = false
                            viewModel.showModelImporter = false
                        }
                    }
                ),
                allowedContentTypes: [.data, .pdf], // allow both types
                allowsMultipleSelection: false
            ) { result in
                guard let url = try? result.get().first else { return }

                if isPdfLoaded {
                    viewModel.handlePDF(.success(url))
                    viewModel.showPDFImporter = false
                } else {
                    viewModel.handleModel(.success(url))
                    viewModel.showModelImporter = false
                }
                
                isPdfLoaded = false
            }
        }
    }
}

// MARK: - UI Sections
private extension ContentView {

    var header: some View {
        Text("Ask your PDF")
            .font(.title.bold())
    }

    var pdfControls: some View {
        HStack {
            Button {
                isPdfLoaded = true
                viewModel.showPDFImporter = true
            } label: {
                Label("Import PDF", systemImage: "doc.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                isPdfLoaded = false
                viewModel.showModelImporter = true
            } label: {
                Label("Load LLM Model", systemImage: "brain")
            }
            .buttonStyle(.borderedProminent)

            if viewModel.isLoadingModel {
                ProgressView("Loading LLM Model…")
                    .padding(.leading, 8)
            }
            
            if viewModel.isIndexing {
                ProgressView("Indexing PDF…")
                    .padding(.leading, 8)
            }
        }
    }

    var questionInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Question")
                .font(.headline)

            TextField("Ask something about the PDF…", text: $question, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)
                .onSubmit(askQuestion)

            Button("Ask") {
                askQuestion()
            }
            .buttonStyle(.bordered)
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    var answerSection: some View {
        ScrollView {
            Text(viewModel.result.isEmpty ? "Answer will appear here…" : viewModel.result)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    var logSection: some View {
        ScrollView {
            Text(viewModel.logs.isEmpty ? "Logs will be added here…" : viewModel.logs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Actions
private extension ContentView {

    func askQuestion() {
        guard !question.isEmpty else { return }
        viewModel.ask(question)
    }

    func handlePDFImport(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        viewModel.handlePDF(.success(url))
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
