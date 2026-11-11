#!/usr/bin/env bash
# Programa vigia.sh una vez por semana (lunes 9:00) con un timer de systemd de USUARIO (sin sudo).
# Si la compu estaba apagada, corre al encenderla (Persistent=true). Quitar: bash instalar-vigia.sh --quitar
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
U="$HOME/.config/systemd/user"
if [ "${1:-}" = "--quitar" ]; then
  systemctl --user disable --now security-suite-vigia.timer 2>/dev/null || true
  rm -f "$U/security-suite-vigia."{service,timer}; systemctl --user daemon-reload; echo "Vigía quitado"; exit 0
fi
command -v systemctl >/dev/null || { echo "Sin systemd (¿macOS?): usa cron → 0 9 * * 1 bash $DIR/vigia.sh" >&2; exit 1; }
mkdir -p "$U"
cat > "$U/security-suite-vigia.service" <<EOF
[Unit]
Description=Security Suite: vigía semanal de mis sitios
After=network-online.target

[Service]
Type=oneshot
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/bin/env bash $DIR/vigia.sh
EOF
cat > "$U/security-suite-vigia.timer" <<'EOF'
[Unit]
Description=Security Suite: vigía semanal

[Timer]
OnCalendar=Mon *-*-* 09:00:00
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now security-suite-vigia.timer
systemctl --user list-timers security-suite-vigia.timer --no-pager | head -3
