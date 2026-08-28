#!/bin/bash

set -e

MYSQL_DATA="/var/lib/mysql"
MYSQL_BASE="/usr/local/mysql"

APP_DIR="/opt/app"

SUPERVISOR_JAVA_DIR="/etc/supervisor/java.d"

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root123456}"
MYSQL_DATABASE="${MYSQL_DATABASE:-app}"
MYSQL_USER="${MYSQL_USER:-app}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-app123456}"

REDIS_PASSWORD="${REDIS_PASSWORD:-redis123456}"


echo "========================================"
echo " My Runtime Container"
echo "========================================"


# ============================================================
# 1. MySQL
# ============================================================

echo "[1/4] Checking MySQL data directory..."


if [ ! -d "${MYSQL_DATA}/mysql" ]; then

    echo "MySQL is not initialized."
    echo "Initializing MySQL..."


    mkdir -p "${MYSQL_DATA}"

    chown -R mysql:mysql "${MYSQL_DATA}"


    "${MYSQL_BASE}/bin/mysqld" \
        --defaults-file=/etc/mysql/my.cnf \
        --initialize-insecure \
        --user=mysql


    echo "MySQL initialization completed."

    echo "Starting temporary MySQL..."


    "${MYSQL_BASE}/bin/mysqld" \
        --defaults-file=/etc/mysql/my.cnf \
        --user=mysql \
        --skip-networking &

    MYSQL_PID=$!


    echo "Waiting for MySQL..."


    MYSQL_READY=false


    for i in {1..60}; do

        if "${MYSQL_BASE}/bin/mysqladmin" \
            --socket=/var/run/mysqld/mysqld.sock \
            ping >/dev/null 2>&1; then

            MYSQL_READY=true

            break

        fi

        sleep 1

    done


    if [ "${MYSQL_READY}" != "true" ]; then

        echo "ERROR: MySQL failed to start."

        kill "${MYSQL_PID}" 2>/dev/null || true

        exit 1

    fi


    echo "Configuring MySQL..."


    "${MYSQL_BASE}/bin/mysql" \
        --socket=/var/run/mysqld/mysqld.sock \
        -uroot <<SQL

ALTER USER 'root'@'localhost'
IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';


CREATE USER IF NOT EXISTS 'root'@'%'
IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';


ALTER USER 'root'@'%'
IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';


GRANT ALL PRIVILEGES
ON *.*
TO 'root'@'%'
WITH GRANT OPTION;


CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`
CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_ai_ci;


CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%'
IDENTIFIED BY '${MYSQL_PASSWORD}';


ALTER USER '${MYSQL_USER}'@'%'
IDENTIFIED BY '${MYSQL_PASSWORD}';


GRANT ALL PRIVILEGES
ON \`${MYSQL_DATABASE}\`.* 
TO '${MYSQL_USER}'@'%';


FLUSH PRIVILEGES;

SQL


    echo "Stopping temporary MySQL..."


    kill "${MYSQL_PID}"

    wait "${MYSQL_PID}" || true


    echo "MySQL first initialization completed."


else

    echo "Existing MySQL data found."
    echo "Skipping initialization."

fi


# ============================================================
# 2. Redis
# ============================================================

echo "[2/4] Preparing Redis..."

mkdir -p /var/lib/redis

chown -R redis:redis /var/lib/redis


echo "Configuring Redis external access..."

# 监听所有 IPv4 地址
sed -i \
    's/^bind .*/bind 0.0.0.0/' \
    /etc/redis/redis.conf

# 关闭 protected-mode
sed -i \
    's/^protected-mode .*/protected-mode no/' \
    /etc/redis/redis.conf

# 前台运行
sed -i \
    's/^daemonize .*/daemonize no/' \
    /etc/redis/redis.conf

# Supervisor 管理 Redis
sed -i \
    's/^supervised .*/supervised no/' \
    /etc/redis/redis.conf

# 设置 Redis 密码
if grep -qE '^#?[[:space:]]*requirepass ' /etc/redis/redis.conf; then

    sed -i \
        "s/^#\?[[:space:]]*requirepass .*/requirepass ${REDIS_PASSWORD}/" \
        /etc/redis/redis.conf

else

    echo "requirepass ${REDIS_PASSWORD}" \
        >> /etc/redis/redis.conf

fi


echo "Redis external access enabled."
echo "Redis password authentication enabled."


# ============================================================
# 3. Java
# ============================================================

echo "[3/4] Preparing application..."

mkdir -p "${APP_DIR}"
mkdir -p "${APP_DIR}/config"
mkdir -p "${SUPERVISOR_JAVA_DIR}"

# 删除旧的自动生成配置
rm -f "${SUPERVISOR_JAVA_DIR}"/*.conf

echo "Scanning Java applications..."

JAR_COUNT=0

# ------------------------------------------------------------
# 查找所有 JAR
# 使用临时文件避免 process substitution
# ------------------------------------------------------------

JAR_LIST="/tmp/java-jars.list"

find "${APP_DIR}" \
    -type f \
    -name "*.jar" \
    -print > "${JAR_LIST}"

# ------------------------------------------------------------
# 读取 JAR 到数组
# ------------------------------------------------------------

JAR_FILES=()

while IFS= read -r JAR; do
    [ -z "${JAR}" ] && continue
    JAR_FILES+=("${JAR}")
done < "${JAR_LIST}"

rm -f "${JAR_LIST}"

# ------------------------------------------------------------
# 遍历 JAR 数组
# ------------------------------------------------------------

for JAR in "${JAR_FILES[@]}"; do

    JAR_COUNT=$((JAR_COUNT + 1))

    # --------------------------------------------------------
    # 获取相对路径
    # --------------------------------------------------------

    RELATIVE_PATH="${JAR#${APP_DIR}/}"

    # --------------------------------------------------------
    # 转换为安全的 Supervisor 名称
    #
    # /opt/app/user/user-service.jar
    #
    # =>
    #
    # java-user-user-service
    # --------------------------------------------------------

    SAFE_NAME="$(
        echo "${RELATIVE_PATH}" \
        | sed 's/\.jar$//' \
        | sed 's#[^a-zA-Z0-9_-]#-#g'
    )"

    PROGRAM_NAME="java-${SAFE_NAME}"

    CONFIG_FILE="${SUPERVISOR_JAVA_DIR}/${PROGRAM_NAME}.conf"

    echo "Found JAR:"
    echo "  ${RELATIVE_PATH}"
    echo "  Supervisor: ${PROGRAM_NAME}"

    # --------------------------------------------------------
    # 获取 JAR 所在目录
    # --------------------------------------------------------

    JAR_DIRECTORY="$(dirname "${JAR}")"

    # --------------------------------------------------------
    # 创建 Supervisor 配置
    # --------------------------------------------------------

    cat > "${CONFIG_FILE}" <<EOF
[program:${PROGRAM_NAME}]
command=/usr/bin/java -jar ${JAR}
directory=${JAR_DIRECTORY}

autostart=true
autorestart=true

startsecs=5
startretries=3

stopasgroup=true
killasgroup=true

stdout_logfile=/var/log/${PROGRAM_NAME}.log
stderr_logfile=/var/log/${PROGRAM_NAME}-error.log

environment=TZ="Asia/Shanghai"
EOF

done

echo "Found ${JAR_COUNT} Java application(s)."


# ============================================================
# 4. Supervisor
# ============================================================

echo "[4/4] Starting Supervisor..."


exec /usr/bin/supervisord \
    -c /etc/supervisor/supervisord.conf