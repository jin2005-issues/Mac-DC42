import SwiftUI
import UniformTypeIdentifiers

/// Convert View - Convert DC42 to other formats
struct ConvertView: View {
    @EnvironmentObject var viewModel: ConvertViewModel
    @State private var showingFilePicker = false
    @State private var showingSavePanel = false
    @State private var isDragging = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Drop Zone
                    dropZoneSection
                    
                    // Source Info
                    if viewModel.sourceImage != nil {
                        sourceInfoSection
                    }
                    
                    // Output Format
                    outputFormatSection
                    
                    // Progress
                    if viewModel.isConverting {
                        progressSection
                    }
                    
                    // Result
                    if let job = viewModel.completedJob, job.status.isCompleted {
                        resultSection(job)
                    }
                    
                    // Error
                    if let error = viewModel.errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Convert")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await viewModel.convert()
                        }
                    } label: {
                        if viewModel.isConverting {
                            ProgressView()
                        } else {
                            Text("Convert")
                        }
                    }
                    .disabled(!viewModel.canConvert)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [
                    UTType(filenameExtension: "dc42") ?? .data,
                    .iso,
                    .diskImage,
                    UTType(filenameExtension: "img") ?? .data
                ],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .fileExporter(
                isPresented: $showingSavePanel,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { _ in
                // Handle save completion
            }
        }
    }
    
    // MARK: - Drop Zone Section
    
    private var dropZoneSection: some View {
        VStack(spacing: 16) {
            DropZoneView(
                isDragging: $isDragging,
                hasContent: viewModel.sourceURL != nil
            ) {
                showingFilePicker = true
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
            }
            
            if let sourceURL = viewModel.sourceURL {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.blue)
                    
                    Text(sourceURL.lastPathComponent)
                        .font(.subheadline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button {
                        viewModel.sourceURL = nil
                        viewModel.sourceImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    // MARK: - Source Info Section
    
    private var sourceInfoSection: some View {
        Group {
            if let image = viewModel.sourceImage {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Source Image")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.title)
                            .foregroundStyle(.blue)
                            .frame(width: 50, height: 50)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(image.volumeName)
                                .font(.headline)
                            
                            Text(ByteCountFormatter.string(fromByteCount: Int64(image.totalSize), countStyle: .file))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    // MARK: - Output Format Section
    
    private var outputFormatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output Format")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(ConversionFormat.allCases) { format in
                    FormatOptionCard(
                        format: format,
                        isSelected: viewModel.outputFormat == format
                    ) {
                        viewModel.outputFormat = format
                    }
                }
            }
            
            // Output filename preview
            if viewModel.sourceURL != nil {
                HStack {
                    Text("Output:")
                        .foregroundStyle(.secondary)
                    
                    Text(viewModel.outputFileName)
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                .font(.subheadline)
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: viewModel.conversionProgress) {
                Text("Converting...")
                    .font(.headline)
            }
            
            Text("\(Int(viewModel.conversionProgress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Result Section
    
    private func resultSection(_ job: ConversionJob) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            
            Text("Conversion Complete")
                .font(.headline)
            
            if let outputURL = job.outputURL {
                HStack {
                    Text("Saved to:")
                        .foregroundStyle(.secondary)
                    
                    Text(outputURL.lastPathComponent)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .font(.subheadline)
                
                ShareLink(item: outputURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Error Section
    
    private func errorSection(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Handlers
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                Task {
                    await viewModel.loadSource(from: url)
                }
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            Task { @MainActor in
                await viewModel.loadSource(from: url)
            }
        }
        
        return true
    }
}

/// Format Option Card
struct FormatOptionCard: View {
    let format: ConversionFormat
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: format.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                
                Text(format.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(format.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ConvertView()
        .environmentObject(ConvertViewModel())
}
