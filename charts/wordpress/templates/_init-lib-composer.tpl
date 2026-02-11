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
{{- end -}}
