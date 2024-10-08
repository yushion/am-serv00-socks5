#!/bin/bash

# 定义颜色
re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

UUID="951eaa92-b679-4cd7-b85a-151210150ec9"

CFWORKERS_DOMAIN="http://ssh.auto.cloudns.ch"
ORIGINRULES_DOMAIN="vmess1.mic.x10.mx"

ARGO_DOMAIN="vmess.mic.x10.mx"
ARGO_AUTH="eyJhIjoiYWE3ODEyOGM0NDgzNjFiMWNkYTVjZjdkYjgwM2UwZmEiLCJ0IjoiZTdiMGQzNDctMTAyMC00NjJlLWEzNDAtOWFkZDU5Y2IyNjNmIiwicyI6Ik5qY3hNamMzT0RVdE9ETTVNQzAwTjJJMkxUZ3dZMk10WkRnd1pqZGlZVE0zWXpneiJ9"
CF_TUNNEL="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"

# Generating Configuration Files
GeneratingFiles_Config() {
  cat > config.json << EOF
{
  "log": {
    "disabled": true,
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8",
        "strategy": "ipv4_only",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "rule_set": [
          "geosite-openai"
        ],
        "server": "wireguard"
      },
      {
        "rule_set": [
          "geosite-netflix"
        ],
        "server": "wireguard"
      },
      {
        "rule_set": [
          "geosite-category-ads-all"
        ],
        "server": "block"
      }
    ],
    "final": "google",
    "strategy": "",
    "disable_cache": false,
    "disable_expire": false
  },
    "inbounds": [
    {
      "tag": "vmess-ws-in",
      "type": "vmess",
      "listen": "::",
      "listen_port": ${VMESS_PORT},
      "users": [
      {
        "uuid": "${UUID}"
      }
    ],
    "transport": {
      "type": "ws",
      "path": "/vmess",
      "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    }
 ],
    "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    },
    {
      "type": "wireguard",
      "tag": "wireguard-out",
      "server": "162.159.195.142",
      "server_port": 4198,
      "local_address": [
        "172.16.0.2/32",
        "2606:4700:110:83c7:b31f:5858:b3a8:c6b1/128"
      ],
      "private_key": "mPZo+V9qlrMGCZ7+E6z2NI6NOV34PD++TpAR09PtCWI=",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": [
        26,
        21,
        228
      ]
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      },
      {
        "rule_set": [
          "geosite-openai"
        ],
        "outbound": "wireguard-out"
      },
      {
        "rule_set": [
          "geosite-netflix"
        ],
        "outbound": "wireguard-out"
      },
      {
        "rule_set": [
          "geosite-category-ads-all"
        ],
        "outbound": "block"
      }
    ],
    "rule_set": [
      {
        "tag": "geosite-netflix",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-netflix.srs",
        "download_detour": "direct"
      },
      {
        "tag": "geosite-openai",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/openai.srs",
        "download_detour": "direct"
      },      
      {
        "tag": "geosite-category-ads-all",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs",
        "download_detour": "direct"
      }
    ],
    "final": "direct"
   },
   "experimental": {
      "cache_file": {
      "path": "cache.db",
      "cache_id": "mycacheid",
      "store_fakeip": true
    }
  }
}
EOF
}

# 获取端口
VMESS_PORT=$(curl -s ${CFWORKERS_DOMAIN}/getport?user=[username] | jq -r '.port')
echo "VMESS_PORT 代理端口号: ${VMESS_PORT}"
if [ -z "$VMESS_PORT" ] || [ "$VMESS_PORT" = "null" ]; then
	VMESS_PORT=$(curl -s ${CFWORKERS_DOMAIN}/loginAction?user=[username] | jq -r '.port')  # 重新开通新端口
	echo "VMESS_PORT 重新开通新代理端口号: ${VMESS_PORT}"
	if [ -z "$VMESS_PORT" ] || [ "$VMESS_PORT" = "null" ]; then
		echo "错误: 未能获取重新开通新的 SOCKS5 端口。"
		exit 0
	fi
fi


USER=$(whoami)
WORKDIR="/home/${USER}/.vmess"
mkdir -p "$WORKDIR"
chmod 777 "$WORKDIR"
cd $WORKDIR

pid=$(pgrep -x "web")
if [ -z "$pid" ]; then
	echo "web is not running!"
	if [ ! -f "${WORKDIR}/web" ]; then
 		echo "web will downloading..."
		wget -q -O "${WORKDIR}/web" "https://github.com/ansoncloud8/am-serv00-vmess/releases/download/1.0.0/amd64-web"
	fi
 	chmod 777 "${WORKDIR}/web"
	GeneratingFiles_Config
	nohup ${WORKDIR}/web run -c config.json >/dev/null 2>&1 &
	sleep 2
	pgrep -x "web" > /dev/null && green "web is running..." || { red "web is not running, restarting..."; pkill -x "web" && nohup ./web run -c config.json >/dev/null 2>&1 & sleep 2; purple "web restarted"; }
fi

pid=$(pgrep -x "cftunnel")
if [ -z "$pid" ]; then
	echo "cftunnel is not running!"
	if [ ! -f "${WORKDIR}/web" ]; then
 		echo "cftunnel will downloading..."
		wget -q -O "${WORKDIR}/cftunnel" "https://github.com/ansoncloud8/am-serv00-vmess/releases/download/1.0.0/amd64-bot"
		
	fi
 	chmod 777 "${WORKDIR}/cftunnel"	
	nohup ${WORKDIR}/cftunnel ${CF_TUNNEL} >/dev/null 2>&1 &
	sleep 2
	pgrep -x "cftunnel" > /dev/null && green "cftunnel is running..." || { red "cftunnel is not running, restarting..."; pkill -x "cftunnel" && nohup ${WORKDIR}/cftunnel ${CF_TUNNEL} >/dev/null 2>&1 & sleep 2; purple "cftunnel restarted"; }
fi

GeneratingFiles_List(){
# get ip
IP=$(curl -s ipv4.ip.sb || { ipv6=$(curl -s --max-time 1 ipv6.ip.sb); echo "[$ipv6]"; })
echo $IP;
sleep 1

# get ipinfo
# ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"_"$30}' | sed -e 's/ /_/g') 
ISP=$(curl -s https://speed.cloudflare.com/meta | jq -r '"\(.country)_\(.city)"')
sleep 1

cat > list.txt <<EOF
vmess://$(echo "{ \"v\": \"2\", \"ps\": \"$ISP\", \"add\": \"$IP\", \"port\": \"${VMESS_PORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"\", \"path\": \"/vmess?ed=2048\", \"tls\": \"\", \"sni\": \"\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)

vmess://$(echo "{ \"v\": \"2\", \"ps\": \"$ISP\", \"add\": \"chat.com\", \"port\": \"80\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ORIGINRULES_DOMAIN}\", \"path\": \"/vmess?ed=2048\", \"tls\": \"\", \"sni\": \"\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)

vmess://$(echo "{ \"v\": \"2\", \"ps\": \"$ISP\", \"add\": \"www.visa.com\", \"port\": \"443\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"/vmess?ed=2048\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)
EOF
}
pid=$(pgrep -x "web")
if [ -n "$pid" ]; then
	echo "web:${pid} is running..."
	pid=$(pgrep -x "cftunnel")
	if [ -n "$pid" ]; then
 		echo "cftunnel:${pid} is running..."
 		sleep 1
   		GeneratingFiles_List
     
		vmessList=$(cat ${WORKDIR}/list.txt)
		vmessList=$(jq -sRr @uri <<< "$vmessList")
		vmessList=$(sed 's/%5Cn/%0A/g' <<< "$vmessList")
  		curl -s "${CFWORKERS_DOMAIN}/setsocks5?user=[username]&socks5=$vmessList"
		purple "list.txt saved successfully, Running done!"
		sleep 3 
	else
 		red "cftunnel is not running!";
	fi
else
	red "web is not running!";
fi
