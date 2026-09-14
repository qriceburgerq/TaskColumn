import Foundation
import AppKit
import Carbon

public struct HotkeyOption: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let keyCode: UInt32
    
    public init(name: String, keyCode: UInt32) {
        self.id = name
        self.name = name
        self.keyCode = keyCode
    }
}

public class HotkeyManager: ObservableObject {
    public static let shared = HotkeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    public var onHotKeyTriggered: (() -> Void)?
    
    // Configurable keys
    public static let availableKeys: [HotkeyOption] = [
        HotkeyOption(name: "A", keyCode: 0x00),
        HotkeyOption(name: "B", keyCode: 0x0B),
        HotkeyOption(name: "C", keyCode: 0x08),
        HotkeyOption(name: "D", keyCode: 0x02),
        HotkeyOption(name: "E", keyCode: 0x0E),
        HotkeyOption(name: "F", keyCode: 0x03),
        HotkeyOption(name: "G", keyCode: 0x05),
        HotkeyOption(name: "K", keyCode: 0x28),
        HotkeyOption(name: "N", keyCode: 0x2D),
        HotkeyOption(name: "T", keyCode: 0x11),
        HotkeyOption(name: "Space (空白鍵)", keyCode: 0x31)
    ]
    
    @Published public var useCommand: Bool {
        didSet { UserDefaults.standard.set(useCommand, forKey: "hk_use_cmd"); reRegister() }
    }
    @Published public var useOption: Bool {
        didSet { UserDefaults.standard.set(useOption, forKey: "hk_use_opt"); reRegister() }
    }
    @Published public var useShift: Bool {
        didSet { UserDefaults.standard.set(useShift, forKey: "hk_use_shift"); reRegister() }
    }
    @Published public var useControl: Bool {
        didSet { UserDefaults.standard.set(useControl, forKey: "hk_use_ctrl"); reRegister() }
    }
    @Published public var selectedKeyName: String {
        didSet { UserDefaults.standard.set(selectedKeyName, forKey: "hk_key_name"); reRegister() }
    }
    
    private init() {
        if UserDefaults.standard.object(forKey: "hk_use_cmd") == nil {
            self.useCommand = true
            self.useShift = true
            self.useOption = false
            self.useControl = false
            self.selectedKeyName = "A"
        } else {
            self.useCommand = UserDefaults.standard.bool(forKey: "hk_use_cmd")
            self.useOption = UserDefaults.standard.bool(forKey: "hk_use_opt")
            self.useShift = UserDefaults.standard.bool(forKey: "hk_use_shift")
            self.useControl = UserDefaults.standard.bool(forKey: "hk_use_ctrl")
            self.selectedKeyName = UserDefaults.standard.string(forKey: "hk_key_name") ?? "A"
        }
        
        setupCarbonHandler()
    }
    
    public var currentDisplayString: String {
        var parts: [String] = []
        if useControl { parts.append("⌃ Control") }
        if useOption { parts.append("⌥ Option") }
        if useShift { parts.append("⇧ Shift") }
        if useCommand { parts.append("⌘ Command") }
        parts.append(selectedKeyName)
        return parts.joined(separator: " + ")
    }
    
    private func setupCarbonHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onHotKeyTriggered?()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            nil
        )
    }
    
    public func reRegister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        
        var modifiers: UInt32 = 0
        if useCommand { modifiers |= UInt32(cmdKey) }
        if useShift { modifiers |= UInt32(shiftKey) }
        if useOption { modifiers |= UInt32(optionKey) }
        if useControl { modifiers |= UInt32(controlKey) }
        
        guard modifiers != 0 else { return }
        
        let keyCode = HotkeyManager.availableKeys.first(where: { $0.name == selectedKeyName })?.keyCode ?? 0x00
        let hotKeyID = EventHotKeyID(signature: OSType(0x544F444F), id: 1)
        
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("Failed to register custom hotkey: \(status)")
        } else {
            print("Successfully registered hotkey: \(currentDisplayString)")
        }
    }
}
