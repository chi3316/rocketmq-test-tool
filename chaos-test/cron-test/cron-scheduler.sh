#!/bin/bash

# 检查是否有两个参数
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 '<cron_expression>' '<script_path> [script_args...]'"
    exit 1
fi

# 获取cron表达式和脚本路径
CRON_EXPR="$1"
SCRIPT_PATH="$2"
shift 2 # 移除前两个参数，剩下的是脚本参数
SCRIPT_ARGS="$@"

# 构建cron作业的命令
CRON_JOB="$CRON_EXPR $SCRIPT_PATH $SCRIPT_ARGS"

# 查看现有的cron作业
(crontab -l 2>/dev/null; echo "$CRON_JOB") | sort - | uniq - | crontab -