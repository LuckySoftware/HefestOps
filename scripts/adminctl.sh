#!/bin/bash
# =====================================================
# Script de gestión de usuarios en Fedora Linux
# INTERFAZ: nmtui (whiptail)
# FUNCIONES: CRUD + Listar
# =====================================================

# --- VERIFICACIONES INICIALES ---

# 1. Verificación de Root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: Este script debe ejecutarse como root (o con sudo)."
   exit 1
fi

# 2. Verificación de 'whiptail'
if ! command -v whiptail &> /dev/null; then
    echo "ERROR: 'whiptail' no está instalado. Es necesario para el menú."
    echo "Por favor, instálalo ejecutando: dnf install newt"
    exit 1
fi

# --- FUNCIONES TUI (Helpers) ---

function tui_show_message() {
    whiptail --title "$1" --msgbox "$2" 15 78 # Aumentado tamaño para listas
}

function tui_get_input() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"
    whiptail --title "$title" --inputbox "$prompt" 10 78 "$default" 3>&1 1>&2 2>&3
}

function tui_confirm() {
    local title="$1"
    local prompt="$2"
    if (whiptail --title "$title" --yesno "$prompt" 10 78); then
        return 0
    else
        return 1
    fi
}

# --- FUNCIONES DE LÓGICA (El "motor" de usuarios/grupos) ---

function altaUsuario_tui() {
    local usuario; usuario=$(tui_get_input "Alta Usuario" "Ingrese el nombre del nuevo usuario:")
    if [ $? -ne 0 ] || [ -z "$usuario" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi

    local directorio; directorio=$(tui_get_input "Alta Usuario" "Nombre para el directorio home (ej: $usuario):" "$usuario")
    if [ $? -ne 0 ] || [ -z "$directorio" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi

    if grep -q "^$usuario:" /etc/passwd; then
        tui_show_message "Error" "El usuario '$usuario' ya existe."
    else
        local comentario="Usuario creado por script TUI [$(logname)]"
        useradd -d "/home/$directorio" -m -c "$comentario" -s /bin/bash "$usuario"
        local exit_code_useradd=$?

        if [ $exit_code_useradd -eq 0 ]; then
            echo "$usuario:usuario" | chpasswd
            chage -d 0 "$usuario"
            tui_show_message "Éxito" "Usuario '$usuario' creado.\nHome: /home/$directorio\nContraseña temporal: 'usuario' (debe cambiarla)."
        else
            local err_msg; err_msg=$(useradd -d "/home/$directorio" -m -c "$comentario" -s /bin/bash "$usuario" 2>&1 >/dev/null)
            tui_show_message "Error" "Falló la creación del usuario '$usuario'.\n\nDetalle: ${err_msg:-'Código $exit_code_useradd'}"
        fi
    fi
}

function bajaUsuario_tui() {
    local usuario; usuario=$(tui_get_input "Baja Usuario" "Ingrese el nombre del usuario a eliminar:")
    if [ $? -ne 0 ] || [ -z "$usuario" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi

    if ! id "$usuario" &>/dev/null; then
        tui_show_message "Error" "El usuario '$usuario' no existe."
        return
    fi

    # Evitar borrar root u otros usuarios críticos (UID < 1000)
    local uid; uid=$(id -u "$usuario")
    if [[ "$uid" -lt 1000 ]]; then
         tui_show_message "Error" "No se permite eliminar usuarios del sistema (UID < 1000)."
         return
    fi


    if tui_confirm "Confirmar Eliminación" "¿Está seguro de que desea eliminar al usuario '$usuario' y SU DIRECTORIO HOME?\n\n¡Esta acción NO se puede deshacer!"; then
        userdel -r "$usuario"
        if [ $? -eq 0 ]; then
            tui_show_message "Éxito" "Usuario '$usuario' eliminado correctamente."
        else
            tui_show_message "Error" "Falló la eliminación del usuario '$usuario'."
        fi
    else
        tui_show_message "Cancelado" "Operación cancelada."
    fi
}

function crearGrupo_tui() {
    local grupo; grupo=$(tui_get_input "Crear Grupo" "Ingrese el nombre del nuevo grupo:")
    if [ $? -ne 0 ] || [ -z "$grupo" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi

    if getent group "$grupo" &>/dev/null; then
        tui_show_message "Error" "El grupo '$grupo' ya existe."
    else
        groupadd "$grupo"
        if [ $? -eq 0 ]; then
            tui_show_message "Éxito" "Grupo '$grupo' creado correctamente."
        else
            tui_show_message "Error" "Falló la creación del grupo '$grupo'."
        fi
    fi
}

function agregarUsuarioGrupo_tui() {
    local usuario; usuario=$(tui_get_input "Agregar Usuario a Grupo" "Nombre del usuario:")
    if [ $? -ne 0 ] || [ -z "$usuario" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi

    if ! id "$usuario" &>/dev/null; then
        tui_show_message "Error" "El usuario '$usuario' no existe."
        return
    fi

    local grupo; grupo=$(tui_get_input "Agregar Usuario a Grupo" "Nombre del grupo al que añadir a '$usuario':")
    if [ $? -ne 0 ] || [ -z "$grupo" ]; then tui_show_message "Cancelado" "Operación cancelada."; return; fi

    if ! getent group "$grupo" &>/dev/null; then
        tui_show_message "Error" "El grupo '$grupo' no existe."
        return
    fi

    # Verificar si el usuario ya pertenece al grupo
    if groups "$usuario" | grep -qw "$grupo"; then
         tui_show_message "Información" "El usuario '$usuario' ya pertenece al grupo '$grupo'."
         return
    fi

    usermod -aG "$grupo" "$usuario"
    if [ $? -eq 0 ]; then
        tui_show_message "Éxito" "Usuario '$usuario' agregado al grupo '$grupo'."
    else
        tui_show_message "Error" "Falló al agregar '$usuario' al grupo '$grupo'."
    fi
}

# --- NUEVAS FUNCIONES DE LISTADO ---

function listar_usuarios_tui() {
    # awk: Imprime el primer campo ($1, nombre) si el tercer campo ($3, UID) es >= 1000
    # sort: Ordena alfabéticamente
    local user_list; user_list=$(awk -F':' '$3 >= 1000 && $1 != "nobody" { print $1 }' /etc/passwd | sort)
    
    if [ -z "$user_list" ]; then
        tui_show_message "Listar Usuarios" "No se encontraron usuarios normales (UID >= 1000)."
    else
        # Whiptail tiene un límite de altura, mostramos en msgbox que es scrollable
        tui_show_message "Listar Usuarios (UID >= 1000)" "$user_list"
    fi
}

function listar_grupos_tui() {
    # cut: Extrae el primer campo (nombre del grupo)
    local group_list; group_list=$(cut -d: -f1 /etc/group | sort)

    if [ -z "$group_list" ]; then
        tui_show_message "Listar Grupos" "No se encontraron grupos." # Muy improbable
    else
        tui_show_message "Listar Grupos" "$group_list"
    fi
}


# --- MENÚ PRINCIPAL TUI ---
function menu_principal_tui() {
    while true; do
        # Ajustamos el tamaño del menú (20 78 12) y las opciones
        CHOICE=$(whiptail --title "Gestión de Usuarios y Grupos" \
                          --menu "\nSeleccione una opción:" 20 78 12 \
                          "1" "Listar Usuarios (normales)" \
                          "2" "Listar Grupos" \
                          "3" "Alta de usuario" \
                          "4" "Baja de usuario" \
                          "5" "Crear grupo" \
                          "6" "Agregar usuario a grupo" \
                          "7" "Salir" \
                          3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then
            break
        fi

        case "$CHOICE" in
            "1") listar_usuarios_tui ;;
            "2") listar_grupos_tui ;;
            "3") altaUsuario_tui ;;
            "4") bajaUsuario_tui ;;
            "5") crearGrupo_tui ;;
            "6") agregarUsuarioGrupo_tui ;;
            "7") break ;;
        esac
    done
}

# --- EJECUCIÓN ---
menu_principal_tui

clear
echo "Saliendo del gestor de usuarios."