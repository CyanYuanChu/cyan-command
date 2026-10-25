import Foundation
import AppKit
@MainActor enum FeatureChecks {
    static func run() async {
        var failed = 0
        func check(_ condition: Bool, _ name: String) { print((condition ? "PASS " : "FAIL ") + name); if !condition { failed += 1 } }
        check(ModuleMetadata.value["protocolVersion"] as? Int == 1, "module protocol metadata")
        check(!ModuleMetadata.id.contains("/"), "stable module identity")
        check(FileManager.default.fileExists(atPath: Bundle.main.resourcePath! + "/module.json"), "standalone manifest bundled")
        check((try? TranslationCommand.parse("T: Hello"))?.text == "Hello", "translation command")
        check((try? TranslationCommand.parse("rm: anything")) == nil, "unknown command rejected")
        check((try? TranslationCommand.parse("T: " + String(repeating: "x", count: 5001))) == nil, "translation length bounded")
        check(RightCommandShortcut.matches(keyCode: 49, flags: CGEventFlags.maskCommand.rawValue | RightCommandShortcut.rightCommand), "right Command shortcut")
        check(!RightCommandShortcut.matches(keyCode: 49, flags: CGEventFlags.maskCommand.rawValue | RightCommandShortcut.leftCommand), "left Command preserved")
        let model = QuickCommandModel(); model.input = "T: first"; model.submit(); let old = model.request!.id
        model.input = "T: second"; model.complete(id: old, output: "stale"); check(model.output.isEmpty, "stale translation discarded")
        print("MODULE_TESTS \(failed == 0 ? "OK" : "FAILED")")
        if failed > 0 { exit(1) }
    }
}
