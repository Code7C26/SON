#!/bin/bash
# Prepara un servidor Ubuntu 24.04 NUEVO para SON. Es lo mismo que hace cloud-init.yaml, para
# proveedores que no tienen la opción "Cloud config / User data" (o si te la saltaste).
#
# Desde tu PC (PowerShell):
#   scp .\preparar-servidor.sh root@LA.IP:/root/
#   ssh root@LA.IP "bash /root/preparar-servidor.sh"
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y upgrade
apt-get -y install docker.io docker-compose-v2 ufw fail2ban unattended-upgrades

systemctl enable --now docker
systemctl enable --now fail2ban

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

mkdir -p /opt/son/datos
cat > /etc/cron.d/son-backup <<'CRON'
# Copia de seguridad de SON todos los días a las 3 de la madrugada
0 3 * * * root [ -x /opt/son/backup.sh ] && /opt/son/backup.sh >> /var/log/son-backup.log 2>&1
CRON
chmod 644 /etc/cron.d/son-backup

touch /var/lib/son-listo
echo "Servidor listo. Ya podés correr publicar.ps1 desde tu PC."
