import { pool } from '../db.js';

export async function getBalance(req, res) {
  try {
    const userId = req.user.id;

    const result = await pool.query(
      `SELECT id, nome, email, saldo_pontos, total_saques_realizados, chave_pix, tipo_chave 
       FROM users 
       WHERE id = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Usuário não encontrado.' });
    }

    const user = result.rows[0];
    const saldoPontos = Number(user.saldo_pontos);
    // Conversão: 100 pontos = R$ 0,01 -> 1.000 pontos = R$ 0,10 -> pontos / 10000 = valor em R$
    const saldoReais = Number((saldoPontos / 10000).toFixed(2));

    // Determina o mínimo do próximo saque com base no histórico
    const isPrimeiroSaque = user.total_saques_realizados === 0;
    const minimoPontos = isPrimeiroSaque ? 5000 : 20000;
    const minimoReais = isPrimeiroSaque ? 0.50 : 2.00;

    return res.json({
      userId: user.id,
      nome: user.nome,
      saldo_pontos: saldoPontos,
      saldo_reais: saldoReais,
      total_saques_realizados: user.total_saques_realizados,
      proximo_saque_minimo: {
        pontos: minimoPontos,
        reais: minimoReais,
        is_primeiro_saque: isPrimeiroSaque,
        pode_sacar: saldoPontos >= minimoPontos
      },
      pix_cadastrado: {
        chave: user.chave_pix,
        tipo: user.tipo_chave
      }
    });
  } catch (error) {
    console.error('Erro ao consultar saldo:', error);
    return res.status(500).json({ error: 'Erro ao obter saldo.' });
  }
}
