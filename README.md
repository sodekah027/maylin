# maylin

Installer **Marzban + MarLing** mandiri (Debian 12/11, Ubuntu 20.04). Tanpa script pihak lain: image `gozargah/marzban`, compose, nginx, xray, template, env semuanya di repo ini.

## Pasang
```bash
apt-get update && apt-get install -y curl && \
curl -fsSL https://cdn.jsdelivr.net/gh/sodekah027/maylin@main/install.sh -o /root/maylin.sh && \
chmod +x /root/maylin.sh && /root/maylin.sh
```
Siapkan A record domain ke IP VPS dulu (acme butuh port 80).

## Isi
- sysctl/BBR, timezone, paket dasar, Docker
- Marzban image resmi + nginx WS/XHTTP single-port
- sertifikat acme ec-256
- admin dari input, ufw (ssh/http/https/8081/1080), token API

## Terkait
SlowDNS/kelola user: `mayling-slowdns`.
