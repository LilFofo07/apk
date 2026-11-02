@echo off
title Rewards Pay-To-Watch API Backend
cd /d "%~dp0backend_python"
echo =========================================================
echo  Iniciando Rewards API (Supabase & Mercado Pago)
echo =========================================================
"C:\Users\Edswilson\AppData\Local\Programs\Python\Python310\python.exe" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
pause
