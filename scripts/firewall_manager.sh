#!/usr/bin/env bash
# fwctl.sh - Gestor sencillo y seguro de firewalld para Fedora Server 42
# Interfaz TUI (nmtui) y CLI

set -euo pipefail
IFS=$'\n\t'

### ====== CONFIG ======
LOGFILE="/var/log/fwctl.log"
YES=0
SCOPE_RUNTIME=0
SCOPE_PERMANENT=0
ZONE_DEFAULT="$(firewall-cmd --get-default-zone 2>/dev/null || echo public)"

if [[ $(id -u) -eq 0 ]]; then
  touch "$LOGFILE" 2>/dev/null || true
  chmod 0640 "$LOGFILE" 2>/dev/null || true
fi

### ====== UTILIDADES (Núcleo) ======
# (Estas funciones se usan tanto en CLI como en TUI)
log() {
  local ts; ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "${ts} - $*" | tee -a "$LOGFILE"
}

# err() es SÓLO para modo CLI. TUI tiene sus propios mensajes.
err() { echo "Error: $*" >&2; exit 1; }
warn() { echo "Aviso: $*" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "se necesita root. Ejecuta con sudo.";
  fi
}

require_fw() {
  command -v firewall-cmd >/dev/null 2>&1 || err "firewall-cmd no encontrado. Instala firewalld."
  systemctl is-active --quiet firewalld || err "firewalld no está activo. Ejecuta: systemctl enable --now firewalld"
}

is_valid_port() {
  local spec="$1"
  if [[ "$spec" =~ ^([0-9]{1,5})(-([0-9]{1,5}))?/(tcp|udp)$ ]]; then
    local p1="${BASH_REMATCH[1]}"
    local p2="${BASH_REMATCH[3]:-$p1}"
    (( p1>=1 && p1<=65535 && p2>=1 && p2<=65535 && p2>=p1 )) || return 1
    return 0
  fi
  return 1
}

is_valid_service() {
  local svc="$1"
  firewall-cmd --get-services | tr ' ' '\n' | grep -qx -- "$svc"
}

is_valid_zone() {
  local z="$1"
  firewall-cmd --get-zones | tr ' ' '\n' | grep -qx -- "$z"
}

is_valid_ip_or_cidr() {
  local ip="$1"
  if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
    IFS='/' read -r addr mask <<<"$ip"
    IFS='.' read -r a b c d <<<"$addr"
    for o in "$a" "$b" "$c" "$d"; do
      [[ "$o" =~ ^[0-9]+$ ]] || return 1
      (( o>=0 && o<=255 )) || return 1
    done
    if [[ -n "${mask:-}" ]]; then
      [[ "$mask" =~ ^[0-9]+$ ]] || return 1
      (( mask>=0 && mask<=32 )) || return 1
    fi
    return 0
  fi
  if [[ "$ip" =~ ^[0-9a-fA-F:]+(/[0-9]{1,3})?$ ]]; then
    return 0
  fi
  return 1
}

apply_cmd() {
  local zone="$1"; shift
  local args=("$@")
  local output=""
  local err_code=0

  if [[ $SCOPE_PERMANENT -eq 1 ]]; then
    log "APPLY PERMANENT: firewall-cmd ${args[*]} --zone=$zone --permanent"
    # Capturamos la salida de error (2>&1)
    output=$(firewall-cmd "${args[@]}" --zone="$zone" --permanent 2>&1)
    err_code=$?
    if [ $err_code -ne 0 ]; then
        echo "Error (Permanent): $output"
        return $err_code
    fi
  fi
  
  if [[ $SCOPE_RUNTIME -eq 1 || $SCOPE_PERMANENT -eq 0 ]]; then
    log "APPLY RUNTIME: firewall-cmd ${args[*]} --zone=$zone"
    output=$(firewall-cmd "${args[@]}" --zone="$zone" 2>&1)
    err_code=$?
    if [ $err_code -ne 0 ]; then
        echo "Error (Runtime): $output"
        return $err_code
    fi
  fi
  
  # Si todo fue bien, imprimimos el éxito (o la última salida)
  echo "$output"
  return 0
}


### ====== ACCIONES (Modo CLI) ======
# (Estas funciones son para el modo CLI, ya que llaman a 'err' y salen)

# confirm() es SÓLO para modo CLI
confirm() {
  local prompt="$1"
  if [[ $YES -eq 1 ]]; then return 0; fi
  read -r -p "$prompt [y/N]: " ans
  if [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]; then
    return 0
  fi
  return 1
}

print_help() {
  cat <<'EOF'
fwctl.sh - Gestor de firewalld
USO:
  fwctl.sh [--runtime|--permanent|--both] [--yes] <accion> [args] [--zone=ZONA] [opciones]
... (el resto de tu ayuda) ...
EOF
}

action_enable_service() {
  local svc="$1"
  is_valid_service "$svc" || err "servicio inválido o desconocido: $svc"
  is_valid_zone "$ZONE" || err "zona inválida: $ZONE"
  confirm "Habilitar servicio '$svc' en zona '$ZONE'?" || return 0
  apply_cmd "$ZONE" --add-service="$svc"
  log "enable-service $svc zone=$ZONE"
}

action_disable_service() {
  local svc="$1"
  is_valid_service "$svc" || err "servicio inválido o desconocido: $svc"
  is_valid_zone "$ZONE" || err "zona inválida: $ZONE"
  confirm "Deshabilitar servicio '$svc' en zona '$ZONE'?" || return 0
  apply_cmd "$ZONE" --remove-service="$svc"
  log "disable-service $svc zone=$ZONE"
}

action_open_port() {
  local port="$1"
  is_valid_port "$port" || err "puerto inválido. Usa p.ej. 80/tcp o 5000-5010/udp"
  is_valid_zone "$ZONE" || err "zona inválida: $ZONE"
  confirm "Abrir puerto '$port' en zona '$ZONE'?" || return 0
  apply_cmd "$ZONE" --add-port="$port"
  log "open-port $port zone=$ZONE"
}

action_close_port() {
  local port="$1"
  is_valid_port "$port" || err "puerto inválido. Usa p.ej. 80/tcp o 5000-5010/udp"
  is_valid_zone "$ZONE" || err "zona inválida: $ZONE"
  confirm "Cerrar puerto '$port' en zona '$ZONE'?" || return 0
  apply_cmd "$ZONE" --remove-port="$port"
  log "close-port $port zone=$ZONE"
}

action_block() {
  local ip="$1"
  is_valid_ip_or_cidr "$ip" || err "IP/CIDR inválido: $ip"
  is_valid_zone "$ZONE" || err "zona inválida: $ZONE"
  local family="ipv4"
  [[ "$ip" == *:* ]] && family="ipv6"
  local rule="rule family=${family} source address=${ip} drop"
  confirm "Bloquear $ip en zona '$ZONE' (rich rule) ?" || return 0
  apply_cmd "$ZONE" --add-rich-rule="$rule"
  log "block $ip zone=$ZONE"
}

action_unblock() {
  local ip="$1"
  is_valid_ip_or_cidr "$ip" || err "IP/CIDR inválido: $ip"
  is_valid_zone "$ZONE" || err "zona inválida: $ZONE"
  local family="ipv4"
  [[ "$ip" == *:* ]] && family="ipv6"
  local rule="rule family=${family} source address=${ip} drop"
  confirm "Desbloquear $ip en zona '$ZONE' ?" || return 0
  apply_cmd "$ZONE" --remove-rich-rule="$rule"
  log "unblock $ip zone=$ZONE"
}

action_fwd() {
  local port="$1"; shift
  is_valid_port "$port" || err "puerto inválido. Usa p.ej. 80/tcp"
  is_valid_zone "$ZONE" || err "zona inválida: $ZONE"
  local TO_PORT="" TO_ADDR=""
  while (($#)); do
    case "$1" in
      --to-port=*) TO_PORT="${1#*=}"; shift ;;
      --to-port) TO_PORT="$2"; shift 2 ;;
      --to-addr=*) TO_ADDR="${1#*=}"; shift ;;
      --to-addr) TO_ADDR="$2"; shift 2 ;;
      *) err "opción desconocida en fwd: $1" ;;
    esac
  done
  [[ -n "$TO_PORT" && "$TO_PORT" =~ ^[0-9]{1,5}$ && $TO_PORT -ge 1 && $TO_PORT -le 65535 ]] || err "--to-port requerido y válido (1-65535)."
  if [[ -n "$TO_ADDR" ]]; then
    is_valid_ip_or_cidr "$TO_ADDR" || err "--to-addr debe ser IP válida (sin máscara)."
    [[ "$TO_ADDR" != *"/"* ]] || err "--to-addr no debe incluir máscara CIDR."
  fi
  
  local p_num="${port%/*}"
  local p_proto="${port#*/}"
  local fw_arg="port=${p_num},proto=${p_proto},to-port=${TO_PORT}"
  if [[ -n "$TO_ADDR" ]]; then
      fw_arg+=",to-addr=${TO_ADDR}"
  fi
  local args=(--add-forward-port="$fw_arg")
  
  confirm "Agregar port-forward $port -> ${TO_ADDR:+$TO_ADDR:}$TO_PORT en zona '$ZONE'?" || return 0
  apply_cmd "$ZONE" "${args[@]}"
  log "fwd $port -> ${TO_ADDR:-localhost}:$TO_PORT zone=$ZONE"
}

action_unfwd() {
  local port="$1"; shift
  is_valid_port "$port" || err "puerto inválido. Usa p.ej. 80/tcp"
  is_valid_zone "$ZONE" || err "zona inválida: $ZONE"
  local TO_PORT="" TO_ADDR=""
  while (($#)); do
    case "$1" in
      --to-port=*) TO_PORT="${1#*=}"; shift ;;
      --to-port) TO_PORT="$2"; shift 2 ;;
      --to-addr=*) TO_ADDR="${1#*=}"; shift ;;
      --to-addr) TO_ADDR="$2"; shift 2 ;;
      *) err "opción desconocida en unfwd: $1" ;;
    esac
  done
  [[ -n "$TO_PORT" && "$TO_PORT" =~ ^[0-9]{1,5}$ && $TO_PORT -ge 1 && $TO_PORT -le 65535 ]] || err "--to-port requerido y válido (1-65535)."
  if [[ -n "$TO_ADDR" ]]; then
    is_valid_ip_or_cidr "$TO_ADDR" || err "--to-addr debe ser IP válida (sin máscara)."
    [[ "$TO_ADDR" != *"/"* ]] || err "--to-addr no debe incluir máscara CIDR."
  fi

  local p_num="${port%/*}"
  local p_proto="${port#*/}"
  local fw_arg="port=${p_num},proto=${p_proto},to-port=${TO_PORT}"
  if [[ -n "$TO_ADDR" ]]; then
      fw_arg+=",to-addr=${TO_ADDR}"
  fi
  local args=(--remove-forward-port="$fw_arg")

  confirm "Quitar port-forward $port -> ${TO_ADDR:+$TO_ADDR:}$TO_PORT en zona '$ZONE'?" || return 0
  apply_cmd "$ZONE" "${args[@]}"
  log "unfwd $port -> ${TO_ADDR:-localhost}:$TO_PORT zone=$ZONE"
}

action_set_default_zone() {
  local newz="$1"
  is_valid_zone "$newz" || err "zona inválida: $newz"
  confirm "Cambiar zona por defecto a '$newz'?" || return 0
  firewall-cmd --set-default-zone="$newz"
  log "set-default-zone $newz"
}

action_iface_to_zone() {
  local iface="$1"; local newz="$2"
  is_valid_zone "$newz" || err "zona inválida: $newz"
  [[ -n "$iface" ]] || err "iface-to-zone requiere interfaz e.g. eth0"
  confirm "Asignar interfaz '$iface' a la zona '$newz'?" || return 0
  firewall-cmd --zone="$newz" --change-interface="$iface"
  log "iface-to-zone $iface -> $newz"
}

action_list_zone() {
  local z="${1:-$ZONE}"
  is_valid_zone "$z" || err "zona inválida: $z"
  firewall-cmd --zone="$z" --list-all
}

action_runtime_to_permanent() {
  confirm "Copiar configuración RUNTIME -> PERMANENT?" || return 0
  firewall-cmd --runtime-to-permanent
  log "runtime-to-permanent"
}

action_permanent_to_runtime() {
  confirm "Recargar desde PERMANENT hacia RUNTIME (complete-reload)?" || return 0
  firewall-cmd --complete-reload
  log "permanent-to-runtime"
}

action_reload() {
  confirm "Recargar firewalld (lee permanente a runtime)?" || return 0
  firewall-cmd --reload
  log "reload"
}

action_panic() {
  local state="$1"
  case "$state" in
    on)
      confirm "ACTIVAR modo pánico (bloquea TODO el tráfico)?" || return 0
      firewall-cmd --panic-on
      log "panic on"
      ;;
    off)
      confirm "DESACTIVAR modo pánico?" || return 0
      firewall-cmd --panic-off
      log "panic off"
      ;;
    *) err "uso: panic on|off" ;;
  esac
}

action_view_logs() {
  local n="${1:-50}"
  if [[ -f "$LOGFILE" ]]; then
    echo "--- Últimas $n líneas de $LOGFILE ---"
    tail -n "$n" "$LOGFILE" || true
  else
    echo "No hay logs en $LOGFILE"
  fi
}


### ====== MENU INTERACTIVO (TUI - nmtui style) ======

# Verificación de whiptail
require_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        echo "ERROR: 'whiptail' no está instalado. Es necesario para el menú."
        echo "Por favor, instálalo ejecutando: dnf install newt"
        exit 1
    fi
}

# --- Funciones TUI (helpers) ---

# Muestra un mensaje
# tui_show_message "Título" "Texto del mensaje"
tui_show_message() {
    whiptail --title "$1" --msgbox "$2" 10 78
}

# Pide confirmación (Sí/No)
# if tui_confirm "Pregunta?"; then ...
tui_confirm() {
    # Si se usó --yes, siempre confirma
    if [[ $YES -eq 1 ]]; then return 0; fi 
    
    if (whiptail --title "Confirmación" --yesno "$1" 10 78); then
        return 0 # "Sí"
    else
        return 1 # "No"
    fi
}

# Pide texto al usuario
# variable=$(tui_get_input "Título" "Pregunta" "ValorPorDefecto")
tui_get_input() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"
    whiptail --title "$title" --inputbox "$prompt" 10 78 "$default" 3>&1 1>&2 2>&3
}

# --- Acciones TUI (Lógica del menú) ---
# (Estas funciones NO llaman a 'err', sino a 'tui_show_message')

# Lógica para Habilitar/Deshabilitar Servicio
tui_action_service() {
    local mode="$1" # "add" o "remove"
    local title_verb; [[ "$mode" == "add" ]] && title_verb="Habilitar" || title_verb="Deshabilitar"
    
    local svc; svc=$(tui_get_input "$title_verb Servicio" "Nombre del servicio (ej. ssh):")
    if [ $? -ne 0 ] || [ -z "$svc" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    
    if ! is_valid_service "$svc"; then
        tui_show_message "Error" "Servicio inválido o desconocido: $svc"; return
    fi
    
    local z; z=$(tui_get_input "$title_verb Servicio" "Zona:" "$ZONE_DEFAULT")
    if [ $? -ne 0 ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    
    if ! is_valid_zone "$z"; then
        tui_show_message "Error" "Zona inválida: $z"; return
    fi
    
    if tui_confirm "$title_verb servicio '$svc' en zona '$z'? (Se aplicará en runtime y permanent)"; then
        SCOPE_RUNTIME=1; SCOPE_PERMANENT=1
        local output; output=$(apply_cmd "$z" "--${mode}-service=$svc" 2>&1)
        if [ $? -eq 0 ]; then
            tui_show_message "Éxito" "Servicio '$svc' ${title_verb,,}do.\n\n$output"
        else
            tui_show_message "Error" "Falló la operación.\n\n$output"
        fi
    fi
}

# Lógica para Abrir/Cerrar Puerto
tui_action_port() {
    local mode="$1" # "add" o "remove"
    local title_verb; [[ "$mode" == "add" ]] && title_verb="Abrir" || title_verb="Cerrar"

    local port; port=$(tui_get_input "$title_verb Puerto" "Puerto (ej. 80/tcp o 5000-5010/udp):")
    if [ $? -ne 0 ] || [ -z "$port" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    
    if ! is_valid_port "$port"; then
        tui_show_message "Error" "Puerto inválido. Formato: 1234/tcp o 1234/udp"; return
    fi
    
    local z; z=$(tui_get_input "$title_verb Puerto" "Zona:" "$ZONE_DEFAULT")
    if [ $? -ne 0 ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    
    if ! is_valid_zone "$z"; then
        tui_show_message "Error" "Zona inválida: $z"; return
    fi
    
    if tui_confirm "$title_verb puerto '$port' en zona '$z'? (Se aplicará en runtime y permanent)"; then
        SCOPE_RUNTIME=1; SCOPE_PERMANENT=1
        local output; output=$(apply_cmd "$z" "--${mode}-port=$port" 2>&1)
        if [ $? -eq 0 ]; then
            tui_show_message "Éxito" "Puerto '$port' ${title_verb,,}to.\n\n$output"
        else
            tui_show_message "Error" "Falló la operación.\n\n$output"
        fi
    fi
}

# Lógica para Bloquear/Desbloquear IP
tui_action_ip() {
    local mode="$1" # "add" o "remove"
    local title_verb; [[ "$mode" == "add" ]] && title_verb="Bloquear" || title_verb="Desbloquear"

    local ip; ip=$(tui_get_input "$title_verb IP" "IP o CIDR (ej. 1.2.3.4 o 1.2.3.0/24):")
    if [ $? -ne 0 ] || [ -z "$ip" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    
    if ! is_valid_ip_or_cidr "$ip"; then
        tui_show_message "Error" "IP/CIDR inválido: $ip"; return
    fi
    
    local z; z=$(tui_get_input "$title_verb IP" "Zona:" "$ZONE_DEFAULT")
    if [ $? -ne 0 ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    
    if ! is_valid_zone "$z"; then
        tui_show_message "Error" "Zona inválida: $z"; return
    fi
    
    local family="ipv4"
    [[ "$ip" == *:* ]] && family="ipv6"
    local rule="rule family=${family} source address=${ip} drop"
    
    if tui_confirm "$title_verb IP '$ip' en zona '$z'? (Se aplicará en runtime y permanent)"; then
        SCOPE_RUNTIME=1; SCOPE_PERMANENT=1
        local output; output=$(apply_cmd "$z" "--${mode}-rich-rule=$rule" 2>&1)
        if [ $? -eq 0 ]; then
            tui_show_message "Éxito" "IP '$ip' ${title_verb,,}da.\n\n$output"
        else
            tui_show_message "Error" "Falló la operación.\n\n$output"
        fi
    fi
}

# Lógica para Redirección de Puertos
tui_action_fwd() {
    local mode="$1" # "add" o "remove"
    local title_verb; [[ "$mode" == "add" ]] && title_verb="Agregar" || title_verb="Quitar"

    local port; port=$(tui_get_input "$title_verb Redirección" "Puerto de origen (ej. 80/tcp):")
    if [ $? -ne 0 ] || [ -z "$port" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    if ! is_valid_port "$port"; then
        tui_show_message "Error" "Puerto inválido: $port"; return
    fi
    
    local to_port; to_port=$(tui_get_input "$title_verb Redirección" "Puerto de destino (ej. 8080):")
    if [ $? -ne 0 ] || [ -z "$to_port" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    
    local to_addr; to_addr=$(tui_get_input "$title_verb Redirección" "IP de destino (Enter para 'localhost'):")
    if [ $? -ne 0 ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi

    local z; z=$(tui_get_input "$title_verb Redirección" "Zona:" "$ZONE_DEFAULT")
    if [ $? -ne 0 ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    if ! is_valid_zone "$z"; then
        tui_show_message "Error" "Zona inválida: $z"; return
    fi

    local p_num="${port%/*}"
    local p_proto="${port#*/}"
    local fw_arg="port=${p_num},proto=${p_proto},to-port=${to_port}"
    if [[ -n "$to_addr" ]]; then
        fw_arg+=",to-addr=${to_addr}"
    fi
    
    if tui_confirm "$title_verb redirección $port -> ${to_addr:-localhost}:$to_port en zona '$z'? (Runtime y Permanent)"; then
        SCOPE_RUNTIME=1; SCOPE_PERMANENT=1
        local output; output=$(apply_cmd "$z" "--${mode}-forward-port=$fw_arg" 2>&1)
        if [ $? -eq 0 ]; then
            tui_show_message "Éxito" "Redirección ${title_verb,,}da.\n\n$output"
        else
            tui_show_message "Error" "Falló la operación.\n\n$output"
        fi
    fi
}

# Lógica para Listar Zona
tui_action_list_zone() {
    local z; z=$(tui_get_input "Listar Zona" "Zona (Enter para '$ZONE_DEFAULT'):" "$ZONE_DEFAULT")
    if [ $? -ne 0 ]; then return; fi
    if ! is_valid_zone "$z"; then
        tui_show_message "Error" "Zona inválida: $z"; return
    fi
    
    # Capturamos la salida de list-all para mostrarla en el msgbox
    local rules; rules=$(firewall-cmd --zone="$z" --list-all)
    tui_show_message "Reglas para: $z" "$rules"
}

# Lógica para Cambiar Zona por Defecto
tui_action_set_default_zone() {
    local newz; newz=$(tui_get_input "Zona por Defecto" "Nueva zona por defecto:" "$ZONE_DEFAULT")
    if [ $? -ne 0 ]; then return; fi
    if ! is_valid_zone "$newz"; then
        tui_show_message "Error" "Zona inválida: $newz"; return
    fi
    
    if tui_confirm "Cambiar zona por defecto a '$newz'?"; then
        firewall-cmd --set-default-zone="$newz"
        ZONE_DEFAULT="$newz" # Actualizamos la variable global
        tui_show_message "Éxito" "Zona por defecto cambiada a '$newz'."
    fi
}

# Lógica para Asignar Interfaz
tui_action_iface_to_zone() {
    local iface; iface=$(tui_get_input "Asignar Interfaz" "Nombre de la interfaz (ej. eth0):")
    if [ $? -ne 0 ] || [ -z "$iface" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    
    local z; z=$(tui_get_input "Asignar Interfaz" "Zona de destino:" "$ZONE_DEFAULT")
    if [ $? -ne 0 ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    if ! is_valid_zone "$z"; then
        tui_show_message "Error" "Zona inválida: $z"; return
    fi
    
    if tui_confirm "Asignar interfaz '$iface' a la zona '$z'? (Cambio permanente)"; then
        # Este comando es --permanent por naturaleza
        local output; output=$(firewall-cmd --zone="$z" --change-interface="$iface" 2>&1)
        if [ $? -eq 0 ]; then
            tui_show_message "Éxito" "Interfaz '$iface' asignada a '$z'.\n\n$output"
        else
            tui_show_message "Error" "Falló la operación.\n\n$output"
        fi
    fi
}

# Lógica para Pánico
tui_action_panic_menu() {
    local CHOICE; CHOICE=$(whiptail --title "Modo Pánico" \
                              --menu "El modo pánico bloquea TODO el tráfico." 15 78 2 \
                              "on" "Activar Modo Pánico" \
                              "off" "Desactivar Modo Pánico" \
                              3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi
    
    if [[ "$CHOICE" == "on" ]]; then
        if tui_confirm "¡ADVERTENCIA! ¿Activar modo pánico AHORA?"; then
            firewall-cmd --panic-on
            tui_show_message "Pánico Activado" "Todo el tráfico está bloqueado."
        fi
    elif [[ "$CHOICE" == "off" ]]; then
        if tui_confirm "¿Desactivar modo pánico AHORA?"; then
            firewall-cmd --panic-off
            tui_show_message "Pánico Desactivado" "El tráfico fluye normalmente."
        fi
    fi
}

# Lógica para Ver Logs
tui_action_view_logs() {
    local n; n=$(tui_get_input "Ver Logs" "Mostrar últimas 'N' líneas:" "50")
    if [ $? -ne 0 ]; then return; fi
    
    if [[ -f "$LOGFILE" ]]; then
        local logs; logs=$(tail -n "$n" "$LOGFILE")
        tui_show_message "Últimas $n líneas de $LOGFILE" "$logs"
    else
        tui_show_message "Error" "No se encuentra el archivo de log: $LOGFILE"
    fi
}

# --- Bucle Principal del Menú TUI ---
tui_main_menu() {
    # Actualizamos la zona por defecto al iniciar
    ZONE_DEFAULT="$(firewall-cmd --get-default-zone 2>/dev/null || echo public)"

    while true; do
        # '--cancel-button "Salir"' cambia el botón "Cancel" por "Salir"
        local CHOICE; CHOICE=$(whiptail --title "Gestor de Firewall (fwctl)" --cancel-button "Salir" \
                                  --menu "\nZona por defecto actual: $ZONE_DEFAULT" 24 78 17 \
                                  "1" "Habilitar servicio" \
                                  "2" "Deshabilitar servicio" \
                                  "3" "Abrir puerto" \
                                  "4" "Cerrar puerto" \
                                  "5" "Bloquear IP/CIDR" \
                                  "6" "Desbloquear IP/CIDR" \
                                  "7" "Redirigir Puerto (Forward)" \
                                  "8" "Quitar Redirección" \
                                  "9" "Ver detalle de una Zona" \
                                  "10" "Cambiar Zona por Defecto" \
                                  "11" "Asignar Interfaz a Zona" \
                                  "12" "Copiar Runtime -> Permanent" \
                                  "13" "Recargar Permanent -> Runtime (Reload Total)" \
                                  "14" "Recargar (Reload Normal)" \
                                  "15" "Modo Pánico (On/Off)" \
                                  "16" "Ver logs del script" \
                                  "17" "Alternar confirmaciones (--yes)" \
                                  3>&1 1>&2 2>&3)
        
        # Si el usuario presiona "Salir", $? será 1
        if [ $? -ne 0 ]; then break; fi

        case "$CHOICE" in
            "1") tui_action_service "add" ;;
            "2") tui_action_service "remove" ;;
            "3") tui_action_port "add" ;;
            "4") tui_action_port "remove" ;;
            "5") tui_action_ip "add" ;;
            "6") tui_action_ip "remove" ;;
            "7") tui_action_fwd "add" ;;
            "8") tui_action_fwd "remove" ;;
            "9") tui_action_list_zone ;;
            "10") tui_action_set_default_zone ;;
            "11") tui_action_iface_to_zone ;;
            "12") 
                if tui_confirm "Copiar REGLAS ACTUALES (Runtime) a PERMANENTES?"; then
                    firewall-cmd --runtime-to-permanent
                    tui_show_message "Éxito" "Reglas actuales guardadas como permanentes."
                fi
                ;;
            "13") 
                if tui_confirm "Borrar reglas actuales y recargar TODO desde PERMANENTE?"; then
                    firewall-cmd --complete-reload
                    tui_show_message "Éxito" "Recarga completa realizada."
                fi
                ;;
            "14") 
                if tui_confirm "Recargar firewalld (aplicar cambios permanentes)?"; then
                    firewall-cmd --reload
                    tui_show_message "Éxito" "Firewall recargado."
                fi
                ;;
            "15") tui_action_panic_menu ;;
            "16") tui_action_view_logs ;;
            "17")
                YES=$((1-YES)) # Truco para cambiar 0 a 1, o 1 a 0
                if [[ $YES -eq 1 ]]; then
                    tui_show_message "Confirmaciones" "Confirmaciones automáticas: ACTIVADAS"
                else
                    tui_show_message "Confirmaciones" "Confirmaciones automáticas: DESACTIVADAS"
                fi
                ;;
        esac
    done
}


### ====== PARSEO DE ARGUMENTOS CLI ======
# (Esta sección se mantiene para el uso por línea de comandos)
ZONE="$ZONE_DEFAULT"
parse_global_args() {
  local -n arr_ref=$1
  local new=()
  while (($#)); do
    case "$1" in
      --yes) YES=1; shift ;;
      --runtime) SCOPE_RUNTIME=1; SCOPE_PERMANENT=0; shift ;;
      --permanent) SCOPE_RUNTIME=0; SCOPE_PERMANENT=1; shift ;;
      --both) SCOPE_RUNTIME=1; SCOPE_PERMANENT=1; shift ;;
      --zone=*) ZONE="${1#*=}"; shift ;;
      --zone) ZONE="$2"; shift 2 ;;
      --help|-h) print_help; exit 0 ;;
      *) new+=("$1"); shift ;;
    esac
  done
  arr_ref=("${new[@]}")
}

### ====== MAIN (El Cerebro) ======
main() {
  # Verificaciones iniciales
  require_root
  require_fw

  ARGS=("$@")
  parse_global_args ARGS "${ARGS[@]}"

  local cmd="${ARGS[0]:-menu}"
  shift || true
  
  # Si 'cmd' NO es 'menu', se ejecuta como CLI
  # Si es 'menu', se salta este 'case' y va al TUI
  case "$cmd" in
    help|--help|-h) print_help; exit 0 ;;
    enable-service)
      [[ $# -ge 1 ]] || err "uso: enable-service <servicio> [--zone=Z]"
      action_enable_service "$1" ; exit 0 ;;
    disable-service)
      [[ $# -ge 1 ]] || err "uso: disable-service <servicio> [--zone=Z]"
      action_disable_service "$1" ; exit 0 ;;
    open-port)
      [[ $# -ge 1 ]] || err "uso: open-port <puerto/proto> [--zone=Z]"
      action_open_port "$1" ; exit 0 ;;
    close-port)
      [[ $# -ge 1 ]] || err "uso: close-port <puerto/proto> [--zone=Z]"
      action_close_port "$1" ; exit 0 ;;
    block)
      [[ $# -ge 1 ]] || err "uso: block <IP|CIDR> [--zone=Z]"
      action_block "$1" ; exit 0 ;;
    unblock)
      [[ $# -ge 1 ]] || err "uso: unblock <IP|CIDR> [--zone=Z]"
      action_unblock "$1" ; exit 0 ;;
    fwd)
      [[ $# -ge 1 ]] || err "uso: fwd <puerto/proto> --to-port=N [--to-addr=IP] [--zone=Z]"
      local port="$1"; shift
      action_fwd "$port" "$@" ; exit 0 ;;
    unfwd)
      [[ $# -ge 1 ]] || err "uso: unfwd <puerto/proto> --to-port=N [--to-addr=IP] [--zone=Z]"
      local port="$1"; shift
      action_unfwd "$port" "$@" ; exit 0 ;;
    set-default-zone)
      [[ $# -ge 1 ]] || err "uso: set-default-zone <zona>"
      action_set_default_zone "$1" ; exit 0 ;;
    iface-to-zone)
      [[ $# -ge 2 ]] || err "uso: iface-to-zone <iface> <zona>"
      action_iface_to_zone "$1" "$2" ; exit 0 ;;
    list-zone)
      action_list_zone "${1:-}" ; exit 0 ;;
    runtime-to-permanent)
      action_runtime_to_permanent ; exit 0 ;;
    permanent-to-runtime)
      action_permanent_to_runtime ; exit 0 ;;
    reload)
      action_reload ; exit 0 ;;
    panic)
      [[ $# -ge 1 ]] || err "uso: panic on|off"
      action_panic "$1" ; exit 0 ;;
    view-logs)
      action_view_logs "${1:-50}" ; exit 0 ;;
    menu)
      # El 'case' se saltará esto, pero lo dejamos por claridad
      : # No hacer nada, dejar que el script continúe al TUI
      ;;
    *)
      # Si el comando CLI no se reconoce, muestra error y sale
      if [[ "$cmd" != "ARGS" ]]; then # "ARGS" es el bug visual que vimos
        err "Acción desconocida: $cmd. Use --help para ver las opciones."
      fi
      # Si no hay argumentos (solo "ARGS"), continúa al TUI
      ;;
  esac

  # --- MODO TUI (nmtui) ---
  # Si el script no salió en la sección CLI, entra al modo TUI
  require_whiptail
  tui_main_menu
  
  # Limpieza final
  clear
  echo "Saliendo de fwctl."
}

# --- Punto de entrada ---
# Llama a main() con todos los argumentos que se le pasaron al script
main "$@"