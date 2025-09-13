#!/bin/bash

run_backup_logic() {
    local backup_type="$1"
    local TELEGRAM_TOKEN=""
    local CHAT_ID=""
    local setup_cron="false"

    local SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    local TELEGRAM_ENV_FILE="$SCRIPT_DIR/.env"
    local DB_ENV_FILE="/opt/remnawave/.env"

    if [ -f "$TELEGRAM_ENV_FILE" ]; then
        TELEGRAM_TOKEN=$(grep -E '^TELEGRAM_TOKEN=' "$TELEGRAM_ENV_FILE" | cut -d'=' -f2-)
        CHAT_ID=$(grep -E '^CHAT_ID=' "$TELEGRAM_ENV_FILE" | cut -d'=' -f2-)
    fi

    if yn_prompt "$(get_text "PROMPT_SCHEDULE_BACKUP")"; then
        setup_cron="true"
        echo ""

        if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$CHAT_ID" ]; then
            if yn_prompt "$(get_text "PROMPT_FOUND_CONFIG")"; then
                echo "$(get_text "PROMPT_USING_SAVED_CONFIG")"
            else
                TELEGRAM_TOKEN=""
                CHAT_ID=""
            fi
        fi

        if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$CHAT_ID" ]; then
            if yn_prompt "$(get_text "PROMPT_SETUP_TELEGRAM")"; then
                echo "$(get_text "TELEGRAM_INFO_1")"
                echo "$(get_text "TELEGRAM_INFO_2")"
                echo "$(get_text "TELEGRAM_INFO_3")"
                echo ""
                read -p "$(get_text "PROMPT_TELEGRAM_TOKEN")" TELEGRAM_TOKEN
                read -p "$(get_text "PROMPT_CHAT_ID")" CHAT_ID

                if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$CHAT_ID" ]; then
                    echo "$(get_text "SAVING_NEW_SETTINGS")"
                    sudo tee -a "$TELEGRAM_ENV_FILE" > /dev/null <<< "TELEGRAM_TOKEN=\"$TELEGRAM_TOKEN\"
CHAT_ID=\"$CHAT_ID\""
                    echo "$(get_text "CONFIG_SAVED_SUCCESS")$TELEGRAM_ENV_FILE."
                fi
            fi
        fi
    fi

    echo "$(get_text "SEARCHING_DB_CONFIG")"
    local DB_USER="remnawave"
    local DB_PASS=""
    local DB_HOST="remnawave-db"
    local DB_NAME="remnawave"

    if [ -f "$DB_ENV_FILE" ]; then
        echo "$(get_text "DB_CONFIG_FOUND")"
        local DB_URL=$(grep 'DATABASE_URL' "$DB_ENV_FILE" | cut -d'=' -f2- | sed 's/"//g')
        if [[ -n "$DB_URL" ]]; then
            DB_USER=$(echo "$DB_URL" | sed -E 's/postgresql:\/\/([^:]+):.*@.*/\1/')
            DB_PASS=$(echo "$DB_URL" | sed -E 's/postgresql:\/\/[^:]+:([^@]+)@.*/\1/')
            DB_HOST=$(echo "$DB_URL" | sed -E 's/postgresql:\/\/[^@]+@([^:]+):.*/\1/')
            DB_NAME=$(echo "$DB_URL" | sed -E 's/.*\/([^?]+).*/\1/')
            echo "$(get_text "DB_INFO_EXTRACTED")"
            sleep 2
        else
            echo "$(get_text "DB_URL_NOT_FOUND")"
        fi
    else
        echo "$(get_text "DB_ENV_NOT_FOUND")"
    fi

    if ! command -v docker &> /dev/null; then
        echo "$(get_text "DOCKER_NOT_RUNNING")"
        echo "$(get_text "DOCKER_INSTALL_PROMPT")"
        exit 1
    fi

    local BACKUP_SCRIPT_PATH="/usr/local/bin/remnawave_backup.sh"

    # Предварительно получаем все строки из словаря, включая эмодзи
    local text_backup_files_note="$(get_text "BACKUP_FILES_NOTE")"
    local text_telegram_caption="$(get_text "TELEGRAM_CAPTION")"
    local text_cleaning_progress="$(get_text "CLEANING_PROGRESS")"
    local text_backups_over_limit="$(get_text "BACKUPS_OVER_LIMIT")"
    local text_no_cleanup_needed="$(get_text "NO_CLEANUP_NEEDED")"
    local text_backup_start="$(get_text "BACKUP_START")"
    local text_creating_temp_dir="$(get_text "CREATING_TEMP_DIR")"
    local text_creating_db_dump="$(get_text "CREATING_DB_DUMP")"
    local text_db_dump_error="$(get_text "DB_DUMP_ERROR")"
    local text_db_dump_success="$(get_text "DB_DUMP_SUCCESS")"
    local text_copying_remnawave_dir="$(get_text "COPYING_REMAWAVE_DIR")"
    local text_copying_all_opt="$(get_text "COPYING_ALL_OPT")"
    local text_db_only_backup_selected="$(get_text "DB_ONLY_BACKUP_SELECTED")"
    local text_creating_single_archive="$(get_text "CREATING_SINGLE_ARCHIVE")"
    local text_archive_error="$(get_text "ARCHIVE_ERROR")"
    local text_archive_success="$(get_text "ARCHIVE_SUCCESS")"
    local text_deleting_temp_dir="$(get_text "DELETING_TEMP_DIR")"

    sudo rm -f "$BACKUP_SCRIPT_PATH"
    sudo touch "$BACKUP_SCRIPT_PATH"

    sudo bash -c "
        printf '#!/bin/bash\n' >> '$BACKUP_SCRIPT_PATH'
        printf '# %s\n' \"$text_backup_files_note\" >> '$BACKUP_SCRIPT_PATH'
        printf 'BACKUP_DIR=\"/opt/backups\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'MAX_BACKUPS=50\n\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'TELEGRAM_TOKEN=\"%s\"\n' \"$TELEGRAM_TOKEN\" >> '$BACKUP_SCRIPT_PATH'
        printf 'CHAT_ID=\"%s\"\n' \"$CHAT_ID\" >> '$BACKUP_SCRIPT_PATH'
        printf 'DB_USER=\"%s\"\n' \"$DB_USER\" >> '$BACKUP_SCRIPT_PATH'
        printf 'DB_PASS=\"%s\"\n' \"$DB_PASS\" >> '$BACKUP_SCRIPT_PATH'
        printf 'DB_HOST=\"%s\"\n' \"$DB_HOST\" >> '$BACKUP_SCRIPT_PATH'
        printf 'DB_NAME=\"%s\"\n' \"$DB_NAME\" >> '$BACKUP_SCRIPT_PATH'
        printf 'BACKUP_TYPE=\"%s\"\n\n' \"$backup_type\" >> '$BACKUP_SCRIPT_PATH'
        printf 'send_telegram_file() {\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    local file_path=\"\$1\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    local caption=\"%s\$(basename \"\$file_path\")\"\n' \"$text_telegram_caption\" >> '$BACKUP_SCRIPT_PATH'
        printf '    if [ -n \"\$TELEGRAM_TOKEN\" ] && [ -n \"\$CHAT_ID\" ]; then\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        echo \"Отправка файла в Telegram...\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        curl -s -X POST \"https://api.telegram.org/bot\$TELEGRAM_TOKEN/sendDocument\" \\\n' >> '$BACKUP_SCRIPT_PATH'
        printf '            -F document=@\"\$file_path\" \\\n' >> '$BACKUP_SCRIPT_PATH'
        printf '            -F chat_id=\"\$CHAT_ID\" \\\n' >> '$BACKUP_SCRIPT_PATH'
        printf '            -F caption=\"\$caption\" > /dev/null\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    fi\n' >> '$BACKUP_SCRIPT_PATH'
        printf '}\n\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'send_telegram_message() {\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    local message=\"\$1\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    if [ -n \"\$TELEGRAM_TOKEN\" ] && [ -n \"\$CHAT_ID\" ]; then\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        curl -s -X POST \"https://api.telegram.org/bot\$TELEGRAM_TOKEN/sendMessage\" \\\n' >> '$BACKUP_SCRIPT_PATH'
        printf '            -d chat_id=\"\$CHAT_ID\" \\\n' >> '$BACKUP_SCRIPT_PATH'
        printf '            --data-urlencode \"text=\$message\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    fi\n' >> '$BACKUP_SCRIPT_PATH'
        printf '}\n\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'clean_old_backups() {\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    echo \"%s\"\n' \"$text_cleaning_progress\" >> '$BACKUP_SCRIPT_PATH'
        printf '    mkdir -p \"\$BACKUP_DIR\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    local backup_count=\$(ls -1 \"\$BACKUP_DIR\" 2>/dev/null | wc -l)\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    if (( backup_count > MAX_BACKUPS )); then\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        local backups_to_remove=\$(( backup_count - MAX_BACKUPS ))\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        printf \"%s\" \"$text_backups_over_limit\" \"\$MAX_BACKUPS\" \"\$backups_to_remove\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        ls -1t \"\$BACKUP_DIR\" | tail -n \"\$backups_to_remove\" | xargs -I {} rm -- \"\$BACKUP_DIR/{}\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    else\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        echo \"%s\"\n' \"$text_no_cleanup_needed\" >> '$BACKUP_SCRIPT_PATH'
        printf '    fi\n' >> '$BACKUP_SCRIPT_PATH'
        printf '}\n\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'echo \"%s\"\n' \"$text_backup_start\" >> '$BACKUP_SCRIPT_PATH'
        printf 'mkdir -p \"\$BACKUP_DIR\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'TIMESTAMP=\$(date +\"%%Y-%%m-%%d_%%H-%%M-%%S\")\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'FINAL_ARCHIVE_FILE=\"\$BACKUP_DIR/remnawave_backup_\$TIMESTAMP.tar.gz\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'TEMP_DIR=\"/tmp/remnawave_backup_\$TIMESTAMP\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'DB_BACKUP_FILE=\"\$TEMP_DIR/remnawave_db.sql\"\n\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'echo \"%s\"\n' \"$text_creating_temp_dir\" >> '$BACKUP_SCRIPT_PATH'
        printf 'mkdir -p \"\$TEMP_DIR\"\n\n' >> '$BACKUP_SCRIPT_PATH'
        printf '# 1. Создаем дамп базы данных\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'echo \"%s\"\n' \"$text_creating_db_dump\" >> '$BACKUP_SCRIPT_PATH'
        printf 'if ! PGPASSWORD=\"\$DB_PASS\" docker exec -i \"\$DB_HOST\" pg_dump -U \"\$DB_USER\" -d \"\$DB_NAME\" > \"\$DB_BACKUP_FILE\"; then\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    echo \"%s\" \"\$DB_HOST\".\n' \"$text_db_dump_error\" >> '$BACKUP_SCRIPT_PATH'
        printf '    rm -rf \"\$TEMP_DIR\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    exit 1\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'fi\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'echo \"%s\"\n' \"$text_db_dump_success\" >> '$BACKUP_SCRIPT_PATH'
        printf '\n' >> '$BACKUP_SCRIPT_PATH'
        printf '# 2. Копируем файлы в зависимости от типа бэкапа\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'case \"\$BACKUP_TYPE\" in\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    \"db_and_remnawave\")\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        echo \"%s\"\n' \"$text_copying_remnawave_dir\" >> '$BACKUP_SCRIPT_PATH'
        printf '        cp -a /opt/remnawave \"\$TEMP_DIR/\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        ;;\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    \"all_opt\")\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        echo \"%s\"\n' \"$text_copying_all_opt\" >> '$BACKUP_SCRIPT_PATH'
        printf '        for dir in /opt/*; do\n' >> '$BACKUP_SCRIPT_PATH'
        printf '            if [ \"\$dir\" != \"\$BACKUP_DIR\" ]; then\n' >> '$BACKUP_SCRIPT_PATH'
        printf '                cp -a \"\$dir\" \"\$TEMP_DIR/\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '            fi\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        done\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        ;;\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    \"db_only\")\n' >> '$BACKUP_SCRIPT_PATH'
        printf '        echo \"%s\"\n' \"$text_db_only_backup_selected\" >> '$BACKUP_SCRIPT_PATH'
        printf '        ;;\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'esac\n\n' >> '$BACKUP_SCRIPT_PATH'
        printf '# 3. Архивируем все содержимое временной директории\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'echo \"%s\"\n' \"$text_creating_single_archive\" >> '$BACKUP_SCRIPT_PATH'
        printf 'if ! tar -czf \"\$FINAL_ARCHIVE_FILE\" -C \"\$TEMP_DIR\" .; then\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    echo \"%s\"\n' \"$text_archive_error\" >> '$BACKUP_SCRIPT_PATH'
        printf '    rm -rf \"\$TEMP_DIR\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '    exit 1\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'fi\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'echo \"%s\$FINAL_ARCHIVE_FILE\"\n' \"$text_archive_success\" >> '$BACKUP_SCRIPT_PATH'
        printf '\n' >> '$BACKUP_SCRIPT_PATH'
        printf '# 4. Отправка единого архива в Telegram\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'send_telegram_file \"\$FINAL_ARCHIVE_FILE\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'MESSAGE_TO_SEND=\"📅 Дата: \$(date +\"%%Y-%%m-%%d %%H:%%M:%%S\")\\n✅ Бэкап успешно создан\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'send_telegram_message \"\$MESSAGE_TO_SEND\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf '\n' >> '$BACKUP_SCRIPT_PATH'
        printf '# 5. Очищаем старые бэкапы\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'clean_old_backups\n\n' >> '$BACKUP_SCRIPT_PATH'
        printf '# 6. Удаляем временную директорию\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'echo \"%s\"\n' \"$text_deleting_temp_dir\" >> '$BACKUP_SCRIPT_PATH'
        printf 'rm -rf \"\$TEMP_DIR\"\n' >> '$BACKUP_SCRIPT_PATH'
        printf 'echo \"Завершено\"\n' >> '$BACKUP_SCRIPT_PATH'
    "
    
    sudo chmod +x "$BACKUP_SCRIPT_PATH"
    echo "$(get_text "SCRIPT_SAVED")$BACKUP_SCRIPT_PATH"

    echo "$(get_text "RUNNING_ONE_TIME_BACKUP")"
    sudo bash "$BACKUP_SCRIPT_PATH"

    if [ "$setup_cron" == "true" ]; then
        echo ""
        echo "$(get_text "CRON_SETUP_HEADER")"
        echo "$(get_text "CRON_SCHEDULE_PROMPT")"
        
        echo "1) $(get_text "CRON_DAILY")"
        echo "2) $(get_text "CRON_TWICE_DAILY")"
        echo "3) $(get_text "CRON_WEEKLY")"
        echo "4) $(get_text "CRON_CUSTOM")"
        
        read -p "$(get_text "CRON_CHOICE_PROMPT")" choice_cron

        local CRON_SCHEDULE=""
        case "$choice_cron" in
            1) CRON_SCHEDULE="0 3 * * *" ;;
            2) CRON_SCHEDULE="0 3,15 * * *" ;;
            3) CRON_SCHEDULE="0 3 * * 0" ;;
            4) read -p "$(get_text "CRON_CUSTOM")" CRON_SCHEDULE ;;
            *) echo "$(get_text "CRON_INVALID_CHOICE")"; CRON_SCHEDULE="0 3 * * *" ;;
        esac

        (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH"; echo "$CRON_SCHEDULE $BACKUP_SCRIPT_PATH > /dev/null 2>&1") | sudo crontab -
        echo "$(get_text "CRON_SCHEDULE_SAVED")'$CRON_SCHEDULE'."
    else
        echo "$(get_text "BACKUP_DONE_NO_CRON")"
    fi

    echo "$(get_text "PRESS_ENTER_TO_RETURN")"
    read -r
    start
}