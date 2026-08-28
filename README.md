# Docker Runtime

All-in-one 开发/运行时容器，集成 MySQL 8.0、Redis、Nginx 和 Java 17 运行环境。适用于快速部署 Spring Boot 应用及前端静态资源。

基于 **Debian 12 (ARM64)**。

## 目录

- [包含组件](#包含组件)
- [快速开始](#快速开始)
- [环境变量](#环境变量)
- [数据持久化](#数据持久化)
- [部署 Java 应用](#部署-java-应用)
- [部署前端资源](#部署前端资源)
- [Nginx 配置](#nginx-配置)
- [构建镜像](#构建镜像)
- [常用命令](#常用命令)
- [Supervisor 管理](#supervisor-管理)
- [目录结构](#目录结构)

## 包含组件

| 组件 | 版本 | 端口 | 说明 |
|------|------|------|------|
| MySQL | 8.0.46 | 3306 | ARM64 Generic Binary |
| Redis | Debian 默认 | 6379 | 密码认证 |
| Nginx | Debian 默认 | 80, 443 | 静态资源反向代理 |
| Java (JRE) | OpenJDK 17 | 8080 | Spring Boot 运行环境 |
| Supervisor | Debian 默认 | - | 进程管理 |

## 快速开始

```bash
# 启动容器
docker compose up -d

# 查看日志
docker compose logs -f
```

启动后自动完成：
1. 初始化 MySQL 数据库（首次启动）
2. 创建 root 用户和默认数据库
3. 配置 Redis 密码认证
4. 扫描 `/opt/app` 下所有 JAR 文件并自动注册为 Supervisor 管理的进程
5. 启动所有服务

## 环境变量

在 `compose.yaml` 中配置：

```yaml
environment:
  TZ: Asia/Shanghai

  # MySQL
  MYSQL_ROOT_PASSWORD: "mysqlpasswd"      # root 密码（默认: root123456）
  MYSQL_DATABASE: "app"                   # 默认数据库（默认: app）
  MYSQL_USER: "app"                       # 普通用户（默认: app）
  MYSQL_PASSWORD: "app123456"             # 普通用户密码（默认: app123456）

  # Redis
  REDIS_PASSWORD: "redispasswd"           # Redis 密码（默认: redis123456）
```

> **注意：** 环境变量仅在 MySQL **首次初始化** 时生效。如果数据目录已存在，修改环境变量不会更新密码。需要重置密码请清空 MySQL 数据目录后重新启动。

## 数据持久化

默认情况下容器内数据不持久化。如需持久化，取消注释 `compose.yaml` 中对应的 volume：

```yaml
volumes:
  # MySQL 数据
  - ./mysql:/var/lib/mysql

  # Redis 数据
  - ./redis:/var/lib/redis

  # Spring Boot 配置文件（如 application.yml）
  - ./config:/opt/app/config
```

## 部署 Java 应用

将 JAR 文件放入 `/opt/app` 目录，容器启动时会自动扫描并注册为 Supervisor 进程。

### 目录结构示例

```
/opt/app/
├── user-service/
│   └── user-service.jar
├── order-service/
│   └── order-service.jar
└── gateway/
    └── gateway.jar
```

### 在 compose.yaml 中挂载

```yaml
volumes:
  # JAR 包目录
  - /path/to/your/jars:/opt/app

  # 配置文件目录（可选）
  - ./config:/opt/app/config
```

### 自动注册机制

容器启动时，`entrypoint.sh` 会：

1. 扫描 `/opt/app` 下所有 `*.jar` 文件
2. 为每个 JAR 自动生成 Supervisor 配置文件（存放在 `/etc/supervisor/java.d/`）
3. 配置规则：进程名从路径自动生成，例如 `/opt/app/user/user-service.jar` → `java-user-user-service`

### JVM 参数

默认启动命令为 `java -jar <jar-file>`。如需自定义 JVM 参数，可以修改 Supervisor 配置。

## 部署前端资源

前端静态资源挂载到容器内对应路径，由 Nginx 提供服务：

```yaml
volumes:
  - /path/to/your/dist:/data/ai-model-manage/dist
```

## Nginx 配置

Nginx 配置通过 volume 挂载：

```yaml
volumes:
  - /etc/nginx/nginx.conf:/etc/nginx/nginx.conf
```

容器内默认端口：
- `80` — HTTP
- `443` — HTTPS（需配置 SSL 证书）

## 构建镜像

### 基础构建

```bash
docker build -t runtime:1.5 .
```

### 使用代理构建

如果网络受限，可通过 build args 传入代理：

```bash
docker build \
  --build-arg HTTP_PROXY=http://your-proxy:port \
  --build-arg HTTPS_PROXY=http://your-proxy:port \
  -t runtime:1.5 .
```

## 常用命令

```bash
# 启动
docker compose up -d

# 停止
docker compose down

# 重启
docker compose restart

# 查看日志
docker compose logs -f

# 查看容器状态
docker compose ps

# 进入容器
docker compose exec runtime bash

# 查看所有进程
docker compose exec runtime supervisorctl status

# 重启单个 Java 服务
docker compose exec runtime supervisorctl restart java-user-user-service

# 查看 MySQL
docker compose exec runtime mysql -uroot -p

# 查看 Redis
docker compose exec runtime redis-cli
```

## Supervisor 管理

Supervisor 是容器内的进程管理器，管理 MySQL、Redis、Nginx 以及所有自动发现的 Java 应用。

```bash
# 查看所有进程状态
supervisorctl status

# 停止某个进程
supervisorctl stop <program-name>

# 重启某个进程
supervisorctl restart <program-name>

# 重启所有进程
supervisorctl restart all

# 查看日志
supervisorctl tail -f <program-name>
```

日志文件位于 `/var/log/` 目录下：
- `mysql-supervisor.log` / `mysql-supervisor-error.log`
- `redis-supervisor.log` / `redis-supervisor-error.log`
- `nginx-supervisor.log` / `nginx-supervisor-error.log`
- `java-<service-name>.log` / `java-<service-name>-error.log`

## 目录结构

```
├── Dockerfile           # 镜像构建文件
├── compose.yaml         # Docker Compose 编排
├── entrypoint.sh        # 容器启动入口脚本
├── my.cnf               # MySQL 配置
└── supervisord.conf     # Supervisor 配置
```

容器内关键路径：

```
/usr/local/mysql/          # MySQL 安装目录
/etc/mysql/my.cnf          # MySQL 配置
/var/lib/mysql/            # MySQL 数据目录
/etc/redis/redis.conf      # Redis 配置
/var/lib/redis/            # Redis 数据目录
/opt/app/                  # Java 应用目录（挂载 JAR 包）
/opt/app/config/           # Spring Boot 配置目录
/etc/supervisor/           # Supervisor 配置
/etc/supervisor/java.d/    # 自动生成的 Java 进程配置
/var/log/                  # 日志目录
/data/ai-model-manage/dist # 前端静态资源目录
```
