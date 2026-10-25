import SwiftUI
import AppKit

@MainActor final class FeatureController: ObservableObject {
    let commands = QuickCommandService()
    var content: AnyView { AnyView(QuickCommandsPage(service: commands, p: GrovePalette())) }
    func start() { if !CommandLine.arguments.contains("--no-shortcut") { commands.start() } }
    func stop() { commands.stop() }
    func refresh() { commands.shortcut.refresh() }
    func perform(_ action: String) async { if action == "panel" { commands.show() } }
    var summary: [String:String] { ["快捷键": commands.shortcut.active ? "监听中" : commands.shortcut.message, "翻译": "英文 → 简体中文 · 本机语言包"] }
}

extension FeatureController { var menuImage: NSImage? { nil } }

extension FeatureController { var previewContent: AnyView { content } }
