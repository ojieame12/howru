import Foundation

// MARK: - Auth Models

/// Request body for OTP request
struct OTPRequestBody: Encodable {
    let phoneNumber: String
    let countryCode: String

    init(phoneNumber: String, countryCode: String = "US") {
        self.phoneNumber = phoneNumber
        self.countryCode = countryCode
    }
}

/// Response from OTP request
struct OTPRequestResponse: Decodable {
    let success: Bool
    let status: String?
    let message: String?
}

/// Request body for OTP verification
struct OTPVerifyBody: Encodable {
    let phoneNumber: String
    let countryCode: String
    let code: String
    let name: String?

    init(phoneNumber: String, code: String, name: String? = nil, countryCode: String = "US") {
        self.phoneNumber = phoneNumber
        self.countryCode = countryCode
        self.code = code
        self.name = name
    }
}

/// Response from OTP verification (successful login)
struct OTPVerifyResponse: Decodable {
    let success: Bool
    let isNewUser: Bool
    let user: APIUser
    let tokens: APITokens
}

/// Tokens object from auth responses
struct APITokens: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: String?
}

/// Request body for token refresh
struct TokenRefreshBody: Encodable {
    let refreshToken: String
}

/// Response from token refresh
struct TokenRefreshResponse: Decodable {
    let success: Bool
    let tokens: APITokens
}

/// Request body for Apple Sign-In
struct AppleSignInBody: Encodable {
    let identityToken: String
    let fullName: AppleFullName?
    let email: String?
}

struct AppleFullName: Encodable {
    let givenName: String?
    let familyName: String?
}

// MARK: - User Models

/// API representation of a user
struct APIUser: Decodable {
    let id: String
    let name: String
    let phoneNumber: String?
    let email: String?
    let profileImageUrl: String?
    let address: String?
    let isChecker: Bool
    let lastKnownLocation: String?
    let lastKnownLocationAt: Date?
    let createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case phoneNumber
        case phone
        case email
        case profileImageUrl
        case address
        case isChecker
        case lastKnownLocation
        case lastKnownLocationAt
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
            ?? container.decodeIfPresent(String.self, forKey: .phone)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        profileImageUrl = try container.decodeIfPresent(String.self, forKey: .profileImageUrl)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        isChecker = try container.decodeIfPresent(Bool.self, forKey: .isChecker) ?? true
        lastKnownLocation = try container.decodeIfPresent(String.self, forKey: .lastKnownLocation)
        lastKnownLocationAt = try container.decodeIfPresent(Date.self, forKey: .lastKnownLocationAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

/// Request body for updating user profile
struct UpdateProfileBody: Encodable {
    let name: String?
    let email: String?
    let profileImageUrl: String?
    let address: String?
}

/// Response from GET /users/me
struct UserProfileResponse: Decodable {
    let success: Bool
    let user: APIUser
    let schedule: APISchedule?
    let subscription: APISubscriptionInfo?
}

// MARK: - Schedule Models

/// API representation of a schedule
struct APISchedule: Decodable {
    let id: String
    let windowStartHour: Int
    let windowStartMinute: Int
    let windowEndHour: Int
    let windowEndMinute: Int
    let timezone: String
    let activeDays: [Int]
    let gracePeriodMinutes: Int
    let reminderEnabled: Bool
    let reminderMinutesBefore: Int
    let isActive: Bool?
}

/// Request body for updating schedule
struct UpdateScheduleBody: Encodable {
    let windowStartHour: Int?
    let windowStartMinute: Int?
    let windowEndHour: Int?
    let windowEndMinute: Int?
    let timezone: String?
    let activeDays: [Int]?
    let gracePeriodMinutes: Int?
    let reminderEnabled: Bool?
    let reminderMinutesBefore: Int?
}

// MARK: - Check-In Models

/// API representation of a check-in (matches backend response)
struct APICheckIn: Decodable {
    let id: String
    let timestamp: Date
    let mentalScore: Int
    let bodyScore: Int
    let moodScore: Int
    let averageScore: Double?
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    let address: String?
    let isManual: Bool?
    let hasSelfie: Bool?
}

/// Request body for creating a check-in (matches backend schema)
struct CreateCheckInBody: Encodable {
    let mentalScore: Int
    let bodyScore: Int
    let moodScore: Int
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    let address: String?
    let isManual: Bool

    init(mentalScore: Int, bodyScore: Int, moodScore: Int, latitude: Double? = nil, longitude: Double? = nil, locationName: String? = nil, address: String? = nil, isManual: Bool = true) {
        self.mentalScore = mentalScore
        self.bodyScore = bodyScore
        self.moodScore = moodScore
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.address = address
        self.isManual = isManual
    }
}

/// Response from check-in creation
struct CheckInResponse: Decodable {
    let success: Bool
    let checkIn: APICheckIn
}

/// Response from check-in list
struct CheckInsResponse: Decodable {
    let success: Bool
    let checkIns: [APICheckIn]
}

/// Response from today's check-in
struct TodayCheckInResponse: Decodable {
    let success: Bool
    let hasCheckedInToday: Bool
    let checkIn: APICheckIn?
}

/// Response from check-in stats
struct CheckInStatsResponse: Decodable {
    let success: Bool
    let stats: APICheckInStats
}

struct APICheckInStats: Decodable {
    let totalCheckIns: Int
    let averageMental: Double
    let averageBody: Double
    let averageMood: Double
    let averageOverall: Double
    let currentStreak: Int
}

// MARK: - Circle Models

/// API representation of a circle member
struct APICircleMember: Decodable {
    let id: String
    let supporterId: String?
    let name: String
    let phone: String?
    let email: String?
    let isAppUser: Bool
    let permissions: APIPermissions
    let alertPriority: Int?
    let alertPreferences: APIAlertPreferences
    let invitedAt: Date
    let acceptedAt: Date?
}

struct APIPermissions: Decodable {
    let canSeeMood: Bool
    let canSeeLocation: Bool
    let canSeeSelfie: Bool
    let canPoke: Bool
}

struct APIAlertPreferences: Decodable {
    let push: Bool
    let sms: Bool
    let email: Bool
}

/// Response from GET /circle
struct CircleResponse: Decodable {
    let success: Bool
    let circle: [APICircleMember]
}

/// API representation of a supported user (checker)
struct APISupportedUser: Decodable {
    let id: String
    let checkerId: String
    let name: String
    let phone: String?
    let lastKnownLocation: String?
    let lastLocationAt: Date?
    let permissions: APIPermissions
}

/// Response from GET /circle/supporting
struct SupportingResponse: Decodable {
    let success: Bool
    let supporting: [APISupportedUser]
}

/// Request body for adding circle member
struct AddCircleMemberBody: Encodable {
    let name: String
    let phone: String?
    let email: String?
    let canSeeMood: Bool
    let canSeeLocation: Bool
    let canSeeSelfie: Bool
    let canPoke: Bool
    let alertPriority: Int
    let alertViaSms: Bool
    let alertViaEmail: Bool

    init(name: String, phone: String? = nil, email: String? = nil, canSeeMood: Bool = true, canSeeLocation: Bool = false, canSeeSelfie: Bool = false, canPoke: Bool = true, alertPriority: Int = 1, alertViaSms: Bool = false, alertViaEmail: Bool = false) {
        self.name = name
        self.phone = phone
        self.email = email
        self.canSeeMood = canSeeMood
        self.canSeeLocation = canSeeLocation
        self.canSeeSelfie = canSeeSelfie
        self.canPoke = canPoke
        self.alertPriority = alertPriority
        self.alertViaSms = alertViaSms
        self.alertViaEmail = alertViaEmail
    }
}

/// Response from add circle member (backend returns {member: ...})
struct AddCircleMemberResponse: Decodable {
    let success: Bool
    let member: APICircleMember
}

/// Request body for creating invite
struct CreateInviteBody: Encodable {
    let role: String
    let canSeeMood: Bool
    let canSeeLocation: Bool
    let canSeeSelfie: Bool
    let canPoke: Bool
    let expiresInHours: Int

    init(role: String = "supporter", canSeeMood: Bool = true, canSeeLocation: Bool = false, canSeeSelfie: Bool = false, canPoke: Bool = true, expiresInHours: Int = 48) {
        self.role = role
        self.canSeeMood = canSeeMood
        self.canSeeLocation = canSeeLocation
        self.canSeeSelfie = canSeeSelfie
        self.canPoke = canPoke
        self.expiresInHours = expiresInHours
    }
}

/// Response from create invite
struct CreateInviteResponse: Decodable {
    let success: Bool
    let invite: APIInvite
}

struct APIInvite: Decodable {
    let id: String
    let code: String
    let role: String?
    let expiresAt: Date?
    let link: String?
}

/// Response from GET /circle/invites/:code
struct InvitePreviewResponse: Decodable {
    let success: Bool
    let invite: APIInvitePreview
}

struct APIInvitePreview: Decodable {
    let inviterName: String
    let role: String
    let expiresAt: Date?
    let permissions: APIPermissions
}

/// Response from POST /circle/invites/:code/accept
struct AcceptInviteResponse: Decodable {
    let success: Bool
    let message: String?
    let role: String
    let inviterName: String
}

/// Request body for sending invite via email
struct SendInviteBody: Encodable {
    let email: String
    let role: String
    let canSeeMood: Bool
    let canSeeLocation: Bool
    let canSeeSelfie: Bool
    let canPoke: Bool

    init(email: String, role: String = "supporter", canSeeMood: Bool = true, canSeeLocation: Bool = false, canSeeSelfie: Bool = false, canPoke: Bool = true) {
        self.email = email
        self.role = role
        self.canSeeMood = canSeeMood
        self.canSeeLocation = canSeeLocation
        self.canSeeSelfie = canSeeSelfie
        self.canPoke = canPoke
    }
}

/// Response from POST /circle/invites/send
struct SendInviteResponse: Decodable {
    let success: Bool
    let invite: APISentInvite
}

struct APISentInvite: Decodable {
    let id: String
    let code: String
    let sentTo: String
}

// MARK: - Poke Models

/// API representation of a poke (matches backend response)
struct APIPoke: Decodable {
    let id: String
    let fromUserId: String?
    let fromName: String?
    let toUserId: String?
    let message: String?
    let sentAt: Date
    let seenAt: Date?
    let respondedAt: Date?
}

/// Request body for creating a poke (matches backend schema)
struct CreatePokeBody: Encodable {
    let toUserId: String
    let message: String?
}

/// Response from poke creation
struct PokeResponse: Decodable {
    let success: Bool
    let poke: APIPokeSent
}

struct APIPokeSent: Decodable {
    let id: String
    let toUserId: String
    let message: String?
    let sentAt: Date
}

/// Response from poke list
struct PokesResponse: Decodable {
    let success: Bool
    let pokes: [APIPoke]
}

/// Response from unseen pokes count
struct UnseenPokesResponse: Decodable {
    let success: Bool
    let count: Int
}

// MARK: - Alert Models

/// API representation of an alert (matches backend response)
struct APIAlert: Decodable {
    let id: String
    let checkerId: String?
    let checkerName: String?
    let type: String
    let status: String
    let triggeredAt: Date
    let missedWindowAt: Date?
    let lastCheckInAt: Date?
    let lastKnownLocation: String?
    let acknowledgedAt: Date?
    let acknowledgedBy: String?
    let resolvedAt: Date?
    let resolution: String?
}

/// Response from alerts list
struct AlertsResponse: Decodable {
    let success: Bool
    let alerts: [APIAlert]
}

/// Request body for resolving alert
struct ResolveAlertBody: Encodable {
    let resolvedAt: Date
    let resolution: String?
    let notes: String?

    init(resolvedAt: Date = Date(), resolution: String? = nil, notes: String? = nil) {
        self.resolvedAt = resolvedAt
        self.resolution = resolution
        self.notes = notes
    }
}

// MARK: - Subscription Models

/// Subscription info from user profile
struct APISubscriptionInfo: Decodable {
    let plan: String
    let status: String
    let expiresAt: Date?
}

/// Full subscription details
struct APISubscription: Decodable {
    let plan: String
    let status: String
    let productId: String?
    let expiresAt: Date?
    let revenueCatId: String?
    let createdAt: Date?
    let updatedAt: Date?
}

/// Feature limits for subscription
struct APIFeatureLimits: Decodable {
    let maxCircleMembers: Int
    let maxCheckInsPerDay: Int
    let selfieEnabled: Bool
    let locationSharingEnabled: Bool
    let dataExportEnabled: Bool
    let customScheduleEnabled: Bool
    let prioritySupport: Bool
}

/// Response from GET /subscriptions/me
struct SubscriptionResponse: Decodable {
    let success: Bool
    let subscription: APISubscription
    let limits: APIFeatureLimits
}

/// Plan offering for paywall
struct APIPlanOffering: Decodable {
    let id: String
    let name: String
    let description: String
    let monthlyProductId: String
    let yearlyProductId: String
    let features: [String]
    let highlighted: Bool
}

/// Response from GET /subscriptions/offerings
struct OfferingsResponse: Decodable {
    let success: Bool
    let offerings: [APIPlanOffering]
}

/// Response from GET /billing/entitlements
struct EntitlementsResponse: Decodable {
    let success: Bool
    let plan: String
    let status: String
    let expiresAt: Date?
    let limits: APIFeatureLimits
}

// MARK: - Upload Models

/// Response from file upload
struct UploadResponse: Decodable {
    let success: Bool
    let url: String
    let expiresAt: Date?
}

/// Request body for selfie upload (base64 JSON)
struct UploadSelfieBody: Encodable {
    let checkinId: String
    let imageData: String  // base64-encoded
    let mimeType: String
}

/// Request body for avatar upload (base64 JSON)
struct UploadAvatarBody: Encodable {
    let imageData: String  // base64-encoded
    let mimeType: String
}

// MARK: - Export Models

/// Response from data export
struct ExportResponse: Decodable {
    let success: Bool
    let downloadUrl: String?
}

// MARK: - Push Token Models

/// Request body for registering push token
struct RegisterPushTokenBody: Encodable {
    let token: String
    let platform: String
    let deviceId: String?

    init(token: String, platform: String = "ios", deviceId: String? = nil) {
        self.token = token
        self.platform = platform
        self.deviceId = deviceId
    }
}

// MARK: - Generic Response

/// Generic success response for operations that don't return data
struct SuccessResponse: Decodable {
    let success: Bool
    let message: String?
}
