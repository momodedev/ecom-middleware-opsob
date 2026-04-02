param()
$ErrorActionPreference = 'Stop'

$controlIp = '20.14.74.130'
$sshUser = 'azureadmin'
$sshPort = 6666
$sshKey = 'C:/Users/v-chengzhiz/.ssh/id_rsa'
$repoPath = '~/ecom-middleware-opsob'
$scriptPath = '~/ecom-middleware-opsob/ansible_ob_centos/scripts/run_oceanbase_benchmark_nmysql_p.sh'
$remoteOut = '/tmp/oceanbase-bench'
$localOut = 'C:/Users/v-chengzhiz/Downloads/ecom-middleware-opsob/benchmark_results'
$baselineLocal = 'C:/Users/v-chengzhiz/Downloads/ecom-middleware-opsob/benchmark_results/20260330T041000Z_d8s_v5_centos_nmysql.csv'
$baselineRemote = '/tmp/oceanbase-bench/20260330T041000Z_d8s_v5_centos_nmysql.csv'

New-Item -ItemType Directory -Force -Path $localOut | Out-Null
$runTs = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$masterLog = Join-Path $localOut ("${runTs}_obproxy_16cycle_master.log")
$manifest = Join-Path $localOut ("${runTs}_obproxy_16cycle_manifest.txt")
$summaryJson = Join-Path $localOut ("${runTs}_obproxy_16cycle_summary.json")

$sshBase = "ssh --% -i $sshKey -p $sshPort $sshUser@$controlIp"
$scpBase = "scp -i $sshKey -P $sshPort"

function Invoke-Ssh($cmd) {
  $full = "$sshBase \"$cmd\""
  $out = Invoke-Expression $full 2>&1
  return ,$out
}

"START_UTC=$runTs" | Tee-Object -FilePath $masterLog -Append | Out-Null

if (-not (Test-Path $baselineLocal)) { throw "Baseline not found: $baselineLocal" }
Invoke-Expression "$scpBase \"$baselineLocal\" $sshUser@$controlIp:$baselineRemote" | Out-Null
"BASELINE_COPIED=$baselineRemote" | Tee-Object -FilePath $masterLog -Append | Out-Null

$cycleSummaries = @()

for ($cycle=1; $cycle -le 16; $cycle++) {
  $cycleTs = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
  $cycleLabel = "d8s_v5_centos_nmysql_cycle$cycle"
  $cyclePrefix = "${cycleTs}_${cycleLabel}"
  $cycleLogLocal = Join-Path $localOut ("${cyclePrefix}_cycle.log")
  $cycleSummaryLocal = Join-Path $localOut ("${cyclePrefix}_summary.txt")

  "CYCLE_START N=$cycle/16 TS=$cycleTs LABEL=$cycleLabel" | Tee-Object -FilePath $masterLog -Append | Tee-Object -FilePath $cycleLogLocal -Append | Out-Null

  $cfgOut = Invoke-Ssh "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -pOceanBase#!123 -N -e 'SELECT @@ob_trx_timeout,@@ob_trx_lock_timeout,@@ob_query_timeout,@@ob_sql_work_area_percentage;' 2>/dev/null || true"
  "CONFIG_SNAPSHOT $($cfgOut -join ' ')" | Tee-Object -FilePath $masterLog -Append | Tee-Object -FilePath $cycleLogLocal -Append | Out-Null

  $gateOk = $false
  for ($retry=1; $retry -le 3; $retry++) {
    "GATE_ATTEMPT=$retry" | Tee-Object -FilePath $masterLog -Append | Tee-Object -FilePath $cycleLogLocal -Append | Out-Null
    $gateCmd = @"
set -e
mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -pOceanBase#!123 -e \"DROP DATABASE IF EXISTS sbtest; CREATE DATABASE sbtest;\"
sysbench --db-driver=mysql --mysql-host=127.0.0.1 --mysql-port=2883 --mysql-user=root@sbtest_tenant --mysql-password=OceanBase#!123 --mysql-db=sbtest --tables=90 --table-size=500000 --threads=10 --db-ps-mode=auto --create_secondary=off oltp_read_only prepare >$remoteOut/${cyclePrefix}_gate_prepare.log 2>&1
cnt=\$(mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -pOceanBase#!123 -N -e \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='sbtest' AND table_name REGEXP '^sbtest[0-9]+$';\" 2>/dev/null || echo 0)
echo TABLE_COUNT=\$cnt
[ \"\$cnt\" = \"90\" ]
sysbench --db-driver=mysql --mysql-host=127.0.0.1 --mysql-port=2883 --mysql-user=root@sbtest_tenant --mysql-password=OceanBase#!123 --mysql-db=sbtest --tables=90 --table-size=500000 --events=0 --report-interval=5 --db-ps-mode=auto --threads=20 --time=15 oltp_read_only run >$remoteOut/${cyclePrefix}_gate_smoke.log 2>&1
rc=\$?
echo SMOKE_RC=\$rc
exit \$rc
"@
    $gateOut = Invoke-Ssh $gateCmd
    $gateText = ($gateOut -join "`n")
    $gateStatusCmd = "test -s $remoteOut/${cyclePrefix}_gate_smoke.log; echo RC=$?; tail -20 $remoteOut/${cyclePrefix}_gate_smoke.log 2>/dev/null || true"
    $gateStatusOut = Invoke-Ssh $gateStatusCmd
    "GATE_OUTPUT $gateText" | Tee-Object -FilePath $masterLog -Append | Tee-Object -FilePath $cycleLogLocal -Append | Out-Null
    "GATE_SMOKE_TAIL $($gateStatusOut -join ' ')" | Tee-Object -FilePath $masterLog -Append | Tee-Object -FilePath $cycleLogLocal -Append | Out-Null

    if ($gateText -match 'SMOKE_RC=0') { $gateOk = $true; break }
    Start-Sleep -Seconds (10 * $retry)
  }

  if (-not $gateOk) {
    "CYCLE_COMPLETE N=$cycle/16 STATUS=failed REASON=gate_failed" | Tee-Object -FilePath $masterLog -Append | Tee-Object -FilePath $cycleLogLocal -Append | Out-Null
    $remoteGlob = "$remoteOut/${cyclePrefix}*"
    Invoke-Expression "$scpBase $sshUser@$controlIp:$remoteGlob \"$localOut/\"" 2>$null | Out-Null
    $cycleSummaries += [pscustomobject]@{cycle=$cycle;status='failed';reason='gate_failed';csv='';avg_tps_delta_pct='';avg_p95_delta_pct='';tuning='none'}
    continue
  }

  "BENCH_RUNNING N=$cycle/16" | Tee-Object -FilePath $masterLog -Append | Tee-Object -FilePath $cycleLogLocal -Append | Out-Null

  $benchCmd = @"
set -e
source ~/ansible-venv/bin/activate
cd $repoPath/ansible_ob_centos/scripts
chmod +x $scriptPath
nohup sudo $scriptPath $cycleLabel 127.0.0.1 root@sbtest_tenant 'OceanBase#!123' sbtest '10.100.1.4 10.100.1.5 10.100.1.6' > $remoteOut/${cyclePrefix}_run.log 2>&1 &
echo PID=\$!
"@
  $benchStartOut = Invoke-Ssh $benchCmd
  $pidLine = ($benchStartOut | Where-Object { $_ -match '^PID=' } | Select-Object -First 1)
  $pid = if ($pidLine) { $pidLine.Split('=')[1] } else { '' }

  $latestCsv = ''
  for ($poll=1; $poll -le 180; $poll++) {
    Start-Sleep -Seconds 30
    $pollCmd = "latest=\$(ls -t $remoteOut/*_${cycleLabel}.csv 2>/dev/null | head -1); if [ -n \"\$latest\" ]; then lines=\$(wc -l < \"\$latest\" 2>/dev/null || echo 0); echo CSV=\$latest LINES=\$lines; fi; if [ -n '$pid' ]; then ps -p $pid >/dev/null 2>&1; echo RUNNING=\$?; else pgrep -f '${cycleLabel}' >/dev/null 2>&1; echo RUNNING=\$?; fi"
    $pollOut = Invoke-Ssh $pollCmd
    $pollText = ($pollOut -join ' ')
    if ($poll -eq 1 -or $poll % 6 -eq 0) {
      "BENCH_RUNNING N=$cycle/16 POLL=$poll $pollText" | Tee-Object -FilePath $masterLog -Append | Tee-Object -FilePath $cycleLogLocal -Append | Out-Null
    }
    if ($pollText -match 'CSV=([^ ]+)') { $latestCsv = $Matches[1] }
    if ($pollText -match 'RUNNING=1') { break }
  }

  if ([string]::IsNullOrWhiteSpace($latestCsv)) {
    $findOut = Invoke-Ssh "ls -t $remoteOut/*_${cycleLabel}.csv 2>/dev/null | head -1"
    $latestCsv = ($findOut | Select-Object -First 1).Trim()
  }

  $cmpCmd = @"
python3 - <<'PY'
import csv, json, sys
base='$baselineRemote'
cur='$latestCsv'
out='$remoteOut/${cyclePrefix}_comparison.json'

def load(path):
    rows={}
    with open(path,newline='') as f:
        for r in csv.DictReader(f):
            if r.get('workload') in ('oltp_read_only','oltp_read_write') and str(r.get('threads')) in ('20','50','100','200'):
                rows[(r['workload'],r['threads'])]=r
    return rows

b=load(base)
c=load(cur) if cur else {}
points=[]
for k,v in c.items():
    if k not in b: continue
    bt=float(b[k].get('tps') or 0)
    ct=float(v.get('tps') or 0)
    bp=float(b[k].get('p95_ms') or b[k].get('p95_latency') or 0)
    cp=float(v.get('p95_ms') or v.get('p95_latency') or 0)
    if bt>0:
        tps_delta=(ct-bt)/bt*100
    else:
        tps_delta=0
    if bp>0:
        p95_delta=(cp-bp)/bp*100
    else:
        p95_delta=0
    points.append({'workload':k[0],'threads':int(k[1]),'tps_delta_pct':tps_delta,'p95_delta_pct':p95_delta,'cur_tps':ct,'base_tps':bt,'cur_p95':cp,'base_p95':bp})
summary={'point_count':len(points),'avg_tps_delta_pct':(sum(p['tps_delta_pct'] for p in points)/len(points) if points else 0.0),'avg_p95_delta_pct':(sum(p['p95_delta_pct'] for p in points)/len(points) if points else 0.0),'points':points}
with open(out,'w') as f: json.dump(summary,f,indent=2)
print(json.dumps(summary))
PY
"@
  $cmpOut = Invoke-Ssh $cmpCmd
  $cmpText = ($cmpOut -join "`n")

  $avgTps = 0.0
  $avgP95 = 0.0
  if ($cmpText -match '"avg_tps_delta_pct"\s*:\s*([-0-9.]+)') { $avgTps = [double]$Matches[1] }
  if ($cmpText -match '"avg_p95_delta_pct"\s*:\s*([-0-9.]+)') { $avgP95 = [double]$Matches[1] }

  $tuningSql = @()
  if ($avgP95 -gt 25) {
    $tuningSql += "SET GLOBAL ob_query_timeout=1200000000"
    $tuningSql += "SET GLOBAL ob_trx_timeout=180000000"
    $tuningSql += "SET GLOBAL ob_trx_lock_timeout=15000000"
    $tuningSql += "SET GLOBAL ob_sql_work_area_percentage=30"
  } elseif ($avgTps -lt -15) {
    $tuningSql += "SET GLOBAL ob_query_timeout=1000000000"
    $tuningSql += "SET GLOBAL ob_trx_timeout=120000000"
    $tuningSql += "SET GLOBAL ob_trx_lock_timeout=10000000"
    $tuningSql += "SET GLOBAL ob_sql_work_area_percentage=25"
  } else {
    $tuningSql += "SET GLOBAL ob_query_timeout=800000000"
    $tuningSql += "SET GLOBAL ob_trx_timeout=120000000"
    $tuningSql += "SET GLOBAL ob_trx_lock_timeout=10000000"
    $tuningSql += "SET GLOBAL ob_sql_work_area_percentage=20"
  }
  $tuningPayload = ($tuningSql -join '; ') + '; SELECT @@ob_trx_timeout,@@ob_trx_lock_timeout,@@ob_query_timeout,@@ob_sql_work_area_percentage;'
  $tuneCmd = "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -pOceanBase#!123 -N -e \"$tuningPayload\" > $remoteOut/${cyclePrefix}_tuning.log 2>&1; rc=\$?; echo TUNE_RC=\$rc; tail -20 $remoteOut/${cyclePrefix}_tuning.log"
  $tuneOut = Invoke-Ssh $tuneCmd

  $status = 'success'
  if ([string]::IsNullOrWhiteSpace($latestCsv)) { $status = 'failed' }

  "CYCLE_RESULT N=$cycle/16 CSV=$latestCsv AVG_TPS_DELTA=$avgTps AVG_P95_DELTA=$avgP95 STATUS=$status" | Tee-Object -FilePath $masterLog -Append | Tee-Object -FilePath $cycleLogLocal -Append | Out-Null
  "TUNING_APPLIED N=$cycle/16 SQL=$($tuningSql -join ' | ')" | Tee-Object -FilePath $masterLog -Append | Tee-Object -FilePath $cycleLogLocal -Append | Out-Null

  $artifactPattern = "$remoteOut/*${cyclePrefix}*"
  Invoke-Expression "$scpBase $sshUser@$controlIp:$artifactPattern \"$localOut/\"" 2>$null | Out-Null

  "CYCLE_COMPLETE N=$cycle/16 STATUS=$status" | Tee-Object -FilePath $masterLog -Append | Tee-Object -FilePath $cycleLogLocal -Append | Out-Null

  @(
    "cycle=$cycle"
    "timestamp=$cycleTs"
    "csv=$latestCsv"
    "avg_tps_delta_pct=$avgTps"
    "avg_p95_delta_pct=$avgP95"
    "status=$status"
    "tuning_sql=$($tuningSql -join '; ')"
  ) | Set-Content -Path $cycleSummaryLocal

  $cycleSummaries += [pscustomobject]@{
    cycle = $cycle
    status = $status
    reason = ''
    csv = $latestCsv
    avg_tps_delta_pct = $avgTps
    avg_p95_delta_pct = $avgP95
    tuning = ($tuningSql -join '; ')
  }
}

$cycleSummaries | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryJson
Get-ChildItem -Path $localOut -File | Sort-Object Name | ForEach-Object { $_.FullName } | Set-Content -Path $manifest

"FINISHED_UTC=$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))" | Tee-Object -FilePath $masterLog -Append | Out-Null
"SUMMARY_JSON=$summaryJson" | Tee-Object -FilePath $masterLog -Append | Out-Null
"MANIFEST=$manifest" | Tee-Object -FilePath $masterLog -Append | Out-Null
