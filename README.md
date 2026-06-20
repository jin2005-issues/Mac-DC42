# DC42Studio

A powerful cross-platform tool for creating, converting, and browsing Classic Mac OS DC42 disk images.

![Platform](https://img.shields.io/badge/Platform-iOS%2015+-blue)
![Platform](https://img.shields.io/badge/Platform-iPadOS%2015+-blue)
![Platform](https://img.shields.io/badge/Platform-macOS%2012+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

### 🎨 Create DC42 Images
- Create DC42 disk images from folders
- Set volume names and comments
- Support for both data and resource forks

### 🔄 Convert Formats
- Import: DC42, ISO, DMG, IMG
- Export: DC42, ISO, DMG, IMG, Folder
- Batch conversion support

### 📁 Browse Contents
- View HFS filesystem contents without extraction
- Navigate folder structures
- Extract individual files or entire volumes
- Search within images

### 📱 Universal App
- iPhone, iPad, and Mac support
- Native SwiftUI interface
- Drag and drop support
- Dark mode ready

## Requirements

- iOS 15.0+
- iPadOS 15.0+
- macOS 12.0+
- Xcode 15.0+

## Installation

### From Source

1. Clone the repository
2. Open `project.yml` in Xcode (or run `xcodegen generate`)
3. Select your target device
4. Build and run

### Using XcodeGen

```bash
cd DC42Studio
xcodegen generate
open DC42Studio.xcodeproj
```

## DC42 Format

DC42 (DiskCopy 4.2) is a disk image format used by Classic Mac OS. It contains:

- **Header (512 bytes)**: Volume info, format flags, checksum
- **Data Fork**: File data
- **Resource Fork**: Mac OS resources (icons, fonts, etc.)

### Header Structure

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | Magic ("CD42") |
| 4 | 2 | Version |
| 6 | 64 | Volume Name |
| 70 | 8 | Image Size |
| 78 | 8 | Media Size |
| 86 | 4 | Format Flags |
| 90 | 4 | Checksum |
| 94 | 128 | Comment |
| 222 | 8 | Data Fork Offset |
| 230 | 8 | Resource Fork Offset |

## Architecture

```
DC42Studio/
├── Sources/
│   ├── App/           # App entry point
│   ├── Models/        # Data models (DC42Image, HFSNode)
│   ├── Services/      # DC42Service, HFSService
│   ├── ViewModels/    # MVVM ViewModels
│   └── Views/         # SwiftUI Views
├── Resources/         # Assets, Info.plist
└── project.yml        # XcodeGen configuration
```

## Usage

### Creating an Image

1. Open DC42Studio
2. Go to the "Create" tab
3. Drop a folder or click to browse
4. Set volume name and options
5. Tap "Create"

### Converting an Image

1. Open DC42Studio
2. Drag a DC42 file to the converter
3. Select output format
4. Tap "Convert"

### Browsing Contents

1. Open a DC42 image
2. Tap "Browse" to view contents
3. Navigate folders
4. Tap a file to preview
5. Long-press to select and extract

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Classic Mac OS community
- Apple Developer Documentation
- SF Symbols for icons

## Contact

- Website: https://dc42studio.app
- GitHub: https://github.com/dc42studio
- Discord: https://discord.gg/dc42studio
