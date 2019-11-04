#!/bin/sh

cert_dir="/etc/letsencrypt/live/<<<domain>>>"

cat "$cert_dir/privkey.pem" "$cert_dir/cert.pem" | tee /etc/lighttpd/combined.pem
cp "$cert_dir/fullchain.pem" /etc/lighttpd/fullchain.pem

cp "$cert_dir/privkey.pem" /etc/nginx/ssl/dns.key
cp "$cert_dir/fullchain.pem" /etc/nginx/ssl/dns.crt

systemctl restart nginx
systemctl start lighttpd
