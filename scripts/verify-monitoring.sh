#!/usr/bin/env bash
# Run on the server after deploying the full stack. Uses the private Prometheus port.
set -Eeuo pipefail
python3 - <<'PY'
import json,time,urllib.request,urllib.parse
queries={
 'Prometheus': 'up{job="prometheus"}',
 'App scrape': 'up{job="calculator"}',
 'Node Exporter': 'up{job="node"}',
 'cAdvisor': 'up{job="cadvisor"}',
 'Blackbox': 'probe_success{job="blackbox"}',
 'Host RAM': 'node_memory_MemAvailable_bytes',
 'Host disk': 'node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay"}',
 'App RAM': 'container_memory_working_set_bytes{container_label_com_docker_compose_service="app",image!=""}',
 'App memory limit': 'container_spec_memory_limit_bytes{container_label_com_docker_compose_service="app",image!=""}',
 'App CPU quota': 'container_spec_cpu_quota{container_label_com_docker_compose_service="app",image!=""}',
 'Page counter': 'calculator_page_views_total',
}
for attempt in range(12):
 failed=[]
 for name,q in queries.items():
  try:
   url='http://127.0.0.1:9090/api/v1/query?'+urllib.parse.urlencode({'query':q})
   with urllib.request.urlopen(url,timeout=8) as r: data=json.load(r)
   values=data.get('data',{}).get('result',[])
   if not values or any(float(v['value'][1])<=0 for v in values) and name!='Page counter': failed.append(name)
  except Exception as e: failed.append(name+': '+str(e))
 if not failed: print('PASS all monitoring targets and required host/container metrics');break
 if attempt==11: raise SystemExit('FAIL missing/zero metrics: '+', '.join(failed))
 print('Waiting for scrape: '+', '.join(failed),flush=True);time.sleep(5)
PY
