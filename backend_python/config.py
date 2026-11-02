import os
from dotenv import load_dotenv

load_dotenv()

PORT = int(os.getenv("PORT", "8000"))
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")

# Supabase / PostgreSQL
DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
SUPABASE_URL = os.getenv("SUPABASE_URL", "").strip()
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "").strip()

# Mercado Pago
MP_ACCESS_TOKEN = os.getenv("MP_ACCESS_TOKEN", "").strip()

# JWT e Segurança
JWT_SECRET = os.getenv("JWT_SECRET", "super_secret_jwt_rewards_key_2026_xyz")
JWT_ALGORITHM = "HS256"
JWT_EXPIRATION_DAYS = 30

# SSV e Economia
AD_NETWORK_SSV_SECRET = os.getenv("AD_NETWORK_SSV_SECRET", "")
POINTS_PER_VIDEO = int(os.getenv("POINTS_PER_VIDEO", "100"))
COOLDOWN_SECONDS_BETWEEN_ADS = int(os.getenv("COOLDOWN_SECONDS_BETWEEN_ADS", "20"))
