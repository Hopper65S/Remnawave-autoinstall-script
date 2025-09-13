#!/bin/bash

make_api_request() {
    local method=$1
    local url=$2
    local token=$3
    local data=$4

    local headers=(
        -H "Authorization: Bearer $token"
        -H "Content-Type: application/json"
    )

    local response
    response=$(curl -X "$method" "$url" "${headers[@]}" -d "$data")

    echo "$response"
}

get_panel_token() {
    local ENV_FILE=".env"
    local TOKEN_VAR="REMNANAWAVE_API_TOKEN"
    local token=""

    # 1. Проверяем, существует ли токен в .env
    if [ -f "$ENV_FILE" ]; then
        token=$(grep "^$TOKEN_VAR=" "$ENV_FILE" | cut -d'=' -f2-)
        if [ -n "$token" ]; then
            echo -e "${GREEN}$(get_text USING_SAVED_TOKEN)${NC}"
            echo "$token"
            return 0
        fi
    fi

    # 2. Если токена нет, запрашиваем у пользователя
    echo -e "${YELLOW}$(get_text ENTER_PANEL_TOKEN)${NC}"
    read -p "Token: " user_token

    if [ -z "$user_token" ]; then
        echo -e "${RED}❌ $(get_text ERROR_MISSING_TOKEN)${NC}"
        return 1
    fi
    
    # 3. Добавляем токен в .env
    echo -e "\n$TOKEN_VAR=$user_token" >> "$ENV_FILE"
    echo -e "${GREEN}$(get_text TOKEN_RECEIVED_AND_SAVED)${NC}"
    echo "$user_token"
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
