# s-ui-scripts
## 📋 使用说明
### 一、快速安装
```bash
# 下载脚本
curl -O https://raw.githubusercontent.com/SagerNet/sing-box/main/install.sh

# 或使用 wget
wget https://raw.githubusercontent.com/SagerNet/sing-box/main/install.sh

# 赋予执行权限
chmod +x install.sh

# 执行安装
sudo bash install.sh
```
### 二、安装选项
```bash
# 安装 (默认)
sudo bash install.sh install

# 卸载
sudo bash install.sh uninstall

# 更新
sudo bash install.sh update

# 显示帮助
sudo bash install.sh help
```
### 三、管理面板使用
安装完成后，运行以下命令启动管理面板：

```bash
s-ui
```
管理面板功能菜单：
```
╔════════════════════════════════════════╗
║       Sing-box 节点管理面板 (S-UI)     ║
╚════════════════════════════════════════╝

1. 查看配置          - 查看当前 JSON 配置
2. 添加节点          - 支持多种协议
3. 删除节点          - 删除已配置的节点
4. 启动/停止/重启    - 管理服务
5. 查看日志          - 实时日志查看
6. 卸载 sing-box     - 完全卸载
0. 退出
```
### 四、支持的节点类型
1. Shadowsocks (SS)
加密方式: aes-128-gcm, aes-256-gcm, chacha20-poly1305
配置示例：
```json
{
  "type": "shadowsocks",
  "tag": "ss-in",
  "listen": "0.0.0.0",
  "listen_port": 8388,
  "method": "aes-256-gcm",
  "password": "your-password"
}
```
2. VLESS
支持 TCP/TLS
配置示例：
```json
{
  "type": "vless",
  "tag": "vless-in",
  "listen": "0.0.0.0",
  "listen_port": 443,
  "users": [
    {
      "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    }
  ],
  "tls": {
    "enabled": true,
    "certificate_path": "/path/to/cert.pem",
    "key_path": "/path/to/key.pem"
  }
}
```
3. Hysteria2 (HY2)
高性能协议
配置示例：
```json
{
  "type": "hysteria2",
  "tag": "hy2-in",
  "listen": "0.0.0.0",
  "listen_port": 443,
  "users": [
    {
      "password": "your-password"
    }
  ],
  "tls": {
    "enabled": true,
    "certificate_path": "/path/to/cert.pem",
    "key_path": "/path/to/key.pem"
  }
}
```
4. Trojan
配置示例：
```json
{
  "type": "trojan",
  "tag": "trojan-in",
  "listen": "0.0.0.0",
  "listen_port": 443,
  "users": [
    {
      "password": "your-password"
    }
  ],
  "tls": {
    "enabled": true,
    "certificate_path": "/path/to/cert.pem",
    "key_path": "/path/to/key.pem"
  }
}
```
5. VMess
配置示例：
```json
{
  "type": "vmess",
  "tag": "vmess-in",
  "listen": "0.0.0.0",
  "listen_port": 8001,
  "users": [
    {
      "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "security": "auto"
    }
  ]
}
```
### 五、常用命令
```bash
# 启动服务
systemctl start sing-box

# 停止服务
systemctl stop sing-box

# 重启服务
systemctl restart sing-box

# 启用开机自启
systemctl enable sing-box

# 禁用开机自启
systemctl disable sing-box

# 查看服务状态
systemctl status sing-box

# 查看实时日志
journalctl -u sing-box -f

# 查看最近 100 行日志
journalctl -u sing-box -n 100

# 验证配置文件
sing-box check -c /etc/sing-box/config.json

# 查看 sing-box 版本
sing-box version

# 启动管理面板
s-ui
```
### 六、配置文件位置
主配置文件: `/etc/sing-box/config.json`
日志文件: `/var/log/sing-box/`
二进制文件: `/usr/local/bin/sing-box`
Systemd 服务: `/etc/systemd/system/sing-box.service`
管理面板: `/opt/s-ui/`
### 七、手动编辑配置
```bash
# 编辑配置文件
sudo nano /etc/sing-box/config.json

# 验证配置
sudo sing-box check -c /etc/sing-box/config.json

# 重启服务应用配置
sudo systemctl restart sing-box
```
### 八、故障排查
查看详细错误日志
```bash
journalctl -u sing-box -n 50 --no-pager
```
检查端口占用
```bash
# 检查特定端口
netstat -tlnp | grep :8388

# 或使用 ss
ss -tlnp | grep :8388
```
验
