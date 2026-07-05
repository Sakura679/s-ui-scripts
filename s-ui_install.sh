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
    mkdir -p ./singbox
    tar -xzf "${FILENAME}" -C /tmp/singbox --strip-components=1

    cd ./singbox
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
    echo "║          v1.0 - 改进版                ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "1. 查看配置"
    echo "2. 添加节点"
    echo "3. 删除节点"
    echo "4. 编辑节点"
    echo "5. 启动/停止/重启服务"
    echo "6. 查看日志"
    echo "7. 验证配置"
    echo "8. 导出节点配置"
    echo "9. 卸载 sing-box"
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

# 生成随机 UUID
generate_uuid() {
    python3 << 'EOFPYTHON'
import uuid
print(str(uuid.uuid4()))
EOFPYTHON
}

# 生成随机密码 (Base64 编码)
generate_password() {
    python3 << 'EOFPYTHON'
import base64
import os
password = base64.b64encode(os.urandom(32)).decode('utf-8')
print(password)
EOFPYTHON
}

# 生成 Reality 公钥和私钥
generate_reality_keys() {
    python3 << 'EOFPYTHON'
import subprocess
import json
import os

try:
    # 使用 sing-box 生成 reality 密钥对
    result = subprocess.run(['/usr/local/bin/sing-box', 'generate', 'reality-keypair'], 
                          capture_output=True, text=True)
    if result.returncode == 0:
        output = json.loads(result.stdout)
        print(f"{output['private_key']}|{output['public_key']}")
    else:
        # 备用方案：生成随机密钥
        import base64
        private_key = base64.b64encode(os.urandom(32)).decode('utf-8')
        public_key = base64.b64encode(os.urandom(32)).decode('utf-8')
        print(f"{private_key}|{public_key}")
except Exception as e:
    print(f"Error: {e}", file=__import__('sys').stderr)
EOFPYTHON
}

# 生成随机 short_id
generate_short_id() {
    python3 << 'EOFPYTHON'
import secrets
short_id = secrets.token_hex(3)
print(short_id)
EOFPYTHON
}

add_ss_node() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║      添加 Shadowsocks 节点             ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    read -p "请输入节点标签 (tag): " ss_tag
    read -p "请输入监听地址 (默认 0.0.0.0): " ss_listen
    ss_listen=${ss_listen:-0.0.0.0}
    read -p "请输入监听端口: " ss_port
    
    echo ""
    echo "加密方式选项:"
    echo "  1. aes-128-gcm"
    echo "  2. aes-256-gcm (推荐)"
    echo "  3. chacha20-poly1305"
    read -p "请选择加密方式 (1-3, 默认 2): " cipher_choice
    
    case $cipher_choice in
        1) ss_cipher="aes-128-gcm" ;;
        3) ss_cipher="chacha20-poly1305" ;;
        *) ss_cipher="aes-256-gcm" ;;
    esac
    
    echo ""
    echo "是否使用混淆插件? (y/n)"
    read -p "选择 (默认 n): " use_plugin
    
    local plugin_config=""
    if [ "$use_plugin" = "y" ] || [ "$use_plugin" = "Y" ]; then
        read -p "请输入混淆域名 (如: gw.alicdn.com): " plugin_opts
        plugin_config=$(cat <<EOFPLUGIN
  "plugin": "obfs-local",
  "plugin_opts": "$plugin_opts",
EOFPLUGIN
)
    fi
    
    # 自动生成密码
    ss_password=$(generate_password)
    
    local ss_config=$(cat <<EOF
{
  "type": "shadowsocks",
  "tag": "$ss_tag",
  "listen": "$ss_listen",
  "listen_port": $ss_port,
  "method": "$ss_cipher",
  "password": "$ss_password"
  $plugin_config
}
EOF
)
    
    add_inbound_to_config "$ss_config"
    
    echo ""
    print_success "Shadowsocks 节点添加成功"
    echo "╔════════════════════════════════════════╗"
    echo "║         节点信息                       ║"
    echo "╚════════════════════════════════════════╝"
    echo "  标签: $ss_tag"
    echo "  地址: $ss_listen:$ss_port"
    echo "  加密: $ss_cipher"
    echo "  密码: $ss_password"
    if [ -n "$plugin_opts" ]; then
        echo "  混淆: $plugin_opts"
    fi
    echo ""
    echo "客户端配置:"
    echo "  \"server\": \"$ss_listen\","
    echo "  \"server_port\": $ss_port,"
    echo "  \"method\": \"$ss_cipher\","
    echo "  \"password\": \"$ss_password\""
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
    read -p "请输入监听地址 (默认 0.0.0.0): " vless_listen
    vless_listen=${vless_listen:-0.0.0.0}
    read -p "请输入监听端口: " vless_port
    
    # 自动生成 UUID
    vless_uuid=$(generate_uuid)
    
    echo ""
    echo "传输协议选项:"
    echo "  1. TCP (默认)"
    echo "  2. WS (WebSocket)"
    echo "  3. gRPC"
    read -p "请选择传输协议 (1-3, 默认 1): " transport_choice
    
    case $transport_choice in
        2) transport_type="ws" ;;
        3) transport_type="grpc" ;;
        *) transport_type="tcp" ;;
    esac
    
    echo ""
    echo "是否启用 TLS? (y/n)"
    read -p "选择 (默认 y): " use_tls
    use_tls=${use_tls:-y}
    
    local tls_config=""
    local flow_config=""
    
    if [ "$use_tls" = "y" ] || [ "$use_tls" = "Y" ]; then
        echo ""
        echo "TLS 模式选项:"
        echo "  1. 标准 TLS"
        echo "  2. Reality (推荐)"
        read -p "请选择 TLS 模式 (1-2, 默认 1): " tls_mode
        
        if [ "$tls_mode" = "2" ]; then
            # Reality 模式
            read -p "请输入 SNI (如: gw.alicdn.com): " reality_sni
            
            echo "正在生成 Reality 密钥对..."
            reality_keys=$(generate_reality_keys)
            reality_private_key=$(echo $reality_keys | cut -d'|' -f1)
            reality_public_key=$(echo $reality_keys | cut -d'|' -f2)
            
            reality_short_id=$(generate_short_id)
            
            tls_config=$(cat <<EOFTLS
    "tls": {
      "enabled": true,
      "server_name": "$reality_sni",
      "reality": {
        "enabled": true,
        "private_key": "$reality_private_key",
        "short_id": "$reality_short_id"
      },
      "utls": {
        "enabled": true,
        "fingerprint": "chrome"
      }
    },
EOFTLS
)
            
            flow_config=$(cat <<EOFFLOW
  "flow": "xtls-rprx-vision",
EOFFLOW
)
            
        else
            # 标准 TLS 模式
            read -p "请输入 SNI (如: example.com): " tls_sni
            read -p "请输入证书路径 (如: /etc/sing-box/cert.pem): " cert_path
            read -p "请输入密钥路径 (如: /etc/sing-box/key.pem): " key_path
            
            tls_config=$(cat <<EOFTLS
    "tls": {
      "enabled": true,
      "server_name": "$tls_sni",
      "certificate_path": "$cert_path",
      "key_path": "$key_path"
    },
EOFTLS
)
        fi
    fi
    
    # 构建传输配置
    local transport_config=""
    if [ "$transport_type" = "ws" ]; then
        read -p "请输入 WebSocket 路径 (默认 /): " ws_path
        ws_path=${ws_path:-/}
        transport_config=$(cat <<EOFWS
  "transport": {
    "type": "ws",
    "path": "$ws_path"
  },
EOFWS
)
    elif [ "$transport_type" = "grpc" ]; then
        read -p "请输入 gRPC 服务名 (默认 grpc): " grpc_service
        grpc_service=${grpc_service:-grpc}
        transport_config=$(cat <<EOFGRPC
  "transport": {
    "type": "grpc",
    "service_name": "$grpc_service"
  },
EOFGRPC
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
  $transport_config
  $tls_config
  $flow_config
}
EOF
)
    
    add_inbound_to_config "$vless_config"
    
    echo ""
    print_success "VLESS 节点添加成功"
    echo "╔════════════════════════════════════════╗"
    echo "║         节点信息                       ║"
    echo "╚════════════════════════════════════════╝"
    echo "  标签: $vless_tag"
    echo "  地址: $vless_listen:$vless_port"
    echo "  UUID: $vless_uuid"
    echo "  传输: $transport_type"
    if [ -n "$tls_config" ]; then
        echo "  TLS: 已启用"
        if [ "$tls_mode" = "2" ]; then
            echo "  模式: Reality"
            echo "  SNI: $reality_sni"
            echo "  公钥: $reality_public_key"
            echo "  Short ID: $reality_short_id"
        else
            echo "  模式: 标准 TLS"
            echo "  SNI: $tls_sni"
        fi
    fi
    echo ""
    echo "客户端配置:"
    echo "  \"server\": \"$vless_listen\","
    echo "  \"server_port\": $vless_port,"
    echo "  \"uuid\": \"$vless_uuid\","
    if [ "$tls_mode" = "2" ]; then
        echo "  \"tls\": {"
        echo "    \"enabled\": true,"
        echo "    \"server_name\": \"$reality_sni\","
        echo "    \"reality\": {"
        echo "      \"enabled\": true,"
        echo "      \"public_key\": \"$reality_public_key\","
        echo "      \"short_id\": \"$reality_short_id\""
        echo "    }"
        echo "  },"
        echo "  \"flow\": \"xtls-rprx-vision\""
    fi
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
    read -p "请输入监听地址 (默认 0.0.0.0): " hy2_listen
    hy2_listen=${hy2_listen:-0.0.0.0}
    read -p "请输入监听端口: " hy2_port
    
    # 自动生成密码
    hy2_password=$(generate_password)
    
    echo ""
    echo "是否启用 TLS? (y/n)"
    read -p "选择 (默认 y): " use_tls
    use_tls=${use_tls:-y}
    
    local tls_config=""
    
    if [ "$use_tls" = "y" ] || [ "$use_tls" = "Y" ]; then
        read -p "请输入 SNI (如: bing.com): " hy2_sni
        read -p "请输入证书路径 (如: /etc/sing-box/cert.pem): " hy2_cert
        read -p "请输入密钥路径 (如: /etc/sing-box/key.pem): " hy2_key
        
        echo ""
        echo "是否忽略证书验证? (y/n)"
        read -p "选择 (默认 n): " insecure
        
        if [ "$insecure" = "y" ] || [ "$insecure" = "Y" ]; then
            insecure_flag="true"
        else
            insecure_flag="false"
        fi
        
        tls_config=$(cat <<EOFTLS
  "tls": {
    "enabled": true,
    "server_name": "$hy2_sni",
    "certificate_path": "$hy2_cert",
    "key_path": "$hy2_key",
    "insecure": $insecure_flag
  },
EOFTLS
)
    fi
    
    # 可选：上行/下行速率限制
    echo ""
    echo "是否设置速率限制? (y/n)"
    read -p "选择 (默认 n): " set_rate_limit
    
    local rate_config=""
    if [ "$set_rate_limit" = "y" ] || [ "$set_rate_limit" = "Y" ]; then
        read -p "请输入上行速率 (Mbps, 如: 100): " up_mbps
        read -p "请输入下行速率 (Mbps, 如: 100): " down_mbps
        
        rate_config=$(cat <<EOFRATE
  "up_mbps": $up_mbps,
  "down_mbps": $down_mbps,
EOFRATE
)
    fi
    
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
  ]
  $rate_config
  $tls_config
}
EOF
)
    
    add_inbound_to_config "$hy2_config"
    
    echo ""
    print_success "Hysteria2 节点添加成功"
    echo "╔════════════════════════════════════════╗"
    echo "║         节点信息                       ║"
    echo "╚════════════════════════════════════════╝"
    echo "  标签: $hy2_tag"
    echo "  地址: $hy2_listen:$hy2_port"
    echo "  密码: $hy2_password"
    if [ -n "$tls_config" ]; then
        echo "  TLS: 已启用"
        echo "  SNI: $hy2_sni"
        echo "  证书验证: $insecure_flag"
    fi
    if [ -n "$rate_config" ]; then
        echo "  上行: ${up_mbps}Mbps"
        echo "  下行: ${down_mbps}Mbps"
    fi
    echo ""
    echo "客户端配置:"
    echo "  \"server\": \"$hy2_listen\","
    echo "  \"server_port\": $hy2_port,"
    echo "  \"password\": \"$hy2_password\","
    echo "  \"tls\": {"
    echo "    \"enabled\": true,"
    echo "    \"server_name\": \"$hy2_sni\","
    echo "    \"insecure\": $insecure_flag"
    echo "  }"
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
    read -p "请输入监听地址 (默认 0.0.0.0): " trojan_listen
    trojan_listen=${trojan_listen:-0.0.0.0}
    read -p "请输入监听端口: " trojan_port
    
    # 自动生成密码
    trojan_password=$(generate_password)
    
    echo ""
    read -p "请输入 SNI (如: example.com): " trojan_sni
    read -p "请输入证书路径 (如: /etc/sing-box/cert.pem): " trojan_cert
    read -p "请输入密钥路径 (如: /etc/sing-box/key.pem): " trojan_key
    
    echo ""
    echo "是否启用 ALPN? (y/n)"
    read -p "选择 (默认 y): " use_alpn
    use_alpn=${use_alpn:-y}
    
    local alpn_config=""
    if [ "$use_alpn" = "y" ] || [ "$use_alpn" = "Y" ]; then
        alpn_config=$(cat <<EOFALPN
    "alpn": ["h2", "http/1.1"],
EOFALPN
)
    fi
    
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
    "server_name": "$trojan_sni",
    "certificate_path": "$trojan_cert",
    "key_path": "$trojan_key"
    $alpn_config
  }
}
EOF
)
    
    add_inbound_to_config "$trojan_config"
    
    echo ""
    print_success "Trojan 节点添加成功"
    echo "╔════════════════════════════════════════╗"
    echo "║         节点信息                       ║"
    echo "╚════════════════════════════════════════╝"
    echo "  标签: $trojan_tag"
    echo "  地址: $trojan_listen:$trojan_port"
    echo "  密码: $trojan_password"
    echo "  SNI: $trojan_sni"
    if [ "$use_alpn" = "y" ] || [ "$use_alpn" = "Y" ]; then
        echo "  ALPN: h2, http/1.1"
    fi
    echo ""
    echo "客户端配置:"
    echo "  \"server\": \"$trojan_listen\","
    echo "  \"server_port\": $trojan_port,"
    echo "  \"password\": \"$trojan_password\","
    echo "  \"tls\": {"
    echo "    \"enabled\": true,"
    echo "    \"server_name\": \"$trojan_sni\""
    echo "  }"
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
    read -p "请输入监听地址 (默认 0.0.0.0): " vmess_listen
    vmess_listen=${vmess_listen:-0.0.0.0}
    read -p "请输入监听端口: " vmess_port
    
    # 自动生成 UUID
    vmess_uuid=$(generate_uuid)
    
    echo ""
    echo "加密方式选项:"
    echo "  1. auto (推荐)"
    echo "  2. aes-128-gcm"
    echo "  3. chacha20-poly1305"
    echo "  4. none"
    read -p "请选择加密方式 (1-4, 默认 1): " cipher_choice
    
    case $cipher_choice in
        2) vmess_cipher="aes-128-gcm" ;;
        3) vmess_cipher="chacha20-poly1305" ;;
        4) vmess_cipher="none" ;;
        *) vmess_cipher="auto" ;;
    esac
    
    echo ""
    echo "传输协议选项:"
    echo "  1. TCP (默认)"
    echo "  2. WS (WebSocket)"
    echo "  3. HTTP"
    echo "  4. gRPC"
    read -p "请选择传输协议 (1-4, 默认 1): " transport_choice
    
    local transport_config=""
    
    case $transport_choice in
        2)
            transport_type="ws"
            read -p "请输入 WebSocket 路径 (默认 /): " ws_path
            ws_path=${ws_path:-/}
            read -p "请输入 WebSocket 主机 (可选): " ws_host
            
            transport_config=$(cat <<EOFWS
  "transport": {
    "type": "ws",
    "path": "$ws_path"
EOFWS
)
            if [ -n "$ws_host" ]; then
                transport_config="$transport_config,
    \"host\": \"$ws_host\""
            fi
            transport_config="$transport_config
  },"
            ;;
        3)
            transport_type="http"
            read -p "请输入 HTTP 路径 (默认 /): " http_path
            http_path=${http_path:-/}
            read -p "请输入 HTTP 主机 (可选): " http_host
            
            transport_config=$(cat <<EOFHTTP
  "transport": {
    "type": "http",
    "path": "$http_path"
EOFHTTP
)
            if [ -n "$http_host" ]; then
                transport_config="$transport_config,
    \"host\": \"$http_host\""
            fi
            transport_config="$transport_config
  },"
            ;;
        4)
            transport_type="grpc"
            read -p "请输入 gRPC 服务名 (默认 grpc): " grpc_service
            grpc_service=${grpc_service:-grpc}
            
            transport_config=$(cat <<EOFGRPC
  "transport": {
    "type": "grpc",
    "service_name": "$grpc_service"
  },
EOFGRPC
)
            ;;
        *)
            transport_type="tcp"
            ;;
    esac
    
    echo ""
    echo "是否启用 TLS? (y/n)"
    read -p "选择 (默认 n): " use_tls
    
    local tls_config=""
    
    if [ "$use_tls" = "y" ] || [ "$use_tls" = "Y" ]; then
        read -p "请输入 SNI (如: example.com): " vmess_sni
        read -p "请输入证书路径 (如: /etc/sing-box/cert.pem): " vmess_cert
        read -p "请输入密钥路径 (如: /etc/sing-box/key.pem): " vmess_key
        
        tls_config=$(cat <<EOFTLS
  "tls": {
    "enabled": true,
    "server_name": "$vmess_sni",
    "certificate_path": "$vmess_cert",
    "key_path": "$vmess_key"
  },
EOFTLS
)
    fi
    
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
  $transport_config
  $tls_config
}
EOF
)
    
    add_inbound_to_config "$vmess_config"
    
    echo ""
    print_success "VMess 节点添加成功"
    echo "╔════════════════════════════════════════╗"
    echo "║         节点信息                       ║"
    echo "╚════════════════════════════════════════╝"
    echo "  标签: $vmess_tag"
    echo "  地址: $vmess_listen:$vmess_port"
    echo "  UUID: $vmess_uuid"
    echo "  加密: $vmess_cipher"
    echo "  传输: $transport_type"
    if [ -n "$tls_config" ]; then
        echo "  TLS: 已启用"
        echo "  SNI: $vmess_sni"
    fi
    echo ""
    echo "客户端配置:"
    echo "  \"server\": \"$vmess_listen\","
    echo "  \"server_port\": $vmess_port,"
    echo "  \"uuid\": \"$vmess_uuid\","
    echo "  \"security\": \"$vmess_cipher\""
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
    python3 << 'EOFPYTHON'
import json
import sys

try:
    with open('/etc/sing-box/config.json', 'r') as f:
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
    
    with open('/etc/sing-box/config.json', 'r') as f:
        config = json.load(f)
    
    inbounds = config.get('inbounds', [])
    
    if 0 <= node_index < len(inbounds):
        deleted = inbounds.pop(node_index)
        
        with open('/etc/sing-box/config.json', 'w') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        print(f"已删除节点: {deleted.get('tag', '未命名')}")
    else
        print("无效的节点序号")
        sys.exit(1)
except Exception as e:
    print(f"错误: {e}", file=sys.stderr)
    sys.exit(1)
EOFPYTHON
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

edit_node() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         编辑节点                       ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    # 列出所有节点
    python3 << 'EOFPYTHON'
import json

try:
    with open('/etc/sing-box/config.json', 'r') as f:
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
    
    read -p "请输入要编辑的节点序号 (0 取消): " node_index
    
    if [ "$node_index" = "0" ]; then
        return
    fi
    
    python3 << EOFPYTHON
import json
import sys

try:
    node_index = $node_index - 1
    
    with open('/etc/sing-box/config.json', 'r') as f:
        config = json.load(f)
    
    inbounds = config.get('inbounds', [])
    
    if 0 <= node_index < len(inbounds):
        node = inbounds[node_index]
        print(f"\n节点详情:")
        print(json.dumps(node, indent=2, ensure_ascii=False))
    else:
        print("无效的节点序号")
        sys.exit(1)
except Exception as e:
    print(f"错误: {e}", file=sys.stderr)
    sys.exit(1)
EOFPYTHON
    
    echo ""
    echo "提示: 直接编辑配置文件可获得更好的编辑体验"
    echo "配置文件路径: /etc/sing-box/config.json"
    echo ""
    read -p "是否用 nano 编辑器打开配置文件? (y/n): " edit_choice
    
    if [ "$edit_choice" = "y" ] || [ "$edit_choice" = "Y" ]; then
        nano /etc/sing-box/config.json
        
        # 验证配置
        echo ""
        echo "正在验证配置..."
        if /usr/local/bin/sing-box check -c /etc/sing-box/config.json > /dev/null 2>&1; then
            print_success "配置验证成功"
            
            echo ""
            read -p "是否重启服务以应用更改? (y/n): " restart_choice
            if [ "$restart_choice" = "y" ] || [ "$restart_choice" = "Y" ]; then
                systemctl restart sing-box
                print_success "服务已重启"
            fi
        else
            print_error "配置验证失败，请检查配置文件"
        fi
    fi
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

manage_service() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║       Sing-box 服务管理                ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    # 检查服务状态
    if systemctl is-active --quiet sing-box; then
        echo "服务状态: ✓ 运行中"
        echo ""
        echo "1. 停止服务"
        echo "2. 重启服务"
        echo "3. 查看实时日志"
        echo "0. 返回"
        echo ""
        read -p "请选择 (0-3): " service_choice
        
        case $service_choice in
            1)
                systemctl stop sing-box
                print_success "服务已停止"
                ;;
            2)
                systemctl restart sing-box
                print_success "服务已重启"
                ;;
            3)
                journalctl -u sing-box -f
                ;;
            0)
                return
                ;;
            *)
                echo "无效选择"
                ;;
        esac
    else
        echo "服务状态: ✗ 已停止"
        echo ""
        echo "1. 启动服务"
        echo "2. 启用开机自启"
        echo "0. 返回"
        echo ""
        read -p "请选择 (0-2): " service_choice
        
        case $service_choice in
            1)
                systemctl start sing-box
                print_success "服务已启动"
                ;;
            2)
                systemctl enable sing-box
                print_success "已启用开机自启"
                ;;
            0)
                return
                ;;
            *)
                echo "无效选择"
                ;;
        esac
    fi
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

view_logs() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         Sing-box 日志查看              ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "1. 查看最近 50 行日志"
    echo "2. 查看最近 100 行日志"
    echo "3. 实时查看日志 (按 Ctrl+C 退出)"
    echo "4. 查看错误日志"
    echo "0. 返回"
    echo ""
    read -p "请选择 (0-4): " log_choice
    
    case $log_choice in
        1)
            journalctl -u sing-box -n 50
            ;;
        2)
            journalctl -u sing-box -n 100
            ;;
        3)
            journalctl -u sing-box -f
            ;;
        4)
            journalctl -u sing-box -p err
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

validate_config() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         配置文件验证                   ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if [ ! -f "$SING_BOX_CONFIG_DIR/config.json" ]; then
        print_error "配置文件不存在"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    echo "正在验证配置文件..."
    echo ""
    
    if /usr/local/bin/sing-box check -c "$SING_BOX_CONFIG_DIR/config.json" > /tmp/sing-box-check.log 2>&1; then
        print_success "配置文件验证成功 ✓"
        echo ""
        echo "配置摘要:"
        python3 << 'EOFPYTHON'
import json

try:
    with open('/etc/sing-box/config.json', 'r') as f:
        config = json.load(f)
    
    inbounds = config.get('inbounds', [])
    outbounds = config.get('outbounds', [])
    
    print(f"入站节点数: {len(inbounds)}")
    print(f"出站节点数: {len(outbounds)}")
    print("")
    print("入站节点:")
    for inbound in inbounds:
        tag = inbound.get('tag', '未命名')
        node_type = inbound.get('type', '未知')
        port = inbound.get('listen_port', 'N/A')
        print(f"  - [{node_type}] {tag} (端口: {port})")
    
    print("")
    print("出站节点:")
    for outbound in outbounds:
        tag = outbound.get('tag', '未命名')
        node_type = outbound.get('type', '未知')
        print(f"  - [{node_type}] {tag}")
        
except Exception as e:
    print(f"错误: {e}")
EOFPYTHON
    else
        print_error "配置文件验证失败 ✗"
        echo ""
        echo "错误信息:"
        cat /tmp/sing-box-check.log
    fi
    
    echo ""
    read -p "按 Enter 返回菜单..."
}

export_nodes() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         导出节点配置                   ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if [ ! -f "$SING_BOX_CONFIG_DIR/config.json" ]; then
        print_error "配置文件不存在"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    echo "导出格式选项:"
    echo "1. JSON 格式 (完整配置)"
    echo "2. 客户端配置 (仅节点信息)"
    echo "3. 分享链接 (sing-box URI)"
    echo "0. 返回"
    echo ""
    read -p "请选择 (0-3): " export_choice
    
    case $export_choice in
        1)
            export_json_config
            ;;
        2)
            export_client_config
            ;;
        3)
            export_share_links
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

export_json_config() {
    echo ""
    echo "正在导出 JSON 配置..."
    
    local export_file="/tmp/sing-box-config-$(date +%Y%m%d-%H%M%S).json"
    
    cp "$SING_BOX_CONFIG_DIR/config.json" "$export_file"
    
    print_success "配置已导出到: $export_file"
    echo ""
    echo "您可以使用以下命令下载:"
    echo "  scp root@<服务器IP>:$export_file ."
}

export_client_config() {
    echo ""
    echo "正在生成客户端配置..."
    
    python3 << 'EOFPYTHON'
import json
from datetime import datetime

try:
    with open('/etc/sing-box/config.json', 'r') as f:
        config = json.load(f)
    
    inbounds = config.get('inbounds', [])
    
    client_config = {
        "version": 1,
        "export_time": datetime.now().isoformat(),
        "nodes": []
    }
    
    for inbound in inbounds:
        node = {
            "tag": inbound.get('tag', '未命名'),
            "type": inbound.get('type', '未知'),
            "server": inbound.get('listen', '0.0.0.0'),
            "server_port": inbound.get('listen_port', 0)
        }
        
        # 根据节点类型添加特定信息
        node_type = inbound.get('type', '')
        
        if node_type == 'shadowsocks':
            users = inbound.get('users', [{}])
            if users:
                node['method'] = inbound.get('method', 'aes-256-gcm')
                node['password'] = users[0].get('password', '')
                
        elif node_type == 'vless':
            users = inbound.get('users', [{}])
            if users:
                node['uuid'] = users[0].get('uuid', '')
            node['transport'] = inbound.get('transport', {}).get('type', 'tcp')
            
            tls = inbound.get('tls', {})
            if tls.get('enabled'):
                node['tls'] = {
                    'enabled': True,
                    'server_name': tls.get('server_name', '')
                }
                if tls.get('reality'):
                    node['tls']['reality'] = {
                        'enabled': True,
                        'public_key': tls['reality'].get('public_key', ''),
                        'short_id': tls['reality'].get('short_id', '')
                    }
        
        elif node_type == 'hysteria2':
            users = inbound.get('users', [{}])
            if users:
                node['password'] = users[0].get('password', '')
            
            tls = inbound.get('tls', {})
            if tls.get('enabled'):
                node['tls'] = {
                    'enabled': True,
                    'server_name': tls.get('server_name', '')
                }
        
        elif node_type == 'trojan':
            users = inbound.get('users', [{}])
            if users:
                node['password'] = users[0].get('password', '')
            
            tls = inbound.get('tls', {})
            if tls.get('enabled'):
                node['tls'] = {
                    'enabled': True,
                    'server_name': tls.get('server_name', '')
                }
        
        elif node_type == 'vmess':
            users = inbound.get('users', [{}])
            if users:
                node['uuid'] = users[0].get('uuid', '')
                node['security'] = users[0].get('security', 'auto')
            node['transport'] = inbound.get('transport', {}).get('type', 'tcp')
        
        client_config['nodes'].append(node)
    
    export_file = f"/tmp/sing-box-client-config-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    with open(export_file, 'w') as f:
        json.dump(client_config, f, indent=2, ensure_ascii=False)
    
    print(f"客户端配置已导出到: {export_file}")
    print("")
    print("配置内容:")
    print(json.dumps(client_config, indent=2, ensure_ascii=False))
    
except Exception as e:
    print(f"错误: {e}")
EOFPYTHON
}

export_share_links() {
    echo ""
    echo "正在生成分享链接..."
    echo ""
    
    python3 << 'EOFPYTHON'
import json
import base64
import urllib.parse

try:
    with open('/etc/sing-box/config.json', 'r') as f:
        config = json.load(f)
    
    inbounds = config.get('inbounds', [])
    
    print("分享链接:")
    print("")
    
    for inbound in inbounds:
        node_type = inbound.get('type', '')
        tag = inbound.get('tag', '未命名')
        server = inbound.get('listen', '0.0.0.0')
        port = inbound.get('listen_port', 0)
        
        if node_type == 'shadowsocks':
            users = inbound.get('users', [{}])
            if users:
                method = inbound.get('method', 'aes-256-gcm')
                password = users[0].get('password', '')
                
                # SS URI 格式: ss://method:password@server:port#tag
                userinfo = f"{method}:{password}"
                userinfo_b64 = base64.b64encode(userinfo.encode()).decode()
                uri = f"ss://{userinfo_b64}@{server}:{port}#{urllib.parse.quote(tag)}"
                print(f"[SS] {tag}")
                print(f"  {uri}")
                print("")
        
        elif node_type == 'vless':
            users = inbound.get('users', [{}])
            if users:
                uuid = users[0].get('uuid', '')
                transport = inbound.get('transport', {}).get('type', 'tcp')
                tls = inbound.get('tls', {})
                
                # VLESS URI 格式
                uri = f"vless://{uuid}@{server}:{port}"
                params = {
                    'type': transport,
                    'encryption': 'none'
                }
                
                if tls.get('enabled'):
                    params['security'] = 'tls'
                    params['sni'] = tls.get('server_name', '')
                    
                    if tls.get('reality'):
                        params['reality'] = '1'
                        params['pbk'] = tls['reality'].get('public_key', '')
                        params['sid'] = tls['reality'].get('short_id', '')
                
                query_string = '&'.join([f"{k}={v}" for k, v in params.items()])
                uri = f"{uri}?{query_string}#{urllib.parse.quote(tag)}"
                
                print(f"[VLESS] {tag}")
                print(f"  {uri}")
                print("")
        
        elif node_type == 'hysteria2':
            users = inbound.get('users', [{}])
            if users:
                password = users[0].get('password', '')
                
                # Hysteria2 URI 格式
                uri = f"hy2://{password}@{server}:{port}"
                params = {}
                
                tls = inbound.get('tls', {})
                if tls.get('enabled'):
                    params['sni'] = tls.get('server_name', '')
                
                if params:
                    query_string = '&'.join([f"{k}={v}" for k, v in params.items()])
                    uri = f"{uri}?{query_string}"
                
                uri = f"{uri}#{urllib.parse.quote(tag)}"
                
                print(f"[Hysteria2] {tag}")
                print(f"  {uri}")
                print("")
        
        elif node_type == 'trojan':
            users = inbound.get('users', [{}])
            if users:
                password = users[0].get('password', '')
                
                # Trojan URI 格式
                uri = f"trojan://{password}@{server}:{port}"
                params = {}
                
                tls = inbound.get('tls', {})
                if tls.get('enabled'):
                    params['sni'] = tls.get('server_name', '')
                
                if params:
                    query_string = '&'.join([f"{k}={v}" for k, v in params.items()])
                    uri = f"{uri}?{query_string}"
                
                uri = f"{uri}#{urllib.parse.quote(tag)}"
                
                print(f"[Trojan] {tag}")
                print(f"  {uri}")
                print("")
        
        elif node_type == 'vmess':
            users = inbound.get('users', [{}])
            if users:
                uuid = users[0].get('uuid', '')
                security = users[0].get('security', 'auto')
                transport = inbound.get('transport', {}).get('type', 'tcp')
                
                # VMess URI 格式 (base64 编码的 JSON)
                vmess_config = {
                    "v": "2",
                    "ps": tag,
                    "add": server,
                    "port": port,
                    "id": uuid,
                    "aid": 0,
                    "scy": security,
                    "net": transport,
                    "type": "none"
                }
                
                vmess_json = json.dumps(vmess_config, separators=(',', ':'))
                vmess_b64 = base64.b64encode(vmess_json.encode()).decode()
                uri = f"vmess://{vmess_b64}"
                
                print(f"[VMess] {tag}")
                print(f"  {uri}")
                print("")

except Exception as e:
    print(f"错误: {e}")
EOFPYTHON
}

uninstall_singbox() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║       卸载 Sing-box                    ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "警告: 此操作将卸载 Sing-box 并删除所有配置"
    echo ""
    read -p "确认卸载? (输入 'yes' 确认): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "已取消卸载"
        echo ""
        read -p "按 Enter 返回菜单..."
        return
    fi
    
    echo ""
    echo "正在卸载..."
    
    # 停止服务
    systemctl stop sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null
    
    # 删除二进制文件
    rm -f /usr/local/bin/sing-box
    
    # 删除 systemd 服务文件
    rm -f /etc/systemd/system/sing-box.service
    systemctl daemon-reload
    
    # 删除配置目录
    read -p "是否删除配置文件? (y/n): " delete_config
    if [ "$delete_config" = "y" ] || [ "$delete_config" = "Y" ]; then
        rm -rf /etc/sing-box
    fi
    
    print_success "Sing-box 已卸载"
    echo ""
    read -p "按 Enter 返回菜单..."
}

# 主循环
main() {
    while true; do
        show_menu
        read -p "请选择 (0-9): " choice
        
        case $choice in
            1)
                view_config
                ;;
            2)
                add_node_menu
                ;;
            3)
                delete_node
                ;;
            4)
                edit_node
                ;;
            5)
                manage_service
                ;;
            6)
                view_logs
                ;;
            7)
                validate_config
                ;;
            8)
                export_nodes
                ;;
            9)
                uninstall_singbox
                ;;
            0)
                clear
                echo "感谢使用 Sing-box 管理面板"
                echo "再见！"
                exit 0
                ;;
            *)
                echo "无效选择，请重试"
                sleep 2
                ;;
        esac
    done
}

# 检查是否以 root 身份运行
if [ "$EUID" -ne 0 ]; then
    print_error "此脚本必须以 root 身份运行"
    echo "请使用: sudo bash $0"
    exit 1
fi

# 检查依赖
check_dependencies

# 检查 Sing-box 是否已安装
if ! command -v /usr/local/bin/sing-box &> /dev/null; then
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║    Sing-box 未安装，正在安装...        ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    install_singbox
fi

# 启动主菜单
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
