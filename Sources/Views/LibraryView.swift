import SwiftUI
import UniformTypeIdentifiers

/// Library View - Browse and manage DC42 images
struct LibraryView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @EnvironmentObject var convertViewModel: ConvertViewModel
    @State private var showingImporter = false
    @State private var showingSortMenu = false
    @State private var selectedForConversion: DC42Image?
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.images.isEmpty {
                    emptyState
                } else {
                    imageList
                }
            }
            .navigationTitle("Library")
            .searchable(text: $viewModel.searchText, prompt: "Search images")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        ForEach(MainViewModel.SortOrder.allCases) { order in
                            Button {
                                viewModel.sortOrder = order
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                    if viewModel.sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "dc42") ?? .data,
                    .data
                ],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .sheet(item: $selectedForConversion) { image in
                ConvertSheetView(sourceImage: image)
                    .environmentObject(convertViewModel)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("No Images Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Import DC42 files to view and manage them here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingImporter = true
            } label: {
                Label("Import Images", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Image List
    
    private var imageList: some View {
        List {
            ForEach(viewModel.filteredImages) { image in
                NavigationLink {
                    ImageDetailView(image: image)
                } label: {
                    ImageListRow(image: image)
                }
                .contextMenu {
                    Button {
                        selectedForConversion = image
                    } label: {
                        Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    Button {
                        Task {
                            await viewModel.refreshImage(image)
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        viewModel.removeImage(image)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.removeImage(image)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }
    
    // MARK: - Helpers
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                Task {
                    await viewModel.importImage(from: url)
                }
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

/// Image List Row
struct ImageListRow: View {
    let image: DC42Image
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(image.isValid ? .blue : .red)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(image.volumeName)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    FormatBadge(format: image.formatType)
                    
                    Text(image.diskFormat.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if !image.isValid {
                        Text("Invalid")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            
            Spacer()
            
            // Size
            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteCountFormatter.string(fromByteCount: Int64(image.totalSize), countStyle: .file))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let date = image.modificationDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Format Badge
struct FormatBadge: View {
    let format: DC42FormatType
    
    var body: some View {
        Text(format.rawValue.description)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    
    private var color: Color {
        switch format {
        case .standard: return .blue
        case .withComment: return .orange
        case .compressed: return .purple
        }
    }
}

/// Convert Sheet View
struct ConvertSheetView: View {
    let sourceImage: DC42Image
    @EnvironmentObject var viewModel: ConvertViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Source Info
                VStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    
                    Text(sourceImage.volumeName)
                        .font(.headline)
                    
                    Text(ByteCountFormatter.string(fromByteCount: Int64(sourceImage.totalSize), countStyle: .file))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // Format Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Output Format")
                        .font(.headline)
                    
                    Picker("Format", selection: $viewModel.outputFormat) {
                        ForEach(ConversionFormat.allCases) { format in
                            Label(format.description, systemImage: format.icon)
                                .tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                
                // Progress
                if viewModel.isConverting {
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.conversionProgress)
                        
                        Text("\(Int(viewModel.conversionProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                
                // Error
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Action Buttons
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button {
                        Task {
                            await viewModel.loadSource(from: sourceImage.fileURL)
                            await viewModel.convert()
                        }
                    } label: {
                        if viewModel.isConverting {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text("Convert")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isConverting)
                }
                .padding()
            }
            .navigationTitle("Convert Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    LibraryView()
        .environmentObject(MainViewModel())
        .environmentObject(ConvertViewModel())
}
