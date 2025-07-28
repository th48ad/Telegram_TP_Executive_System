@echo off
title Signal System Auto-Restart
echo ===============================================
echo    SIGNAL SYSTEM AUTO-RESTART MONITOR
echo ===============================================
echo Starting monitoring loop...
echo Press Ctrl+C to stop monitoring
echo ===============================================

:RESTART_LOOP
echo.
echo [%date% %time%] Starting Signal System...
cd /d "C:\Users\Administrator\OneDrive\Desktop\MT4_Telegram_Signal"
call venv\Scripts\activate.bat
python main.py

echo.
echo [%date% %time%] Signal System stopped (Exit Code: %ERRORLEVEL%)

if %ERRORLEVEL% EQU 0 (
    echo Normal shutdown detected - exiting monitor
    goto END
)

echo [%date% %time%] Unexpected shutdown - restarting in 30 seconds...
echo ===============================================
timeout /t 30 /nobreak

goto RESTART_LOOP

:END
echo.
echo [%date% %time%] Auto-restart monitor stopped
pause 