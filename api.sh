#!/bin/bash
generate_random_string() {
    local length=$1
    local chars=${2:-"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-="}
    local random_string=""

    if [ -z "$length" ]; then
        echo "❌ Ошибка: Не указана длина строки."
        return 1
    fi

    for ((i = 0; i < length; i++)); do
        random_string+="${chars:RANDOM%${#chars}:1}"
    done
    echo "$random_string"
}
make_api_request() {
    local method=$1
    local url=$2
    local data=$3
    local response

    response=$(curl -s -X "$method" "$url" \
               -H "Content-Type: application/json" \
               -d "$data")

    echo "$response"
}

# Функция для получения токена из файла .env
get_panel_token() {
    local ENV_FILE="/opt/remnawave/.env"
    local TOKEN_VAR="JWT_API_TOKENS_SECRET"

    # 1. Проверяем, существует ли файл .env
    if [ ! -f "$ENV_FILE" ]; then
        echo "❌ ОШИБКА: Файл .env не найден по пути $ENV_FILE."
        return 1
    fi

    # 2. Ищем строку с токеном в файле и извлекаем его значение
    local token=$(grep "^$TOKEN_VAR=" "$ENV_FILE" | cut -d'=' -f2-)
    
    # 3. Проверяем, удалось ли получить токен
    if [ -z "$token" ]; then
        echo "❌ ОШИБКА: Не удалось найти JWT_API_TOKENS_SECRET в файле .env."
        return 1
    fi

    echo "✅ Токен успешно получен из файла .env."
    echo "$token"
}
register_panel_user() {
    clear
    
    # 1. Запрашиваем домен панели
    read -p "Пожалуйста, введите домен вашей панели (например, panel.example.com): " domain
    if [ -z "$domain" ]; then
        echo "❌ ОШИБКА: Домен не может быть пустым."
        return 1
    fi

    # 2. Запрашиваем учетные данные с пояснениями
    read -p "Введите логин для администратора: " username
    echo "⚠️ ПАРОЛЬ должен быть не менее 24 символов и содержать буквы, цифры и заглавные/строчные символы."
    read -s -p "Введите пароль для администратора: " password
    echo

    if [ -z "$username" ] || [ -z "$password" ]; then
        echo "❌ ОШИБКА: Логин или пароль не могут быть пустыми."
        return 1
    fi

    # Добавьте проверку длины пароля
    if [ ${#password} -lt 24 ]; then
        echo "❌ ОШИБКА: Пароль слишком короткий. Он должен быть не менее 24 символов."
        return 1
    fi

    # 3. Формируем JSON-тело запроса
    local json_data="{\"username\": \"$username\", \"password\": \"$password\"}"
    
    # 4. Отправляем API-запрос на регистрацию
    local api_url="http://$domain/api/auth/register"
    local response=$(make_api_request "POST" "$api_url" "$json_data")

    # 5. Проверяем ответ от сервера
    if echo "$response" | grep -q '"success":true'; then
        echo "🎉 УСПЕХ: Пользователь $username успешно зарегистрирован!"
        echo "✅ Ответ сервера: $response"
    else
        echo "❌ ОШИБКА: Не удалось зарегистрировать пользователя."
        echo "❗ Ответ сервера: $response"
        return 1
    fi

    return 0
}
get_config_profiles() {
    local domain_url="$1"
    local token="$2"

    local config_response=$(make_api_request "GET" "http://$domain_url/api/config-profiles" "$token")
    if [ -z "$config_response" ] || ! echo "$config_response" | jq -e '.response.configProfiles' > /dev/null 2>&1; then
        echo -e "${RED}❌ $(get_text ERROR_CONFIG_PROFILE_NOT_FOUND): ${config_response}${NC}"
        return 1
    fi

    local profile_uuid=$(echo "$config_response" | jq -r '.response.configProfiles[] | select(.name == "Default-Profile") | .uuid' 2>/dev/null)
    if [ -z "$profile_uuid" ]; then
        echo -e "${YELLOW}❌ $(get_text ERROR_CONFIG_PROFILE_NOT_FOUND)${NC}"
        return 1
    fi

    echo "$profile_uuid"
    return 0
}

get_inbound_from_panel() {
    local domain_url=$1
    local token=$2

    local inbounds_response=$(make_api_request "GET" "http://$domain_url/api/inbounds" "$token")
    if [ -z "$inbounds_response" ] || ! echo "$inbounds_response" | jq -e '.response.inbounds' > /dev/null 2>&1; then
        echo -e "${RED}❌ $(get_text ERROR_GET_INBOUNDS): $inbounds_response${NC}"
        return 1
    fi

    local inbounds=$(echo "$inbounds_response" | jq -r '.response.inbounds[] | "\(.uuid) \(.name)"')
    if [ -z "$inbounds" ]; then
        echo -e "${RED}❌ $(get_text NO_INBOUNDS_FOUND)${NC}"
        return 1
    fi

    local i=1
    declare -A inbound_map
    echo "$(get_text SELECT_INBOUND)"
    while IFS= read -r line; do
        local uuid=$(echo "$line" | awk '{print $1}')
        local name=$(echo "$line" | cut -d' ' -f2-)
        inbound_map["$i"]="$uuid"
        echo -e "${ORANGE}$i) ${WHITE}$name${NC}"
        ((i++))
    done <<< "$inbounds"

    echo ""
    read -p "$(get_text ENTER_YOUR_CHOICE): " choice
    local selected_uuid="${inbound_map[$choice]}"
    
    if [ -z "$selected_uuid" ]; then
        return 1
    fi

    echo "$selected_uuid"
}

create_node() {
    local domain_url=$1
    local token=$2
    local config_profile_uuid=$3
    local inbound_uuid=$4
    local node_address="${5:-$(curl -s -4 ifconfig.me || curl -s -4 api.ipify.org || curl -s -4 ipinfo.io/ip)}"
    local node_name="${6:-Node-$(date +%s)}"

    local node_data=$(cat <<EOF
{
    "name": "$node_name",
    "address": "$node_address",
    "port": 2222,
    "configProfile": {
        "activeConfigProfileUuid": "$config_profile_uuid",
        "activeInbounds": ["$inbound_uuid"]
    },
    "isTrafficTrackingActive": false,
    "trafficLimitBytes": 0,
    "notifyPercent": 0,
    "trafficResetDay": 31,
    "excludedInbounds": [],
    "countryCode": "XX",
    "consumptionMultiplier": 1.0
}
EOF
)

    local node_response=$(make_api_request "POST" "http://$domain_url/api/nodes" "$token" "$node_data")

    if [ -z "$node_response" ] || ! echo "$node_response" | jq -e '.response.uuid' > /dev/null 2>&1; then
        echo -e "${RED}$(get_text ERROR_CREATE_NODE): ${node_response}${NC}"
        return 1
    fi

    echo -e "${GREEN}$(get_text NODE_CREATED)${NC}\n"
    return 0
}
