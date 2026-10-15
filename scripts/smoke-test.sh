#!/usr/bin/env bash
set -Eeuo pipefail
BASE=${1:-http://localhost}
EXPECTED_VERSION=${2:-}
python3 - "$BASE" "$EXPECTED_VERSION" <<'PY'
import sys,json,urllib.request,http.cookiejar
base,expected=sys.argv[1:]
opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
def request(path,data=None):
    body=None if data is None else json.dumps(data).encode()
    req=urllib.request.Request(base+path,data=body,headers={'Content-Type':'application/json'})
    with opener.open(req,timeout=10) as r: return json.load(r)
assert request('/readyz')['status']=='ready'
v=request('/version')['version']
assert not expected or v==expected,(v,expected)
e=request('/api/calculate',dict(a=7,b=6,operation='multiply'))
assert e['result']==42,e
assert request('/api/history')[0]['result']==42
print('PASS readiness, version, calculation and session history; version='+v)
PY
