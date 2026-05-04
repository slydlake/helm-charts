{{- define "wordpress.init-lib-lock" -}}
#!/bin/bash
# WordPress Helm Chart - Database Lock Library
# Provides distributed locking for multi-pod deployments
#
# Heartbeat-based locking:
#   - Lock holder runs a background heartbeat (updates timestamp every 15s)
#   - Waiters check: was lock updated in last 60s?
#   - If no heartbeat for 60s → pod crashed → lock is stale
#   - Same hostname (pod restart): Lock immediately overridden
#   - Lock format: hostname-timestamp

BOOTSTRAP_LOCK_ACQUIRED=false
CONFIG_LOCK_ACQUIRED=false
HEARTBEAT_PID=""
readonly HEARTBEAT_INTERVAL=15  # Seconds between heartbeat updates
readonly STALE_THRESHOLD=60     # Seconds without heartbeat before lock is considered stale
readonly MAX_LOCK_WAIT=600      # Absolute max wait time in seconds (safety net)

# Start heartbeat for a lock - updates timestamp every HEARTBEAT_INTERVAL seconds
# Uses lightweight PHP directly instead of wp-cli to avoid resource contention
# Args: $1 = lock type ("bootstrap" or "config")
_start_heartbeat() {
  local lock_type="$1"
  local pod_hostname="$(hostname)"

  # Kill any existing heartbeat first
  _stop_heartbeat

  if [ "$lock_type" = "bootstrap" ]; then
    (
      while true; do
        sleep $HEARTBEAT_INTERVAL
        HEARTBEAT_TABLE="${TABLE_PREFIX}helm_locks" HEARTBEAT_HOSTNAME="${pod_hostname}" HEARTBEAT_TYPE="bootstrap" php -r '
          $m = @new mysqli(getenv("WORDPRESS_DB_HOST"), getenv("WORDPRESS_DB_USER"), getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME"));
          if(!$m->connect_error) {
            $t=time(); $h=getenv("HEARTBEAT_HOSTNAME"); $tbl=getenv("HEARTBEAT_TABLE");
            $m->query("UPDATE {$tbl} SET lock_value=\"" . $m->real_escape_string("{$h}-{$t}") . "\" WHERE lock_name=\"bootstrap\" AND lock_value LIKE \"" . $m->real_escape_string($h) . "-%\"");
            $m->close();
          }
        ' 2>/dev/null || true
      done
    ) &
  else
    (
      while true; do
        sleep $HEARTBEAT_INTERVAL
        HEARTBEAT_TABLE="${TABLE_PREFIX}options" HEARTBEAT_HOSTNAME="${pod_hostname}" php -r '
          $m = @new mysqli(getenv("WORDPRESS_DB_HOST"), getenv("WORDPRESS_DB_USER"), getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME"));
          if(!$m->connect_error) {
            $t=time(); $h=getenv("HEARTBEAT_HOSTNAME"); $tbl=getenv("HEARTBEAT_TABLE");
            $m->query("UPDATE {$tbl} SET option_value=\"" . $m->real_escape_string("{$h}-{$t}") . "\" WHERE option_name=\"_helm_config_lock\" AND option_value LIKE \"" . $m->real_escape_string($h) . "-%\"");
            $m->close();
          }
        ' 2>/dev/null || true
      done
    ) &
  fi
  HEARTBEAT_PID=$!
  [ "${DEBUG}" = "true" ] && echo "DEBUG: Heartbeat started (PID: $HEARTBEAT_PID) for $lock_type lock" >&2
}

# Stop the heartbeat background process
_stop_heartbeat() {
  if [ -n "$HEARTBEAT_PID" ]; then
    kill $HEARTBEAT_PID 2>/dev/null || true
    wait $HEARTBEAT_PID 2>/dev/null || true
    [ "${DEBUG}" = "true" ] && echo "DEBUG: Heartbeat stopped (PID: $HEARTBEAT_PID)" >&2
    HEARTBEAT_PID=""
  fi
}

_lock_db_query() {
  local sql="$1"

  LOCK_SQL="$sql" php <<'PHPEOF'
<?php
mysqli_report(MYSQLI_REPORT_OFF);

$host = getenv('WORDPRESS_DB_HOST');
$user = getenv('WORDPRESS_DB_USER');
$pass = getenv('WORDPRESS_DB_PASSWORD');
$name = getenv('WORDPRESS_DB_NAME');
$sql = getenv('LOCK_SQL');

$m = @new mysqli($host, $user, $pass, $name);
if ($m->connect_error) {
  fwrite(STDERR, $m->connect_error);
  exit(1);
}

if ($sql === false || $sql === '') {
  fwrite(STDERR, 'missing SQL statement');
  $m->close();
  exit(1);
}

if (!$m->query($sql)) {
  fwrite(STDERR, $m->error);
  $m->close();
  exit(1);
}

$m->close();
PHPEOF
}

_lock_db_read_value() {
  local sql="$1"

  LOCK_SQL="$sql" php <<'PHPEOF'
<?php
mysqli_report(MYSQLI_REPORT_OFF);

$host = getenv('WORDPRESS_DB_HOST');
$user = getenv('WORDPRESS_DB_USER');
$pass = getenv('WORDPRESS_DB_PASSWORD');
$name = getenv('WORDPRESS_DB_NAME');
$sql = getenv('LOCK_SQL');

$m = @new mysqli($host, $user, $pass, $name);
if ($m->connect_error) {
  fwrite(STDERR, $m->connect_error);
  exit(1);
}

$result = $m->query($sql);
if (!$result) {
  fwrite(STDERR, $m->error);
  $m->close();
  exit(1);
}

$row = $result->fetch_row();
if ($row && array_key_exists(0, $row) && $row[0] !== null) {
  echo $row[0];
}

$result->free();
$m->close();
PHPEOF
}

# Attempt to claim bootstrap lock using dedicated helm_locks table
# This is used BEFORE WordPress installation when wp_options doesn't exist yet
#
# Returns:
#   0 - Lock successfully claimed (heartbeat started)
#   1 - Lock held by another pod (after retries)
#
# Heartbeat: Lock holder updates timestamp every 15s.
# Waiters check: no heartbeat for 60s → lock is stale → override.
claim_bootstrap_lock() {
  local retry_interval=10
  local retry_count=0
  local max_retries=$((MAX_LOCK_WAIT / retry_interval))
  local pod_hostname="$(hostname)"
  local current_time=$(date +%s)

  echo "Attempting to claim bootstrap lock (for WordPress installation)..."
  [ "${DEBUG}" = "true" ] && echo "DEBUG: Pod hostname: $pod_hostname" >&2

  while [ $retry_count -lt $max_retries ]; do
    current_time=$(date +%s)

    # Ensure helm_locks table exists on every attempt
    # (CREATE TABLE IF NOT EXISTS is idempotent and fast when table already exists)
    # This handles the case where MariaDB accepts connections but isn't fully ready for DDL yet
    local create_table_output=""
    if ! create_table_output=$(_lock_db_query "
      CREATE TABLE IF NOT EXISTS ${TABLE_PREFIX}helm_locks (
        lock_name VARCHAR(64) PRIMARY KEY,
        lock_value VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    " 2>&1); then
      return 1
    fi

    # Atomic lock claim: override if same hostname OR no heartbeat for STALE_THRESHOLD seconds
    local claim_output=""
    if ! claim_output=$(_lock_db_query "
      INSERT INTO ${TABLE_PREFIX}helm_locks (lock_name, lock_value)
      VALUES ('bootstrap', '$pod_hostname-$current_time')
      ON DUPLICATE KEY UPDATE
        lock_value = IF(
          lock_value LIKE '$pod_hostname-%'
          OR CAST(SUBSTRING_INDEX(lock_value, '-', -1) AS UNSIGNED) < $current_time - $STALE_THRESHOLD,
          '$pod_hostname-$current_time',
          lock_value
        );
    " 2>&1); then
      return 1
    fi

    sleep 0.1

    # Check if we got the lock
    local lock_owner=""
    local lock_query_output=""
    if ! lock_query_output=$(_lock_db_read_value "SELECT lock_value FROM ${TABLE_PREFIX}helm_locks WHERE lock_name='bootstrap';" 2>&1); then
      return 1
    fi
    lock_owner="$lock_query_output"

    if [[ "$lock_owner" == "$pod_hostname-$current_time" ]]; then
      echo "Bootstrap lock acquired successfully!"
      BOOTSTRAP_LOCK_ACQUIRED=true
      _start_heartbeat "bootstrap"
      return 0
    fi

    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      local wait_time=$((retry_count * retry_interval))
      echo "Another pod is installing WordPress, waiting... (${wait_time}s)"
      sleep $retry_interval
    fi
  done

  echo "ERROR: Timeout waiting for bootstrap lock after ${MAX_LOCK_WAIT}s"
  return 1
}

# Release bootstrap lock and stop heartbeat
release_bootstrap_lock() {
  if [ "$BOOTSTRAP_LOCK_ACQUIRED" = "true" ]; then
    _stop_heartbeat
    [ "${DEBUG}" = "true" ] && echo "DEBUG: Releasing bootstrap lock" >&2
    local pod_hostname="$(hostname)"
    # Direct PHP for fast release (no WordPress bootstrap overhead)
    php -r "\$m = @new mysqli('${WORDPRESS_DB_HOST}', '${WORDPRESS_DB_USER}', '${WORDPRESS_DB_PASSWORD}', '${WORDPRESS_DB_NAME}'); if(!\$m->connect_error) { \$m->query(\"DELETE FROM ${TABLE_PREFIX}helm_locks WHERE lock_name='bootstrap' AND lock_value LIKE '${pod_hostname}-%'\"); \$m->close(); }" 2>/dev/null || true
    BOOTSTRAP_LOCK_ACQUIRED=false
    echo "Bootstrap lock released!"
  fi
}

# Attempt to claim configuration lock using wp_options table
# This is used AFTER WordPress installation for plugin/theme/config management
#
# Returns:
#   0 - Lock successfully claimed (heartbeat started)
#   1 - Lock held by another pod (after retries)
#
# Heartbeat: Lock holder updates timestamp every 15s.
# Waiters check: no heartbeat for 60s → lock is stale → override.
claim_config_lock() {
  local retry_interval=10
  local retry_count=0
  local max_retries=$((MAX_LOCK_WAIT / retry_interval))
  local pod_hostname="$(hostname)"
  local current_time=$(date +%s)

  [ "${DEBUG}" = "true" ] && echo "DEBUG: Attempting config lock, hostname: $pod_hostname" >&2

  while [ $retry_count -lt $max_retries ]; do
    current_time=$(date +%s)

    # Atomic lock claim: override if same hostname OR no heartbeat for STALE_THRESHOLD seconds
    local claim_output=""
    if ! claim_output=$(_lock_db_query "
      INSERT INTO ${TABLE_PREFIX}options (option_name, option_value, autoload)
      VALUES ('_helm_config_lock', '$pod_hostname-$current_time', 'no')
      ON DUPLICATE KEY UPDATE
        option_value = IF(
          option_value LIKE '$pod_hostname-%'
          OR CAST(SUBSTRING_INDEX(option_value, '-', -1) AS UNSIGNED) < $current_time - $STALE_THRESHOLD,
          '$pod_hostname-$current_time',
          option_value
        );
    " 2>&1); then
      return 1
    fi

    sleep 0.1

    # Check if we got the lock
    local lock_owner=""
    local lock_query_output=""
    if ! lock_query_output=$(_lock_db_read_value "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='_helm_config_lock';" 2>&1); then
      return 1
    fi
    lock_owner="$lock_query_output"

    if [[ "$lock_owner" == "$pod_hostname-$current_time" ]]; then
      CONFIG_LOCK_ACQUIRED=true
      _start_heartbeat "config"
      [ "${DEBUG}" = "true" ] && echo "DEBUG: Pod $pod_hostname claimed config lock" >&2
      return 0
    fi

    # Lock held by another pod with fresh heartbeat
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      local wait_time=$((retry_count * retry_interval))
      echo "Another pod is running init process, waiting... (${wait_time}s)"
      sleep $retry_interval
    fi
  done

  [ "${DEBUG}" = "true" ] && echo "DEBUG: Timeout waiting for config lock after ${MAX_LOCK_WAIT}s" >&2
  return 1
}

# Release the configuration lock and stop heartbeat
release_config_lock() {
  if [ "$CONFIG_LOCK_ACQUIRED" = "true" ]; then
    _stop_heartbeat
    [ "${DEBUG}" = "true" ] && echo "DEBUG: Releasing config lock" >&2
    local pod_hostname="$(hostname)"
    # Direct PHP for fast release (no WordPress bootstrap overhead)
    php -r "\$m = @new mysqli('${WORDPRESS_DB_HOST}', '${WORDPRESS_DB_USER}', '${WORDPRESS_DB_PASSWORD}', '${WORDPRESS_DB_NAME}'); if(!\$m->connect_error) { \$m->query(\"DELETE FROM ${TABLE_PREFIX}options WHERE option_name='_helm_config_lock' AND option_value LIKE '${pod_hostname}-%'\"); \$m->close(); }" 2>/dev/null || true
    CONFIG_LOCK_ACQUIRED=false
    echo "Config lock released!"
  fi
}
{{- end -}}
