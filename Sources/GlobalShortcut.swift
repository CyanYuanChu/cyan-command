import AppKit
import ApplicationServices
import Combine

// Device-specific Command flags from IOKit/hidsystem/IOLLEvent.h.
enum RightCommandShortcut {
    static let rightCommand: UInt64 = 0x10
    static let leftCommand: UInt64 = 0x08
    static func resolvedFlags(raw: UInt64, rightDown: Bool, leftDown: Bool) -> UInt64 {
        // Device flags identify the side of this event. Never combine them with
        // CGEventSource.keyState: modifier state there can report both key codes
        // as down when only one physical Command key is held.
        if raw & (rightCommand | leftCommand) != 0 { return raw }
        guard rightDown || leftDown else { return raw }
        var flags = raw & ~(rightCommand | leftCommand)
        if rightDown { flags |= rightCommand }
        if leftDown { flags |= leftCommand }
        return flags | CGEventFlags.maskCommand.rawValue
    }
    static func matches(keyCode: Int64, flags: UInt64) -> Bool {
        let blocked = CGEventFlags.maskShift.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
        return keyCode == 49 && flags & rightCommand != 0 && flags & leftCommand == 0
            && flags & CGEventFlags.maskCommand.rawValue != 0 && flags & blocked == 0
    }
}

private let quickCommandTapCallback: CGEventTapCallBack = { _, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    // The tap source is installed exclusively on the main run loop.
    return MainActor.assumeIsolated {
        Unmanaged<GlobalShortcutManager>.fromOpaque(context).takeUnretainedValue().handle(type: type, event: event)
    }
}

@MainActor final class GlobalShortcutManager: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "cyan.command.shortcut")
            if enabled { start() } else { stop(); message = "快捷键已关闭，仍可从菜单栏打开快速指令。" }
        }
    }
    @Published private(set) var active = false
    @Published private(set) var needsPermission = false
    @Published private(set) var message = ""
    @Published private(set) var diagnostic = "等待 Command＋空格。仅显示组合键状态，不记录输入内容。"
    private var triggerCount = 0
    var onTrigger: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var capturedSpace = false
    private var rightCommandDown = false
    private var leftCommandDown = false
    private var notifications = Set<AnyCancellable>()

    init() {
        enabled = UserDefaults.standard.object(forKey: "cyan.command.shortcut") as? Bool ?? true
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }.store(in: &notifications)
    }
    func start() {
        guard enabled else { return }
        refresh()
        if tap == nil && permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }
    func refresh() {
        guard enabled else { return }
        guard AXIsProcessTrusted() else {
            removeTap(); needsPermission = true
            message = "需要辅助功能权限，才能全局识别右 Command＋空格并避免同时触发系统聚焦。"
            return
        }
        needsPermission = false
        if let tap, CFMachPortIsValid(tap) {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            active = CGEvent.tapIsEnabled(tap: tap)
            return
        }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue) | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        // Observe before macOS resolves symbolic shortcuts such as Command-Space.
        // A session tap can receive Command flags while Space is already consumed.
        guard let newTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: quickCommandTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            active = false; message = "快捷键监听尚未启动，请检查辅助功能权限后重试。"
            return
        }
        tap = newTap
        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        active = CGEvent.tapIsEnabled(tap: newTap)
        message = active ? "右 ⌘＋空格 · 已启用；左 Command＋空格保留给系统。" : "快捷键监听不可用，请重试。"
        permissionTimer?.invalidate(); permissionTimer = nil
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        start()
    }
    func openPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func stop() {
        permissionTimer?.invalidate(); permissionTimer = nil; removeTap()
    }
    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; active = false; capturedSpace = false; rightCommandDown = false; leftCommandDown = false
    }
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, enabled && AXIsProcessTrusted() { CGEvent.tapEnable(tap: tap, enable: true) }
            DispatchQueue.main.async { [weak self] in self?.diagnostic = "系统暂停了监听，已请求恢复。" }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged {
            if !event.flags.contains(.maskCommand) {
                rightCommandDown = false; leftCommandDown = false
            } else if event.flags.rawValue & (RightCommandShortcut.rightCommand | RightCommandShortcut.leftCommand) != 0 {
                rightCommandDown = event.flags.rawValue & RightCommandShortcut.rightCommand != 0
                leftCommandDown = event.flags.rawValue & RightCommandShortcut.leftCommand != 0
            } else if code == 54 {
                rightCommandDown.toggle()
            } else if code == 55 {
                leftCommandDown.toggle()
            }
            return Unmanaged.passUnretained(event)
        }
        let flags = RightCommandShortcut.resolvedFlags(raw: event.flags.rawValue,
            rightDown: rightCommandDown, leftDown: leftCommandDown)
        if type == .keyDown && code == 49 && event.flags.contains(.maskCommand) {
            let description = "原始标记 \(String(event.flags.rawValue, radix: 16))，识别标记 \(String(flags, radix: 16))，右键组合 \(RightCommandShortcut.matches(keyCode: code, flags: flags))"
            DispatchQueue.main.async { [weak self] in self?.diagnostic = description }
        }
        if type == .keyUp && code == 49 && capturedSpace {
            capturedSpace = false
            return nil
        }
        guard enabled && type == .keyDown,
              RightCommandShortcut.matches(keyCode: code, flags: flags) else {
            return Unmanaged.passUnretained(event)
        }
        if !capturedSpace && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            capturedSpace = true
            triggerCount += 1
            let count = triggerCount
            // Never open a window while the event tap is blocking the keyboard stream.
            DispatchQueue.main.async { [weak self] in
                self?.diagnostic = "已触发快速指令 \(count) 次。"
                self?.onTrigger?()
            }
        }
        return nil
    }
}
