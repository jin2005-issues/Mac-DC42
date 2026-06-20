import SwiftUI

/// Image Detail View - Show DC42 image information
struct ImageDetailView: View {
    let image: DC42Image
    @EnvironmentObject var browserViewModel: BrowserViewModel
    @Environment(\.openURL) var openURL
    @State private var showingBrowser = false
    @State private var showingShareSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Info Cards
                infoSection
                
                // Metadata
                metadataSection
                
                // Actions
                actionsSection
            }
            .padding()
        }
        .navigationTitle(image.volumeName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingBrowser = true
                    } label: {
                        Label("Browse Contents", systemImage: "doc.text.magnifyingglass")
                    }
                    
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(isPresented: $showingBrowser) {
            BrowserView()
                .environmentObject(browserViewModel)
                .onAppear {
                    Task {
                        await browserViewModel.loadImage(from: image.fileURL)
                    }
                }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.fill")
                .font(.system(size: 64))
                .foregroundStyle(image.isValid ? .blue : .red)
            
            Text(image.volumeName)
                .font(.title)
                .fontWeight(.bold)
            
            HStack(spacing: 12) {
                FormatBadge(format: image.formatType)
                
                if image.isValid {
                    Label("Valid", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Invalid", systemImage: "xmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        VStack(spacing: 12) {
            // Size Info
            HStack {
                SizeCard(
                    title: "Total Size",
                    value: ByteCountFormatter.string(fromByteCount: Int64(image.totalSize), countStyle: .file),
                    icon: "externaldrive.fill",
                    color: .blue
                )
                
                SizeCard(
                    title: "Data Fork",
                    value: ByteCountFormatter.string(fromByteCount: Int64(image.dataForkSize), countStyle: .file),
                    icon: "doc.fill",
                    color: .green
                )
            }
            
            HStack {
                SizeCard(
                    title: "Resource Fork",
                    value: ByteCountFormatter.string(fromByteCount: Int64(image.resourceForkSize), countStyle: .file),
                    icon: "doc.on.doc.fill",
                    color: .orange
                )
                
                SizeCard(
                    title: "Files",
                    value: "\(image.fileCount)",
                    icon: "doc.on.folder.fill",
                    color: .purple
                )
            }
        }
    }
    
    // MARK: - Metadata Section
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
            
            VStack(spacing: 0) {
                MetadataRow(label: "File Name", value: image.fileURL.lastPathComponent)
                Divider()
                MetadataRow(label: "Format", value: image.formatType.description)
                Divider()
                MetadataRow(label: "Disk Type", value: image.diskFormat.description)
                Divider()
                MetadataRow(label: "Sector Size", value: "\(image.diskFormat.sectorSize) bytes")
                
                if let created = image.creationDate {
                    Divider()
                    MetadataRow(label: "Created", value: created.formatted(date: .abbreviated, time: .shortened))
                }
                
                if let modified = image.modificationDate {
                    Divider()
                    MetadataRow(label: "Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if let comment = image.comment, !comment.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Comment")
                        .font(.headline)
                    
                    Text(comment)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                showingBrowser = true
            } label: {
                Label("Browse Contents", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            HStack(spacing: 12) {
                ShareLink(item: image.fileURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// Size Card
struct SizeCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Metadata Row
struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        ImageDetailView(
            image: DC42Image(
                fileURL: URL(fileURLWithPath: "/test.dc42"),
                volumeName: "System 7.5.5",
                totalSize: 1_440_000,
                usedSize: 1_200_000,
                formatType: .standard,
                diskFormat: .floppy1440KB,
                dataForkSize: 1_100_000,
                resourceForkSize: 100_000,
                creationDate: Date(),
                modificationDate: Date(),
                isValid: true,
                fileCount: 42
            )
        )
        .environmentObject(BrowserViewModel())
    }
}
