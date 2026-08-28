FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# ============================================================
# Build Args
# 仅用于构建阶段
# ============================================================

ARG HTTP_PROXY
ARG HTTPS_PROXY

# Docker BuildKit 自动提供
# amd64 / arm64
ARG TARGETARCH

# ============================================================
# MySQL
# ============================================================

ENV MYSQL_VERSION=8.4.11
ENV MYSQL_BASE=/usr/local/mysql
ENV MYSQL_DATA=/var/lib/mysql

# ============================================================
# 1. 安装运行时依赖
# ============================================================

RUN export http_proxy="${HTTP_PROXY}" && \
    export https_proxy="${HTTPS_PROXY}" && \
    export HTTP_PROXY="${HTTP_PROXY}" && \
    export HTTPS_PROXY="${HTTPS_PROXY}" && \
    echo 'Acquire::Retries "10";' \
        > /etc/apt/apt.conf.d/80-retries && \
    echo 'Acquire::http::Pipeline-Depth "0";' \
        > /etc/apt/apt.conf.d/80-pipeline && \
    apt-get update && \
    apt-get install -y \
        --no-install-recommends \
        ca-certificates \
        wget \
        xz-utils \
        libaio1 \
        libncurses6 \
        libnuma1 \
        openjdk-17-jre-headless \
        redis-server \
        nginx \
        supervisor \
        procps && \
    rm -rf \
        /var/lib/apt/lists/* \
        /var/cache/apt/* \
        /etc/apt/apt.conf.d/80-retries \
        /etc/apt/apt.conf.d/80-pipeline

# ============================================================
# 2. 安装 MySQL 8.4.11 Generic Binary
#
# 自动根据 Debian 容器架构选择：
#
# amd64 -> x86_64
# arm64 -> aarch64
# ============================================================

RUN groupadd -r mysql && \
    useradd -r \
        -g mysql \
        -s /usr/sbin/nologin \
        mysql && \
    mkdir -p \
        /var/lib/mysql \
        /var/log/mysql \
        /var/run/mysqld && \
    chown -R mysql:mysql \
        /var/lib/mysql \
        /var/log/mysql \
        /var/run/mysqld && \
    export http_proxy="${HTTP_PROXY}" && \
    export https_proxy="${HTTPS_PROXY}" && \
    export HTTP_PROXY="${HTTP_PROXY}" && \
    export HTTPS_PROXY="${HTTPS_PROXY}" && \
    ARCH="$(dpkg --print-architecture)" && \
    if [ "${ARCH}" = "amd64" ]; then \
        MYSQL_ARCH="x86_64"; \
    elif [ "${ARCH}" = "arm64" ]; then \
        MYSQL_ARCH="aarch64"; \
    else \
        echo "ERROR: Unsupported architecture: ${ARCH}"; \
        echo "Supported architectures: amd64, arm64"; \
        exit 1; \
    fi && \
    echo "========================================" && \
    echo "Installing MySQL ${MYSQL_VERSION}" && \
    echo "Debian ARCH : ${ARCH}" && \
    echo "MySQL ARCH  : ${MYSQL_ARCH}" && \
    echo "========================================" && \
    wget -q \
        "https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-${MYSQL_VERSION}-linux-glibc2.28-${MYSQL_ARCH}.tar.xz" \
        -O /tmp/mysql.tar.xz && \
    tar -xJf /tmp/mysql.tar.xz -C /usr/local && \
    mv \
        "/usr/local/mysql-${MYSQL_VERSION}-linux-glibc2.28-${MYSQL_ARCH}" \
        "${MYSQL_BASE}" && \
    rm -f /tmp/mysql.tar.xz && \
    ln -sf \
        "${MYSQL_BASE}/bin/mysql" \
        /usr/local/bin/mysql && \
    ln -sf \
        "${MYSQL_BASE}/bin/mysqld" \
        /usr/local/bin/mysqld && \
    ln -sf \
        "${MYSQL_BASE}/bin/mysqladmin" \
        /usr/local/bin/mysqladmin && \
    chown -R mysql:mysql "${MYSQL_BASE}"

# ============================================================
# 3. MySQL 配置
# ============================================================

RUN mkdir -p /etc/mysql

COPY my.cnf /etc/mysql/my.cnf

RUN chown root:root /etc/mysql/my.cnf && \
    chmod 644 /etc/mysql/my.cnf

# ============================================================
# 4. Redis 配置
#
# Supervisor 管理 Redis
# 必须以前台模式运行
# ============================================================

RUN sed -i \
        's/^daemonize yes/daemonize no/' \
        /etc/redis/redis.conf && \
    sed -i \
        's/^supervised .*/supervised no/' \
        /etc/redis/redis.conf && \
    mkdir -p /var/lib/redis && \
    chown -R redis:redis /var/lib/redis

# ============================================================
# 5. Java 应用目录
# ============================================================

RUN mkdir -p \
        /opt/app \
        /opt/app/config

# ============================================================
# 6. Supervisor
# ============================================================

COPY supervisord.conf /etc/supervisor/supervisord.conf

# ============================================================
# 7. EntryPoint
# ============================================================

COPY entrypoint.sh /entrypoint.sh

RUN chmod 755 /entrypoint.sh

# ============================================================
# 8. Volume
# ============================================================

VOLUME [ \
    "/var/lib/mysql", \
    "/var/lib/redis", \
    "/opt/app" \
]

# ============================================================
# 9. 端口
# ============================================================

EXPOSE 80
EXPOSE 443
EXPOSE 3306
EXPOSE 6379
EXPOSE 8080

# ============================================================
# 10. 启动
# ============================================================

ENTRYPOINT ["/entrypoint.sh"]