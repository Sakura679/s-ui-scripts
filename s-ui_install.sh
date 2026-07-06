#!/bin/bash

# S-UI - Sing-box 管理脚本
# 功能: 一键安装 sing-box 并提供管理面板

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
WORK_DIR="/etc/sing-box"
CONFIG_FILE="$WORK_DIR/conf/config.json"
INIT_SYSTEM=""
SCRIPT_DIR="https://raw.githubusercontent.com/Sakura679/s-ui-scripts/main"
SINGBOX_INSTALL_SCRIPT="$SCRIPT_DIR/singbox_install.sh"

# 日志函数
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 检查是否为 root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以 root 身份运行"
        exit 1
    fi
}

# 检测 init 系统
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

# 检查 sing-box 是否已安装
check_singbox_installed() {
    if [ ! -f "$WORK_DIR/sing-box" ]; then
        return 1
    fi
    return 0
}

# 一键安装 sing-box
install_singbox() {
    log_info "开始安装 sing-box..."
    
    bash <(curl -Ls "$SINGBOX_INSTALL_SCRIPT")
    
    if check_singbox_installed; then
        log_success "sing-box 安装成功"
        return 0
    else
        log_error "sing-box 安装失败"
        return 1
    fi
}

# 获取 sing-box 运行状态
get_singbox_status() {
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        if systemctl is-active --quiet sing-box; then
            echo "运行中"
            return 0
        else
            echo "已停止"
            return 1
        fi
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        if rc-service sing-box status > /dev/null 2>&1; then
            echo "运行中"
            return 0
        else
            echo "已停止"
            return 1
        fi
    fi
}

# 查看 sing-box 运行状态
view_status() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Sing-box 运行状态               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    if ! check_singbox_installed; then
        log_error "sing-box 未安装"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    STATUS=$(get_singbox_status)
    if [ "$STATUS" = "运行中" ]; then
        echo -e "${GREEN}状态: $STATUS${NC}"
    else
        echo -e "${RED}状态: $STATUS${NC}"
    fi
    
    echo ""
    echo "版本信息:"
    "$WORK_DIR/sing-box" version 2>/dev/null || echo "无法获取版本信息"
    
    echo ""
    echo "详细状态:"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl status sing-box --no-pager 2>/dev/null || echo "无法获取状态"
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-service sing-box status 2>/dev/null || echo "无法获取状态"
    fi
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

# 查看配置文件
view_config() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Sing-box 配置文件               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    echo "配置文件位置: $CONFIG_FILE"
    echo ""
    echo "配置内容:"
    echo "─────────────────────────────────────────"
    cat "$CONFIG_FILE" | jq '.' 2>/dev/null || cat "$CONFIG_FILE"
    echo "─────────────────────────────────────────"
    echo ""
    read -p "按 Enter 返回菜单..."
}

# 启动 sing-box
start_singbox() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        启动 Sing-box                   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    if ! check_singbox_installed; then
        log_error "sing-box 未安装"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    log_info "正在启动 sing-box..."
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl start sing-box
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-service sing-box start
    fi
    
    sleep 2
    
    STATUS=$(get_singbox_status)
    if [ "$STATUS" = "运行中" ]; then
        log_success "sing-box 已启动"
    else
        log_error "sing-box 启动失败"
    fi
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

# 停止 sing-box
stop_singbox() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        停止 Sing-box                   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    if ! check_singbox_installed; then
        log_error "sing-box 未安装"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    log_info "正在停止 sing-box..."
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl stop sing-box
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-service sing-box stop
    fi
    
    sleep 2
    
    STATUS=$(get_singbox_status)
    if [ "$STATUS" = "已停止" ]; then
        log_success "sing-box 已停止"
    else
        log_error "sing-box 停止失败"
    fi
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

# 重启 sing-box
restart_singbox() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        重启 Sing-box                   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    if ! check_singbox_installed; then
        log_error "sing-box 未安装"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    log_info "正在重启 sing-box..."
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl restart sing-box
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-service sing-box restart
    fi
    
    sleep 2
    
    STATUS=$(get_singbox_status)
    if [ "$STATUS" = "运行中" ]; then
        log_success "sing-box 已重启"
    else
        log_error "sing-box 重启失败"
    fi
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

# 生成随机密码 (Base64)
generate_password() {
    openssl rand -base64 24
}

# 生成随机 UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 生成随机短 ID
generate_short_id() {
    openssl rand -hex 3
}

# 生成随机私钥
generate_private_key() {
    # openssl rand -base64 32
    cP-CQW7_ltG-dStdp10eKzTPOcv_o3YYeqdD5HZC10Q
}

# 添加 Shadowsocks 节点
add_shadowsocks() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      添加 Shadowsocks 节点             ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "请输入监听端口 (1-65535): " PORT
    
    # 验证端口号
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        log_error "无效的端口号"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    # 生成密码
    PASSWORD=$(generate_password)
    
    # 创建 inbound 配置
    INBOUND=$(cat <<EOF
{
  "type": "shadowsocks",
  "tag": "ss-in-$PORT",
  "listen": "::",
  "listen_port": $PORT,
  "method": "aes-256-gcm",
  "password": "$PASSWORD"
}
EOF
)
    
    # 添加到配置文件
    if add_inbound_to_config "$INBOUND"; then
        log_success "Shadowsocks 节点已添加"
        echo ""
        echo "节点信息:"
        echo "  端口: $PORT"
        echo "  加密方式: aes-256-gcm"
        echo "  密码: $PASSWORD"
        echo ""
        echo "请保存上述信息，然后重启 sing-box 使配置生效"
    else
        log_error "添加节点失败"
    fi
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

# 添加 VLESS+Reality 节点
add_vless_reality() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      添加 VLESS+Reality 节点           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "请输入监听端口 (1-65535): " PORT
    
    # 验证端口号
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        log_error "无效的端口号"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    # 生成 UUID
    UUID=$(generate_uuid)
    
    # 生成 Reality 密钥对（正确方式）
    log_info "正在生成 Reality 密钥对..."
    
    # 使用 sing-box 生成 x25519 密钥对
    KEYPAIR_OUTPUT=$("$WORK_DIR/sing-box" generate reality-keypair 2>/dev/null)
    
    if [ -z "$KEYPAIR_OUTPUT" ]; then
        log_error "无法生成 Reality 密钥对，请确保 sing-box 已正确安装"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    # 解析输出获取私钥和公钥
    # 输出格式通常为:
    # PrivateKey: xxxxx
    # PublicKey: xxxxx
    PRIVATE_KEY=$(echo "$KEYPAIR_OUTPUT" | grep -i "PrivateKey" | awk '{print $NF}')
    PUBLIC_KEY=$(echo "$KEYPAIR_OUTPUT" | grep -i "PublicKey" | awk '{print $NF}')
    
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        log_error "无法解析 Reality 密钥对"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    # 生成短 ID
    SHORT_ID=$(generate_short_id)
    
    # 创建 inbound 配置
    INBOUND=$(cat <<EOF
{
  "type": "vless",
  "tag": "reality-in-$PORT",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "uuid": "$UUID",
      "flow": "xtls-rprx-vision"
    }
  ],
  "tls": {
    "enabled": true,
    "server_name": "gw.alicdn.com",
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "gw.alicdn.com",
        "server_port": 443
      },
      "private_key": "$PRIVATE_KEY",
      "short_id": [
        "$SHORT_ID"
      ]
    }
  }
}
EOF
)
    
    # 添加到配置文件
    if add_inbound_to_config "$INBOUND"; then
        log_success "VLESS+Reality 节点已添加"
        echo ""
        echo "节点信息:"
        echo "  端口: $PORT"
        echo "  UUID: $UUID"
        echo "  Flow: xtls-rprx-vision"
        echo ""
        echo "客户端需要的信息:"
        echo "  公钥 (PublicKey): $PUBLIC_KEY"
        echo "  短ID (ShortID): $SHORT_ID"
        echo "  SNI: gw.alicdn.com"
        echo ""
        echo "⚠️  重要提示:"
        echo "  - 私钥已保存在服务器配置中，请勿泄露"
        echo "  - 将上述客户端信息分享给用户"
        echo "  - 请重启 sing-box 使配置生效"
    else
        log_error "添加节点失败"
    fi
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

# 添加 Hysteria2 节点
add_hysteria2() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      添加 Hysteria2 节点               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "请输入监听端口 (1-65535): " PORT
    
    # 验证端口号
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        log_error "无效的端口号"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    # 生成密码
    PASSWORD=$(generate_password)
    
    # 创建 inbound 配置
    INBOUND=$(cat <<EOF
{
  "type": "hysteria2",
  "tag": "hy2-in-$PORT",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "password": "$PASSWORD"
    }
  ],
  "tls": {
    "enabled": true,
    "certificate_path": "/etc/sing-box/server.crt",
    "key_path": "/etc/sing-box/server.key"
  }
}
EOF
)
    
    # 添加到配置文件
    if add_inbound_to_config "$INBOUND"; then
        log_success "Hysteria2 节点已添加"
        echo ""
        echo "节点信息:"
        echo "  端口: $PORT"
        echo "  密码: $PASSWORD"
        echo "  证书: /etc/sing-box/server.crt"
        echo "  密钥: /etc/sing-box/server.key"
        echo ""
        echo "请保存上述信息，然后重启 sing-box 使配置生效"
    else
        log_error "添加节点失败"
    fi
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

# 将 inbound 添加到配置文件
add_inbound_to_config() {
    local INBOUND="$1"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在"
        return 1
    fi
    
    # 备份原配置文件
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
    
    # 使用 jq 添加 inbound
    if ! jq ".inbounds += [$INBOUND]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
        log_error "配置文件格式错误或 jq 不可用"
        mv "$CONFIG_FILE.bak" "$CONFIG_FILE"
        return 1
    fi
    
    # 验证新配置文件的有效性
    if ! jq empty "$CONFIG_FILE.tmp" 2>/dev/null; then
        log_error "新配置文件格式无效"
        mv "$CONFIG_FILE.bak" "$CONFIG_FILE"
        rm -f "$CONFIG_FILE.tmp"
        return 1
    fi
    
    # 替换配置文件
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    rm -f "$CONFIG_FILE.bak"
    
    return 0
}

# 添加节点菜单
add_inbound_menu() {
    while true; do
        clear
        echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║      添加服务端节点                    ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
        echo ""
        echo "请选择要添加的节点类型:"
        echo ""
        echo "  1) Shadowsocks"
        echo "  2) VLESS + Reality"
        echo "  3) Hysteria2"
        echo "  0) 返回主菜单"
        echo ""
        read -p "请输入选项 (0-3): " choice
        
        case $choice in
            1)
                add_shadowsocks
                ;;
            2)
                add_vless_reality
                ;;
            3)
                add_hysteria2
                ;;
            0)
                return
                ;;
            *)
                log_error "无效的选项"
                sleep 1
                ;;
        esac
    done
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║          S-UI Sing-box 管理面板        ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
        echo ""
        
        # 检查 sing-box 是否已安装
        if check_singbox_installed; then
            STATUS=$(get_singbox_status)
            if [ "$STATUS" = "运行中" ]; then
                echo -e "状态: ${GREEN}$STATUS${NC}"
            else
                echo -e "状态: ${RED}$STATUS${NC}"
            fi
        else
            echo -e "状态: ${RED}未安装${NC}"
        fi
        
        echo ""
        echo "请选择操作:"
        echo ""
        echo "  1) 查看运行状态"
        echo "  2) 查看配置文件"
        echo "  3) 启动 Sing-box"
        echo "  4) 停止 Sing-box"
        echo "  5) 重启 Sing-box"
        echo "  6) 添加服务端节点"
        echo "  0) 退出"
        echo ""
        read -p "请输入选项 (0-6): " choice
        
        case $choice in
            1)
                view_status
                ;;
            2)
                view_config
                ;;
            3)
                start_singbox
                ;;
            4)
                stop_singbox
                ;;
            5)
                restart_singbox
                ;;
            6)
                add_inbound_menu
                ;;
            0)
                log_info "退出管理面板"
                exit 0
                ;;
            *)
                log_error "无效的选项"
                sleep 1
                ;;
        esac
    done
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "缺少以下依赖: ${missing_deps[*]}"
        log_info "正在安装缺失的依赖..."
        
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
            
            case $OS in
                debian|ubuntu)
                    apt-get update
                    apt-get install -y "${missing_deps[@]}"
                    ;;
                centos|rhel|fedora)
                    yum install -y "${missing_deps[@]}"
                    ;;
                alpine)
                    apk update
                    apk add --no-cache "${missing_deps[@]}"
                    ;;
                *)
                    log_warn "无法自动安装依赖，请手动安装: ${missing_deps[*]}"
                    ;;
            esac
        fi
    fi
}

# 主函数
main() {
    # 检查是否为 root
    check_root
    
    # 检测 init 系统
    detect_init_system
    
    # 检查依赖
    check_dependencies
    
    # 如果传入参数 "install"，则执行安装
    if [ "$1" = "install" ]; then
        install_singbox
        exit $?
    fi
    
    # 检查 sing-box 是否已安装
    if ! check_singbox_installed; then
        clear
        echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║          S-UI Sing-box 管理面板        ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
        echo ""
        log_warn "检测到 sing-box 未安装"
        echo ""
        read -p "是否现在安装 sing-box? (y/n): " install_choice
        
        if [ "$install_choice" = "y" ] || [ "$install_choice" = "Y" ]; then
            install_singbox
            if [ $? -eq 0 ]; then
                log_success "sing-box 安装完成，进入管理面板..."
                sleep 2
                main_menu
            else
                log_error "sing-box 安装失败"
                exit 1
            fi
        else
            log_info "退出"
            exit 0
        fi
    else
        # 进入主菜单
        main_menu
    fi
}

# 运行主函数
main "$@"
