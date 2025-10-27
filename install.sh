#!/bin/bash

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_RESET='\033[0m'

header_info() {
    clear
    printf "${COLOR_GREEN}"
    cat <<"EOF"
Install
EOF
    printf "${COLOR_RESET}\n"
}

handle_result() {
    if [ "$1" -ne 0 ]; then
        printf "${COLOR_RED}[!] Error during step: %s${COLOR_RESET}\n" "$2" >&2
        exit 1
    else
        printf "${COLOR_GREEN}[+] %s: Success${COLOR_RESET}\n" "$2"
    fi
}

CURRENT_DIR_NAME=$(basename "$PWD")
if [ "$CURRENT_DIR_NAME" != "my_n8n" ]; then
    printf "${COLOR_RED}[!] This script must be executed from the 'my_n8n' directory (currently in '$CURRENT_DIR_NAME').${COLOR_RESET}\n" >&2
    exit 1
fi

if [ ! -f ".env" ]; then
    cat .env-template > .env
    handle_result $? "Creating .env file from .env-template"
    printf "${COLOR_GREEN}[+] Reminder: Please initialize your API keys.${COLOR_RESET}\n"
fi

header_info

if grep -q "export DOMAIN=" "$HOME/.bashrc"; then
    DOMAIN=$(grep "export DOMAIN=" "$HOME/.bashrc" | head -n1 | cut -d'=' -f2)
    printf "${COLOR_GREEN}[+] DOMAIN variable is already defined in .bashrc: %s${COLOR_RESET}\n" "$DOMAIN"
elif [ -z "$DOMAIN" ]; then
    printf "${COLOR_GREEN}[+] Enter your domain: ${COLOR_RESET}"
    read -r DOMAIN
    handle_result $? "Domain input"
    printf "${COLOR_GREEN}[+] Would you like to add DOMAIN to your .bashrc for persistence? (Y/n): ${COLOR_RESET}"
    read -r choice
    if [ "$choice" = "Y" ] || [ "$choice" = "y" ] || [ -z "$choice" ]; then
         echo "export DOMAIN=${DOMAIN}" >> "$HOME/.bashrc"
         handle_result $? "Adding DOMAIN to .bashrc"
    fi
else
    printf "${COLOR_GREEN}[+] DOMAIN variable already set in environment: %s${COLOR_RESET}\n" "$DOMAIN"
    printf "${COLOR_GREEN}[+] Would you like to add DOMAIN to your .bashrc for persistence? (Y/n): ${COLOR_RESET}"
    read -r choice
    if [ "$choice" = "Y" ] || [ "$choice" = "y" ] || [ -z "$choice" ]; then
         echo "export DOMAIN=${DOMAIN}" >> "$HOME/.bashrc"
         handle_result $? "Adding DOMAIN to .bashrc"
    fi
fi

export DOMAIN
handle_result $? "Exporting DOMAIN variable"

envsubst '$DOMAIN' < ./nginx-template.conf > ./nginx/nginx.conf
handle_result $? "Substituting variables in nginx.conf"

if grep -q "^alias clonethis=" "$HOME/.bash_aliases"; then
    printf "${COLOR_GREEN}[+] Alias for 'clonethis' already exists in .bash_aliases. Skipping alias creation.${COLOR_RESET}\n"
else
    printf "${COLOR_GREEN}[+] Enter alias command for 'clonethis' (leave empty to skip): ${COLOR_RESET}"
    read -r ALIAS_CMD
    if [ -n "$ALIAS_CMD" ]; then
        echo "alias clonethis='${ALIAS_CMD}'" >> "$HOME/.bash_aliases"
        handle_result $? "Saving alias for clonethis in .bash_aliases"
        printf "${COLOR_GREEN}[+] Alias for 'clonethis' saved. Please reload your terminal or run 'source ~/.bash_aliases' to apply it.${COLOR_RESET}\n"
    fi
fi

# -------------------------------------------------------------------
# Section: Let's Encrypt certificate generation and nginx reload
# -------------------------------------------------------------------

domains=(
    "$DOMAIN"
    "www.$DOMAIN"
    "api.$DOMAIN")
rsa_key_size=4096
data_path="./nginx/certbot"
email="${SSL_EMAIL:-terangui879@tersi.com}" # Adding a valid address is strongly recommended
staging=0 # Set to 1 if you're testing your setup to avoid hitting request limits

if [ -d "$data_path" ]; then
    printf "${COLOR_GREEN}[+] Existing data found for %s. Continue and replace existing certificate? (y/N): ${COLOR_RESET}" "$domains"
    read -r decision
    if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
        printf "${COLOR_RED}[!] Aborting operation.${COLOR_RESET}\n"
        exit
    fi
fi

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
    printf "${COLOR_GREEN}[+] Downloading recommended TLS parameters...${COLOR_RESET}\n"
    mkdir -p "$data_path/conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf >"$data_path/conf/options-ssl-nginx.conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem >"$data_path/conf/ssl-dhparams.pem"
    printf "\n"
fi

printf "${COLOR_GREEN}[+] Creating dummy certificate for %s...${COLOR_RESET}\n" "$domains"
path="/etc/letsencrypt/live/$domains"
mkdir -p "$data_path/conf/live/$domains"
docker compose -f "docker-compose.yml" run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot
handle_result $? "Dummy certificate creation"
printf "\n"

printf "${COLOR_GREEN}[+] Starting nginx...${COLOR_RESET}\n"
docker compose -f "docker-compose.yml" up --force-recreate -d nginx
handle_result $? "Nginx start"
printf "\n"

printf "${COLOR_GREEN}[+] Deleting dummy certificate for %s...${COLOR_RESET}\n" "$domains"
docker compose -f "docker-compose.yml" run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domains && \
  rm -Rf /etc/letsencrypt/archive/$domains && \
  rm -Rf /etc/letsencrypt/renewal/$domains.conf" certbot
handle_result $? "Dummy certificate deletion"
printf "\n"

printf "${COLOR_GREEN}[+] Requesting Let's Encrypt certificate for %s...${COLOR_RESET}\n" "$domains"
# Join $domains to -d args
domain_args=""
for domain in "${domains[@]}"; do
    domain_args="$domain_args -d $domain"
done

# Select appropriate email arg
case "$email" in
    "") email_arg="--register-unsafely-without-email" ;;
    *) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

docker compose -f "docker-compose.yml" run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
handle_result $? "Let's Encrypt certificate request"
printf "\n"

printf "${COLOR_GREEN}[+] Reloading nginx...${COLOR_RESET}\n"
docker compose -f "docker-compose.yml" exec nginx nginx -s reload
handle_result $? "Nginx reload"
