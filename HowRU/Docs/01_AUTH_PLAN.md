# HowRU Authentication Plan

## Overview

Phone-first authentication optimized for elderly users with minimal friction.

---

## 1. Auth Methods (Priority Order)

| Method | Target Users | Implementation |
|--------|--------------|----------------|
| **Phone + SMS OTP** | Primary (all users) | Twilio Verify |
| **Apple Sign-In** | Secondary (iOS users) | AuthenticationServices |
| **Magic Link Email** | Fallback | Resend |

---

## 2. Phone OTP Flow

### User Experience

```
┌─────────────────────────────┐
│  Enter your phone number    │
│  ┌───────────────────────┐  │
│  │ +1 (555) 123-4567     │  │
│  └───────────────────────┘  │
│        [Continue →]         │
└─────────────────────────────┘
           ↓
┌─────────────────────────────┐
│  Enter the code we sent     │
│  ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐   │
│  │4│ │7│ │2│ │9│ │ │ │ │   │
│  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘   │
│  Didn't get it? Resend      │
└─────────────────────────────┘
```

### Technical Flow

```
1. POST /auth/otp/request
   Body: { phoneNumber: "+15551234567", countryCode: "US" }
   Response: { success: true, status: "pending", message: "Verification code sent" }

2. Twilio sends SMS: "Your HowRU code is 472918"

3. POST /auth/otp/verify
   Body: { phoneNumber: "+15551234567", countryCode: "US", code: "472918", name?: "Betty" }
   Response: {
     success: true,
     isNewUser: false,
     user: { id, phoneNumber, name, isChecker },
     tokens: { accessToken, refreshToken, expiresIn }
   }

4. Store tokens in Keychain
5. If isNewUser → Onboarding flow
   Else → Home screen
```

---

## 3. API Endpoints

### Request OTP

```
POST /auth/otp/request

Request:
{
  "phoneNumber": "+15551234567",
  "countryCode": "US"
}

Response (200):
{
  "success": true,
  "status": "pending",
  "message": "Verification code sent"
}

Response (429):
{
  "error": "rate_limited",
  "retryAfter": 3600
}
```

### Verify OTP

```
POST /auth/otp/verify

Request:
{
  "phoneNumber": "+15551234567",
  "countryCode": "US",
  "code": "472918",
  "name": "Betty"
}

Response (200):
{
  "success": true,
  "isNewUser": false,
  "user": {
    "id": "usr_abc123",
    "phoneNumber": "+15551234567",
    "name": "Betty",
    "isChecker": true
  },
  "tokens": {
    "accessToken": "eyJhbGciOiJSUzI1NiIs...",
    "refreshToken": "rt_abc123def456...",
    "expiresIn": 3600
  }
}

Response (401):
{
  "success": false,
  "error": "Invalid or expired verification code"
}
```

### Refresh Token

```
POST /auth/refresh

Request:
{
  "refreshToken": "rt_abc123def456..."
}

Response (200):
{
  "accessToken": "eyJhbGciOiJSUzI1NiIs...",
  "refreshToken": "rt_new789xyz...",  // Rotated
  "expiresIn": 3600
}
```

### Logout

```
POST /auth/logout

Request:
{
  "refreshToken": "rt_abc123def456..."
}

Response (200):
{
  "success": true
}
```

### Delete Account

```
DELETE /users/me

Headers:
  Authorization: Bearer {accessToken}

Response (200):
{
  "success": true,
  "message": "Account scheduled for deletion. All sessions have been logged out."
}
```

---

## 4. Token Strategy

### Access Token (JWT)

```json
{
  "sub": "usr_abc123",
  "iat": 1705312800,
  "exp": 1705316400,
  "iss": "howru.app",
  "aud": "howru-api",
  "phone": "+15551234567",
  "role": "user"
}
```

- **Lifetime:** 1 hour
- **Storage:** Memory (iOS) or Keychain
- **Algorithm:** RS256 (asymmetric)

### Refresh Token

- **Lifetime:** 30 days
- **Storage:** Keychain (secure)
- **Rotation:** New token on each refresh
- **Revocation:** Server-side blacklist

---

## 5. Rate Limiting

| Endpoint | Limit | Window |
|----------|-------|--------|
| `/auth/otp/request` | 3 requests | per phone per hour |
| `/auth/otp/verify` | 5 attempts | per phone per hour |
| `/auth/refresh` | 10 requests | per user per minute |

### Lockout Policy

- 5 failed OTP attempts → 1 hour lockout
- 10 failed attempts in 24h → 24 hour lockout
- Suspicious activity → Manual review

---

## 6. Security Measures

### OTP Security

- 6-digit numeric code
- 5-minute expiry
- One-time use (invalidated after verification)
- Constant-time comparison (prevent timing attacks)

### Token Security

- Refresh token rotation on each use
- Revoke all tokens on password change
- Device fingerprinting (optional)
- Anomaly detection (new device, location)

### Transport Security

- TLS 1.3 required
- Certificate pinning (optional)
- No sensitive data in URLs

---

## 7. iOS Implementation

### AuthService.swift

```swift
import Foundation
import Security

@Observable
final class AuthService {
    private(set) var currentUser: User?
    private(set) var isAuthenticated = false

    private let keychain = KeychainService()
    private let api = APIClient()

    // MARK: - Request OTP

    func requestOTP(phoneNumber: String, countryCode: String = "US") async throws {
        let request = OTPRequest(phoneNumber: phoneNumber, countryCode: countryCode)
        try await api.post("/auth/otp/request", body: request)
    }

    // MARK: - Verify OTP

    func verifyOTP(phoneNumber: String, code: String, name: String? = nil) async throws -> User {
        let request = VerifyOTPRequest(phoneNumber: phoneNumber, countryCode: "US", code: code, name: name)
        let response: AuthResponse = try await api.post("/auth/otp/verify", body: request)

        // Store tokens
        try keychain.save(response.tokens.accessToken, for: .accessToken)
        try keychain.save(response.tokens.refreshToken, for: .refreshToken)

        currentUser = response.user
        isAuthenticated = true

        return response.user
    }

    // MARK: - Refresh Token

    func refreshTokenIfNeeded() async throws {
        guard let refreshToken = keychain.get(.refreshToken) else {
            throw AuthError.notAuthenticated
        }

        let request = RefreshRequest(refreshToken: refreshToken)
        let response: AuthResponse = try await api.post("/auth/refresh", body: request)

        try keychain.save(response.accessToken, for: .accessToken)
        try keychain.save(response.refreshToken, for: .refreshToken)
    }

    // MARK: - Logout

    func logout() async {
        if let refreshToken = keychain.get(.refreshToken) {
            try? await api.post("/auth/logout", body: ["refreshToken": refreshToken])
        }

        keychain.delete(.accessToken)
        keychain.delete(.refreshToken)

        currentUser = nil
        isAuthenticated = false
    }
}
```

### KeychainService.swift

```swift
import Security

struct KeychainService {
    enum Key: String {
        case accessToken = "com.howru.accessToken"
        case refreshToken = "com.howru.refreshToken"
    }

    func save(_ value: String, for key: Key) throws {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

---

## 8. Twilio Integration

### Server-Side (Node.js)

```javascript
import twilio from 'twilio';

const client = twilio(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_AUTH_TOKEN
);

const VERIFY_SERVICE_SID = process.env.TWILIO_VERIFY_SID;

// Send OTP
async function sendOTP(phone, channel = 'sms') {
  return await client.verify.v2
    .services(VERIFY_SERVICE_SID)
    .verifications.create({
      to: phone,
      channel: channel // 'sms' or 'call'
    });
}

// Verify OTP
async function verifyOTP(phone, code) {
  const verification = await client.verify.v2
    .services(VERIFY_SERVICE_SID)
    .verificationChecks.create({
      to: phone,
      code: code
    });

  return verification.status === 'approved';
}
```

### Twilio Verify Pricing

| Channel | Cost |
|---------|------|
| SMS | $0.05 per verification |
| Voice | $0.10 per verification |
| Email | $0.03 per verification |

---

## 9. Apple Sign-In (Secondary)

### When Required

Apple Sign-In is required by App Store if you offer any other social login.

### Flow

```swift
import AuthenticationServices

func signInWithApple() {
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = [.fullName, .email]

    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.performRequests()
}

func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
) {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
          let identityToken = credential.identityToken,
          let tokenString = String(data: identityToken, encoding: .utf8) else {
        return
    }

    // Send to backend
    Task {
        try await api.post("/auth/apple", body: [
            "identityToken": tokenString,
            "fullName": credential.fullName,
            "email": credential.email
        ])
    }
}
```

---

## 10. Implementation Checklist

### Backend

- [ ] Set up Twilio Verify service
- [ ] Implement `/auth/otp/request` endpoint
- [ ] Implement `/auth/otp/verify` endpoint
- [ ] Implement `/auth/refresh` endpoint
- [ ] Implement `/auth/logout` endpoint
- [ ] Implement `DELETE /users/me` endpoint
- [ ] Set up JWT signing (RS256)
- [ ] Implement refresh token rotation
- [ ] Add rate limiting middleware
- [ ] Set up Redis for token blacklist
- [ ] Add audit logging

### iOS App

- [ ] Create AuthService
- [ ] Create KeychainService
- [ ] Build phone entry UI
- [ ] Build OTP verification UI
- [ ] Add auto-fill support for OTP
- [ ] Implement token refresh interceptor
- [ ] Handle session expiry gracefully
- [ ] Add biometric unlock (Face ID/Touch ID) - optional

### Testing

- [ ] Unit tests for auth logic
- [ ] Integration tests with Twilio
- [ ] Rate limit testing
- [ ] Token expiry testing
- [ ] Keychain persistence testing

---

## 11. Cost Estimate

| Item | Monthly Cost (1K users) |
|------|------------------------|
| Twilio Verify (SMS) | $50-100 |
| Twilio Verify (Voice fallback) | $10-20 |
| Total | ~$60-120/month |

---

## Next Steps

1. Create Twilio account and Verify service
2. Set up backend auth routes
3. Implement iOS AuthService
4. Build login/OTP UI screens
5. Test end-to-end flow
