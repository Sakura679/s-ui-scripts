# s-ui-scripts
## 仅仅使用singbox
```bash
bash <(curl -Ls https://raw.githubusercontent.com/Sakura679/s-ui-scripts/main/singbox_install.sh)
```
## 📋 使用说明
### 一、快速安装
```bash
# 一键安装
bash <(curl -Ls https://raw.githubusercontent.com/Sakura679/s-ui-scripts/main/s-ui_install.sh)
```


```bash
# 下载脚本
curl -O https://raw.githubusercontent.com/Sakura679/s-ui-scripts/main/s-ui_install.sh

# 或使用 wget
wget https://raw.githubusercontent.com/Sakura679/s-ui-scripts/main/s-ui_install.sh

# 赋予执行权限
chmod +x s-ui_install.sh

# 执行安装
sudo bash s-ui_install.sh
```
### 二、管理面板使用
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
### 三、支持的节点类型
1. Shadowsocks (SS)
加密方式: aes-128-gcm, aes-256-gcm, chacha20-poly1305
配置示例：
```json
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": 12123,
      "method": "aes-256-gcm",
      "password": "Iq6NSSXsU5GypaQYlQaJ4e9P40zTb7mHmv4tynH5qHY="
    }
```
2. VLESS
支持 TCP/TLS
配置示例：
```json
    {
      "type": "vless",
      "tag": "reality-in",
      "listen": "::",
      "listen_port": 12123,

      "users": [
        {
          "uuid": "26800d23-57be-40b0-8fbd-b9edc0194082",
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

          "private_key": "cP-CQW7_ltG-dStdp10eKzTPOcv_o3YYeqdD5HZC10Q",

          "short_id": [
            "db1df8"
          ]
        }
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
      "listen": "::",
      "listen_port": 12123,

      "users": [
        {
          "password": "/31/ZomnpGLMMaIJjDg/ppDb"
        }
      ],

      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/server.crt",
        "key_path": "/etc/sing-box/server.key"
      }
    }
```
### 四、常用命令
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
### 五、配置文件位置
主配置文件: `/etc/sing-box/config.json`
日志文件: `/var/log/sing-box/`
二进制文件: `/usr/local/bin/sing-box`
Systemd 服务: `/etc/systemd/system/sing-box.service`
管理面板: `/opt/s-ui/`
### 六、手动编辑配置
```bash
# 编辑配置文件
sudo nano /etc/sing-box/config.json

# 验证配置
sudo sing-box check -c /etc/sing-box/config.json

# 重启服务应用配置
sudo systemctl restart sing-box
```

