#!/usr/bin/env bash

# ++-----------
# ||   06 - Start gafana-agent for Consul nodes
# ++------
header1 "Observe Consul service mesh traffic"

# ++-----------------+
# || Variables       |
# ++-----------------+

export STEP_ASSETS="${SCENARIO_OUTPUT_FOLDER}conf/"

export NODES_ARRAY=( "hashicups-db" "hashicups-api" "hashicups-frontend" "hashicups-nginx" )

# ++-----------------+
# || Begin           |
# ++-----------------+

mkdir -p ${STEP_ASSETS}monitoring

header2 "Consul server monitoring"

## todo make all servers discoverable from bastion host
for i in `seq 0 "$((SERVER_NUMBER-1))"`; do

  log_debug "Generate Grafana Agent configuration for consul-server-$i "
  tee ${STEP_ASSETS}monitoring/consul-server-$i.yaml > /dev/null << EOF
server:
  log_level: debug

metrics:
  global:
    scrape_interval: 60s
    remote_write:
    - url: http://${PROMETHEUS_URI}:9009/api/v1/push
  configs:
  - name: default
    scrape_configs:
    - job_name: consul-server
      metrics_path: '/v1/agent/metrics'
      static_configs:
        - targets: ['127.0.0.1:8500']

logs:
  configs:
  - name: default
    clients:
      - url: http://${LOKI_URI}:3100/loki/api/v1/push
    positions:
      filename: /tmp/positions.yaml
    scrape_configs:
     - job_name: consul-server
       static_configs:
       - targets: 
           - localhost
         labels:
           job: logs
           host: consul-server-$i
           __path__: /tmp/*.log
EOF

  log_debug "Stop pre-existing agent processes"
  ## Stop already running Envoy processes (helps idempotency)
  _G_AGENT_PID=`remote_exec consul-server-$i "pidof grafana-agent"`
  if [ ! -z "${_G_AGENT_PID}" ]; then
    remote_exec consul-server-$i "sudo kill -9 ${_G_AGENT_PID}"
  fi

  log_debug "Copy configuration"
  remote_copy consul-server-$i "${STEP_ASSETS}monitoring/consul-server-$i.yaml" "~/grafana-agent.yaml" 

  log "Start Grafana agent"
  # set -x
  remote_exec -o consul-server-$i "bash -c '/usr/bin/grafana-agent -config.file ~/grafana-agent.yaml > /tmp/grafana-agent.log 2>&1 &'"

  # set +x

done

header2 "Consul client monitoring"

for node in "${NODES_ARRAY[@]}"; do

  # header3 "Register Consul Service for ${node}"

  NUM="${node/-/_}""_NUMBER"
  
  for i in `seq ${!NUM}`; do

    export NODE_NAME="${node}-$((i-1))"

    # header3 "Register service for ${NODE_NAME}"
    
    # log "Copy Configuration for ${NODE_NAME}"
    header3 "Start monitoring for ${NODE_NAME}"

    log_debug "Generate Grafana Agent configuration for ${NODE_NAME} "

    tee ${STEP_ASSETS}monitoring/${NODE_NAME}.yaml > /dev/null << EOF
server:
  log_level: debug

metrics:
  global:
    scrape_interval: 60s
    remote_write:
    - url: http://${PROMETHEUS_URI}:9009/api/v1/push
  configs:
  - name: default
    scrape_configs:
    - job_name: ${NODE_NAME}
      metrics_path: '/stats/prometheus'
      static_configs:
        - targets: ['127.0.0.1:19000']
    - job_name: consul-agent
      metrics_path: '/v1/agent/metrics'
      static_configs:
        - targets: ['127.0.0.1:8500']

logs:
  configs:
  - name: default
    clients:
      - url: http://${LOKI_URI}:3100/loki/api/v1/push
    positions:
      filename: /tmp/positions.yaml
    scrape_configs:
     - job_name: service-mesh-apps
       static_configs:
       - targets: 
           - localhost
         labels:
           job: logs
           host: ${NODE_NAME}
           __path__: /tmp/*.log
EOF

    log_debug "Stop pre-existing agent processes"
    ## Stop already running Envoy processes (helps idempotency)
    _G_AGENT_PID=`remote_exec ${NODE_NAME} "pidof grafana-agent"`
    if [ ! -z "${_G_AGENT_PID}" ]; then
      remote_exec ${NODE_NAME} "sudo kill -9 ${_G_AGENT_PID}"
    fi

    log_debug "Copy configuration"
    remote_copy ${NODE_NAME} "${STEP_ASSETS}monitoring/${NODE_NAME}.yaml" "~/grafana-agent.yaml" 

    log "Start Grafana agent"

    remote_exec -o ${NODE_NAME} "bash -c '/usr/bin/grafana-agent -config.file ~/grafana-agent.yaml > /tmp/grafana-agent.log 2>&1 &'"
    
    set +x 

  done
done
