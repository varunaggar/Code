import SwiftUI
import AppKit

final class ClickerViewModel: ObservableObject {
    @Published var interval: Double = 0.1
    @Published var count: Int = 0
    @Published var delay: Double = 0.0
    @Published var startMode: StartMode = .immediate
    @Published var button: MouseButton = .left
    @Published var isRunning: Bool = false
    @Published var isAccessibilityGranted: Bool = AccessibilityHelper.isTrusted()

    private let clicker = AutoClicker()
    private let hotkeys = HotKeyManager()
    private var startAfterClickMonitor: Any?

    init() {
        hotkeys.onStart = { [weak self] in self?.start() }
        hotkeys.onStop = { [weak self] in self?.stop() }
        hotkeys.registerDefaults()
    }

    func promptAccessibility() {
        AccessibilityHelper.promptForTrust()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isAccessibilityGranted = AccessibilityHelper.isTrusted()
        }
    }

    func start() {
        guard AccessibilityHelper.isTrusted() else {
            promptAccessibility()
            return
        }

        if isRunning { return }

        switch startMode {
        case .immediate:
            startClicker()
        case .delayed:
            let d = max(0.0, delay)
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                self?.startClicker()
            }
        case .afterFirstClick:
            armForFirstPhysicalClick()
        }
    }

    func stop() {
        if let token = startAfterClickMonitor {
            NSEvent.removeMonitor(token)
            startAfterClickMonitor = nil
        }
        clicker.stop()
        isRunning = false
    }

    private func startClicker() {
        clicker.start(interval: interval, count: count, button: button)
        isRunning = true
    }

    private func armForFirstPhysicalClick() {
        if startAfterClickMonitor != nil { return }
        startAfterClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            if let token = self.startAfterClickMonitor {
                NSEvent.removeMonitor(token)
                self.startAfterClickMonitor = nil
            }
            self.startClicker()
        }
    }
}

enum StartMode: String, CaseIterable, Identifiable {
    case immediate
    case delayed
    case afterFirstClick

    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var vm: ClickerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("macOS Auto-Clicker").font(.title2).bold()

            Group {
                HStack {
                    Text("Interval (s)")
                    Spacer()
                    TextField("0.1", value: $vm.interval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                HStack {
                    Text("Count (0=infinite)")
                    Spacer()
                    TextField("0", value: $vm.count, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                HStack {
                    Text("Button")
                    Spacer()
                    Picker("Button", selection: $vm.button) {
                        ForEach(MouseButton.allCases) { b in
                            Text(b.displayName).tag(b)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            Divider()

            VStack(alignment: .leading) {
                Text("Start Mode").bold()
                Picker("Start Mode", selection: $vm.startMode) {
                    Text("Immediate").tag(StartMode.immediate)
                    Text("Delayed").tag(StartMode.delayed)
                    Text("After First Click").tag(StartMode.afterFirstClick)
                }
                .pickerStyle(.segmented)

                if vm.startMode == .delayed {
                    HStack {
                        Text("Delay (s)")
                        Spacer()
                        TextField("2.0", value: $vm.delay, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Hotkeys").bold()
                Text("Start: ⌘⌥S    •    Stop: ⌘⌥X")
                    .font(.system(.body, design: .monospaced))
            }

            HStack(spacing: 12) {
                Button(action: vm.start) {
                    Label("Start", systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isRunning)

                Button(action: vm.stop) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!vm.isRunning)
            }

            HStack {
                Circle()
                    .fill(vm.isRunning ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(vm.isRunning ? "Running" : "Idle")
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: vm.isAccessibilityGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(vm.isAccessibilityGranted ? .green : .orange)
                Text(vm.isAccessibilityGranted ? "Accessibility enabled" : "Accessibility required for clicking/hotkeys")
                Spacer()
                if !vm.isAccessibilityGranted {
                    Button("Enable…", action: vm.promptAccessibility)
                }
            }

        }
        .padding(16)
        .frame(width: 460)
    }
}
