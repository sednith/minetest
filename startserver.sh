#!/usr/bin/env sh

# ============================================================================
# Скрипт запуска Minecraft сервера с поддержкой консоли через FIFO
# Запускать ИЗ ПАПКИ СЕРВЕРА: cd /home/server/minetest && ./startserver.sh
# ============================================================================

# === НАСТРОЙКИ ===
FIFO="server_console"

# === ФУНКЦИИ ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

cleanup() {
    echo ""
    log "========================================"
    log "[INFO] Получен сигнал остановки"
    log "[INFO] Очистка ресурсов..."
    log "========================================"

    # Пытаемся мягко остановить сервер через FIFO
    if pgrep -f '\.jar.*--nogui' > /dev/null; then
        log "[INFO] Отправка команды 'stop' в сервер..."
        if [ -p "$FIFO" ]; then
            echo "stop" > "$FIFO" 2>/dev/null
        fi

        WAIT=0
        while pgrep -f '\.jar.*--nogui' > /dev/null; do
            sleep 1
            WAIT=$((WAIT + 1))
            if [ "$WAIT" -ge 10 ]; then
                log "[WARN] Мягкая остановка не удалась. Принудительное завершение..."
                pkill -f '\.jar.*--nogui' 2>/dev/null
                break
            fi
        done
    fi

    # Закрываем дескриптор и удаляем FIFO
    exec 3>&- 2>/dev/null
    rm -f "$FIFO"
    log "[OK] Ресурсы очищены. FIFO удалён."
    exit 0
}

# === ОБРАБОТКА СИГНАЛОВ ===
trap cleanup INT TERM

# === ПРОВЕРКА ЯДРА ===
log "========================================"
log "[INFO] ПРОВЕРКА ОКРУЖЕНИЯ"
log "========================================"

SERVER_JARS=$(find . -maxdepth 1 -type f -name 'paper-*.jar' -o -name 'purpur-*.jar' -o -name 'folia-*.jar' -print)
SERVER_COUNT=$(printf '%s\n' "$SERVER_JARS" | grep -c '.')

if [ "$SERVER_COUNT" -eq 0 ]; then
    log "========================================"
    log "[ERROR] Ядро сервера (paper-*.jar и аналоги) не найдено!"
    log "========================================"
    exit 1
fi

if [ "$SERVER_COUNT" -gt 1 ]; then
    log "========================================"
    log "[ERROR] Найдено несколько ядер сервера!"
    log "[ERROR] Количество: $SERVER_COUNT"
    log ""
    log "[ERROR] Найденные файлы:"
    printf '%s\n' "$SERVER_JARS"
    log ""
    log "[ERROR] Оставьте только один файл .jar и запустите скрипт снова."
    log "========================================"
    exit 1
fi

SERVER_JAR="$SERVER_JARS"
log "[OK] Найдено ядро: $SERVER_JAR"

# === СОЗДАНИЕ FIFO ===
log "[INFO] Подготовка канала управления..."
if [ -e "$FIFO" ]; then
    rm -f "$FIFO"
fi

mkfifo "$FIFO"
exec 3<> "$FIFO"
log "[OK] Канал управления '$FIFO' создан и открыт (fd 3)"

# === ОСНОВНОЙ ЦИКЛ ===
while true; do
    log "========================================"
    log "[INFO] ЗАПУСК СЕРВЕРА"
    log "[INFO] Папка: $(pwd)"
    log "========================================"

    java @java-args -jar "$SERVER_JAR" --nogui < "$FIFO" &
    SERVER_PID=$!

    log "[OK] Процесс Java запущен: PID $SERVER_PID"

    wait $SERVER_PID
    EXIT_CODE=$?

    log "========================================"
    log "[INFO] СЕРВЕР ОСТАНОВЛЕН"
    log "[INFO] Код завершения: $EXIT_CODE"
    log "========================================"

    log "[INFO] Перезапуск через 5 секунд..."
    log "[INFO] Нажмите Ctrl+C для полной остановки."
    echo ""

    sleep 5
done