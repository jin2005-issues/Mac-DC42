import SwiftUI
import UniformTypeIdentifiers

/// Home View - Dashboard with quick actions
struct HomeView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @EnvironmentObject var browserViewModel: BrowserViewModel
    @State private var showingImporter = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Quick Actions
                    quickActionsSection
                    
                    // Recent Images
                    recentImagesSection
                }
                .padding()
            }
            .navigationTitle("DC42Studio")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
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
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Classic Mac Disk Utility")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                QuickActionCard(
                    icon: "plus.circle.fill",
                    title: "Create Image",
                    description: "Make a new DC42",
                    color: .blue
                ) {
                    showingImporter = true
                }
                
                NavigationLink {
                    LibraryView()
                        .environmentObject(viewModel)
                } label: {
                    QuickActionCard(
                        icon: "folder.fill",
                        title: "Open Image",
                        description: "Browse your files",
                        color: .orange
                    )
                }
                
                NavigationLink {
                    BrowserView()
                        .environmentObject(browserViewModel)
                } label: {
                    QuickActionCard(
                        icon: "doc.text.magnifyingglass",
                        title: "Browse",
                        description: "View contents",
                        color: .green
                    )
                }
                
                NavigationLink {
                    ConvertView()
                } label: {
                    QuickActionCard(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Convert",
                        description: "Change format",
                        color: .purple
                    )
                }
            }
        }
    }
    
    // MARK: - Recent Images Section
    
    private var recentImagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Images")
                    .font(.headline)
                
                Spacer()
                
                if !viewModel.images.isEmpty {
                    Button("See All") {
                        // Navigate to library
                    }
                    .font(.subheadline)
                }
            }
            
            if viewModel.images.isEmpty {
                EmptyStateView(
                    icon: "doc.badge.plus",
                    title: "No Recent Images",
                    message: "Open a DC42 file to get started"
                )
            } else {
                ForEach(viewModel.images.prefix(3)) { image in
                    NavigationLink {
                        ImageDetailView(image: image)
                            .environmentObject(browserViewModel)
                    } label: {
                        ImageRowView(image: image)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                Task {
                    await viewModel.importImage(from: url)
                }
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

/// Quick Action Card
struct QuickActionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Image Row View
struct ImageRowView: View {
    let image: DC42Image
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(image.volumeName)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text(image.formatType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(ByteCountFormatter.string(fromByteCount: Int64(image.totalSize), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    HomeView()
        .environmentObject(MainViewModel())
        .environmentObject(BrowserViewModel())
}
