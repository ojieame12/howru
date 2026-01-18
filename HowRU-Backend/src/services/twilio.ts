import Twilio from 'twilio';

const accountSid = process.env.TWILIO_ACCOUNT_SID!;
const authToken = process.env.TWILIO_AUTH_TOKEN!;
const verifySid = process.env.TWILIO_VERIFY_SID!;
const phoneNumber = process.env.TWILIO_PHONE_NUMBER!;
const messagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;

const client = Twilio(accountSid, authToken);

// ============================================================================
// OTP VERIFICATION (for phone auth)
// ============================================================================

/**
 * Send OTP verification code via SMS
 * @param to Phone number in E.164 format (+27123456789)
 */
export async function sendOTP(to: string): Promise<{ status: string; sid: string }> {
  try {
    const verification = await client.verify.v2
      .services(verifySid)
      .verifications.create({
        to,
        channel: 'sms',
      });

    return {
      status: verification.status, // 'pending'
      sid: verification.sid,
    };
  } catch (error: any) {
    console.error('Failed to send OTP:', error.message);
    throw new Error(`Failed to send verification code: ${error.message}`);
  }
}

/**
 * Verify OTP code entered by user
 * @param to Phone number in E.164 format
 * @param code 6-digit code entered by user
 * @returns true if verified, false if invalid
 */
export async function verifyOTP(to: string, code: string): Promise<boolean> {
  try {
    const verificationCheck = await client.verify.v2
      .services(verifySid)
      .verificationChecks.create({
        to,
        code,
      });

    return verificationCheck.status === 'approved';
  } catch (error: any) {
    console.error('Failed to verify OTP:', error.message);
    return false;
  }
}

// ============================================================================
// ALERT SMS (for missed check-ins)
// ============================================================================

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
export async function sendAlertSMS(params: AlertSMSParams): Promise<string> {
  const { to, checkerName, level, locationName, address, phone, lastCheckInTime, ackUrl } = params;

  let body: string;

  switch (level) {
    case 'soft':
      // ~85 chars - 1 segment
      body = `HowRU: ${truncate(checkerName, 15)} hasn't checked in for 24h.${locationName ? ` Last seen: ${truncate(locationName, 25)}.` : ''}${phone ? ` Call: ${phone}` : ''}`;
      break;

    case 'hard':
      // ~160 chars - 1-2 segments
      body = `URGENT HowRU: ${truncate(checkerName, 15)} missed 36h.\n${address ? `Location: ${truncate(address, 40)}\n` : ''}${phone ? `Call: ${phone}\n` : ''}${ackUrl ? `Ack: ${ackUrl}` : ''}`;
      break;

    case 'escalation':
      // ~200 chars - 2-3 segments
      body = `EMERGENCY: ${truncate(checkerName, 15)} - 48H NO CHECK-IN\n\n${lastCheckInTime ? `Last seen: ${lastCheckInTime}\n` : ''}${address ? `At: ${truncate(address, 40)}\n` : ''}\n${phone ? `Call: ${phone}\n` : ''}${ackUrl ? `Ack: ${ackUrl}` : ''}`;
      break;
  }

  try {
    const message = await client.messages.create({
      body,
      to,
      ...(messagingServiceSid
        ? { messagingServiceSid }
        : { from: phoneNumber }),
    });

    console.log(`Alert SMS sent to ${to}: ${message.sid}`);
    return message.sid;
  } catch (error: any) {
    console.error('Failed to send alert SMS:', error.message);
    throw new Error(`Failed to send alert SMS: ${error.message}`);
  }
}

// ============================================================================
// POKE SMS (for nudging checkers)
// ============================================================================

interface PokeSMSParams {
  to: string;
  fromName: string;
  message?: string;
}

/**
 * Send poke notification SMS to checker
 */
export async function sendPokeSMS(params: PokeSMSParams): Promise<string> {
  const { to, fromName, message } = params;

  const body = message
    ? `HowRU: ${truncate(fromName, 15)} is thinking of you: "${truncate(message, 40)}"`
    : `HowRU: ${truncate(fromName, 15)} is thinking of you. Check in when you can!`;

  try {
    const sms = await client.messages.create({
      body,
      to,
      ...(messagingServiceSid
        ? { messagingServiceSid }
        : { from: phoneNumber }),
    });

    return sms.sid;
  } catch (error: any) {
    console.error('Failed to send poke SMS:', error.message);
    throw new Error(`Failed to send poke SMS: ${error.message}`);
  }
}

// ============================================================================
// HELPERS
// ============================================================================

function truncate(str: string, maxLength: number): string {
  if (str.length <= maxLength) return str;
  return str.slice(0, maxLength - 1) + '…';
}

/**
 * Format phone number to E.164 format
 * @param phone Phone number in various formats
 * @param defaultCountry Default country code (e.g., 'ZA' for South Africa)
 */
export function formatPhoneE164(phone: string, defaultCountry: string = 'US'): string {
  // Remove all non-digit characters except leading +
  let cleaned = phone.replace(/[^\d+]/g, '');

  // If already in E.164 format
  if (cleaned.startsWith('+')) {
    return cleaned;
  }

  // Add country code based on default
  const countryCodes: Record<string, string> = {
    US: '+1',
    ZA: '+27',
    UK: '+44',
    AU: '+61',
  };

  const prefix = countryCodes[defaultCountry] || '+1';

  // Remove leading 0 if present (common in local formats)
  if (cleaned.startsWith('0')) {
    cleaned = cleaned.slice(1);
  }

  return `${prefix}${cleaned}`;
}
