#!/bin/bash

# Sing-box 1.14.0-alpha.35 一键安装脚本
# 支持系统: Debian, Ubuntu, CentOS, Alpine, Fedora
# 支持 init 系统: systemd 和 OpenRC

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置变量
SING_BOX_VERSION="1.14.0-alpha.35"
WORK_DIR="/etc/sing-box"
TEMP_DIR="/tmp/sing-box-install"
GITHUB_PROXY="https://github.com"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
OPENRC_SERVICE_FILE="/etc/init.d/sing-box"
INIT_SYSTEM=""  # 将在检测时设置

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查是否为 root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以 root 身份运行"
    fi
}

# 检测系统
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        log_error "无法检测系统类型"
    fi
    
    log_info "检测到系统: $OS $VER"
}

# 检测 init 系统
detect_init_system() {
    if command -v systemctl &> /dev/null; then
        INIT_SYSTEM="systemd"
        log_info "检测到 init 系统: systemd"
    elif command -v rc-service &> /dev/null; then
        INIT_SYSTEM="openrc"
        log_info "检测到 init 系统: OpenRC"
    else
        log_error "无法检测 init 系统，既不支持 systemd 也不支持 OpenRC"
    fi
}

# 检测架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH_NAME="amd64"
            ;;
        aarch64)
            ARCH_NAME="arm64"
            ;;
        armv7l)
            ARCH_NAME="armv7"
            ;;
        *)
            log_error "不支持的架构: $ARCH"
            ;;
    esac
    
    log_info "检测到架构: $ARCH ($ARCH_NAME)"
}

# 安装依赖
install_dependencies() {
    log_info "安装依赖..."
    
    case $OS in
        debian|ubuntu)
            apt-get update
            apt-get install -y wget curl tar gzip openssl
            ;;
        centos|rhel|fedora)
            yum install -y wget curl tar gzip openssl
            ;;
        alpine)
            apk update
            apk add --no-cache wget curl tar gzip openssl
            ;;
        *)
            log_warn "未知系统，跳过依赖安装"
            ;;
    esac
}

# 创建工作目录
create_directories() {
    log_info "创建工作目录..."
    mkdir -p "$WORK_DIR"
    mkdir -p "$TEMP_DIR"
    mkdir -p "$WORK_DIR/conf"
    mkdir -p "$WORK_DIR/logs"
}

# 下载 Sing-box
download_singbox() {
    log_info "下载 Sing-box $SING_BOX_VERSION..."
    
    # 确定下载文件名
    case $OS in
        alpine)
            FILENAME="sing-box-${SING_BOX_VERSION}-linux-${ARCH_NAME}-musl.tar.gz"
            ;;
        *)
            FILENAME="sing-box-${SING_BOX_VERSION}-linux-${ARCH_NAME}.tar.gz"
            ;;
    esac
    
    DOWNLOAD_URL="${GITHUB_PROXY}/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/${FILENAME}"
    
    log_info "下载地址: $DOWNLOAD_URL"
    
    cd "$TEMP_DIR"
    if ! wget "$DOWNLOAD_URL" -O "$FILENAME"; then
        log_error "下载失败，请检查网络连接"
    fi
    
    log_info "解压文件..."
    tar -xzf "$FILENAME" -C "$WORK_DIR" --strip-components=1
    
    chmod +x "$WORK_DIR/sing-box"
    log_info "Sing-box 已安装到 $WORK_DIR/sing-box"
}

# 创建基础配置文件
create_config() {
    log_info "创建配置文件..."
    
    cat > "$WORK_DIR/conf/config.json" << 'EOF'
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

    log_info "生成自签证书"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/sing-box/server.key -out /etc/sing-box/server.crt -subj "/CN=bing.com" -days 36500
    
    log_info "配置文件已创建"
}

# 创建 systemd 服务文件
create_systemd_service() {
    log_info "创建 systemd 服务..."
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Sing-box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=$WORK_DIR/sing-box run -C $WORK_DIR/conf
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    chmod 644 "$SERVICE_FILE"
    log_info "Systemd 服务已创建"
}

# 创建 OpenRC 服务文件
create_openrc_service() {
    log_info "创建 OpenRC 服务..."
    
    cat > "$OPENRC_SERVICE_FILE" << 'EOF'
#!/sbin/openrc-run

description="Sing-box Service"
command="/etc/sing-box/sing-box"
command_args="run -C /etc/sing-box/conf"
pidfile="/run/sing-box.pid"
command_background="true"

depend() {
    need net
}

start_pre() {
    mkdir -p /run/sing-box
}

stop() {
    ebegin "Stopping ${RC_SVCNAME}"
    start-stop-daemon --stop --pidfile "${pidfile}" --exec "${command}"
    eend $?
}
EOF
    
    chmod +x "$OPENRC_SERVICE_FILE"
    log_info "OpenRC 服务已创建"
}

# 启动服务 (systemd)
start_service_systemd() {
    log_info "启动 Sing-box 服务 (systemd)..."
    
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box
    
    sleep 2
    
    if systemctl is-active --quiet sing-box; then
        log_info "Sing-box 服务已启动"
    else
        log_error "Sing-box 服务启动失败"
    fi
}

# 启动服务 (OpenRC)
start_service_openrc() {
    log_info "启动 Sing-box 服务 (OpenRC)..."
    
    rc-update add sing-box default
    rc-service sing-box start
    
    sleep 2
    
    if rc-service sing-box status > /dev/null 2>&1; then
        log_info "Sing-box 服务已启动"
    else
        log_error "Sing-box 服务启动失败"
    fi
}

# 启动服务 (通用)
start_service() {
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        start_service_systemd
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        start_service_openrc
    fi
}

# 显示状态 (systemd)
show_status_systemd() {
    log_info "Sing-box 版本信息:"
    "$WORK_DIR/sing-box" version
    
    log_info "服务状态:"
    systemctl status sing-box --no-pager
    
    log_info "配置文件位置: $WORK_DIR/conf/config.json"
    log_info "日志文件位置: $WORK_DIR/logs/"
}

# 显示状态 (OpenRC)
show_status_openrc() {
    log_info "Sing-box 版本信息:"
    "$WORK_DIR/sing-box" version
    
    log_info "服务状态:"
    rc-service sing-box status
    
    log_info "配置文件位置: $WORK_DIR/conf/config.json"
    log_info "日志文件位置: $WORK_DIR/logs/"
}

# 显示状态 (通用)
show_status() {
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        show_status_systemd
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        show_status_openrc
    fi
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    rm -rf "$TEMP_DIR"
}

# 显示使用说明 (systemd)
show_usage_systemd() {
    cat << EOF

${GREEN}=== Sing-box 安装完成 ===${NC}

${YELLOW}常用命令 (systemd):${NC}
  启动服务:   systemctl start sing-box
  停止服务:   systemctl stop sing-box
  重启服务:   systemctl restart sing-box
  查看状态:   systemctl status sing-box
  查看日志:   journalctl -u sing-box -f

${YELLOW}文件位置:${NC}
  可执行文件: $WORK_DIR/sing-box
  配置文件:   $WORK_DIR/conf/config.json
  日志目录:   $WORK_DIR/logs/

${YELLOW}版本信息:${NC}
  Sing-box 版本: $SING_BOX_VERSION

${YELLOW}下一步:${NC}
  1. 编辑配置文件: nano $WORK_DIR/conf/config.json
  2. 重启服务: systemctl restart sing-box
  3. 查看日志: journalctl -u sing-box -f

EOF
}

# 显示使用说明 (OpenRC)
show_usage_openrc() {
    cat << EOF

${GREEN}=== Sing-box 安装完成 ===${NC}

${YELLOW}常用命令 (OpenRC):${NC}
  启动服务:   rc-service sing-box start
  停止服务:   rc-service sing-box stop
  重启服务:   rc-service sing-box restart
  查看状态:   rc-service sing-box status
  查看日志:   tail -f /var/log/messages

${YELLOW}文件位置:${NC}
  可执行文件: $WORK_DIR/sing-box
  配置文件:   $WORK_DIR/conf/config.json
  日志目录:   $WORK_DIR/logs/
  服务脚本:   $OPENRC_SERVICE_FILE

${YELLOW}版本信息:${NC}
  Sing-box 版本: $SING_BOX_VERSION

${YELLOW}下一步:${NC}
  1. 编辑配置文件: nano $WORK_DIR/conf/config.json
  2. 重启服务: rc-service sing-box restart
  3. 查看日志: tail -f /var/log/messages

EOF
}

# 显示使用说明 (通用)
show_usage() {
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        show_usage_systemd
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        show_usage_openrc
    fi
}

# 卸载函数 (systemd)
uninstall_systemd() {
    log_warn "卸载 Sing-box (systemd)..."
    
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    rm -rf "$WORK_DIR"
    
    log_info "Sing-box 已卸载"
}

# 卸载函数 (OpenRC)
uninstall_openrc() {
    log_warn "卸载 Sing-box (OpenRC)..."
    
    rc-service sing-box stop 2>/dev/null || true
    rc-update del sing-box default 2>/dev/null || true
    rm -f "$OPENRC_SERVICE_FILE"
    rm -rf "$WORK_DIR"
    
    log_info "Sing-box 已卸载"
}

# 卸载函数 (通用)
uninstall() {
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        uninstall_systemd
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        uninstall_openrc
    fi
}

# 主函数
main() {
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════╗"
    echo "║   Sing-box 1.14.0-alpha.35 安装脚本   ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # 检查参数
    if [ "$1" = "uninstall" ]; then
        check_root
        detect_system
        detect_init_system
        uninstall
        exit 0
    fi
    
    check_root
    detect_system
    detect_init_system
    detect_arch
    install_dependencies
    create_directories
    download_singbox
    create_config
    
    # 根据 init 系统创建相应的服务文件
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        create_systemd_service
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        create_openrc_service
    fi
    
    start_service
    show_status
    cleanup
    show_usage
    
    log_info "安装完成！"
}

# 运行主函数
main "$@"
