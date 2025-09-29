import SwiftUI
import AppKit
import Combine

// MARK: - 应用模型
struct AppItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let icon: NSImage
    let path: String
    
    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - 文件夹模型
struct FolderItem: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var apps: [AppItem]
    let icon: NSImage
    
    static func == (lhs: FolderItem, rhs: FolderItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    init(name: String, apps: [AppItem]) {
        self.name = name
        self.apps = apps
        self.icon = Self.createFolderIcon(with: apps)
    }
    
    private static func createFolderIcon(with apps: [AppItem]) -> NSImage {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        let maxIcons = min(9, apps.count)
        
        // 外层文件夹矩形 (居中 80x80)
        let folderSize: CGFloat = 100
        let folderRect = NSRect(
            x: (size.width - folderSize) / 2,
            y: (size.height - folderSize) / 2,
            width: folderSize,
            height: folderSize
        )
        
        // 外框
        let folderPath = NSBezierPath(roundedRect: folderRect, xRadius: 20, yRadius: 20)
        NSColor.black.withAlphaComponent(0.3).setFill()
        folderPath.fill()
        
        NSColor.white.withAlphaComponent(0.2).setStroke()
        folderPath.lineWidth = 1
        folderPath.stroke()
        
        // 添加0.3透明度的白色覆盖层
        NSColor.white.withAlphaComponent(0.3).setFill()
        folderPath.fill()
        
        // 内部小图标参数（更接近系统）
        let iconsPerRow = 3
        let iconSize: CGFloat = 26   // 系统里更大
        let spacing: CGFloat = 2     // 系统里更紧凑
        let totalWidth = CGFloat(iconsPerRow) * iconSize + CGFloat(iconsPerRow - 1) * spacing // 64
        let totalHeight = totalWidth
        
        // 内部边距（80 - 72 = 8，左右上下各 4）
        let innerMargin: CGFloat = (folderSize - 72) / 2 // = 4
        let startX = folderRect.minX + innerMargin + (72 - totalWidth) / 2
        let startY = folderRect.minY + innerMargin + (72 - totalHeight) / 2
        
        // 绘制小图标预览（最多 9 个）
        for index in 0..<maxIcons {
            let row = index / iconsPerRow
            let col = index % iconsPerRow
            
            let x = startX + CGFloat(col) * (iconSize + spacing)
            let y = startY + CGFloat(row) * (iconSize + spacing)
            let iconRect = NSRect(x: x, y: y, width: iconSize, height: iconSize)
            
            let appIcon = apps[index].icon
            appIcon.draw(
                in: iconRect,
                from: NSRect(origin: .zero, size: appIcon.size),
                operation: .sourceOver,
                fraction: 1.0
            )
        }
        
        image.unlockFocus()
        return image
    }
}

// MARK: - 网格项目类型
enum LaunchpadItem: Identifiable, Equatable {
    case app(AppItem)
    case folder(FolderItem)
    case empty(String) // 用于占位的空项目
    
    var id: UUID {
        switch self {
        case .app(let app):
            return app.id
        case .folder(let folder):
            return folder.id
        case .empty(let stringId):
            return UUID(uuidString: stringId) ?? UUID()
        }
    }
    
    var name: String {
        switch self {
        case .app(let app):
            return app.name
        case .folder(let folder):
            return folder.name
        case .empty:
            return ""
        }
    }
    
    var icon: NSImage {
        switch self {
        case .app(let app):
            return app.icon
        case .folder(let folder):
            return folder.icon
        case .empty:
            return NSImage(systemSymbolName: "square", accessibilityDescription: "Empty slot") ?? NSImage()
        }
    }
    
    static func == (lhs: LaunchpadItem, rhs: LaunchpadItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - 图标缓存
class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    
    private init() {}
    
    func getIcon(for path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        let size = NSSize(width: 128, height: 128)
        let resized = NSImage(size: size)
        resized.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: icon.size),
                  operation: .sourceOver, fraction: 1.0)
        resized.unlockFocus()
        cache[path] = resized
        return resized
    }
}

// 递归扫描目录
private func scanDirectoryRecursively(path: String, apps: inout [AppItem]) {
    let fm = FileManager.default
    
    guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return }
    
    for item in contents {
        let fullPath = (path as NSString).appendingPathComponent(item)
        var isDirectory: ObjCBool = false
        
        if fm.fileExists(atPath: fullPath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                if item.hasSuffix(".app") {
                    // 这是一个应用包
                    let icon = IconCache.shared.getIcon(for: fullPath)
                    apps.append(AppItem(name: (item as NSString).deletingPathExtension,
                                        icon: icon, path: fullPath))
                } else {
                    // 这是一个普通文件夹，递归扫描
                    scanDirectoryRecursively(path: fullPath, apps: &apps)
                }
            }
        }
    }
}

// MARK: - 网格图标视图
struct GridIconView: View {
    let item: LaunchpadItem
    let currentPage: Int
    @State private var isHovered = false
    @EnvironmentObject var dragManager: GlobalDragManager
    @Environment(\.launchpadPageFrame) private var pageFrame
    private let dropCalc = DropIndexCalculator()
    
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 108, height: 108)
                .cornerRadius(16)
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .opacity(dragManager.draggingItem?.id == item.id ? 0.3 : 1.0)
            
            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onDrag {
            // Provide a stable item provider for system drag. Use app path for apps and folder name for folders.
            switch item {
            case .app(let app):
                return NSItemProvider(object: app.path as NSString)
            case .folder(let folder):
                return NSItemProvider(object: folder.name as NSString)
            case .empty:
                // Disable meaningful drag for empty slots; still return a benign provider to satisfy API.
                return NSItemProvider(object: "" as NSString)
            }
        } preview: {
            // Custom drag preview that matches our in-app style
            VStack(spacing: 4) {
                Image(nsImage: item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

                if !item.name.isEmpty {
                    Text(item.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
                }
            }
            .padding(6)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if dragManager.draggingItem == nil {
                        // 使用全局坐标记录起始拖拽
                        let globalLocation = CGPoint(
                            x: value.startLocation.x + value.translation.width,
                            y: value.startLocation.y + value.translation.height
                        )
                        dragManager.startDragging(item, at: globalLocation)
                    } else {
                        // 使用全局坐标更新拖拽位置
                        let globalLocation = CGPoint(
                            x: value.startLocation.x + value.translation.width,
                            y: value.startLocation.y + value.translation.height
                        )
                        dragManager.updateDragPosition(globalLocation)
                    }
                }
                .onEnded { value in
                    if dragManager.draggingItem?.id == item.id {
                        // 使用最终位置 - 全局坐标
                        let finalPosition = CGPoint(
                            x: value.startLocation.x + value.translation.width,
                            y: value.startLocation.y + value.translation.height
                        )
                        
                        // 检查是否创建文件夹
                        if let hoveredItem = dragManager.hoveredItem,
                           case .app = hoveredItem,
                           hoveredItem.id != item.id {
                            dragManager.folderCreationTarget = hoveredItem
                        } else {
                            // 使用真实几何计算 index（不再用硬编码 1920 等）
                            let dropIndex = dropCalc.index(for: finalPosition, in: pageFrame, currentPage: currentPage)
                            dragManager.setPendingDropIndex(dropIndex)
                        }
                        
                        dragManager.endDragging()
                    }
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    switch item {
                    case .app(let app):
                        AppDelegate.shared?.hideWindow()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
                        }
                    case .folder(let folder):
                        dragManager.expandFolder(folder)
                    case .empty:
                        break // 空项目不处理点击
                    }
                }
        )
        .onHover { hovering in
            isHovered = hovering
            // 如果正在拖拽且悬停在此项目上，设置悬停状态
            if hovering && dragManager.draggingItem != nil && dragManager.draggingItem?.id != item.id {
                dragManager.setHoveredItem(item)
                print("🎯 悬停在: \(item.name)")
            } else if !hovering && dragManager.hoveredItem?.id == item.id {
                dragManager.setHoveredItem(nil)
            }
        }
        .allowsHitTesting(true)
        .scaleEffect(dragManager.hoveredItem?.id == item.id && dragManager.isCreatingFolder ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: dragManager.hoveredItem?.id == item.id)
    }
    
}

// MARK: - 图标按钮（保留兼容性）
struct AppIconButton: View {
    let app: AppItem
    @State private var isHovered = false
    @EnvironmentObject var dragManager: GlobalDragManager
    
    var body: some View {
        GridIconView(item: .app(app), currentPage: 0)
            .environmentObject(dragManager)
    }
}

