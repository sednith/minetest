#!/usr/bin/env bash
set -euo pipefail

OVERRIDES_DIR="overrides"

echo "========================================="
echo "  Применение overrides"
echo "========================================="

# Проверяем наличие yq
if ! command -v yq &> /dev/null; then
    echo "[ERROR] Утилита yq не найдена. Установите: https://github.com/mikefarah/yq"
    exit 1
fi

# Проверяем наличие папки overrides
if [ ! -d "$OVERRIDES_DIR" ]; then
    echo "[WARN] Папка $OVERRIDES_DIR не найдена. Нечего применять."
    exit 0
fi

# Счетчики
applied=0
skipped=0
errors=0

# Находим все файлы в overrides/ рекурсивно
while IFS= read -r override_file; do
    # Убираем префикс "overrides/" чтобы получить путь к базовому файлу
    base_file="${override_file#"$OVERRIDES_DIR"/}"

    echo ""
    echo "[INFO] Обработка: $override_file -> $base_file"

    # Проверяем, существует ли базовый файл
    if [ ! -f "$base_file" ]; then
        echo "       [WARN] Базовый файл не найден, пропуск"
        ((++skipped))
        continue
    fi

    # Определяем тип файла по расширению
    if [[ "$base_file" == *.yml ]] || [[ "$base_file" == *.yaml ]] || [[ "$base_file" == *.json ]]; then
        echo "       [INFO] Тип: YAML/JSON merge"
        if yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$base_file" "$override_file" > "${base_file}.tmp" 2>/dev/null; then
            mv "${base_file}.tmp" "$base_file"
            echo "       [INFO] Успешно применено"
            ((++applied))
        else
            rm -f "${base_file}.tmp"
            echo "       [ERROR] Ошибка применения YAML/JSON"
            ((++errors))
        fi

    elif [[ "$base_file" == *.properties ]]; then
        echo "       [INFO] Тип: Properties merge"
        prop_ok=true
        for key in $(yq e 'keys | .[]' "$override_file" 2>/dev/null); do
            value=$(yq e ".\"$key\"" "$override_file" 2>/dev/null)
            if ! yq -i ".\"$key\" = \"$value\"" "$base_file" 2>/dev/null; then
                echo "       [ERROR] Ошибка применения ключа: $key"
                prop_ok=false
            fi
        done
        if $prop_ok; then
            echo "       [INFO] Успешно применено"
            ((++applied))
        else
            ((++errors))
        fi

    else
        echo "       [WARN] Неизвестный формат файла, пропуск"
        ((++skipped))
    fi

done < <(find "$OVERRIDES_DIR" -type f | sort)

echo ""
echo "========================================="
echo "  Итого: применено=$applied, пропущено=$skipped, ошибок=$errors"
echo "========================================="

if [ "$errors" -gt 0 ]; then
    echo "[ERROR] Завершение с ошибками при применении overrides!"
    exit 1
fi

echo "[INFO] Все overrides успешно применены"
exit 0