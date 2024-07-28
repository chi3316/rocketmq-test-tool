#!/bin/sh

# Chaos Mesh 注入故障脚本
CHAOSMESH_YAML_FILE=$1  # e.g., "chaos_experiment.yaml"
LOG_FILE=$2  # e.g., "/path/to/chaos_mesh_log.txt"
LIMIT_TIME=$3
POD_NAME=$4

current_millis() {
  echo $(($(date +%s%N)/1000000))
}

log_fault_event() {
  local event_type=$1
  local fault_type=$2
  local timestamp=$(current_millis)
  echo -e "$POD_NAME : fault\t$fault_type\t$event_type\t$timestamp" >> $LOG_FILE
  kubectl exec -it $POD_NAME -c sidecar-container -- /bin/sh -c "echo -e 'fault\t$fault_type\t$event_type\t$timestamp' >> $LOG_FILE"
}

inject_fault() {
  log_fault_event "start" "chaos-mesh-fault"
  kubectl apply -f $CHAOSMESH_YAML_FILE
}

clear_fault() {
  kubectl delete -f $CHAOSMESH_YAML_FILE
  log_fault_event "end" "chaos-mesh-fault"
}

# 注入 Chaos Mesh 故障
inject_fault

# 等待一段时间，要跟单个故障持续时间对应
sleep $LIMIT_TIME

# 清理 Chaos Mesh 故障
clear_fault

