import crypto from 'crypto';
import { pool, withTransaction } from '../db.js';

/**
 * Validador de assinatura SSV (AppLovin MAX / AdMob)
 * O AppLovin envia parâmetros via GET ou POST com uma assinatura hash para evitar spoofing.
 */
function verifySsvSignature(secret, params, signature) {
  if (!secret) return true; // Caso não configurado em ambiente dev local
  if (!signature) return false;

  // Monta a string de validação ordenada dos parâmetros
  const sortedKeys = Object.keys(params).filter(k => k !== 'signature' && k !== 'hash').sort();
  const rawString = sortedKeys.map(k => `${k}=${params[k]}`).join('&');
  
  const expectedHash = crypto
    .createHmac('sha256', secret)
    .update(rawString)
    .digest('hex');

  return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expectedHash));
}

export async function verifyRewardWebhook(req, res) {
  try {
    // Redes de anúncios podem enviar via GET query string ou POST body
    const payload = req.method === 'GET' ? req.query : req.body;
    const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

    // Normalização dos campos comuns (AppLovin MAX / AdMob / Unity)
    // custom_data ou user_id contém o ID do usuário cadastrado na nossa plataforma
    const userId = payload.user_id || payload.custom_data || payload.userId;
    const transactionId = payload.event_id || payload.transaction_id || payload.tx_id || payload.transactionId;
    const network = payload.network || 'applovin';
    const signature = payload.signature || payload.sig;

    if (!userId || !transactionId) {
      console.warn('[SSV] Requisição inválida recebida: faltando userId ou transactionId', payload);
      return res.status(400).json({ error: 'Parâmetros obrigatórios ausentes (user_id, transaction_id).' });
    }

    // 1. CHECAGEM DE ASSINATURA CRIPTOGRÁFICA (SSV SECURITY)
    const secret = process.env.AD_NETWORK_SSV_SECRET;
    if (secret && signature && !verifySsvSignature(secret, payload, signature)) {
      console.error('[SSV] Assinatura inválida detectada!', { ip: clientIp, payload });
      await pool.query(
        `INSERT INTO security_events (user_id, event_type, details, ip_address)
         VALUES ($1, 'INVALID_SIGNATURE', $2, $3)`,
        [userId, 'Assinatura inválida no Webhook SSV', clientIp]
      );
      return res.status(403).json({ error: 'Assinatura SSV inválida.' });
    }

    // 2. IDEMPOTÊNCIA: Evita crédito duplicado se a Ad Network reenviar o webhook
    const existingTx = await pool.query(
      'SELECT id, status FROM reward_logs WHERE transaction_id_adnet = $1',
      [transactionId]
    );

    if (existingTx.rows.length > 0) {
      console.log(`[SSV] Transação já processada anteriormente: ${transactionId}`);
      // Responde 200 OK para que a rede de anúncios cesse as tentativas de reenvio
      return res.status(200).json({
        status: 'DUPLICATE',
        message: 'Recompensa já creditada anteriormente.'
      });
    }

    // 3. REGRA ANTI-FRAUDE: Trava de frequência (Cooldown entre vídeos)
    const cooldownSeconds = parseInt(process.env.COOLDOWN_SECONDS_BETWEEN_ADS || '20', 10);
    const lastReward = await pool.query(
      `SELECT created_at FROM reward_logs 
       WHERE user_id = $1 
       ORDER BY created_at DESC LIMIT 1`,
      [userId]
    );

    if (lastReward.rows.length > 0) {
      const diffSeconds = (new Date() - new Date(lastReward.rows[0].created_at)) / 1000;
      if (diffSeconds < cooldownSeconds) {
        console.warn(`[SSV] Alerta: Vídeo assistido rápido demais (${diffSeconds.toFixed(1)}s) pelo usuário ${userId}`);
        await pool.query(
          `INSERT INTO security_events (user_id, event_type, details, ip_address)
           VALUES ($1, 'FAST_WATCH_SUSPICION', $2, $3)`,
          [userId, `Vídeo concluído em apenas ${diffSeconds.toFixed(1)}s (mínimo ${cooldownSeconds}s)`, clientIp]
        );
        // Opcional: Rejeitar ou registrar como suspeito
      }
    }

    const pontosRecompensa = parseInt(process.env.POINTS_PER_REWARD || '100', 10);

    // 4. TRANSAÇÃO ATÔMICA ACID: Insere o log e credita o saldo
    const creditResult = await withTransaction(async (client) => {
      // Confirma existência do usuário
      const userRes = await client.query('SELECT id, saldo_pontos FROM users WHERE id = $1 FOR UPDATE', [userId]);
      if (userRes.rows.length === 0) {
        throw new Error('USER_NOT_FOUND');
      }

      // Insere log com restrição UNIQUE
      await client.query(
        `INSERT INTO reward_logs (user_id, network, transaction_id_adnet, pontos_ganhos, status, ip_address, raw_payload)
         VALUES ($1, $2, $3, $4, 'VALIDATED', $5, $6)`,
        [userId, network, transactionId, pontosRecompensa, clientIp, JSON.stringify(payload)]
      );

      // Credita os pontos do usuário
      const updatedUser = await client.query(
        `UPDATE users 
         SET saldo_pontos = saldo_pontos + $1, updated_at = NOW() 
         WHERE id = $2 
         RETURNING saldo_pontos`,
        [pontosRecompensa, userId]
      );

      return updatedUser.rows[0];
    });

    return res.status(200).json({
      status: 'SUCCESS',
      message: `${pontosRecompensa} pontos creditados com sucesso!`,
      novo_saldo: Number(creditResult.saldo_pontos)
    });

  } catch (error) {
    if (error.message === 'USER_NOT_FOUND') {
      return res.status(404).json({ error: 'Usuário destinatário não localizado.' });
    }
    // Erro de violação de chave única no postgres (caso de corrida raro de requisições simultâneas)
    if (error.code === '23505') {
      return res.status(200).json({ status: 'DUPLICATE', message: 'Recompensa já creditada.' });
    }
    console.error('[SSV] Erro no processamento do webhook:', error);
    return res.status(500).json({ error: 'Erro interno ao validar recompensa.' });
  }
}
