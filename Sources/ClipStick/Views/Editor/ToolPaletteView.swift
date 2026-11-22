import SwiftUI

struct ToolPaletteView: View {
    @ObservedObject var vm: AnnotationViewModel
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(AnnotationTool.allCases) { tool in
                Button { vm.tool = tool } label: {
                    HStack(spacing: 3) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 12, weight: .medium))
                        if tool == .redact || vm.tool == tool {
                            Text(tool.title)
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, (tool == .redact || vm.tool == tool) ? 7 : 5)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(vm.tool == tool ? Color.accentColor : (tool == .redact ? Color.red.opacity(0.12) : Color.primary.opacity(0.06))))
                    .foregroundStyle(vm.tool == tool ? Color.white : (tool == .redact ? Color.red : Color.primary))
                }
                .buttonStyle(.plain)
                .help("\(tool.title): \(tool.hint)")
            }

            Divider().frame(height: 20).padding(.horizontal, 4)

            ForEach(AnnotationColor.allCases) { color in
                Button { vm.color = color } label: {
                    Circle().fill(Color(nsColor: color.nsColor))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.white, lineWidth: vm.color == color ? 2 : 0))
                        .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                        .padding(3)
                }
                .buttonStyle(.plain)
                .help(color.rawValue.capitalized)
            }

            Divider().frame(height: 20).padding(.horizontal, 4)

            Button { vm.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!vm.canUndo).help("Undo (⌘Z)")
            Button { vm.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!vm.canRedo).help("Redo (⇧⌘Z)")

            Spacer(minLength: 8)

            Button("Cancel", action: onCancel).help("Esc")
            Button(action: onSave) {
                Label("Save & Copy", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .help("⌘↩ — saves the edit as a new layer and copies the result")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 46)
    }
}
