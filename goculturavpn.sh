#!/usr/bin/env bash
# CulturaVPN MÁNAGER GO PROXY
# Autor: @thomasculturavpn
# Modo: menú interactivo para instalar/gestionar GoProxy (ws->tcp)
set -euo pipefail

TITLE="CulturaVPN MÁNAGER GO PROXY"
HANDLE="@thomasculturavpn"
UNIT_NAME="goproxy.service"
BIN_PATH="/usr/local/bin/proxy"
CONF_DIR="/etc/culturavpn"
ENV_FILE="$CONF_DIR/goproxy.env"
BANNER_DEFAULT='<font color="#0CB7F2">| CulturaVPN @thomasculturavpn  |</font>'

# ---------- util ----------
say() { echo -e "$1"; }
require_root() { [ "$(id -u)" -eq 0 ] || { say "❌ Ejecuta como root."; exit 1; }; }

detect_arch() {
  local u
  u="$(uname -m)"
  case "$u" in
    x86_64|amd64)   echo "amd64" ;;
    aarch64|arm64)  echo "arm64" ;;
    armv7l|armv7|armhf) echo "armv7" ;;
    armv6l|armel)   echo "armv6" ;;
    i386|i686)      echo "386" ;;
    *) say "❌ Arquitectura no soportada: $u"; exit 1 ;;
  esac
}

ensure_deps() {
  say "🚀 Instalando dependencias..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y -qq
  apt-get install -y -qq curl jq tar ca-certificates coreutils procps
}

# ---------- descarga/instalación ----------
install_goproxy() {
  require_root; ensure_deps
  mkdir -p "$CONF_DIR"

  local ARCH TAG API ASSET_URL ALT_URL TMP_TGZ
  ARCH="$(detect_arch)"
  API="https://api.github.com/repos/snail007/goproxy/releases/latest"
  TMP_TGZ="/tmp/proxy.tar.gz"

  say "📥 Consultando última versión en GitHub (arch: $ARCH)..."
  TAG="$(curl -fsSL "$API" | jq -r '.tag_name')"
  if [[ -z "${TAG:-}" || "$TAG" == "null" ]]; then
    say "❌ No se pudo obtener la versión desde GitHub API."; exit 1
  fi

  # Busca el asset oficial *.tar.gz para Linux + arch
  ASSET_URL="$(curl -fsSL "$API" | jq -r --arg a "$ARCH" '.assets[].browser_download_url | select(test("proxy-linux-" + $a + ".*tar.gz$"))' | head -n1)"
  # Fallback a URL construida por tag si la API no trajo assets (raro)
  ALT_URL="https://github.com/snail007/goproxy/releases/download/${TAG}/proxy-linux-${ARCH}.tar.gz"
  if [[ -z "$ASSET_URL" ]]; then
    ASSET_URL="$ALT_URL"
  fi

  say "📥 Descargando GoProxy..."
  rm -f "$TMP_TGZ"
  if ! curl -fL --connect-timeout 20 --retry 3 -o "$TMP_TGZ" "$ASSET_URL"; then
    say "❌ Descarga fallida desde: $ASSET_URL"; exit 1
  fi

  # Validaciones: tamaño y formato
  local BYTES
  BYTES="$(wc -c < "$TMP_TGZ" || echo 0)"
  if [[ "$BYTES" -lt 200000 ]]; then
    say "❌ Archivo sospechosamente pequeño ($BYTES bytes). Posible HTML/404. URL: $ASSET_URL"
    exit 1
  fi
  if ! tar -tzf "$TMP_TGZ" >/dev/null 2>&1; then
    say "❌ El archivo no es un .tar.gz válido."
    exit 1
  fi

  say "🗜 Extrayendo..."
  tar -xzf "$TMP_TGZ" -C /tmp
  if [[ ! -f /tmp/proxy ]]; then
    say "❌ No se encontró el binario 'proxy' dentro del tar."
    exit 1
  fi

  say "📦 Instalando en $BIN_PATH ..."
  mv /tmp/proxy "$BIN_PATH"
  chmod +x "$BIN_PATH"

  # Comprobación del binario
  if ! file "$BIN_PATH" | grep -qi 'ELF'; then
    say "⚠️ Binario en $BIN_PATH no parece ejecutable ELF. Abortando."
    exit 1
  fi

  say "✅ GoProxy instalado: $("$BIN_PATH" -v 2>/dev/null || true)"
  init_env_if_missing
  create_or_update_service
  systemctl daemon-reload
  systemctl enable "$UNIT_NAME" >/dev/null 2>&1 || true
}

init_env_if_missing() {
  mkdir -p "$CONF_DIR"
  if [[ ! -f "$ENV_FILE" ]]; then
    cat > "$ENV_FILE" <<EOF
LISTEN_PORT=80
TARGET_PORT=22
BANNER=${BANNER_DEFAULT}
EOF
    chmod 600 "$ENV_FILE"
  fi
}

create_or_update_service() {
  # Usamos /bin/bash -lc para preservar comillas del banner
  cat > "/etc/systemd/system/${UNIT_NAME}" <<'EOF'
[Unit]
Description=GoProxy WebSocket Tunnel con Banner
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/culturavpn/goproxy.env
ExecStart=/bin/bash -lc '/usr/local/bin/proxy ws -p :${LISTEN_PORT} -T tcp -P 127.0.0.1:${TARGET_PORT} -b "${BANNER}"'
Restart=on-failure
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
}

# ---------- configuración puertos y banner ----------
config_ports() {
  require_root; init_env_if_missing
  source "$ENV_FILE"
  say "⚙️  Puerto actual de escucha (WS): $LISTEN_PORT"
  say "⚙️  Puerto actual de redirección (TCP destino): $TARGET_PORT"
  read -rp "Nuevo puerto WS (Enter para mantener $LISTEN_PORT): " L
  read -rp "Nuevo puerto destino TCP (Enter para mantener $TARGET_PORT): " T
  if [[ -n "${L:-}" ]]; then LISTEN_PORT="$L"; fi
  if [[ -n "${T:-}" ]]; then TARGET_PORT="$T"; fi
  sed -i "s/^LISTEN_PORT=.*/LISTEN_PORT=${LISTEN_PORT}/" "$ENV_FILE"
  sed -i "s/^TARGET_PORT=.*/TARGET_PORT=${TARGET_PORT}/" "$ENV_FILE"
  say "✅ Puertos guardados. Reiniciando servicio..."
  systemctl daemon-reload
  systemctl restart "$UNIT_NAME" || true
  systemctl --no-pager -l status "$UNIT_NAME" || true
}

config_banner() {
  require_root; init_env_if_missing
  source "$ENV_FILE"
  say "🪧 Banner actual:"
  echo "$BANNER"
  echo
  read -rp "¿Usar el banner por defecto de CulturaVPN? (S/n): " yn
  yn=${yn:-S}
  if [[ "$yn" =~ ^[sS]$ ]]; then
    BANNER="$BANNER_DEFAULT"
  else
    echo "Escribe el nuevo banner en UNA línea (se permiten etiquetas HTML):"
    read -r BANNER
  fi
  # Escapar barras y ampersands para sed
  local SAFE
  SAFE="$(printf '%s\n' "$BANNER" | sed -e 's/[\/&]/\\&/g')"
  sed -i "s/^BANNER=.*/BANNER=${SAFE}/" "$ENV_FILE"
  say "✅ Banner actualizado. Reiniciando..."
  systemctl restart "$UNIT_NAME" || true
}

# ---------- gestión servicio ----------
start_service()   { systemctl start "$UNIT_NAME";   systemctl --no-pager -l status "$UNIT_NAME" || true; }
stop_service()    { systemctl stop "$UNIT_NAME" || true; say "🛑 Servicio detenido."; }
restart_service() { systemctl restart "$UNIT_NAME" || true; systemctl --no-pager -l status "$UNIT_NAME" || true; }
status_service()  { systemctl --no-pager -l status "$UNIT_NAME" || true; }
logs_service()    { journalctl -u "$UNIT_NAME" -e --no-pager -n 100; }
follow_logs()     { journalctl -u "$UNIT_NAME" -f; }
enable_boot()     { systemctl enable "$UNIT_NAME"; say "✅ Habilitado al arranque."; }
disable_boot()    { systemctl disable "$UNIT_NAME"; say "✅ Deshabilitado al arranque."; }

test_101() {
  source "$ENV_FILE" 2>/dev/null || true
  local P="${LISTEN_PORT:-80}"
  say "🔎 Probando handshake WebSocket contra http://127.0.0.1:${P} ..."
  # Enviamos cabeceras de Upgrade para esperar un 101 Switching Protocols
  local RES
  RES="$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Upgrade: websocket" \
    -H "Connection: Upgrade" \
    -H "Sec-WebSocket-Version: 13" \
    -H "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" \
    "http://127.0.0.1:${P}/")" || true
  if [[ "$RES" == "101" ]]; then
    say "✅ Recibido 101 Switching Protocols."
  else
    say "⚠️ Respuesta HTTP: $RES (esperado 101). Revisa 'goculturavpn -> Ver logs'."
  fi
}

uninstall_all() {
  require_root
  systemctl stop "$UNIT_NAME" 2>/dev/null || true
  systemctl disable "$UNIT_NAME" 2>/dev/null || true
  rm -f "/etc/systemd/system/${UNIT_NAME}"
  systemctl daemon-reload
  rm -f "$BIN_PATH"
  rm -rf "$CONF_DIR"
  sed -i '/alias goculturavpn=/d' /root/.bashrc 2>/dev/null || true
  sed -i '/alias goculturavpn=/d' /etc/skel/.bashrc 2>/dev/null || true
  say "🧹 Desinstalado GoProxy y configuración de CulturaVPN."
}

ensure_alias() {
  # Alias permanente
  if ! grep -q 'alias goculturavpn=' /root/.bashrc 2>/dev/null; then
    echo "alias goculturavpn='bash $PWD/$(basename "$0")'" >> /root/.bashrc
  fi
}

# ---------- menú ----------
menu() {
  clear
  say "==============================="
  say " $TITLE"
  say " $HANDLE"
  say "==============================="
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
  read -rp "Selecciona una opción: " op
  case "${op:-}" in
    1) install_goproxy ;;
    2) config_ports ;;
    3) config_banner ;;
    4) start_service ;;
    5) stop_service ;;
    6) restart_service ;;
    7) status_service ;;
    8) logs_service ;;
    9) follow_logs ;;
    10) enable_boot ;;
    11) disable_boot ;;
    12) test_101 ;;
    13) uninstall_all ;;
    0) exit 0 ;;
    *) say "Opción inválida." ;;
  esac
  read -rp "⏎ Enter para volver al menú..." _dummy
  menu
}

# ---------- arranque ----------
require_root
ensure_alias
menu
