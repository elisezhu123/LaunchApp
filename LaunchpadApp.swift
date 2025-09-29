import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let launchpadWindowShown = Notification.Name("LaunchpadWindowShown")
    static let launchpadWindowHidden = Notification.Name("LaunchpadWindowHidden")
    static let stopShaking = Notification.Name("StopShaking")
}

// MARK: - 自定义无边框窗口类
class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 自定义 AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate?
    
    var window: NSWindow!
    private var lastShowAt: Date?
    private var cancellables = Set<AnyCancellable>()
    
    private var isTerminating = false
    private var windowIsVisible = false
    private var isAnimatingWindow = false
    private var pendingShow = false
    private var pendingHide = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        setupWindow()
        showWindow()
    }
    
    private func setupWindow() {
        guard let screen = NSScreen.main else { return }
        
        // 创建自定义无边框窗口
        window = BorderlessWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.delegate = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        
        // ✅ 关键：设置窗口属性，在当前桌面空间显示
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        window.acceptsMouseMovedEvents = true
        
        // SwiftUI 内容 - 使用完整的 Launchpad 视图
        let hostingView = NSHostingView(rootView: LaunchpadView())
        window.contentView = hostingView
        
        // ✅ 隐藏菜单栏和 Dock，让菜单栏变黑
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        
        // 初始状态：隐藏
        window.alphaValue = 0
        window.contentView?.alphaValue = 0
        windowIsVisible = false
    }
    
    func showWindow() {
        pendingShow = true
        pendingHide = false
        startPendingWindowTransition()
    }
    
    func hideWindow() {
        pendingHide = true
        pendingShow = false
        startPendingWindowTransition()
    }
    
    // MARK: - Quit with fade
    func quitWithFade() {
        guard !isTerminating else { NSApp.terminate(nil); return }
        isTerminating = true
        if let window = window {
            pendingShow = false
            pendingHide = false
            animateWindow(to: 0, resumePending: false) {
                window.orderOut(nil)
                window.alphaValue = 1
                window.contentView?.alphaValue = 1
                NSApp.terminate(nil)
            }
        } else {
            NSApp.terminate(nil)
        }
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        quitWithFade()
        return .terminateLater
    }
    
    // MARK: - Window animation helpers
    private func startPendingWindowTransition() {
        guard !isAnimatingWindow else { return }
        if pendingShow {
            performShowWindow()
        } else if pendingHide {
            performHideWindow()
        }
    }
    
    private func performShowWindow() {
        pendingShow = false
        guard let window = window else { return }
        
        if windowIsVisible && !isAnimatingWindow && window.alphaValue >= 0.99 {
            return
        }
        
        guard let screen = NSScreen.main else { return }
        let rect = screen.frame
        window.setFrame(rect, display: true)
        
        if window.alphaValue <= 0.01 || !windowIsVisible {
            window.alphaValue = 0
            window.contentView?.alphaValue = 0
        }
        
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        lastShowAt = Date()
        windowIsVisible = true
        NotificationCenter.default.post(name: .launchpadWindowShown, object: nil)
        
        animateWindow(to: 1) {
            self.windowIsVisible = true
        }
    }
    
    private func performHideWindow() {
        pendingHide = false
        guard let window = window else { return }
        
        let finalize: () -> Void = {
            self.windowIsVisible = false
            window.orderOut(nil)
            window.alphaValue = 1
            window.contentView?.alphaValue = 1
            // 停止抖动状态
            NotificationCenter.default.post(name: .stopShaking, object: nil)
            NotificationCenter.default.post(name: .launchpadWindowHidden, object: nil)
        }
        
        if (!windowIsVisible && window.alphaValue <= 0.01) || isTerminating {
            finalize()
            return
        }
        
        animateWindow(to: 0) {
            finalize()
        }
    }
    
    private func animateWindow(to targetAlpha: CGFloat, resumePending: Bool = true, completion: (() -> Void)? = nil) {
        guard let window = window else {
            completion?()
            return
        }
        
        isAnimatingWindow = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = targetAlpha
            window.contentView?.animator().alphaValue = targetAlpha
        }, completionHandler: {
            window.alphaValue = targetAlpha
            window.contentView?.alphaValue = targetAlpha
            self.isAnimatingWindow = false
            completion?()
            if resumePending {
                self.startPendingWindowTransition()
            }
        })
    }
    
    func windowDidResignKey(_ notification: Notification) { autoHideIfNeeded() }
    func windowDidResignMain(_ notification: Notification) { autoHideIfNeeded() }
    private func autoHideIfNeeded() {
        hideWindow()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window?.isVisible == true {
            hideWindow()
        } else {
            showWindow()
        }
        return false
    }
}

// MARK: - SwiftUI App 入口
@main
struct MyLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // 不需要窗口组，否则会生成额外窗口
        Settings {
            EmptyView()
        }
    }
}
