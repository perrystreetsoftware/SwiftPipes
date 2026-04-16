# SwiftPipes Feature Summary

## Core Features
✅ SSH tunnel management with SOCKS proxy
✅ Multiple connection profiles
✅ Menu bar integration with status indicator
✅ Automatic system SOCKS proxy configuration
✅ SSH key and password authentication
✅ Connection state persistence

## Security Features
✅ All passwords stored in macOS Keychain
✅ Keychain access controls (unlock-only)
✅ No passwords in process arguments
✅ Shell injection prevention
✅ Secure admin password caching
✅ Automatic cleanup on connection deletion

## Advanced Features
✅ ServerAliveInterval configuration (keepalive)
✅ Strict host key checking option
✅ Custom local bind address and port
✅ Port conflict detection
✅ Multiple simultaneous connections

## User Experience
✅ Launch at login option
✅ Notification Center integration
✅ Connection status notifications
✅ Context menu for quick actions
✅ Manage Connections window
✅ Preferences panel
✅ Clean disconnect on quit

## Architecture
✅ SwiftUI-based interface
✅ Comprehensive test suite (19 tests)
✅ Clean separation of concerns
✅ Observable patterns for state management

## Menu Structure
```
☁️ Cloud Icon (filled when connected)
├── Connection 1 [●]
├── Connection 2 [○]
├── ──────────────
├── Manage Connections...
├── Preferences...
├── ──────────────
└── Quit SwiftPipes
```

## Preferences
- Launch at Login
- Show Notifications

## Connection Settings
- Connection Name
- SSH Server Address
- Port (default: 22)
- Username
- Password (Keychain)
- Local Bind Address (default: localhost)
- Local Port (default: 8158)
- Auto-configure SOCKS proxy (checkbox)
- Use SSH identity file (checkbox)
- Strict Host Key Checking (checkbox)
- Server Alive Interval (default: 30 seconds)
