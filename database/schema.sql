-- ==============================================================================
-- PLATAFORMA REWARDS PAY-TO-WATCH (PIX) - ESQUEMA DDL (POSTGRESQL)
-- ==============================================================================

-- Habilita extensão para UUID se necessário
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. TABELA DE USUÁRIOS
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    senha_hash VARCHAR(255) NOT NULL,
    device_id VARCHAR(100) NOT NULL, -- Identificador único do aparelho (anti-fraude)
    last_ip VARCHAR(45),             -- IPv4 ou IPv6 do último acesso
    chave_pix VARCHAR(100),
    tipo_chave VARCHAR(20) CHECK (tipo_chave IN ('CPF', 'EMAIL', 'TELEFONE', 'ALEATORIA')),
    saldo_pontos BIGINT NOT NULL DEFAULT 0 CHECK (saldo_pontos >= 0), -- Constraint estrita: saldo nunca negativo
    total_saques_realizados INT NOT NULL DEFAULT 0,                   -- Controle de regra do 1º saque
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Índice para busca rápida de e-mail e device_id
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_device_id ON users(device_id);

-- 2. TABELA DE LOGS DE RECOMPENSAS (REWARDED ADS SSV)
-- Salva cada evento de anúncio com idempotência garantida pela Ad Network
CREATE TABLE IF NOT EXISTS reward_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    network VARCHAR(50) NOT NULL DEFAULT 'applovin', -- applovin, admob, unity
    transaction_id_adnet VARCHAR(150) UNIQUE NOT NULL, -- Chave de idempotência da rede de anúncios
    pontos_ganhos INT NOT NULL DEFAULT 100,
    status VARCHAR(30) NOT NULL DEFAULT 'VALIDATED',   -- VALIDATED, REJECTED, DUPLICATE
    ip_address VARCHAR(45),
    raw_payload JSONB,                                 -- Auditoria dos parâmetros enviados pela ad network
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_reward_logs_user_id ON reward_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_reward_logs_trans_id ON reward_logs(transaction_id_adnet);

-- 3. TABELA DE SOLICITAÇÕES DE SAQUE (WITHDRAWALS)
CREATE TABLE IF NOT EXISTS withdrawals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    valor_reais NUMERIC(10, 2) NOT NULL,
    pontos_descontados BIGINT NOT NULL,
    chave_pix VARCHAR(100) NOT NULL,
    tipo_chave VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'processando', 'pago', 'rejeitado')),
    gateway_reference VARCHAR(150),                    -- ID do pagamento no Mercado Pago / Asaas
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_withdrawals_user_id ON withdrawals(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON withdrawals(status);

-- 4. TABELA DE AUDITORIA DE SEGURANÇA E RATE LIMIT
CREATE TABLE IF NOT EXISTS security_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    device_id VARCHAR(100),
    event_type VARCHAR(50) NOT NULL, -- MULTIPLE_ACCOUNTS_ATTEMPT, FAST_WATCH_SUSPICION, INVALID_SIGNATURE
    details TEXT,
    ip_address VARCHAR(45),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
