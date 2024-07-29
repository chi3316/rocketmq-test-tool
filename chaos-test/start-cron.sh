#!/bin/sh
CHAOSMESH_YAML_FILE=$1
LOG_FILE=$2
LIMIT_TIME=$3
POD_NAME=$4
CRON='* * * * *'

cleanup() {
  echo "Performing cleanup..."
  crontab -r
  kubectl cp $POD_NAME:/chaos-framework/report  /root/chaos-test/report
  kubectl delete deployment openchaos-controller
  kubectl delete pod $POD_NAME
  echo "Cleanup completed."
}

# 设置 trap 捕获脚本退出或中断信号
trap cleanup EXIT

# start openchaos
kubectl exec -it $POD_NAME -c openchaos-controller -- /bin/sh -c "./start-openchaos.sh --driver driver-rocketmq/rocketmq.yaml -u rocketmq --output-dir ./report -t 180" &

# start cron scheduler
./cron-scheduler.sh $CRON /home/chichi/rocketmq-chaos-test/starter-cron/inject_fault_cron.sh "$CHAOSMESH_YAML_FILE" "$LOG_FILE" "$LIMIT_TIME" "$POD_NAME"

# 等待后台进程完成
wait
