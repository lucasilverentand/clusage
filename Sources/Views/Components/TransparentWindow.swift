import SwiftUI
import AppKit

/// Modifier that controls the hosting NSWindow's transparency.
/// When `transparent` is true, materials show the desktop behind the window.
/// When false, the window returns to its default opaque background.
struct WindowTransparencyModifier: ViewModifier {
    let transparent: Bool

    func body(content: Content) -> some View {
        content
            .background(WindowTransparencyAccessor(transparent: transparent))
    }
}

private struct WindowTransparencyAccessor: NSViewRepresentable {
    let transparent: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applyTransparency(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyTransparency(to: nsView.window)
    }

    private func applyTransparency(to window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = !transparent
        window.backgroundColor = transparent ? .clear : .windowBackgroundColor
        window.titlebarAppearsTransparent = transparent
        window.titlebarSeparatorStyle = transparent ? .none : .automatic
    }
}

/// Makes the window background clear so materials show the desktop,
/// but keeps the native titlebar with its liquid glass appearance.
private struct GlassWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applyGlass(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyGlass(to: nsView.window)
    }

    private func applyGlass(to window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
    }
}

extension View {
    func transparentWindow() -> some View {
        modifier(WindowTransparencyModifier(transparent: true))
    }

    func opaqueWindow() -> some View {
        modifier(WindowTransparencyModifier(transparent: false))
    }

    /// See-through window with native liquid glass titlebar preserved.
    func glassWindow() -> some View {
        background(GlassWindowAccessor())
    }
}
