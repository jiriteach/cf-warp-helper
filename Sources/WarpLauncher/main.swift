import AppKit
import Darwin
import Foundation

private let appPath = "/Applications/Cloudflare WARP.app"
private let appName = "Cloudflare WARP"
private let guiProcessName = "Cloudflare WARP"
private let socketPath = "/var/run/cloudflare-warp-helper.sock"
private let downloadURL = URL(string: "https://downloads.cloudflareclient.com/v1/download/macos/ga")!
private let helperLabel = "local.cloudflare-warp-helper"
private let helperInstallPath = "/Library/PrivilegedHelperTools/local.cloudflare-warp-helper"
private let helperPlistPath = "/Library/LaunchDaemons/local.cloudflare-warp-helper.plist"
private let oldHelperInstallPath = "/Library/PrivilegedHelperTools/local.cloudflare-warp-toggle.helper"
private let oldHelperPlistPath = "/Library/LaunchDaemons/local.cloudflare-warp-toggle.helper.plist"
private let oldHelperSocketPath = "/var/run/cloudflare-warp-toggle.sock"

struct CommandResult {
    let status: Int32
    let output: String
    let error: String
}

@discardableResult
func run(_ executable: String, _ arguments: [String] = []) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return CommandResult(status: 127, output: "", error: error.localizedDescription)
    }

    return CommandResult(
        status: process.terminationStatus,
        output: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
        error: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    )
}

func fileExists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func appleScriptQuote(_ value: String) -> String {
    "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n") + "\""
}

@discardableResult
func runAsAdministrator(_ command: String) -> CommandResult {
    let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
    return run("/usr/bin/osascript", ["-e", script])
}

func installedWarpVersion() -> String? {
    guard
        let bundle = Bundle(url: URL(fileURLWithPath: appPath)),
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        !version.isEmpty
    else {
        return nil
    }

    return version
}

func processIsRunning(exactName: String) -> Bool {
    run("/usr/bin/pgrep", ["-x", exactName]).status == 0
}

func helperRequest(_ command: String) throws -> String {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw NSError(domain: "WarpLauncher", code: 10, userInfo: [
            NSLocalizedDescriptionKey: "Could not create a helper connection."
        ])
    }
    defer { close(fd) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = Array(socketPath.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
        throw NSError(domain: "WarpLauncher", code: 11, userInfo: [
            NSLocalizedDescriptionKey: "Helper socket path is too long."
        ])
    }

    withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
        for index in pathBytes.indices {
            rawBuffer[index] = pathBytes[index]
        }
        rawBuffer[pathBytes.count] = 0
    }

    let connectStatus = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard connectStatus == 0 else {
        throw NSError(domain: "WarpLauncher", code: 12, userInfo: [
            NSLocalizedDescriptionKey: "The privileged helper is not running. Run ./install-helper.sh once, then open this launcher again."
        ])
    }

    let request = command + "\n"
    let requestBytes = Array(request.utf8)
    let sent = requestBytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, requestBytes.count) }
    guard sent == requestBytes.count else {
        throw NSError(domain: "WarpLauncher", code: 13, userInfo: [
            NSLocalizedDescriptionKey: "Could not send the command to the privileged helper."
        ])
    }

    var response = [UInt8](repeating: 0, count: 4096)
    let received = Darwin.read(fd, &response, response.count)
    guard received > 0 else {
        throw NSError(domain: "WarpLauncher", code: 14, userInfo: [
            NSLocalizedDescriptionKey: "The privileged helper did not return a response."
        ])
    }

    let message = String(decoding: response[0..<received], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    if message.hasPrefix("OK") {
        return message
    }

    let detail = message.replacingOccurrences(of: "ERR ", with: "")
    throw NSError(domain: "WarpLauncher", code: 15, userInfo: [
        NSLocalizedDescriptionKey: detail.isEmpty ? "The privileged helper failed." : detail
    ])
}

func helperSaysWarpIsRunning() -> Bool {
    (try? helperRequest("status")) == "OK running"
}

func helperIsInstalledAndRunning() -> Bool {
    (try? helperRequest("status")) != nil
}

func installHelper() throws {
    guard let helperSource = Bundle.main.path(forResource: "cloudflare-warp-helper", ofType: nil) else {
        throw NSError(domain: "WarpLauncher", code: 20, userInfo: [
            NSLocalizedDescriptionKey: "The bundled helper could not be found."
        ])
    }

    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>\(helperLabel)</string>
      <key>ProgramArguments</key>
      <array>
        <string>\(helperInstallPath)</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <true/>
      <key>StandardOutPath</key>
      <string>/var/log/cloudflare-warp-helper.log</string>
      <key>StandardErrorPath</key>
      <string>/var/log/cloudflare-warp-helper.log</string>
    </dict>
    </plist>
    """

    let command = """
    set -e
    /usr/bin/install -o root -g wheel -m 755 \(shellQuote(helperSource)) \(shellQuote(helperInstallPath))
    /bin/cat > \(shellQuote(helperPlistPath)) <<'PLIST'
    \(plist)
    PLIST
    /usr/sbin/chown root:wheel \(shellQuote(helperPlistPath))
    /bin/chmod 644 \(shellQuote(helperPlistPath))
    /bin/launchctl bootout system \(shellQuote(helperPlistPath)) 2>/dev/null || true
    /bin/launchctl bootstrap system \(shellQuote(helperPlistPath))
    /bin/launchctl bootout system \(shellQuote(oldHelperPlistPath)) 2>/dev/null || true
    /bin/rm -f \(shellQuote(oldHelperPlistPath)) \(shellQuote(oldHelperInstallPath)) \(shellQuote(oldHelperSocketPath))
    /bin/launchctl enable system/\(helperLabel)
    /bin/launchctl kickstart -k system/\(helperLabel)
    """

    let result = runAsAdministrator(command)
    guard result.status == 0 else {
        throw NSError(domain: "WarpLauncher", code: Int(result.status), userInfo: [
            NSLocalizedDescriptionKey: "Could not install the privileged helper.\n\n\(result.error)\(result.output)"
        ])
    }

    for _ in 0..<20 {
        if helperIsInstalledAndRunning() {
            return
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    throw NSError(domain: "WarpLauncher", code: 21, userInfo: [
        NSLocalizedDescriptionKey: "The helper was installed, but it did not start responding."
    ])
}

func startWarp() throws {
    guard fileExists(appPath) else {
        throw NSError(domain: "WarpLauncher", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "\(appName) was not found at \(appPath)."
        ])
    }

    _ = try helperRequest("start")

    let openResult = run("/usr/bin/open", [appPath])
    guard openResult.status == 0 else {
        throw NSError(domain: "WarpLauncher", code: Int(openResult.status), userInfo: [
            NSLocalizedDescriptionKey: "Could not open \(appName).\n\n\(openResult.error)\(openResult.output)"
        ])
    }
}

func stopWarp() throws {
    _ = run("/usr/bin/pkill", ["-x", guiProcessName])
    _ = try helperRequest("stop")
}

final class StatusWindowController: NSWindowController {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "Install", target: nil, action: nil)
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)
    private let buttonStack = NSStackView()
    private var actionHandler: (() -> Void)?

    init(message: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        window.title = "Cloudflare WARP"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        if let iconPath = Bundle.main.path(forResource: "applicationIcon", ofType: "icns") {
            iconView.image = NSImage(contentsOfFile: iconPath)
        } else {
            iconView.image = NSApp.applicationIconImage
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.stringValue = message
        label.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        label.alignment = .center
        label.isSelectable = true
        label.allowsEditingTextAttributes = true
        label.translatesAutoresizingMaskIntoConstraints = false

        actionButton.bezelStyle = .rounded
        actionButton.isHidden = true
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        closeButton.bezelStyle = .rounded
        closeButton.isHidden = true
        closeButton.target = NSApp
        closeButton.action = #selector(NSApplication.terminate(_:))
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .gravityAreas
        buttonStack.spacing = 12
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.addArrangedSubview(actionButton)
        buttonStack.addArrangedSubview(closeButton)

        let contentView = NSView()
        contentView.addSubview(iconView)
        contentView.addSubview(label)
        contentView.addSubview(buttonStack)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 32),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            buttonStack.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 34),
            buttonStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            buttonStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])

        super.init(window: window)

        actionButton.target = self
        actionButton.action = #selector(runPrimaryAction(_:))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ title: String) {
        window?.title = title
    }

    func setStatus(_ status: String) {
        label.stringValue = status
        label.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        label.alignment = .center
        label.textColor = .labelColor
        actionButton.isHidden = true
        closeButton.isHidden = true
    }

    func showNotInstalled() {
        let text = "Not Installed - Download"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        let linkRange = (text as NSString).range(of: "Download")
        attributedText.addAttributes([
            .link: downloadURL,
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ], range: linkRange)

        label.alignment = .center
        label.attributedStringValue = attributedText
        actionButton.isHidden = true
        closeButton.isHidden = false
    }

    func showHelperNotInstalled(onInstall: @escaping () -> Void) {
        actionHandler = onInstall
        setStatus("Helper Not Installed - Install?")
        actionButton.title = "Install"
        actionButton.isHidden = false
        closeButton.isHidden = false
    }

    func setControlsEnabled(_ enabled: Bool) {
        actionButton.isEnabled = enabled
        closeButton.isEnabled = enabled
    }

    @objc private func runPrimaryAction(_ sender: NSButton) {
        actionHandler?()
    }
}

func showError(_ message: String) {
    let app = NSApplication.shared
    app.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "Cloudflare WARP Launcher Error"
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let windowController = StatusWindowController(message: "Checking ...")

windowController.showWindow(nil)
app.activate(ignoringOtherApps: true)

func finishAfterTwoSeconds(from startTime: Date, errorMessage: String?) {
    let elapsed = Date().timeIntervalSince(startTime)
    let remaining = max(0, 2.0 - elapsed)

    DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
        if let errorMessage {
            showError(errorMessage)
        }
        app.terminate(nil)
    }
}

func promptForHelperInstall() {
    DispatchQueue.main.async {
        windowController.showHelperNotInstalled {
            windowController.setControlsEnabled(false)
            windowController.setStatus("Installing Helper ...")

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try installHelper()
                    DispatchQueue.main.async {
                        windowController.setControlsEnabled(true)
                    }
                    runToggleFlow()
                } catch {
                    DispatchQueue.main.async {
                        showError(error.localizedDescription)
                        windowController.setControlsEnabled(true)
                        promptForHelperInstall()
                    }
                }
            }
        }
    }
}

func runToggleFlow() {
    DispatchQueue.global(qos: .userInitiated).async {
        DispatchQueue.main.async {
            windowController.setStatus("Checking ...")
        }

    guard fileExists(appPath) else {
        DispatchQueue.main.async {
            windowController.showNotInstalled()
        }
        return
    }

    let version = installedWarpVersion()
    let title = version.map { "\(appName) - \($0)" } ?? appName

    DispatchQueue.main.async {
        windowController.setTitle(title)
    }

    guard helperIsInstalledAndRunning() else {
        promptForHelperInstall()
        return
    }

    let shouldClose = helperSaysWarpIsRunning() || processIsRunning(exactName: guiProcessName)
    let startTime = Date()

    DispatchQueue.main.async {
        windowController.setStatus(shouldClose ? "Closing ..." : "Launching ...")
    }

    let operationError: String?

    do {
        if shouldClose {
            try stopWarp()
        } else {
            try startWarp()
        }
        operationError = nil
    } catch {
        operationError = error.localizedDescription
    }

        finishAfterTwoSeconds(from: startTime, errorMessage: operationError)
    }
}

runToggleFlow()

app.run()
