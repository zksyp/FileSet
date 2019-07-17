# !/bin/bash

install_docker() {
    echo "未安装docker，现在开始安装================================="
    apt-get update < /dev/tty
    apt-get install curl -y < /dev/tty
    curl -fsSL get.docker.com -o get-docker.sh
    chmod +x get-docker.sh
    sh get-docker.sh
    rm -rf get-docker.sh
    if [[ -z $(which docker) ]]; then
        echo "error: docker安装失败"
        exit 0
    fi
}

install_docker_compose() {
    echo "未安装docker-compose，现在开始安装========================="
    apt-get update < /dev/tty
    apt-get install docker-compose -y < /dev/tty
    if [[ -z $(which docker-compose) ]]; then
        echo "error: docker-compose安装失败"
        exit 0
    fi
}

read -p "你的域名：" domain

if [[ -z $(which docker) ]]; then
    install_docker
fi

if [[ -z $(which docker-compose) ]]; then
    install_docker_compose
fi

docker-compose -f docker/acme.sh/docker-compose.yml up -d
docker exec acme.sh acme.sh --issue -d $domain --standalone -k ec-256
docker exec acme.sh acme.sh --installcert -d $domain --fullchainpath /acme/out/v2ray.crt --keypath /acme/out/v2ray.key --ecc

uuid=`cat /proc/sys/kernel/random/uuid`
cat << EOF > docker/v2ray/config.json
{
    "inbounds": [
        {
            "port": 10001,
            "listen": "0.0.0.0",
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "alterId": 64
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/ray"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF

cat << EOF > docker/v2ray/nginx/conf.d/default.conf 
server {
    listen 443 ssl;
    server_name $domain;

    ssl on;
    ssl_certificate /etc/v2ray/ssl/v2ray.crt;
    ssl_certificate_key /etc/v2ray/ssl/v2ray.key;
    ssl_protocols         TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers           HIGH:!aNULL:!MD5;

    location /ray {
        proxy_redirect off;
        proxy_pass http://v2ray:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;

        # Show realip in v2ray access.log
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

docker network create --driver bridge v2ray_bridge
cd docker/v2ray && docker-compose up -d

echo "========================================="
echo "v2ray服务器配置完成"
echo "你的uuid是$uuid"
echo "========================================="

