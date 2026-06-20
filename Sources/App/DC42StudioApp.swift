import SwiftUI

@main
struct DC42StudioApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

/// Global App State
@MainActor
class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var isShowingImporter = false
    @Published var isShowingExporter = false
    
    public enum AppTab: String, CaseIterable {
        case home = "Home"
        case library = "Library"
        case create = "Create"
        case settings = "Settings"
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .library: return "folder.fill"
            case .create: return "plus.circle.fill"
            case .settings: return "gear"
            }
        }
    }
}
