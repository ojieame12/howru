import { Resend } from 'resend';
declare const resend: Resend;
interface AlertEmailParams {
    to: string;
    checkerName: string;
    userName: string;
    alertLevel: 'reminder' | 'soft' | 'hard' | 'escalation';
    lastCheckIn?: Date;
    lastLocation?: string;
    lastMood?: {
        mental: number;
        body: number;
        mood: number;
    };
}
export declare function sendAlertEmail(params: AlertEmailParams): Promise<import("resend").CreateEmailResponse>;
export declare function sendWelcomeEmail(to: string, name: string): Promise<import("resend").CreateEmailResponse>;
export declare function sendPokeEmail(to: string, recipientName: string, senderName: string, message?: string): Promise<import("resend").CreateEmailResponse>;
export declare function sendExportReadyEmail(params: {
    to: string;
    userName: string;
    exportId: string;
    format: 'json' | 'csv';
}): Promise<import("resend").CreateEmailResponse>;
export declare function sendCircleInviteEmail(to: string, inviterName: string, role: 'checker' | 'supporter', inviteCode?: string): Promise<import("resend").CreateEmailResponse>;
export default resend;
//# sourceMappingURL=resend.d.ts.map