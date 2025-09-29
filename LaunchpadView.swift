import SwiftUI
import AppKit

// 环境Key用于传递当前页面的frame信息
struct LaunchpadPageFrameKey: EnvironmentKey {
    static let defaultValue: CGRect = .zero
}

extension EnvironmentValues {
    var launchpadPageFrame: CGRect {
        get { self[LaunchpadPageFrameKey.self] }
        set { self[LaunchpadPageFrameKey.self] = newValue }
    }
}

// 布局参数（与PagedGridView保持一致）
struct LaunchpadLayout {
    let columns: Int = 7
    let rows: Int = 5
    let hSpacing: CGFloat = 20      // GridItem(.flexible(), spacing: 20)
    let vSpacing: CGFloat = 35      // LazyVGrid spacing
    let iconSize: CGFloat = 108     // GridIconView 里的 .frame(width:108,height:108)
    let labelHeight: CGFloat = 20   // 小字一行，大致高度
    let hPadding: CGFloat = 200     // .padding(.horizontal, 200)
    let vPadding: CGFloat = 20      // .padding(.vertical, 20)
    
    var cellHeight: CGFloat { iconSize + vSpacing + labelHeight } // 近似
}

// 拖拽索引计算器
struct DropIndexCalculator {
    let layout = LaunchpadLayout()
    
    func index(for globalPoint: CGPoint, in pageFrame: CGRect, currentPage: Int) -> Int {
        // 1) 统一到"当前页"的本地坐标
        let local = CGPoint(x: globalPoint.x - pageFrame.minX,
                            y: globalPoint.y - pageFrame.minY)
        
        // 2) 去掉 padding
        let p = layout
        let gridX = local.x - p.hPadding
        let gridY = local.y - p.vPadding
        
        // 3) 真实可用宽度（按当前页 frame）
        let availableWidth = pageFrame.width - p.hPadding * 2
        let cellWidth = availableWidth / CGFloat(p.columns)   // 与 .flexible() 对齐的等分
        
        // 4) 映射到网格坐标
        let cellX = Int(gridX / cellWidth)
        let cellY = Int(gridY / p.cellHeight)
        
        // 5) clamp 到有效范围
        let clampedX = max(0, min(cellX, p.columns - 1))
        let clampedY = max(0, min(cellY, p.rows - 1))
        
        // 6) 页内 → 全局索引
        let pageIndex = clampedY * p.columns + clampedX
        return currentPage * (p.columns * p.rows) + pageIndex
    }
}
import Foundation
import Combine

// MARK: - 系统配置加载
func loadSystemLaunchpadConfig() -> [LaunchpadItem] {
    // 尝试读取系统Launchpad配置
    let dockPlistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.dock.plist"
    
    if let dockData = NSData(contentsOfFile: dockPlistPath),
       let dockPlist = try? PropertyListSerialization.propertyList(from: dockData as Data, options: [], format: nil) as? [String: Any],
       let persistentApps = dockPlist["persistent-apps"] as? [[String: Any]] {
        
        print("📱 找到系统Launchpad配置，包含 \(persistentApps.count) 个应用")
        
        var systemApps: [LaunchpadItem] = []
        
        for appData in persistentApps {
            if let tileData = appData["tile-data"] as? [String: Any],
               let fileLabel = tileData["file-label"] as? String,
               let fileData = tileData["file-data"] as? [String: Any],
               let filePath = fileData["_CFURLString"] as? String {
                
                // 解析文件路径
                let cleanPath = filePath.replacingOccurrences(of: "file://", with: "")
                let decodedPath = cleanPath.removingPercentEncoding ?? cleanPath
                
                if FileManager.default.fileExists(atPath: decodedPath) {
                    let icon = IconCache.shared.getIcon(for: decodedPath)
                    let app = AppItem(name: fileLabel, icon: icon, path: decodedPath)
                    systemApps.append(.app(app))
                    print("✅ 加载系统应用: \(fileLabel)")
                }
            }
        }
        
        if !systemApps.isEmpty {
            print("🎯 成功加载 \(systemApps.count) 个系统Launchpad应用")
            return systemApps
        }
    }
    
    print("⚠️ 未找到系统Launchpad配置，使用默认扫描")
    return loadApplications()
}

func loadApplications() -> [LaunchpadItem] {
    var apps: [AppItem] = []
    
    // 扫描路径列表（包括子文件夹）
    let appPaths = [
        "/Applications",
        "/System/Applications", 
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
        "/System/Library/CoreServices",
        "/System/Library/PreferencePanes"
    ]
    
    // 递归扫描所有应用
    for path in appPaths {
        scanDirectoryRecursively(path: path, apps: &apps)
    }
    
    // 去重并排序
    let uniqueApps = Dictionary(grouping: apps, by: { $0.name })
        .compactMapValues { $0.first }
        .values
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    
    // 第一页固定应用列表（按指定顺序）
    let firstPageApps = [
        "App Store", "Safari", "Mail", "Contacts", "Calendar", "Reminders", "Notes",
        "FaceTime", "Messages", "Maps", "FindMy", "Photo Booth", "Photos", "Music",
        "Podcasts", "TV", "VoiceMemos", "Weather", "Stocks", "Books", "Clock",
        "Calculator", "Freeform", "Home", "Siri", "iPhone Mirroring", "Passwords", "System Settings"
    ]
    
    // 分离第一页应用和其他应用
    var firstPage: [AppItem] = []
    var otherApps: [AppItem] = []
    
    for app in uniqueApps {
        if firstPageApps.contains(app.name) {
            firstPage.append(app)
        } else {
            otherApps.append(app)
        }
    }
    
    // 第一页按固定顺序排列，其他应用按A-Z排序
    let sortedFirstPage = firstPageApps.compactMap { appName in
        firstPage.first { $0.name == appName }
    }
    
    let sortedOtherApps = otherApps.sorted { $0.name < $1.name }
    
    let allApps = sortedFirstPage + sortedOtherApps
    
    // 创建默认工具文件夹（只创建一个）
    let toolsFolderApps = createToolsFolderApps(from: allApps)
    
    // 从主列表中移除已放入文件夹的应用
    let remainingApps = allApps.filter { app in
        !toolsFolderApps.contains { $0.name == app.name }
    }
    
    // 创建工具文件夹
    let toolsFolder = FolderItem(name: "Tools", apps: toolsFolderApps)
    
    // 调试信息
    print("🔧 工具文件夹创建:")
    print("   - 文件夹名称: \(toolsFolder.name)")
    print("   - 包含应用数量: \(toolsFolderApps.count)")
    print("   - 应用列表: \(toolsFolderApps.map { $0.name })")
    
    // 返回结果：主应用列表 + 工具文件夹
    let result: [LaunchpadItem] = remainingApps.map { .app($0) } + [.folder(toolsFolder)]
    
    print("📱 加载完成: \(remainingApps.count) 个主应用 + 1个工具文件夹(\(toolsFolderApps.count)个应用)")
    return result
}

// 递归扫描目录
private func scanDirectoryRecursively(path: String, apps: inout [AppItem]) {
    let fm = FileManager.default
    
    guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return }
    
    for item in contents {
        let fullPath = "\(path)/\(item)"
        var isDirectory: ObjCBool = false
        
        if fm.fileExists(atPath: fullPath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                if item.hasSuffix(".app") {
                    // 这是一个应用包
                    let appName = item.replacingOccurrences(of: ".app", with: "")
                    let icon = IconCache.shared.getIcon(for: fullPath)
                    let app = AppItem(name: appName, icon: icon, path: fullPath)
                    apps.append(app)
                    print("📱 发现应用: \(appName) at \(fullPath)")
                } else {
                    // 这是一个文件夹，递归扫描
                    scanDirectoryRecursively(path: fullPath, apps: &apps)
                }
            }
        }
    }
}

// 创建工具文件夹应用列表
func createToolsFolderApps(from allApps: [AppItem]) -> [AppItem] {
    // 工具文件夹中的应用列表（按实际应用名称）
    let toolsAppNames = [
        "Shortcuts", "QuickTime Player", "Dictionary", "TextEdit", "Font Book",
        "Screen Sharing", "Mission Control", "Time Machine", "Preview", "Screenshot",
        "Image Capture", "Digital Color Meter", "ColorSync Utility", "Stickies",
        "Grapher", "VoiceOver Utility", "Print Center", "Automator", "Script Editor",
        "Audio MIDI Setup", "Bluetooth File Exchange", "Disk Utility", "System Information",
        "Activity Monitor", "Console", "Terminal", "AirPort Utility", "Migration Assistant", "Tips"
    ]
    
    // 从所有应用中筛选出工具应用
    let toolsApps = toolsAppNames.compactMap { appName in
        allApps.first { $0.name == appName }
    }
    
    return toolsApps
}

// MARK: - 数据管理器
class LaunchpadDataManager: ObservableObject {
    @Published var apps: [LaunchpadItem] = []
    private let saveURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("LaunchpadData.json")
    
    init() {
        loadData()
    }
    
    func loadData() {
        // 强制加载系统配置，忽略保存的数据
        apps = loadSystemLaunchpadConfig()
        print("📱 强制加载系统配置: \(apps.count) 个项目")
    }
    
    func saveData() {
        guard let url = saveURL else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            // 将LaunchpadItem转换为可编码的结构
            let codableApps = apps.map { item in
                CodableLaunchpadItem.from(item)
            }
            
            let data = try encoder.encode(codableApps)
            try data.write(to: url)
            print("💾 数据已保存到: \(url.path)")
        } catch {
            print("❌ 保存数据失败: \(error)")
        }
    }
    
    private func loadSavedData() -> [LaunchpadItem]? {
        guard let url = saveURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let codableApps = try decoder.decode([CodableLaunchpadItem].self, from: data)
            
            return codableApps.compactMap { $0.toLaunchpadItem() }
        } catch {
            print("❌ 加载保存数据失败: \(error)")
            return nil
        }
    }
    
    func updateFolderName(_ folderId: UUID, newName: String) {
        for i in 0..<apps.count {
            if case .folder(var folder) = apps[i], folder.id == folderId {
                folder.name = newName
                apps[i] = .folder(folder)
                saveData()
                print("📝 文件夹重命名成功: \(newName)")
                break
            }
        }
    }
    
    func reorderApps(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex < apps.count,
              destinationIndex <= apps.count else { return }
        
        let item = apps.remove(at: sourceIndex)
        let insertIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        apps.insert(item, at: insertIndex)
        saveData()
        print("🔄 应用重排成功: \(sourceIndex) -> \(insertIndex)")
    }
    
    func createFolder(from draggingItem: LaunchpadItem, to targetItem: LaunchpadItem) {
        guard case .app(let draggingApp) = draggingItem,
              case .app(let targetApp) = targetItem else { return }
        
        // 确保不是拖拽到自身
        guard draggingApp.id != targetApp.id else { return }
        
        // 先找到目标应用的原始位置
        guard let originalTargetIndex = apps.firstIndex(where: { $0.id == targetItem.id }) else { return }
        
        // 移除被拖拽的应用和目标应用
        apps.removeAll { $0.id == draggingApp.id || $0.id == targetApp.id }
        
        // 创建新文件夹
        let newFolder = FolderItem(name: "新建文件夹", apps: [draggingApp, targetApp])
        
        // 插入新文件夹到目标应用原来的位置
        let insertIndex = originalTargetIndex >= apps.count ? apps.count : originalTargetIndex
        apps.insert(.folder(newFolder), at: insertIndex)
        
        saveData()
        print("📁 创建文件夹成功: \(newFolder.name)")
    }
}

// MARK: - 可编码的数据结构
struct CodableAppItem: Codable {
    let id: UUID
    let name: String
    let path: String
}

struct CodableFolderItem: Codable {
    let id: UUID
    var name: String
    let apps: [CodableAppItem]
}

enum CodableLaunchpadItem: Codable {
    case app(CodableAppItem)
    case folder(CodableFolderItem)
    case empty(String)
    
    static func from(_ item: LaunchpadItem) -> CodableLaunchpadItem {
        switch item {
        case .app(let app):
            return .app(CodableAppItem(id: app.id, name: app.name, path: app.path))
        case .folder(let folder):
            let codableApps = folder.apps.map { CodableAppItem(id: $0.id, name: $0.name, path: $0.path) }
            return .folder(CodableFolderItem(id: folder.id, name: folder.name, apps: codableApps))
        case .empty(let stringId):
            return .empty(stringId)
        }
    }
    
    func toLaunchpadItem() -> LaunchpadItem? {
        switch self {
        case .app(let codableApp):
            let icon = IconCache.shared.getIcon(for: codableApp.path)
            let app = AppItem(name: codableApp.name, icon: icon, path: codableApp.path)
            return .app(app)
        case .folder(let codableFolder):
            let apps = codableFolder.apps.compactMap { codableApp in
                let icon = IconCache.shared.getIcon(for: codableApp.path)
                return AppItem(name: codableApp.name, icon: icon, path: codableApp.path)
            }
            let folder = FolderItem(name: codableFolder.name, apps: apps)
            return .folder(folder)
        case .empty(let stringId):
            return .empty(stringId)
        }
    }
}
class GlobalDragManager: ObservableObject {
    @Published var draggingItem: LaunchpadItem? = nil
    @Published var dragPreviewPosition: CGPoint = .zero
    @Published var dragPreviewScale: CGFloat = 1.2
    @Published var pendingDropIndex: Int? = nil
    @Published var isCreatingFolder = false
    @Published var expandedFolder: FolderItem? = nil
    @Published var hoveredItem: LaunchpadItem? = nil
    @Published var folderCreationTarget: LaunchpadItem? = nil
    @Published var lastDraggedItem: LaunchpadItem? = nil
    @Published var dragVelocity: CGSize = .zero // 拖拽速度
    @Published var isNearEdge = false // 是否接近边缘
    @Published var edgeResistance: CGFloat = 1.0 // 边缘阻力系数
    
    private var lastDragPosition: CGPoint = .zero
    private var lastDragTime: Date = Date()
    
    func startDragging(_ item: LaunchpadItem, at position: CGPoint) {
        draggingItem = item
        dragPreviewPosition = position
        dragPreviewScale = 1.0
        isCreatingFolder = false
        hoveredItem = nil
        folderCreationTarget = nil
    }
    
    func updateDragPosition(_ position: CGPoint) {
        dragPreviewPosition = position
    }
    
    func setPendingDropIndex(_ index: Int?) {
        if pendingDropIndex != index {
            pendingDropIndex = index
        }
    }
    
    func setCreatingFolder(_ creating: Bool) {
        isCreatingFolder = creating
    }
    
    func setHoveredItem(_ item: LaunchpadItem?) {
        hoveredItem = item
        // 如果拖拽的是应用，悬停在另一个应用上，则准备创建文件夹
        if let dragging = draggingItem, let hovered = item {
            if case .app = dragging, case .app = hovered, dragging.id != hovered.id {
                folderCreationTarget = hovered
                isCreatingFolder = true
                print("📁 准备创建文件夹: \(dragging.name) + \(hovered.name)")
            } else {
                folderCreationTarget = nil
                isCreatingFolder = false
            }
        } else {
            folderCreationTarget = nil
            isCreatingFolder = false
        }
    }
    
    func endDragging() {
        lastDraggedItem = draggingItem
        draggingItem = nil
        pendingDropIndex = nil
        isCreatingFolder = false
        hoveredItem = nil
        dragPreviewScale = 1.0
    }
    
    func expandFolder(_ folder: FolderItem) {
        expandedFolder = folder
    }
    
    func closeFolder() {
        expandedFolder = nil
    }
    
    func updateExpandedFolderName(_ newName: String) {
        guard var folder = expandedFolder else { return }
        folder.name = newName
        expandedFolder = folder
    }
}

// MARK: - 滚轮事件捕获器
struct ScrollEventCatcher: NSViewRepresentable {
    typealias NSViewType = ScrollEventCatcherView
    let onScroll: (CGFloat, CGFloat, NSEvent.Phase, Bool, Bool) -> Void

    func makeNSView(context: Context) -> ScrollEventCatcherView {
        let view = ScrollEventCatcherView()
        view.onScroll = onScroll
        return view
    }
    
    func updateNSView(_ nsView: ScrollEventCatcherView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class ScrollEventCatcherView: NSView {
        var onScroll: ((CGFloat, CGFloat, NSEvent.Phase, Bool, Bool) -> Void)?
        private var eventMonitor: Any?

        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            // Prefer primary phase; fallback to momentum
            let phase = event.phase != [] ? event.phase : event.momentumPhase
            let isMomentum = event.momentumPhase != []
            let isPreciseOrTrackpad = event.hasPreciseScrollingDeltas || event.phase != [] || event.momentumPhase != []
            onScroll?(event.scrollingDeltaX,
                      event.scrollingDeltaY,
                      phase,
                      isMomentum,
                      isPreciseOrTrackpad)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor = eventMonitor { NSEvent.removeMonitor(monitor); eventMonitor = nil }
            // 全局监听当前窗口的滚动事件，不消费事件
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                let phase = event.phase != [] ? event.phase : event.momentumPhase
                let isMomentum = event.momentumPhase != []
                let isPreciseOrTrackpad = event.hasPreciseScrollingDeltas || event.phase != [] || event.momentumPhase != []
                self?.onScroll?(event.scrollingDeltaX,
                                event.scrollingDeltaY,
                                phase,
                                isMomentum,
                                isPreciseOrTrackpad)
                return event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // 不拦截命中测试，让下层视图处理点击/拖拽等
            return nil
        }

        deinit {
            if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

// MARK: - 分页器（7×5）
struct PagedGridView: View {
    @Binding var currentPage: Int
    let pages: [[LaunchpadItem]]
    @EnvironmentObject var dragManager: GlobalDragManager
    @State private var accumulatedScrollX: CGFloat = 0
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 7)
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                HStack(spacing: 0) {
                    ForEach(0..<pages.count, id: \.self) { pageIndex in
                        GeometryReader { pageGeo in
                            LazyVGrid(columns: columns, spacing: 35) {
                                ForEach(Array(0..<35), id: \.self) { index in
                                    if index < pages[pageIndex].count {
                                        let globalIndex = pageIndex * 35 + index
                                        let item = pages[pageIndex][index]
                                        
                                        GridIconView(item: item, currentPage: pageIndex)
                                            .environmentObject(dragManager)
                                            .environment(\.launchpadPageFrame, pageGeo.frame(in: .named("launchpad-space")))
                                    } else {
                                        Color.clear
                                            .frame(height: 100)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                // 点击空白区域隐藏窗口
                                                AppDelegate.shared?.hideWindow()
                                            }
                                    }
                                }
                            }
                            .padding(.horizontal, 200)
                            .padding(.vertical, 20)
                        }
                        .frame(width: geo.size.width)
                    }
                }
                .offset(x: -CGFloat(currentPage) * geo.size.width)
                .animation(.easeInOut, value: currentPage)
                .gesture(
                    DragGesture().onEnded { value in
                        let threshold = geo.size.width / 4
                        if value.translation.width < -threshold && currentPage < pages.count - 1 {
                            currentPage += 1
                        }
                        if value.translation.width > threshold && currentPage > 0 {
                            currentPage -= 1
                        }
                    }
                )
                
                ScrollEventCatcher { deltaX, deltaY, phase, isMomentum, isPrecise in
                    // 处理分页切换
                    print("ScrollEventCatcher received: deltaX=\(deltaX), deltaY=\(deltaY), phase=\(phase), isMomentum=\(isMomentum), isPrecise=\(isPrecise)")
                    
                    // 鼠标滚轮（非精确）：累积距离；应用小冷却避免多页翻转
                    if !isPrecise {
                        // 将垂直滚轮映射到水平方向，像精确滚动一样
                        let primaryDelta = abs(deltaX) >= abs(deltaY) ? deltaX : -deltaY
                        if primaryDelta == 0 { return }
                        let direction = primaryDelta > 0 ? 1 : -1
                        
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if direction > 0 && currentPage > 0 {
                                currentPage -= 1
                            } else if direction < 0 && currentPage < pages.count - 1 {
                                currentPage += 1
                            }
                        }
                        return
                    }
                    
                    // 触控板精确滚动：累积并在阈值后翻转
                    // 忽略动量阶段以确保每个手势只翻转一次
                    if isMomentum { return }
                    let delta = abs(deltaX) >= abs(deltaY) ? deltaX : -deltaY // 垂直滑动映射到水平
                    
                    switch phase {
                    case .began:
                        // 开始滚动 - 重置累积值
                        accumulatedScrollX = 0
                        print("Trackpad scroll began")
                    case .changed:
                        // 滚动中 - 累积滚动距离
                        accumulatedScrollX += delta
                        print("Trackpad scroll changed: accumulated=\(accumulatedScrollX)")
                    case .ended, .cancelled:
                        // 结束滚动，检查是否达到阈值
                        let pageWidth = geo.size.width
                        let threshold = pageWidth * 0.15 // 使用页面宽度的15%作为阈值
                        print("Trackpad scroll ended: accumulated=\(accumulatedScrollX), threshold=\(threshold)")
                        
                        if accumulatedScrollX <= -threshold && currentPage < pages.count - 1 {
                            print("Navigating to next page")
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage += 1
                            }
                        } else if accumulatedScrollX >= threshold && currentPage > 0 {
                            print("Navigating to previous page")
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage -= 1
                            }
                        }
                        accumulatedScrollX = 0
                    default:
                        break
                    }
                }
            }
            
            // 拖动预览
            if let draggingItem = dragManager.draggingItem {
                DragPreviewView(item: draggingItem)
                    .environmentObject(dragManager)
                    .position(
                        x: dragManager.dragPreviewPosition.x - geo.frame(in: .named("launchpad-space")).minX,
                        y: dragManager.dragPreviewPosition.y - geo.frame(in: .named("launchpad-space")).minY
                    )
                    .zIndex(100)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - 拖动预览视图
struct DragPreviewView: View {
    let item: LaunchpadItem
    @EnvironmentObject var dragManager: GlobalDragManager
    
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
            
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
        }
        .scaleEffect(dragManager.dragPreviewScale)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragManager.dragPreviewScale)
    }
}

// MARK: - 主界面
struct LaunchpadView: View {
    @State private var query = ""
    @State private var currentPage = 0
    @State private var appearAnim = false
    @StateObject private var dragManager = GlobalDragManager()
    @StateObject private var dataManager = LaunchpadDataManager()
    @FocusState private var searchFocused: Bool
    
    // 用于拖拽重排的虚拟应用列表
    private var visualApps: [LaunchpadItem] {
        guard let draggingItem = dragManager.draggingItem,
              let pendingIndex = dragManager.pendingDropIndex else {
            return dataManager.apps
        }
        
        var result = dataManager.apps
        if let sourceIndex = result.firstIndex(where: { $0.id == draggingItem.id }) {
            result.remove(at: sourceIndex)
            let insertIndex = min(pendingIndex, result.count)
            result.insert(draggingItem, at: insertIndex)
        }
        return result
    }
    
    var pages: [[LaunchpadItem]] {
        let filtered = query.isEmpty
            ? visualApps
            : visualApps.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return stride(from: 0, to: filtered.count, by: 35).map {
            Array(filtered[$0..<min($0+35, filtered.count)])
        }
    }
    
    var body: some View {
        ZStack {
            VisualBlurView()
                .ignoresSafeArea()
                .onTapGesture {
                    // 只有在没有展开文件夹时才隐藏窗口
                    if dragManager.expandedFolder == nil {
                        AppDelegate.shared?.hideWindow()
                        if searchFocused {
                            searchFocused = false
                        }
                    }
                }
            
            if let expandedFolder = dragManager.expandedFolder {
                // 文件夹展开视图
                FolderExpandedView(folder: expandedFolder)
                    .environmentObject(dragManager)
                    .environmentObject(dataManager)
            } else {
                // 主视图
                VStack(spacing: 0) {
                LaunchpadSearchBar(query: $query)
                        .focused($searchFocused)
                        .padding(.top, 80)
                        .padding(.bottom, 20)
                    .scaleEffect(appearAnim ? 1 : 0.9)
                    .opacity(appearAnim ? 1 : 0)
                    .animation(.easeOut(duration: 0.35).delay(0.05), value: appearAnim)
                
                PagedGridView(currentPage: $currentPage, pages: pages)
                    .environmentObject(dragManager)
                    .frame(height: 600)
                
                Spacer()
                
                HStack(spacing: 4) {
                    ForEach(pages.indices, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? Color.white.opacity(0.9) : Color.white.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .padding(4)
                            .onTapGesture { currentPage = i }
                    }
                }
                .padding(.bottom, 100)
                .opacity(appearAnim ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.2), value: appearAnim)
                }
            }
        }
        .coordinateSpace(name: "launchpad-space")
        .environmentObject(dragManager)
        .onAppear {
            withAnimation { appearAnim = true }
        }
        .onChange(of: query) { _, _ in
            currentPage = 0
        }
        .onKeyPress(.escape) {
            AppDelegate.shared?.hideWindow()
            return .handled
        }
        .onChange(of: dragManager.pendingDropIndex) { _, newValue in
            // 移除实时更新，避免无限循环
        }
        .onChange(of: dragManager.draggingItem) { _, draggingItem in
            // 当拖拽结束时（draggingItem变为nil），应用最终的重排
            if draggingItem == nil, let lastItem = dragManager.lastDraggedItem, let dropIndex = dragManager.pendingDropIndex {
                applyReordering(from: lastItem, to: dropIndex)
                dragManager.lastDraggedItem = nil
            }
        }
        .onChange(of: dragManager.folderCreationTarget) { _, target in
            if let target = target, let draggingItem = dragManager.draggingItem {
                createFolder(from: draggingItem, to: target)
            }
        }
    }
    
    // MARK: - LaunchNow风格的拖拽处理
    private func applyReordering(from draggingItem: LaunchpadItem, to dropIndex: Int) {
        guard let sourceIndex = dataManager.apps.firstIndex(where: { $0.id == draggingItem.id }) else { 
            print("❌ 找不到源应用: \(draggingItem.name)")
            return 
        }
        
        print("🔄 LaunchNow风格重排:")
        print("   - 源应用: \(draggingItem.name) (索引: \(sourceIndex))")
        print("   - 目标索引: \(dropIndex)")
        
        // 检查是否为跨页拖拽
        let sourcePage = sourceIndex / 35
        let targetPage = dropIndex / 35
        
        if sourcePage == targetPage {
            // 同页内移动：使用页内排序逻辑
            let pageStart = sourcePage * 35
            let pageEnd = min(pageStart + 35, dataManager.apps.count)
            var pageItems = Array(dataManager.apps[pageStart..<pageEnd])
            
            let localFrom = sourceIndex - pageStart
            let localTo = max(0, min(dropIndex - pageStart, pageItems.count - 1))
            
            let moving = pageItems.remove(at: localFrom)
            pageItems.insert(moving, at: localTo)
            
            // 更新数据
            var newApps = dataManager.apps
            newApps.replaceSubrange(pageStart..<pageEnd, with: pageItems)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dataManager.apps = newApps
            }
            
            print("✅ 同页内重排完成")
        } else {
            // 跨页拖拽：使用级联插入逻辑
            moveItemAcrossPagesWithCascade(item: draggingItem, to: dropIndex)
        }
        
        // 保存数据
        dataManager.saveData()
    }
    
    private func moveItemAcrossPagesWithCascade(item: LaunchpadItem, to targetIndex: Int) {
        guard let sourceIndex = dataManager.apps.firstIndex(where: { $0.id == item.id }) else { return }
        
        let targetPage = targetIndex / 35
        let sourcePage = sourceIndex / 35
        
        // 移除源项目
        var newApps = dataManager.apps
        newApps.remove(at: sourceIndex)
        
        // 计算插入位置
        let insertIndex = min(targetIndex, newApps.count)
        
        // 如果目标页面不存在，创建空项目填充
        let targetPageStart = targetPage * 35
        while newApps.count < targetPageStart {
            newApps.append(.empty(UUID().uuidString))
        }
        
        // 插入到目标位置
        newApps.insert(item, at: insertIndex)
        
        // 压缩空项目到页面末尾
        compactItemsWithinPages(&newApps)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dataManager.apps = newApps
        }
        
        // 切换到目标页面
        if targetPage != currentPage {
            currentPage = targetPage
        }
        
        print("✅ 跨页重排完成")
    }
    
    private func compactItemsWithinPages(_ apps: inout [LaunchpadItem]) {
        let itemsPerPage = 35
        var result: [LaunchpadItem] = []
        
        for pageStart in stride(from: 0, to: apps.count, by: itemsPerPage) {
            let pageEnd = min(pageStart + itemsPerPage, apps.count)
            let pageItems = Array(apps[pageStart..<pageEnd])
            
            // 分离空项目和非空项目
            let nonEmptyItems = pageItems.filter { item in
                if case .empty = item { return false }
                return true
            }
            let emptyItems = pageItems.filter { item in
                if case .empty = item { return true }
                return false
            }
            
            // 先添加非空项目，再添加空项目
            result.append(contentsOf: nonEmptyItems)
            result.append(contentsOf: emptyItems)
        }
        
        apps = result
    }
    
    private func createFolder(from draggingItem: LaunchpadItem, to targetItem: LaunchpadItem) {
        guard case .app = draggingItem,
              case .app = targetItem else { return }
        
        // 使用数据管理器创建文件夹
        dataManager.createFolder(from: draggingItem, to: targetItem)
        
        dragManager.folderCreationTarget = nil // 清空目标
    }
}

// MARK: - 文件夹展开视图
struct FolderExpandedView: View {
    let folder: FolderItem
    @EnvironmentObject var dragManager: GlobalDragManager
    @EnvironmentObject var dataManager: LaunchpadDataManager
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var currentPage = 0
    
    private let maxAppsPerPage = 12 // 一页最多12个图标
    private let gridColumns = 7 // 7列布局，和主页一样
    
    // 分页应用
    private var paginatedApps: [[AppItem]] {
        stride(from: 0, to: folder.apps.count, by: maxAppsPerPage).map {
            Array(folder.apps[$0..<min($0 + maxAppsPerPage, folder.apps.count)])
        }
    }
    
    var body: some View {
                    ZStack {
            VisualBlurView()
                .ignoresSafeArea()
                .onTapGesture { dragManager.closeFolder() } // Click background to close folder
            
            VStack(spacing: 20) {
                // 文件夹名称（在磨砂矩形外面）
                if isEditingName {
                    TextField("文件夹名称", text: $editedName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .textFieldStyle(PlainTextFieldStyle())
                        .multilineTextAlignment(.center)
                        .background(Color.clear)
                        .accentColor(.white)
                        .colorScheme(.dark)
                        .onSubmit {
                            if !editedName.isEmpty {
                                // 使用数据管理器更新文件夹名称
                                dataManager.updateFolderName(folder.id, newName: editedName)
                                // 更新当前显示的文件夹名称
                                dragManager.updateExpandedFolderName(editedName)
                            }
                            isEditingName = false
                        }
                        .onAppear {
                            editedName = folder.name
                        }
                } else {
                    Text(folder.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .onTapGesture {
                            isEditingName = true
                        }
                }
                
                // 居中的磨砂矩形
                VStack(spacing: 16) {
                    // 分页应用网格
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(0..<paginatedApps.count, id: \.self) { pageIndex in
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: gridColumns),
                                    spacing: 35
                                ) {
                                    ForEach(Array(0..<maxAppsPerPage), id: \.self) { index in
                                        if index < paginatedApps[pageIndex].count {
                                            let app = paginatedApps[pageIndex][index]
                                        VStack(spacing: 8) {
                                            Image(nsImage: app.icon)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                    .frame(width: 108, height: 108)
                                                    .cornerRadius(16)
                                                
                                            Text(app.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                        }
                                            .contentShape(Rectangle())
                                        .onTapGesture {
                                                // 点击应用图标：关闭文件夹并启动应用
                                                dragManager.closeFolder()
                                                AppDelegate.shared?.hideWindow()
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
                                                }
                                            }
                                        } else {
                                            // 空白占位符
                                            Color.clear
                                                .frame(width: 108, height: 108)
                                        }
                                    }
                                }
                                .padding(.horizontal, 40)
                                .padding(.vertical, 30)
                                .frame(width: geometry.size.width)
                            }
                        }
                        .offset(x: -CGFloat(currentPage) * geometry.size.width)
                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                        .gesture(
                            DragGesture().onEnded { value in
                                    let threshold = geometry.size.width / 4
                                if value.translation.width < -threshold && currentPage < paginatedApps.count - 1 {
                                        currentPage += 1
                                }
                                if value.translation.width > threshold && currentPage > 0 {
                                        currentPage -= 1
                                    }
                                }
                        )
                    }
                    .frame(height: 400) // 固定高度
                
                // 分页指示器
                    if paginatedApps.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(0..<paginatedApps.count, id: \.self) { i in
                        Circle()
                                    .fill(i == currentPage ? Color.white.opacity(0.9) : Color.white.opacity(0.5))
                                    .frame(width: 8, height: 8)
                                    .padding(4)
                                    .onTapGesture { currentPage = i }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
                .frame(width: 1200) // 固定宽度
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.8)),
            removal: .opacity.combined(with: .scale(scale: 0.8))
        ))
        .onAppear {
            // 添加滚轮事件监听
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                let deltaY = event.scrollingDeltaY
                let threshold: CGFloat = 10.0
                
                if deltaY > threshold && currentPage > 0 {
                    currentPage -= 1
                } else if deltaY < -threshold && currentPage < paginatedApps.count - 1 {
                    currentPage += 1
                }
                
                return event
            }
        }
    }
}

