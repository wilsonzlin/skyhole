#!/usr/bin/env bash

set -e

pushd "$(dirname "$0")" > /dev/null

error() {
  echo >&2 "$1"
  popd > /dev/null
  exit 1
}

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
  --email)
    EMAIL="$2"
    shift # past argument
    shift # past value
    ;;

  --domain)
    DOMAIN="$2"
    shift # past argument
    shift # past value
    ;;

  --password)
    PASSWORD="$2"
    shift # past argument
    shift # past value
    ;;

  --ssh)
    SSH_PORT="$2"
    shift # past argument
    shift # past value
    ;;

  --https)
    HTTPS_PORT="$2"
    shift # past argument
    shift # past value
    ;;

  --dot)
    DOT_PORT="$2"
    shift # past argument
    shift # past value
    ;;

  --incoming)
    FIREWALL_CIDR="$2"
    shift # past argument
    shift # past value
    ;;

  *) # unknown option
    error "Unknown option $1"
    ;;
  esac
done

if [ -z "$PASSWORD" ]; then
  echo -n 'Password: '
  read -s PASSWORD
  echo
  echo -n 'Confirm password: '
  read -s PASSWORD_CONFIRM
  echo
  if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    error "Passwords do not match"
  fi
  echo
fi

if [ -z "$EMAIL" ]; then error "No email"; fi
if [ -z "$DOMAIN" ]; then error "No domain"; fi
if [ -z "$PASSWORD" ]; then error "No password"; fi
if [ -z "$SSH_PORT" ]; then SSH_PORT=22; fi
if [ -z "$HTTPS_PORT" ]; then HTTPS_PORT=443; fi
if [ -z "$DOT_PORT" ]; then DOT_PORT=853; fi
if [ -z "$FIREWALL_CIDR" ]; then FIREWALL_CIDR=0.0.0.0/0; fi

# Install system updates.
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt \
  -o Dpkg::Options::=--force-confold \
  -o Dpkg::Options::=--force-confdef \
  dist-upgrade \
  -yq \
  --allow-downgrades \
  --allow-remove-essential \
  --allow-change-held-packages
sudo apt install -y software-properties-common wget

# Install Nginx.
sudo apt -y install nginx
sed "s/<<<port>>>/$DOT_PORT/" nginx.conf | \
  sudo tee /etc/nginx/nginx.conf
# This will be eventually used by Let's Encrypt post-renewal script.
sudo mkdir -p /etc/nginx/ssl
# Stop to prevent conflicting with lighttpd.
# Don't reload/restart Nginx yet, as certificate hasn't been copied yet.
# Post-hook will do this automatically.
sudo systemctl stop nginx

# Install Stubby.
sudo apt install -y stubby
sudo sed -i 's/^  - 127.0.0.1$/  - 127.0.0.2/' /etc/stubby/stubby.yml
# It's not a typo; there are two spaces after the hyphen in the original file.
sudo sed -i 's/^  -  0::1$/  - 0::2/' /etc/stubby/stubby.yml
sudo systemctl restart stubby

# Install Pi-hole.
sudo mkdir -p /etc/pihole/
# Find IPv4 address, subnet, and interface.
route=$(ip route get 8.8.8.8 | head -1)
ipv4="$(echo $route | awk '{print $7}')"
interface="$(echo $route | awk '{print $5}')"
subnet="$(ip -oneline -family inet address show | grep "${ipv4}/" | awk '{print $4}')"
# Run Pi-hole install script.
# Subnet contains slashes, so use % for sed.
sed "s%<<<ipv4>>>%$subnet%; s%<<<interface>>>%$interface%" pi-hole-setup.conf | \
  sudo tee /etc/pihole/setupVars.conf
script="$(mktemp)"
wget -O "$script" https://install.pi-hole.net
sudo bash "$script" --unattended
rm "$script"
pihole -a -p "$PASSWORD"
sed "s/<<<domain>>>/$DOMAIN/; s/<<<port>>>/$HTTPS_PORT/" lighttpd.external.conf | \
  sudo tee /etc/lighttpd/external.conf

# Install Certbot.
# Do this last so that pre and post hooks work.
sudo add-apt-repository -y universe
sudo add-apt-repository -y ppa:certbot/certbot
sudo apt update
sudo apt install -y certbot
# Install pre hook.
sudo mkdir -p /etc/letsencrypt/renewal-hooks/pre
sudo cp certbot-pre.sh /etc/letsencrypt/renewal-hooks/pre/pre.sh
# Install post hook.
sudo mkdir -p /etc/letsencrypt/renewal-hooks/post
sed "s/<<<domain>>>/$DOMAIN/" certbot-post.sh | sudo tee /etc/letsencrypt/renewal-hooks/post/post.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/post/post.sh
# certonly doesn't run hooks, so run manually.
sudo /etc/letsencrypt/renewal-hooks/pre/pre.sh
sudo certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"
sudo /etc/letsencrypt/renewal-hooks/post/post.sh

# SSH
sudo sed -i "s/^#Port 22$/Port $SSH_PORT/" /etc/ssh/sshd_config
sudo systemctl restart ssh

# Firewall.
# Incoming SSH.
sudo ufw allow proto tcp from "$FIREWALL_CIDR" to "$FIREWALL_CIDR" port "$SSH_PORT"
# Incoming HTTPS.
sudo ufw allow proto tcp from "$FIREWALL_CIDR" to "$FIREWALL_CIDR" port "$HTTPS_PORT"
# Incoming and outgoing DNS-over-TLS.
sudo ufw allow proto tcp from "$FIREWALL_CIDR" to "$FIREWALL_CIDR" port "$DOT_PORT"
sudo ufw --force enable

popd > /dev/null
