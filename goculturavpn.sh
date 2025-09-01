#!/bin/bash
# ===============================
#   CulturaVPN Manager GoProxy
#   Autor: @thomasculturavpn
#   Repo: github.com/nube50/goculturavpn
# ===============================

CONFIG_DIR="/etc/culturavpn"
CONFIG_FILE="$CONFIG_DIR/goproxy.env"
SERVICE_FILE="/etc/systemd/system/goproxy.service"

# Crear directorio y archivo de configuración si no existen
mkdir -p $CONFIG_DIR
if [ ! -f "$CONFIG_FILE" ]; then
    cat <<EOF > "$CONFIG_FILE"
# Configuración de GoProxy
LISTEN_PORT=80
REDIRECT_PORT=443
BANNER="Bienvenido a CulturaVPN"
EOF
fi

# Cargar configuración
source "$CONFIG_FILE"

# ===============================
# Funciones
# ===============================

instalar_goproxy() {
    echo "📥 Instalando GoProxy..."
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        URL="https://github.com/snail007/goproxy/releases/latest/download/proxy-linux-amd64.tar.gz"
    elif [[ "$ARCH" == "aarch64" ]]; then
        URL="https://github.com/snail007/goproxy/releases/latest/download/proxy-linux-arm64.tar.gz"
    else
        echo "❌ Arquitectura no soportada: $ARCH"
        exit 1
    fi

    curl -L "$URL" -o /tmp/proxy.tar.gz
    tar -xzf /tmp/proxy.tar.gz -C /tmp || { echo "❌ Error al extraer"; exit 1; }
    mv /tmp/proxy /usr/local/bin/proxy
    chmod +x /usr/local/bin/proxy

    echo "✅ GoProxy instalado: $(/usr/local/bin/proxy --version 2>/dev/null)"
    read -p "⏎ Enter para volver al menú..."
}

configurar_puertos() {
    read -p "🔌 Puerto de escucha WS (actual: $LISTEN_PORT): " NEW_LISTEN
    read -p "↪️ Puerto de redirección TCP (actual: $REDIRECT_PORT): " NEW_REDIRECT

    LISTEN_PORT=${NEW_LISTEN:-$LISTEN_PORT}
    REDIRECT_PORT=${NEW_REDIRECT:-$REDIRECT_PORT}

    cat <<EOF > "$CONFIG_FILE"
LISTEN_PORT=$LISTEN_PORT
REDIRECT_PORT=$REDIRECT_PORT
BANNER="$BANNER"
EOF

    echo "✅ Configuración actualizada."
    read -p "⏎ Enter para volver al menú..."
}

configurar_banner() {
    read -p "📝 Nuevo banner (actual: $BANNER): " NEW_BANNER
    BANNER=${NEW_BANNER:-$BANNER}

    cat <<EOF > "$CONFIG_FILE"
LISTEN_PORT=$LISTEN_PORT
REDIRECT_PORT=$REDIRECT_PORT
BANNER="$BANNER"
EOF

    echo "✅ Banner actualizado."
    read -p "⏎ Enter para volver al menú..."
}

iniciar_servicio() {
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=GoProxy WebSocket Tunnel con Banner
After=network.target

[Service]
ExecStart=/usr/local/bin/proxy ws -p :$LISTEN_PORT -T tcp://127.0.0.1:$REDIRECT_PORT --wstls --wsskipverify --wsbanner "$BANNER"
Restart=always
EnvironmentFile=$CONFIG_FILE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reexec
    systemctl enable --now goproxy
    echo "🚀 GoProxy iniciado en puerto $LISTEN_PORT → $REDIRECT_PORT"
    read -p "⏎ Enter para volver al menú..."
}

# ===============================
# Menú principal
# ===============================

while true; do
    clear
    echo "==============================="
    echo " CulturaVPN MÁNAGER GO PROXY"
    echo " @thomasculturavpn"
    echo "==============================="
    echo "1) Instalar/Actualizar GoProxy"
    echo "2) Configurar PUERTO de escucha (WS) y PUERTO de redirección (TCP)"
    echo "3) Configurar banner"
    echo "4) Iniciar servicio"
    echo "5) Detener servicio"
    echo "6) Reiniciar servicio"
    echo "7) Estado del servicio"
    echo "8) Ver últimos logs"
    echo "9) Seguir logs en vivo"
    echo "10) Habilitar al arranque"
    echo "11) Deshabilitar al arranque"
    echo "12) Probar HTTP 101 (handshake WS)"
    echo "13) Desinstalar TODO"
    echo "0) Salir"
    echo
    read -p "Selecciona una opción: " OPCION

    case $OPCION in
        1) instalar_goproxy ;;
        2) configurar_puertos ;;
        3) configurar_banner ;;
        4) iniciar_servicio ;;
        5) systemctl stop goproxy ;;
        6) systemctl restart goproxy ;;
        7) systemctl status goproxy ;;
        8) journalctl -u goproxy --no-pager -n 30 ;;
        9) journalctl -u goproxy -f ;;
        10) systemctl enable goproxy ;;
        11) systemctl disable goproxy ;;
        12) curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" http://127.0.0.1:$LISTEN_PORT/ ;;
        13) systemctl stop goproxy; systemctl disable goproxy; rm -f $SERVICE_FILE; rm -rf $CONFIG_DIR; rm -f /usr/local/bin/proxy; echo "❌ GoProxy eliminado." ;;
        0) exit ;;
        *) echo "❌ Opción inválida" ;;
    esac
    read -p "⏎ Enter para continuar..."
done
