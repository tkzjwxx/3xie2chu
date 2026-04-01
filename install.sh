#!/bin/bash
# ====================================================================
# 天网系统 V24 终极解耦版 (纯粹的前端双轨分流路由器)
# ====================================================================
clear
echo -e "\033[1;36m=================================================================\033[0m"
echo -e "\033[1;37m                 🛡️ 天网系统 V24 (纯净双轨路由版) 🛡️\033[0m"
echo -e "\033[1;36m=================================================================\033[0m"
echo -e "\033[1;33m[架构说明]\033[0m 本脚本仅部署 Sing-box 核心作为流量分发路由，绝不碰您的网络底座！"
echo -e "\033[1;32m[轨 1] 全局直通组:\033[0m HY2(8443) / VLESS(10001) / VMess(10002) -> 走系统全局 WARP"
echo -e "\033[1;35m[轨 2] 赛风引流组:\033[0m HY2(8444) / VLESS(10003) / VMess(10004) -> 走本地 40000 Socks5"
echo -e "\033[1;36m-----------------------------------------------------------------\033[0m"
echo -e "  \033[1;32m[1]\033[0m 🚀 部署双轨分流路由器 (Sing-box 核心)"
echo -e "  \033[1;31m[2]\033[0m 🗑️ 彻底卸载前端路由 (绝不影响底层 WARP 及 SOCKS5)"
echo -e "  \033[1;33m[0]\033[0m 🚪 退出"
echo -e "\033[1;36m=================================================================\033[0m"
read -p "👉 请选择操作序号: " menu_choice

if [ "$menu_choice" == "2" ]; then
    echo -e "\n\033[1;31m⚠️ 正在卸载前端分流路由...\033[0m"
    systemctl stop sing-box cloudflared 2>/dev/null
    systemctl disable sing-box cloudflared 2>/dev/null
    pkill -9 -f sing-box; pkill -9 -f cloudflared
    rm -rf /etc/skynet_router /usr/local/bin/cloudflared /usr/bin/st
    rm -f /etc/systemd/system/sing-box.service /etc/systemd/system/cloudflared.service
    systemctl daemon-reload
    sed -i '/precedence ::ffff:0:0\/96/d' /etc/gai.conf 2>/dev/null
    echo -e "\033[1;32m🎉 卸载完毕！系统已恢复纯净。\033[0m"; exit 0
elif [ "$menu_choice" == "0" ]; then exit 0
elif [ "$menu_choice" != "1" ]; then exit 1; fi

clear
echo -e "\033[1;36m🚀 正在执行【双轨前端路由器】初始化...\033[0m"

# 1. 环境准备与 IPv4 优先补丁
systemctl stop sing-box cloudflared 2>/dev/null
pkill -9 -f sing-box 2>/dev/null
rm -rf /etc/skynet_router /usr/bin/st
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget jq openssl net-tools >/dev/null 2>&1
mkdir -p /etc/skynet_router

sed -i '/precedence ::ffff:0:0\/96/d' /etc/gai.conf 2>/dev/null
echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
echo -e "\033[1;32m✅ IPv4 优先补丁已注入，解决纯 IPv6 双栈 DNS 黑洞！\033[0m"

# 2. 检查 40000 端口状态 (仅提示，不阻断)
echo -ne "\n\033[1;33m⏳ 检查本地 40000 端口... \033[0m"
if ! netstat -tlnp 2>/dev/null | grep -q ":40000 "; then
    echo -e "\033[1;31m[未检测到]\033[0m (请确保您用勇哥脚本开启了 40000 的 Socks5 代理)"
else
    echo -e "\033[1;32m[就绪]\033[0m"
fi

# 3. 部署 Sing-box 与生成密钥
echo -e "\n\033[1;33m📦 拉取 Sing-box 核心并生成安全凭证...\033[0m"
curl -sL -o /tmp/sbox.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.10.1/sing-box-1.10.1-linux-amd64.tar.gz"
tar -xzf /tmp/sbox.tar.gz -C /tmp/ 2>/dev/null
mv -f /tmp/sing-box-*/sing-box /etc/skynet_router/sing-box 2>/dev/null
chmod +x /etc/skynet_router/sing-box

openssl req -new -x509 -days 3650 -nodes -out /etc/skynet_router/hy2.crt -keyout /etc/skynet_router/hy2.key -subj "/CN=bing.com" 2>/dev/null
SYS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "d3b2a1a1-5f2a-4a2a-8c2a-1a2a3a4a5a6a")
SYS_PW="TK_$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)"

cat << EOF > /etc/skynet_router/status.env
SYS_UUID="$SYS_UUID"
SYS_PW="$SYS_PW"
D_V1=""
D_M1=""
D_V2=""
D_M2=""
EOF

# 4. 生成双轨 6 节点配置 (核心路由逻辑)
cat << EOF > /etc/skynet_router/config.json
{
  "log": {"level": "warn"},
  "inbounds": [
    { "type": "hysteria2", "tag": "hy2-global", "listen": "::", "listen_port": 8443, "users": [{"password": "$SYS_PW"}], "tls": {"enabled": true, "server_name": "bing.com", "certificate_path": "/etc/skynet_router/hy2.crt", "key_path": "/etc/skynet_router/hy2.key"} },
    { "type": "vless", "tag": "vless-global", "listen": "127.0.0.1", "listen_port": 10001, "users": [{"uuid": "$SYS_UUID"}], "transport": {"type": "ws", "path": "/vg"} },
    { "type": "vmess", "tag": "vmess-global", "listen": "127.0.0.1", "listen_port": 10002, "users": [{"uuid": "$SYS_UUID", "alterId": 0}], "transport": {"type": "ws", "path": "/mg"} },
    
    { "type": "hysteria2", "tag": "hy2-socks", "listen": "::", "listen_port": 8444, "users": [{"password": "$SYS_PW"}], "tls": {"enabled": true, "server_name": "bing.com", "certificate_path": "/etc/skynet_router/hy2.crt", "key_path": "/etc/skynet_router/hy2.key"} },
    { "type": "vless", "tag": "vless-socks", "listen": "127.0.0.1", "listen_port": 10003, "users": [{"uuid": "$SYS_UUID"}], "transport": {"type": "ws", "path": "/vs"} },
    { "type": "vmess", "tag": "vmess-socks", "listen": "127.0.0.1", "listen_port": 10004, "users": [{"uuid": "$SYS_UUID", "alterId": 0}], "transport": {"type": "ws", "path": "/ms"} }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct-out" },
    { "type": "socks", "tag": "socks-out", "server": "127.0.0.1", "server_port": 40000 }
  ],
  "route": {"rules": [ 
    {"inbound": ["hy2-socks", "vless-socks", "vmess-socks"], "outbound": "socks-out"},
    {"inbound": ["hy2-global", "vless-global", "vmess-global"], "outbound": "direct-out"}
  ]}
}
EOF

cat > /etc/systemd/system/sing-box.service << 'EOF'
[Unit]
Description=SkyNet Dual-Track Router
After=network.target
[Service]
ExecStart=/etc/skynet_router/sing-box run -c /etc/skynet_router/config.json
Restart=always
LimitNOFILE=512000
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now sing-box >/dev/null 2>&1

# 5. 构建全景中控面板 (st)
echo -e "\n\033[1;35m🌌 构建双轨大一统面板 (st)...\033[0m"
cat << 'EOF' > /usr/bin/st
#!/bin/bash
APIS=("http://api.ipify.org" "http://icanhazip.com" "http://ifconfig.me/ip" "http://ident.me" "http://checkip.amazonaws.com")

while true; do
    source /etc/skynet_router/status.env
    clear
    echo -e "\033[1;36m==================================================================\033[0m"
    echo -e "\033[1;37m                 🛡️ V24 双轨解耦大一统总控台 🛡️                  \033[0m"
    echo -e "\033[1;36m==================================================================\033[0m"
    
    echo -e "\033[1;35m⏳ 正在扫描双轨 IP，请稍候 (并发测网极速版)...\033[0m"
    
    (
        API=${APIS[$RANDOM % ${#APIS[@]}]}
        TMP_V4=$(curl -s4 -m 5 $API 2>/dev/null | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n 1)
        [ -z "$TMP_V4" ] && echo "超时或无IPv4" > /tmp/skynet_v4.tmp || echo "$TMP_V4" > /tmp/skynet_v4.tmp
    ) &
    
    (
        TMP_V6=$(curl -s6 -m 5 api64.ipify.org 2>/dev/null | grep -E -o "([0-9a-fA-F:]+)" | head -n 1)
        [ -z "$TMP_V6" ] && echo "超时或无IPv6" > /tmp/skynet_v6.tmp || echo "$TMP_V6" > /tmp/skynet_v6.tmp
    ) &
    
    (
        API=${APIS[$RANDOM % ${#APIS[@]}]}
        TMP_SOCKS=$(curl -s4 -m 6 --socks5 127.0.0.1:40000 $API 2>/dev/null | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n 1)
        [ -z "$TMP_SOCKS" ] && echo "未启动或超时" > /tmp/skynet_socks.tmp || echo "$TMP_SOCKS" > /tmp/skynet_socks.tmp
    ) &
    wait

    V4_IP=$(cat /tmp/skynet_v4.tmp 2>/dev/null)
    V6_IP=$(cat /tmp/skynet_v6.tmp 2>/dev/null)
    SOCKS_IP=$(cat /tmp/skynet_socks.tmp 2>/dev/null)

    if netstat -tlnp 2>/dev/null | grep -q ":40000 "; then P_ST="\033[1;32m🟢 40000 端口已连接\033[0m"
    else P_ST="\033[1;31m🔴 40000 端口离线 (请重启您的赛风脚本)\033[0m"; fi

    clear
    echo -e "\033[1;36m==================================================================\033[0m"
    echo -e "\033[1;37m                 🛡️ V24 双轨解耦大一统总控台 🛡️                  \033[0m"
    echo -e "\033[1;36m==================================================================\033[0m"
    echo -e " \033[1;34m>>> 🌐 轨1：系统全局出口 (直连 WARP) <<<\033[0m"
    echo -e "  * 节点: HY2(8443) / VLESS(10001) / VMess(10002)"
    echo -e "  * 当前全局 IPv4: \033[1;37m$V4_IP\033[0m"
    echo -e "  * 当前全局 IPv6: \033[1;37m$V6_IP\033[0m"
    echo -e "------------------------------------------------------------------"
    echo -e " \033[1;35m>>> 🏴 轨2：暗网引流出口 (指向 40000 端口) <<<\033[0m"
    echo -e "  * 节点: HY2(8444) / VLESS(10003) / VMess(10004)"
    echo -e "  * 底座状态侦测 : $P_ST"
    echo -e "  * 赛风分流 IP  : \033[1;32m$SOCKS_IP\033[0m"
    echo -e "------------------------------------------------------------------"
    echo -e " \033[1;33m>>> ⚙️ 系统功能库 <<<\033[0m"
    echo -e "  [\033[1;36m1\033[0m] ☁️ 部署 Argo 隧道并录入 4 个专属域名"
    echo -e "  [\033[1;36m2\033[0m] 🔗 \033[1;32m一键生成并提取双轨 6大节点链接 (支持批量纯净复制)\033[0m"
    echo -e "  [\033[1;36m3\033[0m] 📜 追踪 Sing-box 流量分发路由日志"
    echo -e "  [\033[1;36m0\033[0m] 🚪 退出面板"
    echo -e "\033[1;36m==================================================================\033[0m"
    
    read -p "👉 请输入指令 (0-3): " CMD
    case $CMD in
        1)
            clear
            echo -e "\033[1;36m==================================================================\033[0m"
            echo -e "\033[1;32m                 ☁️ Argo 隧道自动化部署向导                 \033[0m"
            echo -e "\033[1;36m==================================================================\033[0m"
            echo -e "\033[1;33m【第一步：部署 Argo 隧道 (已装可直接回车跳过)】\033[0m"
            read -p "🔑 请在此粘贴 CF 提供的 Install Token 指令并回车: " RAW_INPUT
            ARGO_TOKEN=$(echo "$RAW_INPUT" | grep -oE 'eyJ[A-Za-z0-9_\-\.]+')
            
            if [ -n "$ARGO_TOKEN" ]; then
                echo -e "\033[1;35m⏳ 正在拉取并注册 Argo 系统服务...\033[0m"
                systemctl stop cloudflared 2>/dev/null; rm -f /usr/local/bin/cloudflared
                curl -sL -o /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x /usr/local/bin/cloudflared
                /usr/local/bin/cloudflared service install "$ARGO_TOKEN" >/dev/null 2>&1
                systemctl enable --now cloudflared >/dev/null 2>&1
                echo -e "\033[1;32m🎉 Argo 部署完毕！\033[0m\n"
            fi
            
            echo -e "\033[1;33m【第二步：录入 4 个专属子域名】\033[0m"
            echo -e " \033[1;37m(请先去 CF 后台，把四个域名分别映射给 localhost 的 10001~10004 端口)\033[0m"
            read -p "👉 [轨1-全局] 录入 VLESS (10001) 域名: " IN_1
            [ -n "$IN_1" ] && sed -i "s/^D_V1=.*/D_V1=\"$IN_1\"/" /etc/skynet_router/status.env
            read -p "👉 [轨1-全局] 录入 VMess (10002) 域名: " IN_2
            [ -n "$IN_2" ] && sed -i "s/^D_M1=.*/D_M1=\"$IN_2\"/" /etc/skynet_router/status.env
            read -p "👉 [轨2-赛风] 录入 VLESS (10003) 域名: " IN_3
            [ -n "$IN_3" ] && sed -i "s/^D_V2=.*/D_V2=\"$IN_3\"/" /etc/skynet_router/status.env
            read -p "👉 [轨2-赛风] 录入 VMess (10004) 域名: " IN_4
            [ -n "$IN_4" ] && sed -i "s/^D_M2=.*/D_M2=\"$IN_4\"/" /etc/skynet_router/status.env
            
            echo -e "\n\033[1;32m✅ 域名录入完毕！请按 2 提取节点！\033[0m"
            read -n 1 -s -r -p "按任意键返回主菜单..."
            ;;
        2)
            source /etc/skynet_router/status.env
            IP=$(cat /tmp/skynet_v6.tmp 2>/dev/null)
            if [[ "$IP" == *"超时"* ]] || [[ -z "$IP" ]]; then
                IP=$(ip -6 addr show scope global | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n 1)
            fi
            [ -z "$IP" ] && IP="获取IPv6失败_请手动替换"
            
            gen_vmess() { echo "vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$1\",\"add\":\"$2\",\"port\":\"443\",\"id\":\"$SYS_UUID\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$2\",\"path\":\"$3\",\"tls\":\"tls\"}" | base64 -w 0)"; }
            
            clear
            echo -e "\033[1;36m==================================================================\033[0m"
            echo -e " \033[1;34m>>> 🌐 轨1：系统全局直通组 (原生/全局 WARP 出口) <<<\033[0m"
            echo -e " 🟣 \033[1;35mHY2   (端口 8443)\033[0m: \033[40;32m hysteria2://$SYS_PW@[$IP]:8443/?sni=bing.com&insecure=1#Global-HY2 \033[0m"
            echo -e " 🔵 \033[1;35mVLESS (Argo CDN)\033[0m: \033[40;32m vless://$SYS_UUID@${D_V1}:443?encryption=none&security=tls&sni=${D_V1}&type=ws&host=${D_V1}&path=%2Fvg#Global-VLESS \033[0m"
            echo -e " 🟡 \033[1;35mVMess (Argo CDN)\033[0m: \033[40;32m $(gen_vmess "Global-VMess" "${D_M1}" "/mg") \033[0m"
            echo -e "\n------------------------------------------------------------------"
            echo -e " \033[1;31m>>> 🏴 轨2：赛风暗网引流组 (40000 端口极品 IP 出口) <<<\033[0m"
            echo -e " 🟣 \033[1;35mHY2   (端口 8444)\033[0m: \033[40;32m hysteria2://$SYS_PW@[$IP]:8444/?sni=bing.com&insecure=1#Socks-HY2 \033[0m"
            echo -e " 🔵 \033[1;35mVLESS (Argo CDN)\033[0m: \033[40;32m vless://$SYS_UUID@${D_V2}:443?encryption=none&security=tls&sni=${D_V2}&type=ws&host=${D_V2}&path=%2Fvs#Socks-VLESS \033[0m"
            echo -e " 🟡 \033[1;35mVMess (Argo CDN)\033[0m: \033[40;32m $(gen_vmess "Socks-VMess" "${D_M2}" "/ms") \033[0m"
            echo -e "\033[1;36m==================================================================\033[0m"
            
            echo -e "\n\033[1;33m👇👇👇 [批量复制区域：请直接全选下方全部代码] 👇👇👇\033[0m\033[0m"
            echo "hysteria2://$SYS_PW@[$IP]:8443/?sni=bing.com&insecure=1#Global-HY2"
            echo "vless://$SYS_UUID@${D_V1}:443?encryption=none&security=tls&sni=${D_V1}&type=ws&host=${D_V1}&path=%2Fvg#Global-VLESS"
            echo "$(gen_vmess "Global-VMess" "${D_M1}" "/mg")"
            echo "hysteria2://$SYS_PW@[$IP]:8444/?sni=bing.com&insecure=1#Socks-HY2"
            echo "vless://$SYS_UUID@${D_V2}:443?encryption=none&security=tls&sni=${D_V2}&type=ws&host=${D_V2}&path=%2Fvs#Socks-VLESS"
            echo "$(gen_vmess "Socks-VMess" "${D_M2}" "/ms")"
            echo -e "\033[1;33m👆👆👆 [批量复制区域结束] 👆👆👆\033[0m"
            
            echo ""
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        3) echo -e "\033[1;36m📜 追踪前端分流底层日志 (Ctrl+C 退出)...\033[0m"; journalctl -u sing-box --no-pager --output cat -f -n 50 ;;
        0) clear; exit 0 ;;
        *) echo -e "\033[1;31m❌ 无效指令！\033[0m"; sleep 1 ;;
    esac
done
EOF
chmod +x /usr/bin/st

echo -e "\n\033[1;32m🎉 天网系统 V24 部署完毕！轻量级双轨分流器已上线！\033[0m"
echo -e "\033[1;37m👉 请在终端输入 \033[1;33mst\033[1;37m 呼出面板，享受极致稳定的分流体验！\033[0m"
