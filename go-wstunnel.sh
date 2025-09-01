#!/bin/bash

SERVICE="goproxy"
BINARY="/usr/local/bin/goproxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE}.service"
SRC_DIR="/tmp/goproxy_build"

detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)   echo "amd64" ;;
        aarch64)  echo "arm64" ;;
        armv7l)   echo "arm"   ;;
        *)        echo "unsupported" ;;
    esac
}

install_proxy() {
    echo "[*] Instalando Go Proxy..."

    # Verificar si Go está instalado
    if ! command -v go &> /dev/null; then
        echo "[✘] Go no está instalado. Instálalo primero."
        exit 1
    fi

    mkdir -p "$SRC_DIR"
    cat > "$SRC_DIR/goproxy.go" <<'EOF'
package main

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"strings"
	"time"
)

const (
    LISTEN_ADDR = "0.0.0.0"
    LISTEN_PORT = 80
    DEFAULT_HOST = "127.0.0.1"
    DEFAULT_PORT = 22
	PASS         = ""
	RESPONSE     = "HTTP/1.1 101 <b><font color=\"green\"> CulturaVPN THOMAS </font></b>\r\nContent-Length: 104857600000\r\n\r\n"
	TIMEOUT      = 60 * time.Second
)

func handleConnection(client net.Conn) {
	defer client.Close()
	client.SetDeadline(time.Now().Add(TIMEOUT))

	reader := bufio.NewReader(client)
	var headers []string

	// leer cabeceras
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			return
		}
		if line == "\r\n" {
			break
		}
		headers = append(headers, line)
	}

	// extraer headers personalizados
	hostPort := ""
	pass := ""
	split := ""

	for _, h := range headers {
		l := strings.ToLower(h)
		if strings.HasPrefix(l, "x-real-host:") {
			hostPort = strings.TrimSpace(strings.SplitN(h, ":", 2)[1])
		}
		if strings.HasPrefix(l, "x-pass:") {
			pass = strings.TrimSpace(strings.SplitN(h, ":", 2)[1])
		}
		if strings.HasPrefix(l, "x-split:") {
			split = "1"
		}
	}

	if hostPort == "" {
		hostPort = fmt.Sprintf("%s:%d", DEFAULT_HOST, DEFAULT_PORT)
	}
	if !strings.Contains(hostPort, ":") {
		hostPort = fmt.Sprintf("%s:%d", hostPort, DEFAULT_PORT)
	}

	// si hay X-Split -> leer y descartar bloque extra
	if split != "" {
		_, _ = reader.Discard(4096)
	}

	// validar pass
	if PASS != "" && pass != PASS {
		client.Write([]byte("HTTP/1.1 400 WrongPass!\r\n\r\n"))
		return
	}

	// restricciones de host (como en Python: solo localhost si no hay PASS)
	if PASS == "" && !(strings.HasPrefix(hostPort, "127.0.0.1") || strings.HasPrefix(hostPort, "localhost")) {
		client.Write([]byte("HTTP/1.1 403 Forbidden!\r\n\r\n"))
		return
	}

	// conectar a destino
	target, err := net.DialTimeout("tcp", hostPort, TIMEOUT)
	if err != nil {
		client.Write([]byte("HTTP/1.1 502 BadGateway\r\n\r\n"))
		return
	}
	defer target.Close()
	target.SetDeadline(time.Now().Add(TIMEOUT))

	// enviar respuesta inicial
	client.Write([]byte(RESPONSE))

	// iniciar forward bidireccional
	errc := make(chan error, 2)
	go func() { _, err := io.Copy(target, reader); errc <- err }()
	go func() { _, err := io.Copy(client, target); errc <- err }()
	<-errc
}

func main() {
	listenAddr := fmt.Sprintf("%s:%d", LISTEN_ADDR, LISTEN_PORT)
	ln, err := net.Listen("tcp", listenAddr)
	if err != nil {
		panic(err)
	}
	fmt.Println("Listening on", listenAddr)

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handleConnection(conn)
	}
}
EOF

    ARCH=$(detect_arch)
    if [[ "$ARCH" == "unsupported" ]]; then
        echo "[✘] Arquitectura no soportada: $(uname -m)"
        exit 1
    fi

    echo "[*] Compilando binario para $ARCH..."
    cd "$SRC_DIR" || exit 1
    GOARCH=$ARCH go build -o "$BINARY" goproxy.go

    if [ $? -ne 0 ]; then
        echo "[✘] Error al compilar el binario"
        exit 1
    fi

    chmod +x "$BINARY"

    echo "[*] Creando servicio systemd..."
    sleep 2
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Go WS-Tunnel Port80
After=network.target

[Service]
ExecStart=$BINARY
Restart=always
RestartSec=3
User=root
NoNewPrivileges=true
LimitNOFILE=65535

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    echo "[*] Recargando systemd..."
    systemctl daemon-reload
    systemctl enable "$SERVICE"
    systemctl restart "$SERVICE"

    clear
    echo "[✔] Instalación completada. Estado del servicio:"
    sleep 3
    systemctl status "$SERVICE" --no-pager -l
}

# Llamar a la función principal
install_proxy
