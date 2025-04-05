#!/bin/bash

# --- 配置 ---
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
TARGET_API_URL="https://generativelanguage.googleapis.com/v1beta/models/"

# --- 颜色定义 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- 辅助函数 ---
function print_info {
    echo -e "${GREEN}[信息] $1${NC}"
}

function print_warning {
    echo -e "${YELLOW}[警告] $1${NC}"
}

function print_error {
    echo -e "${RED}[错误] $1${NC}"
}

function check_root {
    if [[ $EUID -ne 0 ]]; then
       print_error "此脚本需要以 root 权限运行。请使用 'sudo ./setup_gemini_proxy.sh' 运行。"
       exit 1
    fi
}

function check_nginx {
    if ! command -v nginx &> /dev/null; then
        print_error "未找到 Nginx。请先安装 Nginx (例如: 'sudo apt update && sudo apt install nginx' 或 'sudo yum install nginx')。"
        exit 1
    fi
    print_info "检测到 Nginx 已安装。"
}

# --- 主逻辑 ---
clear
print_info "欢迎使用 Google Gemini API Nginx 反向代理配置脚本"
print_warning "--------------------------------------------------"
print_warning "重要提示:"
print_warning "1. API Key 安全: 强烈建议让客户端在请求时提供 API Key (通过 Header 或 URL 参数)。"
print_warning "   脚本生成的配置默认不包含 API Key，您需要在客户端请求中添加它。"
print_warning "   如果您选择在 Nginx 配置中添加 Key (不推荐)，请务必保护好配置文件的安全。"
print_warning "2. HTTPS: 强烈建议为您的代理启用 HTTPS，以保护通信安全。"
print_warning "--------------------------------------------------"
echo

# 1. 检查权限和 Nginx
check_root
check_nginx
echo

# 2. 获取用户输入
read -p "请输入您的服务器域名或公共 IP 地址: " server_name
while [[ -z "$server_name" ]]; do
    print_warning "服务器域名或 IP 地址不能为空。"
    read -p "请输入您的服务器域名或公共 IP 地址: " server_name
done

read -p "请输入您希望在服务器上访问 Gemini 的路径前缀 (必须以 / 开头和结尾, 例如 /gemini/): " proxy_location
# 验证路径格式
while ! [[ "$proxy_location" =~ ^/.*\/$ ]]; do
    print_warning "路径前缀格式无效。必须以 / 开头和结尾 (例如 /gemini/ )。"
    read -p "请重新输入路径前缀: " proxy_location
done

config_file_name="gemini-proxy-${server_name//./_}.conf" # 基于域名/IP生成文件名
config_file_path="${NGINX_SITES_AVAILABLE}/${config_file_name}"
link_path="${NGINX_SITES_ENABLED}/${config_file_name}"

read -p "是否需要配置 HTTPS (需要您准备好 SSL 证书)? (y/n, 默认 n): " use_https
use_https=$(echo "$use_https" | tr '[:upper:]' '[:lower:]') # 转小写

ssl_cert_path=""
ssl_key_path=""
listen_directive="listen 80;"
ssl_config_block=""

if [[ "$use_https" == "y" ]]; then
    listen_directive="listen 443 ssl http2;"
    print_info "已选择启用 HTTPS。"
    while [[ -z "$ssl_cert_path" ]]; do
        read -p "请输入 SSL 证书文件的完整路径 (例如 /etc/letsencrypt/live/yourdomain.com/fullchain.pem): " ssl_cert_path
        if [[ -z "$ssl_cert_path" ]]; then
            print_warning "证书路径不能为空。"
        # 可选：添加文件存在性检查
        # elif [[ ! -f "$ssl_cert_path" ]]; then
        #     print_warning "找不到证书文件: $ssl_cert_path"
        #     ssl_cert_path=""
        fi
    done
     while [[ -z "$ssl_key_path" ]]; do
        read -p "请输入 SSL 私钥文件的完整路径 (例如 /etc/letsencrypt/live/yourdomain.com/privkey.pem): " ssl_key_path
         if [[ -z "$ssl_key_path" ]]; then
            print_warning "私钥路径不能为空。"
        # 可选：添加文件存在性检查
        # elif [[ ! -f "$ssl_key_path" ]]; then
        #     print_warning "找不到私钥文件: $ssl_key_path"
        #     ssl_key_path=""
        fi
    done

    # 构建 SSL 配置块
    ssl_config_block=$(cat <<EOF
        # --- SSL 配置 ---
        ssl_certificate $ssl_cert_path;
        ssl_certificate_key $ssl_key_path;

        # 推荐的 SSL 参数 (如果使用 Let's Encrypt, 可以包含它们的推荐配置)
        # include /etc/letsencrypt/options-ssl-nginx.conf; # 取消注释并确保此文件存在
        # ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;   # 取消注释并确保此文件存在

        # 较强的加密套件和协议 (可以根据需要调整)
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers off;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
EOF
)
    print_info "HTTPS 配置准备就绪。"
else
    print_info "已选择使用 HTTP (不推荐用于生产环境)。"
fi
echo

# 3. 生成 Nginx 配置内容
print_info "正在生成 Nginx 配置文件..."

# 使用 heredoc 创建配置文件内容
nginx_config=$(cat <<EOF
server {
    $listen_directive
    server_name $server_name;

$ssl_config_block

    # 可选：设置更大的 client_max_body_size 以允许更大的请求体
    # client_max_body_size 10M;

    # --- Gemini API 反向代理配置 ---
    location $proxy_location {
        # 代理目标地址 (末尾的 / 很重要)
        proxy_pass $TARGET_API_URL;

        # 设置必要的请求头
        proxy_set_header Host generativelanguage.googleapis.com;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Accept-Encoding ""; # 防止 Nginx 压缩与后端冲突

        # SSL 相关配置 (与 HTTPS 后端通信)
        proxy_ssl_server_name on; # 必须开启，以支持 SNI
        # proxy_ssl_verify on;    # 建议开启后端 SSL 证书验证 (可能需要配置 proxy_ssl_trusted_certificate)
        # proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt; # 根据系统调整路径

        # 超时设置 (根据需要调整)
        # proxy_connect_timeout 60s;
        # proxy_send_timeout   60s;
        # proxy_read_timeout   60s;

        # 处理流式响应 (如果 Gemini API 使用流式输出)
        proxy_buffering off;      # 对于 SSE (Server-Sent Events) 可能需要关闭缓冲
        proxy_cache off;          # 通常 API 代理不需要缓存
        proxy_http_version 1.1;   # 建议使用 HTTP/1.1 与后端通信
        proxy_set_header Connection ""; # 清除 Connection 头

        # --- API Key 处理 ---
        # !! 推荐方式：客户端提供 API Key !!
        # Nginx 默认会转发客户端的请求头 (如 x-goog-api-key) 和 URL 参数 (?key=...)
        # 客户端调用示例 (Header):
        # curl -H "x-goog-api-key: YOUR_API_KEY" ... http(s)://$server_name${proxy_location}gemini-pro:generateContent
        # 客户端调用示例 (URL 参数):
        # curl ... "http(s)://$server_name${proxy_location}gemini-pro:generateContent?key=YOUR_API_KEY"

        # --- 不推荐：在 Nginx 中添加 API Key (有安全风险) ---
        # 如果您执意如此，并了解风险，可以取消注释下面这行，并替换 Key
        # proxy_set_header x-goog-api-key YOUR_ACTUAL_GEMINI_API_KEY;
        # 注意：请务必保护好此 Nginx 配置文件的访问权限！
    }

    # 可选：根路径处理
    location / {
        # 可以返回一个简单的文本或 404
        return 403 "Forbidden";
        # 或者指向一个静态页面
        # root /var/www/html;
        # index index.html index.htm;
    }

    # 日志文件路径
    access_log /var/log/nginx/${config_file_name}.access.log;
    error_log /var/log/nginx/${config_file_name}.error.log;
}
EOF
)

# 4. 写入配置文件
print_info "正在将配置写入到: $config_file_path"
echo "$nginx_config" > "$config_file_path"
if [[ $? -ne 0 ]]; then
    print_error "写入配置文件失败！请检查权限或磁盘空间。"
    exit 1
fi
print_info "配置文件已成功创建。"
echo

# 5. 创建符号链接
print_info "正在启用配置 (创建符号链接)..."
# 使用 -f 强制覆盖可能存在的旧链接
ln -sf "$config_file_path" "$link_path"
if [[ $? -ne 0 ]]; then
    print_error "创建符号链接失败！"
    exit 1
fi
print_info "配置已启用: $link_path -> $config_file_path"
echo

# 6. 完成与后续步骤
print_info "--------------------------------------------------"
print_info "配置完成！"
print_info "--------------------------------------------------"
echo -e "${YELLOW}下一步操作:${NC}"
echo -e "1. ${GREEN}测试 Nginx 配置语法:${NC}"
echo -e "   sudo nginx -t"
echo
echo -e "2. ${GREEN}如果测试成功 (显示 'syntax is ok' 和 'test is successful')，重新加载 Nginx 服务:${NC}"
echo -e "   sudo systemctl reload nginx"
echo
echo -e "3. ${GREEN}使用您的反向代理:${NC}"
echo -e "   现在您可以通过以下 URL 访问 Gemini API (请将 'gemini-pro:generateContent' 替换为实际的模型和方法):"
if [[ "$use_https" == "y" ]]; then
    echo -e "   ${YELLOW}POST https://$server_name${proxy_location}gemini-pro:generateContent${NC}"
else
    echo -e "   ${YELLOW}POST http://$server_name${proxy_location}gemini-pro:generateContent${NC}"
fi
echo -e "   ${YELLOW}重要:${NC} 请确保在您的客户端请求中包含 Google API Key，通过 HTTP Header ('x-goog-api-key: YOUR_API_KEY') 或 URL 参数 ('?key=YOUR_API_KEY')。"
echo
print_warning "请再次确认您的防火墙设置，确保端口 80 (HTTP) 和/或 443 (HTTPS) 已对外部开放。"
print_info "脚本执行完毕。"

exit 0