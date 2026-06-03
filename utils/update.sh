#!/bin/bash

# Colors
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RED="\033[31m"
CYAN="\033[36m"

# Detecting system language
SYS_LANG="${LANG:0:2}"

# Localization
case "$SYS_LANG" in
    ru)
        STR_ERR="Ошибка:"
        STR_NOT_FOUND="не найдена!"
        STR_START="Начинаем обновление репозиториев в"
        STR_CHECK="▶ Проверяем репозиторий:"
        STR_DETACHED="⚠ Внимание: Вы вне ветки (detached HEAD). Ищем основную..."
        STR_SWITCH="➔ Переключаемся на:"
        STR_NO_BRANCH="✖ Ошибка: Не удалось определить основную ветку. Пропускаем."
        STR_SUCCESS="✔ Успешно обновлено!"
        STR_PULL_ERR="✖ Ошибка при git pull!"
        STR_DONE="Процесс обновления завершен!"
        STR_FOLDER="Папка"
        ;;
    uk|ua)
        STR_ERR="Помилка:"
        STR_NOT_FOUND="не знайдено!"
        STR_START="Починаємо оновлення репозиторіїв у"
        STR_CHECK="▶ Перевіряємо репозиторій:"
        STR_DETACHED="⚠ Увага: Ви поза гілкою (detached HEAD). Шукаємо основну..."
        STR_SWITCH="➔ Переключаємося на:"
        STR_NO_BRANCH="✖ Помилка: Не вдалося визначити основну гілку. Пропускаємо."
        STR_SUCCESS="✔ Успішно оновлено!"
        STR_PULL_ERR="✖ Помилка при git pull!"
        STR_DONE="Процес оновлення завершено!"
        STR_FOLDER="Папка"
        ;;
    *) # Английский по умолчанию (en)
        STR_ERR="Error:"
        STR_NOT_FOUND="not found!"
        STR_START="Starting repository updates in"
        STR_CHECK="▶ Checking repository:"
        STR_DETACHED="⚠ Warning: You are in a detached HEAD state. Looking for the main branch..."
        STR_SWITCH="➔ Switching to:"
        STR_NO_BRANCH="✖ Error: Could not determine the main branch. Skipping."
        STR_SUCCESS="✔ Successfully updated!"
        STR_PULL_ERR="✖ Error during git pull!"
        STR_DONE="Update process completed!"
        STR_FOLDER="Folder"
        ;;
esac

TARGET_DIR="deps"

if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}${BOLD}${STR_ERR}${RESET} ${STR_FOLDER} ${YELLOW}$TARGET_DIR${RESET} ${STR_NOT_FOUND}"
    exit 1
fi

echo -e "${CYAN}${BOLD}================================================${RESET}"
echo -e "${CYAN}${BOLD}  ${STR_START} $TARGET_DIR/ ${RESET}"
echo -e "${CYAN}${BOLD}================================================${RESET}"

for dir in "$TARGET_DIR"/*/; do
    if [ -d "$dir" ] && [ -d "${dir}.git" ]; then
        repo_name=$(basename "$dir")
        echo -e "\n${BLUE}${BOLD}${STR_CHECK}${RESET} ${BOLD}$repo_name${RESET}"
        
        (
            cd "$dir" || exit
            
            # Checking detached HEAD
            if ! git symbolic-ref -q HEAD > /dev/null; then
                echo -e "  ${YELLOW}${STR_DETACHED}${RESET}"
                
                # Search for main branch
                default_branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | cut -d' ' -f5)
                
                if [ -z "$default_branch" ]; then
                    if git show-ref --verify --quiet refs/heads/main; then
                        default_branch="main"
                    elif git show-ref --verify --quiet refs/heads/master; then
                        default_branch="master"
                    fi
                fi
                
                if [ -n "$default_branch" ]; then
                    echo -e "  ${YELLOW}${STR_SWITCH}${RESET} $default_branch"
                    git checkout "$default_branch"
                else
                    echo -e "  ${RED}${STR_NO_BRANCH}${RESET}"
                    exit 1
                fi
            fi
            
            # Attempting to perform git pull
            if git pull; then
                echo -e "  ${GREEN}${STR_SUCCESS}${RESET}"
            else
                echo -e "  ${RED}${STR_PULL_ERR}${RESET}"
            fi
        )
    fi
done

echo -e "\n${CYAN}${BOLD}================================================${RESET}"
echo -e "${GREEN}${BOLD}  ${STR_DONE}${RESET}"
echo -e "${CYAN}${BOLD}================================================${RESET}"