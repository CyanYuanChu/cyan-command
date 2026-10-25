import Foundation
import AppKit

struct TranslationCommand: Equatable {
    let text: String
    static func parse(_ input: String) throws -> Self {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { throw GroveError.message("输入 T: 加上英文内容，按回车翻译。") }
        let prefix = String(clean.prefix(2)).lowercased()
        guard prefix == "t:" || prefix == "t：" else {
            throw GroveError.message("暂时支持 T: 翻译指令，例如 T: Hello, world!")
        }
        let text = String(clean.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GroveError.message("请在 T: 后输入要翻译的英文。") }
        guard text.count <= 5_000 else { throw GroveError.message("一次最多翻译 5,000 个字符，请分段输入。") }
        return Self(text: text)
    }
}

struct CommandTranslationRequest: Equatable {
    let id: UUID
    let text: String
}

@MainActor final class QuickCommandModel: ObservableObject {
    @Published var input = "" {
        didSet {
            if input != oldValue {
                request = nil; output = ""; error = nil; working = false; copied = false
            }
        }
    }
    @Published private(set) var request: CommandTranslationRequest?
    @Published private(set) var output = ""
    @Published private(set) var error: String?
    @Published private(set) var working = false
    @Published private(set) var copied = false
    @Published private(set) var statusText = "正在准备系统翻译…"
    @Published var focusVersion = 0

    func submit() {
        guard !working else { return }
        do {
            let command = try TranslationCommand.parse(input)
            error = nil; output = ""; copied = false; working = true; statusText = "正在准备系统翻译…"
            request = CommandTranslationRequest(id: UUID(), text: command.text)
        } catch { self.error = error.localizedDescription }
    }
    func setPhase(id: UUID, text: String) { if request?.id == id { statusText = text } }
    func complete(id: UUID, output: String) {
        guard request?.id == id else { return }
        self.output = output; working = false; error = nil
    }
    func fail(id: UUID, message: String) {
        guard request?.id == id else { return }
        error = message; working = false
    }
    func cancel() { request = nil; working = false }
    func copyResult() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        copied = true
    }
}

@MainActor final class QuickCommandService {
    let model = QuickCommandModel()
    let shortcut = GlobalShortcutManager()
    lazy var panel = CommandPanelController(model: model)
    func start() {
        shortcut.onTrigger = { [weak self] in self?.panel.toggle() }
        shortcut.start()
    }
    func stop() { shortcut.stop(); model.cancel() }
    func show(input: String? = nil) {
        if let input { model.input = input }
        panel.show()
    }
}
