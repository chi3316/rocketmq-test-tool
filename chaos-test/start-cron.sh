#!/bin/sh
CHAOSMESH_YAML_FILE=$1
LOG_FILE=$2
LIMIT_TIME=$3
POD_NAME=$4
ns=$5
REPORT_DIR=$6
CRON='* * * * *'

cleanup() {
  echo "Performing cleanup..."
  crontab -r
  kubectl cp -n ${ns} $POD_NAME:/chaos-framework/report "$REPORT_DIR"
  ls /home/runner/work/image-repo/chaos-test-report
  kubectl delete deployment openchaos-controller -n ${ns}
  kubectl delete pod $POD_NAME -n ${ns}
  echo "Cleanup completed..."
}

# 设置 trap 捕获脚本退出或中断信号
trap cleanup EXIT

# start openchaos
kubectl exec -it $POD_NAME -n ${ns} -c openchaos-controller -- /bin/sh -c "./start-openchaos.sh --driver driver-rocketmq/rocketmq.yaml -u rocketmq --output-dir ./report -t 180" &

# start cron scheduler
./cron-scheduler.sh "$CRON" /root/chaos-test/inject_fault_cron.sh "$CHAOSMESH_YAML_FILE" "$LOG_FILE" "$LIMIT_TIME" "$POD_NAME" "$ns"

# 等待后台进程完成
wait
