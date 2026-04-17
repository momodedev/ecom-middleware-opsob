#!/bin/bash
# OceanBase v4.5.0 - Deep Performance Configuration Check

PASS='OceanBase#!123'
OB="obclient -h127.0.0.1 -P2881 -uroot@sys -p${PASS} -Doceanbase -A"

run_sql() {
    echo "$1" | $OB 2>&1
}

echo "================================================================"
echo "=== OceanBase v4.5.0 - Performance Configuration Deep Check ==="
echo "================================================================"

echo ""
echo "=== [1] MEMORY CONFIGURATION ==="

echo "-- memory_limit, system_memory, memstore, cache --"
run_sql "SELECT name, value, section FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'memory_limit','memory_limit_percentage','system_memory',
  'memstore_limit_percentage','freeze_trigger_percentage',
  'memory_chunk_cache_size','memory_reserved',
  'cache_wash_threshold',
  'bf_cache_priority','index_block_cache_priority','user_block_cache_priority',
  'user_row_cache_priority','fuse_row_cache_priority','opt_tab_stat_cache_priority',
  'storage_meta_cache_priority','tablet_ls_cache_priority',
  'query_memory_limit_percentage','sql_work_area'
) ORDER BY name;"

echo ""
echo "-- Live memory stats (GV\$OB_MEMORY) - top consumers --"
run_sql "SELECT tenant_id, hold/1024/1024 AS hold_MB, used/1024/1024 AS used_MB, mod_name FROM oceanbase.GV\$OB_MEMORY WHERE hold > 10*1024*1024 ORDER BY hold DESC LIMIT 30;"

echo ""
echo "-- MemStore usage per tenant --"
run_sql "SELECT tenant_id, svr_ip, active_span/1024/1024 AS active_MB, freeze_trigger/1024/1024 AS freeze_trigger_MB, mem_limit/1024/1024 AS mem_limit_MB FROM oceanbase.GV\$OB_MEMSTORE;"

echo ""
echo "=== [2] CPU & THREAD CONFIGURATION ==="

run_sql "SELECT name, value, section FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'cpu_count','cpu_quota_concurrency','workers_per_cpu_quota',
  'net_thread_count','sql_net_thread_count','sql_login_thread_count',
  'tenant_sql_net_thread_count','tenant_sql_login_thread_count',
  'high_priority_net_thread_count','io_scheduler_thread_count',
  'disk_io_thread_count','sync_io_thread_count',
  'compaction_high_thread_score','compaction_mid_thread_score','compaction_low_thread_score',
  'ddl_high_thread_score','ddl_thread_score',
  'ha_high_thread_score','ha_mid_thread_score','ha_low_thread_score',
  'rootservice_async_task_thread_count',
  'px_workers_per_cpu_quota','large_query_worker_percentage',
  'location_refresh_thread_count','ttl_thread_score'
) ORDER BY name;"

echo ""
echo "-- Live thread pool usage --"
run_sql "SELECT tenant_id, svr_ip, active_cnt, waiting_cnt, request_queue_cnt, free_cnt FROM oceanbase.GV\$OB_THREAD_POOL ORDER BY tenant_id;" 2>/dev/null || echo "(GV\$OB_THREAD_POOL not available)"

echo ""
echo "=== [3] STORAGE & IO CONFIGURATION ==="

run_sql "SELECT name, value, section FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'datafile_size','datafile_maxsize','datafile_next','datafile_disk_percentage',
  'datafile_disk_percentage','data_dir','log_disk_size','log_disk_percentage',
  'data_disk_usage_limit_percentage','data_disk_write_limit_percentage',
  'log_disk_utilization_threshold','log_disk_utilization_limit_threshold',
  'log_disk_throttling_percentage','log_disk_throttling_maximum_duration',
  'redundancy_level','tablet_size','auto_split_tablet_size',
  'default_compress','default_compress_func','log_storage_compress_all','log_storage_compress_func',
  'log_transport_compress_all','log_transport_compress_func',
  'micro_block_merge_verify_level','default_micro_block_format_version',
  'disk_io_thread_count','io_scheduler_thread_count','sync_io_thread_count',
  'clog_io_isolation_mode','ss_cache_maxsize_percpu','ss_cache_max_percentage',
  'storage_rowsets_size','spill_compression_codec','sql_work_area'
) ORDER BY name;"

echo ""
echo "-- SSTable disk usage --"
run_sql "SELECT tenant_id, svr_ip, data_disk_in_use/1024/1024/1024 AS data_disk_GB, data_disk_capacity/1024/1024/1024 AS data_disk_cap_GB FROM oceanbase.GV$OB_SERVERS;" 2>/dev/null

run_sql "SELECT svr_ip, svr_port, disk_type, total_size/1024/1024/1024 AS total_GB, free_size/1024/1024/1024 AS free_GB FROM oceanbase.GV\$OB_DISK_STAT;" 2>/dev/null || echo "(GV\$OB_DISK_STAT view query failed)"

echo ""
echo "=== [4] COMPACTION & MERGE CONFIGURATION ==="

run_sql "SELECT name, value, section FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'minor_compact_trigger','major_compact_trigger','major_freeze_duty_time',
  'freeze_trigger_percentage','merger_check_interval',
  'mds_minor_compact_trigger','mds_compaction_high_thread_score','mds_compaction_mid_thread_score',
  'ob_compaction_schedule_interval','compaction_dag_cnt_limit',
  'compaction_schedule_tablet_batch_cnt',
  'default_progressive_merge_num','default_table_merge_engine',
  'dump_data_dictionary_to_log_interval','enable_major_freeze',
  'builtin_db_data_verify_cycle'
) ORDER BY name;"

echo ""
echo "-- Major freeze status --"
run_sql "SELECT * FROM oceanbase.CDB_OB_MAJOR_COMPACTION;" 2>/dev/null || run_sql "SELECT * FROM oceanbase.DBA_OB_MAJOR_COMPACTION;" 2>/dev/null

echo ""
echo "=== [5] TRANSACTION & LOCK CONFIGURATION ==="

run_sql "SELECT name, value, section FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'undo_retention','writing_throttling_trigger_percentage','writing_throttling_maximum_duration',
  'row_compaction_update_limit','trx_2pc_retry_interval',
  'clog_sync_time_warn_threshold','dead_socket_detection_timeout',
  'enable_early_lock_release','enable_monotonic_weak_read',
  'max_stale_time_for_weak_consistency','weak_read_version_refresh_interval',
  'rpc_timeout','tcp_keepidle','tcp_keepintvl','tcp_keepcnt','enable_tcp_keepalive',
  'shared_log_retention','large_query_threshold','arbitration_timeout',
  'ignore_replay_checksum_error'
) ORDER BY name;"

echo ""
echo "=== [6] SQL & QUERY ENGINE CONFIGURATION ==="

run_sql "SELECT name, value, section FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'sql_work_area','workarea_size_policy','px_task_size','px_workers_per_cpu_quota',
  'px_node_policy','enable_sql_audit','enable_sql_operator_dump',
  'enable_adaptive_plan_cache','enable_ps_parameterize',
  'ob_enable_batched_multi_statement','optimizer_index_cost_adj',
  'plan_cache_evict_interval','sql_plan_management_mode',
  'open_cursors','enable_early_lock_release','location_cache_cpu_quota',
  'location_cache_refresh_min_interval','location_cache_refresh_rpc_timeout',
  'location_cache_refresh_sql_timeout','location_fetch_concurrency',
  'result_cache_max_size','result_cache_max_result',
  'range_optimizer_max_mem_size','large_query_threshold','large_query_worker_percentage',
  'enable_record_trace_log','trace_log_slow_query_watermark',
  'query_response_time_stats','ob_result_cache_evict_percentage'
) ORDER BY name;"

echo ""
echo "-- Tenant-level session/global variables (via sys tenant) --"
run_sql "SELECT name, value FROM oceanbase.GV\$OB_PARAMETERS WHERE section='TENANT' ORDER BY name;"

echo ""
echo "=== [7] NETWORK & RPC CONFIGURATION ==="

run_sql "SELECT name, value, section FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'net_thread_count','rpc_timeout','rpc_port','rpc_memory_limit_percentage',
  'rpc_client_authentication_method','rpc_server_authentication_method',
  'rpc_client_authentication_method','enable_rpc_authentication_bypass',
  'sql_net_thread_count','high_priority_net_thread_count',
  'sys_bkgd_net_percentage','standby_fetch_log_bandwidth_limit',
  'dtl_buffer_size','kv_transport_compress_func','kv_transport_compress_threshold',
  'devname','local_ip','use_ipv6','use_large_pages',
  'tcp_keepidle','tcp_keepintvl','tcp_keepcnt','dead_socket_detection_timeout',
  'stack_size','enable_ob_ratelimit','ob_ratelimit_stat_period'
) ORDER BY name;"

echo ""
echo "-- Active connections --"
run_sql "SELECT tenant_id, svr_ip, svr_port, all_cnt, active_cnt FROM oceanbase.GV\$OB_PROCESSLIST GROUP BY tenant_id, svr_ip, svr_port;" 2>/dev/null || run_sql "SELECT COUNT(*) AS total_connections, state FROM oceanbase.GV\$OB_PROCESSLIST GROUP BY state;"

echo ""
echo "=== [8] WAIT EVENTS & TOP SQL ===" 

echo "-- Top wait events (instance level) --"
run_sql "SELECT event, total_waits, total_timeouts, time_waited_micro/1000 AS time_waited_ms, average_wait_micro/1000 AS avg_wait_ms FROM oceanbase.GV\$SYSTEM_EVENT WHERE total_waits > 0 ORDER BY time_waited_micro DESC LIMIT 20;" 2>/dev/null || echo "(GV\$SYSTEM_EVENT not available)"

echo ""
echo "-- Top SQL by elapsed time (sql_audit) --"
run_sql "SELECT sid, tenant_id, user_name, db_name, elapsed_time/1000 AS elapsed_ms, execute_time/1000 AS execute_ms, queue_time/1000 AS queue_ms, get_plan_time/1000 AS plan_ms, affected_rows, return_rows, SUBSTR(query_sql,1,100) AS sql FROM oceanbase.GV\$OB_SQL_AUDIT WHERE is_executor_rpc=0 ORDER BY elapsed_time DESC LIMIT 15;" 2>/dev/null || echo "(GV\$OB_SQL_AUDIT query failed)"

echo ""
echo "=== [9] PLAN CACHE STATUS ==="

run_sql "SELECT tenant_id, svr_ip, svr_port, mem_used/1024/1024 AS mem_used_MB, hit_count, miss_count, access_count, plan_num FROM oceanbase.GV\$OB_PLAN_CACHE_STAT;" 2>/dev/null || echo "(GV\$OB_PLAN_CACHE_STAT not available)"

echo ""
echo "=== [10] LOG & SYSLOG CONFIGURATION ==="

run_sql "SELECT name, value, section FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'syslog_level','enable_syslog_recycle','max_syslog_file_count',
  'syslog_io_bandwidth_limit','syslog_compress_func','syslog_disk_size',
  'syslog_file_uncompressed_count','enable_syslog_wf','enable_async_syslog',
  'diag_syslog_per_error_limit','alert_log_level',
  'enable_perf_event','enable_sql_audit','enable_record_trace_id',
  'audit_trail','audit_log_enable','max_string_print_length',
  'load_data_diagnosis_log_max_size'
) ORDER BY name;"

echo ""
echo "=== [11] RESOURCE ISOLATION ==="

run_sql "SELECT name, value, section FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'enable_cgroup','global_background_cpu_quota','enable_global_background_resource_isolation',
  'server_cpu_quota_max','server_cpu_quota_min',
  'resource_hard_limit','enable_sys_unit_standalone',
  'query_memory_limit_percentage'
) ORDER BY name;"

echo ""
echo "=== [12] CURRENT SERVER STATISTICS ==="

run_sql "SELECT svr_ip, svr_port, cpu_capacity, cpu_capacity_max, cpu_assigned, cpu_assigned_max,
  mem_capacity/1024/1024/1024 AS mem_cap_GB, mem_assigned/1024/1024/1024 AS mem_assigned_GB,
  data_disk_capacity/1024/1024/1024 AS data_disk_cap_GB,
  data_disk_in_use/1024/1024/1024 AS data_disk_used_GB,
  log_disk_capacity/1024/1024/1024 AS log_disk_cap_GB,
  log_disk_assigned/1024/1024/1024 AS log_disk_assigned_GB,
  log_disk_in_use/1024/1024/1024 AS log_disk_used_GB
FROM oceanbase.GV\$OB_SERVERS;"

echo ""
echo "=== [13] ACTIVE SESSIONS & TRANSACTIONS ==="

run_sql "SELECT tenant_id, COUNT(*) AS sessions, SUM(CASE WHEN state='ACTIVE' THEN 1 ELSE 0 END) AS active FROM oceanbase.GV\$OB_PROCESSLIST GROUP BY tenant_id;" 2>/dev/null

run_sql "SELECT tenant_id, svr_ip, trans_type, state, ctx_create_time, expire_time, participants, sql_no FROM oceanbase.GV\$OB_TRANSACTION_PARTICIPANTS WHERE state != 'IDLE' LIMIT 20;" 2>/dev/null || echo "(no active transactions or view unavailable)"
