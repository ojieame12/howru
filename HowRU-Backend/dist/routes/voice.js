"use strict";
/**
 * TwiML Voice Routes
 * Handles automated voice calls for alert escalation
 *
 * Features:
 * - Polly neural voice for natural speech
 * - DTMF gathering for acknowledgment
 * - Call status tracking
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.initiateAlertCall = initiateAlertCall;
const express_1 = require("express");
const twilio_1 = __importDefault(require("twilio"));
const index_js_1 = require("../db/index.js");
const router = (0, express_1.Router)();
const VoiceResponse = twilio_1.default.twiml.VoiceResponse;
// ============================================================================
// ALERT VOICE CALL
// Played when supporter answers the call
// ============================================================================
router.post('/alert/:alertId', async (req, res) => {
    try {
        const { alertId } = req.params;
        // Get alert details
        const alert = (await (0, index_js_1.sql) `SELECT * FROM alerts WHERE id = ${alertId}`)[0];
        if (!alert) {
            const twiml = new VoiceResponse();
            twiml.say({ voice: 'Polly.Joanna' }, 'Sorry, this alert is no longer active. Goodbye.');
            twiml.hangup();
            res.type('text/xml');
            return res.send(twiml.toString());
        }
        // Get checker details
        const checker = await (0, index_js_1.getUserById)(alert.checker_id);
        // Calculate hours since missed
        const hoursSinceMissed = Math.round((Date.now() - new Date(alert.missed_window_at).getTime()) / (1000 * 60 * 60));
        const twiml = new VoiceResponse();
        // Urgent greeting
        twiml.say({ voice: 'Polly.Joanna' }, 'This is an urgent wellness alert from How Are You.');
        twiml.pause({ length: 1 });
        // Alert message
        twiml.say({ voice: 'Polly.Joanna' }, `${checker?.name || 'Your loved one'} has not checked in for ${hoursSinceMissed} hours. Please check on them immediately.`);
        twiml.pause({ length: 1 });
        // Gather response
        const gather = twiml.gather({
            numDigits: 1,
            action: `/voice/response/${alertId}`,
            timeout: 10,
        });
        gather.say({ voice: 'Polly.Joanna' }, 'Press 1 to acknowledge this alert. Press 2 to hear contact information. Press 9 to repeat this message.');
        // If no input, repeat
        twiml.redirect(`/voice/alert/${alertId}`);
        res.type('text/xml');
        res.send(twiml.toString());
    }
    catch (error) {
        console.error('Voice alert error:', error);
        const twiml = new VoiceResponse();
        twiml.say({ voice: 'Polly.Joanna' }, 'An error occurred. Please try again later.');
        twiml.hangup();
        res.type('text/xml');
        res.send(twiml.toString());
    }
});
// ============================================================================
// GATHER RESPONSE HANDLER
// Processes DTMF input from the caller
// ============================================================================
router.post('/response/:alertId', async (req, res) => {
    try {
        const { alertId } = req.params;
        const digit = req.body.Digits;
        const callerPhone = req.body.Called;
        const twiml = new VoiceResponse();
        // Get alert and checker
        const alert = (await (0, index_js_1.sql) `SELECT * FROM alerts WHERE id = ${alertId}`)[0];
        const checker = alert ? await (0, index_js_1.getUserById)(alert.checker_id) : null;
        switch (digit) {
            case '1':
                // Acknowledge alert
                // Find supporter by phone number
                const supporter = (await (0, index_js_1.sql) `
            SELECT id FROM users WHERE phone_number = ${callerPhone}
          `)[0];
                if (supporter && alert) {
                    await (0, index_js_1.sql) `
            UPDATE alerts
            SET acknowledged_at = NOW(), acknowledged_by = ${supporter.id}, status = 'acknowledged'
            WHERE id = ${alertId} AND acknowledged_at IS NULL
          `;
                    // Log the call
                    await (0, index_js_1.sql) `
            INSERT INTO call_logs (alert_id, supporter_id, call_sid, status)
            VALUES (${alertId}, ${supporter.id}, ${req.body.CallSid || 'unknown'}, 'acknowledged')
          `;
                }
                twiml.say({ voice: 'Polly.Joanna' }, 'Thank you. The alert has been acknowledged. Please check on them as soon as possible. Goodbye.');
                twiml.hangup();
                break;
            case '2':
                // Read contact information
                if (checker) {
                    twiml.say({ voice: 'Polly.Joanna' }, `${checker.name}'s phone number is ${formatPhoneForSpeech(checker.phone_number)}.`);
                    twiml.pause({ length: 1 });
                    twiml.say({ voice: 'Polly.Joanna' }, `I repeat, ${formatPhoneForSpeech(checker.phone_number)}.`);
                    if (checker.last_known_address) {
                        twiml.pause({ length: 1 });
                        twiml.say({ voice: 'Polly.Joanna' }, `Their last known location was ${checker.last_known_address}.`);
                    }
                }
                else {
                    twiml.say({ voice: 'Polly.Joanna' }, 'Contact information is not available.');
                }
                // Return to main menu
                twiml.redirect(`/voice/alert/${alertId}`);
                break;
            case '9':
            default:
                // Repeat message
                twiml.redirect(`/voice/alert/${alertId}`);
                break;
        }
        res.type('text/xml');
        res.send(twiml.toString());
    }
    catch (error) {
        console.error('Voice response error:', error);
        const twiml = new VoiceResponse();
        twiml.say({ voice: 'Polly.Joanna' }, 'An error occurred. Please try again later.');
        twiml.hangup();
        res.type('text/xml');
        res.send(twiml.toString());
    }
});
// ============================================================================
// CALL STATUS WEBHOOK
// Twilio calls this when call status changes
// ============================================================================
router.post('/status/:alertId', async (req, res) => {
    try {
        const { alertId } = req.params;
        const { CallSid, CallStatus, CallDuration, Called, } = req.body;
        console.log(`Voice call status: ${CallSid} -> ${CallStatus}`);
        // Find supporter by phone
        const supporter = (await (0, index_js_1.sql) `
        SELECT id FROM users WHERE phone_number = ${Called}
      `)[0];
        // Log call status
        await (0, index_js_1.sql) `
      INSERT INTO call_logs (alert_id, supporter_id, call_sid, status, duration_seconds)
      VALUES (
        ${alertId},
        ${supporter?.id || null},
        ${CallSid},
        ${CallStatus},
        ${CallDuration ? parseInt(CallDuration) : null}
      )
      ON CONFLICT (call_sid) DO UPDATE
      SET status = EXCLUDED.status, duration_seconds = EXCLUDED.duration_seconds
    `;
        res.json({ received: true });
    }
    catch (error) {
        console.error('Voice status webhook error:', error);
        res.json({ received: true, error: 'Failed to process status' });
    }
});
// ============================================================================
// HELPERS
// ============================================================================
/**
 * Format phone number for speech synthesis
 * "+15551234567" -> "5 5 5, 1 2 3, 4 5 6 7"
 */
function formatPhoneForSpeech(phone) {
    if (!phone)
        return 'unknown';
    // Remove non-digits and get last 10
    const digits = phone.replace(/\D/g, '').slice(-10);
    if (digits.length < 10) {
        return digits.split('').join(' ');
    }
    // Format as "area code, exchange, line"
    return `${digits.slice(0, 3).split('').join(' ')}, ${digits.slice(3, 6).split('').join(' ')}, ${digits.slice(6).split('').join(' ')}`;
}
exports.default = router;
// ============================================================================
// VOICE CALL INITIATOR (used by jobs/escalate-alerts)
// ============================================================================
async function initiateAlertCall(supporterPhone, alertId) {
    const accountSid = process.env.TWILIO_ACCOUNT_SID;
    const authToken = process.env.TWILIO_AUTH_TOKEN;
    const fromNumber = process.env.TWILIO_PHONE_NUMBER;
    const apiUrl = process.env.API_URL || 'https://api.howru.app';
    if (!accountSid || !authToken || !fromNumber) {
        console.error('Twilio credentials not configured for voice calls');
        return null;
    }
    try {
        const client = (0, twilio_1.default)(accountSid, authToken);
        const call = await client.calls.create({
            to: supporterPhone,
            from: fromNumber,
            url: `${apiUrl}/voice/alert/${alertId}`,
            statusCallback: `${apiUrl}/voice/status/${alertId}`,
            statusCallbackEvent: ['initiated', 'ringing', 'answered', 'completed'],
        });
        console.log(`Initiated voice call ${call.sid} to ${supporterPhone}`);
        return call.sid;
    }
    catch (error) {
        console.error('Failed to initiate voice call:', error);
        return null;
    }
}
//# sourceMappingURL=voice.js.map