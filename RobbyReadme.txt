已帮你加好了，之后你只需要这两个命令：

# 一键启动（现在会检查所有服务是否正常启动）
make up-full

# 一键停止（干净地停止所有服务）
make down-full

# 查看 Worker 状态
make workers-status

# 查看 Worker 日志
make workers-logs
我已经实际验证过 Makefile，新命令可识别且流程正确（包含 Node 20 切换、基础设施、迁移、全服务、RAG/Workflow worker）。

你现在重启电脑后，进入项目目录直接执行：

cd /home/vboxuser/tgo-project
make up-full