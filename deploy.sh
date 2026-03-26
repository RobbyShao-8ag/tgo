#!/bin/bash

# ==========================================================
# TGO 单机一键部署脚本
# 适用于: CentOS 7 + 宝塔面板
# ==========================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 未安装，请先安装"
        exit 1
    fi
}

check_docker() {
    check_command docker
    check_command docker-compose
    
    if ! docker info &> /dev/null; then
        log_error "Docker 未正常运行，请检查 Docker 服务"
        exit 1
    fi
    log_info "Docker 检查通过"
}

generate_secret() {
    openssl rand -hex 32
}

setup_env() {
    if [ -f ".env" ]; then
        log_warn ".env 文件已存在，跳过创建"
        return
    fi
    
    if [ ! -f ".env.standalone.example" ]; then
        log_error ".env.standalone.example 文件不存在"
        exit 1
    fi
    
    cp .env.standalone.example .env
    
    SECRET=$(generate_secret)
    sed -i "s|请运行_openssl_rand_hex_32_生成并替换|$SECRET|g" .env
    
    log_info ".env 文件已创建，请编辑配置:"
    log_warn "  1. 修改 SERVER_HOST 为你的服务器IP或域名"
    log_warn "  2. 修改 POSTGRES_PASSWORD 为强密码"
    log_warn "  3. 修改 VITE_API_BASE_URL 为你的API地址"
    log_warn "  4. 修改 WUKONGIM_WSS_ADDR 为你的WebSocket地址"
    echo ""
    read -p "配置完成后按回车继续..."
}

create_directories() {
    log_info "创建数据目录..."
    mkdir -p data/postgres
    mkdir -p data/redis
    mkdir -p data/wukongim
    mkdir -p data/tgo-rag/uploads
    mkdir -p data/tgo-api/uploads
    mkdir -p data/tgo-device-control/screenshots
    mkdir -p data/plugins
    mkdir -p data/skills
    chmod -R 755 data
    log_info "数据目录创建完成"
}

pull_images() {
    log_info "拉取 Docker 镜像 (可能需要几分钟)..."
    docker-compose -f docker-compose.standalone.yml pull
    log_info "镜像拉取完成"
}

start_services() {
    log_info "启动服务..."
    
    log_info "启动基础设施服务 (PostgreSQL, Redis, WuKongIM)..."
    docker-compose -f docker-compose.standalone.yml up -d postgres redis wukongim
    
    log_info "等待数据库就绪..."
    sleep 10
    
    log_info "启动 RAG 服务..."
    docker-compose -f docker-compose.standalone.yml up -d tgo-rag tgo-rag-worker tgo-rag-beat
    
    log_info "等待 RAG 服务就绪..."
    sleep 15
    
    log_info "启动 AI 服务..."
    docker-compose -f docker-compose.standalone.yml up -d tgo-ai
    
    log_info "等待 AI 服务就绪..."
    sleep 15
    
    log_info "启动 Plugin Runtime 和 Device Control..."
    docker-compose -f docker-compose.standalone.yml up -d tgo-plugin-runtime tgo-device-control
    
    log_info "启动 Workflow 服务..."
    docker-compose -f docker-compose.standalone.yml up -d tgo-workflow tgo-workflow-worker
    
    log_info "启动 API 服务..."
    docker-compose -f docker-compose.standalone.yml up -d tgo-api
    
    log_info "等待 API 服务就绪..."
    sleep 10
    
    log_info "启动 Platform 服务..."
    docker-compose -f docker-compose.standalone.yml up -d tgo-platform
    
    log_info "启动前端服务..."
    docker-compose -f docker-compose.standalone.yml up -d tgo-web tgo-widget-js
    
    log_info "所有服务启动完成"
}

check_services() {
    log_info "检查服务状态..."
    echo ""
    
    services=(
        "tgo-postgres:PostgreSQL"
        "tgo-redis:Redis"
        "tgo-wukongim:WuKongIM"
        "tgo-rag:RAG服务"
        "tgo-rag-worker:RAG Worker"
        "tgo-rag-beat:RAG Beat"
        "tgo-ai:AI服务"
        "tgo-plugin-runtime:Plugin Runtime"
        "tgo-device-control:Device Control"
        "tgo-workflow:Workflow服务"
        "tgo-workflow-worker:Workflow Worker"
        "tgo-api:API服务"
        "tgo-platform:Platform服务"
        "tgo-web:Web前端"
        "tgo-widget-js:Widget前端"
    )
    
    for service in "${services[@]}"; do
        IFS=':' read -r container name <<< "$service"
        status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")
        if [ "$status" == "running" ]; then
            echo -e "  ${GREEN}✓${NC} $name ($container): $status"
        else
            echo -e "  ${RED}✗${NC} $name ($container): $status"
        fi
    done
    echo ""
}

health_check() {
    log_info "健康检查..."
    echo ""
    
    echo "API Health:"
    curl -s http://127.0.0.1:8000/health && echo "" || echo "  API 服务未响应"
    
    echo "AI Health:"
    curl -s http://127.0.0.1:8081/health && echo "" || echo "  AI 服务未响应"
    
    echo "RAG Health:"
    curl -s http://127.0.0.1:8082/health && echo "" || echo "  RAG 服务未响应"
    
    echo "WuKongIM Health:"
    curl -s http://127.0.0.1:5001/health && echo "" || echo "  WuKongIM 服务未响应"
    
    echo "Web:"
    curl -s -o /dev/null -w "  HTTP Status: %{http_code}\n" http://127.0.0.1:18080/
    
    echo "Widget:"
    curl -s -o /dev/null -w "  HTTP Status: %{http_code}\n" http://127.0.0.1:18081/
    echo ""
}

show_info() {
    log_info "部署完成!"
    echo ""
    echo "=========================================="
    echo "服务访问地址:"
    echo "=========================================="
    echo "  Web管理后台:    http://127.0.0.1:18080"
    echo "  Widget组件:     http://127.0.0.1:18081"
    echo "  API服务:        http://127.0.0.1:8000"
    echo "  WuKongIM API:   http://127.0.0.1:5001"
    echo "  WuKongIM WS:    ws://127.0.0.1:5200"
    echo "=========================================="
    echo ""
    echo "宝塔 Nginx 配置请参考: deploy-guide.md"
    echo ""
    echo "常用命令:"
    echo "  查看日志:   docker-compose -f docker-compose.standalone.yml logs -f [服务名]"
    echo "  重启服务:   docker-compose -f docker-compose.standalone.yml restart [服务名]"
    echo "  停止服务:   docker-compose -f docker-compose.standalone.yml down"
    echo "  查看状态:   docker-compose -f docker-compose.standalone.yml ps"
    echo ""
}

main() {
    echo ""
    echo "=========================================="
    echo "  TGO 单机部署脚本"
    echo "=========================================="
    echo ""
    
    check_docker
    setup_env
    create_directories
    pull_images
    start_services
    sleep 5
    check_services
    health_check
    show_info
}

main "$@"
