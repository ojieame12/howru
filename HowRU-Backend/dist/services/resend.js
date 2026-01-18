"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendAlertEmail = sendAlertEmail;
exports.sendWelcomeEmail = sendWelcomeEmail;
exports.sendPokeEmail = sendPokeEmail;
exports.sendExportReadyEmail = sendExportReadyEmail;
exports.sendCircleInviteEmail = sendCircleInviteEmail;
const resend_1 = require("resend");
const resend = new resend_1.Resend(process.env.RESEND_API_KEY);
const FROM_EMAIL = process.env.FROM_EMAIL || 'HowRU <noreply@howru.app>';
// ============================================================================
// DESIGN SYSTEM TOKENS (matching iOS Theme.swift)
// ============================================================================
const colors = {
    // Backgrounds
    background: '#F7F3EE',
    backgroundWarm: '#FDF9F5',
    surface: '#FFFFFF',
    surfaceWarm: '#FFFCF9',
    // Text
    textPrimary: '#2D2A26',
    textSecondary: '#9D958A',
    // Brand
    coral: '#E85A3C',
    coralLight: '#F4A68E',
    coralGlow: '#FFEEE8',
    // Semantic
    success: '#4CD964',
    warning: '#F5A623',
    error: '#FF3B30',
    info: '#5D4E8C',
    // Mood colors
    moodMental: '#5D4E8C',
    moodBody: '#4CD964',
    moodEmotional: '#E85A3C',
    // UI
    divider: '#E8E2DA',
    buttonBg: '#1C1917',
    buttonText: '#F5F2EE',
};
const radius = {
    sm: '8px',
    md: '12px',
    lg: '20px',
    xl: '28px',
};
// Web-safe font stack matching app typography
const fonts = {
    headline: "Georgia, 'Times New Roman', serif",
    body: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif",
};
// ============================================================================
// BASE EMAIL TEMPLATE
// ============================================================================
function baseTemplate(content, footerText) {
    return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>HowRU</title>
</head>
<body style="margin: 0; padding: 0; background-color: ${colors.background}; font-family: ${fonts.body};">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: ${colors.background};">
    <tr>
      <td align="center" style="padding: 40px 20px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width: 520px; background-color: ${colors.surface}; border-radius: ${radius.xl}; box-shadow: 0 4px 24px rgba(139, 115, 85, 0.08);">

          <!-- Header with Logo -->
          <tr>
            <td align="center" style="padding: 40px 32px 24px 32px;">
              <table role="presentation" cellspacing="0" cellpadding="0">
                <tr>
                  <td align="center" style="width: 64px; height: 64px; background: linear-gradient(135deg, ${colors.coral}, ${colors.coralLight}); border-radius: 50%;">
                    <span style="font-family: ${fonts.headline}; font-size: 28px; font-weight: 600; color: white;">H</span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Content -->
          ${content}

          <!-- Footer -->
          <tr>
            <td style="padding: 24px 32px 40px 32px; border-top: 1px solid ${colors.divider};">
              <p style="margin: 0; font-size: 13px; color: ${colors.textSecondary}; text-align: center; line-height: 1.6;">
                ${footerText || `You're receiving this because you're part of a care circle on HowRU.`}
              </p>
              <p style="margin: 12px 0 0 0; font-size: 13px; text-align: center;">
                <a href="https://howru.app/settings/notifications" style="color: ${colors.textSecondary}; text-decoration: underline;">Manage notifications</a>
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>
  `.trim();
}
async function sendAlertEmail(params) {
    const { to, checkerName, userName, alertLevel, lastCheckIn, lastLocation, lastMood } = params;
    const levelConfig = {
        reminder: {
            subject: `Reminder: ${userName} hasn't checked in yet`,
            color: colors.warning,
            urgency: 'Gentle Reminder',
            message: `${userName} hasn't completed their check-in for today. This is just a friendly heads up.`,
        },
        soft: {
            subject: `${userName} missed their check-in window`,
            color: colors.warning,
            urgency: 'Soft Alert',
            message: `${userName} has missed their scheduled check-in window. They may be busy, but we wanted to let you know.`,
        },
        hard: {
            subject: `${userName} hasn't checked in for 36+ hours`,
            color: colors.coral,
            urgency: 'Urgent Alert',
            message: `${userName} hasn't checked in for over 36 hours. You may want to reach out to them.`,
        },
        escalation: {
            subject: `URGENT: ${userName} hasn't checked in for 48+ hours`,
            color: colors.error,
            urgency: 'Critical Escalation',
            message: `${userName} hasn't responded in over 48 hours. Please try to contact them or someone who can check on them.`,
        },
    };
    const config = levelConfig[alertLevel];
    const lastCheckInText = lastCheckIn
        ? `${lastCheckIn.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })} at ${lastCheckIn.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}`
        : 'No recent check-ins';
    const content = `
    <!-- Urgency Label -->
    <tr>
      <td style="padding: 0 32px 8px 32px;">
        <p style="margin: 0; font-size: 12px; font-weight: 500; text-transform: uppercase; letter-spacing: 1px; color: ${config.color}; text-align: center;">
          ${config.urgency}
        </p>
      </td>
    </tr>

    <!-- Title -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <h1 style="margin: 0; font-family: ${fonts.headline}; font-size: 24px; font-weight: 400; color: ${colors.textPrimary}; text-align: center; line-height: 1.3;">
          ${userName} needs a check-in
        </h1>
      </td>
    </tr>

    <!-- Message -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <p style="margin: 0; font-size: 15px; color: ${colors.textSecondary}; text-align: center; line-height: 1.6;">
          Hi ${checkerName}, ${config.message}
        </p>
      </td>
    </tr>

    <!-- Status Card -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: ${colors.backgroundWarm}; border-radius: ${radius.lg};">
          <tr>
            <td style="padding: 20px;">

              <!-- Last Check-in Row -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-bottom: ${lastLocation || lastMood ? '16px' : '0'};">
                <tr>
                  <td style="width: 44px; vertical-align: top;">
                    <table role="presentation" cellspacing="0" cellpadding="0">
                      <tr>
                        <td style="width: 36px; height: 36px; background-color: rgba(93, 78, 140, 0.12); border-radius: ${radius.sm}; text-align: center; vertical-align: middle;">
                          <img src="https://howru.app/email/icon-clock.png" alt="" width="20" height="20" style="display: block; margin: 8px auto;" />
                        </td>
                      </tr>
                    </table>
                  </td>
                  <td style="padding-left: 12px; vertical-align: middle;">
                    <p style="margin: 0 0 2px 0; font-size: 13px; color: ${colors.textSecondary};">Last Check-in</p>
                    <p style="margin: 0; font-size: 15px; font-weight: 500; color: ${colors.textPrimary};">${lastCheckInText}</p>
                  </td>
                </tr>
              </table>

              ${lastLocation ? `
              <!-- Location Row -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-bottom: ${lastMood ? '16px' : '0'};">
                <tr>
                  <td style="width: 44px; vertical-align: top;">
                    <table role="presentation" cellspacing="0" cellpadding="0">
                      <tr>
                        <td style="width: 36px; height: 36px; background-color: rgba(76, 217, 100, 0.12); border-radius: ${radius.sm}; text-align: center; vertical-align: middle;">
                          <img src="https://howru.app/email/icon-location.png" alt="" width="20" height="20" style="display: block; margin: 8px auto;" />
                        </td>
                      </tr>
                    </table>
                  </td>
                  <td style="padding-left: 12px; vertical-align: middle;">
                    <p style="margin: 0 0 2px 0; font-size: 13px; color: ${colors.textSecondary};">Last Location</p>
                    <p style="margin: 0; font-size: 15px; font-weight: 500; color: ${colors.textPrimary};">${lastLocation}</p>
                  </td>
                </tr>
              </table>
              ` : ''}

              ${lastMood ? `
              <!-- Mood Row -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                <tr>
                  <td style="width: 44px; vertical-align: top;">
                    <table role="presentation" cellspacing="0" cellpadding="0">
                      <tr>
                        <td style="width: 36px; height: 36px; background-color: rgba(232, 90, 60, 0.12); border-radius: ${radius.sm}; text-align: center; vertical-align: middle;">
                          <img src="https://howru.app/email/icon-heart.png" alt="" width="20" height="20" style="display: block; margin: 8px auto;" />
                        </td>
                      </tr>
                    </table>
                  </td>
                  <td style="padding-left: 12px; vertical-align: top;">
                    <p style="margin: 0 0 8px 0; font-size: 13px; color: ${colors.textSecondary};">Last Mood Scores</p>
                    <table role="presentation" cellspacing="0" cellpadding="0">
                      <tr>
                        <td style="padding-right: 8px;">
                          <span style="display: inline-block; padding: 4px 10px; background-color: rgba(93, 78, 140, 0.12); border-radius: 12px; font-size: 13px; color: ${colors.moodMental}; font-weight: 500;">Mental ${lastMood.mental}/5</span>
                        </td>
                        <td style="padding-right: 8px;">
                          <span style="display: inline-block; padding: 4px 10px; background-color: rgba(76, 217, 100, 0.12); border-radius: 12px; font-size: 13px; color: ${colors.moodBody}; font-weight: 500;">Body ${lastMood.body}/5</span>
                        </td>
                        <td>
                          <span style="display: inline-block; padding: 4px 10px; background-color: rgba(232, 90, 60, 0.12); border-radius: 12px; font-size: 13px; color: ${colors.moodEmotional}; font-weight: 500;">Mood ${lastMood.mood}/5</span>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
              ` : ''}

            </td>
          </tr>
        </table>
      </td>
    </tr>

    <!-- CTA Button -->
    <tr>
      <td style="padding: 0 32px 32px 32px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
          <tr>
            <td align="center">
              <a href="https://howru.app" style="display: inline-block; padding: 14px 32px; background-color: ${colors.buttonBg}; color: ${colors.buttonText}; text-decoration: none; font-size: 15px; font-weight: 500; border-radius: ${radius.lg};">
                Open HowRU
              </a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  `;
    const html = baseTemplate(content, `You're receiving this because you're a checker for ${userName} on HowRU.`);
    const result = await resend.emails.send({
        from: FROM_EMAIL,
        to,
        subject: config.subject,
        html,
    });
    return result;
}
// ============================================================================
// WELCOME EMAIL
// ============================================================================
async function sendWelcomeEmail(to, name) {
    const content = `
    <!-- Title -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <h1 style="margin: 0; font-family: ${fonts.headline}; font-size: 28px; font-weight: 400; color: ${colors.textPrimary}; text-align: center; line-height: 1.3;">
          Welcome to HowRU
        </h1>
      </td>
    </tr>

    <!-- Message -->
    <tr>
      <td style="padding: 0 32px 32px 32px;">
        <p style="margin: 0; font-size: 15px; color: ${colors.textSecondary}; text-align: center; line-height: 1.6;">
          Hi ${name}, thanks for joining HowRU. We're here to help you stay connected with the people who care about you.
        </p>
      </td>
    </tr>

    <!-- Getting Started Card -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: ${colors.backgroundWarm}; border-radius: ${radius.lg};">
          <tr>
            <td style="padding: 24px;">
              <p style="margin: 0 0 16px 0; font-family: ${fonts.headline}; font-size: 18px; color: ${colors.textPrimary};">Getting Started</p>

              <!-- Step 1 -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-bottom: 12px;">
                <tr>
                  <td style="width: 32px; vertical-align: top;">
                    <table role="presentation" cellspacing="0" cellpadding="0">
                      <tr>
                        <td style="width: 24px; height: 24px; background-color: ${colors.coral}; border-radius: 50%; text-align: center; vertical-align: middle;">
                          <span style="color: white; font-size: 12px; font-weight: 600; line-height: 24px;">1</span>
                        </td>
                      </tr>
                    </table>
                  </td>
                  <td style="padding-left: 12px; vertical-align: middle;">
                    <p style="margin: 0; font-size: 15px; color: ${colors.textPrimary};">Set up your daily check-in schedule</p>
                  </td>
                </tr>
              </table>

              <!-- Step 2 -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-bottom: 12px;">
                <tr>
                  <td style="width: 32px; vertical-align: top;">
                    <table role="presentation" cellspacing="0" cellpadding="0">
                      <tr>
                        <td style="width: 24px; height: 24px; background-color: ${colors.coral}; border-radius: 50%; text-align: center; vertical-align: middle;">
                          <span style="color: white; font-size: 12px; font-weight: 600; line-height: 24px;">2</span>
                        </td>
                      </tr>
                    </table>
                  </td>
                  <td style="padding-left: 12px; vertical-align: middle;">
                    <p style="margin: 0; font-size: 15px; color: ${colors.textPrimary};">Invite trusted people to your circle</p>
                  </td>
                </tr>
              </table>

              <!-- Step 3 -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                <tr>
                  <td style="width: 32px; vertical-align: top;">
                    <table role="presentation" cellspacing="0" cellpadding="0">
                      <tr>
                        <td style="width: 24px; height: 24px; background-color: ${colors.coral}; border-radius: 50%; text-align: center; vertical-align: middle;">
                          <span style="color: white; font-size: 12px; font-weight: 600; line-height: 24px;">3</span>
                        </td>
                      </tr>
                    </table>
                  </td>
                  <td style="padding-left: 12px; vertical-align: middle;">
                    <p style="margin: 0; font-size: 15px; color: ${colors.textPrimary};">Complete your first check-in</p>
                  </td>
                </tr>
              </table>

            </td>
          </tr>
        </table>
      </td>
    </tr>

    <!-- CTA Button -->
    <tr>
      <td style="padding: 0 32px 32px 32px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
          <tr>
            <td align="center">
              <a href="https://howru.app" style="display: inline-block; padding: 14px 32px; background-color: ${colors.buttonBg}; color: ${colors.buttonText}; text-decoration: none; font-size: 15px; font-weight: 500; border-radius: ${radius.lg};">
                Open HowRU
              </a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  `;
    const html = baseTemplate(content, 'Questions? Reply to this email or visit our Help Center.');
    return resend.emails.send({
        from: FROM_EMAIL,
        to,
        subject: 'Welcome to HowRU',
        html,
    });
}
// ============================================================================
// POKE NOTIFICATION EMAIL
// ============================================================================
async function sendPokeEmail(to, recipientName, senderName, message) {
    const content = `
    <!-- Title -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <h1 style="margin: 0; font-family: ${fonts.headline}; font-size: 24px; font-weight: 400; color: ${colors.textPrimary}; text-align: center; line-height: 1.3;">
          ${senderName} is thinking of you
        </h1>
      </td>
    </tr>

    <!-- Message -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <p style="margin: 0; font-size: 15px; color: ${colors.textSecondary}; text-align: center; line-height: 1.6;">
          Hi ${recipientName}, ${senderName} sent you a poke on HowRU to check in on you.
        </p>
      </td>
    </tr>

    ${message ? `
    <!-- Personal Message -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: ${colors.backgroundWarm}; border-radius: ${radius.lg}; border-left: 4px solid ${colors.coral};">
          <tr>
            <td style="padding: 16px 20px;">
              <p style="margin: 0; font-size: 15px; color: ${colors.textPrimary}; font-style: italic; line-height: 1.5;">
                "${message}"
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
    ` : ''}

    <!-- CTA Button -->
    <tr>
      <td style="padding: 0 32px 32px 32px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
          <tr>
            <td align="center">
              <a href="https://howru.app" style="display: inline-block; padding: 14px 32px; background-color: ${colors.buttonBg}; color: ${colors.buttonText}; text-decoration: none; font-size: 15px; font-weight: 500; border-radius: ${radius.lg};">
                Open HowRU to Respond
              </a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  `;
    const html = baseTemplate(content);
    return resend.emails.send({
        from: FROM_EMAIL,
        to,
        subject: `${senderName} sent you a poke on HowRU`,
        html,
    });
}
// ============================================================================
// CIRCLE INVITE EMAIL
// ============================================================================
async function sendExportReadyEmail(params) {
    const { to, userName, exportId, format } = params;
    const content = `
    <!-- Title -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <h1 style="margin: 0; font-family: ${fonts.headline}; font-size: 24px; font-weight: 400; color: ${colors.textPrimary}; text-align: center; line-height: 1.3;">
          Your Data Export is Ready
        </h1>
      </td>
    </tr>

    <!-- Message -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <p style="margin: 0; font-size: 15px; color: ${colors.textSecondary}; text-align: center; line-height: 1.6;">
          Hi ${userName}, your data export (${format.toUpperCase()}) is ready to download. The download link will expire in 24 hours.
        </p>
      </td>
    </tr>

    <!-- CTA Button -->
    <tr>
      <td style="padding: 0 32px 32px 32px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
          <tr>
            <td align="center">
              <a href="https://howru.app/exports/${exportId}" style="display: inline-block; padding: 14px 32px; background-color: ${colors.buttonBg}; color: ${colors.buttonText}; text-decoration: none; font-size: 15px; font-weight: 500; border-radius: ${radius.lg};">
                Download Export
              </a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  `;
    const html = baseTemplate(content, 'You requested this export from the HowRU app.');
    return resend.emails.send({
        from: FROM_EMAIL,
        to,
        subject: 'Your HowRU Data Export is Ready',
        html,
    });
}
// ============================================================================
// CIRCLE INVITE EMAIL
// ============================================================================
async function sendCircleInviteEmail(to, inviterName, role, inviteCode) {
    const roleDescription = role === 'supporter'
        ? `${inviterName} wants you to be part of their care circle as a supporter. You'll receive notifications if they miss their daily check-ins.`
        : `${inviterName} wants to join your care circle to help keep an eye on your wellbeing.`;
    const content = `
    <!-- Title -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <h1 style="margin: 0; font-family: ${fonts.headline}; font-size: 24px; font-weight: 400; color: ${colors.textPrimary}; text-align: center; line-height: 1.3;">
          ${inviterName} invited you to HowRU
        </h1>
      </td>
    </tr>

    <!-- Message -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <p style="margin: 0; font-size: 15px; color: ${colors.textSecondary}; text-align: center; line-height: 1.6;">
          ${roleDescription}
        </p>
      </td>
    </tr>

    <!-- What is HowRU Card -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: ${colors.backgroundWarm}; border-radius: ${radius.lg};">
          <tr>
            <td style="padding: 24px;">
              <p style="margin: 0 0 12px 0; font-family: ${fonts.headline}; font-size: 18px; color: ${colors.textPrimary};">What is HowRU?</p>
              <p style="margin: 0; font-size: 15px; color: ${colors.textSecondary}; line-height: 1.6;">
                HowRU is a simple app that helps people stay connected through daily check-ins. If someone misses their check-in, their trusted circle gets notified.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>

    ${inviteCode ? `
    <!-- Invite Code -->
    <tr>
      <td style="padding: 0 32px 24px 32px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: ${colors.coralGlow}; border-radius: ${radius.lg};">
          <tr>
            <td style="padding: 20px; text-align: center;">
              <p style="margin: 0 0 8px 0; font-size: 13px; color: ${colors.textSecondary};">Your invite code</p>
              <p style="margin: 0; font-family: monospace; font-size: 28px; font-weight: 600; color: ${colors.coral}; letter-spacing: 3px;">${inviteCode}</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
    ` : ''}

    <!-- CTA Button -->
    <tr>
      <td style="padding: 0 32px 32px 32px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
          <tr>
            <td align="center">
              <a href="https://howru.app/invite${inviteCode ? `?code=${inviteCode}` : ''}" style="display: inline-block; padding: 14px 32px; background-color: ${colors.buttonBg}; color: ${colors.buttonText}; text-decoration: none; font-size: 15px; font-weight: 500; border-radius: ${radius.lg};">
                Accept Invitation
              </a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  `;
    const html = baseTemplate(content, "If you didn't expect this invitation, you can safely ignore this email.");
    return resend.emails.send({
        from: FROM_EMAIL,
        to,
        subject: `${inviterName} invited you to join their circle on HowRU`,
        html,
    });
}
exports.default = resend;
//# sourceMappingURL=resend.js.map