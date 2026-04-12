{{- define "wordpress.init-lib-composer" -}}
#!/bin/bash
# WordPress Helm Chart - Composer Library
# Provides Composer package management utilities

# Install Composer on-demand to temporary directory
# Downloads, verifies checksum, and installs to COMPOSER_INSTALL_DIR
# Idempotent - skips if composer already available
#
# Performance Notes:
#   - Downloads only happen once per pod lifetime
#   - Uses retry logic for network resilience
#   - Checksum verification prevents corrupted downloads
ensure_composer() {
  # Set Composer home to writable directory
  export COMPOSER_HOME="${COMPOSER_HOME_DIR}"
  mkdir -p "$COMPOSER_HOME"

  if ! command -v composer &> /dev/null; then
    echo "Composer not found, installing..."
    cd "${COMPOSER_INSTALL_DIR}" || handle_error "Cannot access Composer install directory"

    # Download Composer installer with retry logic
    echo "  Downloading Composer installer..."
    if ! retry_command php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"; then
      handle_error "Failed to download Composer installer after retries"
    fi

    # Download and verify checksum with retry logic
    echo "  Verifying checksum..."
    if ! EXPECTED_CHECKSUM="$(retry_command php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"; then
      rm -f composer-setup.php
      handle_error "Failed to download Composer checksum after retries"
    fi

    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
      rm composer-setup.php
      handle_error "Invalid Composer installer checksum"
    fi

    # Install Composer to temporary location
    echo "  Running installer..."
    php composer-setup.php --quiet --install-dir="${COMPOSER_INSTALL_DIR}" --filename=composer 2>&1 | grep -v "PHP version" | grep -v "diagnose" || true
    rm composer-setup.php

    # Add to PATH for this session
    export PATH="${COMPOSER_INSTALL_DIR}:$PATH"

    echo "  Composer installed!"
  fi
}

# Execute composer command with proper environment
# Wraps composer with DRY_RUN support
#
# Args:
#   $@ - Composer command and arguments
composer_exec() {
  if [ "${DRY_RUN}" = "true" ]; then
    echo "[DRY_RUN] composer $*"
    return 0
  fi
  composer "$@"
}

# Run a Composer command, print output with low-signal lines filtered, and
# preserve the real Composer exit code.
#
# Args:
#   $@ - Composer command and arguments (without the leading composer binary)
composer_run_filtered() {
  local output=""
  local exit_code=0

  if [ "${DRY_RUN}" = "true" ]; then
    echo "[DRY_RUN] composer $*"
    return 0
  fi

  output=$(composer "$@" 2>&1)
  exit_code=$?

  if [ -n "$output" ]; then
    printf '%s\n' "$output" | grep -v "suggest" | grep -v "funding" || true
  fi

  return $exit_code
}

# Check whether a package is present in composer.json require.
# This must inspect the actual require map, not the whole file, because package
# names can also appear in installer-path rules.
#
# Args:
#   $1 - Composer package name
#   $2 - Optional path to composer.json (default: composer.json)
composer_package_is_required() {
  local package_name="$1"
  local composer_file="${2:-composer.json}"

  if [ -z "$package_name" ] || [ ! -f "$composer_file" ]; then
    return 1
  fi

  COMPOSER_REQUIRED_PACKAGE="$package_name" php -r '
    $composerFile = $argv[1];
    $packageName = getenv("COMPOSER_REQUIRED_PACKAGE");
    $json = json_decode(file_get_contents($composerFile), true);

    if (!is_array($json) || !isset($json["require"]) || !is_array($json["require"])) {
      exit(1);
    }

    exit(array_key_exists($packageName, $json["require"]) ? 0 : 1);
  ' "$composer_file"
}

# Link a Composer package from vendor/ into a WordPress plugin/theme directory
# when Composer keeps the package in vendor/ (for example type=library).
#
# Args:
#   $1 - Composer package name (vendor/package)
#   $2 - Target directory in the WordPress tree
link_vendor_package_into_wordpress_dir() {
  local package_name="$1"
  local target_dir="$2"
  local source_dir="/var/www/html/vendor/${package_name}"

  if [ -z "$package_name" ] || [ -z "$target_dir" ]; then
    return 1
  fi

  if [ -d "$target_dir" ] || [ -L "$target_dir" ]; then
    return 0
  fi

  if [ ! -d "$source_dir" ]; then
    return 1
  fi

  mkdir -p "$(dirname "$target_dir")"
  ln -s "$source_dir" "$target_dir"
  return 0
}

# Synchronize composer.json with chart-managed repositories and installer paths.
# Explicit package rules ensure Composer packages land in WordPress plugin/theme
# directories even when upstream packages are declared as type=library.
#
# Args:
#   $1 - JSON array of custom repositories
#   $2 - JSON array of Composer plugin package names
#   $3 - JSON array of Composer theme package names
sync_composer_json() {
  local custom_repos_json="${1:-[]}"
  local plugin_packages_json="${2:-[]}"
  local theme_packages_json="${3:-[]}"

  CUSTOM_REPOS_JSON="$custom_repos_json" \
  COMPOSER_PLUGIN_PACKAGES_JSON="$plugin_packages_json" \
  COMPOSER_THEME_PACKAGES_JSON="$theme_packages_json" \
  php -r '
    function uniqueRules(array $rules): array {
      $unique = [];
      foreach ($rules as $rule) {
        if (!is_string($rule) || $rule === "") {
          continue;
        }
        if (!in_array($rule, $unique, true)) {
          $unique[] = $rule;
        }
      }
      return $unique;
    }

    $json = json_decode(file_get_contents("composer.json"), true);
    if (!is_array($json)) {
      fwrite(STDERR, "composer.json is invalid JSON\n");
      exit(1);
    }

    $cleanJson = [];
    foreach ($json as $key => $value) {
      if (!is_numeric($key)) {
        $cleanJson[$key] = $value;
      }
    }
    $json = $cleanJson;

    if (!isset($json["require"]) || !is_array($json["require"]) || $json["require"] === []) {
      $json["require"] = new stdClass();
    }

    $customRepos = json_decode(getenv("CUSTOM_REPOS_JSON") ?: "[]", true);
    if (!is_array($customRepos)) {
      $customRepos = [];
    }

    $pluginPackages = json_decode(getenv("COMPOSER_PLUGIN_PACKAGES_JSON") ?: "[]", true);
    if (!is_array($pluginPackages)) {
      $pluginPackages = [];
    }

    $themePackages = json_decode(getenv("COMPOSER_THEME_PACKAGES_JSON") ?: "[]", true);
    if (!is_array($themePackages)) {
      $themePackages = [];
    }

    $json["repositories"] = [
      ["type" => "composer", "url" => "https://wpackagist.org"],
    ];
    foreach ($customRepos as $repo) {
      if (is_array($repo)) {
        $json["repositories"][] = $repo;
      }
    }

    if (!isset($json["extra"]) || !is_array($json["extra"])) {
      $json["extra"] = [];
    }
    if (!isset($json["extra"]["installer-paths"]) || !is_array($json["extra"]["installer-paths"])) {
      $json["extra"]["installer-paths"] = [];
    }
    unset($json["extra"]["installer-types"]);

    $pluginPath = "wp-content/plugins/{\$name}/";
    $themePath = "wp-content/themes/{\$name}/";

    $existingPluginRules = isset($json["extra"]["installer-paths"][$pluginPath]) && is_array($json["extra"]["installer-paths"][$pluginPath])
      ? $json["extra"]["installer-paths"][$pluginPath]
      : [];
    $existingThemeRules = isset($json["extra"]["installer-paths"][$themePath]) && is_array($json["extra"]["installer-paths"][$themePath])
      ? $json["extra"]["installer-paths"][$themePath]
      : [];

    $json["extra"]["installer-paths"][$pluginPath] = uniqueRules(array_merge(
      ["type:wordpress-plugin"],
      $existingPluginRules,
      $pluginPackages
    ));
    $json["extra"]["installer-paths"][$themePath] = uniqueRules(array_merge(
      ["type:wordpress-theme"],
      $existingThemeRules,
      $themePackages
    ));

    if (!isset($json["config"]) || !is_array($json["config"])) {
      $json["config"] = [];
    }
    if (!isset($json["config"]["allow-plugins"]) || !is_array($json["config"]["allow-plugins"])) {
      $json["config"]["allow-plugins"] = [];
    }
    $json["config"]["allow-plugins"]["composer/installers"] = true;
    unset($json["config"]["allow-plugins"]["oomphinc/composer-installers-extender"]);

    if (is_array($json["require"]) && isset($json["require"]["oomphinc/composer-installers-extender"])) {
      unset($json["require"]["oomphinc/composer-installers-extender"]);
    }

    echo json_encode($json, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
  '
}
{{- end -}}
