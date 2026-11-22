import SwiftUI

/// Editor toolbar: icon-only, grouped, one accent for the active tool. Shapes and privacy tools live in menus.
struct ToolPaletteView: View {
    @ObservedObject var vm: AnnotationViewModel
    let onSave: () -> Void
    let onCancel: () -> Void

    private static let shapes: [AnnotationTool] = [.rectangle, .square, .circle, .triangle]
    private static let privacy: [AnnotationTool] = [.redact, .pixelate]

    var body: some View {
        HStack(spacing: 6) {
            group { toolButton(.crop); toolButton(.eraser) }
            group { toolButton(.marker); toolButton(.pen); toolButton(.arrow) }
            group {
                menuTool(Self.shapes, fallback: .rectangle, help: "Shapes")
                toolButton(.text); toolButton(.badge)
            }
            group {
                menuTool(Self.privacy, fallback: .redact, help: "Privacy", extra: {
                    Divider()
                    Button { vm.autoRedact() } label: { Label("Auto-redact secrets", systemImage: "wand.and.stars") }
                })
            }

            colors

            Spacer(minLength: 8)

            if let status = vm.statusMessage {
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Button { vm.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!vm.canUndo).help("Undo (⌘Z)")
            Button { vm.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!vm.canRedo).help("Redo (⇧⌘Z)")
            Button("Cancel", action: onCancel).help("Esc")
            Button("Save & Copy", action: onSave)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help("⌘↩ — saves the edit and copies the result")
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .frame(height: 46)
    }

    // MARK: Pieces

    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 2) { content() }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button { vm.tool = tool } label: { chip(tool.symbol, active: vm.tool == tool) }
            .buttonStyle(.plain)
            .help("\(tool.title) — \(tool.hint)")
    }

    private func menuTool<E: View>(_ tools: [AnnotationTool], fallback: AnnotationTool, help: String,
                                   @ViewBuilder extra: () -> E = { EmptyView() }) -> some View {
        let active = tools.contains(vm.tool)
        let current = active ? vm.tool : fallback
        return Menu {
            ForEach(tools) { t in
                Button { vm.tool = t } label: { Label(t.title, systemImage: t.symbol) }
            }
            extra()
        } label: {
            chip(current.symbol, active: active)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }

    private func chip(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 28, height: 26)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active ? Color.accentColor : .clear))
            .contentShape(Rectangle())
    }

    private var colors: some View {
        HStack(spacing: 2) {
            ForEach(AnnotationColor.allCases) { color in
                Button { vm.color = color } label: {
                    Circle().fill(Color(nsColor: color.nsColor))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(vm.color == color ? 0.9 : 0), lineWidth: 1.5).padding(-3))
                        .padding(5)
                }
                .buttonStyle(.plain)
                .help(color.rawValue.capitalized)
            }
        }
        .padding(.leading, 4)
    }
}
