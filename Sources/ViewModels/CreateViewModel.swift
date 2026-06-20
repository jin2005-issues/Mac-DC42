import Foundation
import SwiftUI

/// View Model for Creating DC42 Images
@MainActor
public class CreateViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var sourceURL: URL?
    @Published public var volumeName: String = "Untitled"
    @Published public var comment: String = ""
    @Published public var formatType: DC42FormatType = .standard
    @Published public var includeResourceFork = false
    
    @Published public var isCreating = false
    @Published public var creationProgress: Double = 0
    @Published public var createdImage: DC42Image?
    @Published public var errorMessage: String?
    
    // MARK: - Computed Properties
    
    public var canCreate: Bool {
        sourceURL != nil && !volumeName.isEmpty && !isCreating
    }
    
    public var sourceName: String {
        sourceURL?.lastPathComponent ?? "No source selected"
    }
    
    public var hasSource: Bool {
        sourceURL != nil
    }
    
    // MARK: - Creation
    
    public func createImage() async {
        guard let sourceURL = sourceURL else {
            errorMessage = "No source selected"
            return
        }
        
        isCreating = true
        creationProgress = 0
        errorMessage = nil
        
        do {
            // Create DC42 from folder
            let outputURL = try DC42Service.shared.createFromFolder(
                sourceURL: sourceURL,
                volumeName: volumeName
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.creationProgress = progress
                }
            }
            
            // Validate the created image
            createdImage = try DC42Service.shared.validate(url: outputURL)
            creationProgress = 1.0
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isCreating = false
    }
    
    public func reset() {
        sourceURL = nil
        volumeName = "Untitled"
        comment = ""
        formatType = .standard
        includeResourceFork = false
        isCreating = false
        creationProgress = 0
        createdImage = nil
        errorMessage = nil
    }
}

/// View Model for Converting DC42 Images
@MainActor
public class ConvertViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var sourceURL: URL?
    @Published public var sourceImage: DC42Image?
    @Published public var outputFormat: ConversionFormat = .iso
    @Published public var outputURL: URL?
    
    @Published public var isConverting = false
    @Published public var conversionProgress: Double = 0
    @Published public var completedJob: ConversionJob?
    @Published public var errorMessage: String?
    
    // MARK: - Computed Properties
    
    public var canConvert: Bool {
        sourceURL != nil && !isConverting
    }
    
    public var sourceName: String {
        sourceURL?.lastPathComponent ?? "No source selected"
    }
    
    public var sourceInfo: String {
        guard let image = sourceImage else { return "" }
        return "\(image.volumeName) • \(ByteCountFormatter.string(fromByteCount: Int64(image.totalSize), countStyle: .file))"
    }
    
    public var outputFileName: String {
        guard let sourceURL = sourceURL else { return "" }
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        return "\(baseName).\(outputFormat.fileExtension)"
    }
    
    // MARK: - Conversion
    
    public func loadSource(from url: URL) async {
        sourceURL = url
        
        do {
            sourceImage = try DC42Service.shared.validate(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func convert() async {
        guard let sourceURL = sourceURL else {
            errorMessage = "No source selected"
            return
        }
        
        isConverting = true
        conversionProgress = 0
        errorMessage = nil
        
        var job = ConversionJob(sourceFile: sourceURL, outputFormat: outputFormat)
        
        do {
            let url = try DC42Service.shared.convert(
                sourceURL: sourceURL,
                to: outputFormat
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.conversionProgress = progress
                }
            }
            
            outputURL = url
            job.outputURL = url
            job.status = .completed
            job.endTime = Date()
            completedJob = job
            
        } catch {
            errorMessage = error.localizedDescription
            job.status = .failed(error.localizedDescription)
            job.endTime = Date()
            job.errorMessage = error.localizedDescription
            completedJob = job
        }
        
        isConverting = false
    }
    
    public func reset() {
        sourceURL = nil
        sourceImage = nil
        outputFormat = .iso
        outputURL = nil
        isConverting = false
        conversionProgress = 0
        completedJob = nil
        errorMessage = nil
    }
}

/// View Model for Browsing DC42 Images
@MainActor
public class BrowserViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var imageURL: URL?
    @Published public var volumeInfo: HFSVolumeInfo?
    @Published public var rootNode: HFSNode?
    @Published public var currentNode: HFSNode?
    @Published public var navigationPath: [HFSNode] = []
    @Published public var selectedNodes: Set<UUID> = []
    
    @Published public var searchText = ""
    @Published public var searchResults: [HFSNode] = []
    
    @Published public var isLoading = false
    @Published public var isExtracting = false
    @Published public var extractionProgress: Double = 0
    @Published public var errorMessage: String?
    
    // MARK: - Computed Properties
    
    public var currentContents: [HFSNode] {
        if !searchText.isEmpty {
            return searchResults
        }
        return currentNode?.children ?? []
    }
    
    public var breadcrumbs: [HFSNode] {
        navigationPath + (currentNode.map { [$0] } ?? [])
    }
    
    public var canNavigateUp: Bool {
        !navigationPath.isEmpty
    }
    
    // MARK: - Loading
    
    public func loadImage(from url: URL) async {
        imageURL = url
        isLoading = true
        errorMessage = nil
        
        do {
            // Get volume info
            volumeInfo = try HFSService.shared.parseVolume(url: url)
            
            // Get file tree
            rootNode = try HFSService.shared.parseFileTree(url: url)
            currentNode = rootNode
            navigationPath = []
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Navigation
    
    public func navigateTo(_ node: HFSNode) {
        if node.isDirectory {
            navigationPath.append(currentNode ?? rootNode!)
            currentNode = node
            selectedNodes.removeAll()
        }
    }
    
    public func navigateUp() {
        guard let previous = navigationPath.popLast() else { return }
        currentNode = previous
        selectedNodes.removeAll()
    }
    
    public func navigateToRoot() {
        navigationPath.removeAll()
        currentNode = rootNode
        selectedNodes.removeAll()
    }
    
    public func navigateToBreadcrumb(at index: Int) {
        if index < 0 {
            navigateToRoot()
        } else if index < navigationPath.count {
            currentNode = navigationPath[index]
            navigationPath = Array(navigationPath.prefix(index))
            selectedNodes.removeAll()
        }
    }
    
    // MARK: - Selection
    
    public func toggleSelection(_ node: HFSNode) {
        if selectedNodes.contains(node.id) {
            selectedNodes.remove(node.id)
        } else {
            selectedNodes.insert(node.id)
        }
    }
    
    public func selectAll() {
        selectedNodes = Set(currentContents.map { $0.id })
    }
    
    public func deselectAll() {
        selectedNodes.removeAll()
    }
    
    public func selectedNodesArray() -> [HFSNode] {
        currentContents.filter { selectedNodes.contains($0.id) }
    }
    
    // MARK: - Search
    
    public func search() async {
        guard let imageURL = imageURL, !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        do {
            searchResults = try HFSService.shared.search(in: imageURL, pattern: searchText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Extraction
    
    public func extractSelected(to destination: URL) async {
        guard let imageURL = imageURL else { return }
        
        isExtracting = true
        extractionProgress = 0
        errorMessage = nil
        
        do {
            if selectedNodes.isEmpty {
                // Extract all
                try HFSService.shared.extractAll(from: imageURL, to: destination) { [weak self] progress in
                    Task { @MainActor in
                        self?.extractionProgress = progress
                    }
                }
            } else {
                // Extract selected
                let nodes = selectedNodesArray()
                for (index, node) in nodes.enumerated() {
                    let destPath = destination.appendingPathComponent(node.name)
                    try HFSService.shared.extractFile(from: imageURL, node: node, to: destPath) { p in
                        // Individual file progress
                    }
                    extractionProgress = Double(index + 1) / Double(nodes.count)
                }
            }
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isExtracting = false
    }
    
    public func reset() {
        imageURL = nil
        volumeInfo = nil
        rootNode = nil
        currentNode = nil
        navigationPath = []
        selectedNodes = []
        searchText = ""
        searchResults = []
        isLoading = false
        isExtracting = false
        extractionProgress = 0
        errorMessage = nil
    }
}
