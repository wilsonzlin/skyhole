#!/usr/bin/env bash

set -e

pushd "$(dirname "$0")" > /dev/null

error() {
  echo >&2 "$1"
  popd > /dev/nul
  exit 1
}

export DEBIAN_FRONTEND=noninteractive

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

  *) # unknown option
    error "Unknown option $1"
    ;;
  esac
done

if [ -z "$PASSWORD" ]; then
  echo -n Password:
  read -s PASSWORD
  echo
fi

if [ -z "$EMAIL" ]; then error "No email"; fi
if [ -z "$DOMAIN" ]; then error "No domain"; fi
if [ -z "$PASSWORD" ]; then error "No password"; fi

# Install system updates.
sudo apt update
sudo apt dist-upgrade -yq
sudo apt install -y software-properties-common

# Install Nginx.
sudo apt -y install nginx
sudo cp nginx.conf /etc/nginx/.
# Stop to prevent conflicting with lighttpd.
# Don't reload/restart Nginx yet, as certificate hasn't been copied yet.
# Post-hook will do this automatically.
sudo systemctl stop nginx

# Install Stubby.
sudo apt install -y stubby
sudo sed -i /etc/stubby/stubby.yml 's%listen_addresses:\n  - 127.0.0.1\n  -  0::1%listen_addresses:\n  - 127.0.0.2\n  -  0::2%'

# Install Pi-hole.
sed pi-hole-setup.conf "s%<<<password>>>%$PASSWORD%" | sudo tee /etc/pihole/setupVars.conf
curl -L https://install.pi-hole.net | bash /dev/stdin --unattended
sed lighttpd.external.conf "s%<<<domain>>>%$DOMAIN%" | sudo tee /etc/lighttpd/external.conf

# Install Certbot.
# Do this last so that pre and post hooks work.
sudo add-apt-repository -y universe
sudo add-apt-repository -y ppa:certbot/certbot
sudo apt update
sudo apt install -y certbot
sed post-00-copy-cert.sh "s%<<<domain>>>%$DOMAIN%" | sudo tee /etc/letsencrypt/renewal-hooks/post/00-copy-cert.sh
sudo cp pre/* /etc/letsencrypt/renewal-hooks/pre/.
sudo cp post/* /etc/letsencrypt/renewal-hooks/post/.
certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"

# Firewall.
# Incoming SSH.
sudo ufw allow proto tcp from any to any port 22
# Incoming HTTPS.
sudo ufw allow proto tcp from any to any port 443
# Incoming and outgoing DNS-over-TLS.
sudo ufw allow proto tcp from any to any port 853
sudo ufw enable

popd > /dev/null
