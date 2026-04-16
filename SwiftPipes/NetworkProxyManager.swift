import Foundation
import SystemConfiguration
import Security

class NetworkProxyManager {
    private let keychainService = "com.swiftpipes.admin"
    private let keychainAccount = "admin-password"
    
    func enableSOCKSProxy(host: String, port: Int) {
        let services = getNetworkServices()
        print("Enabling SOCKS proxy for services: \(services)")
        
        // Build all commands at once to execute in a single sudo session
        var commands: [String] = []
        for service in services {
            let escaped = service.replacingOccurrences(of: "'", with: "'\\''")
            commands.append("/usr/sbin/networksetup -setsocksfirewallproxy '\(escaped)' '\(host)' '\(port)'")
            commands.append("/usr/sbin/networksetup -setsocksfirewallproxystate '\(escaped)' on")
        }
        
        if !commands.isEmpty {
            runCommandsBatch(commands)
        }
    }
    
    func disableSOCKSProxy() {
        let services = getNetworkServices()
        print("Disabling SOCKS proxy for services: \(services)")
        
        // Build all commands at once to execute in a single sudo session
        var commands: [String] = []
        for service in services {
            let escaped = service.replacingOccurrences(of: "'", with: "'\\''")
            commands.append("/usr/sbin/networksetup -setsocksfirewallproxystate '\(escaped)' off")
        }
        
        if !commands.isEmpty {
            runCommandsBatch(commands)
        }
    }
    
    private func getNetworkServices() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listallnetworkservices"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                return lines
                    .dropFirst()
                    .filter { !$0.isEmpty && !$0.hasPrefix("*") }
            }
        } catch {
            print("Failed to get network services: \(error)")
        }
        
        return []
    }
    
    private func runCommandsBatch(_ commands: [String]) {
        // Get password from keychain ONCE
        var password = KeychainHelper.shared.get(forKey: keychainAccount)
        
        // If no password, prompt for it (max 3 attempts)
        var attempts = 0
        while password == nil && attempts < 3 {
            password = promptForPassword()
            if let pwd = password {
                if KeychainHelper.shared.save(pwd, forKey: keychainAccount) {
                    break
                }
            }
            attempts += 1
        }
        
        guard let pwd = password else {
            print("No password provided after \(attempts) attempts")
            return
        }
        
        // Escape the password for shell
        let escapedPassword = pwd.replacingOccurrences(of: "'", with: "'\\''")
        
        // Combine all commands with &&
        let combinedCommand = commands.joined(separator: " && ")
        
        // Escape the combined command for nested shell
        let escapedCommand = combinedCommand.replacingOccurrences(of: "'", with: "'\\''")
        
        // Use printf instead of echo to avoid issues with special characters
        let fullCommand = "printf '%s\\n' '\(escapedPassword)' | sudo -S sh -c '\(escapedCommand)'"
        
        // Use sudo with password via stdin - SINGLE execution
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        task.arguments = ["-c", fullCommand]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                print("Successfully configured network proxy")
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
                    // Filter out just the "Password:" prompt from stderr
                    let filteredError = error.components(separatedBy: .newlines)
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "Password:" }
                        .joined(separator: "\n")
                    
                    if !filteredError.isEmpty {
                        print("Network configuration failed")
                    }
                    
                    if error.contains("Sorry, try again") || error.contains("incorrect password") {
                        _ = KeychainHelper.shared.delete(forKey: keychainAccount)
                        // Try again with iteration instead of recursion
                        var retryPassword: String?
                        var retryAttempts = 0
                        while retryAttempts < 2 {
                            retryPassword = promptForPassword()
                            if let pwd = retryPassword {
                                if KeychainHelper.shared.save(pwd, forKey: keychainAccount) {
                                    runCommandsBatch(commands)
                                    return
                                }
                            }
                            retryAttempts += 1
                        }
                    }
                }
            }
        } catch {
            print("Failed to execute network configuration")
        }
    }
    
    private func promptForPassword() -> String? {
        let script = """
        display dialog "SwiftPipes needs your administrator password to configure network settings. Your password will be saved securely in Keychain." default answer "" with title "Administrator Password Required" with icon caution with hidden answer
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if var result = String(data: data, encoding: .utf8) {
                    if let range = result.range(of: "text returned:") {
                        result = String(result[range.upperBound...])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return result
                    }
                }
            }
        } catch {
            print("Failed to prompt for password: \(error)")
        }
        
        return nil
    }
}
