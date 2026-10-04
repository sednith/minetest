#!/usr/bin/env sh

# ============================================================================
# Скрипт рестарта Minecraft сервера
# Запускать ИЗ ПАПКИ СЕРВЕРА: cd /home/server/minetest && ./restart.sh
# ============================================================================

# === НАСТРОЙКИ ===
LOG_FILE="logs/latest.log"
FIFO="server_console"
TIMEOUT=120
CHECK_INTERVAL=2
STOP_TIMEOUT=30
RESTART_WAIT=7

# === ФУНКЦИИ ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Найти PID сервера по рабочей директории
find_server_pid() {
    local target_dir="$1"
    for pid in $(pgrep -f '\.jar.*--nogui'); do
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
        if [ "$cwd" = "$target_dir" ]; then
            echo "$pid"
            return 0
        fi
    done
    return 1
}

# === ОПРЕДЕЛЯЕМ ТЕКУЩУЮ ПАПКУ ===
SERVER_DIR=$(pwd)

log "========================================"
log "[INFO] Рестарт сервера"
log "[INFO] Папка: $SERVER_DIR"
log "========================================"

# === ШАГ 1: Найти процесс сервера ===
log "[INFO] Поиск запущенного процесса..."
SERVER_PID=$(find_server_pid "$SERVER_DIR")

if [ -z "$SERVER_PID" ]; then
    log "[ERROR] Сервер не запущен в этой папке"
    log "[ERROR] Проверьте, что сервер работает и запущен через startserver.sh"
    exit 1
fi

log "[OK] Найден процесс: PID $SERVER_PID"

# === ШАГ 2: Запомнить позицию в логе ===
log "[INFO] Фиксация текущей позиции в логе..."
if [ -f "$LOG_FILE" ]; then
    LOG_SIZE_BEFORE=$(wc -c < "$LOG_FILE")
else
    LOG_SIZE_BEFORE=0
fi
log "[OK] Текущий размер лога: $LOG_SIZE_BEFORE байт"

# === ШАГ 3: Проверить наличие FIFO ===
log "[INFO] Проверка канала управления (FIFO)..."
if [ ! -p "$FIFO" ]; then
    log "[ERROR] Named pipe '$FIFO' не найден!"
    log "[ERROR] Убедитесь, что сервер запущен через startserver.sh"
    exit 1
fi
log "[OK] Канал управления найден"

# === ШАГ 4: Отправить команду stop ===
log "[INFO] Отправка команды 'stop' в консоль сервера..."
echo "stop" > "$FIFO"

# === ШАГ 5: Ждать остановки процесса ===
log "[INFO] Ожидание остановки сервера (макс. ${STOP_TIMEOUT}с)..."
WAIT=0
while find_server_pid "$SERVER_DIR" > /dev/null; do
    sleep 1
    WAIT=$((WAIT + 1))
    if [ "$WAIT" -ge "$STOP_TIMEOUT" ]; then
        log "[ERROR] Сервер не остановился за $STOP_TIMEOUT секунд"
        exit 1
    fi
done
log "[OK] Сервер остановлен (за ${WAIT}с)"

# === ШАГ 6: Ждать перезапуска от основного скрипта ===
log "[INFO] Ожидание автоматического перезапуска (${RESTART_WAIT}с)..."
sleep "$RESTART_WAIT"

NEW_PID=$(find_server_pid "$SERVER_DIR")
if [ -z "$NEW_PID" ]; then
    log "[ERROR] Сервер не перезапустился"
    exit 1
fi

if [ "$NEW_PID" = "$SERVER_PID" ]; then
    log "[ERROR] PID не изменился, сервер не перезапустился"
    exit 1
fi

log "[OK] Новый процесс запущен: PID $NEW_PID (был: $SERVER_PID)"

# === ШАГ 7: Ждать полной загрузки через логи ===
log "[INFO] Ожидание полной загрузки (поиск 'Done' в логе)..."
log "[INFO] Таймаут: ${TIMEOUT}с, проверка каждые ${CHECK_INTERVAL}с"
echo ""

ELAPSED=0
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE_NOW=$(wc -c < "$LOG_FILE")

        # === ЗАЩИТА ОТ РОТАЦИИ ЛОГОВ ===
        if [ "$LOG_SIZE_NOW" -lt "$LOG_SIZE_BEFORE" ]; then
            log "[WARN] Обнаружена ротация лога. Сбрасываем точку отсчета."
            LOG_SIZE_BEFORE=0
        fi

        if tail -c +"$LOG_SIZE_BEFORE" "$LOG_FILE" 2>/dev/null | grep -q "Done.*For help"; then
            echo ""
            log "========================================"
            log "[OK] СЕРВЕР УСПЕШНО ЗАГРУЖЕН И ГОТОВ К РАБОТЕ!"
            log "========================================"
            log "[INFO] Время загрузки: ${ELAPSED}с"
            log "[INFO] Новый PID: $NEW_PID"
            exit 0
        fi
    fi

    sleep "$CHECK_INTERVAL"
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))

    if [ $((ELAPSED % 10)) -eq 0 ]; then
        log "[INFO]   ...прошло ${ELAPSED}/${TIMEOUT} сек"
    fi
done

log "[ERROR] Сервер не загрузился за $TIMEOUT секунд"
log "[INFO] Последние 20 строк лога:"
tail -n 20 "$LOG_FILE" 2>/dev/null
exit 1