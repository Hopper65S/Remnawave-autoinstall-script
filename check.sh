#!/bin/bash

# === ФУНКЦИИ ПРОВЕРОК ===
check_ssh_port() {
    local current_port=$(grep -E "^Port\s+" /etc/ssh/sshd_config | awk '{print $2}' | tail -n1)
    if [ "$current_port" = "$SSH_PORT" ]; then
        return 0 # уже настроено
    else
        return 1 # нужно настраивать
    fi
}

check_ssh_security() {
    local root_login=$(grep -E "^PermitRootLogin\s+" /etc/ssh/sshd_config | tail -n1 | awk '{print $2}')
    local password_auth=$(grep -E "^PasswordAuthentication\s+" /etc/ssh/sshd_config | tail -n1 | awk '{print $2}')
    
    if [ "$root_login" = "no" ] && [ "$password_auth" = "no" ]; then
        return 0 # уже настроено
    else
        return 1 # нужно настраивать
    fi
}

check_user_exists() {
    if id "$NEW_USER" &>/dev/null; then
        return 0 # пользователь существует
    else
        return 1 # пользователя нет
    fi
}

check_ssh_key() {
    local key_file="/home/$NEW_USER/.ssh/authorized_keys"
    if [ -f "$key_file" ] && grep -q "$AUTHORIZED_KEY" "$key_file" 2>/dev/null; then
        return 0 # ключ уже настроен
    else
        return 1 # ключ не настроен
    fi
}

check_docker_installed() {
    if command -v docker &>/dev/null; then
        return 0 # docker установлен
    else
        return 1 # docker не установлен
    fi
}

check_caddy_installed() {
    if command -v caddy &>/dev/null; then
        return 0 # caddy установлен
    else
        return 1 # caddy не установлен
    fi
}

check_caddy_config() {
    if [ -f "/etc/caddy/Caddyfile" ] && grep -q "$DOMAIN" "/etc/caddy/Caddyfile" 2>/dev/null; then
        return 0 # конфиг уже настроен
    else
        return 1 # конфиг не настроен
    fi
}