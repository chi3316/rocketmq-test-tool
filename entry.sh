#!/bin/sh -l
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

ACTION=$1
VERSION=$2
ASK_CONFIG=$3
DOCKER_REPO_USERNAME=$4
DOCKER_REPO_PASSWORD=$5
CHART_GIT=$6
CHART_BRANCH=$7
CHART_PATH=$8
TEST_CODE_GIT=${9}
TEST_CODE_BRANCH=${10}
TEST_CODE_PATH=${11}
TEST_CMD_BASE=${12}
JOB_INDEX=${13}
HELM_VALUES=${14}

export VERSION
export CHART_GIT
export CHART_BRANCH
export CHART_PATH
export REPO_NAME=`echo ${GITHUB_REPOSITORY#*/} | sed -e "s/\//-/g" | cut -c1-36 | tr '[A-Z]' '[a-z]'`
export WORKFLOW_NAME=${GITHUB_WORKFLOW}
export RUN_ID=${GITHUB_RUN_ID}
export TEST_CODE_GIT
export TEST_CODE_BRANCH
export TEST_CODE_PATH
export YAML_VALUES=`echo "${HELM_VALUES}" | sed -s 's/^/          /g'`

echo "Start test version: ${GITHUB_REPOSITORY}@${VERSION}"

echo "************************************"
echo "*          Set config...           *"
echo "************************************"
mkdir -p ${HOME}/.kube
kube_config=$(echo "${ASK_CONFIG}")
echo "${kube_config}" > ${HOME}/.kube/config
export KUBECONFIG="${HOME}/.kube/config"

# 先用helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm version

# 启用vela的fluxcd插件，可能是版本太新了，默认已经移除了type=helm的类型，需要通过插件启用
vela addon enable fluxcd

VELA_APP_TEMPLATE='
apiVersion: core.oam.dev/v1beta1
kind: Application
metadata:
  name: ${VELA_APP_NAME}
  description: ${REPO_NAME}-${WORKFLOW_NAME}-${RUN_ID}@${VERSION}
spec:
  components:
    - name: ${REPO_NAME}
      type: helm
      properties:
        chart: ${CHART_PATH}
        git:
          branch: ${CHART_BRANCH}
        repoType: git
        retries: 3
        secretRef: \047\047
        url: ${CHART_GIT}
        values:
${YAML_VALUES}'

echo -e "${VELA_APP_TEMPLATE}" > ./velaapp.yaml
sed -i '1d' ./velaapp.yaml

env_uuid=${REPO_NAME}-${GITHUB_RUN_ID}-${JOB_INDEX}


if [ ${ACTION} == "deploy" ]; then
  echo "************************************"
  echo "*     Create env and deploy...     *"
  echo "************************************"

  echo ${VERSION}: ${env_uuid} deploy start

  # vela env init ${env_uuid} --namespace ${env_uuid}

  export VELA_APP_NAME=${env_uuid}
  envsubst < ./velaapp.yaml > velaapp-${REPO_NAME}.yaml
  cat velaapp-${REPO_NAME}.yaml

  # vela env set ${env_uuid}
  # vela up -f "velaapp-${REPO_NAME}.yaml"
  kubectl create ns ${env_uuid}
  helm install rocketmq -n ${env_uuid} /root/chaos-test/rocketmq-k8s-helm/
  app="rocketmq"

# 检查 Helm release 状态
check_helm_release_status() {
  status=$(helm status ${app} -n ${env_uuid} | grep "STATUS:" | awk '{print $2}')
  if [ "${status}" == "deployed" ]; then
    return 0
  else
    return 1
  fi
}

# 检查所有 Pods 的状态
check_pods_status() {
  not_ready_pods=$(kubectl get pods -n ${env_uuid} --no-headers | grep -v "Running" | wc -l)
  if [ "$not_ready_pods" -ne 0 ]; then
    return 0
  else 
    return 1
  fi
}

# 等待 Helm release 和 Pods 都准备好
let count=0
while true; do
  if check_helm_release_status && check_pods_status; then
    echo "Helm release and all Pods are ready"
    kubectl get pods -n ${env_uuid}
    break
  fi

  if [ $count -gt 240 ]; then
    echo "Deployment timeout..."
    exit 1
  fi

  echo "Waiting for Helm release and Pods to be ready..."
  sleep 5
  let count=${count}+1
done
  # app=${env_uuid}

  # status=`vela status ${app} -n ${app}`
  # echo $status
  # res=`echo $status | grep "Create helm release successfully"`
  # let count=0
  # while [ -z "$res" ]
  # do
  #     if [ $count -gt 240 ]; then
  #       echo "env ${app} deploy timeout..."
  #       exit 1
  #     fi
  #     echo "waiting for env ${app} ready..."
  #     sleep 5
  #     status=`vela status ${app} -n ${app}`
  #     stopped=`echo $status | grep "not found"`
  #     if [ ! -z "$stopped" ]; then
  #         echo "env ${app} deploy stopped..."
  #         exit 1
  #     fi
  #     res=`echo $status | grep "Create helm release successfully"`
  #     let count=${count}+1
  # done
fi

TEST_POD_TEMPLATE='
apiVersion: v1
kind: Pod
metadata:
  name: ${test_pod_name}
  namespace: ${ns}
spec:
  restartPolicy: Never
  containers:
  - name: ${test_pod_name}
    image: cloudnativeofalibabacloud/test-runner:v0.0.3
    resources:
          limits:
            cpu: "8"
            memory: "8Gi"
          requests:
            cpu: "8"
            memory: "8Gi"
    env:
    - name: CODE
      value: ${TEST_CODE_GIT}
    - name: BRANCH
      value: ${TEST_CODE_BRANCH}
    - name: CODE_PATH
      value: ${TEST_CODE_PATH}
    - name: ALL_IP
      value: ${ALL_IP}
    - name: CMD
      value: |
${TEST_CMD}
'

echo -e "${TEST_POD_TEMPLATE}" > ./testpod.yaml
sed -i '1d' ./testpod.yaml

if [ ${ACTION} == "test" ]; then
  echo "************************************"
  echo "*            E2E Test...           *"
  echo "************************************"

  ns=${env_uuid}
  test_pod_name=test-${env_uuid}-${RANDOM}
  export test_pod_name

  echo namespace: $ns
  all_pod_name=`kubectl get pods --no-headers -o custom-columns=":metadata.name" -n ${ns}`
  ALL_IP=""
  for pod in $all_pod_name;
  do
      if [ ! -z `echo "${pod}" | grep "test-${env_uuid}"` ]; then
        continue
      fi
      POD_HOST=$(kubectl get pod ${pod} --template={{.status.podIP}} -n ${ns})
      ALL_IP=${pod}:${POD_HOST},${ALL_IP}
  done

  echo $ALL_IP
  echo $TEST_CODE_GIT
  echo $TEST_CMD_BASE

  export ALL_IP
  export ns

  TEST_CMD=`echo "${TEST_CMD_BASE}" | sed -s 's/^/        /g'`

  echo $TEST_CMD
  export TEST_CMD

  envsubst < ./testpod.yaml > ./testpod-${ns}.yaml
  cat ./testpod-${ns}.yaml

  kubectl apply -f ./testpod-${ns}.yaml

  sleep 5

  pod_status=`kubectl get pod ${test_pod_name} --template={{.status.phase}} -n ${ns}`
  if [ -z "$pod_status" ]; then
      pod_status="Pending"
  fi

  while [ "${pod_status}" == "Pending" ] || [ "${pod_status}" == "Running" ]
  do
      echo waiting for ${test_pod_name} test done...
      sleep 5
      pod_status=`kubectl get pod ${test_pod_name} --template={{.status.phase}} -n ${ns}`
      if [ -z "$pod_status" ]; then
          pod_status="Pending"
      fi
      test_done=`kubectl exec -i ${test_pod_name} -n ${ns} -- ls /root | grep testdone`
      if [ ! -z "$test_done" ]; then
        echo "Test status: test done"
          if [ ! -d "./test_report" ]; then
            echo "Copy test reports"
            kubectl cp --retries=10 ${test_pod_name}:/root/testlog.txt testlog.txt -n ${ns}
            mkdir -p test_report
            cd test_report
            kubectl cp --retries=10 ${test_pod_name}:/root/code/${TEST_CODE_PATH}/target/surefire-reports/. . -n ${ns}
            rm -rf *.txt
            ls
            cd -
          fi
      fi
  done

  exit_code=`kubectl get pod ${test_pod_name} --output="jsonpath={.status.containerStatuses[].state.terminated.exitCode}" -n ${ns}`
  kubectl delete pod ${test_pod_name} -n ${ns}
  echo E2E Test exit code: ${exit_code}
  exit ${exit_code}
fi

if [ ${ACTION} == "test_local" ]; then
  echo "************************************"
  echo "*        E2E Test local...         *"
  echo "************************************"

  wget https://dlcdn.apache.org/maven/maven-3/3.8.7/binaries/apache-maven-3.8.7-bin.tar.gz
  tar -zxvf apache-maven-3.8.7-bin.tar.gz -C /opt/
  export PATH=$PATH:/opt/apache-maven-3.8.7/bin

  ns=${env_uuid}

  echo namespace: $ns
  all_pod_name=`kubectl get pods --no-headers -o custom-columns=":metadata.name" -n ${ns}`
  ALL_IP=""
  for pod in $all_pod_name;
  do
      label=`kubectl get pod ${pod} --output="jsonpath={.metadata.labels.app\.kubernetes\.io/name}" -n ${ns}`
      pod_port=`kubectl get -o json services --selector="app.kubernetes.io/name=${label}" -n ${ns} | jq -r '.items[].spec.ports[].port'`
      echo "${pod}: ${pod_port}"
      for port in ${pod_port};
      do
          kubectl port-forward ${pod} ${port}:${port} -n ${ns} &
          res=$?
          if [ ${res} -ne 0 ]; then
            echo "kubectl port-forward error: ${pod} ${port}:${port}"
            exit ${res}
          fi
      done
      ALL_IP=${pod}:"127.0.0.1",${ALL_IP}
      sleep 3
  done

  echo $ALL_IP
  echo $TEST_CODE_GIT
  echo $TEST_CMD_BASE

  export ALL_IP
  export ns
  is_mvn_cmd=`echo $TEST_CMD_BASE | grep "mvn"`
  if [ ! -z "$is_mvn_cmd" ]; then
      TEST_CMD="$TEST_CMD_BASE -DALL_IP=${ALL_IP}"
  else
      TEST_CMD=$TEST_CMD_BASE
  fi
  echo $TEST_CMD

  git clone $TEST_CODE_GIT -b $TEST_CODE_BRANCH code

  cd code
  cd $TEST_CODE_PATH
  ${TEST_CMD}
  exit_code=$?

  killall kubectl
  exit ${exit_code}
fi

if [ ${ACTION} == "chaos-test" ]; then
    echo "************************************"
    echo "*         Chaos test...            *"
    echo "************************************"

    # 启动crond
    crond

    # 检查 crond 是否成功启动
    if ps aux | grep '[c]rond' > /dev/null
    then
        echo "crond is running"
    else
        echo "Failed to start crond"
        exit 1
    fi

    # 使用helm部署chaos-mesh
    helm repo add chaos-mesh https://charts.chaos-mesh.org
    kubectl create ns chaos-mesh
    helm install chaos-mesh chaos-mesh/chaos-mesh -n=chaos-mesh --set chaosDaemon.runtime=containerd --set chaosDaemon.socketPath=/run/containerd/containerd.sock --version 2.6.3
    
    # 检查 Chaos Mesh Pod 状态
    check_chaos_mesh_pods_status() {
      not_ready_pods=$(kubectl get pods -n chaos-mesh --no-headers | grep -v "Running" | wc -l)
      if [ "$not_ready_pods" -ne 0 ]; then
        return 0
      else 
        return 1
      fi
    }

    # 等待 Chaos Mesh Pods 都准备好
    let count=0
    while true; do
      if check_chaos_mesh_pods_status; then
        echo "Chaos Mesh Pods are ready" --no-headers
        kubectl get pods -n chaos-mesh
        break
      fi

      if [ $count -gt 240 ]; then
        echo "Chaos Mesh deployment timeout..."
        exit 1
      fi

      echo "Waiting for Chaos Mesh Pods to be ready..."
      sleep 5
      let count=${count}+1
    done
    
    # 部署一个测试Pod：openchaos-controller
    # 创建 ConfigMap
    kubectl apply -f /root/chaos-test/openchaos/driver-rocketmq.yaml -n ${env_uuid}

    # 部署 openchaos-controller Pod
    kubectl apply -f /root/chaos-test/openchaos/chaos-controller.yaml -n ${env_uuid}
    sleep 10
    
    test_pod_name=$(kubectl get pods -n ${env_uuid} -l app=openchaos-controller -o jsonpath='{.items[0].metadata.name}')
    
    # 检查 openchaos-controller Pod 状态
    check_test_pod_status() {
      pod_status=$(kubectl get pod ${test_pod_name} -n ${env_uuid} --template={{.status.phase}})
      if [ -z "$pod_status" ]; then
        pod_status="Pending"
      fi
      if [[ "${pod_status}" == "Pending" || "${pod_status}" == "Running" ]]; then
        return 1
      else
        return 0
      fi
    }

    # 等待 openchaos-controller Pod 准备好
    let count=0
    while true; do
      if check_test_pod_status; then
        echo "openchaos-controller Pod is ready"
        break
      fi

      if [ $count -gt 240 ]; then
        echo "openchaos-controller Pod deployment timeout..."
        exit 1
      fi

      echo "Waiting for openchaos-controller Pod to be ready..."
      sleep 5
      let count=${count}+1
    done

    # 执行启动脚本
    mkdir /root/chaos-test/report
    sh /root/chaos-test/start-cron.sh /root/chaos-test/fault.yaml /chaos-framework/report/chaos-mesh-fault 30 "$test_pod_name"

fi

if [ ${ACTION} == "clean" ]; then
    echo "************************************"
    echo "*       Delete app and env...      *"
    echo "************************************"

    env=${env_uuid}

    # vela delete ${env} -n ${env} -y
    all_pod_name=`kubectl get pods --no-headers -o custom-columns=":metadata.name" -n ${env}`
    for pod in $all_pod_name;
    do
      kubectl delete pod ${pod} -n ${env}
    done

    sleep 30

    kubectl proxy &
    PID=$!
    sleep 3

    DELETE_ENV=${env}

    helm uninstall rocketmq
    helm uninstall chaos-mesh
    # vela env delete ${DELETE_ENV} -y
    sleep 3
    kubectl delete namespace ${DELETE_ENV} --wait=false
    kubectl get ns ${DELETE_ENV} -o json | jq '.spec.finalizers=[]' > ns-without-finalizers.json
    cat ns-without-finalizers.json
    curl -X PUT http://localhost:8001/api/v1/namespaces/${DELETE_ENV}/finalize -H "Content-Type: application/json" --data-binary @ns-without-finalizers.json

    kill $PID
fi

if [ ${ACTION} == "try" ]; then
  kubectl get pods --all-namespaces
fi


