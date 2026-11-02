import os
import sqlite3
import psycopg2
from psycopg2.extras import RealDictCursor
import config

USE_POSTGRES = bool(config.DATABASE_URL)

def get_connection():
    if USE_POSTGRES:
        # Conexão direta com Supabase (Pooler ou Direct) com SSL
        conn = psycopg2.connect(
            config.DATABASE_URL,
            cursor_factory=RealDictCursor,
            sslmode="require" if "supabase" in config.DATABASE_URL or "sslmode=require" in config.DATABASE_URL else "prefer"
        )
        return conn
    else:
        # SQLite local para desenvolvimento instantâneo offline/local
        db_path = os.path.join(os.path.dirname(__file__), "local_rewards.db")
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        return conn

def init_db():
    conn = get_connection()
    cur = conn.cursor()

    if USE_POSTGRES:
        # PostgreSQL / Supabase
        cur.execute("""
            CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
            CREATE TABLE IF NOT EXISTS users (
                id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                nome VARCHAR(100) NOT NULL,
                email VARCHAR(150) UNIQUE NOT NULL,
                senha_hash VARCHAR(255) NOT NULL,
                device_id VARCHAR(100) NOT NULL,
                last_ip VARCHAR(45),
                chave_pix VARCHAR(100),
                tipo_chave VARCHAR(20) DEFAULT 'CPF',
                saldo_pontos BIGINT NOT NULL DEFAULT 0,
                total_saques_realizados INT NOT NULL DEFAULT 0,
                is_active BOOLEAN NOT NULL DEFAULT TRUE,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS reward_logs (
                id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                network VARCHAR(50) NOT NULL DEFAULT 'applovin',
                transaction_id_adnet VARCHAR(150) UNIQUE NOT NULL,
                pontos_ganhos INT NOT NULL DEFAULT 100,
                status VARCHAR(30) NOT NULL DEFAULT 'VALIDATED',
                ip_address VARCHAR(45),
                raw_payload TEXT,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS withdrawals (
                id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                user_id UUID NOT NULL REFERENCES users(id),
                valor_reais NUMERIC(10, 2) NOT NULL,
                pontos_descontados BIGINT NOT NULL,
                chave_pix VARCHAR(100) NOT NULL,
                tipo_chave VARCHAR(20) NOT NULL,
                status VARCHAR(20) NOT NULL DEFAULT 'pendente',
                mp_payment_id VARCHAR(100),
                mp_qr_code_copia_cola TEXT,
                mp_ticket_url TEXT,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            );
        """)
        conn.commit()
    else:
        # SQLite
        cur.executescript("""
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                nome TEXT NOT NULL,
                email TEXT UNIQUE NOT NULL,
                senha_hash TEXT NOT NULL,
                device_id TEXT NOT NULL,
                last_ip TEXT,
                chave_pix TEXT,
                tipo_chave TEXT DEFAULT 'CPF',
                saldo_pontos INTEGER NOT NULL DEFAULT 0,
                total_saques_realizados INTEGER NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS reward_logs (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                network TEXT NOT NULL DEFAULT 'applovin',
                transaction_id_adnet TEXT UNIQUE NOT NULL,
                pontos_ganhos INTEGER NOT NULL DEFAULT 100,
                status TEXT NOT NULL DEFAULT 'VALIDATED',
                ip_address TEXT,
                raw_payload TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id)
            );

            CREATE TABLE IF NOT EXISTS withdrawals (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                valor_reais REAL NOT NULL,
                pontos_descontados INTEGER NOT NULL,
                chave_pix TEXT NOT NULL,
                tipo_chave TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pendente',
                mp_payment_id TEXT,
                mp_qr_code_copia_cola TEXT,
                mp_ticket_url TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id)
            );
        """)
        conn.commit()

    cur.close()
    conn.close()
    print(f"[Database] Inicializado com sucesso usando: {'Supabase (PostgreSQL)' if USE_POSTGRES else 'SQLite Local'}")
