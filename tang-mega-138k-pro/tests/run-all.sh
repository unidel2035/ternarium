#!/bin/bash
# Verilog CI — прогон всех testbench в проекте tang
#
# Запуск: bash tang/tang-mega-138k-pro/tests/run-all.sh
# Exit code: 0 = all pass, 1 = failures

BASE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
SKIP=0
RESULTS=()

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║  Tang Verilog CI — testbench runner       ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

# Ищем все testbench файлы
for tb in $(find "$BASE" -name "*_tb.v" -o -name "*_test.v" 2>/dev/null | sort); do
  dir=$(dirname "$tb")
  name=$(basename "$tb" .v)
  module_dir=$(basename "$dir")

  # Находим исходники в той же директории
  srcs=$(ls "$dir"/*.v 2>/dev/null | grep -v "_tb\|_test" | tr '\n' ' ')

  if [ -z "$srcs" ]; then
    echo "  ⏭ $module_dir/$name — нет исходников"
    SKIP=$((SKIP + 1))
    continue
  fi

  # Компиляция
  mkdir -p "$dir/build"
  if iverilog -o "$dir/build/$name" "$tb" $srcs 2>/dev/null; then
    # Запуск (timeout 30 сек)
    output=$(timeout 30 vvp "$dir/build/$name" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
      # Проверяем есть ли FAIL в выводе
      if echo "$output" | grep -qi "FAIL"; then
        echo "  ❌ $module_dir/$name — FAIL в выводе"
        FAIL=$((FAIL + 1))
        RESULTS+=("FAIL:$module_dir/$name")
      else
        echo "  ✅ $module_dir/$name — PASS"
        PASS=$((PASS + 1))
        RESULTS+=("PASS:$module_dir/$name")
      fi
    elif [ $exit_code -eq 124 ]; then
      echo "  ⏱ $module_dir/$name — TIMEOUT (>30s)"
      FAIL=$((FAIL + 1))
      RESULTS+=("TIMEOUT:$module_dir/$name")
    else
      echo "  ❌ $module_dir/$name — runtime error ($exit_code)"
      FAIL=$((FAIL + 1))
      RESULTS+=("ERROR:$module_dir/$name")
    fi
  else
    echo "  ❌ $module_dir/$name — compilation error"
    FAIL=$((FAIL + 1))
    RESULTS+=("COMPILE_ERROR:$module_dir/$name")
  fi
done

echo ""
echo "═══════════════════════════════════════════"
echo "  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
echo "═══════════════════════════════════════════"

# Сохраняем результаты
RESULT_FILE="$BASE/tests/ci-results.txt"
printf "%s\n" "${RESULTS[@]}" > "$RESULT_FILE"
echo "  Results: $RESULT_FILE"
echo ""

if [ $FAIL -gt 0 ]; then
  echo "❌ CI FAILED"
  exit 1
else
  echo "✅ CI PASSED"
  exit 0
fi
