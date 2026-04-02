$ErrorActionPreference = 'Stop'

$ControlIp = '20.14.74.130'
$SshUser = 'azureadmin'
$SshPort = 6666
$SshKey = 'C:/Users/v-chengzhiz/.ssh/id_rsa'
$RemoteRepo = '/home/azureadmin/ecom-middleware-opsob'
$RemoteBenchScript = '/home/azureadmin/ecom-middleware-opsob/ansible_ob_centos/scripts/run_oceanbase_benchmark_nmysql_p.sh'
$RemoteOut = '/tmp/oceanbase-bench'
$ArtifactRoot = 'benchmark_results/loop16_obproxy_centos_exp2'
$RunSuffix = 'd8s_v5_centos_nmysql_p_loop16'
$BaselineLocal = 'benchmark_results/20260330T041000Z_d8s_v5_centos_nmysql.csv'
$ObserverIps = '10.100.1.4 10.100.1.5 10.100.1.6'

$Workspace = (Get-Location).Path
$LocalBenchScript = Join-Path $Workspace 'ansible_ob_centos/scripts/run_oceanbase_benchmark_nmysql_p.sh'
$ArtifactRootAbs = Join-Path $Workspace $ArtifactRoot
$BaselineAbs = Join-Path $Workspace $BaselineLocal
$MasterTs = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$RunRoot = Join-Path $ArtifactRootAbs $MasterTs
$MasterLog = Join-Path $RunRoot 'master.log'
$MasterSummary = Join-Path $RunRoot 'final_summary.md'

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

function LogLine([string]$line) {
  $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  "$ts $line" | Tee-Object -FilePath $MasterLog -Append | Out-Null
}

function Invoke-Ssh([string]$cmd, [int]$retries=3, [int]$sleepSec=8) {
  for ($a=1; $a -le $retries; $a++) {
    $out = & ssh '-i' $SshKey '-p' $SshPort "${SshUser}@${ControlIp}" $cmd 2>&1
    if ($LASTEXITCODE -eq 0) { return ,$out }
    if ($a -lt $retries) { LogLine "RETRY ssh attempt=$a reason=exit_$LASTEXITCODE"; Start-Sleep -Seconds ($sleepSec * $a) }
  }
  throw 'SSH command failed after retries'
}

function Invoke-Scp([string]$source, [string]$dest, [int]$retries=3) {
  for ($a=1; $a -le $retries; $a++) {
    & scp '-i' $SshKey '-P' $SshPort $source $dest 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { return }
    if ($a -lt $retries) { LogLine "RETRY scp attempt=$a source=$source"; Start-Sleep -Seconds (6 * $a) }
  }
  throw "SCP failed for $source"
}

function Filter-Points([object[]]$rows) {
  $rows | Where-Object { $_.workload -in @('oltp_read_only','oltp_read_write') -and $_.threads -in @('20','50','100','200') }
}

function Compare-Csv([string]$baselinePath, [string]$currentPath) {
  $base = Filter-Points (Import-Csv -Path $baselinePath)
  $cur = Filter-Points (Import-Csv -Path $currentPath)
  $res = @()
  foreach ($r in $cur) {
    $m = $base | Where-Object { $_.workload -eq $r.workload -and $_.threads -eq $r.threads } | Select-Object -First 1
    if (-not $m) { continue }
    $bt = [double]$m.tps; $ct = [double]$r.tps
    $bp = [double]$m.p95_ms; $cp = [double]$r.p95_ms
    $ba = [double]$m.avg_latency_ms; $ca = [double]$r.avg_latency_ms
    $tpsDelta = if ($bt -ne 0) { (($ct - $bt) / $bt) * 100 } else { 0 }
    $p95Delta = if ($bp -ne 0) { (($cp - $bp) / $bp) * 100 } else { 0 }
    $avgDelta = if ($ba -ne 0) { (($ca - $ba) / $ba) * 100 } else { 0 }
    $res += [pscustomobject]@{ workload=$r.workload; threads=[int]$r.threads; tps_delta_pct=[math]::Round($tpsDelta,2); p95_delta_pct=[math]::Round($p95Delta,2); avg_delta_pct=[math]::Round($avgDelta,2); errors=[int]$r.errors; status=$r.status; exit_code=[int]$r.exit_code }
  }
  $avgTps = if ($res.Count) { [math]::Round((($res | Measure-Object tps_delta_pct -Average).Average),2) } else { 0 }
  $avgP95 = if ($res.Count) { [math]::Round((($res | Measure-Object p95_delta_pct -Average).Average),2) } else { 0 }
  $avgAvg = if ($res.Count) { [math]::Round((($res | Measure-Object avg_delta_pct -Average).Average),2) } else { 0 }
  $failed = ($res | Where-Object { $_.status -ne 'ok' -or $_.exit_code -ne 0 }).Count
  $errs = [int](($res | Measure-Object errors -Sum).Sum)
  [pscustomobject]@{ points=$res; avg_tps_delta_pct=$avgTps; avg_p95_delta_pct=$avgP95; avg_avg_delta_pct=$avgAvg; failed_cases=$failed; total_errors=$errs }
}

function Analyze-And-Tune([object]$cmp, [string]$iterDir) {
  $findings = @()
  if ($cmp.failed_cases -gt 0 -or $cmp.total_errors -gt 0) { $findings += 'Failed cases/errors suggest lock waits, retries, or OBProxy reroute pressure.' }
  if ($cmp.avg_tps_delta_pct -lt -15) { $findings += 'TPS regression indicates queueing or execution-path stalls under concurrency.' }
  if ($cmp.avg_p95_delta_pct -gt 25) { $findings += 'p95 tail growth indicates long-wait transactions and timeout pressure.' }
  if (-not $findings.Count) { $findings += 'Mixed profile; apply balanced timeout/work-area tuning and remeasure.' }

  $tuning = @('SET GLOBAL ob_query_timeout=800000000','SET GLOBAL ob_trx_timeout=120000000','SET GLOBAL ob_trx_lock_timeout=10000000','SET GLOBAL ob_sql_work_area_percentage=20')
  if ($cmp.failed_cases -gt 0 -or $cmp.total_errors -gt 0 -or $cmp.avg_p95_delta_pct -gt 25) {
    $tuning = @('SET GLOBAL ob_query_timeout=1200000000','SET GLOBAL ob_trx_timeout=180000000','SET GLOBAL ob_trx_lock_timeout=15000000','SET GLOBAL ob_sql_work_area_percentage=30')
  } elseif ($cmp.avg_tps_delta_pct -lt -15) {
    $tuning = @('SET GLOBAL ob_query_timeout=1000000000','SET GLOBAL ob_trx_timeout=150000000','SET GLOBAL ob_trx_lock_timeout=12000000','SET GLOBAL ob_sql_work_area_percentage=25')
  }

  $before = Invoke-Ssh "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -pOceanBase#!123 -N -e 'SELECT @@ob_trx_timeout,@@ob_trx_lock_timeout,@@ob_query_timeout,@@ob_sql_work_area_percentage'"
  $sql = ($tuning -join '; ') + '; SELECT @@ob_trx_timeout,@@ob_trx_lock_timeout,@@ob_query_timeout,@@ob_sql_work_area_percentage;'
  $after = Invoke-Ssh "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -pOceanBase#!123 -N -e \"$sql\""

  @('# Iteration analysis','',"- avg_tps_delta_pct: $($cmp.avg_tps_delta_pct)","- avg_p95_delta_pct: $($cmp.avg_p95_delta_pct)","- avg_avg_latency_delta_pct: $($cmp.avg_avg_delta_pct)","- failed_cases: $($cmp.failed_cases)","- total_errors: $($cmp.total_errors)",'','## Bottleneck findings',($findings | ForEach-Object { "- $_" }),'','## Tuning changes (cumulative)',"- Before: $($before -join ' | ')",($tuning | ForEach-Object { "- Applied: $_" }),"- After: $($after -join ' | ')" ) | Set-Content -Path (Join-Path $iterDir 'analysis.md')

  [pscustomobject]@{ tuning_sql=($tuning -join '; ') }
}

if (-not (Test-Path $BaselineAbs)) { throw "Baseline missing: $BaselineAbs" }
if (-not (Test-Path $LocalBenchScript)) { throw "Local runner missing: $LocalBenchScript" }

LogLine "LAUNCH run_ts=$MasterTs artifact_root=$ArtifactRoot run_suffix=$RunSuffix"
Invoke-Scp $BaselineAbs "${SshUser}@${ControlIp}:${RemoteOut}/"
Invoke-Scp $LocalBenchScript "${SshUser}@${ControlIp}:${RemoteBenchScript}"
Invoke-Ssh "chmod +x $RemoteBenchScript" | Out-Null

$iterResults = @()
for ($i=1; $i -le 16; $i++) {
  $iterTs = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
  $iterName = "${iterTs}_iter$('{0:d2}' -f $i)"
  $iterLabel = "${RunSuffix}_iter$('{0:d2}' -f $i)"
  $iterDir = Join-Path $RunRoot $iterName
  New-Item -ItemType Directory -Force -Path $iterDir | Out-Null
  LogLine "ITER_START i=$i ts=$iterTs label=$iterLabel"

  $preflightCmd = "systemctl is-active obproxy >/tmp/${iterName}_obproxy_status.txt 2>&1 || true; ss -lntp | grep ':2883' >/tmp/${iterName}_port_2883.txt 2>&1 || true; mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -pOceanBase#!123 -N -e 'SELECT 1' >/tmp/${iterName}_handshake.txt 2>&1 || true; mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -pOceanBase#!123 -N -e \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='sbtest' AND table_name REGEXP '^sbtest[0-9]+$'\" >/tmp/${iterName}_table_count.txt 2>&1 || true; cat /tmp/${iterName}_obproxy_status.txt; echo ---; cat /tmp/${iterName}_port_2883.txt | head -3; echo ---; cat /tmp/${iterName}_handshake.txt; echo ---; cat /tmp/${iterName}_table_count.txt"
  $pre = Invoke-Ssh $preflightCmd
  ($pre -join "`n") | Set-Content -Path (Join-Path $iterDir 'preflight.txt')

  $runCmd = "source ~/ansible-venv/bin/activate; cd $RemoteRepo; chmod +x $RemoteBenchScript; nohup sudo $RemoteBenchScript $iterLabel 127.0.0.1 root@sbtest_tenant 'OceanBase#!123' sbtest '$ObserverIps' > $RemoteOut/${iterName}_run.log 2>&1 & echo PID=`$!"
  $startOut = Invoke-Ssh $runCmd
  $pidLine = ($startOut | Where-Object { $_ -match '^PID=' } | Select-Object -First 1)
  $pid = if ($pidLine) { $pidLine.Split('=')[1].Trim() } else { '' }
  LogLine "ITER_BENCH_STARTED i=$i pid=$pid"

  $latestCsv = ''
  for ($p=1; $p -le 260; $p++) {
    Start-Sleep -Seconds 30
    $pollCmd = "latest=`$(ls -t $RemoteOut/*_${iterLabel}.csv 2>/dev/null | head -1); if [ -n \"`$latest\" ]; then echo CSV=`$latest; wc -l \"`$latest\"; fi; if [ -n \"$pid\" ]; then ps -p $pid >/dev/null 2>&1; echo RUNNING=`$?; else pgrep -f '$iterLabel' >/dev/null 2>&1; echo RUNNING=`$?; fi"
    $poll = Invoke-Ssh $pollCmd
    $pt = $poll -join ' '
    if ($pt -match 'CSV=([^ ]+)') { $latestCsv = $Matches[1] }
    if ($p -eq 1 -or $p % 8 -eq 0) { LogLine "ITER_PROGRESS i=$i poll=$p $pt" }
    if ($pt -match 'RUNNING=1') { break }
  }

  if ([string]::IsNullOrWhiteSpace($latestCsv)) {
    $latestCsv = (Invoke-Ssh "ls -t $RemoteOut/*_${iterLabel}.csv 2>/dev/null | head -1" | Select-Object -First 1).Trim()
  }
  if ([string]::IsNullOrWhiteSpace($latestCsv)) {
    LogLine "ITER_FAIL i=$i reason=no_csv_found"
    $iterResults += [pscustomobject]@{ iteration=$i; status='failed'; reason='no_csv'; avg_tps_delta_pct=''; avg_p95_delta_pct=''; csv='' }
    continue
  }

  Invoke-Scp "${SshUser}@${ControlIp}:${latestCsv}" "$iterDir/"
  & scp '-i' $SshKey '-P' $SshPort "${SshUser}@${ControlIp}:${RemoteOut}/${iterName}_run.log" "$iterDir/" 2>$null | Out-Null

  $localCsv = Join-Path $iterDir (Split-Path $latestCsv -Leaf)
  $cmp = Compare-Csv -baselinePath $BaselineAbs -currentPath $localCsv
  $cmp.points | Export-Csv -Path (Join-Path $iterDir 'comparison_points.csv') -NoTypeInformation
  $cmp | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $iterDir 'comparison_summary.json')

  $tune = Analyze-And-Tune -cmp $cmp -iterDir $iterDir

  $diagCmd = "journalctl -u obproxy -n 400 > $RemoteOut/${iterName}_journal_obproxy.log 2>&1; for p in /home/admin/obproxy/log /var/log/obproxy /home/azureadmin/obproxy/log; do if [ -d \"`$p\" ]; then tar -czf $RemoteOut/${iterName}_obproxy_logs.tgz -C \"`$p\" . && break; fi; done; mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -pOceanBase#!123 -e 'SHOW VARIABLES LIKE \"ob_%timeout\"; SHOW VARIABLES LIKE \"ob_sql_work_area_percentage\";' > $RemoteOut/${iterName}_tuning_snapshot.sql.txt 2>&1"
  Invoke-Ssh $diagCmd | Out-Null
  & scp '-i' $SshKey '-P' $SshPort "${SshUser}@${ControlIp}:${RemoteOut}/${iterName}_*" "$iterDir/" 2>$null | Out-Null

  $iterResults += [pscustomobject]@{ iteration=$i; status='success'; reason=''; avg_tps_delta_pct=$cmp.avg_tps_delta_pct; avg_p95_delta_pct=$cmp.avg_p95_delta_pct; csv=(Split-Path $localCsv -Leaf); tuning_sql=$tune.tuning_sql }
  LogLine "ITER_DONE i=$i status=success avg_tps_delta_pct=$($cmp.avg_tps_delta_pct) avg_p95_delta_pct=$($cmp.avg_p95_delta_pct)"
}

$iterResults | Export-Csv -Path (Join-Path $RunRoot 'iterations_summary.csv') -NoTypeInformation
$best = $iterResults | Where-Object { $_.status -eq 'success' } | Sort-Object {[double]$_.avg_tps_delta_pct} -Descending | Select-Object -First 1
@('# Loop16 summary','',"- launch_utc: $MasterTs", "- artifact_root: $ArtifactRoot/$MasterTs", "- completed_iterations: $($iterResults.Count)", "- successful_iterations: $(($iterResults | Where-Object status -eq 'success').Count)", "- failed_iterations: $(($iterResults | Where-Object status -ne 'success').Count)", "- best_iteration: $(if ($best) { $best.iteration } else { 'n/a' })", "- best_avg_tps_delta_pct: $(if ($best) { $best.avg_tps_delta_pct } else { 'n/a' })") | Set-Content -Path $MasterSummary
LogLine "LOOP_COMPLETE run_ts=$MasterTs"
