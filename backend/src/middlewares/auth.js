import jwt from 'jsonwebtoken';

export function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Token de autenticação não fornecido' });
  }

  jwt.verify(token, process.env.JWT_SECRET || 'super_secret_jwt_key_32chars_long_min', (err, user) => {
    if (err) {
      return res.status(403).json({ error: 'Sessão expirada ou token inválido' });
    }
    req.user = user; // { id, email }
    next();
  });
}
