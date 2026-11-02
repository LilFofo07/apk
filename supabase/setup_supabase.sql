-- ==============================================================================
-- SETUP SUPABASE (POSTGRESQL NA NUVEM) - EXECUTE NO "SQL EDITOR" DO SUPABASE
-- ==============================================================================

-- 1. Habilita a extensão UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. TABELA DE USUÁRIOS
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    senha_hash VARCHAR(255) NOT NULL,
    device_id VARCHAR(100) NOT NULL,
    last_ip VARCHAR(45),
    chave_pix VARCHAR(100),
    tipo_chave VARCHAR(20) DEFAULT 'CPF',
    saldo_pontos BIGINT NOT NULL DEFAULT 0 CHECK (saldo_pontos >= 0),
    total_saques_realizados INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_device_id ON public.users(device_id);

-- 3. TABELA DE LOGS DE RECOMPENSAS (REWARDED ADS SSV)
CREATE TABLE IF NOT EXISTS public.reward_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    network VARCHAR(50) NOT NULL DEFAULT 'applovin',
    transaction_id_adnet VARCHAR(150) UNIQUE NOT NULL, -- Garante Idempotência
    pontos_ganhos INT NOT NULL DEFAULT 100,
    status VARCHAR(30) NOT NULL DEFAULT 'VALIDATED',
    ip_address VARCHAR(45),
    raw_payload JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_reward_logs_user_id ON public.reward_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_reward_logs_tx ON public.reward_logs(transaction_id_adnet);

-- 4. TABELA DE SAQUES (INTEGRAÇÃO MERCADO PAGO PIX)
CREATE TABLE IF NOT EXISTS public.withdrawals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    valor_reais NUMERIC(10, 2) NOT NULL,
    pontos_descontados BIGINT NOT NULL,
    chave_pix VARCHAR(100) NOT NULL,
    tipo_chave VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'processando', 'pago', 'rejeitado')),
    mp_payment_id VARCHAR(100),             -- ID do Pagamento no Mercado Pago
    mp_qr_code_copia_cola TEXT,             -- Código PIX Copia e Cola
    mp_ticket_url TEXT,                     -- URL do comprovante no Mercado Pago
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_withdrawals_user_id ON public.withdrawals(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_mp_id ON public.withdrawals(mp_payment_id);

-- 5. TABELA DE EVENTOS DE SEGURANÇA E ANTI-FRAUDE
CREATE TABLE IF NOT EXISTS public.security_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.users(id),
    device_id VARCHAR(100),
    event_type VARCHAR(50) NOT NULL,
    details TEXT,
    ip_address VARCHAR(45),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);
