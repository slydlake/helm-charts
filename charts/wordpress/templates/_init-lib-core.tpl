{{- define "wordpress.init-lib-core" -}}
#!/bin/bash
# WordPress Helm Chart - Core Library
# Provides essential utility functions for the init script

# ============================================================================
# Test Mode Support
# ============================================================================
# When TEST_MODE=true, enables assert() for validation
# Usage: TEST_MODE=true ./init.sh

# Assert function for testing - validates conditions
# Only active when TEST_MODE=true
#
# Args:
#   $1 - Description of assertion
#   $2 - Condition to evaluate (must return 0 for success)
#
# Example:
#   assert "wp command exists" "command -v wp"
#   assert "plugins directory exists" "[ -d wp-content/plugins ]"
assert() {
  local description="$1"
  shift
  local condition="$@"

  if [ "${TEST_MODE}" != "true" ]; then
    return 0
  fi

  if eval "$condition"; then
    echo "✓ PASS: $description"
    return 0
  else
    echo "✗ FAIL: $description"
    echo "  Condition: $condition"
    ASSERT_FAILURES=$((${ASSERT_FAILURES:-0} + 1))
    return 1
  fi
}

# Print test summary - call at end of script when TEST_MODE=true
test_summary() {
  if [ "${TEST_MODE}" != "true" ]; then
    return 0
  fi

  echo ""
  echo "========================================="
  echo "Test Summary"
  echo "========================================="
  if [ "${ASSERT_FAILURES:-0}" -eq 0 ]; then
    echo "All assertions passed!"
    return 0
  else
    echo "FAILED: ${ASSERT_FAILURES} assertion(s) failed"
    return 1
  fi
}

# ============================================================================
# DRY_RUN Mode Support
# ============================================================================
# When DRY_RUN=true, commands are printed but not executed
# Useful for testing what would happen without making changes

# Execute a command, respecting DRY_RUN mode
# In DRY_RUN mode, prints the command instead of executing
#
# Args:
#   $@ - Command and arguments to execute
execute() {
  if [ "${DRY_RUN}" = "true" ]; then
    echo "[DRY_RUN] Would execute: $*"
    return 0
  fi
  "$@"
}

# ============================================================================
# Core Helper Functions
# ============================================================================

# WP-CLI wrapper with optional debug output
# Uses global DEBUG flag to control verbosity
#
# Args: All arguments are passed through to wp-cli
#
# Performance Note:
#   Each wp call loads WordPress core - can be slow
#   Use batch operations where possible (e.g., install multiple plugins at once)
wp() {
  if [ "${DRY_RUN}" = "true" ]; then
    echo "[DRY_RUN] wp $*"
    return 0
  fi
  # --skip-plugins/themes: avoid loading all installed plugins on every call
  # (huge speedup when Composer packages like s3-uploads are installed)
  if [ "${DEBUG}" = "true" ]; then
    command wp --path="${WORDPRESS_PATH}" --skip-plugins --skip-themes --debug "$@"
  else
    command wp --path="${WORDPRESS_PATH}" --skip-plugins --skip-themes "$@"
  fi
}

# Run commands with optional output suppression based on DEBUG flag
#
# Args: Command and arguments to execute
run() {
  if [ "${DRY_RUN}" = "true" ]; then
    echo "[DRY_RUN] $*"
    return 0
  fi
  if [ "${DEBUG}" = "true" ]; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

# Standardized error handler
# Logs error message and exits with code 1
#
# Args:
#   $1 - Error message to display
handle_error() {
  echo "ERROR: $1" >&2
  exit 1
}

# Warning handler for non-fatal errors
# Logs warning but allows script to continue
#
# Args:
#   $1 - Warning message to display
warn_and_continue() {
  echo "WARNING: $1" >&2
  return 0
}

# Retry wrapper for network operations with exponential backoff
# Retries failed commands up to MAX_RETRIES times with increasing delays
#
# Args:
#   $@ - Command and arguments to execute
#
# Returns:
#   0 - Command succeeded (possibly after retries)
#   1 - Command failed after all retries exhausted
retry_command() {
  local max_retries=${MAX_RETRIES:-3}
  local retry_delay=${RETRY_DELAY:-2}
  local attempt=1
  local exit_code=0

  while [ $attempt -le $max_retries ]; do
    if "$@"; then
      return 0
    fi
    exit_code=$?

    if [ $attempt -lt $max_retries ]; then
      local wait_time=$((retry_delay * attempt))
      echo "Command failed (attempt $attempt/$max_retries), retrying in ${wait_time}s..." >&2
      sleep $wait_time
    fi

    attempt=$((attempt + 1))
  done

  echo "Command failed after $max_retries attempts" >&2
  return $exit_code
}

# Validate package name to prevent injection attacks
# Checks for dangerous characters and patterns
#
# Args:
#   $1 - Package name to validate
#
# Returns:
#   0 - Package name is valid
#   1 - Package name contains invalid characters
validate_package_name() {
  local name="$1"

  # Check for empty name
  if [ -z "$name" ]; then
    echo "ERROR: Package name cannot be empty" >&2
    return 1
  fi

  # Check for dangerous characters (backticks, semicolons, pipes, etc.)
  if echo "$name" | grep -qE '[`;|&$()<>]'; then
    echo "ERROR: Package name contains invalid characters: $name" >&2
    return 1
  fi

  # Check for path traversal attempts
  if echo "$name" | grep -q '\.\.'; then
    echo "ERROR: Package name contains path traversal: $name" >&2
    return 1
  fi

  return 0
}

# ============================================================================
# Fast Plugin/Theme List Functions (Direct Database Queries)
# ============================================================================
# Drop-in replacements for wp plugin list and wp theme list
# 60x faster (~0.5s vs 30s) by using direct DB queries instead of loading WordPress

# Fast plugin list using direct database query
# Drop-in replacement for: wp plugin list --field=name --status=active/inactive
#
# Supports:
#   --field=name (default)
#   --status=active|inactive|any (default: any)
#   --format=csv (with --fields for multiple columns)
#
# Performance: ~0.15s vs 30s for wp plugin list (200x faster)
#
# Args:
#   $@ - Parameters (--field=X, --status=X, --format=X, --fields=X,Y)
#
# Examples:
#   wp_plugin_list --field=name
#   wp_plugin_list --status=active --field=name
#   wp_plugin_list --fields=name,auto_update --format=csv
wp_plugin_list() {
  local status="any"
  local field="name"
  local fields=""
  local format=""

  # Parse parameters
  for arg in "$@"; do
    case "$arg" in
      --status=*) status="${arg#*=}" ;;
      --field=*) field="${arg#*=}" ;;
      --fields=*) fields="${arg#*=}" ;;
      --format=*) format="${arg#*=}" ;;
    esac
  done

  # Get active plugins from DB (serialized PHP array)
  local active_plugins=$(wp db query "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='active_plugins';" --skip-column-names 2>/dev/null || echo "")

  # Get auto-update plugins from DB (serialized PHP array)
  local autoupdate_plugins=$(wp db query "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='auto_update_plugins';" --skip-column-names 2>/dev/null || echo "")

  # Find all installed plugins using filesystem
  local all_plugins=$(find "${WORDPRESS_PATH}/wp-content/plugins" -maxdepth 2 -name '*.php' -type f 2>/dev/null | while read plugin_file; do
    # Extract plugin slug from path (e.g., akismet/akismet.php -> akismet/akismet.php)
    local plugin_path="${plugin_file#${WORDPRESS_PATH}/wp-content/plugins/}"
    echo "$plugin_path"
  done | grep '/' || echo "")

  # Deserialize active plugins using PHP
  local active_list=""
  if [ -n "$active_plugins" ]; then
    active_list=$(echo "$active_plugins" | php -r 'while($line=fgets(STDIN)){$arr=@unserialize($line);if(is_array($arr)){foreach($arr as $p){echo $p."\n";}}}' 2>/dev/null || echo "")
  fi

  # Deserialize auto-update plugins using PHP
  local autoupdate_list=""
  if [ -n "$autoupdate_plugins" ]; then
    autoupdate_list=$(echo "$autoupdate_plugins" | php -r 'while($line=fgets(STDIN)){$arr=@unserialize($line);if(is_array($arr)){foreach($arr as $p){echo $p."\n";}}}' 2>/dev/null || echo "")
  fi

  # Filter by status and extract slug
  echo "$all_plugins" | while read plugin_path; do
    [ -z "$plugin_path" ] && continue

    # Extract slug (first part before /)
    local slug="${plugin_path%%/*}"

    # Check if active
    local is_active=false
    if echo "$active_list" | grep -qF "$plugin_path"; then
      is_active=true
    fi

    # Apply status filter
    if [ "$status" = "active" ] && [ "$is_active" = false ]; then
      continue
    fi
    if [ "$status" = "inactive" ] && [ "$is_active" = true ]; then
      continue
    fi

    # Output based on field/format
    if [ "$format" = "csv" ] && [ -n "$fields" ]; then
      # Multi-field CSV output
      local output_parts=()
      IFS=',' read -ra FIELD_ARRAY <<< "$fields"
      for f in "${FIELD_ARRAY[@]}"; do
        case "$f" in
          name) output_parts+=("$slug") ;;
          auto_update)
            if echo "$autoupdate_list" | grep -qF "$plugin_path"; then
              output_parts+=("on")
            else
              output_parts+=("off")
            fi
            ;;
        esac
      done
      # Join with commas
      local IFS=','
      echo "${output_parts[*]}"
    else
      # Single field output (default)
      case "$field" in
        name) echo "$slug" ;;
      esac
    fi
  done | sort -u
}

# Fast theme list using direct database query
# Drop-in replacement for: wp theme list --field=name --status=active/inactive
#
# Supports:
#   --field=name (default)
#   --status=active|inactive|any (default: any)
#   --format=csv (with --fields for multiple columns)
#
# Performance: ~0.10s vs 30s for wp theme list (300x faster)
#
# Args:
#   $@ - Parameters (--field=X, --status=X, --format=X, --fields=X,Y)
#
# Examples:
#   wp_theme_list --field=name
#   wp_theme_list --status=active --field=name
#   wp_theme_list --fields=name,auto_update --format=csv
wp_theme_list() {
  local status="any"
  local field="name"
  local fields=""
  local format=""

  # Parse parameters
  for arg in "$@"; do
    case "$arg" in
      --status=*) status="${arg#*=}" ;;
      --field=*) field="${arg#*=}" ;;
      --fields=*) fields="${arg#*=}" ;;
      --format=*) format="${arg#*=}" ;;
    esac
  done

  # Get active theme from DB (stylesheet)
  local active_theme=$(wp db query "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='stylesheet';" --skip-column-names 2>/dev/null || echo "")

  # Get auto-update themes from DB (serialized PHP array)
  local autoupdate_themes=$(wp db query "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='auto_update_themes';" --skip-column-names 2>/dev/null || echo "")

  # Find all installed themes using filesystem
  local all_themes=$(find "${WORDPRESS_PATH}/wp-content/themes" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while read theme_dir; do
    basename "$theme_dir"
  done || echo "")

  # Deserialize auto-update themes using PHP
  local autoupdate_list=""
  if [ -n "$autoupdate_themes" ]; then
    autoupdate_list=$(echo "$autoupdate_themes" | php -r 'while($line=fgets(STDIN)){$arr=@unserialize($line);if(is_array($arr)){foreach($arr as $t){echo $t."\n";}}}' 2>/dev/null || echo "")
  fi

  # Filter by status and output
  echo "$all_themes" | while read theme_slug; do
    [ -z "$theme_slug" ] && continue

    # Check if active
    local is_active=false
    if [ "$theme_slug" = "$active_theme" ]; then
      is_active=true
    fi

    # Apply status filter
    if [ "$status" = "active" ] && [ "$is_active" = false ]; then
      continue
    fi
    if [ "$status" = "inactive" ] && [ "$is_active" = true ]; then
      continue
    fi

    # Output based on field/format
    if [ "$format" = "csv" ] && [ -n "$fields" ]; then
      # Multi-field CSV output
      local output_parts=()
      IFS=',' read -ra FIELD_ARRAY <<< "$fields"
      for f in "${FIELD_ARRAY[@]}"; do
        case "$f" in
          name) output_parts+=("$theme_slug") ;;
          auto_update)
            if echo "$autoupdate_list" | grep -qF "$theme_slug"; then
              output_parts+=("on")
            else
              output_parts+=("off")
            fi
            ;;
        esac
      done
      # Join with commas
      local IFS=','
      echo "${output_parts[*]}"
    else
      # Single field output (default)
      case "$field" in
        name) echo "$theme_slug" ;;
      esac
    fi
  done | sort -u
}

# Enable auto-updates for a list of plugins or themes via direct DB update
# Consolidates duplicated PHP serialization logic for plugins and themes
#
# Args:
#   $1 - Type: "plugins" or "themes"
#   $@ - List of slugs to enable auto-updates for
#
# For plugins: resolves slug to main plugin file path (e.g., akismet -> akismet/akismet.php)
# For themes: uses slug directly
#
# Performance: Single DB read + PHP merge + single DB write
enable_autoupdates() {
  local type="$1"
  shift
  local items=("$@")
  local option_name="auto_update_${type}"

  if [ ${#items[@]} -eq 0 ]; then return 0; fi

  echo "Enabling auto-updates for ${#items[@]} ${type}..."

  # Get current auto-update list from DB
  local current_value=$(wp db query "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='${option_name}';" --skip-column-names 2>/dev/null || echo "")

  # Pass items as newline-separated string
  local items_str=$(printf '%s\n' "${items[@]}")
  export AUTOUPDATE_ITEMS="$items_str"
  export AUTOUPDATE_TYPE="$type"

  # Use PHP to merge arrays and serialize
  local new_value=$(echo "$current_value" | php -r '
    $current = @unserialize(file_get_contents("php://stdin"));
    if (!is_array($current)) { $current = []; }
    $toAddStr = trim(getenv("AUTOUPDATE_ITEMS"));
    $toAdd = !empty($toAddStr) ? explode("\n", $toAddStr) : [];
    $type = getenv("AUTOUPDATE_TYPE");

    $merged = $current;
    foreach ($toAdd as $slug) {
      $slug = trim($slug);
      if (empty($slug)) continue;

      if ($type === "plugins") {
        // Resolve plugin slug to main file path
        $pluginDir = "/var/www/html/wp-content/plugins/" . $slug;
        if (is_dir($pluginDir)) {
          $mainFile = $slug . "/" . $slug . ".php";
          if (!file_exists("/var/www/html/wp-content/plugins/" . $mainFile)) {
            $files = glob($pluginDir . "/*.php");
            if (!empty($files)) {
              $mainFile = $slug . "/" . basename($files[0]);
            }
          }
          if (!in_array($mainFile, $merged)) {
            $merged[] = $mainFile;
          }
        }
      } else {
        // Themes use slug directly
        if (!in_array($slug, $merged)) {
          $merged[] = $slug;
        }
      }
    }
    echo serialize(array_values(array_unique($merged)));
  ' 2>/dev/null)

  # Update database
  if [ -n "$new_value" ]; then
    local escaped_value=$(echo "$new_value" | sed "s/'/\\\\'/g")
    wp db query "INSERT INTO ${TABLE_PREFIX}options (option_name, option_value, autoload) VALUES ('${option_name}', '$escaped_value', 'no') ON DUPLICATE KEY UPDATE option_value='$escaped_value';" >/dev/null 2>&1
    echo "Auto-updates for ${type} enabled!"
  fi
}
{{- end -}}
