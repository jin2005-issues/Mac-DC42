import SwiftUI

/// Main Content View - Adaptive for iOS/macOS
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var mainViewModel = MainViewModel()
    @StateObject private var createViewModel = CreateViewModel()
    @StateObject private var convertViewModel = ConvertViewModel()
    @StateObject private var browserViewModel = BrowserViewModel()
    
    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }
    
    // MARK: - iOS Layout (TabView)
    
    #if os(iOS)
    var iOSLayout: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .environmentObject(mainViewModel)
                .environmentObject(browserViewModel)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppState.AppTab.home)
            
            LibraryView()
                .environmentObject(mainViewModel)
                .environmentObject(convertViewModel)
                .tabItem {
                    Label("Library", systemImage: "folder.fill")
                }
                .tag(AppState.AppTab.library)
            
            CreateView()
                .environmentObject(createViewModel)
                .environmentObject(convertViewModel)
                .tabItem {
                    Label("Create", systemImage: "plus.circle.fill")
                }
                .tag(AppState.AppTab.create)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppState.AppTab.settings)
        }
    }
    #endif
    
    // MARK: - macOS Layout (NavigationSplitView)
    
    #if os(macOS)
    var macOSLayout: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $appState.selectedTab) {
                Section("Navigation") {
                    Label("Home", systemImage: "house.fill")
                        .tag(AppState.AppTab.home)
                    Label("Library", systemImage: "folder.fill")
                        .tag(AppState.AppTab.library)
                    Label("Create", systemImage: "plus.circle.fill")
                        .tag(AppState.AppTab.create)
                }
                
                Section("Tools") {
                    NavigationLink {
                        ConvertView()
                            .environmentObject(convertViewModel)
                    } label: {
                        Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    NavigationLink {
                        BrowserView()
                            .environmentObject(browserViewModel)
                    } label: {
                        Label("Browse", systemImage: "doc.text.magnifyingglass")
                    }
                }
                
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .listStyle(.sidebar)
        } detail: {
            // Detail View
            switch appState.selectedTab {
            case .home:
                HomeView()
                    .environmentObject(mainViewModel)
                    .environmentObject(browserViewModel)
            case .library:
                LibraryView()
                    .environmentObject(mainViewModel)
                    .environmentObject(convertViewModel)
            case .create:
                CreateView()
                    .environmentObject(createViewModel)
                    .environmentObject(convertViewModel)
            case .settings:
                SettingsView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
    #endif
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
