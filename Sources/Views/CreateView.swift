import SwiftUI
import UniformTypeIdentifiers

/// Create View - Create new DC42 images
struct CreateView: View {
    @EnvironmentObject var viewModel: CreateViewModel
    @EnvironmentObject var convertViewModel: ConvertViewModel
    @State private var showingFolderPicker = false
    @State private var isDragging = false
    @State private var showingSuccessAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Drop Zone
                    dropZoneSection
                    
                    // Configuration
                    if viewModel.hasSource {
                        configurationSection
                    }
                    
                    // Creation Progress
                    if viewModel.isCreating {
                        progressSection
                    }
                    
                    // Error
                    if let error = viewModel.errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Create Image")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await viewModel.createImage()
                            if viewModel.createdImage != nil {
                                showingSuccessAlert = true
                            }
                        }
                    } label: {
                        if viewModel.isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(!viewModel.canCreate)
                }
            }
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderImport(result)
            }
            .alert("Image Created", isPresented: $showingSuccessAlert) {
                Button("Open in Browser") {
                    // Navigate to browser
                }
                Button("Create Another") {
                    viewModel.reset()
                }
                Button("Done", role: .cancel) {}
            } message: {
                Text("Your DC42 image has been created successfully.")
            }
        }
    }
    
    // MARK: - Drop Zone Section
    
    private var dropZoneSection: some View {
        VStack(spacing: 16) {
            DropZoneView(
                isDragging: $isDragging,
                hasContent: viewModel.hasSource
            ) {
                showingFolderPicker = true
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
            }
            
            if viewModel.hasSource {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    
                    Text(viewModel.sourceName)
                        .font(.subheadline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button {
                        viewModel.sourceURL = nil
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
    
    // MARK: - Configuration Section
    
    private var configurationSection: some View {
        VStack(spacing: 16) {
            // Volume Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Volume Name")
                    .font(.headline)
                
                TextField("Enter volume name", text: $viewModel.volumeName)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Format Type
            VStack(alignment: .leading, spacing: 8) {
                Text("Format Type")
                    .font(.headline)
                
                Picker("Format", selection: $viewModel.formatType) {
                    ForEach(DC42FormatType.allCases, id: \.self) { format in
                        Text(format.description).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Comment
            VStack(alignment: .leading, spacing: 8) {
                Text("Comment (Optional)")
                    .font(.headline)
                
                TextField("Add a comment", text: $viewModel.comment, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: viewModel.creationProgress) {
                Text("Creating Image...")
                    .font(.headline)
            }
            
            Text("\(Int(viewModel.creationProgress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
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
    
    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                viewModel.sourceURL = url
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
                viewModel.sourceURL = url
            }
        }
        
        return true
    }
}

/// Drop Zone View
struct DropZoneView: View {
    @Binding var isDragging: Bool
    let hasContent: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: hasContent ? "checkmark.circle.fill" : "folder.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(hasContent ? .green : .blue)
                
                Text(hasContent ? "Source Selected" : "Drop Folder Here")
                    .font(.headline)
                
                Text(hasContent ? "Tap to change" : "or click to browse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isDragging ? Color.blue : Color.clear,
                                style: StrokeStyle(lineWidth: 3, dash: [8])
                            )
                    )
            )
            .overlay(
                isDragging ?
                VStack {
                    Text("Release to select")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                : nil
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CreateView()
        .environmentObject(CreateViewModel())
        .environmentObject(ConvertViewModel())
}
