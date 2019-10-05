#!/usr/bin/env bash

set -e

pushd "$(dirname "$0")" > /dev/null

error() {
  echo >&2 "$1"
  popd > /dev/null
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
sudo apt install -y software-properties-common wget

# Install Nginx.
sudo apt -y install nginx
sudo cp nginx.conf /etc/nginx/.
# Stop to prevent conflicting with lighttpd.
# Don't reload/restart Nginx yet, as certificate hasn't been copied yet.
# Post-hook will do this automatically.
sudo systemctl stop nginx

# Install Stubby.
sudo apt install -y stubby
sudo sed -i 's/^  - 127.0.0.1$/  - 127.0.0.2/' /etc/stubby/stubby.yml
sudo sed -i 's/^  - 0::1$/  - 0::2/' /etc/stubby/stubby.yml

# Install Pi-hole.
sudo mkdir -p /etc/pihole/
# Find IPv4 address, gateway, subnet, and interface.
route=$(ip route get 8.8.8.8 | head -1)
ipv4="$(echo $route | awk '{print $7}')"
gateway="$(echo $route | awk '{print $3}')"
interface="$(echo $route | awk '{print $5}')"
subnet=$(ip -oneline -family inet address show | grep "${ipv4}/" |  awk '{print $4}')
# Run Pi-hole install script.
sed \
  "s/<<<ipv4>>>/$subnet/" \
  "s/<<<interface>>>/$interface/" \
  pi-hole-setup.conf | sudo tee /etc/pihole/setupVars.conf
script="$(mktemp)"
wget -O "$script" https://install.pi-hole.net
sudo bash "$script" --unattended
rm "$script"
pihole -a -p "$PASSWORD"
sed "s/<<<domain>>>/$DOMAIN/" lighttpd.external.conf | sudo tee /etc/lighttpd/external.conf

# Install Certbot.
# Do this last so that pre and post hooks work.
sudo add-apt-repository -y universe
sudo add-apt-repository -y ppa:certbot/certbot
sudo apt update
sudo apt install -y certbot
sed "s/<<<domain>>>/$DOMAIN/" post-00-copy-cert.sh | sudo tee /etc/letsencrypt/renewal-hooks/post/00-copy-cert.sh
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
