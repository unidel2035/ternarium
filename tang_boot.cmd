@echo off
rem tang_boot.cmd — поднять интерфейс Tang Mega после включения платы.
rem Флеш платы < 34 МБ, а битстримы open-тулчейна несжимаемы, поэтому после
rem перезагрузки плата грузит заводские полосы. Этот скрипт за 30 секунд
rem возвращает рабочий экран. Запуск: двойной клик после включения платы.
rem (или ярлык в автозагрузку — сработает при старте Windows)

usbipd detach --busid 1-6 2>nul
usbipd attach --wsl --busid 1-6
timeout /t 3 /nobreak >nul
wsl.exe -d Ubuntu bash -c "echo Denver2035 | sudo -S openFPGALoader --board tangmega138k ~/fly-build/tang-mega-138k-pro/fly_brain_lcd/build/fly_brain_lcd.fs 2>&1 | tail -1"
echo Готово: экран Tang загружен.
pause
