# TGO 单机部署指南

> 适用于: CentOS 7 + 宝塔面板 + Docker

## 一、部署步骤

### 1. 上传文件到服务器

将以下文件上传到服务器 `/www/wwwroot/tgo/` 目录:

```
docker-compose.standalone.yml
.env.standalone.example
deploy.sh
```

### 2. 配置环境变量

```bash
cd /www/wwwroot/tgo

# 复制配置模板
cp .env.standalone.example .env

# 编辑配置
vi .env
```

**必须修改的配置项:**

| 配置项 | 说明 | 示例 |
|--------|------|------|
| `SERVER_HOST` | 服务器公网IP | `123.45.67.89` |
| `POSTGRES_PASSWORD` | 数据库密码 | `YourStrongPassword123!` |
| `VITE_API_BASE_URL` | API地址 | `https://your-domain.com/api` |
| `WUKONGIM_WSS_ADDR` | WebSocket地址 (HTTPS下必须用wss) | `wss://your-domain.com/ws` |

> ⚠️ **重要**: 如果你的网站使用 HTTPS，WebSocket 地址必须使用 `wss://` 协议，否则浏览器会阻止 WebSocket 连接。

### 3. 执行部署脚本

```bash
cd /www/wwwroot/tgo

# 添加执行权限
chmod +x deploy.sh

# 执行部署
./deploy.sh
```

### 4. 验证服务

```bash
# 检查所有容器状态
docker ps

# 健康检查
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8081/health
curl http://127.0.0.1:8082/health
curl http://127.0.0.1:5001/health
```

---

## 二、宝塔 Nginx 配置

> ⚠️ **注意**: 宝塔面板的反向代理功能只能添加一条规则，无法配置多个路径。请使用以下方式直接修改 Nginx 配置文件。

### 步骤

1. 打开宝塔面板 -> 网站 -> 添加站点
2. 填写域名，PHP版本选择"纯静态"
3. 点击站点设置 -> 配置文件
4. 将配置文件内容替换为以下内容 (注意修改 `your-domain.com` 为你的域名):

```nginx
server {
    listen 80;
    listen 443 ssl http2;
    server_name your-domain.com;
    
    # SSL配置 (在宝塔面板中配置SSL后会自动生成)
    # ssl_certificate    /www/server/panel/vhost/cert/your-domain.com/fullchain.pem;
    # ssl_certificate_key    /www/server/panel/vhost/cert/your-domain.com/privkey.pem;
    # ssl_protocols TLSv1.2 TLSv1.3;
    
    # 日志
    access_log /www/wwwlogs/tgo.access.log;
    error_log /www/wwwlogs/tgo.error.log;
    
    # 客户端上传大小限制
    client_max_body_size 100m;
    
    # API 反向代理
    location /api/ {
        rewrite ^/api(/.*)$ $1 break;
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
    
    # WebSocket 反向代理 (WuKongIM)
    location /ws {
        rewrite ^/ws/?(.*)$ /$1 break;
        proxy_pass http://127.0.0.1:5200;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_connect_timeout 60s;
        proxy_buffering off;
        proxy_cache_bypass $http_upgrade;
    }
    
    # Widget 反向代理
    location /widget/ {
        rewrite ^/widget(/.*)$ $1 break;
        proxy_pass http://127.0.0.1:18081;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # 静态资源
    location /assets/ {
        proxy_pass http://127.0.0.1:18080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 静态资源缓存
        expires 7d;
        add_header Cache-Control "public, immutable";
    }
    
    # Web 前端 (放在最后作为默认路由)
    location / {
        proxy_pass http://127.0.0.1:18080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## 三、服务端口说明

| 服务 | 容器端口 | 主机端口 | 说明 |
|------|----------|----------|------|
| tgo-web | 80 | 18080 | 管理后台前端 |
| tgo-widget-js | 80 | 18081 | 访客组件前端 |
| tgo-api | 8000 | 8000 | 核心API服务 |
| tgo-ai | 8081 | 8081 | AI服务 |
| tgo-rag | 8082 | 8082 | RAG服务 |
| wukongim | 5001/5100/5200/5300 | 同左 | IM服务 |

---

## 四、常用命令

```bash
# 进入项目目录
cd /www/wwwroot/tgo

# 查看所有服务状态
docker-compose -f docker-compose.standalone.yml ps

# 查看服务日志
docker-compose -f docker-compose.standalone.yml logs -f tgo-api
docker-compose -f docker-compose.standalone.yml logs -f tgo-ai

# 重启单个服务
docker-compose -f docker-compose.standalone.yml restart tgo-api

# 重启所有服务
docker-compose -f docker-compose.standalone.yml restart

# 停止所有服务
docker-compose -f docker-compose.standalone.yml down

# 启动所有服务
docker-compose -f docker-compose.standalone.yml up -d

# 更新镜像并重启
docker-compose -f docker-compose.standalone.yml pull
docker-compose -f docker-compose.standalone.yml up -d
```

---

## 五、故障排查

### 1. 服务无法启动

```bash
# 查看容器日志
docker logs tgo-api
docker logs tgo-ai
docker logs tgo-rag

# 检查容器状态
docker inspect tgo-api
```

### 2. 数据库连接失败

```bash
# 检查 PostgreSQL 是否运行
docker logs tgo-postgres

# 进入数据库容器
docker exec -it tgo-postgres psql -U tgo -d tgo
```

### 3. WebSocket 连接失败

- 确保 Nginx 配置了 `/ws` 路径的反向代理
- HTTPS 下必须使用 `wss://` 协议
- 检查 WuKongIM 服务状态: `docker logs tgo-wukongim`

### 4. 前端无法访问后端

- 检查 `.env` 中的 `VITE_API_BASE_URL` 配置
- 确保 Nginx `/api/` 反向代理配置正确
- 检查 API 服务健康状态: `curl http://127.0.0.1:8000/health`

---

## 六、文件结构

```
/www/wwwroot/tgo/
├── docker-compose.standalone.yml  # Docker Compose 配置
├── .env.standalone.example        # 环境变量模板
├── .env                           # 环境变量 (需创建)
├── deploy.sh                      # 部署脚本
├── deploy-guide.md                # 本文档
└── data/                          # 数据目录 (自动创建)
    ├── postgres/                  # PostgreSQL 数据
    ├── redis/                     # Redis 数据
    ├── wukongim/                  # WuKongIM 数据
    ├── tgo-api/uploads/           # API 上传文件
    ├── tgo-rag/uploads/           # RAG 上传文件
    ├── plugins/                   # 插件目录
    └── skills/                    # 技能目录
```

---

## 七、安全建议

1. **修改默认密码**: 修改 `.env` 中的 `POSTGRES_PASSWORD`
2. **配置防火墙**: 只开放 80/443 端口，其他端口不要对外暴露
3. **启用 HTTPS**: 在宝塔面板中配置 SSL 证书
4. **定期备份**: 备份 `data/` 目录和数据库
