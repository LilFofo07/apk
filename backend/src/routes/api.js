import { Router } from 'express';
import { register, login } from '../controllers/authController.js';
import { verifyRewardWebhook } from '../controllers/adsController.js';
import { getBalance } from '../controllers/userController.js';
import { requestWithdraw, getWithdrawHistory } from '../controllers/withdrawController.js';
import { authenticateToken } from '../middlewares/auth.js';
import { authLimiter, withdrawLimiter } from '../middlewares/rateLimiter.js';

const router = Router();

// ==========================================
// 1. ROTAS DE AUTENTICAÇÃO
// ==========================================
router.post('/auth/register', authLimiter, register);
router.post('/auth/login', authLimiter, login);

// ==========================================
// 2. WEBHOOK SSV (SERVER-SIDE VERIFICATION)
// Suporta POST e GET (conforme padrão das Ad Networks)
// Não exige token JWT de usuário, mas valida assinatura criptográfica da ad network
// ==========================================
router.post('/ads/verify-reward', verifyRewardWebhook);
router.get('/ads/verify-reward', verifyRewardWebhook);

// ==========================================
// 3. ROTAS DE USUÁRIO (PROTEGIDAS COM JWT)
// ==========================================
router.get('/user/balance', authenticateToken, getBalance);

// ==========================================
// 4. ROTAS DE SAQUE (PIX)
// ==========================================
router.post('/withdraw', authenticateToken, withdrawLimiter, requestWithdraw);
router.get('/withdraw/history', authenticateToken, getWithdrawHistory);

export default router;
