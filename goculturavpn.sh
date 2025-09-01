#!/bin/bash
# ========================================================
# 🌐 CulturaVPN MÁNAGER GO PROXY
# by @thomasculturavpn
# ========================================================

BANNER="| CulturaVPN @thomasculturavpn |"
SERVICE_FILE="/etc/systemd/system/goproxy.service"

# Detectar arquitectura automáticamente
detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)   FILE="proxy-linux-amd64" ;;
        aarch64)  FILE="proxy-linux-arm64" ;;
        armv7l)   FILE="proxy-linux-arm" ;;
        *) echo "❌ Arquitectura no soportada: $ARCH"; exit 1 ;;
    esac
    echo "$FILE"
}

install_goproxy() {
    echo "🚀 Instalando dependencias..."
    apt update -y
    apt install -y curl

    FILE=$(detect_arch)
    URL="https://github.com/snail007/goproxy/releases/latest/download/$FILE"

    echo "📥 Descargando GoProxy desde: $URL"
    curl -L "$URL" -o /usr/local/bin/proxy

    chmod +x /usr/local/bin/proxy

    echo "✅ GoProxy instalado correctamente."
    /usr/local/bin/proxy -v || echo "⚠️ No se pudo comprobar la versión."
}

configure_service() {
    read -p "👉 Puerto de escucha (WS) [default 80]: " PORT_LISTEN
    PORT_LISTEN=${PORT_LISTEN:-80}
    read -p "👉 Puerto de redirección (TCP) [default 22]: " PORT_TARGET
    PORT_TARGET=${PORT_TARGET:-22}

    cat > $SERVICE_FILE <<EOF
[Unit]
Description=GoProxy WebSocket Tunnel con Banner
After=network.target

[Service]
ExecStart=/usr/local/bin/proxy ws -p :$PORT_LISTEN -T tcp -P 127.0.0.1:$PORT_TARGET -H "X-Banner: $BANNER"
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable goproxy
    systemctl restart goproxy

    echo "✅ Servicio configurado y ejecutándose en puerto $PORT_LISTEN → $PORT_TARGET"
    systemctl status goproxy --no-pager
}

uninstall_goproxy() {
    systemctl stop goproxy
    systemctl disable goproxy
    rm -f $SERVICE_FILE
    rm -f /usr/local/bin/proxy
    systemctl daemon-reload
    echo "✅ GoProxy desinstalado completamente."
}

menu() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║   🌐 CulturaVPN MÁNAGER GO PROXY       ║"
    echo "║        by @thomasculturavpn            ║"
    echo "╚════════════════════════════════════════╝"
    echo
    echo "1) Instalar GoProxy"
    echo "2) Configurar y arrancar servicio"
    echo "3) Desinstalar GoProxy"
    echo "0) Salir"
    echo
    read -p "Selecciona una opción: " OPCION
    case $OPCION in
        1) install_goproxy ;;
        2) configure_service ;;
        3) uninstall_goproxy ;;
        0) exit 0 ;;
        *) echo "❌ Opción inválida" ;;
    esac
}

menu
