@echo off
chcp 65001 > nul
echo ========================================================
echo   Compilador do Aplicativo Mobile (Flutter APK)
echo ========================================================
echo.

where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERRO] O comando 'flutter' nao foi encontrado no sistema!
    echo.
    echo Para compilar localmente na sua maquina:
    echo 1. Baixe o Flutter SDK em: https://docs.flutter.dev/get-started/install/windows
    echo 2. Extraia (ex: C:\src\flutter) e adicione o caminho 'bin' nas Variaveis de Ambiente (PATH).
    echo 3. Instale o Android Studio com Android SDK e Command-Line Tools.
    echo.
    echo DICA: Voce tambem pode subir para o GitHub para compilar o APK gratuitamente
    echo na nuvem pelo GitHub Actions usando o arquivo configurado:
    echo .github/workflows/build-apk.yml
    echo ========================================================
    pause
    exit /b 1
)

echo [1/3] Obtendo dependencias do Flutter...
call flutter pub get
if %errorlevel% neq 0 (
    echo [ERRO] Falha ao executar 'flutter pub get'.
    pause
    exit /b 1
)

echo.
echo [2/3] Compilando APK em modo Release...
call flutter build apk --release
if %errorlevel% neq 0 (
    echo [ERRO] Falha na compilacao do APK.
    pause
    exit /b 1
)

echo.
echo ========================================================
echo [3/3] SUCESSO! APK gerado com sucesso em:
echo build\app\outputs\flutter-apk\app-release.apk
echo ========================================================
pause
