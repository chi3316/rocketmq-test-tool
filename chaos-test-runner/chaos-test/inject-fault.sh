#!/bin/sh
CHAOSMESH_YAML_FILE=$1  
LOG_FILE=$2  
DURITION=$3 
POD_NAME=$4
NS=$5

export KUBECTL_PATH=/usr/local/bin/kubectl

if [ ! -f "$CHAOSMESH_YAML_FILE" ]; then
  echo "Chaos Mesh YAML file not found: $CHAOSMESH_YAML_FILE"
  exit 1
fi

current_millis() {
  echo $(( $(date +%s%N) / 1000000 ))
}

log_fault_event() {
  event_type=$1
  fault_type=$2
  timestamp=$(current_millis)
  $KUBECTL_PATH exec -i $POD_NAME -n ${NS} -c sidecar-container -- /bin/sh -c "echo -e 'fault\t$fault_type\t$event_type\t$timestamp' >> $LOG_FILE"
}

inject_fault() {
  $KUBECTL_PATH apply -f $CHAOSMESH_YAML_FILE &
  apply_pid=$!

  while ! $KUBECTL_PATH get -f $CHAOSMESH_YAML_FILE > /dev/null 2>&1; do
    sleep 1  # 每秒钟检查一次
  done

  log_fault_event "start" "chaos-mesh-fault"
  
  wait $apply_pid
}

clear_fault() {
  $KUBECTL_PATH delete -f $CHAOSMESH_YAML_FILE &
  delete_pid=$!

  while $KUBECTL_PATH get -f $CHAOSMESH_YAML_FILE > /dev/null 2>&1; do
    sleep 1  
  done

  log_fault_event "end" "chaos-mesh-fault"
  
  wait $delete_pid
}

inject_fault

# Wait for a period of time equal to the duration of a single fault
sleep $DURITION

clear_fault
