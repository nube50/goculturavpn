#!/bin/bash
# ==========================================
#   CulturaVPN Manager - GoProxy
#   Autor: @thomasculturavpn
# ==========================================

CONFIG_DIR="/etc/culturavpn"
ENV_FILE="$CONFIG_DIR/goproxy.env"
SERVICE_FILE="/etc/systemd/system/goproxy.service"

mkdir -p "$CONFIG_DIR"

# Función para instalar/actualizar GoProxy
instalar_goproxy() {
    echo "📥 Instalando/Actualizando GoProxy..."

    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64|arm64)
            URL="https://github.com/snail007/goproxy/releases/download/v11.6/proxy-linux-arm64.tar.gz"
            ;;
        x86_64|amd64)
            URL="https://github.com/snail007/goproxy/releases/download/v11.6/proxy-linux-amd64.tar.gz"
            ;;
        *)
            echo "❌ Arquitectura no soportada: $ARCH"
            return
            ;;
    esac

    curl -L "$URL" -o /tmp/proxy.tar.gz || { echo "❌ Error en descarga"; return; }

    tar -xvzf /tmp/proxy.tar.gz -C /tmp || { echo "❌ Error al extraer"; return; }

    mv /tmp/proxy /usr/local/bin/proxy
    chmod +x /usr/local/bin/proxy
    VERSION=$(/usr/local/bin/proxy --version 2>/dev/null | head -n1)

    echo "✅ GoProxy instalado: $VERSION"
    read -p "⏎ Enter para volver al menú..."
}

# Configurar puertos
configurar_puertos() {
    echo "⚙️ Configurar puertos"
    read -p "Puerto de escucha (WS): " WS_PORT
    read -p "Puerto de redirección (TCP): " TCP_PORT
    cat > "$ENV_FILE" <<EOF
WS_PORT=$WS_PORT
TCP_PORT=$TCP_PORT
BANNER="Bienvenido a CulturaVPN"
EOF
    echo "✅ Guardado en $ENV_FILE"
    read -p "⏎ Enter para volver al menú..."
}

# Configurar banner
configurar_banner() {
    echo "⚙️ Configurar banner"
    read -p "Nuevo banner: " BANNER
    if [ -f "$ENV_FILE" ]; then
        sed -i "s|^BANNER=.*|BANNER=\"$BANNER\"|" "$ENV_FILE"
    else
        echo "BANNER=\"$BANNER\"" > "$ENV_FILE"
    fi
    echo "✅ Banner actualizado"
    read -p "⏎ Enter para volver al menú..."
}

# Crear servicio systemd
crear_servicio() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "❌ Configura primero los puertos con opción 2"
        return
    fi
    source "$ENV_FILE"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=GoProxy WebSocket Tunnel con Banner
After=network.target

[Service]
ExecStart=/usr/local/bin/proxy ws -p :$WS_PORT -T tcp -P 127.0.0.1:$TCP_PORT --ttl 7200 --banner "\$BANNER"
Restart=always
EnvironmentFile=$ENV_FILE

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

iniciar_servicio() { crear_servicio; systemctl start goproxy; echo "✅ Servicio iniciado"; read -p "⏎"; }
detener_servicio() { systemctl stop goproxy; echo "🛑 Servicio detenido"; read -p "⏎"; }
reiniciar_servicio() { systemctl restart goproxy; echo "🔄 Servicio reiniciado"; read -p "⏎"; }
estado_servicio() { systemctl status goproxy --no-pager; read -p "⏎"; }
logs_servicio() { journalctl -u goproxy -n 20 --no-pager; read -p "⏎"; }
logs_vivo() { journalctl -u goproxy -f; }
habilitar_arranque() { systemctl enable goproxy; echo "✅ Servicio habilitado al arranque"; read -p "⏎"; }
deshabilitar_arranque() { systemctl disable goproxy; echo "🛑 Servicio deshabilitado al arranque"; read -p "⏎"; }
probar_http() { curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Host: localhost" -H "Origin: http://localhost" http://127.0.0.1:$(grep WS_PORT $ENV_FILE | cut -d= -f2) || echo "❌ Falló prueba"; read -p "⏎"; }
desinstalar_todo() {
    systemctl stop goproxy 2>/dev/null
    systemctl disable goproxy 2>/dev/null
    rm -f /usr/local/bin/proxy $SERVICE_FILE $ENV_FILE
    systemctl daemon-reload
    echo "🗑 GoProxy eliminado"
    read -p "⏎"
}

# Menú principal
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
    echo ""
    read -p "Selecciona una opción: " opcion
    case $opcion in
        1) instalar_goproxy ;;
        2) configurar_puertos ;;
        3) configurar_banner ;;
        4) iniciar_servicio ;;
        5) detener_servicio ;;
        6) reiniciar_servicio ;;
        7) estado_servicio ;;
        8) logs_servicio ;;
        9) logs_vivo ;;
        10) habilitar_arranque ;;
        11) deshabilitar_arranque ;;
        12) probar_http ;;
        13) desinstalar_todo ;;
        0) exit 0 ;;
        *) echo "❌ Opción inválida"; sleep 1 ;;
    esac
done
