"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const auth_js_1 = __importDefault(require("./routes/auth.js"));
const checkins_js_1 = __importDefault(require("./routes/checkins.js"));
const webhooks_js_1 = __importDefault(require("./routes/webhooks.js"));
const circle_js_1 = __importDefault(require("./routes/circle.js"));
const pokes_js_1 = __importDefault(require("./routes/pokes.js"));
const alerts_js_1 = __importDefault(require("./routes/alerts.js"));
const users_js_1 = __importDefault(require("./routes/users.js"));
const voice_js_1 = __importDefault(require("./routes/voice.js"));
const uploads_js_1 = __importDefault(require("./routes/uploads.js"));
const exports_js_1 = __importDefault(require("./routes/exports.js"));
const app = (0, express_1.default)();
const PORT = process.env.PORT || 3000;
// Middleware
app.use((0, cors_1.default)());
app.use(express_1.default.json());
// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});
// Routes
app.use('/auth', auth_js_1.default);
app.use('/checkins', checkins_js_1.default);
app.use('/webhooks', webhooks_js_1.default);
app.use('/circle', circle_js_1.default);
app.use('/pokes', pokes_js_1.default);
app.use('/alerts', alerts_js_1.default);
app.use('/users', users_js_1.default);
app.use('/voice', voice_js_1.default);
app.use('/uploads', uploads_js_1.default);
app.use('/exports', exports_js_1.default);
// Error handler
app.use((err, req, res, next) => {
    console.error('Unhandled error:', err);
    res.status(500).json({
        success: false,
        error: 'Internal server error',
    });
});
// Start server
app.listen(PORT, () => {
    console.log(`🚀 HowRU API server running on port ${PORT}`);
    console.log(`   Health check: http://localhost:${PORT}/health`);
});
exports.default = app;
//# sourceMappingURL=index.js.map