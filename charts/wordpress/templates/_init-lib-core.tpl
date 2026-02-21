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

# WP-CLI wrapper that keeps plugins enabled (for plugin-provided commands)
# Still skips themes for startup performance and consistency.
#
# Args: All arguments are passed through to wp-cli
wp_with_plugins() {
  if [ "${DRY_RUN}" = "true" ]; then
    echo "[DRY_RUN] wp(with-plugins) $*"
    return 0
  fi

  if [ "${DEBUG}" = "true" ]; then
    command wp --path="${WORDPRESS_PATH}" --skip-themes --debug "$@"
  else
    command wp --path="${WORDPRESS_PATH}" --skip-themes "$@"
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

# Multisite-aware wp wrapper for site-specific operations
# Automatically adds --url parameter for the specified site
#
# Args:
#   $1 - Site slug or blog_id (e.g., "blog" or "2")
#   $@ - Remaining arguments passed to wp
#
# Example:
#   wp_site blog plugin activate woocommerce
#   wp_site 2 theme activate twentytwentythree
wp_site() {
  local site_identifier="$1"
  shift

  if [ -z "$site_identifier" ]; then
    echo "ERROR: wp_site requires site identifier as first argument"
    return 1
  fi

  # If multisite is not enabled, fall back to regular wp
  if [ "${WP_MULTISITE_ENABLED:-false}" != "true" ]; then
    wp "$@"
    return $?
  fi

  # Determine site URL based on identifier type
  local site_url=""
  if [[ "$site_identifier" =~ ^[0-9]+$ ]]; then
    # Numeric identifier - it's a blog_id, get URL from DB
    site_url=$(wp db query "SELECT CONCAT(CASE WHEN domain LIKE 'http%' THEN '' ELSE 'http://' END, domain, path) FROM ${TABLE_PREFIX}blogs WHERE blog_id=${site_identifier};" --skip-column-names 2>/dev/null | head -n1)
  else
    # String identifier - it's a slug, construct URL
    if [ "${WP_MULTISITE_SUBDOMAIN:-false}" = "true" ]; then
      site_url="http://${site_identifier}.${DOMAIN_CURRENT_SITE:-$(echo "${WP_URL}" | sed -E 's|^https?://||' | sed -E 's|/.*||')}"
    else
      site_url="${WP_URL%/}/${site_identifier}"
    fi
  fi

  if [ -z "$site_url" ]; then
    echo "ERROR: Could not determine URL for site: $site_identifier"
    return 1
  fi

  wp --url="$site_url" "$@"
}

# Multisite-aware wp wrapper for network-wide operations
# Adds --network flag to wp commands
#
# Args:
#   $@ - Arguments passed to wp with --network flag
#
# Example:
#   wp_network plugin activate woocommerce
#   wp_network theme enable twentytwentythree
wp_network() {
  if [ "${WP_MULTISITE_ENABLED:-false}" != "true" ]; then
    echo "WARNING: wp_network called but multisite is not enabled"
    wp "$@"
    return $?
  fi

  wp --network "$@"
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
  # In multisite, auto_update_plugins is stored in wp_sitemeta (network option)
  local autoupdate_plugins=""
  if [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
    autoupdate_plugins=$(wp db query "SELECT meta_value FROM ${TABLE_PREFIX}sitemeta WHERE meta_key='auto_update_plugins' AND site_id=1;" --skip-column-names 2>/dev/null || echo "")
  else
    autoupdate_plugins=$(wp db query "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='auto_update_plugins';" --skip-column-names 2>/dev/null || echo "")
  fi

  # Get network-active plugins from wp_sitemeta (for multisite)
  local network_active_plugins=""
  if [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
    network_active_plugins=$(wp db query "SELECT meta_value FROM ${TABLE_PREFIX}sitemeta WHERE meta_key='active_sitewide_plugins' AND site_id=1;" --skip-column-names 2>/dev/null || echo "")
  fi

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

  # Deserialize network-active plugins using PHP (keys are plugin paths for active_sitewide_plugins)
  local network_active_list=""
  if [ -n "$network_active_plugins" ]; then
    network_active_list=$(echo "$network_active_plugins" | php -r 'while($line=fgets(STDIN)){$arr=@unserialize($line);if(is_array($arr)){foreach(array_keys($arr) as $p){echo $p."\n";}}}' 2>/dev/null || echo "")
  fi

  # Filter by status and extract slug
  echo "$all_plugins" | while read plugin_path; do
    [ -z "$plugin_path" ] && continue

    # Extract slug (first part before /)
    local slug="${plugin_path%%/*}"

    # Check if active (site-active or network-active)
    local is_active=false
    if echo "$active_list" | grep -qF "$plugin_path"; then
      is_active=true
    elif echo "$network_active_list" | grep -qF "$plugin_path"; then
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
          status)
            if [ "$is_active" = true ]; then
              output_parts+=("active")
            else
              output_parts+=("inactive")
            fi
            ;;
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
  # In multisite, auto_update_themes is stored in wp_sitemeta (network option)
  local autoupdate_themes=""
  if [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
    autoupdate_themes=$(wp db query "SELECT meta_value FROM ${TABLE_PREFIX}sitemeta WHERE meta_key='auto_update_themes' AND site_id=1;" --skip-column-names 2>/dev/null || echo "")
  else
    autoupdate_themes=$(wp db query "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='auto_update_themes';" --skip-column-names 2>/dev/null || echo "")
  fi

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
          status)
            if [ "$is_active" = true ]; then
              output_parts+=("active")
            else
              output_parts+=("inactive")
            fi
            ;;
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

# ============================================================================
# Helm Site Mapping — persistent name → blog_id tracking in wp_sitemeta
# ============================================================================
# Stores a JSON object in wp_sitemeta (meta_key='helm_managed_sites', site_id=1)
# Format: {"company-blog": 3, "shop": 2}
# This allows site slug renames without losing the blog_id association.

SITE_MAPPING=""

# Load site mapping from database into SITE_MAPPING variable
load_site_mapping() {
  SITE_MAPPING=$(php <<'PHPEOF'
<?php
  $host = getenv("WORDPRESS_DB_HOST");
  $user = getenv("WORDPRESS_DB_USER");
  $pass = getenv("WORDPRESS_DB_PASSWORD");
  $name = getenv("WORDPRESS_DB_NAME");
  $prefix = getenv("WORDPRESS_TABLE_PREFIX") ?: "wp_";
  $c = new mysqli($host, $user, $pass, $name);
  if ($c->connect_error) { echo "{}"; exit; }
  $r = $c->query("SELECT meta_value FROM {$prefix}sitemeta WHERE meta_key='helm_managed_sites' AND site_id=1");
  if ($r && $row = $r->fetch_assoc()) {
    $data = json_decode($row["meta_value"], true);
    if (is_array($data)) { echo json_encode($data); $c->close(); exit; }
  }
  echo "{}";
  $c->close();
PHPEOF
  ) || SITE_MAPPING="{}"
}

# Save site mapping from SITE_MAPPING variable to database
save_site_mapping() {
  local json="$SITE_MAPPING"
  php <<PHPEOF
<?php
  \$host = getenv("WORDPRESS_DB_HOST");
  \$user = getenv("WORDPRESS_DB_USER");
  \$pass = getenv("WORDPRESS_DB_PASSWORD");
  \$name = getenv("WORDPRESS_DB_NAME");
  \$prefix = getenv("WORDPRESS_TABLE_PREFIX") ?: "wp_";
  \$c = new mysqli(\$host, \$user, \$pass, \$name);
  if (\$c->connect_error) { echo "WARNING: Failed to save site mapping"; exit(1); }
  \$json = '$json';
  \$escaped = \$c->real_escape_string(\$json);
  \$r = \$c->query("SELECT meta_id FROM {\$prefix}sitemeta WHERE meta_key='helm_managed_sites' AND site_id=1");
  if (\$r && \$r->num_rows > 0) {
    \$c->query("UPDATE {\$prefix}sitemeta SET meta_value='{\$escaped}' WHERE meta_key='helm_managed_sites' AND site_id=1");
  } else {
    \$c->query("INSERT INTO {\$prefix}sitemeta (site_id, meta_key, meta_value) VALUES (1, 'helm_managed_sites', '{\$escaped}')");
  }
  \$c->close();
PHPEOF
}

# Get blog_id for a Helm site name from the in-memory mapping
# Args: $1 - site name
# Returns: blog_id or empty string
get_blog_id_by_name() {
  local name="$1"
  echo "$SITE_MAPPING" | php -r '
    $data = json_decode(file_get_contents("php://stdin"), true);
    $name = $argv[1];
    echo isset($data[$name]) ? $data[$name] : "";
  ' -- "$name" 2>/dev/null
}

# Store name → blog_id in the in-memory mapping (call save_site_mapping to persist)
# Args: $1 - site name, $2 - blog_id
set_blog_id_for_name() {
  local name="$1"
  local blog_id="$2"
  SITE_MAPPING=$(echo "$SITE_MAPPING" | php -r '
    $data = json_decode(file_get_contents("php://stdin"), true) ?: [];
    $data[$argv[1]] = (int)$argv[2];
    echo json_encode($data);
  ' -- "$name" "$blog_id" 2>/dev/null) || true
}

# Remove a name from the in-memory mapping
# Args: $1 - site name
remove_name_from_mapping() {
  local name="$1"
  SITE_MAPPING=$(echo "$SITE_MAPPING" | php -r '
    $data = json_decode(file_get_contents("php://stdin"), true) ?: [];
    unset($data[$argv[1]]);
    echo json_encode($data, JSON_FORCE_OBJECT);
  ' -- "$name" 2>/dev/null) || true
}

# Get current slug/path for a blog_id from wp_blogs
# Args: $1 - blog_id
# Returns: slug (without slashes)
get_site_slug_by_blog_id() {
  local blog_id="$1"
  if [ "${WP_MULTISITE_SUBDOMAIN:-false}" = "true" ]; then
    wp db query "SELECT domain FROM ${TABLE_PREFIX}blogs WHERE blog_id=${blog_id};" --skip-column-names 2>/dev/null | sed "s/\\.${DOMAIN_CURRENT_SITE}$//" | tr -d '[:space:]'
  else
    wp db query "SELECT path FROM ${TABLE_PREFIX}blogs WHERE blog_id=${blog_id};" --skip-column-names 2>/dev/null | sed 's|^/||;s|/$||' | tr -d '[:space:]'
  fi
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
  # In multisite, auto-update options are stored in wp_sitemeta (network options)
  local current_value=""
  if [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
    current_value=$(wp db query "SELECT meta_value FROM ${TABLE_PREFIX}sitemeta WHERE meta_key='${option_name}' AND site_id=1;" --skip-column-names 2>/dev/null || echo "")
  else
    current_value=$(wp db query "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='${option_name}';" --skip-column-names 2>/dev/null || echo "")
  fi

  # Pass items as newline-separated string
  local items_str=$(printf '%s\n' "${items[@]}")
  export AUTOUPDATE_ITEMS="$items_str"
  export AUTOUPDATE_TYPE="$type"

  # Use PHP to resolve slugs and serialize (full-replace: only items from values, not merging with DB)
  # NOTE: Uses heredoc (<<'PHPEOF') instead of php -r '...' to avoid single-quote conflicts
  # with preg_match regex delimiters inside the PHP code
  local new_value=$(echo "$current_value" | php <<'PHPEOF'
<?php
    // Read current value (only needed for reference, not for merging)
    $current = @unserialize(file_get_contents("php://stdin"));
    if (!is_array($current)) { $current = []; }
    $toAddStr = trim(getenv("AUTOUPDATE_ITEMS"));
    $toAdd = !empty($toAddStr) ? explode("\n", $toAddStr) : [];
    $type = getenv("AUTOUPDATE_TYPE");

    $merged = [];  // Full-replace: build list only from Helm values
    foreach ($toAdd as $slug) {
      $slug = trim($slug);
      if (empty($slug)) continue;

      if ($type === "plugins") {
        // Resolve plugin slug to main plugin file (the one with "Plugin Name:" header)
        $pluginDir = "/var/www/html/wp-content/plugins/" . $slug;
        if (is_dir($pluginDir)) {
          $mainFile = null;
          // First try conventional $slug/$slug.php
          $conventional = $slug . "/" . $slug . ".php";
          if (file_exists("/var/www/html/wp-content/plugins/" . $conventional)) {
            $content = @file_get_contents("/var/www/html/wp-content/plugins/" . $conventional);
            if ($content !== false && preg_match('/^\s*\*?\s*Plugin\s*Name\s*:/mi', $content)) {
              $mainFile = $conventional;
            }
          }
          // Fallback: scan all .php files for WordPress plugin header
          if ($mainFile === null) {
            $files = glob($pluginDir . "/*.php");
            foreach ($files as $file) {
              $content = @file_get_contents($file);
              if ($content !== false && preg_match('/^\s*\*?\s*Plugin\s*Name\s*:/mi', $content)) {
                $mainFile = $slug . "/" . basename($file);
                break;
              }
            }
          }
          if ($mainFile !== null) {
            // Remove any existing entry for the same slug (stale paths from previous versions)
            $merged = array_values(array_filter($merged, function($entry) use ($slug) {
              return strpos($entry, $slug . "/") !== 0;
            }));
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
PHPEOF
)

  # Update database
  if [ -n "$new_value" ]; then
    local escaped_value=$(echo "$new_value" | sed "s/'/\\\\'/g")
    if [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
      # Multisite: write to wp_sitemeta (no unique key, so check existence first)
      local row_exists=$(wp db query "SELECT COUNT(*) FROM ${TABLE_PREFIX}sitemeta WHERE meta_key='${option_name}' AND site_id=1;" --skip-column-names 2>/dev/null || echo "0")
      if [ "$row_exists" -gt 0 ] 2>/dev/null; then
        wp db query "UPDATE ${TABLE_PREFIX}sitemeta SET meta_value='$escaped_value' WHERE meta_key='${option_name}' AND site_id=1;" >/dev/null 2>&1
      else
        wp db query "INSERT INTO ${TABLE_PREFIX}sitemeta (site_id, meta_key, meta_value) VALUES (1, '${option_name}', '$escaped_value');" >/dev/null 2>&1
      fi
      # Clean up stale entries from wrong table (from previous versions)
      wp db query "DELETE FROM ${TABLE_PREFIX}options WHERE option_name='${option_name}';" >/dev/null 2>&1
    else
      wp db query "INSERT INTO ${TABLE_PREFIX}options (option_name, option_value, autoload) VALUES ('${option_name}', '$escaped_value', 'no') ON DUPLICATE KEY UPDATE option_value='$escaped_value';" >/dev/null 2>&1
    fi
    echo "Auto-updates for ${type} enabled!"
  fi
}
{{- end -}}
