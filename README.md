# SwiftPipes

A modern macOS SSH tunnel manager built with Swift and SwiftUI, designed as a replacement for the discontinued Secure Pipes app.

## Features

- **Menu Bar App**: Lives in your menu bar with visual connection status indicator
- **SSH SOCKS Proxy**: Create SSH tunnels with dynamic port forwarding (SOCKS proxy)
- **Automatic Proxy Configuration**: Optionally configure system-wide SOCKS proxy settings
- **Multiple Connections**: Manage and quickly toggle between multiple SSH tunnel configurations
- **Identity File Support**: Use SSH key files or password authentication
- **Customizable**: Configure local bind address, ports, and host key checking
- **Server Keep-Alive**: Configurable ServerAliveInterval to prevent connection timeouts
- **Launch at Login**: Optional automatic startup when you log in
- **Notifications**: Optional notification center alerts for connection status changes
- **Secure Storage**: All passwords stored securely in macOS Keychain

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.4 or later (for building)

## Building

1. Open `SwiftPipes.xcodeproj` in Xcode
2. Select the SwiftPipes scheme
3. Build and Run (⌘R)

```bash
xcodebuild -project SwiftPipes.xcodeproj -scheme SwiftPipes -configuration Release build
```

## Testing

The project includes comprehensive unit tests for core functionality.

Run tests in Xcode with ⌘U or via command line:

```bash
xcodebuild test -project SwiftPipes.xcodeproj -scheme SwiftPipes -destination 'platform=macOS'
```

### Test Coverage

- **SSHTunnelTests**: Tests for the `SSHTunnel` data model
  - Initialization and default values
  - Codable encoding/decoding
  - Equatable and Identifiable conformance
  - Various configuration scenarios
  
- **SSHTunnelManagerTests**: Tests for the `SSHTunnelManager` class
  - Adding, updating, and deleting tunnels
  - Persistence across app restarts
  - Connection state management
  - Multiple tunnel handling

## Usage

### Adding a Connection

1. Click the menu bar icon
2. Select "Manage Connections..."
3. Click the + button
4. Configure your connection:
   - **Connection Name**: A friendly name for this connection
   - **SSH Server Address**: Hostname or IP of your SSH server
   - **Port**: SSH port (default: 22)
   - **SSH Username**: Your SSH username
   - **Password**: SSH password (if not using identity file)
   - **Local Bind Address**: Usually "localhost"
   - **Local Port**: Default 8158 (can be any available port)
   - **Auto-configure SOCKS proxy**: Automatically update system network settings
   - **Use SSH identity file**: Use an SSH key instead of password
   - **Strict Host Key Checking**: Enable/disable SSH host key verification
   - **Server Alive Interval**: Send keepalive packets every X seconds (default: 30)

### Preferences

Click "Preferences..." in the menu to access:

- **Launch at Login**: Automatically start SwiftPipes when you log in
- **Show Notifications**: Receive notifications when connections are established or disconnected

### Connecting/Disconnecting

1. Click the menu bar icon
2. Click on any connection name to toggle its state
3. A checkmark indicates an active connection
4. The menu bar icon changes when connections are active

### Editing or Deleting

Right-click (or Control+click) on a connection in the menu to edit or delete it.

## How It Works

SwiftPipes creates an SSH tunnel using the `ssh` command with dynamic port forwarding (`-D` flag), which creates a SOCKS proxy on your local machine. When "Automatically configure SOCKS proxy" is enabled, the app modifies macOS network settings to route all traffic through this tunnel.

## Security

SwiftPipes implements several security best practices:

- **Keychain Storage**: SSH passwords and admin passwords are stored securely in macOS Keychain, not in plain text
- **Access Controls**: Keychain items are marked as accessible only when device is unlocked (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **No Password Exposure**: Admin passwords are passed via stdin to avoid appearing in process listings
- **Shell Injection Prevention**: All command arguments are properly escaped and validated
- **Temporary Scripts**: Network configuration commands use temporary scripts with restricted permissions
- **SSH Key Support**: Supports SSH key-based authentication as a more secure alternative to passwords

### Security Notes

- **Admin Password**: You'll be prompted once for your administrator password to configure network settings. This is stored in Keychain and reused for subsequent connections.
- **SSH Passwords**: SSH passwords are stored per-connection in Keychain and never written to disk in plain text.
- **Keychain Access**: You can view or delete stored passwords using Keychain Access.app (search for "swiftpipes").

## Important Notes

- **System Network Settings**: When using automatic SOCKS proxy configuration, the app needs to modify system preferences. You may need to grant appropriate permissions.
- **Disconnection**: When you disconnect a tunnel with auto-proxy enabled, the SOCKS proxy is automatically disabled in system settings.
- **Persistence**: Connection configurations are saved automatically and persist across app restarts.

## Limitations

- Password authentication with SSH may require additional setup (consider using SSH keys)
- The app runs in the menu bar only (no dock icon)
- Requires the system `ssh` command to be available

## Future Enhancements

Potential features for future versions:
- Connection status monitoring with detailed logs
- Support for local port forwarding (specific ports)
- Import/export connection configurations
- Automatic reconnection on disconnect
- Connection groups/favorites

## License

This project is provided as-is for personal use.

## Credits

Inspired by the discontinued Secure Pipes/Pyro application by opoet.
