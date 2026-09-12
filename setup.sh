#!/bin/bash
# setup.sh — установка тулчейна для Tang Mega 138K Pro (GW5AST-138)
# Запусти: bash ~/tang/setup.sh
set -e

OSSCAD_VERSION="2026-04-29"
OSSCAD_URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${OSSCAD_VERSION}/oss-cad-suite-linux-x64-$(echo $OSSCAD_VERSION | tr -d -).tgz"
OSSCAD_DIR="$HOME/oss-cad-suite"

echo "=== Tang Mega 138K Pro toolchain ==="
echo "Ubuntu $(lsb_release -rs 2>/dev/null || echo unknown)"

# 1. OSS CAD Suite — yosys + nextpnr-himbaechel + apycula + openFPGALoader
echo ""
echo "[1/3] OSS CAD Suite (~700 МБ архив, распаковка в ${OSSCAD_DIR})..."
if [ -d "$OSSCAD_DIR/bin" ] && [ -x "$OSSCAD_DIR/bin/nextpnr-himbaechel" ]; then
  echo "  уже установлен — пропускаю"
else
  cd "$HOME"
  if [ ! -f oss-cad-suite.tgz ]; then
    curl -fL --progress-bar -o oss-cad-suite.tgz "$OSSCAD_URL"
  fi
  rm -rf "$OSSCAD_DIR"
  tar xzf oss-cad-suite.tgz
  echo "  ✓ распаковано"
fi

# Проверить ключевые инструменты
echo ""
source "$OSSCAD_DIR/environment"
echo "  yosys:               $(yosys -V | head -1)"
echo "  nextpnr-himbaechel:  $(nextpnr-himbaechel --version 2>&1 | head -1)"
echo "  gowin_pack:          $(gowin_pack --help 2>&1 | head -1 || echo OK)"
echo "  openFPGALoader:      $(openFPGALoader --Version 2>&1 | head -1 || openFPGALoader --version 2>&1 | head -1)"

# 2. udev правила (доступ к FT2232H без root)
echo ""
echo "[2/3] udev правила для Tang Mega 138K Pro..."
if [ -f /etc/udev/rules.d/99-tang.rules ]; then
  echo "  уже есть"
else
  sudo tee /etc/udev/rules.d/99-tang.rules > /dev/null << 'UDEV'
# Tang Mega 138K Pro / Sipeed — FT2232H (JTAG channel A, UART channel B)
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6010", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6011", MODE="0666", GROUP="plugdev"
# WCH CH552 (для некоторых Tang Nano)
SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="55d4", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="1a86", ATTR{idProduct}=="55d3", MODE="0666", GROUP="plugdev"
UDEV
  sudo udevadm control --reload-rules 2>/dev/null || true
fi

# 3. Группы пользователя
echo ""
echo "[3/3] Группы пользователя..."
sudo usermod -aG plugdev,dialout $USER 2>/dev/null || true

# 4. Постоянная активация environment в .bashrc
echo ""
if ! grep -q "oss-cad-suite/environment" "$HOME/.bashrc" 2>/dev/null; then
  echo "  добавляю автозагрузку OSS CAD Suite в ~/.bashrc"
  echo "" >> "$HOME/.bashrc"
  echo "# OSS CAD Suite (Tang Mega 138K Pro toolchain)" >> "$HOME/.bashrc"
  echo "[ -f \"\$HOME/oss-cad-suite/environment\" ] && source \"\$HOME/oss-cad-suite/environment\"" >> "$HOME/.bashrc"
fi

echo ""
echo "==================================================="
echo "✓ Тулчейн установлен!"
echo ""
echo "Активация в текущем шелле:"
echo "  source ~/oss-cad-suite/environment"
echo ""
echo "Сборка:"
echo "  cd ~/tang/tang-mega-138k-pro/blink"
echo "  make          — синтез + bitstream"
echo "  make flash    — прошить плату (SRAM)"
echo ""
echo "ВАЖНО для WSL2: USB в WSL2 требует usbipd-win."
echo "  Инструкция: ~/tang/WSL2-USB.md"
echo "==================================================="
