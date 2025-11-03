# Server Management Scripts Suite

![hefestoopslogo](https://github.com/user-attachments/assets/45a285c5-fe49-462a-bc7e-e32fd582c9a1)

A comprehensive collection of Bash scripts for Fedora Server 42 system administration, featuring both CLI and TUI (Text User Interface) modes for user-friendly server management.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Scripts Documentation](#scripts-documentation)
  - [main.sh](#mainsh---control-panel)
  - [admin_control.sh](#admin_controlsh---user--group-management)
  - [fwctl.sh](#fwctlsh---firewall-manager)
  - [backup_manager.sh](#backup_managersh---backup-scheduler)
  - [backup.sh](#backupsh---backup-executor)
- [Usage Examples](#usage-examples)
- [Security Considerations](#security-considerations)
- [License](#license)

## Overview

This suite provides a centralized management system for common server administration tasks. All scripts are designed to work together seamlessly, offering both interactive (TUI) and command-line (CLI) interfaces for maximum flexibility.

## Features

- 🖥️ **Unified TUI Interface** - nmtui-style menu system for easy navigation
- 🔐 **User & Group Management** - Complete CRUD operations with password policies
- 🛡️ **Firewall Control** - Simplified firewalld management with zone configuration
- 💾 **Automated Backups** - Scheduled and on-demand backup solutions
- 📝 **Comprehensive Logging** - All operations are logged for audit trails
- ✅ **Input Validation** - Robust error checking and user confirmation
- 🎨 **Dual Interface** - Both CLI and TUI modes available

## Prerequisites

### System Requirements
- **OS**: Fedora Server 42 (may work on other RHEL-based distributions)
- **Shell**: Bash 4.0+
- **Privileges**: Root access required

### Required Packages
```bash
# Install required utilities
sudo dnf install newt firewalld rsync tar coreutils
```

### Optional Dependencies
- **mountpoint**: For backup destination verification
- **rsync**: For network backup synchronization
- **firewalld**: For firewall management features

## Installation

1. **Clone or download the scripts**:
```bash
mkdir -p /root/scripts
cd /root/scripts
# Place all scripts in this directory
```

2. **Set permissions**:
```bash
chmod +x /root/scripts/*.sh
```

3. **Configure backup destinations** (edit `backup.sh`):
```bash
nano /root/scripts/backup.sh
# Modify ORIGEN, DESTINO_LOCAL, and DESTINO_RED variables
```

4. **Launch the control panel**:
```bash
sudo /root/scripts/main.sh
```

## Scripts Documentation

### main.sh - Control Panel

**Purpose**: Central launcher providing a unified menu interface for all administration tools.

**Features**:
- Interactive menu using `whiptail`
- Root privilege verification
- Automatic script location detection
- Clean session management

**Usage**:
```bash
sudo ./main.sh
```

**Menu Options**:
1. User and Group Management
2. Firewall Management
3. Backup Scheduler (CRON)
4. Execute Immediate Backup

---

### admin_control.sh - User & Group Management

**Purpose**: Comprehensive user and group administration with security best practices.

**Features**:
- Create/delete users with automatic home directory management
- Password policy enforcement (minimum length, complexity)
- Group management (create, delete, add/remove members)
- User listing with formatted output
- Sudo privileges management
- Account locking/unlocking
- Shell assignment

**Usage**:

**Interactive Mode**:
```bash
sudo ./admin_control.sh
```

**CLI Mode Examples**:
```bash
# Create a user
sudo ./admin_control.sh create-user john --shell /bin/bash

# Add user to group
sudo ./admin_control.sh add-to-group john developers

# Grant sudo access
sudo ./admin_control.sh grant-sudo john

# Lock an account
sudo ./admin_control.sh lock-user john
```

**Logging**: All operations logged to `/var/log/admin_control.log`

---

### fwctl.sh - Firewall Manager

**Purpose**: Simplified firewalld management with intuitive interfaces for both beginners and advanced users.

**Features**:
- Service management (enable/disable common services)
- Port control (open/close individual or range of ports)
- IP blocking/unblocking (rich rules with IPv4/IPv6 support)
- Port forwarding (NAT configuration)
- Zone management (list, set default, assign interfaces)
- Runtime and permanent configuration modes
- Panic mode (emergency traffic block)
- Configuration persistence

**Usage**:

**Interactive Mode**:
```bash
sudo ./fwctl.sh
# or
sudo ./fwctl.sh menu
```

**CLI Mode Examples**:
```bash
# Enable SSH service
sudo ./fwctl.sh --permanent enable-service ssh

# Open a port
sudo ./fwctl.sh --both open-port 8080/tcp --zone=public

# Block an IP address
sudo ./fwctl.sh block 192.168.1.100 --zone=public

# Port forwarding
sudo ./fwctl.sh fwd 80/tcp --to-port=8080 --to-addr=192.168.1.10

# List zone configuration
sudo ./fwctl.sh list-zone public

# Make runtime changes permanent
sudo ./fwctl.sh runtime-to-permanent
```

**Scope Options**:
- `--runtime`: Apply changes to current session only
- `--permanent`: Apply changes to saved configuration
- `--both`: Apply to both runtime and permanent (default in TUI)

**Logging**: All operations logged to `/var/log/fwctl.log`

---

### backup_manager.sh - Backup Scheduler

**Purpose**: CRON-based backup scheduling with flexible timing options.

**Features**:
- Visual crontab editor
- Pre-defined schedule templates (daily, weekly, monthly)
- Custom schedule creation
- Current schedule viewing
- Schedule removal
- Automatic cron syntax validation

**Usage**:

**Interactive Mode**:
```bash
sudo ./backup_manager.sh
```

**Menu Options**:
1. View current backup schedule
2. Schedule daily backup
3. Schedule weekly backup
4. Schedule monthly backup
5. Custom schedule
6. Remove backup schedule

**Common Schedules**:
- **Daily**: 2:00 AM every day
- **Weekly**: 3:00 AM every Sunday
- **Monthly**: 4:00 AM on the 1st of each month

**Cron Entry Format**:
```
# Minute Hour Day Month Weekday Command
0 2 * * * /root/scripts/backup.sh
```

---

### backup.sh - Backup Executor

**Purpose**: Automated backup creation, compression, and distribution with multiple destination support.

**Features**:
- TAR.GZ compression
- Multiple destination support (local and network)
- Mount point verification
- Automatic cleanup
- Progress tracking (TUI mode)
- Detailed reporting
- Error handling and logging

**Configuration Variables** (edit in script):
```bash
ORIGEN="/home"                        # Source directory
DESTINO_LOCAL="/mnt/backup_local"     # Local backup destination
DESTINO_RED="/mnt/backup_red"         # Network backup destination
LOG="/var/log/backup.log"             # Log file location
```

**Usage**:

**Direct Execution**:
```bash
sudo ./backup.sh
```

**Scheduled Execution** (via cron):
```bash
# Runs automatically based on backup_manager.sh configuration
```

**Backup Process Flow**:
1. **Initialization**: Verify mount points and prerequisites
2. **Creation**: Compress source directory to `/tmp/backup_YYYY-MM-DD_HH-MM-SS.tar.gz`
3. **Distribution**: Copy to local destination, rsync to network destination
4. **Cleanup**: Remove temporary file from `/tmp`
5. **Reporting**: Display summary with size and file count

**Logging**: All operations logged to `/var/log/backup.log`

**Output Example**:
```
====================================
      BACKUP REPORT            
====================================

Date and time:    2025-11-02_14-30-00
Source folder:    /home
Backup file:      backup_2025-11-02_14-30-00.tar.gz

Size:             2.4G
Files:            15,432

Status:          [OK] Backup completed successfully
====================================
```

## Usage Examples

### Complete Workflow Example

```bash
# 1. Launch control panel
sudo /root/scripts/main.sh

# 2. Create a new user (via admin_control.sh)
#    Navigate to option 1, then create user "webdev"

# 3. Configure firewall (via fwctl.sh)
#    Navigate to option 2, open port 443/tcp

# 4. Schedule daily backups (via backup_manager.sh)
#    Navigate to option 3, set daily backup at 2:00 AM

# 5. Test backup immediately (via backup.sh)
#    Navigate to option 4 to run backup now
```

### CLI Automation Example

```bash
#!/bin/bash
# Automated server setup script

# Create application user
/root/scripts/admin_control.sh create-user appuser --shell /bin/bash

# Configure firewall
/root/scripts/fwctl.sh --both enable-service http
/root/scripts/fwctl.sh --both enable-service https
/root/scripts/fwctl.sh --both open-port 3000/tcp

# Schedule nightly backups
echo "0 2 * * * /root/scripts/backup.sh" | crontab -

# Run initial backup
/root/scripts/backup.sh
```

## Security Considerations

### User Management
- ⚠️ **Default passwords** must be changed on first login
- ✅ **Password complexity** enforced (minimum length, alphanumeric)
- ✅ **Sudo access** requires explicit grant
- ✅ **Account locking** available for security incidents

### Firewall
- ⚠️ **Panic mode** blocks ALL traffic (use with caution)
- ✅ **Changes require confirmation** (unless `--yes` flag used)
- ✅ **Separate runtime/permanent** configurations prevent accidental lockouts
- ✅ **IP blocking** uses rich rules for granular control

### Backups
- ⚠️ **Backup files** contain sensitive data - secure destinations
- ✅ **Log files** contain operation history (`/var/log/`)
- ✅ **Mount point verification** prevents backup to unmounted drives
- ⚠️ **Network shares** should use secure protocols (NFS with Kerberos, SMB with encryption)

### General
- ✅ **All scripts require root** - prevents unauthorized changes
- ✅ **Comprehensive logging** - audit trail for all operations
- ✅ **Error handling** - prevents partial configurations
- ⚠️ **Review logs regularly** in `/var/log/`

## Troubleshooting

### Common Issues

**"whiptail not found"**
```bash
sudo dnf install newt
```

**"firewall-cmd not found"**
```bash
sudo dnf install firewalld
sudo systemctl enable --now firewalld
```

**Backup destinations not mounting**
```bash
# Check /etc/fstab entries
sudo mount -a
# Verify mount points
mountpoint /mnt/backup_local
```

**Permission denied errors**
```bash
# Ensure root execution
sudo -i
cd /root/scripts
./main.sh
```

## File Structure

```
/root/scripts/
├── main.sh                 # Control panel launcher
├── admin_control.sh        # User/group management
├── fwctl.sh               # Firewall manager
├── backup_manager.sh      # Backup scheduler
└── backup.sh              # Backup executor

/var/log/
├── admin_control.log      # User management logs
├── fwctl.log             # Firewall operation logs
└── backup.log            # Backup execution logs
```

## Contributing

Contributions are welcome! Please ensure:
- Bash script follows existing code style
- Root privilege checks are maintained
- All operations include logging
- Error handling is comprehensive
- Documentation is updated

## License

This project is provided as-is for educational and administrative purposes. Feel free to modify and distribute according to your needs.

---

**Tested On**: Fedora Server 42
