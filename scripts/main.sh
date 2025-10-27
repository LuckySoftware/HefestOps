#!/bin/bash
# ======================================================
# main.sh - Panel de Control TUI
# Un lanzador de scripts estilo 'nmtui'
# ======================================================

# --- 1. Verificación de Root ---
# Todos estos scripts requieren privilegios elevados.
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: Este script debe ejecutarse como root (o con sudo)."
   exit 1
fi

# --- 2. Verificación de 'whiptail' ---
# Nos aseguramos de que la herramienta para el TUI (Text User Interface) esté instalada.
if ! command -v whiptail &> /dev/null; then
    echo "ERROR: 'whiptail' no está instalado. Es necesario para el menú."
    echo "Por favor, instálalo ejecutando: dnf install newt"
    exit 1
fi

# --- 3. Definir la ubicación de los scripts ---
# Asumimos que todos los scripts están en /root/scripts, basado en tu prompt.
SCRIPT_DIR="/root/scripts"

# --- 4. Bucle del Menú Principal ---
# Usamos 'while true' para que el menú vuelva a aparecer después
# de que un script termine, tal como lo hace nmtui.
while true; do

    # 'whiptail' dibuja el menú.
    # Capturamos la elección (ej. "1") en la variable $CHOICE.
    # El '3>&1 1>&2 2>&3' es un truco necesario para que whiptail
    # dibuje el menú en la pantalla pero nos devuelva la elección.
    CHOICE=$(whiptail --title "Panel de Control (vbox)" \
                      --menu "\nSeleccione una herramienta de administración:" 20 78 10 \
                      "1" "Gestión de Usuarios y Grupos (admin_control.sh)" \
                      "2" "Gestión del Firewall (firewall_manager.sh)" \
                      "3" "Programar Backups - CRON (backup_manager.sh)" \
                      "4" "EJECUTAR un Backup AHORA (backup.sh)" \
                      3>&1 1>&2 2>&3)

    # $? es el código de salida. Si el usuario presiona "Cancelar" o ESC, salimos.
    if [ $? -ne 0 ]; then
        break # Rompe el bucle 'while true'
    fi

    # --- 5. Ejecutar la acción ---
    case "$CHOICE" in
        "1")
            # Este script ya es interactivo y limpia su propia pantalla.
            "$SCRIPT_DIR/admin_control.sh"
            ;;
        "2")
            # Este script también es interactivo.
            "$SCRIPT_DIR/firewall_manager.sh"
            ;;
        "3")
            # Este script también es interactivo.
            "$SCRIPT_DIR/backup_manager.sh"
            ;;
        "4")
            # Este script (backup.sh) NO es interactivo.
            # Por eso, limpiamos la pantalla y le damos contexto
            # y una pausa al final para que el usuario vea el resultado.
            clear
            echo "--- Ejecutando Backup Inmediato ---"
            echo "Por favor, espere..."

            "$SCRIPT_DIR/backup.sh"

            echo "-----------------------------------"
            # El script de backup.sh ya hace un 'clear' y muestra un informe,
            # pero puede que termine muy rápido. Esta pausa asegura
            # que volvamos al menú principal cuando el usuario quiera.
            read -p "Backup finalizado. Presiona ENTER para volver al menú principal..."
            ;;
    esac
done

# --- 6. Limpieza al salir ---
# Limpiamos la pantalla una última vez.
clear
echo "Saliendo del Panel de Control."