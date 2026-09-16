@echo off
rem load_brain.cmd — загрузить мозг+LCD в SRAM Tang Mega 138K Pro (до перетыкания питания)
rem Во flash живёт заводской 800_480_screen (34MB битстрим apycula во flash не влезает -
rem GW5AST не поддерживает компрессию, запись с заворотом затирает начало флеша).
usbipd detach --busid 1-1 2>nul
usbipd attach --wsl --busid 1-1
timeout /t 3 /nobreak >nul
wsl.exe -d Ubuntu bash -c "echo Denver2035 | sudo -S openFPGALoader --board tangmega138k ~/fly-build/tang-mega-138k-pro/fly_brain_lcd/build/fly_brain_lcd.fs 2>&1 | tail -1"
pause
