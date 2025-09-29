import SwiftUI
import AppKit

struct SuperviewOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            SuperviewAccessor { _, window in
                guard let window = window,
                      let contentView = window.contentView,
                      let container = contentView.superview else { return }

                // 1. 窗口覆盖整个屏幕（包含菜单栏和 Dock 区域）
                if let screen = window.screen ?? NSScreen.main {
                    window.setFrame(screen.frame, display: true)
                }

                // 2. 无边框 & 全尺寸内容
                window.styleMask = [.borderless, .fullSizeContentView]
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.hasShadow = false

                // 3. 出现在当前空间
                window.collectionBehavior = [
                    .stationary, .fullScreenAuxiliary
                ]

                // ✅ 菜单栏 & Dock 默认隐藏（鼠标移上去呼出）
                NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
                
               

                // 4. 添加模糊层 + 暗化层（只加一次）
                if !(container.subviews.contains { $0 is NSVisualEffectView }) {
                    let fx = NSVisualEffectView()
                    fx.material = .underWindowBackground
                    fx.blendingMode = .behindWindow
                    fx.state = .active
                    fx.translatesAutoresizingMaskIntoConstraints = false
                    container.addSubview(fx, positioned: .below, relativeTo: nil)

                    NSLayoutConstraint.activate([
                        fx.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                        fx.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                        fx.topAnchor.constraint(equalTo: container.topAnchor),
                        fx.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    ])

                    let dim = NSView()
                    dim.wantsLayer = true
                    dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
                    dim.translatesAutoresizingMaskIntoConstraints = false
                    container.addSubview(dim, positioned: .above, relativeTo: fx)

                    NSLayoutConstraint.activate([
                        dim.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                        dim.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                        dim.topAnchor.constraint(equalTo: container.topAnchor),
                        dim.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    ])
                }
            }
        )
    }
}

struct SuperviewAccessor: NSViewRepresentable {
    var callback: (NSView, NSWindow?) -> ()
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { callback(view, view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func launchpadOverlay() -> some View {
        self.modifier(SuperviewOverlayModifier())
    }
}

