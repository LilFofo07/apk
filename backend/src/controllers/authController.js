import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { pool } from '../db.js';

export async function register(req, res) {
  try {
    const { nome, email, senha, device_id, chave_pix, tipo_chave } = req.body;
    const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

    if (!nome || !email || !senha || !device_id) {
      return res.status(400).json({ error: 'Nome, e-mail, senha e identificador do aparelho são obrigatórios.' });
    }

    // REGRA ANTI-FRAUDE: 1 Conta por Aparelho Físico (Device ID)
    const deviceCheck = await pool.query(
      'SELECT id, email FROM users WHERE device_id = $1 LIMIT 1',
      [device_id]
    );

    if (deviceCheck.rows.length > 0) {
      // Registra evento de segurança para auditoria
      await pool.query(
        `INSERT INTO security_events (device_id, event_type, details, ip_address)
         VALUES ($1, 'MULTIPLE_ACCOUNTS_ATTEMPT', $2, $3)`,
        [device_id, `Tentativa de criar conta duplicada com email ${email}`, clientIp]
      );

      return res.status(409).json({
        error: 'Este aparelho já está associado a outra conta. A política de recompensas permite apenas 1 conta por dispositivo.'
      });
    }

    // Checa se o e-mail já existe
    const emailCheck = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
    if (emailCheck.rows.length > 0) {
      return res.status(409).json({ error: 'Este e-mail já está em uso.' });
    }

    // Hash da senha
    const saltRounds = 10;
    const senha_hash = await bcrypt.hash(senha, saltRounds);

    const result = await pool.query(
      `INSERT INTO users (nome, email, senha_hash, device_id, last_ip, chave_pix, tipo_chave)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, nome, email, saldo_pontos, total_saques_realizados, created_at`,
      [nome, email, senha_hash, device_id, clientIp, chave_pix || null, tipo_chave || null]
    );

    const newUser = result.rows[0];

    // Gera token JWT
    const token = jwt.sign(
      { id: newUser.id, email: newUser.email },
      process.env.JWT_SECRET || 'super_secret_jwt_key_32chars_long_min',
      { expiresIn: '30d' }
    );

    return res.status(201).json({
      message: 'Usuário registrado com sucesso!',
      user: {
        id: newUser.id,
        nome: newUser.nome,
        email: newUser.email,
        saldo_pontos: Number(newUser.saldo_pontos),
        saldo_reais: Number(newUser.saldo_pontos) / 10000,
        total_saques_realizados: newUser.total_saques_realizados
      },
      token
    });
  } catch (error) {
    console.error('Erro no registro:', error);
    return res.status(500).json({ error: 'Erro interno ao cadastrar usuário.' });
  }
}

export async function login(req, res) {
  try {
    const { email, senha, device_id } = req.body;
    const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

    if (!email || !senha) {
      return res.status(400).json({ error: 'E-mail e senha são obrigatórios.' });
    }

    const result = await pool.query('SELECT * FROM users WHERE email = $1', [email]);
    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Credenciais inválidas.' });
    }

    const user = result.rows[0];

    if (!user.is_active) {
      return res.status(403).json({ error: 'Conta suspensa por suspeita de fraude.' });
    }

    const senhaCorreta = await bcrypt.compare(senha, user.senha_hash);
    if (!senhaCorreta) {
      return res.status(401).json({ error: 'Credenciais inválidas.' });
    }

    // Atualiza last_ip e device_id se informado
    await pool.query(
      'UPDATE users SET last_ip = $1, device_id = COALESCE($2, device_id), updated_at = NOW() WHERE id = $3',
      [clientIp, device_id || null, user.id]
    );

    const token = jwt.sign(
      { id: user.id, email: user.email },
      process.env.JWT_SECRET || 'super_secret_jwt_key_32chars_long_min',
      { expiresIn: '30d' }
    );

    return res.json({
      message: 'Login realizado com sucesso!',
      user: {
        id: user.id,
        nome: user.nome,
        email: user.email,
        chave_pix: user.chave_pix,
        tipo_chave: user.tipo_chave,
        saldo_pontos: Number(user.saldo_pontos),
        saldo_reais: Number(user.saldo_pontos) / 10000,
        total_saques_realizados: user.total_saques_realizados
      },
      token
    });
  } catch (error) {
    console.error('Erro no login:', error);
    return res.status(500).json({ error: 'Erro interno ao realizar login.' });
  }
}
