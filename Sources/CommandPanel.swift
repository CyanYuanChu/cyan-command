import SwiftUI
import AppKit
import Translation
import Combine

final class QuickCommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var dismissAction: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { dismissAction?() }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == 53 {
            dismissAction?()
            return
        }
        super.sendEvent(event)
    }
}

@MainActor final class CommandPanelController: NSObject, NSWindowDelegate {
    let model: QuickCommandModel
    private var panel: QuickCommandPanel?
    private var changes: AnyCancellable?
    private var previousApplication: NSRunningApplication?
    init(model: QuickCommandModel) {
        self.model = model
        super.init()
        changes = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateSize() }
        }
    }
    func toggle() { if panel?.isVisible == true { dismiss() } else { show() } }
    func show() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        if !panel.isVisible { previousApplication = NSWorkspace.shared.frontmostApplication }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height = desiredHeight
        panel.setFrame(NSRect(x: visible.midX - 340, y: visible.maxY - max(80, visible.height * 0.22) - height,
                              width: 680, height: height), display: false)
        // Showing a floating window does not activate its application. Take
        // keyboard ownership explicitly when invoked from another application.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusVersion += 1
    }
    func dismiss() {
        let previousApplication = previousApplication
        self.previousApplication = nil
        model.cancel()
        panel?.orderOut(nil)
        if let previousApplication, previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApplication.activate(options: [])
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        guard panel?.attachedSheet == nil, !model.working else { return }
        panel?.orderOut(nil)
    }
    private var desiredHeight: CGFloat { !model.output.isEmpty ? 430 : model.error != nil ? 258 : 204 }
    private func updateSize() {
        guard let panel, panel.isVisible else { return }
        let top = panel.frame.maxY
        let height = desiredHeight
        var frame = panel.frame; frame.origin.y = top - height; frame.size.height = height
        panel.setFrame(frame, display: true, animate: false)
    }
    private func createPanel() {
        let created = QuickCommandPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 204),
            styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        created.title = "Cyan Grove · 快速指令"
        created.isReleasedWhenClosed = false
        created.level = .floating; created.isOpaque = false; created.backgroundColor = .clear
        created.hasShadow = true; created.hidesOnDeactivate = false
        created.becomesKeyOnlyIfNeeded = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        created.delegate = self
        created.dismissAction = { [weak self] in self?.dismiss() }
        let host: NSView
        if #available(macOS 15.0, *) {
            host = NSHostingView(rootView: TranslationCommandView(model: model, dismiss: { [weak self] in self?.dismiss() }))
        } else {
            host = NSHostingView(rootView: Text("快速翻译需要 macOS 15 或更高版本。").padding(30))
        }
        created.contentView = host
        panel = created
    }
}

@available(macOS 15.0, *)
struct TranslationCommandView: View {
    @ObservedObject var model: QuickCommandModel
    var dismiss: () -> Void
    @GroveState private var configuration: TranslationSession.Configuration?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                GroveMark(size: 24)
                Text("Cyan Command").font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("快速指令").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(action: dismiss) { Text("esc").font(.system(size: 10, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 3) }
                    .buttonStyle(.plain).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel("关闭快速指令")
            }
            HStack(spacing: 12) {
                Image(systemName: "text.bubble").font(.system(size: 23, weight: .light)).foregroundStyle(Color(hex: "719D50"))
                CommandInputField(model: model, dismiss: dismiss).frame(height: 34)
            }.frame(minHeight: 42)
            Divider().opacity(0.6)
            if model.working {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.statusText).font(.system(size: 12))
                    Spacer()
                    Button("取消") { model.cancel() }.buttonStyle(.plain).font(.system(size: 11))
                }
            } else if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !model.output.isEmpty {
                HStack {
                    Text("简体中文").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.copied ? "已复制" : "复制译文") { model.copyResult() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color(hex: "487341"))
                }
                ScrollView {
                    Text(model.output).font(.system(size: 17)).lineSpacing(6).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    Text("T:").font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 3).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                    Text("英文 → 简体中文").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("↵ 翻译").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if model.working && model.statusText == "正在准备系统翻译…" { Text("首次使用可能需要下载系统翻译语言包。").font(.system(size: 10)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .padding(22).frame(width: 680).frame(maxHeight: .infinity, alignment: .topLeading)
        .background(CommandPanelMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.09), lineWidth: 1))
        .onExitCommand(perform: dismiss)
        .task(id: model.request?.id) {
            guard let request = model.request else { configuration = nil; return }
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let installed = await LanguageAvailability().status(from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "zh-Hans"))
                guard !Task.isCancelled, model.request?.id == request.id else { return }
                if installed == .installed {
                    configuration = nil
                    await translateInstalled(request)
                    return
                }
            }
            #endif
            guard !Task.isCancelled, model.request?.id == request.id else { return }
            if configuration == nil {
                configuration = TranslationSession.Configuration(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "zh-Hans"))
            } else { configuration?.invalidate() }
        }
        .translationTask(configuration) { session in
            guard let request = model.request else { return }
            do {
                try await session.prepareTranslation()
                try Task.checkCancellation()
                model.setPhase(id: request.id, text: "正在本机翻译…")
                let response = try await session.translate(request.text)
                try Task.checkCancellation()
                model.complete(id: request.id, output: response.targetText)
            } catch is CancellationError {
                if model.working { model.fail(id: request.id, message: "翻译已中断，请按回车重试。") }
            } catch {
                model.fail(id: request.id, message: "翻译未完成。请确认英中语言包已下载后重试。")
            }
        }
    }
    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    @MainActor private func translateInstalled(_ request: CommandTranslationRequest) async {
        let session = TranslationSession(installedSource: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "zh-Hans"))
        model.setPhase(id: request.id, text: "正在本机翻译…")
        let watchdog = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            guard model.request?.id == request.id, model.working else { return }
            session.cancel()
            model.fail(id: request.id, message: "系统翻译响应超时，请按回车重试。")
        }
        defer { watchdog.cancel() }
        do {
            let response = try await session.translate(request.text)
            try Task.checkCancellation()
            if model.working { model.complete(id: request.id, output: response.targetText) }
        } catch is CancellationError {
            if model.working { model.fail(id: request.id, message: "翻译已中断，请按回车重试。") }
        } catch {
            if model.working { model.fail(id: request.id, message: "系统翻译暂时不可用，请按回车重试。") }
        }
    }

    #endif
}

// Keep the field editor and Escape/Return handling in AppKit's responder chain.
// A retained SwiftUI FocusState may stay true after the panel closes and fail to
// restore the field editor the next time the global shortcut opens the panel.
private struct CommandInputField: NSViewRepresentable {
    @ObservedObject var model: QuickCommandModel
    var dismiss: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(model: model, dismiss: dismiss) }
    func makeNSView(context: Context) -> CommandInputTextField {
        let field = CommandInputTextField()
        field.delegate = context.coordinator
        field.isBordered = false; field.isBezeled = false; field.drawsBackground = false
        field.font = .systemFont(ofSize: 23); field.textColor = .labelColor
        field.focusRingType = .none; field.isEditable = true; field.isSelectable = true
        field.placeholderString = "T: 输入英文，回车译成中文"
        field.cell?.isScrollable = true; field.cell?.wraps = false
        field.cell?.usesSingleLineMode = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("快速指令输入")
        return field
    }
    func updateNSView(_ field: CommandInputTextField, context: Context) {
        if field.stringValue != model.input { field.stringValue = model.input }
        if context.coordinator.focusVersion != model.focusVersion {
            context.coordinator.focusVersion = model.focusVersion
            field.requestKeyboardFocus()
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: QuickCommandModel
        let dismiss: () -> Void
        var focusVersion: Int?
        init(model: QuickCommandModel, dismiss: @escaping () -> Void) { self.model = model; self.dismiss = dismiss }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.input = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { model.submit(); return true }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) { dismiss(); return true }
            return false
        }
    }
}

private final class CommandInputTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { requestKeyboardFocus() }
    }
    func requestKeyboardFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            window.makeFirstResponder(self)
            if let editor = self.currentEditor() {
                editor.selectedRange = NSRange(location: (self.stringValue as NSString).length, length: 0)
            }
        }
    }
}

struct CommandPanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
