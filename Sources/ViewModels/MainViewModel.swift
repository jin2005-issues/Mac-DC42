import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Main View Model for DC42 Studio
@MainActor
public class MainViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var images: [DC42Image] = []
    @Published public var selectedImage: DC42Image?
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var searchText = ""
    @Published public var sortOrder: SortOrder = .dateDescending
    
    // MARK: - Computed Properties
    
    public var filteredImages: [DC42Image] {
        var result = images
        
        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { image in
                image.volumeName.localizedCaseInsensitiveContains(searchText) ||
                image.fileURL.lastPathComponent.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply sort
        switch sortOrder {
        case .nameAscending:
            result.sort { $0.volumeName < $1.volumeName }
        case .nameDescending:
            result.sort { $0.volumeName > $1.volumeName }
        case .dateAscending:
            result.sort { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
        case .dateDescending:
            result.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        case .sizeAscending:
            result.sort { $0.totalSize < $1.totalSize }
        case .sizeDescending:
            result.sort { $0.totalSize > $1.totalSize }
        }
        
        return result
    }
    
    // MARK: - Sort Order
    
    public enum SortOrder: String, CaseIterable, Identifiable {
        case nameAscending = "Name (A-Z)"
        case nameDescending = "Name (Z-A)"
        case dateAscending = "Date (Oldest)"
        case dateDescending = "Date (Newest)"
        case sizeAscending = "Size (Smallest)"
        case sizeDescending = "Size (Largest)"
        
        public var id: String { rawValue }
    }
    
    // MARK: - Initialization
    
    public init() {
        loadRecentImages()
    }
    
    // MARK: - Image Management
    
    public func importImage(from url: URL) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                throw DC42Error.readFailed
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Validate and create image model
            let image = try DC42Service.shared.validate(url: url)
            
            // Add to list
            images.insert(image, at: 0)
            
            // Save to recents
            saveRecentImage(image)
            
            // Update selected
            selectedImage = image
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    public func removeImage(_ image: DC42Image) {
        images.removeAll { $0.id == image.id }
        if selectedImage?.id == image.id {
            selectedImage = nil
        }
        removeFromRecents(image)
    }
    
    public func refreshImage(_ image: DC42Image) async {
        guard let index = images.firstIndex(where: { $0.id == image.id }) else { return }
        
        do {
            let updated = try DC42Service.shared.validate(url: image.fileURL)
            images[index] = updated
            if selectedImage?.id == image.id {
                selectedImage = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Recent Images
    
    private let recentsKey = "DC42Studio.RecentImages"
    
    private func loadRecentImages() {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let urls = try? JSONDecoder().decode([URL].self, from: data) else {
            return
        }
        
        Task {
            for url in urls.prefix(10) {
                await importImage(from: url)
            }
        }
    }
    
    private func saveRecentImage(_ image: DC42Image) {
        var urls = getRecentURLs()
        urls.removeAll { $0 == image.fileURL }
        urls.insert(image.fileURL, at: 0)
        urls = Array(urls.prefix(20))
        
        if let data = try? JSONEncoder().encode(urls) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }
    
    private func removeFromRecents(_ image: DC42Image) {
        var urls = getRecentURLs()
        urls.removeAll { $0 == image.fileURL }
        if let data = try? JSONEncoder().encode(urls) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }
    
    private func getRecentURLs() -> [URL] {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let urls = try? JSONDecoder().decode([URL].self, from: data) else {
            return []
        }
        return urls
    }
    
    public func clearRecents() {
        UserDefaults.standard.removeObject(forKey: recentsKey)
        images.removeAll()
        selectedImage = nil
    }
}
