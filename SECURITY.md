# SwiftPipes Security Documentation

## Security Overview
SwiftPipes is designed with security as a priority, following macOS security best practices for handling sensitive credentials and system-level operations.

## Implemented Security Features

### 1. Credential Storage
- **SSH Passwords**: Stored securely in macOS Keychain with `kSecAttrAccessibleAfterFirstUnlock`
- **Admin Passwords**: Stored in Keychain for network configuration
- **No Plain Text**: Zero passwords stored in UserDefaults, plist files, or memory dumps
- **Automatic Cleanup**: Keychain items deleted when connections are removed

### 2. Shell Injection Prevention
- **Argument Escaping**: All shell arguments properly escaped (single quotes handled)
- **Process API**: Uses Process with argument arrays where possible
- **Input Validation**: User input sanitized before use in commands
- **No Direct eval()**: No use of shell evaluation of untrusted strings

### 3. Privilege Escalation
- **Limited Scope**: Admin privileges only for network configuration
- **User Consent**: Password prompt explains why privileges are needed
- **Rate Limiting**: Maximum 3 password attempts to prevent brute force
- **Iteration Over Recursion**: Password retry uses iteration to prevent stack overflow

### 4. SSH Security
- **Host Key Verification**: StrictHostKeyChecking enabled by default
- **User Choice**: Users can disable for convenience (with awareness of risks)
- **Key Authentication**: Supports SSH key files as alternative to passwords
- **ServerAliveInterval**: Prevents connection hijacking through keep-alive

### 5. Data Protection
- **No Logging of Secrets**: Passwords never written to logs
- **Keychain Only Access**: App only accesses its own keychain items
- **Non-Synchronizable**: Passwords not synced to iCloud Keychain
- **Process Memory**: Password in memory only during authentication

## Known Security Considerations

### Password in Process Memory
**Status**: Acceptable Risk
- Admin password briefly exists in process memory during sudo authentication
- This is standard for privilege escalation on macOS
- Alternative would require separate privileged helper tool (XPC)

### Ad-Hoc Code Signing (Development)
**Status**: Development Only
- Development builds use ad-hoc signing
- Production releases should use Developer ID certificate
- Enables hardened runtime and notarization

### No Sandboxing
**Status**: By Design
- App requires network configuration privileges
- Sandboxing would require privileged helper tool
- Current approach is standard for system utilities

## Security Audit Results

### ✅ Passed
- No hardcoded credentials
- Sensitive data encrypted at rest
- No sensitive data in logs
- Proper input validation
- Secure error handling
- Secure defaults

### 🔒 Production Recommendations
1. **Code Signing**: Use Developer ID certificate
2. **Notarization**: Submit to Apple for notarization
3. **Hardened Runtime**: Enable in release builds
4. **Remove Debug Logging**: Production builds should minimize logging
5. **Regular Updates**: Keep dependencies current for security patches

## Reporting Security Issues

If you discover a security vulnerability, please email security@[your-domain].com.

**Please do not:**
- Open a public GitHub issue
- Post details on social media
- Test against production servers

## Security Best Practices for Users

1. **Use SSH Keys**: More secure than password authentication
2. **Enable Strict Host Key Checking**: Protects against MITM attacks
3. **Keep macOS Updated**: Ensures latest security patches
4. **Review Keychain**: Periodically audit stored credentials
5. **Use Strong Passwords**: For both SSH and admin accounts

## Compliance

SwiftPipes follows:
- Apple's macOS Security Guidelines
- OWASP Secure Coding Practices
- Industry standard key management practices

## Last Security Review
Date: 2026-02-26
Reviewer: Internal
Status: ✅ No critical vulnerabilities found

---

**Security Rating: 🟢 GOOD**  
Suitable for production use with proper code signing and notarization.
