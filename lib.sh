#!/bin/bash

# Функция для получения перевода
get_text() {
    local key=$1
    if [[ $LANG_CHOICE == "ru" ]]; then
        echo "${lang_ru[$key]}"
    else
        echo "${lang_en[$key]}"
    fi
}

yn_prompt() {
    local -a yn_options=("Да" "Нет")
    local selected_index=0
    
    while true; do
        clear
        echo -e "${ORANGE}$1${NC}" # Выводим текст вопроса
        echo ""
        
        for i in "${!yn_options[@]}"; do
            if [[ $i -eq $selected_index ]]; then
                echo -e "${GREEN}● ${yn_options[$i]}${NC}"
            else
                echo -e "${ORANGE}○ ${yn_options[$i]}${NC}"
            fi
        done
        
        echo ""
        echo -e "${ORANGE}Навигация: ↑↓, Выбор: Enter${NC}"
        
        read -sn1 -r key
        
        case "$key" in
            $'\x1b')
                read -sn1 -r -t 0.001 key
                read -sn1 -r -t 0.001 key
                case "$key" in
                    A)
                        ((selected_index = 0))
                        ;;
                    B)
                        ((selected_index = 1))
                        ;;
                esac
                ;;
            "")
                if [ "$selected_index" -eq 0 ]; then
                    return 0 # Да (Yes)
                else
                    return 1 # Нет (No)
                fi
                ;;
        esac
    done
}