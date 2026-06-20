# DC42Studio - Specification Document

## 1. Project Overview

**Project Name:** DC42Studio  
**Bundle Identifier:** com.dc42studio.app  
**Core Functionality:** A cross-platform tool for creating, converting, browsing, and managing Classic Mac OS DC42 disk images  
**Target Users:** Classic Mac OS enthusiasts, retro computing collectors, developers working with legacy Mac software  
**Platform Support:** iOS 15+, iPadOS 15+, macOS 12+ (Monterey and later)

## 2. UI/UX Specification

### Screen Structure

#### Main Screens
1. **HomeView** - Dashboard with quick actions
2. **ImageListView** - Browse and manage DC42 files
3. **ImageDetailView** - View image metadata and contents
4. **CreateImageView** - Create new DC42 image
5. **ConvertImageView** - Convert DC42 to other formats
6. **BrowserView** - Browse image contents
7. **SettingsView** - App preferences

#### Navigation Structure
- **iOS/iPadOS:** TabView with NavigationStack per tab
- **macOS:** NavigationSplitView with sidebar

#### Screen Hierarchy
```
TabView (iOS/iPad) / NavigationSplitView (macOS)
├── Home
│   └── ImageDetail
│       └── Browser
├── Library
│   └── ImageDetail
├── Create
├── Settings
```

### Visual Design

#### Color Palette
- **Primary:** System Blue (#007AFF)
- **Secondary:** System Gray (#8E8E93)
- **Accent:** System Orange (#FF9500) - for highlights
- **Background:** System Background (adaptive)
- **Surface:** Secondary System Background
- **Success:** System Green (#34C759)
- **Warning:** System Yellow (#FFCC00)
- **Error:** System Red (#FF3B30)

#### Typography
- **Large Title:** SF Pro Display, 34pt Bold
- **Title:** SF Pro Display, 28pt Bold
- **Headline:** SF Pro Text, 17pt Semibold
- **Body:** SF Pro Text, 17pt Regular
- **Caption:** SF Pro Text, 12pt Regular
- **Monospace:** SF Mono, 14pt (for file sizes, hex data)

#### Spacing System (8pt Grid)
- **XS:** 4pt
- **S:** 8pt
- **M:** 16pt
- **L:** 24pt
- **XL:** 32pt
- **XXL:** 48pt

#### macOS-Specific Elements
- Toolbar with segmented control
- Menu bar integration
- Touch Bar support (MacBook Pro)
- Drag & drop between Finder and app

### Views & Components

#### Reusable Components
1. **ImageCard** - Thumbnail card for image list
2. **DropZone** - Drag & drop target area
3. **ProgressOverlay** - Task progress indicator
4. **MetadataRow** - Key-value display row
5. **FileTreeItem** - Hierarchical file browser item
6. **FormatBadge** - Image format indicator
7. **EmptyStateView** - No content placeholder

#### View States
- **Default:** Normal interactive state
- **Loading:** Progress indicator + dimmed content
- **Empty:** Illustration + call-to-action
- **Error:** Error message + retry button
- **Dragging:** Highlighted drop zone

#### Interactive Behaviors
- Long-press context menu (iOS)
- Right-click context menu (macOS)
- Swipe actions (iOS)
- Hover states (macOS)
- Pull-to-refresh (iOS)

## 3. Functionality Specification

### Core Features

#### F1: DC42 Image Creation (Priority: HIGH)
- Create from folder (preserving folder structure)
- Create from raw data
- Set volume name
- Select format (DC42, DC42 with comment)
- Progress indication
- Cancelable operation

#### F2: DC42 Image Conversion (Priority: HIGH)
- **Import formats:** DC42, ISO, IMG, DMG, folder
- **Export formats:** DC42, ISO, DMG, folder, raw IMG
- Batch conversion support
- Format auto-detection

#### F3: DC42 Image Browsing (Priority: HIGH)
- Display HFS filesystem contents
- File/folder navigation
- Extract individual files
- Extract all contents
- Search within image
- File type icons

#### F4: DC42 Image Validation (Priority: MEDIUM)
- Check image integrity
- Verify checksum (if present)
- Display format information
- Detect corruption

#### F5: Image Information (Priority: MEDIUM)
- Volume name
- Total capacity
- Used space
- Creation date
- Format version
- File count
- Fork information (data/resource)

#### F6: Favorites & History (Priority: LOW)
- Recently opened images
- Favorite images
- Open recent folder

### User Interactions & Flows

#### Create Image Flow
1. User taps "Create" tab
2. Select source (folder picker or drop zone)
3. Configure options (volume name, format)
4. Tap "Create"
5. Progress shown
6. Success → Open in detail view

#### Convert Image Flow
1. User drags DC42 file to drop zone OR selects file
2. Choose output format
3. Configure options
4. Tap "Convert"
5. Progress shown
6. Success → Save location

#### Browse Image Flow
1. Open image detail
2. Tap "Browse"
3. Navigate file tree
4. Tap file to preview OR extract
5. Long-press for context menu

### Data Handling
- **Local Storage:** UserDefaults for preferences, FileManager for recent files
- **Temporary Files:** Use app's temp directory for conversions
- **File Access:** Security-scoped bookmarks for persistent access

### Architecture Pattern
**MVVM (Model-View-ViewModel)**
- **Models:** DC42Image, HFSNode, ConversionJob
- **Views:** SwiftUI views
- **ViewModels:** ObservableObject classes

### Edge Cases & Error Handling
- Invalid/corrupted DC42 file → Show error, suggest repair
- Insufficient storage → Alert before operation
- Unsupported format → Clear error message
- Large file handling → Background processing
- App backgrounding → Continue operation
- File access denied → Request permission

## 4. Technical Specification

### Dependencies (Swift Package Manager)

#### Required
- None (using native frameworks only)

#### Optional (Future)
- SQLite.swift (for metadata database)
- ZIPFoundation (for archive operations)

### UI Framework
- **Primary:** SwiftUI
- **Fallback:** UIKit for specific components (file picker)

### Native Frameworks Used
- **Foundation:** Core functionality
- **SwiftUI:** UI framework
- **UniformTypeIdentifiers:** File type handling
- **CoreServices:** HFS support (macOS only)
- **FinderSync:** Finder integration (macOS)

### Asset Requirements

#### Icons
- App Icon (1024x1024 + all sizes)
- SF Symbols for UI icons
- Custom icons for file types

#### Colors
- Asset catalog with light/dark variants

### DC42 Format Specification

```
DC42 Header Structure:
├── Magic Number: "CD42" (4 bytes)
├── Version: UInt16 (typically 2)
├── Volume Name: 64 bytes (padded)
├── Image Size: UInt64
├── Media Size: UInt64
├── Format Flags: UInt32
├── Checksum: UInt32
├── Comment: 128 bytes (optional)
├── Data Fork Offset: UInt64
├── Resource Fork Offset: UInt64
├── Data Fork Size: UInt64
├── Resource Fork Size: UInt64
├── Creation Date: UInt32 (Mac format)
├── Modification Date: UInt32
└── Reserved: padding to 512 bytes
```

### Compatibility Matrix

| Feature | iOS 15 | iPadOS 15 | macOS 12 |
|---------|--------|-----------|----------|
| SwiftUI | ✅ | ✅ | ✅ |
| NavigationSplitView | ✅ | ✅ | ✅ |
| MenuBarExtra | ❌ | ❌ | ✅ |
| ShareSheet | ✅ | ✅ | ✅ |
| FileImporter | ✅ | ✅ | ✅ |
