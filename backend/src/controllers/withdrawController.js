import { pool, withTransaction } from '../db.js';

// Tabela de valores permitidos e conversão em pontos
const VALORES_PERMITIDOS = {
  0.50: { pontos: 5000, apenasPrimeiroSaque: true },
  2.00: { pontos: 20000, apenasPrimeiroSaque: false },
  5.00: { pontos: 50000, apenasPrimeiroSaque: false }
};

export async function requestWithdraw(req, res) {
  try {
    const userId = req.user.id;
    const { valor_reais, chave_pix, tipo_chave } = req.body;

    const valorFloat = parseFloat(valor_reais);
    const regraValor = VALORES_PERMITIDOS[valorFloat];

    if (!regraValor) {
      return res.status(400).json({
        error: 'Valor de saque inválido. Os valores válidos são R$ 0,50, R$ 2,00 ou R$ 5,00.'
      });
    }

    if (!chave_pix || !tipo_chave) {
      return res.status(400).json({ error: 'Chave PIX e tipo da chave são obrigatórios.' });
    }

    const pontosNecessarios = regraValor.pontos;

    // Transação ACID com isolamento rigoroso
    const withdrawRecord = await withTransaction(async (client) => {
      // Bloqueio pessimista para evitar concorrência/double spending
      const userRes = await client.query(
        'SELECT id, saldo_pontos, total_saques_realizados FROM users WHERE id = $1 FOR UPDATE',
        [userId]
      );

      if (userRes.rows.length === 0) {
        throw new Error('USER_NOT_FOUND');
      }

      const user = userRes.rows[0];
      const saldoAtual = Number(user.saldo_pontos);
      const totalSaques = user.total_saques_realizados;

      // Validação da regra do 1º Saque (R$ 0,50)
      if (valorFloat === 0.50 && totalSaques > 0) {
        throw new Error('FIRST_WITHDRAW_ALREADY_USED');
      }

      // Validação do saldo suficiente
      if (saldoAtual < pontosNecessarios) {
        throw new Error('INSUFFICIENT_POINTS');
      }

      // Checa se há algum saque 'pendente' ou 'processando' em aberto (evita flood)
      const pendingRes = await client.query(
        `SELECT id FROM withdrawals 
         WHERE user_id = $1 AND status IN ('pendente', 'processando') 
         LIMIT 1`,
        [userId]
      );

      if (pendingRes.rows.length > 0) {
        throw new Error('PENDING_WITHDRAW_EXISTS');
      }

      // 1. Debita os pontos do saldo e incrementa o contador de saques
      await client.query(
        `UPDATE users 
         SET saldo_pontos = saldo_pontos - $1, 
             total_saques_realizados = total_saques_realizados + 1,
             chave_pix = COALESCE($2, chave_pix),
             tipo_chave = COALESCE($3, tipo_chave),
             updated_at = NOW() 
         WHERE id = $4`,
        [pontosNecessarios, chave_pix, tipo_chave, userId]
      );

      // 2. Insere a solicitação de saque na tabela
      const insertRes = await client.query(
        `INSERT INTO withdrawals (user_id, valor_reais, pontos_descontados, chave_pix, tipo_chave, status)
         VALUES ($1, $2, $3, $4, $5, 'pendente')
         RETURNING id, valor_reais, pontos_descontados, chave_pix, tipo_chave, status, created_at`,
        [userId, valorFloat, pontosNecessarios, chave_pix, tipo_chave]
      );

      return insertRes.rows[0];
    });

    // TODO: Aqui pode ser despachado um Job para a fila (BullMQ / RabbitMQ) ou chamado direto a API do Mercado Pago / Asaas PIX

    return res.status(201).json({
      message: 'Solicitação de saque PIX registrada com sucesso!',
      saque: withdrawRecord
    });

  } catch (error) {
    if (error.message === 'FIRST_WITHDRAW_ALREADY_USED') {
      return res.status(400).json({
        error: 'O saque promocional de R$ 0,50 é exclusivo para o 1º resgate. Para saques futuros, a meta mínima é R$ 2,00 (20.000 pontos).'
      });
    }
    if (error.message === 'INSUFFICIENT_POINTS') {
      return res.status(400).json({ error: 'Saldo de pontos insuficiente para este resgate.' });
    }
    if (error.message === 'PENDING_WITHDRAW_EXISTS') {
      return res.status(400).json({
        error: 'Você já possui uma solicitação de saque em análise. Aguarde a conclusão do pagamento anterior.'
      });
    }
    if (error.message === 'USER_NOT_FOUND') {
      return res.status(404).json({ error: 'Usuário não encontrado.' });
    }

    console.error('Erro ao processar saque:', error);
    return res.status(500).json({ error: 'Erro interno ao processar o saque.' });
  }
}

export async function getWithdrawHistory(req, res) {
  try {
    const userId = req.user.id;

    const result = await pool.query(
      `SELECT id, valor_reais, pontos_descontados, chave_pix, tipo_chave, status, gateway_reference, created_at, updated_at
       FROM withdrawals 
       WHERE user_id = $1 
       ORDER BY created_at DESC`,
      [userId]
    );

    return res.json({
      saques: result.rows
    });
  } catch (error) {
    console.error('Erro ao obter histórico de saques:', error);
    return res.status(500).json({ error: 'Erro ao buscar histórico de saques.' });
  }
}
