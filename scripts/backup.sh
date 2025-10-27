#!/bin/bash
# ======================================================
# OS: Fedora Linux
# Interfaz: nmtui (whiptail)
# ======================================================

# === 1. CONFIGURACIÓN ===
ORIGEN="/home/usuario/proyectos"
DESTINO_LOCAL="/mnt/backups_local"
DESTINO_RED="/mnt/servidor_backups"
FECHA=$(date +"%Y-%m-%d_%H-%M")
NOMBRE="backup_${FECHA}.tar.gz"
LOG="/var/log/backup_.log"

# --- Verificación de Root ---
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: Este script debe ejecutarse como root (o con sudo)."
   exit 1
fi

# --- Verificación de 'whiptail' ---
if ! command -v whiptail &> /dev/null; then
    echo "ERROR: 'whiptail' no está instalado. Es necesario para el menú."
    echo "Por favor, instálalo ejecutando: dnf install newt"
    exit 1
fi


# === 2. FUNCIONES ===

# ---
# Función: log()
# MODIFICADA: Escribe SOLO al log, sin 'tee', para no ensuciar la TUI.
# ---
log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" >> "$LOG"
}

# ---
# Función: verificar_montajes()
# Propósito: Comprobar si los directorios de destino están realmente montados.
# ---
verificar_montajes() {
    local all_ok=true
    for destino in "$DESTINO_LOCAL" "$DESTINO_RED"; do
        if mountpoint -q "$destino"; then
            log " [OK] Destino disponible: $destino"
        else
            log " [ERROR] Destino no montado: $destino"
            # Opcional: podríamos hacer que falle si un destino no está.
            # all_ok=false 
        fi
    done
    # De momento, no fallamos si un disco no está, solo lo logueamos.
    return 0
}

# ---
# Función: crear_backup()
# MODIFICADA: Usa 'return 1' en lugar de 'exit 1' para manejo de errores TUI.
# ---
crear_backup() {
    log "Creando backup comprimido..."
    tar -czf "/tmp/$NOMBRE" "$ORIGEN" 2>>"$LOG"
    
    if [ $? -eq 0 ]; then
        log " [OK] Backup creado en /tmp/$NOMBRE"
        return 0 # Éxito
    else
        log " [ERROR] Error al crear el backup"
        return 1 # Falla
    fi
}

# ---
# Función: copiar_backup()
# Propósito: Copiar el backup temporal a los destinos finales.
# ---
copiar_backup() {
    # --- 1. Copia Local ---
    if mountpoint -q "$DESTINO_LOCAL"; then
        log "Copiando (cp) a $DESTINO_LOCAL..."
        cp "/tmp/$NOMBRE" "$DESTINO_LOCAL/" 2>>"$LOG"
        if [ $? -eq 0 ]; then
            log " [OK] Copiado a $DESTINO_LOCAL"
        else
            log " [ERROR] Error copiando a $DESTINO_LOCAL"
        fi
    else
        log " [AVISO] Destino local $DESTINO_LOCAL no está montado. Saltando."
    fi

    # --- 2. Copia Red (rsync) ---
    if mountpoint -q "$DESTINO_RED"; then
        log "Sincronizando (rsync) a $DESTINO_RED..."
        rsync -a "/tmp/$NOMBRE" "$DESTINO_RED/" 2>>"$LOG"
        if [ $? -eq 0 ]; then
            log " [OK] Sincronizado (rsync) a $DESTINO_RED"
        else
            log " [ERROR] Error sincronizando (rsync) a $DESTINO_RED"
        fi
    else
        log " [AVISO] Destino de red $DESTINO_RED no está montado. Saltando."
    fi
    return 0
}

# ---
# Función: limpiar()
# Propósito: Borrar el archivo de backup temporal de /tmp.
# ---
limpiar() {
    rm -f "/tmp/$NOMBRE"
    log " [OK] Backup temporal eliminado"
}

# ---
# Función: informe_final()
# MODIFICADA: Ya no imprime en consola. Devuelve (echo) una cadena de texto.
# ---
informe_final() {
    local TAMANO=$(du -h "/tmp/$NOMBRE" 2>/dev/null | cut -f1)
    local ARCHIVOS=$(tar -tzf "/tmp/$NOMBRE" 2>/dev/null | wc -l)

    # Creamos una cadena de texto (string) con saltos de línea (\n)
    local INFORME_STR=""
    INFORME_STR+="====================================\n"
    INFORME_STR+="      INFORME DEL BACKUP            \n"
    INFORME_STR+="====================================\n\n"
    INFORME_STR+="Fecha y hora:    $FECHA\n"
    INFORME_STR+="Carpeta origen:  $ORIGEN\n"
    INFORME_STR+="Archivo backup:  $NOMBRE\n\n"
    INFORME_STR+="Tamaño:          ${TAMANO:-'N/D'}\n"
    INFORME_STR+="Archivos:        ${ARCHIVOS:-'N/D'}\n\n"
    INFORME_STR+="Estado:         [OK] Backup completado con éxito\n"
    INFORME_STR+="===================================="
    
    # Devolvemos la cadena
    echo "$INFORME_STR"
}

# === 3. EJECUCIÓN TUI ===
# Esta es la nueva función principal que controla la TUI.
# Reemplaza el bloque de ejecución antiguo.
# ---
function main_tui() {
    
    # Un archivo temporal para saber si el subproceso falló
    local STATUS_FILE="/tmp/backup_status.$$"

    # { ... } | whiptail --gauge
    # Ejecutamos toda la lógica de backup (el bloque {}) y
    # su salida (los 'echo') se la pasamos a la barra de progreso.
    {
        # 0% - Iniciando
        log " [OK] Iniciando rutina de backup"
        echo "XXX"
        echo 0
        echo "Iniciando rutina de backup..."
        echo "XXX"
        sleep 1

        # 20% - Verificando Montajes
        verificar_montajes
        echo "XXX"
        echo 20
        echo "Verificando puntos de montaje..."
        echo "XXX"
        sleep 1

        # 40% - Creando Backup
        crear_backup
        # Verificamos el código de salida ($?) de crear_backup
        if [ $? -ne 0 ]; then
            echo "ERROR" > $STATUS_FILE # Escribimos "ERROR" en el archivo de estado
            # Forzamos la barra al 100% para que se cierre
            echo 100 ; sleep 1
            exit # Salimos del subproceso
        fi
        echo "XXX"
        echo 40
        echo "Creando archivo .tar.gz..."
        echo "XXX"
        sleep 1 # Damos tiempo a que se vea el mensaje

        # 70% - Copiando Backup
        copiar_backup
        echo "XXX"
        echo 70
        echo "Copiando a destinos..."
        echo "XXX"
        sleep 1

        # 90% - Limpiando
        limpiar
        echo "XXX"
        echo 90
        echo "Limpiando archivos temporales..."
        echo "XXX"
        sleep 1

        # 100% - Completado
        log " [OK] Respaldo completado con éxito"
        echo "OK" > $STATUS_FILE # Escribimos "OK" en el archivo de estado
        echo "XXX"
        echo 100
        echo "¡Completado! Mostrando informe..."
        echo "XXX"
        sleep 1

    } | whiptail --title "Proceso de Backup" --gauge "Iniciando..." 8 78 0

    # --- Fuera de la barra de progreso ---

    # Leemos el estado (OK o ERROR) del archivo temporal
    local STATUS=$(cat $STATUS_FILE 2>/dev/null)
    rm -f $STATUS_FILE # Borramos el archivo temporal

    # Si el estado es "OK", mostramos el informe
    if [[ "$STATUS" == "OK" ]]; then
        local INFORME
        INFORME=$(informe_final) # Capturamos el string del informe
        # Mostramos el informe en una ventana de mensaje
        whiptail --title "Informe Final" --msgbox "$INFORME" 20 78
    else
        # Si el estado es "ERROR" (o vacío), mostramos un error
        whiptail --title "Error" --msgbox "¡Ocurrió un error crítico durante el backup!\n\nPor favor, revise el log para más detalles:\n$LOG" 10 78
    fi

    clear
}

# --- Punto de entrada ---
# Llamamos a la función TUI principal
main_tui
# === FIN DEL SCRIPT ===