#!/bin/bash
# ======================================================
# Gestor de Tareas (Crontab) para Backups
# OS: Fedora Linux
# INTERFAZ: nmtui (whiptail)
# ======================================================

# --- CONFIGURACIÓN ---
SCRIPT_DE_BACKUP="/root/scripts/backup.sh"

# --- VERIFICACIONES INICIALES ---

# 1. Verificación de Root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: Este script debe ejecutarse como root (o con sudo)."
   exit 1
fi

# 2. Verificación de que el script de backup existe
if [ ! -f "$SCRIPT_DE_BACKUP" ]; then
    echo "¡ERROR! No se encuentra el script de backup en:"
    echo "$SCRIPT_DE_BACKUP"
    echo "Por favor, asegúrate de que el archivo exista y esté en la ruta correcta."
    exit 1
fi

# 3. Verificación de que crond (cron) esté corriendo
if ! systemctl is-active --quiet crond; then
    echo "AVISO: El servicio 'crond' no está activo. Iniciando y habilitando..."
    systemctl enable --now crond
    sleep 1
fi

# 4. Verificación de 'whiptail' (la herramienta TUI)
if ! command -v whiptail &> /dev/null; then
    echo "ERROR: 'whiptail' no está instalado. Es necesario para el menú."
    echo "Por favor, instálalo ejecutando: dnf install newt"
    exit 1
fi

# --- FUNCIONES DE LÓGICA (El "motor" de cron) ---

# Esta función elimina cualquier tarea *antigua* de este script
function limpiar_tareas_viejas() {
    (crontab -l | grep -v "$SCRIPT_DE_BACKUP" || true) | crontab -
}

# Esta función programa la nueva tarea
function programar_tarea() {
    local frecuencia_cron="$1"
    limpiar_tareas_viejas
    # Añade la nueva línea al crontab
    (crontab -l ; echo "$frecuencia_cron $SCRIPT_DE_BACKUP") | crontab -
}

# --- FUNCIONES DE INTERFAZ (El "menú" TUI) ---

# Función para listar la tarea actual en una ventana
function listar_tarea_tui() {
    # Obtenemos la tarea actual, o un mensaje si no existe
    local TAREA_ACTUAL
    TAREA_ACTUAL=$(crontab -l | grep "$SCRIPT_DE_BACKUP" || echo "No hay ninguna tarea programada para este script.")
    
    # Mostramos la tarea en un '--msgbox' (un cuadro de mensaje)
    whiptail --title "Tarea Programada Actual" --msgbox "$TAREA_ACTUAL" 10 78
}

# Función para eliminar la tarea (con confirmación TUI)
function eliminar_tarea_tui() {
    # Primero, verificamos si hay algo que eliminar
    if ! crontab -l | grep -q "$SCRIPT_DE_BACKUP"; then
        whiptail --title "Error" --msgbox "No hay ninguna tarea programada para eliminar." 8 78
        return
    fi

    local TAREA_ACTUAL
    TAREA_ACTUAL=$(crontab -l | grep "$SCRIPT_DE_BACKUP")
    
    # Usamos '--yesno' (un cuadro de Sí/No) para confirmar
    if (whiptail --title "Confirmar Eliminación" --yesno "¿Está seguro de que desea eliminar esta tarea?\n\n$TAREA_ACTUAL" 10 78); then
        # Si el usuario elige "Sí"
        limpiar_tareas_viejas
        whiptail --title "Éxito" --msgbox "¡Tarea eliminada!" 8 78
    else
        # Si el usuario elige "No"
        whiptail --title "Cancelado" --msgbox "Operación cancelada." 8 78
    fi
}

# --- MENÚ PRINCIPAL TUI ---
function menu_principal_tui() {
    # Bucle infinito para que el menú vuelva a aparecer (como en nmtui)
    while true; do
        # 'whiptail --menu' crea el menú interactivo
        # La elección del usuario se guarda en la variable $CHOICE
        # El '3>&1 1>&2 2>&3' es un truco estándar para que whiptail funcione
        CHOICE=$(whiptail --title "Gestor de Programación de Backups" \
                          --menu "\nSeleccione la frecuencia del backup:" 20 78 10 \
                          "1" "Listar tarea programada" \
                          "2" "Programar DIARIAMENTE (a medianoche)" \
                          "3" "Programar SEMANALMENTE (domingo a medianoche)" \
                          "4" "Programar MENSUALMENTE (día 1 a medianoche)" \
                          "5" "Programar CADA HORA" \
                          "6" "ELIMINAR Programación de Backup" \
                          3>&1 1>&2 2>&3)

        # $? es el código de salida. Si es 0, el usuario eligió <OK>
        # Si es != 0, el usuario eligió <Cancelar> o presionó ESC.
        if [ $? -ne 0 ]; then
            break # Rompe el bucle y sale del script
        fi

        # Un 'case' para actuar según la elección
        case "$CHOICE" in
            "1")
                listar_tarea_tui
                ;;
            "2")
                programar_tarea "@daily"
                whiptail --title "Éxito" --msgbox "Backup programado DIARIAMENTE." 8 78
                ;;
            "3")
                programar_tarea "@weekly"
                whiptail --title "Éxito" --msgbox "Backup programado SEMANALMENTE." 8 78
                ;;
            "4")
                programar_tarea "@monthly"
                whiptail --title "Éxito" --msgbox "Backup programado MENSUALMENTE." 8 78
                ;;
            "5")
                programar_tarea "@hourly"
                whiptail --title "Éxito" --msgbox "Backup programado CADA HORA." 8 78
                ;;
            "6")
                eliminar_tarea_tui
                ;;
        esac
    done
}

# --- EJECUCIÓN ---
menu_principal_tui

# Limpiamos la pantalla al salir
clear
echo "Saliendo del gestor de tareas."