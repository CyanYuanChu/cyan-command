import SwiftUI

struct QuickCommandSettingsView: View {
    let service: QuickCommandService
    @ObservedObject var shortcut: GlobalShortcutManager
    var p: GrovePalette
    init(service: QuickCommandService, p: GrovePalette) {
        self.service = service; self.shortcut = service.shortcut; self.p = p
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("快速指令", systemImage: "command").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("右 ⌘ + 空格").font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 9).padding(.vertical, 5).background(p.soft, in: RoundedRectangle(cornerRadius: 6))
                Toggle("启用全局快捷键", isOn: $shortcut.enabled).labelsHidden().toggleStyle(.switch).tint(p.accent)
            }
            Text(shortcut.message).font(.system(size: 11)).foregroundStyle(shortcut.needsPermission ? .orange : p.secondary).lineSpacing(4)
            DisclosureGroup("快捷键诊断") {
                Text(shortcut.diagnostic).font(.system(size: 10, design: .monospaced)).foregroundStyle(p.secondary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }.font(.system(size: 10)).foregroundStyle(p.secondary)
            HStack(spacing: 12) {
                Button("打开快速指令") { service.show() }
                if shortcut.needsPermission {
                    Button("授权辅助功能") { shortcut.requestPermission(); shortcut.openPermissionSettings() }
                } else if shortcut.enabled && !shortcut.active {
                    Button("重试快捷键") { shortcut.start() }
                }
            }.font(.system(size: 11)).tint(p.accent)
            Text("输入 T: 后跟英文，回车译成简体中文。只识别唤起组合键，不记录键盘输入；翻译使用系统语言包，首次可能提示下载。")
                .font(.system(size: 10)).foregroundStyle(p.secondary).lineSpacing(5)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card, in: RoundedRectangle(cornerRadius: 18))
            .onAppear { shortcut.refresh() }
    }
}

struct QuickCommandsPage: View {
    let service: QuickCommandService
    var p: GrovePalette
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeading(eyebrow: "QUICK COMMANDS", title: "一句指令，随手完成。", subtitle: "右 Command＋空格唤起，输入 T: 执行英译中。")
            QuickCommandSettingsView(service: service, p: p)
            VStack(alignment: .leading, spacing: 16) {
                Label("翻译", systemImage: "text.bubble").font(.system(size: 17, weight: .medium))
                Text("T: Hello, world!").font(.system(size: 20, design: .monospaced)).textSelection(.enabled)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(p.hero, in: RoundedRectangle(cornerRadius: 12))
                Text("默认英文 → 简体中文。译文直接显示在输入框下方，可选中文字或点击复制。Esc 关闭；不会自动读取剪贴板。")
                    .font(.system(size: 12)).foregroundStyle(p.secondary).lineSpacing(5)
                Button("试试这个例子") { service.show(input: "T: Hello, world!") }.buttonStyle(.borderedProminent).tint(p.accent)
            }.padding(24).background(p.card, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
