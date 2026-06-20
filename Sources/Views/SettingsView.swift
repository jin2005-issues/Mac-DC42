import SwiftUI

/// Settings View - App preferences
struct SettingsView: View {
    @AppStorage("defaultOutputFormat") private var defaultOutputFormat = ConversionFormat.iso.rawValue
    @AppStorage("autoValidateImages") private var autoValidateImages = true
    @AppStorage("showFileExtensions") private var showFileExtensions = true
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("preserveTimestamps") private var preserveTimestamps = true
    
    @State private var showingClearDataAlert = false
    @State private var showingAbout = false
    
    var body: some View {
        Form {
            // General Settings
            Section("General") {
                Toggle("Auto-validate images on open", isOn: $autoValidateImages)
                Toggle("Show file extensions", isOn: $showFileExtensions)
                Toggle("Confirm before deleting", isOn: $confirmBeforeDelete)
            }
            
            // Conversion Settings
            Section("Conversion") {
                Picker("Default output format", selection: $defaultOutputFormat) {
                    ForEach(ConversionFormat.allCases) { format in
                        Text(format.description).tag(format.rawValue)
                    }
                }
                
                Toggle("Preserve timestamps", isOn: $preserveTimestamps)
            }
            
            // Data Management
            Section("Data") {
                Button("Clear Recent Files") {
                    showingClearDataAlert = true
                }
                .foregroundStyle(.red)
                
                NavigationLink {
                    StorageView()
                } label: {
                    Text("Storage Usage")
                }
            }
            
            // About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                
                Button("About DC42Studio") {
                    showingAbout = true
                }
                
                Link(destination: URL(string: "https://github.com/dc42studio")!) {
                    HStack {
                        Text("Source Code")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Link(destination: URL(string: "https://github.com/dc42studio/issues")!) {
                    HStack {
                        Text("Report Issue")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Support
            Section("Support") {
                Link(destination: URL(string: "https://dc42studio.app/help")!) {
                    HStack {
                        Text("Documentation")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Link(destination: URL(string: "https://discord.gg/dc42studio")!) {
                    HStack {
                        Text("Discord Community")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .alert("Clear Recent Files?", isPresented: $showingClearDataAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearRecentFiles()
            }
        } message: {
            Text("This will remove all recently opened files from the app. The files themselves will not be deleted.")
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }
    
    private func clearRecentFiles() {
        UserDefaults.standard.removeObject(forKey: "DC42Studio.RecentImages")
    }
}

/// Storage View
struct StorageView: View {
    @State private var storageUsed: Int64 = 0
    @State private var cacheSize: Int64 = 0
    @State private var tempFilesSize: Int64 = 0
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Documents")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Cache")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Temporary Files")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: tempFilesSize, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Button("Clear Cache") {
                    clearCache()
                }
                
                Button("Clear Temporary Files") {
                    clearTempFiles()
                }
            }
        }
        .navigationTitle("Storage")
        .onAppear {
            calculateStorage()
        }
    }
    
    private func calculateStorage() {
        // Calculate storage usage
        let fileManager = FileManager.default
        
        // App documents
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            storageUsed = directorySize(url: documentsURL)
        }
        
        // Cache
        if let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheSize = directorySize(url: cacheURL)
        }
        
        // Temp
        tempFilesSize = directorySize(url: fileManager.temporaryDirectory)
    }
    
    private func directorySize(url: URL) -> Int64 {
        let fileManager = FileManager.default
        var size: Int64 = 0
        
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        
        return size
    }
    
    private func clearCache() {
        let fileManager = FileManager.default
        if let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? fileManager.removeItem(at: cacheURL)
            try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }
        calculateStorage()
    }
    
    private func clearTempFiles() {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("DC42Studio")
        try? fileManager.removeItem(at: tempDir)
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        calculateStorage()
    }
}

/// About View
struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // App Icon
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)
                        .padding(.top, 40)
                    
                    // App Name
                    VStack(spacing: 4) {
                        Text("DC42Studio")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Version 1.0.0")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Description
                    Text("A powerful tool for creating, converting, and browsing Classic Mac OS DC42 disk images. Works seamlessly across iPhone, iPad, and Mac.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 32)
                    
                    // Features
                    VStack(alignment: .leading, spacing: 12) {
                        FeatureRow(icon: "plus.circle.fill", text: "Create DC42 images from folders")
                        FeatureRow(icon: "arrow.triangle.2.circlepath", text: "Convert to ISO, DMG, and more")
                        FeatureRow(icon: "doc.text.magnifyingglass", text: "Browse contents without extraction")
                        FeatureRow(icon: "iphone.and.arrow.forward", text: "Universal app for all devices")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    
                    // Credits
                    VStack(spacing: 8) {
                        Text("Made with ❤️ for Classic Mac")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text("© 2025 DC42Studio")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 20)
                    
                    Spacer()
                }
            }
            .navigationTitle("About")
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

/// Feature Row
struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
