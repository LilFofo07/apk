import rateLimit from 'express-rate-limit';

// Limitador geral de API (100 req por 15 min)
export const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { error: 'Muitas requisições deste IP. Tente novamente mais tarde.' },
  standardHeaders: true,
  legacyHeaders: false,
});

// Limitador de Login e Cadastro (anti-força bruta)
export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 15,
  message: { error: 'Muitas tentativas de autenticação. Aguarde 15 minutos.' },
  standardHeaders: true,
  legacyHeaders: false,
});

// Limitador de pedido de saque
export const withdrawLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 3,
  message: { error: 'Muitas solicitações de saque seguidas. Aguarde 1 minuto.' },
  standardHeaders: true,
  legacyHeaders: false,
});
