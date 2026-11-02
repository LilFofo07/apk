import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import apiRoutes from './routes/api.js';
import { generalLimiter } from './middlewares/rateLimiter.js';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// Configurações de segurança e middlewares globais
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(generalLimiter);

// Health check para monitoramento e balanceadores de carga
app.get('/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

// Rotas da aplicação sob o prefixo /api
app.use('/api', apiRoutes);

// Tratamento de rotas inexistentes
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint não encontrado.' });
});

// Inicia o servidor HTTP
app.listen(PORT, () => {
  console.log(`=======================================================`);
  console.log(`🚀 Rewards Pay-To-Watch Backend rodando na porta ${PORT}`);
  console.log(`📡 SSV Webhook URL: http://localhost:${PORT}/api/ads/verify-reward`);
  console.log(`🛡️  Ambiente: ${process.env.NODE_ENV || 'development'}`);
  console.log(`=======================================================`);
});
