#!/bin/bash
set -e

echo "🔍 Detectando arquitectura..."
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)   GOARCH="amd64" ;;
    aarch64)  GOARCH="arm64" ;;
    *) echo "❌ Arquitectura $ARCH no soportada"; exit 1 ;;
esac

echo "📥 Descargando GoProxy para $GOARCH..."
URL="https://github.com/snail007/goproxy/releases/download/v10.7/proxy-linux-$GOARCH.tar.gz"

rm -f /tmp/proxy.tar.gz
curl -L -o /tmp/proxy.tar.gz "$URL"

echo "🗜 Verificando archivo..."
file /tmp/proxy.tar.gz | grep -q 'gzip compressed data' || { echo "❌ Descarga fallida"; exit 1; }

echo "📦 Extrayendo..."
tar -xvzf /tmp/proxy.tar.gz -C /tmp

echo "🚀 Instalando en /usr/local/bin..."
mv /tmp/proxy /usr/local/bin/proxy
chmod +x /usr/local/bin/proxy

echo "✅ Verificando instalación..."
/usr/local/bin/proxy -v || { echo "❌ Instalación fallida"; exit 1; }

# ---- Alias permanente ----
if ! grep -q "alias goculturavpn=" ~/.bashrc; then
    echo "alias goculturavpn='/usr/local/bin/proxy'" >> ~/.bashrc
    echo "✅ Alias permanente 'goculturavpn' añadido"
else
    echo "ℹ️ Alias 'goculturavpn' ya existe"
fi

# ---- Servicio systemd ----
SERVICE_FILE="/etc/systemd/system/goproxy.service"
if [ ! -f "$SERVICE_FILE" ]; then
cat <<EOF > $SERVICE_FILE
[Unit]
Description=GoProxy WebSocket Tunnel con Banner
After=network.target

[Service]
ExecStart=/usr/local/bin/proxy ws -p :80 -T tcp -C "🚀 Bienvenido a CulturaVPN"
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable goproxy
    echo "✅ Servicio systemd creado: goproxy"
else
    echo "ℹ️ Servicio systemd ya existe"
fi

echo "🎉 Instalación completa."
echo "👉 Usa 'systemctl start goproxy' para iniciar"
echo "👉 Usa 'systemctl status goproxy' para ver el estado"
echo "👉 O ejecuta 'goculturavpn' manualmente"
