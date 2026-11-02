# 🚀 Plataforma de Recompensas Pay-To-Watch (Supabase + Mercado Pago PIX)

Plataforma 100% funcional e real onde usuários assistem a anúncios premiados (Rewarded Video Ads) e realizam saques instantâneos via PIX integrados com o **Mercado Pago** e banco de dados na nuvem via **Supabase**.

---

## ⚡ Como Rodar o Backend em 1 Clique (Pronto para Uso)

Basta dar dois cliques no arquivo:
```
c:\Users\Edswilson\Documents\ads\start_backend.bat
```
Ou executar no terminal:
```bash
cd backend_python
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

A documentação interativa e painel de testes (Swagger UI) abrirá em:
👉 **http://localhost:8000/docs**

---

## ☁️ 1. Como Conectar ao Supabase (PostgreSQL Grátis na Nuvem)

1. Crie uma conta gratuita em [supabase.com](https://supabase.com).
2. Crie um novo projeto (ex: `rewards-app`).
3. Vá em **SQL Editor** no menu lateral esquerdo, clique em **New Query**, cole o conteúdo do arquivo:
   [`supabase/setup_supabase.sql`](file:///c:/Users/Edswilson/Documents/ads/supabase/setup_supabase.sql) e clique em **RUN**.
4. Vá em **Project Settings** -> **Database** -> **Connection string** (selecione a aba **URI**).
5. Copie a URI e cole no arquivo [`backend_python/.env`](file:///c:/Users/Edswilson/Documents/ads/backend_python/.env):
   ```env
   DATABASE_URL=postgres://postgres.[SEU_PROJETO]:[SUA_SENHA]@aws-0-sa-east-1.pooler.supabase.com:6543/postgres?sslmode=require
   ```
*(Nota: Se deixar em branco, o backend utiliza automaticamente o banco local SQLite para você testar imediatamente offline sem nenhuma dependência!)*

---

## 💳 2. Como Obter a Chave Gratuita do Mercado Pago (PIX Real)

1. Acesse o portal de desenvolvedores do Mercado Pago: [mercadopago.com.br/developers](https://www.mercadopago.com.br/developers/panel).
2. Faça login com sua conta do Mercado Livre / Mercado Pago.
3. Clique em **Suas integrações** -> **Criar aplicação** (Nome: `Rewards App`).
4. No menu lateral da sua aplicação, clique em **Credenciais de teste** (Ambiente Sandbox Gratuito).
5. Copie o **Access Token de Teste** (começa com `TEST-...`).
6. Cole no arquivo [`backend_python/.env`](file:///c:/Users/Edswilson/Documents/ads/backend_python/.env):
   ```env
   MP_ACCESS_TOKEN=TEST-xxxxxxxx-xxxxxx-xxxxxxxxxxxxxxxxxxxxxxxx-xxxxxxxxx
   ```
*(Nota: Enquanto você não colocar o token, o sistema opera no modo simulador realista de PIX, gerando IDs e códigos Copia e Cola compatíveis).*

---

## 📱 3. Como Rodar o Aplicativo Mobile (Flutter)

O app já está configurado para comunicar com o backend e exibir o saldo, botões de anúncios e saques PIX.

```bash
cd mobile
flutter pub get
flutter run
```

---

## 🧪 Resumo do Teste de Validação Ponta a Ponta Realizado

Executamos o teste automatizado no próprio ambiente com o seguinte fluxo:
1. **Cadastro do Usuário:** Conta criada com proteção de 1 conta por Hardware ID (`device_id`).
2. **Saldo Inicial:** R$ 0,00 (0 pontos).
3. **50 Vídeos Assistidos (SSV):** +5.000 pontos validados pelo Webhook de Ad Network.
4. **Saldo Atualizado:** R$ 0,50 (5.000 pontos).
5. **Saque de Boas-Vindas:** R$ 0,50 processado via Mercado Pago PIX, gerando ID de transação e código PIX Copia e Cola.
6. **Bloqueio de Regra de Negócio:** Próximo saque condicionado à meta regular de R$ 2,00 (20.000 pontos).
