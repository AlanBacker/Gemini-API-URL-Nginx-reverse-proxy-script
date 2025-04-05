#!/bin/bash

# --- 配置 ---
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_LOG_DIR="/var/log/nginx"

# --- 颜色定义 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
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
       print_error "此脚本需要以 root 权限运行。请使用 'sudo ./remove_nginx_proxy.sh' 运行。"
       exit 1
    fi
}

# --- 主逻辑 ---
clear
print_info "Nginx 反向代理配置移除脚本"
print_warning "--------------------------------------------------"
print_warning "此脚本将帮助您删除 Nginx 代理配置文件、符号链接和相关日志。"
print_warning "请仔细确认要删除的文件名，误删可能导致 Nginx 无法正常工作！"
print_warning "--------------------------------------------------"
echo

# 1. 检查权限
check_root
echo

# 2. 列出可能的配置文件供用户选择
print_info "在 '$NGINX_SITES_AVAILABLE' 中找到的可能配置文件:"
echo -e "${CYAN}"
ls -1 "$NGINX_SITES_AVAILABLE" | grep -E '(proxy|google|gemini)' || echo "  (未找到明显匹配 'proxy', 'google' 或 'gemini' 的文件)"
echo -e "${NC}"
print_info "在 '$NGINX_SITES_ENABLED' 中启用的站点 (符号链接):"
echo -e "${CYAN}"
ls -l "$NGINX_SITES_ENABLED" | grep -E '(proxy|google|gemini)' || echo "  (未找到明显匹配 'proxy', 'google' 或 'gemini' 的链接)"
ls -l "$NGINX_SITES_ENABLED" | grep -v -E '(proxy|google|gemini)' # 显示其他文件以防万一
echo -e "${NC}"
echo

# 3. 获取用户要删除的配置文件名
read -p "请输入您要彻底删除的配置文件的【完整文件名】(位于 $NGINX_SITES_AVAILABLE 目录下): " config_filename

# 检查输入是否为空
if [[ -z "$config_filename" ]]; then
    print_error "未输入文件名。操作中止。"
    exit 1
fi

config_file_path="${NGINX_SITES_AVAILABLE}/${config_filename}"
link_path="${NGINX_SITES_ENABLED}/${config_filename}" # 假设链接名和文件名相同，这是脚本创建时的行为
log_filename_base="${config_filename%.conf}" # 去掉 .conf 后缀作为日志文件基础名
access_log_path="${NGINX_LOG_DIR}/${log_filename_base}.access.log"
error_log_path="${NGINX_LOG_DIR}/${log_filename_base}.error.log"

# 4. 确认文件存在性并最终确认
if [[ ! -f "$config_file_path" ]]; then
    print_error "配置文件 '$config_file_path' 不存在！请检查您输入的文件名。"
    exit 1
fi

echo
print_warning "将要执行以下删除操作:"
print_warning "  - 删除符号链接: $link_path"
print_warning "  - 删除配置文件: $config_file_path"
print_warning "  - 删除访问日志: $access_log_path (如果存在)"
print_warning "  - 删除错误日志: $error_log_path (如果存在)"
echo
read -p "$(echo -e ${RED}"!!! 此操作不可恢复，确定要删除吗? (y/n): "${NC})" confirmation
confirmation=$(echo "$confirmation" | tr '[:upper:]' '[:lower:]')

if [[ "$confirmation" != "y" ]]; then
    print_info "操作已取消。"
    exit 0
fi

# 5. 执行删除
print_info "正在删除符号链接: $link_path"
rm -f "$link_path"
if [[ $? -eq 0 ]]; then
    print_info "符号链接删除成功。"
else
    print_warning "删除符号链接失败或链接不存在。" # 即使失败也继续尝试删除配置文件
fi

print_info "正在删除配置文件: $config_file_path"
rm -f "$config_file_path"
if [[ $? -ne 0 ]]; then
    print_error "删除配置文件 '$config_file_path' 失败！请检查权限。"
    # 即使配置文件删除失败，也尝试删除日志，但最后退出码应为失败
    error_occurred=1
else
    print_info "配置文件删除成功。"
fi

print_info "正在尝试删除日志文件..."
rm -f "$access_log_path" && print_info "访问日志已删除 (如果存在)。" || print_warning "无法删除访问日志或文件不存在。"
rm -f "$error_log_path" && print_info "错误日志已删除 (如果存在)。" || print_warning "无法删除错误日志或文件不存在。"
echo

# 6. 提示后续操作
print_info "删除操作完成。建议执行以下命令检查并应用更改："
echo -e "1. ${GREEN}测试 Nginx 配置语法:${NC}"
echo -e "   sudo nginx -t"
echo
echo -e "2. ${GREEN}如果测试成功，重新加载 Nginx 服务:${NC}"
echo -e "   sudo systemctl reload nginx"
echo

if [[ $error_occurred -eq 1 ]]; then
    exit 1 # 以错误码退出
else
    exit 0 # 正常退出
fi
