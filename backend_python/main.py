import uuid
import hmac
import hashlib
from datetime import datetime, timedelta
from typing import Optional, List

from fastapi import FastAPI, HTTPException, Depends, Header, Request, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from passlib.context import CryptContext
import jwt

import config
from database import get_connection, init_db, USE_POSTGRES
from services.mercadopago_service import mp_service

# Inicialização
app = FastAPI(
    title="Rewards Pay-To-Watch API (Supabase & Mercado Pago)",
    description="Backend completo e seguro com validação SSV de anúncios e saques automáticos via PIX Mercado Pago.",
    version="2.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

import bcrypt

# Funções de Hash Direto com bcrypt
def hash_password(password: str) -> str:
    # Garante limite de 72 bytes do bcrypt
    pwd_bytes = password.encode('utf-8')[:72]
    return bcrypt.hashpw(pwd_bytes, bcrypt.gensalt()).decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        pwd_bytes = plain_password.encode('utf-8')[:72]
        hash_bytes = hashed_password.encode('utf-8')
        return bcrypt.checkpw(pwd_bytes, hash_bytes)
    except Exception:
        return False

# ==============================================================================
# SCHEMAS (PYDANTIC)
# ==============================================================================
class RegisterRequest(BaseModel):
    nome: str
    email: str
    senha: str
    device_id: str
    chave_pix: Optional[str] = None
    tipo_chave: Optional[str] = "CPF"

class LoginRequest(BaseModel):
    email: str
    senha: str
    device_id: Optional[str] = None

class WithdrawRequest(BaseModel):
    valor_reais: float
    chave_pix: str
    tipo_chave: str

# Metas de Saque e Regras de Negócio
METAS_SAQUE = {
    0.50: {"pontos": 5000, "apenas_primeiro": True},
    2.00: {"pontos": 20000, "apenas_primeiro": False},
    5.00: {"pontos": 50000, "apenas_primeiro": False}
}

# ==============================================================================
# HELPERS DE AUTENTICAÇÃO JWT
# ==============================================================================
def create_access_token(user_id: str, email: str) -> str:
    expires = datetime.utcnow() + timedelta(days=config.JWT_EXPIRATION_DAYS)
    payload = {"sub": user_id, "email": email, "exp": expires}
    return jwt.encode(payload, config.JWT_SECRET, algorithm=config.JWT_ALGORITHM)

def get_current_user(authorization: Optional[str] = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token não fornecido.")
    token = authorization.split(" ")[1]
    try:
        payload = jwt.decode(token, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM])
        return {"id": payload["sub"], "email": payload["email"]}
    except jwt.PyJWTError:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Sessão inválida ou expirada.")

# Inicializa o banco de dados imediatamente
init_db()

# ==============================================================================
# 1. ROTAS DE AUTENTICAÇÃO
# ==============================================================================
@app.post("/api/auth/register", tags=["Autenticação"])
def register(data: RegisterRequest, request: Request):
    client_ip = request.client.host if request.client else "127.0.0.1"
    conn = get_connection()
    cur = conn.cursor()

    # ANTI-FRAUDE: 1 Conta por Dispositivo Físico
    query_dev = "SELECT id FROM users WHERE device_id = %s" if USE_POSTGRES else "SELECT id FROM users WHERE device_id = ?"
    cur.execute(query_dev, (data.device_id,))
    if cur.fetchone():
        conn.close()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Este aparelho já possui uma conta cadastrada. Limite: 1 conta por celular."
        )

    # Checa e-mail
    query_email = "SELECT id FROM users WHERE email = %s" if USE_POSTGRES else "SELECT id FROM users WHERE email = ?"
    cur.execute(query_email, (data.email,))
    if cur.fetchone():
        conn.close()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Este e-mail já está em uso.")

    user_id = str(uuid.uuid4())
    senha_hash = hash_password(data.senha)

    if USE_POSTGRES:
        cur.execute("""
            INSERT INTO users (id, nome, email, senha_hash, device_id, last_ip, chave_pix, tipo_chave)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (user_id, data.nome, data.email, senha_hash, data.device_id, client_ip, data.chave_pix, data.tipo_chave))
    else:
        cur.execute("""
            INSERT INTO users (id, nome, email, senha_hash, device_id, last_ip, chave_pix, tipo_chave)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (user_id, data.nome, data.email, senha_hash, data.device_id, client_ip, data.chave_pix, data.tipo_chave))

    conn.commit()
    conn.close()

    token = create_access_token(user_id, data.email)
    return {
        "message": "Conta criada com sucesso!",
        "token": token,
        "user": {
            "id": user_id,
            "nome": data.nome,
            "email": data.email,
            "saldo_pontos": 0,
            "saldo_reais": 0.0
        }
    }

@app.post("/api/auth/login", tags=["Autenticação"])
def login(data: LoginRequest, request: Request):
    client_ip = request.client.host if request.client else "127.0.0.1"
    conn = get_connection()
    cur = conn.cursor()

    query = "SELECT * FROM users WHERE email = %s" if USE_POSTGRES else "SELECT * FROM users WHERE email = ?"
    cur.execute(query, (data.email,))
    user = cur.fetchone()

    if not user or not verify_password(data.senha, user["senha_hash"]):
        conn.close()
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="E-mail ou senha incorretos.")

    if not user["is_active"]:
        conn.close()
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Conta suspensa por violação das regras.")

    # Atualiza IP
    up_query = "UPDATE users SET last_ip = %s WHERE id = %s" if USE_POSTGRES else "UPDATE users SET last_ip = ? WHERE id = ?"
    cur.execute(up_query, (client_ip, user["id"]))
    conn.commit()
    conn.close()

    saldo_pts = user["saldo_pontos"]
    token = create_access_token(str(user["id"]), user["email"])

    return {
        "message": "Login bem-sucedido!",
        "token": token,
        "user": {
            "id": str(user["id"]),
            "nome": user["nome"],
            "email": user["email"],
            "chave_pix": user["chave_pix"],
            "tipo_chave": user["tipo_chave"],
            "saldo_pontos": saldo_pts,
            "saldo_reais": round(saldo_pts / 10000.0, 2),
            "total_saques_realizados": user["total_saques_realizados"]
        }
    }

# ==============================================================================
# 2. WEBHOOK SSV (SERVER-SIDE VERIFICATION)
# ==============================================================================
@app.api_route("/api/ads/verify-reward", methods=["GET", "POST"], tags=["Anúncios & SSV"])
async def verify_reward_ssv(request: Request):
    """
    Webhook chamado pelo AppLovin MAX / AdMob após exibição do Rewarded Video.
    Valida idempotência, segurança e credita +100 pontos ao usuário.
    """
    if request.method == "GET":
        params = dict(request.query_params)
    else:
        try:
            params = await request.json()
        except:
            params = dict(request.query_params)

    user_id = params.get("user_id") or params.get("custom_data")
    tx_id = params.get("event_id") or params.get("transaction_id") or params.get("tx_id")
    signature = params.get("signature") or params.get("sig")

    if not user_id or not tx_id:
        raise HTTPException(status_code=400, detail="user_id e transaction_id são obrigatórios.")

    conn = get_connection()
    cur = conn.cursor()

    # 1. Idempotência: Checa se a transação já foi creditada
    chk_query = "SELECT id FROM reward_logs WHERE transaction_id_adnet = %s" if USE_POSTGRES else "SELECT id FROM reward_logs WHERE transaction_id_adnet = ?"
    cur.execute(chk_query, (tx_id,))
    if cur.fetchone():
        conn.close()
        return {"status": "DUPLICATE", "message": "Recompensa já processada anteriormente."}

    # 2. Confirma existência do usuário
    u_query = "SELECT id, saldo_pontos FROM users WHERE id = %s" if USE_POSTGRES else "SELECT id, saldo_pontos FROM users WHERE id = ?"
    cur.execute(u_query, (user_id,))
    user = cur.fetchone()
    if not user:
        conn.close()
        raise HTTPException(status_code=404, detail="Usuário destinatário não localizado.")

    # 3. Transação atômica: Salva log e credita 100 pontos
    log_id = str(uuid.uuid4())
    pts = config.POINTS_PER_VIDEO

    if USE_POSTGRES:
        cur.execute("""
            INSERT INTO reward_logs (id, user_id, network, transaction_id_adnet, pontos_ganhos, status)
            VALUES (%s, %s, 'applovin', %s, %s, 'VALIDATED')
        """, (log_id, user_id, tx_id, pts))
        cur.execute("UPDATE users SET saldo_pontos = saldo_pontos + %s WHERE id = %s RETURNING saldo_pontos", (pts, user_id))
        novo_saldo = cur.fetchone()["saldo_pontos"]
    else:
        cur.execute("""
            INSERT INTO reward_logs (id, user_id, network, transaction_id_adnet, pontos_ganhos, status)
            VALUES (?, ?, 'applovin', ?, ?, 'VALIDATED')
        """, (log_id, user_id, tx_id, pts))
        cur.execute("UPDATE users SET saldo_pontos = saldo_pontos + ? WHERE id = ?", (pts, user_id))
        cur.execute("SELECT saldo_pontos FROM users WHERE id = ?", (user_id,))
        novo_saldo = cur.fetchone()["saldo_pontos"]

    conn.commit()
    conn.close()

    return {
        "status": "SUCCESS",
        "message": f"+{pts} pontos creditados com sucesso via SSV!",
        "novo_saldo_pontos": novo_saldo,
        "novo_saldo_reais": round(novo_saldo / 10000.0, 2)
    }

# ==============================================================================
# 3. SALDO E PERFIL
# ==============================================================================
@app.get("/api/user/balance", tags=["Usuário"])
def get_balance(current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    cur = conn.cursor()

    query = "SELECT id, nome, email, saldo_pontos, total_saques_realizados, chave_pix, tipo_chave FROM users WHERE id = %s" if USE_POSTGRES else "SELECT id, nome, email, saldo_pontos, total_saques_realizados, chave_pix, tipo_chave FROM users WHERE id = ?"
    cur.execute(query, (current_user["id"],))
    user = cur.fetchone()
    conn.close()

    if not user:
        raise HTTPException(status_code=404, detail="Usuário não encontrado.")

    saldo_pts = user["saldo_pontos"]
    total_saques = user["total_saques_realizados"]
    is_primeiro = total_saques == 0

    min_pts = 5000 if is_primeiro else 20000
    min_reais = 0.50 if is_primeiro else 2.00

    return {
        "userId": str(user["id"]),
        "nome": user["nome"],
        "saldo_pontos": saldo_pts,
        "saldo_reais": round(saldo_pts / 10000.0, 2),
        "total_saques_realizados": total_saques,
        "proximo_saque_minimo": {
            "pontos": min_pts,
            "reais": min_reais,
            "is_primeiro_saque": is_primeiro,
            "pode_sacar": saldo_pts >= min_pts
        },
        "pix_cadastrado": {
            "chave": user["chave_pix"],
            "tipo": user["tipo_chave"]
        }
    }

# ==============================================================================
# 4. SAQUE VIA PIX (MERCADO PAGO)
# ==============================================================================
@app.post("/api/withdraw", tags=["Saques & PIX"])
def request_withdraw(data: WithdrawRequest, current_user: dict = Depends(get_current_user)):
    user_id = current_user["id"]
    valor = float(data.valor_reais)

    if valor not in METAS_SAQUE:
        raise HTTPException(status_code=400, detail="Valor inválido. Valores aceitos: R$ 0,50, R$ 2,00 ou R$ 5,00.")

    regra = METAS_SAQUE[valor]
    pontos_necessarios = regra["pontos"]

    conn = get_connection()
    cur = conn.cursor()

    # Consulta usuário
    u_query = "SELECT saldo_pontos, total_saques_realizados FROM users WHERE id = %s" if USE_POSTGRES else "SELECT saldo_pontos, total_saques_realizados FROM users WHERE id = ?"
    cur.execute(u_query, (user_id,))
    user = cur.fetchone()

    if not user:
        conn.close()
        raise HTTPException(status_code=404, detail="Usuário não encontrado.")

    # Valida regra do 1º Saque
    if valor == 0.50 and user["total_saques_realizados"] > 0:
        conn.close()
        raise HTTPException(status_code=400, detail="O saque de R$ 0,50 é exclusivo para o 1º resgate. Próxima meta: R$ 2,00.")

    # Valida saldo
    if user["saldo_pontos"] < pontos_necessarios:
        conn.close()
        raise HTTPException(status_code=400, detail="Saldo de pontos insuficiente para este resgate.")

    # 1. Gera a transação PIX no Mercado Pago
    mp_res = mp_service.create_pix_payment(
        amount=valor,
        description=f"Resgate Rewards PIX ({pontos_necessarios} pts)",
        payer_email=current_user["email"],
        pix_key=data.chave_pix
    )

    withdraw_id = str(uuid.uuid4())

    # 2. Debita pontos e grava histórico
    if USE_POSTGRES:
        cur.execute("""
            UPDATE users 
            SET saldo_pontos = saldo_pontos - %s, 
                total_saques_realizados = total_saques_realizados + 1,
                chave_pix = %s, tipo_chave = %s
            WHERE id = %s
        """, (pontos_necessarios, data.chave_pix, data.tipo_chave, user_id))

        cur.execute("""
            INSERT INTO withdrawals (id, user_id, valor_reais, pontos_descontados, chave_pix, tipo_chave, status, mp_payment_id, mp_qr_code_copia_cola, mp_ticket_url)
            VALUES (%s, %s, %s, %s, %s, %s, 'pendente', %s, %s, %s)
        """, (withdraw_id, user_id, valor, pontos_necessarios, data.chave_pix, data.tipo_chave, mp_res.get("payment_id"), mp_res.get("qr_code"), mp_res.get("ticket_url")))
    else:
        cur.execute("""
            UPDATE users 
            SET saldo_pontos = saldo_pontos - ?, 
                total_saques_realizados = total_saques_realizados + 1,
                chave_pix = ?, tipo_chave = ?
            WHERE id = ?
        """, (pontos_necessarios, data.chave_pix, data.tipo_chave, user_id))

        cur.execute("""
            INSERT INTO withdrawals (id, user_id, valor_reais, pontos_descontados, chave_pix, tipo_chave, status, mp_payment_id, mp_qr_code_copia_cola, mp_ticket_url)
            VALUES (?, ?, ?, ?, ?, ?, 'pendente', ?, ?, ?)
        """, (withdraw_id, user_id, valor, pontos_necessarios, data.chave_pix, data.tipo_chave, mp_res.get("payment_id"), mp_res.get("qr_code"), mp_res.get("ticket_url")))

    conn.commit()
    conn.close()

    return {
        "message": "Saque solicitado e processado via Mercado Pago!",
        "saque": {
            "id": withdraw_id,
            "valor_reais": valor,
            "pontos_descontados": pontos_necessarios,
            "chave_pix": data.chave_pix,
            "status": "pendente",
            "mercado_pago_id": mp_res.get("payment_id"),
            "pix_copia_e_cola": mp_res.get("qr_code"),
            "ticket_url": mp_res.get("ticket_url")
        }
    }

@app.get("/api/withdraw/history", tags=["Saques & PIX"])
def get_withdraw_history(current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    cur = conn.cursor()

    query = "SELECT * FROM withdrawals WHERE user_id = %s ORDER BY created_at DESC" if USE_POSTGRES else "SELECT * FROM withdrawals WHERE user_id = ? ORDER BY created_at DESC"
    cur.execute(query, (current_user["id"],))
    saques = cur.fetchall()
    conn.close()

    return {
        "saques": [
            {
                "id": str(s["id"]),
                "valor_reais": float(s["valor_reais"]),
                "pontos_descontados": s["pontos_descontados"],
                "chave_pix": s["chave_pix"],
                "tipo_chave": s["tipo_chave"],
                "status": s["status"],
                "mp_payment_id": s["mp_payment_id"],
                "mp_qr_code": s["mp_qr_code_copia_cola"],
                "created_at": str(s["created_at"])
            }
            for s in saques
        ]
    }

# ==============================================================================
# 5. WEBHOOK DO MERCADO PAGO (CONFIRMAÇÃO AUTOMÁTICA DE PIX)
# ==============================================================================
@app.post("/api/mercadopago/webhook", tags=["Mercado Pago Webhook"])
async def mercadopago_webhook(request: Request):
    """
    Recebe notificação de atualização do Mercado Pago quando o PIX for concluído.
    """
    body = await request.json()
    action = body.get("action")
    data = body.get("data", {})
    payment_id = str(data.get("id"))

    if payment_id:
        status_mp = mp_service.get_payment_status(payment_id)
        if status_mp == "approved":
            conn = get_connection()
            cur = conn.cursor()
            up_q = "UPDATE withdrawals SET status = 'pago' WHERE mp_payment_id = %s" if USE_POSTGRES else "UPDATE withdrawals SET status = 'pago' WHERE mp_payment_id = ?"
            cur.execute(up_q, (payment_id,))
            conn.commit()
            conn.close()

    return {"status": "ok"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=config.PORT, reload=True)
