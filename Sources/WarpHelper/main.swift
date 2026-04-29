import Darwin
import Foundation

private let daemonPlistPath = "/Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist"
private let daemonProcessName = "CloudflareWARP"
private let daemonLabel = "com.cloudflare.1dot1dot1dot1.macos.warp.daemon"
private let socketPath = "/var/run/cloudflare-warp-helper.sock"

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

func processIsRunning(exactName: String) -> Bool {
    run("/usr/bin/pgrep", ["-x", exactName]).status == 0
}

func daemonIsLoaded() -> Bool {
    run("/bin/launchctl", ["print", "system/\(daemonLabel)"]).status == 0
}

func warpIsRunning() -> Bool {
    daemonIsLoaded() || processIsRunning(exactName: daemonProcessName)
}

func startWarpDaemon() throws {
    guard fileExists(daemonPlistPath) else {
        throw NSError(domain: "WarpHelper", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "The WARP daemon plist was not found at \(daemonPlistPath)."
        ])
    }

    let command = [
        "/bin/launchctl enable system/\(shellQuote(daemonLabel)) 2>/dev/null || true;",
        "/bin/launchctl bootstrap system \(shellQuote(daemonPlistPath)) 2>/dev/null",
        "|| /bin/launchctl load -w \(shellQuote(daemonPlistPath))",
        "|| true"
    ].joined(separator: " ")

    _ = run("/bin/sh", ["-c", command])

    if !warpIsRunning() {
        throw NSError(domain: "WarpHelper", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "The helper tried to start the WARP daemon, but it does not appear to be running."
        ])
    }
}

func stopWarpDaemon() throws {
    if fileExists(daemonPlistPath) {
        let command = [
            "(/bin/launchctl bootout system \(shellQuote(daemonPlistPath)) 2>/dev/null",
            "|| /bin/launchctl unload -w \(shellQuote(daemonPlistPath))",
            "|| /usr/bin/pkill -x \(shellQuote(daemonProcessName))",
            "|| true);",
            "/bin/launchctl disable system/\(shellQuote(daemonLabel)) 2>/dev/null || true"
        ].joined(separator: " ")

        _ = run("/bin/sh", ["-c", command])
    } else {
        _ = run("/usr/bin/pkill", ["-x", daemonProcessName])
    }

    if warpIsRunning() {
        throw NSError(domain: "WarpHelper", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "The helper tried to stop the WARP daemon, but it still appears to be running."
        ])
    }
}

func response(for command: String) -> String {
    do {
        switch command.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "status":
            return warpIsRunning() ? "OK running\n" : "OK stopped\n"
        case "start":
            try startWarpDaemon()
            return "OK started\n"
        case "stop":
            try stopWarpDaemon()
            return "OK stopped\n"
        default:
            return "ERR Unknown command.\n"
        }
    } catch {
        return "ERR \(error.localizedDescription)\n"
    }
}

func createServerSocket() throws -> Int32 {
    unlink(socketPath)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = Array(socketPath.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
        throw NSError(domain: "WarpHelper", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Helper socket path is too long."
        ])
    }

    withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
        for index in pathBytes.indices {
            rawBuffer[index] = pathBytes[index]
        }
        rawBuffer[pathBytes.count] = 0
    }

    let bindStatus = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard bindStatus == 0 else {
        close(fd)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }

    chmod(socketPath, 0o666)

    guard listen(fd, 8) == 0 else {
        close(fd)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }

    return fd
}

let serverSocket = try createServerSocket()

signal(SIGTERM) { _ in
    unlink(socketPath)
    exit(0)
}

while true {
    let client = accept(serverSocket, nil, nil)
    guard client >= 0 else {
        continue
    }

    var buffer = [UInt8](repeating: 0, count: 1024)
    let bytesRead = Darwin.read(client, &buffer, buffer.count)

    let reply: String
    if bytesRead > 0 {
        let command = String(decoding: buffer[0..<bytesRead], as: UTF8.self)
        reply = response(for: command)
    } else {
        reply = "ERR Empty command.\n"
    }

    let replyBytes = Array(reply.utf8)
    _ = replyBytes.withUnsafeBytes { Darwin.write(client, $0.baseAddress, replyBytes.count) }
    close(client)
}
