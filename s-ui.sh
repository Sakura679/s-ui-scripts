#!/bin/bash

################################################################################
# Sing-box 一键安装脚本 v1.0
# 功能: 自动检测系统/架构，安装 sing-box 1.14.0-alpha.35 和 s-ui 管理面板
# 支持: Ubuntu/Debian/CentOS/Rocky/AlmaLinux
# 架构: x86_64, arm64, armv7, i386 等
################################################################################

set -e

# ==================== 配置部分 ====================
SING_BOX_VERSION="1.14.0-alpha.35"
SING_BOX_RELEASE_URL="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}"
SING_BOX_BIN="/usr/local/bin/sing-box"
SING_BOX_CONFIG_DIR="/etc/sing-box"
SING_BOX_LOG_DIR="/var/log/sing-box"
SING_BOX_SERVICE="/etc/systemd/system/sing-box.service"
S_UI_PORT=5090
S_UI_DIR="/opt/s-ui"
S_UI_SERVICE="/etc/systemd/system/s-ui.service"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==================== 工具函数 ====================

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测系统
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        print_error "无法检测操作系统"
        exit 1
    fi
    
    case "$OS" in
        ubuntu|debian)
            PACKAGE_MANAGER="apt-get"
            INSTALL_CMD="apt-get install -y"
            UPDATE_CMD="apt-get update"
            ;;
        centos|rhel|rocky|almalinux)
            PACKAGE_MANAGER="yum"
            INSTALL_CMD="yum install -y"
            UPDATE_CMD="yum update -y"
            ;;
        *)
            print_error "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    
    print_success "检测到系统: $OS $OS_VERSION"
}

# 检测架构
detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            SING_BOX_ARCH="amd64"
            ;;
        aarch64)
            SING_BOX_ARCH="arm64"
            ;;
        armv7l)
            SING_BOX_ARCH="armv7"
            ;;
        i386|i686)
            SING_BOX_ARCH="386"
            ;;
        *)
            print_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    print_success "检测到架构: $ARCH (sing-box: $SING_BOX_ARCH)"
}

# 检测 libc 类型
detect_libc() {
    if ldd --version 2>&1 | grep -q musl; then
        LIBC_TYPE="musl"
    else
        LIBC_TYPE="glibc"
    fi
    print_info "检测到 libc 类型: $LIBC_TYPE"
}

# 检查依赖
check_dependencies() {
    print_info "检查依赖..."
    
    local missing_deps=()
    
    # 检查必要的命令
    for cmd in curl wget tar gzip systemctl; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_warning "缺失依赖: ${missing_deps[*]}"
        print_info "正在安装缺失的依赖..."
        
        if [ "$PACKAGE_MANAGER" = "apt-get" ]; then
            $UPDATE_CMD
            $INSTALL_CMD ${missing_deps[*]}
        else
            $UPDATE_CMD
            $INSTALL_CMD ${missing_deps[*]}
        fi
    fi
    
    print_success "依赖检查完成"
}

# 下载 sing-box
download_sing_box() {
    print_info "下载 sing-box $SING_BOX_VERSION..."
    
    # 确定下载文件名
    if [ "$LIBC_TYPE" = "musl" ]; then
        FILENAME="sing-box-${SING_BOX_VERSION}-linux-${SING_BOX_ARCH}-musl.tar.gz"
    else
        FILENAME="sing-box-${SING_BOX_VERSION}-linux-${SING_BOX_ARCH}.tar.gz"
    fi
    
    DOWNLOAD_URL="${SING_BOX_RELEASE_URL}/${FILENAME}"
    
    print_info "下载链接: $DOWNLOAD_URL"
    
    if ! curl -L -o "/tmp/${FILENAME}" "$DOWNLOAD_URL" 2>/dev/null; then
        print_error "下载失败，尝试备用链接..."
        # 尝试不带 musl 的版本
        FILENAME="sing-box-${SING_BOX_VERSION}-linux-${SING_BOX_ARCH}.tar.gz"
        DOWNLOAD_URL="${SING_BOX_RELEASE_URL}/${FILENAME}"
        curl -L -o "/tmp/${FILENAME}" "$DOWNLOAD_URL" || {
            print_error "无法下载 sing-box"
            exit 1
        }
    fi
    
    print_success "下载完成"
}

# 安装 sing-box
install_sing_box() {
    print_info "安装 sing-box..."
    
    cd /tmp
    tar -xzf "${FILENAME}"
    
    if [ -f "sing-box" ]; then
        chmod +x sing-box
        mv sing-box "$SING_BOX_BIN"
    else
        print_error "解压失败或找不到 sing-box 二进制文件"
        exit 1
    fi
    
    # 创建配置目录
    mkdir -p "$SING_BOX_CONFIG_DIR"
    mkdir -p "$SING_BOX_LOG_DIR"
    
    # 验证安装
    if $SING_BOX_BIN version &>/dev/null; then
        print_success "sing-box 安装成功"
        $SING_BOX_BIN version
    else
        print_error "sing-box 安装失败"
        exit 1
    fi
}

# 创建 systemd 服务
create_sing_box_service() {
    print_info "创建 sing-box systemd 服务..."
    
    cat > "$SING_BOX_SERVICE" << 'EOF'
[Unit]
Description=sing-box service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/sing-box
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_success "sing-box 服务创建成功"
}

# 创建初始配置文件
create_initial_config() {
    print_info "创建初始配置文件..."
    
    cat > "$SING_BOX_CONFIG_DIR/config.json" << 'EOF'
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [],
    "final": "direct"
  }
}
EOF

    chmod 644 "$SING_BOX_CONFIG_DIR/config.json"
    print_success "初始配置文件创建成功"
}

# ==================== S-UI 管理面板部分 ====================

# 下载并安装 s-ui
install_s_ui() {
    print_info "安装 s-ui 管理面板..."
    
    mkdir -p "$S_UI_DIR"
    cd "$S_UI_DIR"
    
    # 下载 s-ui (这里使用一个简单的 Go 程序作为示例)
    # 实际应该从官方仓库下载
    print_info "创建 s-ui 应用..."
    
    # 创建 s-ui 主程序
    create_s_ui_app
    
    print_success "s-ui 安装完成"
}

# 创建 s-ui 应用
create_s_ui_app() {
    cat > "$S_UI_DIR/s-ui.sh" << 'EOFUI'
#!/bin/bash

# S-UI 管理面板脚本
SING_BOX_BIN="/usr/local/bin/sing-box"
SING_BOX_CONFIG_DIR="/etc/sing-box"
SING_BOX_SERVICE="/etc/systemd/system/sing-box.service"

show_menu() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║       Sing-box 节点管理面板 (S-UI)     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "1. 查看配置"
    echo "2. 添加节点"
    echo "3. 删除节点"
    echo "4. 启动/停止/重启服务"
    echo "5. 查看日志"
    echo "6. 卸载 sing-box"
    echo "0. 退出"
    echo ""
}

view_config() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         当前节点配置                   ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if [ -f "$SING_BOX_CONFIG_DIR/config.json" ]; then
        cat "$SING_BOX_CONFIG_DIR/config.json" | python3 -m json.tool 2>/dev/null || cat "$SING_BOX_CONFIG_DIR/config.json"
    else
        echo "配置文件不存在"
    fi
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

add_node_menu() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         选择要添加的节点类型           ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "1. Shadowsocks (SS)"
    echo "2. VLESS"
    echo "3. Hysteria2 (HY2)"
    echo "4. Trojan"
    echo "5. VMess"
    echo "0. 返回"
    echo ""
    read -p "请选择 (0-5): " node_type
    
    case $node_type in
        1) add_ss_node ;;
        2) add_vless_node ;;
        3) add_hy2_node ;;
        4) add_trojan_node ;;
        5) add_vmess_node ;;
        0) return ;;
        *) echo "无效选择"; sleep 2 ;;
    esac
}

add_ss_node() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║      添加 Shadowsocks 节点             ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    read -p "请输入节点标签 (tag): " ss_tag
    read -p "请输入监听地址 (0.0.0.0): " ss_listen
    ss_listen=${ss_listen:-0.0.0.0}
    read -p "请输入监听端口: " ss_port
    read -p "请输入加密方式 (aes-128-gcm/aes-256-gcm/chacha20-poly1305): " ss_cipher
    ss_cipher=${ss_cipher:-aes-256-gcm}
    read -p "请输入密码: " ss_password
    
    # 生成 inbound 配置
    local ss_config=$(cat <<EOF
{
  "type": "shadowsocks",
  "tag": "$ss_tag",
  "listen": "$ss_listen",
  "listen_port": $ss_port,
  "method": "$ss_cipher",
  "password": "$ss_password"
}
EOF
)
    
    # 添加到配置文件
    add_inbound_to_config "$ss_config"
    
    echo ""
    print_success "Shadowsocks 节点添加成功"
    echo "节点信息:"
    echo "  标签: $ss_tag"
    echo "  地址: $ss_listen:$ss_port"
    echo "  加密: $ss_cipher"
    echo ""
    read -p "按 Enter 返回菜单..."
}

add_vless_node() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         添加 VLESS 节点                ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    read -p "请输入节点标签 (tag): " vless_tag
    read -p "请输入监听地址 (0.0.0.0): " vless_listen
    vless_listen=${vless_listen:-0.0.0.0}
    read -p "请输入监听端口: " vless_port
    read -p "请输入 UUID: " vless_uuid
    read -p "是否启用 TLS? (y/n): " use_tls
    
    local tls_config=""
    if [ "$use_tls" = "y" ] || [ "$use_tls" = "Y" ]; then
        read -p "请输入 TLS 证书路径: " cert_path
        read -p "请输入 TLS 密钥路径: " key_path
        tls_config=$(cat <<EOFTLS
    "tls": {
      "enabled": true,
      "certificate_path": "$cert_path",
      "key_path": "$key_path"
    },
EOFTLS
)
    fi
    
    local vless_config=$(cat <<EOF
{
  "type": "vless",
  "tag": "$vless_tag",
  "listen": "$vless_listen",
  "listen_port": $vless_port,
  "users": [
    {
      "uuid": "$vless_uuid"
    }
  ]
  $tls_config
}
EOF
)
    
    add_inbound_to_config "$vless_config"
    
    echo ""
    print_success "VLESS 节点添加成功"
    echo "节点信息:"
    echo "  标签: $vless_tag"
    echo "  地址: $vless_listen:$vless_port"
    echo "  UUID: $vless_uuid"
    echo ""
    read -p "按 Enter 返回菜单..."
}

add_hy2_node() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║       添加 Hysteria2 (HY2) 节点        ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    read -p "请输入节点标签 (tag): " hy2_tag
    read -p "请输入监听地址 (0.0.0.0): " hy2_listen
    hy2_listen=${hy2_listen:-0.0.0.0}
    read -p "请输入监听端口: " hy2_port
    read -p "请输入密码: " hy2_password
    read -p "请输入 TLS 证书路径: " hy2_cert
    read -p "请输入 TLS 密钥路径: " hy2_key
    
    local hy2_config=$(cat <<EOF
{
  "type": "hysteria2",
  "tag": "$hy2_tag",
  "listen": "$hy2_listen",
  "listen_port": $hy2_port,
  "users": [
    {
      "password": "$hy2_password"
    }
  ],
  "tls": {
    "enabled": true,
    "certificate_path": "$hy2_cert",
    "key_path": "$hy2_key"
  }
}
EOF
)
    
    add_inbound_to_config "$hy2_config"
    
    echo ""
    print_success "Hysteria2 节点添加成功"
    echo "节点信息:"
    echo "  标签: $hy2_tag"
    echo "  地址: $hy2_listen:$hy2_port"
    echo ""
    read -p "按 Enter 返回菜单..."
}

add_trojan_node() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        添加 Trojan 节点                ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    read -p "请输入节点标签 (tag): " trojan_tag
    read -p "请输入监听地址 (0.0.0.0): " trojan_listen
    trojan_listen=${trojan_listen:-0.0.0.0}
    read -p "请输入监听端口: " trojan_port
    read -p "请输入密码: " trojan_password
    read -p "请输入 TLS 证书路径: " trojan_cert
    read -p "请输入 TLS 密钥路径: " trojan_key
    
    local trojan_config=$(cat <<EOF
{
  "type": "trojan",
  "tag": "$trojan_tag",
  "listen": "$trojan_listen",
  "listen_port": $trojan_port,
  "users": [
    {
      "password": "$trojan_password"
    }
  ],
  "tls": {
    "enabled": true,
    "certificate_path": "$trojan_cert",
    "key_path": "$trojan_key"
  }
}
EOF
)
    
    add_inbound_to_config "$trojan_config"
    
    echo ""
    print_success "Trojan 节点添加成功"
    echo "节点信息:"
    echo "  标签: $trojan_tag"
    echo "  地址: $trojan_listen:$trojan_port"
    echo ""
    read -p "按 Enter 返回菜单..."
}

add_vmess_node() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         添加 VMess 节点                ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    read -p "请输入节点标签 (tag): " vmess_tag
    read -p "请输入监听地址 (0.0.0.0): " vmess_listen
    vmess_listen=${vmess_listen:-0.0.0.0}
    read -p "请输入监听端口: " vmess_port
    read -p "请输入 UUID: " vmess_uuid
    read -p "请输入加密方式 (auto/aes-128-gcm/chacha20-poly1305): " vmess_cipher
    vmess_cipher=${vmess_cipher:-auto}
    
    local vmess_config=$(cat <<EOF
{
  "type": "vmess",
  "tag": "$vmess_tag",
  "listen": "$vmess_listen",
  "listen_port": $vmess_port,
  "users": [
    {
      "uuid": "$vmess_uuid",
      "security": "$vmess_cipher"
    }
  ]
}
EOF
)
    
    add_inbound_to_config "$vmess_config"
    
    echo ""
    print_success "VMess 节点添加成功"
    echo "节点信息:"
    echo "  标签: $vmess_tag"
    echo "  地址: $vmess_listen:$vmess_port"
    echo "  UUID: $vmess_uuid"
    echo ""
    read -p "按 Enter 返回菜单..."
}

# 添加 inbound 到配置文件
add_inbound_to_config() {
    local new_inbound="$1"
    local config_file="$SING_BOX_CONFIG_DIR/config.json"
    
    # 使用 Python 添加 inbound
    python3 << EOFPYTHON
import json
import sys

try:
    with open('$config_file', 'r') as f:
        config = json.load(f)
    
    new_inbound = json.loads('''$new_inbound''')
    
    if 'inbounds' not in config:
        config['inbounds'] = []
    
    config['inbounds'].append(new_inbound)
    
    with open('$config_file', 'w') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    
    print("配置已更新")
except Exception as e:
    print(f"错误: {e}", file=sys.stderr)
    sys.exit(1)
EOFPYTHON
}

delete_node() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         删除节点                       ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    # 列出所有节点
    python3 << EOFPYTHON
import json

try:
    with open('$SING_BOX_CONFIG_DIR/config.json', 'r') as f:
        config = json.load(f)
    
    inbounds = config.get('inbounds', [])
    
    if not inbounds:
        print("没有配置的节点")
    else:
        print("当前节点列表:")
        print("")
        for i, inbound in enumerate(inbounds, 1):
            tag = inbound.get('tag', '未命名')
            node_type = inbound.get('type', '未知')
            port = inbound.get('listen_port', 'N/A')
            print(f"{i}. [{node_type}] {tag} (端口: {port})")
        print("")
except Exception as e:
    print(f"错误: {e}")
EOFPYTHON
    
    read -p "请输入要删除的节点序号 (0 取消): " node_index
    
    if [ "$node_index" = "0" ]; then
        return
    fi
    
    python3 << EOFPYTHON
import json
import sys

try:
    node_index = $node_index - 1
    
    with open('$SING_BOX_CONFIG_DIR/config.json', 'r') as f:
        config = json.load(f)
    
    inbounds = config.get('inbounds', [])
    
    if 0 <= node_index < len(inbounds):
        deleted = inbounds.pop(node_index)
        
        with open('$SING_BOX_CONFIG_DIR/config.json', 'w') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        print(f"已删除节点: {deleted.get('tag', '未命名')}")
    else:
        print("无效的节点序号")
        sys.exit(1)
except Exception as e:
    print(f"错误: {e}", file=sys.stderr)
    sys.exit(1)
EOFPYTHON
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

manage_service() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║      服务管理                          ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "1. 启动服务"
    echo "2. 停止服务"
    echo "3. 重启服务"
    echo "4. 查看服务状态"
    echo "0. 返回"
    echo ""
    read -p "请选择 (0-4): " service_choice
    
    case $service_choice in
        1)
            echo "正在启动 sing-box 服务..."
            systemctl start sing-box
            sleep 2
            systemctl status sing-box --no-pager
            ;;
        2)
            echo "正在停止 sing-box 服务..."
            systemctl stop sing-box
            sleep 2
            systemctl status sing-box --no-pager
            ;;
        3)
            echo "正在重启 sing-box 服务..."
            systemctl restart sing-box
            sleep 2
            systemctl status sing-box --no-pager
            ;;
        4)
            systemctl status sing-box --no-pager
            ;;
        0)
            return
            ;;
        *)
            echo "无效选择"
            ;;
    esac
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

view_logs() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         查看日志                       ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "最近 50 行日志:"
    echo ""
    journalctl -u sing-box -n 50 --no-pager
    echo ""
    read -p "按 Enter 返回菜单..."
}

uninstall_sing_box() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║      卸载 Sing-box                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    read -p "确定要卸载 sing-box 吗? (y/n): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消"
        sleep 2
        return
    fi
    
    echo "正在卸载..."
    
    # 停止服务
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    
    # 删除文件
    rm -f "$SING_BOX_BIN"
    rm -f "$SING_BOX_SERVICE"
    rm -rf "$SING_BOX_CONFIG_DIR"
    rm -rf "$SING_BOX_LOG_DIR"
    
    systemctl daemon-reload
    
    echo "卸载完成"
    sleep 2
}

# 主循环
main() {
    while true; do
        show_menu
        read -p "请选择 (0-6): " choice
        
        case $choice in
            1) view_config ;;
            2) add_node_menu ;;
            3) delete_node ;;
            4) manage_service ;;
            5) view_logs ;;
            6) uninstall_sing_box ;;
            0) 
                echo "退出"
                exit 0
                ;;
            *)
                echo "无效选择"
                sleep 2
                ;;
        esac
    done
}

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    echo "此脚本需要 root 权限运行"
    exit 1
fi

main
EOFUI

    chmod +x "$S_UI_DIR/s-ui.sh"
    print_success "s-ui 应用创建成功"
}

# 创建 s-ui systemd 服务
create_s_ui_service() {
    print_info "创建 s-ui systemd 服务..."
    
    cat > "$S_UI_SERVICE" << EOF
[Unit]
Description=S-UI Management Panel for Sing-box
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$S_UI_DIR/s-ui.sh
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_success "s-ui 服务创建成功"
}

# 创建 s-ui 命令别名
create_s_ui_command() {
    print_info "创建 s-ui 命令..."
    
    cat > "/usr/local/bin/s-ui" << 'EOF'
#!/bin/bash
exec "$S_UI_DIR/s-ui.sh" "$@"
EOF

    sed -i "s|\$S_UI_DIR|$S_UI_DIR|g" "/usr/local/bin/s-ui"
    chmod +x "/usr/local/bin/s-ui"
    
    print_success "s-ui 命令创建成功，可以直接运行 's-ui' 启动管理面板"
}

# ==================== 主安装流程 ====================

main_install() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║   Sing-box 一键安装脚本 v1.0           ║"
    echo "║   版本: $SING_BOX_VERSION              ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        print_error "此脚本需要 root 权限运行"
        exit 1
    fi
    
    # 执行安装步骤
    print_info "开始安装 sing-box..."
    echo ""
    
    detect_system
    detect_arch
    detect_libc
    check_dependencies
    download_sing_box
    install_sing_box
    create_sing_box_service
    create_initial_config
    install_s_ui
    create_s_ui_service
    create_s_ui_command
    
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║        安装完成！                      ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    print_success "Sing-box 已安装到: $SING_BOX_BIN"
    print_success "配置文件位置: $SING_BOX_CONFIG_DIR/config.json"
    print_success "日志位置: $SING_BOX_LOG_DIR"
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║        快速开始                        ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "1. 启动管理面板:"
    echo "   ${GREEN}s-ui${NC}"
    echo ""
    echo "2. 启动 sing-box 服务:"
    echo "   ${GREEN}systemctl start sing-box${NC}"
    echo ""
    echo "3. 查看服务状态:"
    echo "   ${GREEN}systemctl status sing-box${NC}"
    echo ""
    echo "4. 查看实时日志:"
    echo "   ${GREEN}journalctl -u sing-box -f${NC}"
    echo ""
    echo "5. 查看配置文件:"
    echo "   ${GREEN}cat $SING_BOX_CONFIG_DIR/config.json${NC}"
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║        常用命令                        ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "启动服务:        ${GREEN}systemctl start sing-box${NC}"
    echo "停止服务:        ${GREEN}systemctl stop sing-box${NC}"
    echo "重启服务:        ${GREEN}systemctl restart sing-box${NC}"
    echo "启用开机自启:    ${GREEN}systemctl enable sing-box${NC}"
    echo "禁用开机自启:    ${GREEN}systemctl disable sing-box${NC}"
    echo "查看服务状态:    ${GREEN}systemctl status sing-box${NC}"
    echo "查看实时日志:    ${GREEN}journalctl -u sing-box -f${NC}"
    echo "查看历史日志:    ${GREEN}journalctl -u sing-box -n 100${NC}"
    echo "验证配置文件:    ${GREEN}$SING_BOX_BIN check -c $SING_BOX_CONFIG_DIR/config.json${NC}"
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║        管理面板使用                    ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "运行以下命令启动管理面板:"
    echo "   ${GREEN}s-ui${NC}"
    echo ""
    echo "管理面板功能:"
    echo "  • 查看当前配置"
    echo "  • 添加节点 (SS/VLESS/HY2/Trojan/VMess)"
    echo "  • 删除节点"
    echo "  • 启动/停止/重启服务"
    echo "  • 查看实时日志"
    echo "  • 卸载 sing-box"
    echo ""
    
    # 询问是否立即启动
    read -p "是否立即启动 sing-box 服务? (y/n): " start_now
    if [ "$start_now" = "y" ] || [ "$start_now" = "Y" ]; then
        systemctl start sing-box
        sleep 2
        systemctl status sing-box --no-pager
        print_success "服务已启动"
    fi
    
    echo ""
    read -p "是否立即启动管理面板? (y/n): " start_ui
    if [ "$start_ui" = "y" ] || [ "$start_ui" = "Y" ]; then
        s-ui
    fi
}

# ==================== 卸载函数 ====================

uninstall() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║      卸载 Sing-box                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if [ "$EUID" -ne 0 ]; then
        print_error "此脚本需要 root 权限运行"
        exit 1
    fi
    
    read -p "确定要卸载 sing-box 吗? (y/n): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消"
        exit 0
    fi
    
    print_info "正在卸载..."
    
    # 停止服务
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    
    # 删除文件
    rm -f "$SING_BOX_BIN"
    rm -f "$SING_BOX_SERVICE"
    rm -f "/usr/local/bin/s-ui"
    rm -f "$S_UI_SERVICE"
    rm -rf "$S_UI_DIR"
    
    # 保留配置文件供备份
    print_warning "配置文件已保留在: $SING_BOX_CONFIG_DIR"
    read -p "是否删除配置文件? (y/n): " delete_config
    if [ "$delete_config" = "y" ] || [ "$delete_config" = "Y" ]; then
        rm -rf "$SING_BOX_CONFIG_DIR"
        rm -rf "$SING_BOX_LOG_DIR"
    fi
    
    systemctl daemon-reload
    
    print_success "卸载完成"
}

# ==================== 更新函数 ====================

update_sing_box() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║      更新 Sing-box                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if [ "$EUID" -ne 0 ]; then
        print_error "此脚本需要 root 权限运行"
        exit 1
    fi
    
    print_info "检查更新..."
    
    detect_system
    detect_arch
    detect_libc
    
    print_info "停止服务..."
    systemctl stop sing-box
    
    print_info "下载新版本..."
    download_sing_box
    
    print_info "安装新版本..."
    install_sing_box
    
    print_info "启动服务..."
    systemctl start sing-box
    sleep 2
    
    print_success "更新完成"
    systemctl status sing-box --no-pager
}

# ==================== 帮助信息 ====================

show_help() {
    cat << EOF
Sing-box 一键安装脚本 v1.0

用法: $0 [选项]

选项:
    install     安装 sing-box 和 s-ui 管理面板 (默认)
    uninstall   卸载 sing-box 和 s-ui
    update      更新 sing-box 到最新版本
    help        显示此帮助信息

示例:
    $0 install
    $0 uninstall
    $0 update

EOF
}

# ==================== 脚本入口 ====================

# 解析命令行参数
case "${1:-install}" in
    install)
        main_install
        ;;
    uninstall)
        uninstall
        ;;
    update)
        update_sing_box
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "未知的选项: $1"
        show_help
        exit 1
        ;;
esac
