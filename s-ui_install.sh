#!/bin/bash

# Sing-box 管理面板脚本 (s-ui.sh)
# 专注于 Sing-box 配置管理
# 支持 systemd 和 OpenRC

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 配置变量
WORK_DIR="/etc/sing-box"
CONFIG_FILE="$WORK_DIR/conf/config.json"
BACKUP_DIR="$WORK_DIR/backups"
INIT_SYSTEM=""
SING_BOX_BIN="$WORK_DIR/sing-box"

# ==================== 日志函数 ====================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# ==================== 系统检测函数 ====================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以 root 身份运行"
        exit 1
    fi
}

detect_init_system() {
    if command -v systemctl &> /dev/null; then
        INIT_SYSTEM="systemd"
    elif command -v rc-service &> /dev/null; then
        INIT_SYSTEM="openrc"
    else
        log_error "无法检测 init 系统"
        exit 1
    fi
}

check_sing_box_installed() {
    if [ ! -f "$SING_BOX_BIN" ]; then
        log_error "Sing-box 未安装，请先运行安装脚本"
        exit 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
}

create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
}

# ==================== 配置验证函数 ====================

validate_json() {
    if ! jq empty "$1" 2>/dev/null; then
        log_error "JSON 格式错误"
        return 1
    fi
    return 0
}

check_config_syntax() {
    log_info "检查配置文件语法..."
    if "$SING_BOX_BIN" check -c "$CONFIG_FILE" > /dev/null 2>&1; then
        log_success "配置文件语法正确"
        return 0
    else
        log_error "配置文件语法错误"
        "$SING_BOX_BIN" check -c "$CONFIG_FILE"
        return 1
    fi
}

# ==================== 备份恢复函数 ====================

backup_config() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/config_${timestamp}.json"
    cp "$CONFIG_FILE" "$backup_file"
    log_success "配置已备份到: $backup_file"
}

list_backups() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}备份文件列表${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
        log_warn "暂无备份文件"
        read -p "按 Enter 继续..."
        return
    fi
    
    local count=1
    for backup in $(ls -t "$BACKUP_DIR"/config_*.json 2>/dev/null); do
        local filename=$(basename "$backup")
        local size=$(du -h "$backup" | cut -f1)
        local mtime=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2)
        
        echo "$count. $filename ($size) - $mtime"
        ((count++))
    done
    
    echo ""
    read -p "按 Enter 继续..."
}

restore_config() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}恢复配置${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
        log_warn "暂无备份文件"
        read -p "按 Enter 继续..."
        return
    fi
    
    local backups=($(ls -t "$BACKUP_DIR"/config_*.json 2>/dev/null))
    local count=${#backups[@]}
    
    for ((i=0; i<count; i++)); do
        local filename=$(basename "${backups[$i]}")
        echo "$((i+1)). $filename"
    done
    
    echo ""
    read -p "请选择要恢复的备份 (1-$count): " restore_choice
    
    if ! [[ "$restore_choice" =~ ^[0-9]+$ ]] || [ "$restore_choice" -lt 1 ] || [ "$restore_choice" -gt "$count" ]; then
        log_error "无效选择"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    local restore_index=$((restore_choice - 1))
    local restore_file="${backups[$restore_index]}"
    
    read -p "确认恢复此备份吗? (y/n): " confirm
    
    if [ "$confirm" != "y" ]; then
        log_warn "已取消恢复"
        read -p "按 Enter 继续..."
        return
    fi
    
    # 备份当前配置
    backup_config
    
    # 恢复备份
    cp "$restore_file" "$CONFIG_FILE"
    
    if check_config_syntax; then
        log_success "配置已恢复"
        
        read -p "是否立即重启服务? (y/n): " restart_confirm
        if [ "$restart_confirm" = "y" ]; then
            restart_service
        fi
    else
        log_error "恢复失败，已恢复之前的备份"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    read -p "按 Enter 继续..."
}

# ==================== 服务管理函数 ====================

start_service() {
    clear
    log_info "启动 Sing-box 服务..."
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl start sing-box
        sleep 2
        if systemctl is-active --quiet sing-box; then
            log_success "Sing-box 服务已启动"
        else
            log_error "Sing-box 服务启动失败"
        fi
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-service sing-box start
        sleep 2
        if rc-service sing-box status > /dev/null 2>&1; then
            log_success "Sing-box 服务已启动"
        else
            log_error "Sing-box 服务启动失败"
        fi
    fi
    
    read -p "按 Enter 继续..."
}

stop_service() {
    clear
    log_info "停止 Sing-box 服务..."
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl stop sing-box
        sleep 2
        if ! systemctl is-active --quiet sing-box; then
            log_success "Sing-box 服务已停止"
        else
            log_error "Sing-box 服务停止失败"
        fi
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-service sing-box stop
        sleep 2
        if ! rc-service sing-box status > /dev/null 2>&1; then
            log_success "Sing-box 服务已停止"
        else
            log_error "Sing-box 服务停止失败"
        fi
    fi
    
    read -p "按 Enter 继续..."
}

restart_service() {
    clear
    log_info "重启 Sing-box 服务..."
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl restart sing-box
        sleep 2
        if systemctl is-active --quiet sing-box; then
            log_success "Sing-box 服务已重启"
        else
            log_error "Sing-box 服务重启失败"
        fi
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-service sing-box restart
        sleep 2
        if rc-service sing-box status > /dev/null 2>&1; then
            log_success "Sing-box 服务已重启"
        else
            log_error "Sing-box 服务重启失败"
        fi
    fi
    
    read -p "按 Enter 继续..."
}

show_service_status() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Sing-box 服务状态${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl status sing-box --no-pager
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-service sing-box status
    fi
    
    echo ""
    read -p "按 Enter 继续..."
}

show_logs() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Sing-box 实时日志 (按 Ctrl+C 退出)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        journalctl -u sing-box -f
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        tail -f /var/log/messages | grep sing-box
    fi
}

show_version() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Sing-box 版本信息${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    "$SING_BOX_BIN" version
    echo ""
    read -p "按 Enter 继续..."
}

# ==================== 节点管理函数 ====================

get_inbound_count() {
    jq '.inbounds | length' "$CONFIG_FILE"
}

show_inbound_list() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Sing-box 节点列表${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local count=$(get_inbound_count)
    
    if [ "$count" -eq 0 ]; then
        log_warn "暂无节点"
        return
    fi
    
    for ((i=0; i<count; i++)); do
        local tag=$(jq -r ".inbounds[$i].tag" "$CONFIG_FILE")
        local type=$(jq -r ".inbounds[$i].type" "$CONFIG_FILE")
        local port=$(jq -r ".inbounds[$i].listen_port // .inbounds[$i].port // \"N/A\"" "$CONFIG_FILE")
        
        echo "$((i+1)). [$type] $tag (端口: $port)"
    done
    
    echo ""
}

add_shadowsocks_node() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}添加 Shadowsocks 节点${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请输入节点标签: " tag
    read -p "请输入监听端口: " port
    read -p "请输入加密方法 (aes-256-gcm/chacha20-poly1305): " method
    read -p "请输入密码: " password
    
    if [ -z "$tag" ] || [ -z "$port" ] || [ -z "$method" ] || [ -z "$password" ]; then
        log_error "输入不能为空"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    backup_config
    
    local new_inbound=$(cat <<EOF
{
  "type": "shadowsocks",
  "tag": "$tag",
  "listen": "::",
  "listen_port": $port,
  "method": "$method",
  "password": "$password",
  "network": "tcp,udp"
}
EOF
)
    local new_inbound=$(cat <<EOF
{
  "type": "shadowsocks",
  "tag": "$tag",
  "listen": "::",
  "listen_port": $port,
  "method": "$method",
  "password": "$password",
  "network": "tcp,udp"
}
EOF
)

    jq ".inbounds += [$new_inbound]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    if check_config_syntax; then
        log_success "Shadowsocks 节点已添加"
        read -p "是否立即重启服务? (y/n): " restart_confirm
        if [ "$restart_confirm" = "y" ]; then
            restart_service
        fi
    else
        log_error "配置错误，已恢复备份"
        cp "$BACKUP_DIR"/config_*.json "$CONFIG_FILE" | tail -1
        read -p "按 Enter 继续..."
        return 1
    fi
    
    read -p "按 Enter 继续..."
}

add_vless_reality_node() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}添加 VLESS+Reality 节点${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请输入节点标签: " tag
    read -p "请输入监听端口: " port
    read -p "请输入 UUID: " uuid
    read -p "请输入 SNI (如: gw.alicdn.com): " sni
    read -p "请输入握手服务器地址: " handshake_server
    read -p "请输入握手服务器端口 (默认: 443): " handshake_port
    handshake_port=${handshake_port:-443}
    read -p "请输入私钥: " private_key
    read -p "请输入 Short ID (如: db1df8): " short_id
    
    if [ -z "$tag" ] || [ -z "$port" ] || [ -z "$uuid" ] || [ -z "$sni" ] || [ -z "$private_key" ]; then
        log_error "输入不能为空"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    backup_config
    
    local new_inbound=$(cat <<EOF
{
  "type": "vless",
  "tag": "$tag",
  "listen": "::",
  "listen_port": $port,
  "users": [
    {
      "uuid": "$uuid"
    }
  ],
  "tls": {
    "enabled": true,
    "server_name": "$sni",
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "$handshake_server",
        "port": $handshake_port
      },
      "private_key": "$private_key",
      "short_id": [
        "$short_id"
      ]
    }
  }
}
EOF
)

    jq ".inbounds += [$new_inbound]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    if check_config_syntax; then
        log_success "VLESS+Reality 节点已添加"
        read -p "是否立即重启服务? (y/n): " restart_confirm
        if [ "$restart_confirm" = "y" ]; then
            restart_service
        fi
    else
        log_error "配置错误，已恢复备份"
        cp "$(ls -t $BACKUP_DIR/config_*.json | head -1)" "$CONFIG_FILE"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    read -p "按 Enter 继续..."
}

add_hysteria2_node() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}添加 Hysteria2 节点${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请输入节点标签: " tag
    read -p "请输入监听端口: " port
    read -p "请输入密码: " password
    read -p "请输入证书路径 (默认: /etc/sing-box/server.crt): " cert_path
    cert_path=${cert_path:-/etc/sing-box/server.crt}
    read -p "请输入密钥路径 (默认: /etc/sing-box/server.key): " key_path
    key_path=${key_path:-/etc/sing-box/server.key}
    
    if [ -z "$tag" ] || [ -z "$port" ] || [ -z "$password" ]; then
        log_error "输入不能为空"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    if [ ! -f "$cert_path" ] || [ ! -f "$key_path" ]; then
        log_error "证书或密钥文件不存在"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    backup_config
    
    local new_inbound=$(cat <<EOF
{
  "type": "hysteria2",
  "tag": "$tag",
  "listen": "::",
  "listen_port": $port,
  "users": [
    {
      "password": "$password"
    }
  ],
  "tls": {
    "enabled": true,
    "certificate_path": "$cert_path",
    "key_path": "$key_path"
  }
}
EOF
)

    jq ".inbounds += [$new_inbound]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    if check_config_syntax; then
        log_success "Hysteria2 节点已添加"
        read -p "是否立即重启服务? (y/n): " restart_confirm
        if [ "$restart_confirm" = "y" ]; then
            restart_service
        fi
    else
        log_error "配置错误，已恢复备份"
        cp "$(ls -t $BACKUP_DIR/config_*.json | head -1)" "$CONFIG_FILE"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    read -p "按 Enter 继续..."
}

add_trojan_node() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}添加 Trojan 节点${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请输入节点标签: " tag
    read -p "请输入监听端口: " port
    read -p "请输入密码: " password
    read -p "请输入证书路径 (默认: /etc/sing-box/server.crt): " cert_path
    cert_path=${cert_path:-/etc/sing-box/server.crt}
    read -p "请输入密钥路径 (默认: /etc/sing-box/server.key): " key_path
    key_path=${key_path:-/etc/sing-box/server.key}
    
    if [ -z "$tag" ] || [ -z "$port" ] || [ -z "$password" ]; then
        log_error "输入不能为空"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    if [ ! -f "$cert_path" ] || [ ! -f "$key_path" ]; then
        log_error "证书或密钥文件不存在"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    backup_config
    
    local new_inbound=$(cat <<EOF
{
  "type": "trojan",
  "tag": "$tag",
  "listen": "::",
  "listen_port": $port,
  "users": [
    {
      "password": "$password"
    }
  ],
  "tls": {
    "enabled": true,
    "certificate_path": "$cert_path",
    "key_path": "$key_path"
  }
}
EOF
)

    jq ".inbounds += [$new_inbound]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    if check_config_syntax; then
        log_success "Trojan 节点已添加"
        read -p "是否立即重启服务? (y/n): " restart_confirm
        if [ "$restart_confirm" = "y" ]; then
            restart_service
        fi
    else
        log_error "配置错误，已恢复备份"
        cp "$(ls -t $BACKUP_DIR/config_*.json | head -1)" "$CONFIG_FILE"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    read -p "按 Enter 继续..."
}

add_node_menu() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}添加节点${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "1. Shadowsocks"
    echo "2. VLESS+Reality"
    echo "3. Hysteria2"
    echo "4. Trojan"
    echo "5. 返回主菜单"
    echo ""
    read -p "请选择协议 (1-5): " choice
    
    case $choice in
        1) add_shadowsocks_node ;;
        2) add_vless_reality_node ;;
        3) add_hysteria2_node ;;
        4) add_trojan_node ;;
        5) return ;;
        *) log_error "无效选择" ;;
    esac
}

delete_node() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}删除节点${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    show_inbound_list
    
    local count=$(get_inbound_count)
    
    if [ "$count" -eq 0 ]; then
        read -p "按 Enter 继续..."
        return
    fi
    
    read -p "请输入要删除的节点编号 (1-$count): " node_num
    
    if ! [[ "$node_num" =~ ^[0-9]+$ ]] || [ "$node_num" -lt 1 ] || [ "$node_num" -gt "$count" ]; then
        log_error "无效选择"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    local delete_index=$((node_num - 1))
    local tag=$(jq -r ".inbounds[$delete_index].tag" "$CONFIG_FILE")
    
    read -p "确认删除节点 '$tag' 吗? (y/n): " confirm
    
    if [ "$confirm" != "y" ]; then
        log_warn "已取消删除"
        read -p "按 Enter 继续..."
        return
    fi
    
    backup_config
    
    jq "del(.inbounds[$delete_index])" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    if check_config_syntax; then
        log_success "节点已删除"
        read -p "是否立即重启服务? (y/n): " restart_confirm
        if [ "$restart_confirm" = "y" ]; then
            restart_service
        fi
    else
        log_error "配置错误，已恢复备份"
        cp "$(ls -t $BACKUP_DIR/config_*.json | head -1)" "$CONFIG_FILE"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    read -p "按 Enter 继续..."
}

modify_node() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}修改节点${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    show_inbound_list
    
    local count=$(get_inbound_count)
    
    if [ "$count" -eq 0 ]; then
        read -p "按 Enter 继续..."
        return
    fi
    
    read -p "请输入要修改的节点编号 (1-$count): " node_num
    
    if ! [[ "$node_num" =~ ^[0-9]+$ ]] || [ "$node_num" -lt 1 ] || [ "$node_num" -gt "$count" ]; then
        log_error "无效选择"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    local modify_index=$((node_num - 1))
    local type=$(jq -r ".inbounds[$modify_index].type" "$CONFIG_FILE")
    local tag=$(jq -r ".inbounds[$modify_index].tag" "$CONFIG_FILE")
    
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}修改节点: $tag ($type)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "1. 修改端口"
    echo "2. 修改密码/UUID"
    echo "3. 修改 SNI/Host"
    echo "4. 查看完整配置"
    echo "5. 返回"
    echo ""
    read -p "请选择修改项 (1-5): " modify_choice
    
    case $modify_choice in
        1)
            read -p "请输入新端口: " new_port
            if ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
                log_error "端口必须是数字"
                read -p "按 Enter 继续..."
                return 1
            fi
            backup_config
            jq ".inbounds[$modify_index].listen_port = $new_port" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            if check_config_syntax; then
                log_success "端口已修改为: $new_port"
                read -p "是否立即重启服务? (y/n): " restart_confirm
                if [ "$restart_confirm" = "y" ]; then
                    restart_service
                fi
            else
                log_error "配置错误，已恢复备份"
                cp "$(ls -t $BACKUP_DIR/config_*.json | head -1)" "$CONFIG_FILE"
            fi
            ;;
        2)
            if [ "$type" = "shadowsocks" ]; then
                read -p "请输入新密码: " new_password
                backup_config
                jq ".inbounds[$modify_index].password = \"$new_password\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            elif [ "$type" = "vless" ]; then
                read -p "请输入新 UUID: " new_uuid
                backup_config
                jq ".inbounds[$modify_index].users[0].uuid = \"$new_uuid\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            elif [ "$type" = "trojan" ] || [ "$type" = "hysteria2" ]; then
                read -p "请输入新密码: " new_password
                backup_config
                jq ".inbounds[$modify_index].users[0].password = \"$new_password\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            fi
            
            if check_config_syntax; then
                log_success "密码/UUID 已修改"
                read -p "是否立即重启服务? (y/n): " restart_confirm
                if [ "$restart_confirm" = "y" ]; then
                    restart_service
                fi
            else
                log_error "配置错误，已恢复备份"
                cp "$(ls -t $BACKUP_DIR/config_*.json | head -1)" "$CONFIG_FILE"
            fi
            ;;
        3)
            if [ "$type" = "vless" ]; then
                read -p "请输入新 SNI: " new_sni
                backup_config
                jq ".inbounds[$modify_index].tls.server_name = \"$new_sni\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                log_success "SNI 已修改为: $new_sni"
            else
                log_warn "此节点类型不支持修改 SNI"
            fi
            ;;
        4)
            clear
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}节点完整配置${NC}"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            jq ".inbounds[$modify_index]" "$CONFIG_FILE"
            echo ""
            ;;
        5)
            return
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
    
    read -p "按 Enter 继续..."
}

show_node_info() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}查看节点信息${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    show_inbound_list
    
    local count=$(get_inbound_count)
    
    if [ "$count" -eq 0 ]; then
        read -p "按 Enter 继续..."
        return
    fi
    
    read -p "请输入要查看的节点编号 (1-$count): " node_num
    
    if ! [[ "$node_num" =~ ^[0-9]+$ ]] || [ "$node_num" -lt 1 ] || [ "$node_num" -gt "$count" ]; then
        log_error "无效选择"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    local view_index=$((node_num - 1))
    
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}节点详细信息${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    jq ".inbounds[$view_index]" "$CONFIG_FILE" | jq '.'
    echo ""
    read -p "按 Enter 继续..."
}

# ==================== 配置文件管理函数 ====================

view_config() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}查看配置文件${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    jq '.' "$CONFIG_FILE"
    echo ""
    read -p "按 Enter 继续..."
}

edit_config() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}编辑配置文件${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    backup_config
    
    if command -v nano &> /dev/null; then
        nano "$CONFIG_FILE"
    elif command -v vi &> /dev/null; then
        vi "$CONFIG_FILE"
    else
        log_error "未找到文本编辑器 (nano/vi)"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    if check_config_syntax; then
        log_success "配置文件已保存"
        read -p "是否立即重启服务? (y/n): " restart_confirm
        if [ "$restart_confirm" = "y" ]; then
            restart_service
        fi
    else
        log_error "配置文件有错误，已恢复备份"
        cp "$(ls -t $BACKUP_DIR/config_*.json | head -1)" "$CONFIG_FILE"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    read -p "按 Enter 继续..."
}

format_config() {
    clear
    log_info "格式化配置文件..."
    
    backup_config
    
    if "$SING_BOX_BIN" format -w -c "$CONFIG_FILE" > /dev/null 2>&1; then
        log_success "配置文件已格式化"
    else
        log_error "格式化失败"
        cp "$(ls -t $BACKUP_DIR/config_*.json | head -1)" "$CONFIG_FILE"
    fi
    
    read -p "按 Enter 继续..."
}

merge_config() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}合并配置文件${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请输入配置目录路径 (默认: $WORK_DIR/conf): " config_dir
    config_dir=${config_dir:-$WORK_DIR/conf}
    
    if [ ! -d "$config_dir" ]; then
        log_error "目录不存在: $config_dir"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    backup_config
    
    local output_file="$WORK_DIR/config_merged.json"
    
    if "$SING_BOX_BIN" merge "$output_file" -c "$CONFIG_FILE" -D "$config_dir" > /dev/null 2>&1; then
        log_success "配置已合并到: $output_file"
        
        read -p "是否使用合并后的配置? (y/n): " use_merged
        if [ "$use_merged" = "y" ]; then
            cp "$output_file" "$CONFIG_FILE"
            log_success "已切换到合并配置"
            read -p "是否立即重启服务? (y/n): " restart_confirm
            if [ "$restart_confirm" = "y" ]; then
                restart_service
            fi
        fi
    else
        log_error "合并失败"
    fi
    
    read -p "按 Enter 继续..."
}

# ==================== 出站管理函数 ====================

show_outbound_list() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}出站列表${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local count=$(jq '.outbounds | length' "$CONFIG_FILE")
    
    if [ "$count" -eq 0 ]; then
        log_warn "暂无出站"
        return
    fi
    
    for ((i=0; i<count; i++)); do
        local tag=$(jq -r ".outbounds[$i].tag" "$CONFIG_FILE")
        local type=$(jq -r ".outbounds[$i].type" "$CONFIG_FILE")
        
        echo "$((i+1)). [$type] $tag"
    done
    
    echo ""
}

add_direct_outbound() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}添加直连出站${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请输入出站标签: " tag
    
    if [ -z "$tag" ]; then
        log_error "标签不能为空"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    backup_config
    
    local new_outbound=$(cat <<EOF
{
  "type": "direct",
  "tag": "$tag"
}
EOF
)

    jq ".outbounds += [$new_outbound]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    if check_config_syntax; then
        log_success "直连出站已添加"
    else
        log_error "配置错误，已恢复备份"
        cp "$(ls -t $BACKUP_DIR/config_*.json | head -1)" "$CONFIG_FILE"
    fi
    
    read -p "按 Enter 继续..."
}

add_socks_outbound() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}添加 SOCKS5 出站${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请输入出站标签: " tag
    read -p "请输入服务器地址: " server
    read -p "请输入服务器端口: " port
    read -p "请输入用户名 (可选): " username
    read -p "请输入密码 (可选): " password
    
    if [ -z "$tag" ] || [ -z "$server" ] || [ -z "$port" ]; then
        log_error "标签、服务器和端口不能为空"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    backup_config
    
    local new_outbound=$(cat <<EOF
{
  "type": "socks",
  "tag": "$tag",
  "server": "$server",
  "server_port": $port
EOF
)

    if [ -n "$username" ] && [ -n "$password" ]; then
        new_outbound+=",\"username\": \"$username\",\"password\": \"$password\""
    fi
    
    new_outbound+="}"
    
    jq ".outbounds += [$new_outbound]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    if check_config_syntax; then
        log_success "SOCKS5 出站已添加"
    else
        log_error "配置错误，已恢复备份"
        cp "$(ls -t $BACKUP_DIR/config_*.json | head -1)" "$CONFIG_FILE"
    fi
    
    read -p "按 Enter 继续..."
}

# ==================== 路由管理函数 ====================

show_route_rules() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}路由规则列表${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local count=$(jq '.route.rules | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
    
    if [ "$count" -eq 0 ]; then
        log_warn "暂无路由规则"
        return
    fi
    
    for ((i=0; i<count; i++)); do
        local outbound=$(jq -r ".route.rules[$i].outbound" "$CONFIG_FILE")
        local domain_count=$(jq ".route.rules[$i].domain // [] | length" "$CONFIG_FILE")
        
        echo "$((i+1)). 出站: $outbound (域名规则: $domain_count)"
    done
    
    echo ""
}

add_route_rule() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}添加路由规则${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请输入出站标签: " outbound
    read -p "请输入域名 (多个用逗号分隔): " domains
    
    if [ -z "$outbound" ] || [ -z "$domains" ]; then
        log_error "出站和域名不能为空"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    backup_config
    
    # 将逗号分隔的域名转换为 JSON 数组
    local domain_array=$(echo "$domains" | tr ',' '\n' | jq -R . | jq -s .)
    
    local new_rule=$(cat <<EOF
{
  "domain": $domain_array,
  "outbound": "$outbound"
}
EOF
)

    jq ".route.rules += [$new_rule]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    if check_config_syntax; then
        log_success "路由规则已添加"
    else
        log_error "配置错误，已恢复备份"
        cp "$(ls -t $BACKUP_DIR/config_*.json | head -1)" "$CONFIG_FILE"
    fi
    
    read -p "按 Enter 继续..."
}

# ==================== 系统信息函数 ====================

show_system_info() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}系统信息${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "${GREEN}操作系统:${NC}"
    uname -a
    echo ""
    
    echo -e "${GREEN}CPU 信息:${NC}"
    grep "model name" /proc/cpuinfo | head -1
    echo ""
    
    echo -e "${GREEN}内存信息:${NC}"
    free -h
    echo ""
    
    echo -e "${GREEN}磁盘信息:${NC}"
    df -h /
    echo ""
    
    echo -e "${GREEN}网络接口:${NC}"
    ip addr show | grep "inet " | grep -v "127.0.0.1"
    echo ""
    
    read -p "按 Enter 继续..."
}

show_network_stats() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}网络统计 (按 Ctrl+C 退出)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    watch -n 1 'ss -s'
}

show_process_info() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Sing-box 进程信息${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    ps aux | grep sing-box | grep -v grep
    echo ""
    read -p "按 Enter 继续..."
}

# ==================== 证书管理函数 ====================

generate_self_signed_cert() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}生成自签名证书${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请输入证书域名: " domain
    read -p "请输入证书有效期 (天数, 默认: 365): " days
    days=${days:-365}
    
    if [ -z "$domain" ]; then
        log_error "域名不能为空"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    local cert_file="$WORK_DIR/server.crt"
    local key_file="$WORK_DIR/server.key"
    
    log_info "生成自签名证书..."
    
    openssl req -x509 -newkey rsa:2048 -keyout "$key_file" -out "$cert_file" \
        -days "$days" -nodes -subj "/CN=$domain" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        chmod 600 "$key_file"
        chmod 644 "$cert_file"
        log_success "证书已生成"
        echo -e "${GREEN}证书路径: $cert_file${NC}"
        echo -e "${GREEN}密钥路径: $key_file${NC}"
    else
        log_error "证书生成失败"
    fi
    
    read -p "按 Enter 继续..."
}

view_cert_info() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}查看证书信息${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请输入证书文件路径: " cert_path
    
    if [ ! -f "$cert_path" ]; then
        log_error "证书文件不存在"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    openssl x509 -in "$cert_path" -text -noout
    echo ""
    read -p "按 Enter 继续..."
}

# ==================== 备份恢复函数 ====================

list_backups() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}备份列表${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR)" ]; then
        log_warn "暂无备份"
        read -p "按 Enter 继续..."
        return
    fi
    
    local count=0
    for backup in $(ls -t "$BACKUP_DIR"/config_*.json); do
        count=$((count + 1))
        local size=$(du -h "$backup" | cut -f1)
        local time=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2 || stat -f "%Sm" "$backup" 2>/dev/null)
        echo "$count. $(basename $backup) ($size) - $time"
    done
    
    echo ""
    read -p "按 Enter 继续..."
}

restore_backup() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}恢复备份${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR)" ]; then
        log_warn "暂无备份"
        read -p "按 Enter 继续..."
        return
    fi
    
    local count=0
    local -a backups
    
    for backup in $(ls -t "$BACKUP_DIR"/config_*.json); do
        count=$((count + 1))
        backups+=("$backup")
        echo "$count. $(basename $backup)"
    done
    
    echo ""
    read -p "请选择要恢复的备份 (1-$count): " backup_num
    
    if ! [[ "$backup_num" =~ ^[0-9]+$ ]] || [ "$backup_num" -lt 1 ] || [ "$backup_num" -gt "$count" ]; then
        log_error "无效选择"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    local restore_index=$((backup_num - 1))
    local restore_file="${backups[$restore_index]}"
    
    read -p "确认恢复此备份吗? (y/n): " confirm
    
    if [ "$confirm" != "y" ]; then
        log_warn "已取消恢复"
        read -p "按 Enter 继续..."
        return
    fi
    
    cp "$restore_file" "$CONFIG_FILE"
    
    if check_config_syntax; then
        log_success "备份已恢复"
        read -p "是否立即重启服务? (y/n): " restart_confirm
        if [ "$restart_confirm" = "y" ]; then
            restart_service
        fi
    else
        log_error "恢复的配置有错误"
    fi
    
    read -p "按 Enter 继续..."
}

clean_old_backups() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}清理旧备份${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "请输入保留备份数量 (默认: 10): " keep_count
    keep_count=${keep_count:-10}
    
    if ! [[ "$keep_count" =~ ^[0-9]+$ ]]; then
        log_error "必须输入数字"
        read -p "按 Enter 继续..."
        return 1
    fi
    
    local total=$(ls -1 "$BACKUP_DIR"/config_*.json 2>/dev/null | wc -l)
    local delete_count=$((total - keep_count))
    
    if [ "$delete_count" -le 0 ]; then
        log_info "备份数量已在限制内"
        read -p "按 Enter 继续..."
        return
    fi
    
    log_info "将删除 $delete_count 个旧备份..."
    ls -t "$BACKUP_DIR"/config_*.json | tail -n "$delete_count" | xargs rm -f
    
    log_success "旧备份已清理"
    read -p "按 Enter 继续..."
}

# ==================== 主菜单函数 ====================

show_main_menu() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}   Sing-box 管理面板${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}【服务管理】${NC}"
    echo "1.  启动服务"
    echo "2.  停止服务"
    echo "3.  重启服务"
    echo "4.  查看服务状态"
    echo "5.  查看实时日志"
    echo ""
    echo -e "${GREEN}【节点管理】${NC}"
    echo "6.  查看节点列表"
    echo "7.  添加节点"
    echo "8.  删除节点"
    echo "9.  修改节点"
    echo "10. 查看节点信息"
    echo ""
    echo -e "${GREEN}【配置管理】${NC}"
    echo "11. 查看配置文件"
    echo "12. 编辑配置文件"
    echo "13. 格式化配置"
    echo "14. 合并配置文件"
    echo ""
    echo -e "${GREEN}【出站管理】${NC}"
    echo "15. 查看出站列表"
    echo "16. 添加直连出站"
    echo "17. 添加 SOCKS5 出站"
    echo ""
    echo -e "${GREEN}【路由管理】${NC}"
    echo "18. 查看路由规则"
    echo "19. 添加路由规则"
    echo ""
    echo -e "${GREEN}【证书管理】${NC}"
    echo "20. 生成自签名证书"
    echo "21. 查看证书信息"
    echo ""
    echo -e "${GREEN}【备份恢复】${NC}"
    echo "22. 查看备份列表"
    echo "23. 恢复备份"
    echo "24. 清理旧备份"
    echo ""
    echo -e "${GREEN}【系统信息】${NC}"
    echo "25. 查看系统信息"
    echo "26. 查看网络统计"
    echo "27. 查看进程信息"
    echo ""
    echo -e "${GREEN}【其他】${NC}"
    echo "28. 检查更新"
    echo "29. 卸载 Sing-box"
    echo "0.  退出"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "请选择操作 (0-29): " choice
}

# ==================== 主程序 ====================

main() {
    check_root
    check_dependencies
    init_environment
    
    while true; do
        show_main_menu
        
        case $choice in
            1) start_service ;;
            2) stop_service ;;
            3) restart_service ;;
            4) show_service_status ;;
            5) show_realtime_logs ;;
            6) show_inbound_list; read -p "按 Enter 继续..." ;;
            7) add_node_menu ;;
            8) delete_node ;;
            9) modify_node ;;
            10) show_node_info ;;
            11) view_config ;;
            12) edit_config ;;
            13) format_config ;;
            14) merge_config ;;
            15) show_outbound_list; read -p "按 Enter 继续..." ;;
            16) add_direct_outbound ;;
            17) add_socks_outbound ;;
            18) show_route_rules; read -p "按 Enter 继续..." ;;
            19) add_route_rule ;;
            20) generate_self_signed_cert ;;
            21) view_cert_info ;;
            22) list_backups ;;
            23) restore_backup ;;
            24) clean_old_backups ;;
            25) show_system_info ;;
            26) show_network_stats ;;
            27) show_process_info ;;
            28) check_updates ;;
            29) uninstall_singbox ;;
            0)
                log_info "退出管理面板"
                exit 0
                ;;
            *)
                log_error "无效选择，请重试"
                read -p "按 Enter 继续..."
                ;;
        esac
    done
}

# ==================== 脚本入口 ====================

# 检查是否以 root 身份运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 此脚本必须以 root 身份运行${NC}"
    exit 1
fi

# 运行主程序
main "$@"
