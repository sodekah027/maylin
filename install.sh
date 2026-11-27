#!/bin/bash
# maylin/install.sh - installer Marzban + MarLing mandiri (tanpa script pihak lain)
set -euo pipefail
R="https://cdn.jsdelivr.net/gh/sodekah027/maylin@main"
D=/opt/marzban
DATA=/etc/maylin

r() { printf '\e[92m%s\e[0m\n' "$*"; }
y() { printf '\e[93m%s\e[0m\n' "$*"; }
e() { printf '\e[91m%s\e[0m\n' "$*"; }
die() { e "$*"; exit 1; }

[ "$(id -u)" = 0 ] || die "root saja"
. /etc/os-release 2>/dev/null || die "os-release tak ada"
case "$ID $VERSION_ID" in
  "debian 12"|"debian 11"|"ubuntu 20.04") ;;
  *) die "hanya Debian 11/12 atau Ubuntu 20.04" ;;
esac

mkdir -p "$DATA" "$D" /var/lib/marzban /var/www/html /var/log/nginx
touch /var/log/nginx/access.log /var/log/nginx/error.log

# ---- data panel ----
read -rp "Domain (sudah A ke IP ini): " domain
[ -n "$domain" ] || die "domain wajib"
read -rp "Email acme: " email
[ -n "$email" ] || die "email wajib"
while :; do
  read -rp "Username panel (alnum, tanpa 'admin'): " userpanel
  [[ "$userpanel" =~ ^[A-Za-z0-9]+$ ]] && [[ ! "$userpanel" =~ [Aa][Dd][Mm][Ii][Nn] ]] && break
  y "ulangi"
done
read -rsp "Password panel: " passpanel; echo
[ -n "$passpanel" ] || die "password wajib"
printf '%s\n' "$domain" >"$DATA/domain"
printf '%s\n' "$userpanel" >"$DATA/userpanel"
printf '%s\n' "$passpanel" >"$DATA/passpanel"; chmod 600 "$DATA/passpanel"

# ---- paket ----
y "== update & paket =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get purge -y --auto-remove samba* apache2* sendmail* bind9* >/dev/null 2>&1 || true
apt-get install -y curl wget unzip zip screen htop nano socat iptables ufw cron at bsdmainutils lsof lnav bc gnupg dnsutils net-tools vnstat docker.io docker-compose-plugin 2>/dev/null \
  || { curl -fsSL https://get.docker.com | sh; }

# pastikan docker daemon hidup
systemctl enable --now docker >/dev/null 2>&1 || true
for i in 1 2 3 4 5; do docker info >/dev/null 2>&1 && break; sleep 3; done
docker info >/dev/null 2>&1 || die "docker daemon tidak jalan"
docker compose version >/dev/null 2>&1 || die "docker compose plugin tidak ada"

# ---- sysctl/BBR ----
if ! grep -q "maylin-bbr" /etc/sysctl.conf 2>/dev/null; then
  sed -i 's/^net.ipv6.conf.all.disable_ipv6.*/# &/' /etc/sysctl.conf 2>/dev/null || true
  cat >>/etc/sysctl.conf <<'EOF'
# maylin-bbr
fs.file-max = 500000
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_fastopen = 3
net.ipv4.ip_forward = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  sysctl -p >/dev/null 2>&1 || true
fi
timedatectl set-timezone Asia/Jakarta 2>/dev/null || true

# ---- file dari repo ----
y "== ambil file aplikasi =="
for f in env docker-compose.yml nginx.conf vps.conf xray.conf xray_config.json profile cekservice.sh; do
  curl -fsSL "$R/files/$f" -o "/tmp/maylin-$f" || die "gagal ambil $f"
done
install -m644 "/tmp/maylin-env" "$D/.env"
install -m644 "/tmp/maylin-docker-compose.yml" "$D/docker-compose.yml"
install -m644 "/tmp/maylin-nginx.conf" "$D/nginx.conf"
install -m644 "/tmp/maylin-vps.conf" "$D/default.conf"
install -m644 "/tmp/maylin-xray.conf" "$D/xray.conf"
install -m644 "/tmp/maylin-xray_config.json" /var/lib/marzban/xray_config.json
mkdir -p /var/lib/marzban/templates/subscription
curl -fsSL "https://raw.githubusercontent.com/GawrAme/MarLing/main/index.html" -o /var/lib/marzban/templates/subscription/index.html || y "template subs gagal (opsional)"
install -m755 "/tmp/maylin-profile" /usr/bin/profile
install -m755 "/tmp/maylin-cekservice.sh" /usr/bin/cekservice
grep -q "/usr/bin/profile" /root/.profile || echo "[ -x /usr/bin/profile ] && /usr/bin/profile" >>/root/.profile
echo "<pre>Setup by Maylin</pre>" >/var/www/html/index.html

# ---- DB kosong (tanpa db bawaan orang) ----
[ -s /var/lib/marzban/db.sqlite3 ] || : >/var/lib/marzban/db.sqlite3

# ---- sertifikat (sebelum nginx pakai port 80) ----
y "== admin & sertifikat =="
command -v socat >/dev/null || apt-get install -y socat >/dev/null 2>&1 || true
curl -fsSL https://get.acme.sh -o /tmp/acme_install.sh 2>/dev/null || true
if [ -s /tmp/acme_install.sh ]; then
  sh /tmp/acme_install.sh -s email="$email" --force >/dev/null 2>&1 || true
fi
ACME="$HOME/.acme.sh/acme.sh"
if [ ! -x "$ACME" ] && [ -s /tmp/acme_install.sh ]; then
  sh /tmp/acme_install.sh -s email="$email" --force --nocron >/dev/null 2>&1 || true
fi
[ -x "$ACME" ] || die "acme.sh gagal dipasang"
"$ACME" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
"$ACME" --register-account -m "$email" >/dev/null 2>&1 || true
"$ACME" --issue -d "$domain" --standalone -k ec-256 --force || die "issue cert gagal (cek A record & port 80 bebas)"
"$ACME" --installcert -d "$domain" \
  --fullchainpath /var/lib/marzban/xray.crt --keypath /var/lib/marzban/xray.key --ecc || die "install cert gagal"
[ -s /var/lib/marzban/xray.crt ] && [ -s /var/lib/marzban/xray.key ] || die "cert tidak ada"

# ---- admin via env, boot ----
sed -i "s/# SUDO_USERNAME = \"admin\"/SUDO_USERNAME = \"$userpanel\"/" "$D/.env"
sed -i "s/# SUDO_PASSWORD = \"admin\"/SUDO_PASSWORD = \"$passpanel\"/" "$D/.env"
(cd "$D" && docker compose up -d) || die "docker compose gagal"
sleep 25

docker exec marzban-marzban-1 marzban cli admin import-from-env -y 2>/dev/null || \
  (cd "$D" && docker compose exec -T marzban marzban cli admin import-from-env -y) || y "import admin manual perlu"
sed -i "s/SUDO_USERNAME = \"$userpanel\"/# SUDO_USERNAME = \"admin\"/" "$D/.env"
sed -i "s/SUDO_PASSWORD = \"$passpanel\"/# SUDO_PASSWORD = \"admin\"/" "$D/.env"
(cd "$D" && docker compose down && docker compose up -d)

# ---- ufw (tambah saja, jangan reset agar rule lain tetap) ----
y "== firewall =="
ufw default deny incoming >/dev/null 2>&1 || true
ufw default allow outgoing >/dev/null 2>&1 || true
for rule in "ssh" "http" "https" "8081/tcp" "1080/tcp" "1080/udp"; do
  ufw allow "$rule" >/dev/null 2>&1 || true
done
ufw --force enable >/dev/null 2>&1 || true

# ---- token & info ----
y "== selesai, generate token =="
sleep 30
curl -s -X POST "https://$domain/api/admin/token" -H 'accept: application/json' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "grant_type=password&username=$userpanel&password=$passpanel" >"$DATA/token.json" || true
cat >/root/log-install.txt <<EOF
URL    : https://$domain/dashboard
user   : $userpanel
pass   : $passpanel
EOF
apt-get autoremove -y >/dev/null 2>&1 || true
r "SELESAI. Login: https://$domain/dashboard"
read -rp "Reboot sekarang? [Y/n] " a
[[ "$a" =~ ^[Nn] ]] || reboot
