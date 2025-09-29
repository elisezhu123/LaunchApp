# Launchpad - macOS 启动台应用

一个仿照 macOS Launchpad 的 SwiftUI 应用，提供类似原版启动台的用户体验。

⚠️目前还没写完（很多功能会慢慢写）

# 界面参考

主页
![IMG_9974](https://github.com/user-attachments/assets/1a8db7ae-716d-4a19-a722-55e9504ba531)

文件夹样式
![IMG_9975](https://github.com/user-attachments/assets/fa4046b3-16e6-4eb4-ba9e-0ea8c5ee2b9d)

图标样式（9个为一组）
![IMG_9977](https://github.com/user-attachments/assets/3c20bf01-2e49-422c-8e9e-cd8f0aac5f3b)

## 功能特性

### 🎯 核心功能
- **应用网格显示**: 7列5行的网格布局，支持多页面分页
- **应用启动**: 点击应用图标直接启动对应应用
- **文件夹支持**: 创建和管理应用文件夹
- **文件夹展开**: 点击文件夹显示内部应用，支持分页（每页最多12个应用）
- **应用重命名**: 支持文件夹重命名功能
- **数据持久化**: 所有修改（重命名、文件夹创建等）自动保存

### 🎨 界面设计
- **磨砂玻璃效果**: 使用 `.ultraThinMaterial` 实现现代化的磨砂背景
- **响应式布局**: 自适应不同屏幕尺寸和窗口大小
- **暗色主题**: 专为暗色模式优化的界面设计
- **圆角图标**: 108x108 像素的应用图标，16像素圆角
- **分页指示器**: 底部显示当前页面和总页数

### 📱 应用管理
- **系统应用扫描**: 自动扫描系统应用目录
- **应用分类**: 自动创建"工具"文件夹，包含系统工具应用
- **应用排序**: 第一页按系统默认顺序排列，其他应用按字母顺序
- **应用去重**: 自动去除重复应用

### 🔍 搜索功能
- **实时搜索**: 输入关键词实时过滤应用
- **模糊匹配**: 支持应用名称的部分匹配
- **搜索高亮**: 匹配的文本会高亮显示

### 📂 文件夹功能
- **文件夹展开**: 点击文件夹显示磨砂矩形界面
- **文件夹重命名**: 点击文件夹名称进行编辑
- **文件夹分页**: 文件夹内应用超过12个时自动分页
- **文件夹图标**: 自动生成文件夹图标，显示前9个应用的图标

## 技术实现

### 🏗️ 架构设计
- **MVVM 模式**: 使用 SwiftUI 的 `@Observable` 和 `@StateObject`
- **环境对象**: 通过 `@EnvironmentObject` 共享状态管理
- **数据持久化**: 使用 JSON 编码/解码保存应用数据

### 📊 数据模型
```swift
enum LaunchpadItem {
    case app(AppItem)
    case folder(FolderItem)
    case empty(String)
}

struct AppItem {
    let id: String
    let name: String
    let path: String
    let icon: NSImage
}

struct FolderItem {
    let id: String
    var name: String
    let apps: [AppItem]
    let icon: NSImage
}
```

### 🎛️ 状态管理
- **GlobalDragManager**: 管理拖拽状态和文件夹展开状态
- **LaunchpadDataManager**: 管理应用数据和持久化存储
- **环境传递**: 通过环境值传递页面frame信息

### 🎨 界面组件
- **LaunchpadView**: 主界面，包含搜索栏和分页网格
- **PagedGridView**: 分页网格视图，支持滚轮和触控板手势
- **GridIconView**: 单个应用/文件夹图标视图
- **FolderExpandedView**: 文件夹展开视图，磨砂矩形设计
- **LaunchpadSearchBar**: 搜索栏组件
- **VisualBlurView**: 磨砂背景视图

## 安装和运行

### 系统要求
- macOS 14.0 或更高版本
- Xcode 15.0 或更高版本
- Swift 5.9 或更高版本

### 构建步骤
1. 克隆项目到本地
2. 使用 Xcode 打开 `Launchpad.xcodeproj`
3. 选择目标设备（Mac）
4. 按 `Cmd + R` 运行项目

### 构建命令
```bash
xcodebuild -project Launchpad.xcodeproj -scheme Launchpad -configuration Debug build ENABLE_APP_SANDBOX=NO
```

## 使用说明

### 基本操作
1. **启动应用**: 运行后显示启动台界面
2. **浏览应用**: 使用滚轮或触控板左右滑动切换页面
3. **启动应用**: 点击应用图标启动对应应用
4. **打开文件夹**: 点击文件夹图标展开文件夹内容
5. **搜索应用**: 在顶部搜索栏输入应用名称

### 文件夹操作
1. **创建文件夹**: 将应用拖拽到另一个应用上创建文件夹
2. **重命名文件夹**: 在文件夹展开界面点击文件夹名称进行编辑
3. **关闭文件夹**: 点击文件夹外部区域或按 ESC 键
4. **文件夹内操作**: 在文件夹内点击应用图标启动应用并关闭启动台

### 搜索功能
1. **实时搜索**: 在搜索栏输入关键词，应用列表实时过滤
2. **清除搜索**: 删除搜索内容或点击清除按钮
3. **搜索高亮**: 匹配的文本会以高亮显示

## 项目结构

```
Launchpad/
├── LaunchpadApp.swift          # 应用入口
├── ContentView.swift           # 主内容视图
├── LaunchpadView.swift         # 启动台主视图
├── AppIcon.swift              # 应用图标和网格组件
├── LaunchpadSearchBar.swift   # 搜索栏组件
├── VisualBlurView.swift       # 磨砂背景视图
├── FullscreenWindowModifier.swift # 全屏窗口修饰器
└── Assets.xcassets/           # 应用资源
```

## 开发说明

### 添加新功能
1. 在相应的 Swift 文件中添加新组件
2. 更新数据模型（如需要）
3. 在 `LaunchpadView` 中集成新功能
4. 测试功能并更新文档

### 自定义配置
- **网格布局**: 修改 `LaunchpadLayout` 中的参数
- **应用扫描**: 修改 `loadApplications()` 函数中的路径
- **界面样式**: 调整各个视图的样式参数

## 许可证

本项目采用 MIT 许可证。详见 LICENSE 文件。

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目。

## 更新日志

### v1.0.0
- 初始版本发布
- 实现基本的启动台功能
- 支持应用网格显示和启动
- 支持文件夹创建和管理
- 支持搜索功能
- 支持数据持久化
