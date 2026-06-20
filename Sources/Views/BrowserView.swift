import SwiftUI
import UniformTypeIdentifiers

/// Browser View - Browse DC42 image contents
struct BrowserView: View {
    @EnvironmentObject var viewModel: BrowserViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var selectedNodeForPreview: HFSNode?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Breadcrumbs
                if !viewModel.breadcrumbs.isEmpty {
                    breadcrumbBar
                }
                
                // Content
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    contentList
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 16) {
                        if !viewModel.selectedNodes.isEmpty {
                            Button {
                                showingExporter = true
                            } label: {
                                Label("Extract", systemImage: "square.and.arrow.down")
                            }
                        }
                        
                        Menu {
                            Button {
                                showingImporter = true
                            } label: {
                                Label("Open Image", systemImage: "folder")
                            }
                            
                            Button {
                                viewModel.selectAll()
                            } label: {
                                Label("Select All", systemImage: "checkmark.circle")
                            }
                            
                            if !viewModel.selectedNodes.isEmpty {
                                Button {
                                    viewModel.deselectAll()
                                } label: {
                                    Label("Deselect All", systemImage: "circle")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search files")
            .onChange(of: viewModel.searchText) { _, newValue in
                if !newValue.isEmpty {
                    Task {
                        await viewModel.search()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "dc42") ?? .data,
                    .data
                ],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .fileExporter(
                isPresented: $showingExporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleExport(result)
            }
            .sheet(item: $selectedNodeForPreview) { node in
                FilePreviewSheet(node: node)
            }
        }
    }
    
    // MARK: - Breadcrumb Bar
    
    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.element.id) { index, node in
                    Button {
                        viewModel.navigateToBreadcrumb(at: index - 1)
                    } label: {
                        HStack(spacing: 4) {
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            
                            Text(node.name)
                                .font(index == viewModel.breadcrumbs.count - 1 ? .headline : .subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading image...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            Text("Error Loading Image")
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                // Retry loading
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Content List
    
    private var contentList: some View {
        List {
            if viewModel.currentContents.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "folder",
                    description: Text("This folder is empty")
                )
            } else {
                ForEach(viewModel.currentContents) { node in
                    FileNodeRow(
                        node: node,
                        isSelected: viewModel.selectedNodes.contains(node.id)
                    ) {
                        if node.isDirectory {
                            viewModel.navigateTo(node)
                        } else {
                            selectedNodeForPreview = node
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if node.isDirectory {
                            viewModel.navigateTo(node)
                        } else {
                            selectedNodeForPreview = node
                        }
                    }
                    .simultaneousGesture(
                        LongPressGesture().onEnded { _ in
                            viewModel.toggleSelection(node)
                        }
                    )
                    .swipeActions(edge: .leading) {
                        Button {
                            viewModel.toggleSelection(node)
                        } label: {
                            Label(
                                viewModel.selectedNodes.contains(node.id) ? "Deselect" : "Select",
                                systemImage: viewModel.selectedNodes.contains(node.id) ? "circle" : "checkmark.circle"
                            )
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isExtracting {
                extractingOverlay
            }
        }
    }
    
    // MARK: - Extracting Overlay
    
    private var extractingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView(value: viewModel.extractionProgress) {
                    Text("Extracting Files...")
                        .font(.headline)
                }
                .progressViewStyle(.circular)
                
                Text("\(Int(viewModel.extractionProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Handlers
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                Task {
                    await viewModel.loadImage(from: url)
                }
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
    
    private func handleExport(_ result: Result<URL?, Error>) {
        switch result {
        case .success(let url):
            if let url = url {
                Task {
                    await viewModel.extractSelected(to: url)
                }
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

/// File Node Row
struct FileNodeRow: View {
    let node: HFSNode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .tertiary)
            
            // Icon
            Image(systemName: node.iconName)
                .font(.title2)
                .foregroundStyle(node.isDirectory ? .blue : .secondary)
                .frame(width: 32)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if !node.isDirectory {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(node.size), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if node.typeCode != "????" {
                        Text(node.typeCode)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
            
            // Chevron
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
}

/// File Preview Sheet
struct FilePreviewSheet: View {
    let node: HFSNode
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: node.iconName)
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                
                Text(node.name)
                    .font(.headline)
                
                VStack(spacing: 8) {
                    if !node.isDirectory {
                        HStack {
                            Text("Size")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(node.size), countStyle: .file))
                        }
                    }
                    
                    HStack {
                        Text("Type")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(node.typeCode)
                    }
                    
                    HStack {
                        Text("Creator")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(node.creatorCode)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
            }
            .padding()
            .navigationTitle("File Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

extension HFSNode: @retroactive Identifiable {}

#Preview {
    BrowserView()
        .environmentObject(BrowserViewModel())
}
