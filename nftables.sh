#!/bin/bash

###############################################################################
# nftables 全面管理脚本
# 功能：提供nftables的全面管理功能，包括所有表、链、规则的管理
# 使用方法：bash nftables_manager.sh [命令] [选项]
# 支持的表：filter, nat, mangle, raw, inet, bridge, netdev
# 自动检测并安装nftables（如未安装）
###############################################################################

set -uo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/tmp/${SCRIPT_NAME}.log"
readonly RULES_BACKUP_DIR="/etc/nftables_backup"
readonly NFTABLES_SAVE_FILE="/etc/nftables.conf"
readonly INSTALL_LOG="/tmp/nftables_install.log"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检测Linux发行版
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/arch-release ]]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

# 检测包管理器
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# 检查nftables是否已安装
check_nftables_installed() {
    if command -v nft &> /dev/null; then
        local version=$(nft --version 2>/dev/null || echo "unknown")
        log_info "✓ nftables已安装，版本: $version"
        return 0
    else
        log_warn "✗ nftables未安装"
        return 1
    fi
}

# 安装nftables
install_nftables() {
    local pkg_manager=$(detect_package_manager)
    local distro=$(detect_distro)
    
    log_info "开始安装nftables..."
    log_info "检测到包管理器: $pkg_manager, 发行版: $distro"
    
    case "$pkg_manager" in
        apt)
            log_info "使用apt-get安装nftables..."
            if apt-get update >> "$INSTALL_LOG" 2>&1 && \
               apt-get install -y nftables >> "$INSTALL_LOG" 2>&1; then
                log_success "nftables安装成功"
                return 0
            else
                log_error "nftables安装失败，请查看日志: $INSTALL_LOG"
                return 1
            fi
            ;;
        yum)
            log_info "使用yum安装nftables..."
            if yum install -y nftables >> "$INSTALL_LOG" 2>&1; then
                log_success "nftables安装成功"
                return 0
            else
                log_error "nftables安装失败，请查看日志: $INSTALL_LOG"
                return 1
            fi
            ;;
        dnf)
            log_info "使用dnf安装nftables..."
            if dnf install -y nftables >> "$INSTALL_LOG" 2>&1; then
                log_success "nftables安装成功"
                return 0
            else
                log_error "nftables安装失败，请查看日志: $INSTALL_LOG"
                return 1
            fi
            ;;
        pacman)
            log_info "使用pacman安装nftables..."
            if pacman -S --noconfirm nftables >> "$INSTALL_LOG" 2>&1; then
                log_success "nftables安装成功"
                return 0
            else
                log_error "nftables安装失败，请查看日志: $INSTALL_LOG"
                return 1
            fi
            ;;
        zypper)
            log_info "使用zypper安装nftables..."
            if zypper install -y nftables >> "$INSTALL_LOG" 2>&1; then
                log_success "nftables安装成功"
                return 0
            else
                log_error "nftables安装失败，请查看日志: $INSTALL_LOG"
                return 1
            fi
            ;;
        *)
            log_error "无法识别包管理器，请手动安装nftables"
            log_info "Debian/Ubuntu: apt-get install -y nftables"
            log_info "CentOS/RHEL: yum install -y nftables 或 dnf install -y nftables"
            log_info "Arch: pacman -S nftables"
            log_info "openSUSE: zypper install nftables"
            return 1
            ;;
    esac
}

# 启用nftables服务
enable_nftables_service() {
    if systemctl is-enabled nftables &> /dev/null; then
        log_info "nftables服务已启用"
        return 0
    fi
    
    log_info "启用nftables服务..."
    if systemctl enable nftables >> "$INSTALL_LOG" 2>&1; then
        log_success "nftables服务已启用"
        return 0
    else
        log_warn "启用nftables服务失败，但可以继续使用"
        return 1
    fi
}

# 检查并安装nftables
check_and_install_nftables() {
    if check_nftables_installed; then
        enable_nftables_service
        return 0
    fi
    
    log_warn "nftables未安装，开始自动安装..."
    
    if ! install_nftables; then
        log_error "nftables安装失败，脚本无法继续"
        exit 1
    fi
    
    # 验证安装
    if ! check_nftables_installed; then
        log_error "nftables安装验证失败"
        exit 1
    fi
    
    # 启用服务
    enable_nftables_service
    
    log_success "nftables安装和配置完成"
}

# 检查命令是否存在
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        log_error "命令 '$cmd' 未找到"
        return 1
    fi
}

# 初始化检查
init_check() {
    check_root
    check_and_install_nftables
    check_command nft
    
    # 创建备份目录
    mkdir -p "$RULES_BACKUP_DIR"
    
    log_info "初始化检查完成"
}

# 显示帮助信息
show_help() {
    cat << EOF
${CYAN}========================================
  nftables 全面管理脚本
========================================${NC}

${GREEN}使用方法：${NC}
  $SCRIPT_NAME [命令] [选项]

${GREEN}基本命令：${NC}
  list          - 列出所有规则
  status        - 显示nftables状态和统计
  flush         - 清空所有规则
  delete        - 删除规则
  save          - 保存当前规则
  restore       - 恢复规则
  backup        - 备份当前规则
  reset         - 重置nftables到默认状态

${GREEN}表管理：${NC}
  table-list    - 列出所有表
  table-create  - 创建表
  table-delete  - 删除表
  table-flush   - 清空表

${GREEN}链管理：${NC}
  chain-list    - 列出链
  chain-create  - 创建链
  chain-delete  - 删除链
  chain-flush   - 清空链

${GREEN}规则管理：${NC}
  add           - 添加规则
  insert        - 插入规则（指定位置）
  replace       - 替换规则

${GREEN}集合管理：${NC}
  set-create    - 创建集合
  set-add       - 添加元素到集合
  set-delete    - 从集合删除元素
  set-list      - 列出集合

${GREEN}映射管理：${NC}
  map-create    - 创建映射
  map-add       - 添加映射项
  map-delete    - 删除映射项
  map-list      - 列出映射

${GREEN}常用功能：${NC}
  allow-ip      - 允许指定IP访问
  block-ip      - 屏蔽指定IP
  allow-port    - 允许指定端口
  block-port    - 屏蔽指定端口
  forward       - 设置端口转发
  snat          - 设置SNAT（源地址转换）
  dnat          - 设置DNAT（目标地址转换）
  masquerade    - 设置MASQUERADE

${GREEN}黑名单/白名单：${NC}
  blacklist-add     - 添加IP到黑名单
  blacklist-remove  - 从黑名单移除IP
  blacklist-list    - 列出黑名单
  whitelist-add     - 添加IP到白名单
  whitelist-remove  - 从白名单移除IP
  whitelist-list    - 列出白名单

${GREEN}高级功能：${NC}
  limit         - 设置连接限制/限速
  log           - 启用规则日志记录
  counter       - 创建计数器
  quota         - 设置配额
  nat           - NAT相关操作
  block-user-agent - 屏蔽 User-Agent（⚠️ 仅限明文HTTP，有限制）
  string-match  - 字符串匹配（⚠️ 仅限明文HTTP，有限制）

${GREEN}示例：${NC}
  $SCRIPT_NAME list
  $SCRIPT_NAME table-create inet filter
  $SCRIPT_NAME chain-create inet filter input '{ type filter hook input priority 0; }'
  $SCRIPT_NAME add rule inet filter input tcp dport 22 accept
  $SCRIPT_NAME allow-ip 192.168.1.100
  $SCRIPT_NAME block-ip 10.0.0.1
  $SCRIPT_NAME allow-port 80 tcp
  $SCRIPT_NAME forward 8080 192.168.1.10 80
  $SCRIPT_NAME status

EOF
}

# 列出所有规则
list_rules() {
    local table="${1:-all}"
    
    echo -e "${CYAN}========== nftables 规则列表 ==========${NC}"
    
    if [[ "$table" == "all" ]]; then
        nft list ruleset 2>/dev/null || log_error "无法列出规则"
    else
        nft list table "$table" 2>/dev/null || log_error "无法列出表 $table 的规则"
    fi
    
    echo ""
}

# 显示nftables状态
show_status() {
    echo -e "${CYAN}========== nftables 状态信息 ==========${NC}\n"
    
    echo -e "${YELLOW}nftables版本：${NC}"
    nft --version 2>/dev/null || echo "无法获取版本信息"
    
    echo -e "\n${YELLOW}当前活动规则：${NC}"
    nft list ruleset | head -30
    
    echo -e "\n${YELLOW}规则统计：${NC}"
    nft list ruleset | grep -c "^[[:space:]]*" || echo "0"
    
    echo -e "\n${YELLOW}服务状态：${NC}"
    if systemctl is-active nftables &> /dev/null; then
        echo "  服务状态: 运行中"
    else
        echo "  服务状态: 未运行"
    fi
    
    if systemctl is-enabled nftables &> /dev/null; then
        echo "  开机自启: 已启用"
    else
        echo "  开机自启: 未启用"
    fi
    
    echo ""
}

# 清空所有规则
flush_rules() {
    local table="${1:-all}"
    
    read -p "确定要清空规则吗？(yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "操作已取消"
        return
    fi
    
    if [[ "$table" == "all" ]]; then
        log_info "清空所有规则..."
        nft flush ruleset
        log_success "已清空所有规则"
    else
        log_info "清空表 $table 的所有规则..."
        nft flush table "$table"
        log_success "已清空表 $table"
    fi
}

# 保存规则
save_rules() {
    local save_file="${1:-$NFTABLES_SAVE_FILE}"
    local save_dir=$(dirname "$save_file")
    
    mkdir -p "$save_dir"
    
    log_info "保存规则到 $save_file ..."
    nft list ruleset > "$save_file"
    log_success "规则已保存到 $save_file"
}

# 恢复规则
restore_rules() {
    local restore_file="${1:-$NFTABLES_SAVE_FILE}"
    
    if [[ ! -f "$restore_file" ]]; then
        log_error "规则文件不存在: $restore_file"
        return 1
    fi
    
    read -p "确定要恢复规则吗？这将覆盖当前规则 (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "操作已取消"
        return
    fi
    
    log_info "从 $restore_file 恢复规则..."
    nft -f "$restore_file"
    log_success "规则已恢复"
}

# 备份规则
backup_rules() {
    local backup_file="${RULES_BACKUP_DIR}/nftables_$(date +%Y%m%d_%H%M%S).nft"
    
    log_info "备份规则到 $backup_file ..."
    nft list ruleset > "$backup_file"
    log_success "规则已备份到 $backup_file"
}

# 重置nftables
reset_nftables() {
    read -p "确定要重置nftables吗？这将清空所有规则 (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "操作已取消"
        return
    fi
    
    log_info "重置nftables..."
    nft flush ruleset
    log_success "nftables已重置"
}

# 添加规则
add_rule() {
    shift  # 移除 'add' 参数
    if nft "$@"; then
        log_success "规则已添加"
    else
        log_error "添加规则失败"
        return 1
    fi
}

# 删除规则
delete_rule() {
    shift  # 移除 'delete' 参数
    if nft "$@"; then
        log_success "规则已删除"
    else
        log_error "删除规则失败"
        return 1
    fi
}

# 插入规则
insert_rule() {
    shift  # 移除 'insert' 参数
    if nft "$@"; then
        log_success "规则已插入"
    else
        log_error "插入规则失败"
        return 1
    fi
}

# 替换规则
replace_rule() {
    shift  # 移除 'replace' 参数
    if nft "$@"; then
        log_success "规则已替换"
    else
        log_error "替换规则失败"
        return 1
    fi
}

# 列出所有表
list_tables() {
    local family="${1:-all}"
    
    echo -e "${CYAN}========== nftables 表列表 ==========${NC}\n"
    
    if [[ "$family" == "all" ]]; then
        nft list tables 2>/dev/null || log_error "无法列出表"
    else
        nft list tables "$family" 2>/dev/null || log_error "无法列出地址族 $family 的表"
    fi
    
    echo ""
}

# 创建表
create_table() {
    local family="$1"
    local table="$2"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]]; then
        log_error "用法: table-create <family> <table-name>"
        log_info "例如: table-create inet filter"
        log_info "地址族: ip, ip6, inet, arp, bridge, netdev"
        return 1
    fi
    
    if nft create table "$family" "$table" 2>/dev/null; then
        log_success "已创建表 $table (地址族: $family)"
    else
        log_error "创建表失败（可能已存在）"
        return 1
    fi
}

# 删除表
delete_table() {
    local family="$1"
    local table="$2"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]]; then
        log_error "用法: table-delete <family> <table-name>"
        return 1
    fi
    
    # 先清空表
    nft flush table "$family" "$table" 2>/dev/null
    
    # 删除表
    if nft delete table "$family" "$table" 2>/dev/null; then
        log_success "已删除表 $table (地址族: $family)"
    else
        log_error "删除表失败"
        return 1
    fi
}

# 清空表
flush_table() {
    local family="$1"
    local table="$2"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]]; then
        log_error "用法: table-flush <family> <table-name>"
        return 1
    fi
    
    if nft flush table "$family" "$table" 2>/dev/null; then
        log_success "已清空表 $table (地址族: $family)"
    else
        log_error "清空表失败"
        return 1
    fi
}

# 列出链
list_chains() {
    local family="${1:-all}"
    local table="${2:-}"
    
    echo -e "${CYAN}========== nftables 链列表 ==========${NC}\n"
    
    if [[ "$family" == "all" ]]; then
        nft list chains 2>/dev/null || log_error "无法列出链"
    elif [[ -n "$table" ]]; then
        nft list chain "$family" "$table" "$table" 2>/dev/null || log_error "无法列出链"
    else
        nft list chains "$family" 2>/dev/null || log_error "无法列出链"
    fi
    
    echo ""
}

# 创建链
create_chain() {
    local family="$1"
    local table="$2"
    local chain="$3"
    local definition="$4"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]] || [[ -z "$chain" ]]; then
        log_error "用法: chain-create <family> <table> <chain-name> [definition]"
        log_info "例如: chain-create inet filter input '{ type filter hook input priority 0; }'"
        return 1
    fi
    
    if [[ -n "$definition" ]]; then
        if nft create chain "$family" "$table" "$chain" "$definition" 2>/dev/null; then
            log_success "已创建链 $chain (表: $family $table)"
        else
            log_error "创建链失败"
            return 1
        fi
    else
        if nft create chain "$family" "$table" "$chain" 2>/dev/null; then
            log_success "已创建链 $chain (表: $family $table)"
        else
            log_error "创建链失败"
            return 1
        fi
    fi
}

# 删除链
delete_chain() {
    local family="$1"
    local table="$2"
    local chain="$3"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]] || [[ -z "$chain" ]]; then
        log_error "用法: chain-delete <family> <table> <chain-name>"
        return 1
    fi
    
    # 先清空链
    nft flush chain "$family" "$table" "$chain" 2>/dev/null
    
    # 删除链
    if nft delete chain "$family" "$table" "$chain" 2>/dev/null; then
        log_success "已删除链 $chain (表: $family $table)"
    else
        log_error "删除链失败"
        return 1
    fi
}

# 清空链
flush_chain() {
    local family="$1"
    local table="$2"
    local chain="$3"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]] || [[ -z "$chain" ]]; then
        log_error "用法: chain-flush <family> <table> <chain-name>"
        return 1
    fi
    
    if nft flush chain "$family" "$table" "$chain" 2>/dev/null; then
        log_success "已清空链 $chain (表: $family $table)"
    else
        log_error "清空链失败"
        return 1
    fi
}

# 允许指定IP访问
allow_ip() {
    local ip="$1"
    local family="${2:-inet}"
    local table="${3:-filter}"
    local chain="${4:-input}"
    
    if [[ -z "$ip" ]]; then
        log_error "用法: allow-ip <ip-address> [family] [table] [chain]"
        return 1
    fi
    
    # 确保表和链存在
    nft create table "$family" "$table" 2>/dev/null
    nft create chain "$family" "$table" "$chain" '{ type filter hook input priority 0; }' 2>/dev/null
    
    nft add rule "$family" "$table" "$chain" ip saddr "$ip" accept
    log_success "已允许IP $ip 访问 (链: $family $table $chain)"
}

# 屏蔽指定IP
block_ip() {
    local ip="$1"
    local family="${2:-inet}"
    local table="${3:-filter}"
    local chain="${4:-input}"
    
    if [[ -z "$ip" ]]; then
        log_error "用法: block-ip <ip-address> [family] [table] [chain]"
        return 1
    fi
    
    # 确保表和链存在
    nft create table "$family" "$table" 2>/dev/null
    nft create chain "$family" "$table" "$chain" '{ type filter hook input priority 0; }' 2>/dev/null
    
    nft add rule "$family" "$table" "$chain" ip saddr "$ip" drop
    log_success "已屏蔽IP $ip (链: $family $table $chain)"
}

# 允许指定端口
allow_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local family="${3:-inet}"
    local table="${4:-filter}"
    local chain="${5:-input}"
    
    if [[ -z "$port" ]]; then
        log_error "用法: allow-port <port> [protocol] [family] [table] [chain]"
        return 1
    fi
    
    # 确保表和链存在
    nft create table "$family" "$table" 2>/dev/null
    nft create chain "$family" "$table" "$chain" '{ type filter hook input priority 0; }' 2>/dev/null
    
    nft add rule "$family" "$table" "$chain" "$protocol" dport "$port" accept
    log_success "已允许端口 $port/$protocol (链: $family $table $chain)"
}

# 屏蔽指定端口
block_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local family="${3:-inet}"
    local table="${4:-filter}"
    local chain="${5:-input}"
    
    if [[ -z "$port" ]]; then
        log_error "用法: block-port <port> [protocol] [family] [table] [chain]"
        return 1
    fi
    
    # 确保表和链存在
    nft create table "$family" "$table" 2>/dev/null
    nft create chain "$family" "$table" "$chain" '{ type filter hook input priority 0; }' 2>/dev/null
    
    nft add rule "$family" "$table" "$chain" "$protocol" dport "$port" drop
    log_success "已屏蔽端口 $port/$protocol (链: $family $table $chain)"
}

# 设置端口转发
set_forward() {
    local local_port="$1"
    local remote_ip="$2"
    local remote_port="$3"
    local protocol="${4:-tcp}"
    
    if [[ -z "$local_port" ]] || [[ -z "$remote_ip" ]] || [[ -z "$remote_port" ]]; then
        log_error "用法: forward <local-port> <remote-ip> <remote-port> [protocol]"
        log_info "例如: forward 8080 192.168.1.10 80"
        return 1
    fi
    
    # 启用IP转发
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # 创建nat表
    nft create table ip nat 2>/dev/null
    
    # 创建prerouting链
    nft create chain ip nat prerouting '{ type nat hook prerouting priority -100; }' 2>/dev/null
    
    # 添加DNAT规则
    nft add rule ip nat prerouting "$protocol" dport "$local_port" dnat to "$remote_ip:$remote_port"
    
    # 创建postrouting链（MASQUERADE）
    nft create chain ip nat postrouting '{ type nat hook postrouting priority 100; }' 2>/dev/null
    nft add rule ip nat postrouting "$protocol" dport "$remote_port" daddr "$remote_ip" masquerade
    
    log_success "已设置端口转发: $local_port -> $remote_ip:$remote_port"
}

# 设置SNAT
set_snat() {
    local source_network="$1"
    local public_ip="$2"
    
    if [[ -z "$source_network" ]] || [[ -z "$public_ip" ]]; then
        log_error "用法: snat <source-network> <public-ip>"
        log_info "例如: snat 192.168.1.0/24 203.0.113.1"
        return 1
    fi
    
    # 创建nat表
    nft create table ip nat 2>/dev/null
    nft create chain ip nat postrouting '{ type nat hook postrouting priority 100; }' 2>/dev/null
    
    nft add rule ip nat postrouting ip saddr "$source_network" snat to "$public_ip"
    log_success "已设置SNAT: $source_network -> $public_ip"
}

# 设置DNAT
set_dnat() {
    local public_port="$1"
    local private_ip="$2"
    local private_port="$3"
    local protocol="${4:-tcp}"
    
    if [[ -z "$public_port" ]] || [[ -z "$private_ip" ]] || [[ -z "$private_port" ]]; then
        log_error "用法: dnat <public-port> <private-ip> <private-port> [protocol]"
        return 1
    fi
    
    # 创建nat表
    nft create table ip nat 2>/dev/null
    nft create chain ip nat prerouting '{ type nat hook prerouting priority -100; }' 2>/dev/null
    
    nft add rule ip nat prerouting "$protocol" dport "$public_port" dnat to "$private_ip:$private_port"
    log_success "已设置DNAT: $public_port -> $private_ip:$private_port"
}

# 设置MASQUERADE
set_masquerade() {
    local interface="${1:-+}"
    
    # 创建nat表
    nft create table ip nat 2>/dev/null
    nft create chain ip nat postrouting '{ type nat hook postrouting priority 100; }' 2>/dev/null
    
    if [[ "$interface" == "+" ]]; then
        nft add rule ip nat postrouting masquerade
    else
        nft add rule ip nat postrouting oifname "$interface" masquerade
    fi
    
    log_success "已设置MASQUERADE (接口: $interface)"
}

# 创建集合
create_set() {
    local family="$1"
    local table="$2"
    local set_name="$3"
    local type="$4"
    local flags="${5:-}"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]] || [[ -z "$set_name" ]] || [[ -z "$type" ]]; then
        log_error "用法: set-create <family> <table> <set-name> <type> [flags]"
        log_info "例如: set-create inet filter my_set '{ type ipv4_addr; }'"
        return 1
    fi
    
    if [[ -n "$flags" ]]; then
        nft create set "$family" "$table" "$set_name" "{ type $type; $flags; }" 2>/dev/null
    else
        nft create set "$family" "$table" "$set_name" "{ type $type; }" 2>/dev/null
    fi
    
    if [[ $? -eq 0 ]]; then
        log_success "已创建集合 $set_name (表: $family $table)"
    else
        log_error "创建集合失败"
        return 1
    fi
}

# 添加元素到集合
set_add() {
    local family="$1"
    local table="$2"
    local set_name="$3"
    shift 3
    local elements="$*"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]] || [[ -z "$set_name" ]]; then
        log_error "用法: set-add <family> <table> <set-name> <elements...>"
        return 1
    fi
    
    nft add element "$family" "$table" "$set_name" "{ $elements }" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        log_success "已添加元素到集合 $set_name"
    else
        log_error "添加元素失败"
        return 1
    fi
}

# 从集合删除元素
set_delete() {
    local family="$1"
    local table="$2"
    local set_name="$3"
    shift 3
    local elements="$*"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]] || [[ -z "$set_name" ]]; then
        log_error "用法: set-delete <family> <table> <set-name> <elements...>"
        return 1
    fi
    
    nft delete element "$family" "$table" "$set_name" "{ $elements }" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        log_success "已从集合删除元素 $set_name"
    else
        log_error "删除元素失败"
        return 1
    fi
}

# 列出集合
set_list() {
    local family="${1:-all}"
    local table="${2:-}"
    
    echo -e "${CYAN}========== nftables 集合列表 ==========${NC}\n"
    
    if [[ "$family" == "all" ]]; then
        nft list sets 2>/dev/null || log_error "无法列出集合"
    elif [[ -n "$table" ]]; then
        nft list set "$family" "$table" "$table" 2>/dev/null || log_error "无法列出集合"
    else
        nft list sets "$family" 2>/dev/null || log_error "无法列出集合"
    fi
    
    echo ""
}

# 黑名单管理
BLACKLIST_FILE="/etc/nftables_blacklist.txt"
blacklist_add() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        log_error "用法: blacklist-add <ip-address>"
        return 1
    fi
    
    # 添加到文件
    echo "$ip" >> "$BLACKLIST_FILE"
    
    # 创建表和链（如果不存在）
    nft create table inet filter 2>/dev/null
    nft create chain inet filter input '{ type filter hook input priority 0; }' 2>/dev/null
    nft create chain inet filter output '{ type filter hook output priority 0; }' 2>/dev/null
    
    # 添加到nftables
    nft add rule inet filter input ip saddr "$ip" drop
    nft add rule inet filter output ip daddr "$ip" drop
    
    log_success "已添加 $ip 到黑名单"
}

blacklist_remove() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        log_error "用法: blacklist-remove <ip-address>"
        return 1
    fi
    
    # 从文件删除
    sed -i "/^$ip$/d" "$BLACKLIST_FILE" 2>/dev/null
    
    # 从nftables删除（需要找到规则句柄）
    local handles=$(nft -a list chain inet filter input | grep "ip saddr $ip" | grep -oP 'handle \K\d+')
    for handle in $handles; do
        nft delete rule inet filter input handle "$handle" 2>/dev/null
    done
    
    handles=$(nft -a list chain inet filter output | grep "ip daddr $ip" | grep -oP 'handle \K\d+')
    for handle in $handles; do
        nft delete rule inet filter output handle "$handle" 2>/dev/null
    done
    
    log_success "已从黑名单移除 $ip"
}

blacklist_list() {
    if [[ -f "$BLACKLIST_FILE" ]]; then
        echo -e "${CYAN}========== 黑名单列表 ==========${NC}\n"
        cat "$BLACKLIST_FILE"
        echo ""
    else
        log_info "黑名单文件不存在，尚未添加任何IP"
    fi
}

# 白名单管理
WHITELIST_FILE="/etc/nftables_whitelist.txt"
whitelist_add() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        log_error "用法: whitelist-add <ip-address>"
        return 1
    fi
    
    # 添加到文件
    echo "$ip" >> "$WHITELIST_FILE"
    
    # 创建表和链（如果不存在）
    nft create table inet filter 2>/dev/null
    nft create chain inet filter input '{ type filter hook input priority 0; }' 2>/dev/null
    nft create chain inet filter output '{ type filter hook output priority 0; }' 2>/dev/null
    
    # 添加到nftables（放在最前面）
    nft insert rule inet filter input position 0 ip saddr "$ip" accept
    nft insert rule inet filter output position 0 ip daddr "$ip" accept
    
    log_success "已添加 $ip 到白名单"
}

whitelist_remove() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        log_error "用法: whitelist-remove <ip-address>"
        return 1
    fi
    
    # 从文件删除
    sed -i "/^$ip$/d" "$WHITELIST_FILE" 2>/dev/null
    
    # 从nftables删除
    local handles=$(nft -a list chain inet filter input | grep "ip saddr $ip" | grep -oP 'handle \K\d+')
    for handle in $handles; do
        nft delete rule inet filter input handle "$handle" 2>/dev/null
    done
    
    handles=$(nft -a list chain inet filter output | grep "ip daddr $ip" | grep -oP 'handle \K\d+')
    for handle in $handles; do
        nft delete rule inet filter output handle "$handle" 2>/dev/null
    done
    
    log_success "已从白名单移除 $ip"
}

whitelist_list() {
    if [[ -f "$WHITELIST_FILE" ]]; then
        echo -e "${CYAN}========== 白名单列表 ==========${NC}\n"
        cat "$WHITELIST_FILE"
        echo ""
    else
        log_info "白名单文件不存在，尚未添加任何IP"
    fi
}

# 启用规则日志
enable_log() {
    local family="${1:-inet}"
    local table="${2:-filter}"
    local chain="${3:-input}"
    local prefix="${4:-NFTABLES}"
    
    # 创建表和链（如果不存在）
    nft create table "$family" "$table" 2>/dev/null
    nft create chain "$family" "$table" "$chain" '{ type filter hook input priority 0; }' 2>/dev/null
    
    # 添加日志规则
    nft add rule "$family" "$table" "$chain" log prefix "\"$prefix: \"" level 4
    
    log_success "已在链 $family $table $chain 启用日志记录 (前缀: $prefix)"
}

# 屏蔽 User-Agent（警告：此功能有限制）
# 注意：nftables 不是为应用层（L7）过滤设计的，屏蔽 User-Agent 有以下严重限制：
# 1. 只能用于明文 HTTP（不适用于 HTTPS）
# 2. 需要精确的字节偏移量，HTTP 头位置可变导致匹配脆弱
# 3. 不适用于 HTTP/2
# 4. 强烈建议使用 Web 服务器层面（nginx/Apache）进行 User-Agent 过滤
block_user_agent() {
    local user_agent="$1"
    local port="${2:-80}"
    local offset="${3:-200}"
    local family="${4:-inet}"
    local table="${5:-filter}"
    local chain="${6:-input}"
    
    if [[ -z "$user_agent" ]]; then
        log_error "用法: block-user-agent <user-agent-string> [port] [offset] [family] [table] [chain]"
        log_warn ""
        log_warn "⚠️  重要警告："
        log_warn "1. 此功能只能用于明文 HTTP（不适用于 HTTPS）"
        log_warn "2. 需要指定字节偏移量，HTTP 头位置可变导致匹配可能失败"
        log_warn "3. 不适用于 HTTP/2"
        log_warn "4. 强烈建议使用 Web 服务器层面（nginx/Apache）进行 User-Agent 过滤"
        log_warn ""
        log_info "推荐的替代方案："
        log_info "  - Nginx: if (\$http_user_agent ~* 'BadBot') { return 403; }"
        log_info "  - Apache: BrowserMatchNoCase 'BadBot' block"
        log_info ""
        return 1
    fi
    
    # 显示警告
    log_warn ""
    log_warn "⚠️  警告：使用 nftables 屏蔽 User-Agent 有以下限制："
    log_warn "  1. 仅适用于明文 HTTP（HTTPS 无法使用）"
    log_warn "  2. HTTP 头位置可变，可能导致匹配失败"
    log_warn "  3. 不适用于 HTTP/2"
    log_warn "  4. 强烈建议使用 Web 服务器层面进行过滤"
    log_warn ""
    
    read -p "是否继续？(yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "操作已取消"
        return
    fi
    
    # 创建表和链（如果不存在）
    nft create table "$family" "$table" 2>/dev/null
    nft create chain "$family" "$table" "$chain" '{ type filter hook input priority 0; }' 2>/dev/null
    
    # 计算字符串长度（字节）
    local string_length=$(echo -n "User-Agent: $user_agent" | wc -c)
    local length_bits=$((string_length * 8))
    
    # 尝试匹配 User-Agent（使用原始载荷匹配）
    # 注意：offset 需要根据实际情况调整
    # 基本思路：TCP 头（20-60字节）+ HTTP 请求行 + 其他头部
    # User-Agent 通常在 HTTP 请求行的几十到上百字节之后
    
    log_info "尝试添加规则（偏移量: $offset 位，字符串长度: $string_length 字节）..."
    log_info "注意：如果规则不生效，可能需要调整偏移量"
    log_info "提示：使用 tcpdump -A 或 Wireshark 分析实际数据包来确定正确的偏移量"
    
    # 方法1：尝试匹配 "User-Agent: <string>" 在指定偏移量
    if nft add rule "$family" "$table" "$chain" tcp dport "$port" @th, "$offset", "$length_bits" "{ \"User-Agent: $user_agent\" }" drop 2>/dev/null; then
        log_success "已添加 User-Agent 屏蔽规则: $user_agent (端口: $port)"
        log_warn "请测试规则是否正常工作，如无效请调整偏移量"
    else
        log_error "添加规则失败"
        log_info "建议：使用 Web 服务器层面进行 User-Agent 过滤"
        return 1
    fi
}

# 字符串匹配（通用）
string_match() {
    local family="$1"
    local table="$2"
    local chain="$3"
    local string="$4"
    local port="${5:-80}"
    local offset="${6:-200}"
    local target="${7:-drop}"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]] || [[ -z "$chain" ]] || [[ -z "$string" ]]; then
        log_error "用法: string-match <family> <table> <chain> <string> [port] [offset] [target]"
        log_warn "注意：此功能仅适用于明文 HTTP，不适用于 HTTPS"
        return 1
    fi
    
    # 计算字符串长度（字节）
    local string_length=$(echo -n "$string" | wc -c)
    local length_bits=$((string_length * 8))
    
    # 创建表和链（如果不存在）
    nft create table "$family" "$table" 2>/dev/null
    nft create chain "$family" "$table" "$chain" '{ type filter hook input priority 0; }' 2>/dev/null
    
    if nft add rule "$family" "$table" "$chain" tcp dport "$port" @th, "$offset", "$length_bits" "{ \"$string\" }" "$target" 2>/dev/null; then
        log_success "已添加字符串匹配规则: $string -> $target"
        log_warn "注意：此功能仅适用于明文 HTTP，不适用于 HTTPS"
    else
        log_error "添加规则失败"
        return 1
    fi
}

# 创建计数器
create_counter() {
    local family="$1"
    local table="$2"
    local counter_name="$3"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]] || [[ -z "$counter_name" ]]; then
        log_error "用法: counter <family> <table> <counter-name>"
        return 1
    fi
    
    nft create counter "$family" "$table" "$counter_name" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        log_success "已创建计数器 $counter_name (表: $family $table)"
    else
        log_error "创建计数器失败"
        return 1
    fi
}

# 设置配额
set_quota() {
    local family="$1"
    local table="$2"
    local chain="$3"
    local quota="$4"
    
    if [[ -z "$family" ]] || [[ -z "$table" ]] || [[ -z "$chain" ]] || [[ -z "$quota" ]]; then
        log_error "用法: quota <family> <table> <chain> <quota>"
        log_info "例如: quota inet filter input 10 mbytes"
        return 1
    fi
    
    nft add rule "$family" "$table" "$chain" quota "$quota"
    log_success "已设置配额: $quota"
}

# 主函数
main() {
    local command="${1:-help}"
    
    case "$command" in
        help|--help|-h)
            show_help
            ;;
        list)
            init_check
            list_rules "${2:-all}"
            ;;
        status)
            init_check
            show_status
            ;;
        flush)
            init_check
            flush_rules "${2:-all}"
            ;;
        save)
            init_check
            save_rules "$2"
            ;;
        restore)
            init_check
            restore_rules "$2"
            ;;
        backup)
            init_check
            backup_rules
            ;;
        reset)
            init_check
            reset_nftables
            ;;
        add)
            init_check
            add_rule "$@"
            ;;
        delete|del)
            init_check
            delete_rule "$@"
            ;;
        insert)
            init_check
            insert_rule "$@"
            ;;
        replace)
            init_check
            replace_rule "$@"
            ;;
        table-list)
            init_check
            list_tables "${2:-all}"
            ;;
        table-create)
            init_check
            create_table "$2" "$3"
            ;;
        table-delete)
            init_check
            delete_table "$2" "$3"
            ;;
        table-flush)
            init_check
            flush_table "$2" "$3"
            ;;
        chain-list)
            init_check
            list_chains "$2" "$3"
            ;;
        chain-create)
            init_check
            create_chain "$2" "$3" "$4" "$5"
            ;;
        chain-delete)
            init_check
            delete_chain "$2" "$3" "$4"
            ;;
        chain-flush)
            init_check
            flush_chain "$2" "$3" "$4"
            ;;
        allow-ip)
            init_check
            allow_ip "$2" "$3" "$4" "$5"
            ;;
        block-ip)
            init_check
            block_ip "$2" "$3" "$4" "$5"
            ;;
        allow-port)
            init_check
            allow_port "$2" "$3" "$4" "$5" "$6"
            ;;
        block-port)
            init_check
            block_port "$2" "$3" "$4" "$5" "$6"
            ;;
        forward)
            init_check
            set_forward "$2" "$3" "$4" "$5"
            ;;
        snat)
            init_check
            set_snat "$2" "$3"
            ;;
        dnat)
            init_check
            set_dnat "$2" "$3" "$4" "$5"
            ;;
        masquerade)
            init_check
            set_masquerade "$2"
            ;;
        set-create)
            init_check
            create_set "$2" "$3" "$4" "$5" "$6"
            ;;
        set-add)
            init_check
            set_add "$2" "$3" "$4" "${@:5}"
            ;;
        set-delete)
            init_check
            set_delete "$2" "$3" "$4" "${@:5}"
            ;;
        set-list)
            init_check
            set_list "$2" "$3"
            ;;
        blacklist-add)
            init_check
            blacklist_add "$2"
            ;;
        blacklist-remove)
            init_check
            blacklist_remove "$2"
            ;;
        blacklist-list)
            blacklist_list
            ;;
        whitelist-add)
            init_check
            whitelist_add "$2"
            ;;
        whitelist-remove)
            init_check
            whitelist_remove "$2"
            ;;
        whitelist-list)
            whitelist_list
            ;;
        log)
            init_check
            enable_log "$2" "$3" "$4" "$5"
            ;;
        counter)
            init_check
            create_counter "$2" "$3" "$4"
            ;;
        quota)
            init_check
            set_quota "$2" "$3" "$4" "$5"
            ;;
        block-user-agent)
            init_check
            block_user_agent "$2" "$3" "$4" "$5" "$6" "$7"
            ;;
        string-match)
            init_check
            string_match "$2" "$3" "$4" "$5" "$6" "$7" "$8"
            ;;
        *)
            log_error "未知命令: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
