/**
 * Send OTP verification code via SMS
 * @param to Phone number in E.164 format (+27123456789)
 */
export declare function sendOTP(to: string): Promise<{
    status: string;
    sid: string;
}>;
/**
 * Verify OTP code entered by user
 * @param to Phone number in E.164 format
 * @param code 6-digit code entered by user
 * @returns true if verified, false if invalid
 */
export declare function verifyOTP(to: string, code: string): Promise<boolean>;
interface AlertSMSParams {
    to: string;
    checkerName: string;
    level: 'soft' | 'hard' | 'escalation';
    locationName?: string;
    address?: string;
    phone?: string;
    lastCheckInTime?: string;
    ackUrl?: string;
}
/**
 * Send alert SMS to supporter when checker misses check-in
 */
export declare function sendAlertSMS(params: AlertSMSParams): Promise<string>;
interface PokeSMSParams {
    to: string;
    fromName: string;
    message?: string;
}
/**
 * Send poke notification SMS to checker
 */
export declare function sendPokeSMS(params: PokeSMSParams): Promise<string>;
/**
 * Format phone number to E.164 format
 * @param phone Phone number in various formats
 * @param defaultCountry Default country code (e.g., 'ZA' for South Africa)
 */
export declare function formatPhoneE164(phone: string, defaultCountry?: string): string;
export {};
//# sourceMappingURL=twilio.d.ts.map