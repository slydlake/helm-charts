## Plan: WordPress Init Script Refactoring

Das Init-Script im ConfigMap-Template (~2715 Zeilen) ist grundsätzlich gut durchdacht — besonders das Heartbeat-Locking, die Fast-DB-Queries und die Batch-Operationen. Folgende Änderungen verbessern Sicherheit, Performance, Klarheit und Struktur, priorisiert nach Vorgabe.

---

### 1. Sicherheitsbedenken

**Phase 1.1: Credential Exposure in Prozessargumenten fixen**

- [ ] **Step 1.1.1**: Alle `php -r` Aufrufe, die DB-Credentials inline nutzen, auf stdin-basierte Variante umstellen

  Betrifft: Heartbeat-Prozesse in `lib-lock.sh`, DB-Wait in `init.sh`

  Aktuell (z.B. Heartbeat, `configmap.yaml` ~L796-801):
  ```bash
  php -r "\$m = @new mysqli('${WORDPRESS_DB_HOST}', '${WORDPRESS_DB_USER}', '${WORDPRESS_DB_PASSWORD}', ...);"
  ```
  Credentials sind via `ps aux` sichtbar.

  **Vorschlag** — Credentials via Environment statt Prozessargumente:
  ```bash
  php -r '
    $m = @new mysqli(
      getenv("WORDPRESS_DB_HOST"),
      getenv("WORDPRESS_DB_USER"),
      getenv("WORDPRESS_DB_PASSWORD"),
      getenv("WORDPRESS_DB_NAME")
    );
    // ...
  '
  ```
  Die Env-Vars sind bereits gesetzt (kommen aus dem Deployment). Keine Änderung an der Funktionalität, aber Credentials verschwinden aus der Prozessliste.

  **Validation**: `kubectl exec <pod> -- ps aux | grep php` — keine Credentials sichtbar

- [ ] **Step 1.1.2**: Gleiches Pattern für den DB-Wait-Check in `init.sh`

  Aktuell (`configmap.yaml` ~L1131):
  ```bash
  until php -r "\$m = @new mysqli('${WORDPRESS_DB_HOST}', ...); exit(\$m->connect_error ? 1 : 0);" 2>/dev/null; do
  ```
  **Vorschlag**:
  ```bash
  until php -r 'exit(@(new mysqli(getenv("WORDPRESS_DB_HOST"), getenv("WORDPRESS_DB_USER"), getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME")))->connect_error ? 1 : 0);' 2>/dev/null; do
  ```

---

**Phase 1.2: SQL-Injection Schutz für Permalink-Struktur**

- [ ] **Step 1.2.1**: `WP_PERMALINK_STRUCTURE` escapen bevor es in SQL landet

  Aktuell (`configmap.yaml` ~L1283-1286):
  ```bash
  wp db query "INSERT INTO ${TABLE_PREFIX}options ... VALUES ('permalink_structure', '${WP_PERMALINK_STRUCTURE}', 'yes') ..."
  ```

  **Vorschlag** — wp-cli statt raw SQL verwenden:
  ```bash
  wp option update permalink_structure "${WP_PERMALINK_STRUCTURE}"
  ```
  wp-cli handled das Escaping intern. Alternativ, wenn Performance kritisch: den Wert durch `printf '%s' "$var" | sed "s/'/''/g"` escapen.

  **Validation**: Setze `customStructure: "/%postname%'; DROP TABLE wp_options; --"` und prüfe ob die DB intakt bleibt.

---

**Phase 1.3: User-Creation Input-Validierung**

- [ ] **Step 1.3.1**: Template-seitige Validierung für User-Felder mit `quote`

  Aktuell (`configmap.yaml` ~L1311-1320):
  ```bash
  run wp user create "{{ .username }}" "{{ .email }}" \
    --role="{{ .role }}" \
    --display_name="{{ .displayname }}"
  ```

  **Vorschlag** — Helm `quote` Funktion nutzen:
  ```bash
  run wp user create {{ .username | quote }} {{ .email | quote }} \
    --role={{ .role | quote }} \
    --display_name={{ .displayname | quote }} \
    --first_name={{ .firstname | quote }} \
    --last_name={{ .lastname | quote }} \
    --send-email={{ .sendEmail | quote }}
  ```

---

**Phase 1.4: Composer Autoloader nur für aktive Plugins**

- [ ] **Step 1.4.1**: MU-Plugin Autoloader auf aktive Plugins einschränken

  Aktuell (`configmap.yaml` ~L1913-1924):
  ```php
  foreach ( glob( WP_CONTENT_DIR . '/plugins/*/vendor/autoload.php' ) as $autoloader ) {
      require_once $autoloader;
  }
  ```
  Lädt auch Autoloader von deaktivierten Plugins.

  **Vorschlag**:
  ```php
  <?php
  /**
   * Plugin Name: Composer Autoloader
   * Description: Loads Composer autoloaders from active plugins and all themes
   * Author: Helm Chart
   * Version: 1.1.0
   */

  // Only load autoloaders for active plugins
  $active_plugins = get_option( 'active_plugins', array() );
  foreach ( $active_plugins as $plugin ) {
      $plugin_dir = dirname( WP_CONTENT_DIR . '/plugins/' . $plugin );
      $autoloader = $plugin_dir . '/vendor/autoload.php';
      if ( file_exists( $autoloader ) ) {
          require_once $autoloader;
      }
  }

  // Load Composer autoloaders from active theme
  $theme_autoloader = get_template_directory() . '/vendor/autoload.php';
  if ( file_exists( $theme_autoloader ) ) {
      require_once $theme_autoloader;
  }
  ```

---

### 2. Performance

**Phase 2.1: Plugin/Theme-Listen konsolidieren**

- [ ] **Step 2.1.1**: `wp_plugin_list` einmal mit allen Feldern abfragen, statt 3x

  Aktuell (`configmap.yaml` ~L1565-1567):
  ```bash
  INSTALLED_PLUGINS=$(wp_plugin_list --field=name ...)
  ACTIVE_PLUGINS=$(wp_plugin_list --status=active --field=name ...)
  AUTOUPDATE_ENABLED=$(wp_plugin_list --fields=name,auto_update --format=csv ...)
  ```

  **Vorschlag** — Eine einzige Abfrage, dann Variablen ableiten:
  ```bash
  echo "Caching plugin data..."
  ALL_PLUGIN_DATA=$(wp_plugin_list --fields=name,status,auto_update --format=csv 2>/dev/null || echo "")
  INSTALLED_PLUGINS=$(echo "$ALL_PLUGIN_DATA" | tail -n +2 | cut -d',' -f1 || echo "")
  ACTIVE_PLUGINS=$(echo "$ALL_PLUGIN_DATA" | grep ",active," | cut -d',' -f1 || echo "")
  AUTOUPDATE_ENABLED=$(echo "$ALL_PLUGIN_DATA" | grep ",on$" | cut -d',' -f1 || echo "")
  ```
  Reduziert 3 DB-Queries + 3 Filesystem-Scans auf 1.

- [ ] **Step 2.1.2**: Gleiches Pattern für Theme-Listen (`configmap.yaml` ~L2102-2104)

---

**Phase 2.2: Composer Themes batchen**

- [ ] **Step 2.2.1**: Composer-Themes wie Plugins in einem `composer require` installieren

  Aktuell (`configmap.yaml` ~L2255-2266):
  ```bash
  for package_spec in "${COMPOSER_THEMES_TO_INSTALL[@]}"; do
    retry_command composer require "$package_spec" --no-interaction
  ```

  **Vorschlag** — Batch wie bei Plugins:
  ```bash
  if [ ${#COMPOSER_THEMES_TO_INSTALL[@]} -gt 0 ]; then
    all_packages="${COMPOSER_THEMES_TO_INSTALL[@]}"
    echo "Attempting batch install: $all_packages"
    if COMPOSER_OUTPUT=$(retry_command composer require $all_packages --no-interaction 2>&1); then
      echo "Batch install successful!"
    else
      for package_spec in "${COMPOSER_THEMES_TO_INSTALL[@]}"; do
        retry_command composer require "$package_spec" --no-interaction 2>&1 || \
          handle_error "Failed to install Composer theme: $package_spec"
      done
    fi
  fi
  ```

---

**Phase 2.3: Doppeltes `composer install` vermeiden**

- [ ] **Step 2.3.1**: Guard-Variable `COMPOSER_INSTALL_DONE` einführen

  ```bash
  COMPOSER_INSTALL_DONE=false

  # Bei erstem Aufruf (nach Plugin-Installation):
  if [ "$COMPOSER_INSTALL_DONE" = "false" ] && [ -f composer.json ]; then
    retry_command composer install --no-interaction ...
    COMPOSER_INSTALL_DONE=true
  fi

  # Bei zweitem Aufruf (nach Theme-Installation) — wird übersprungen
  ```

---

### 3. Vereinfachungen

**Phase 3.1: Toten Code entfernen**

- [ ] **Step 3.1.1**: Metrics-Plugin else-Zweig fixen — **Bug!**

  Aktuell (`configmap.yaml` ~L1618-1625):
  ```bash
  else
    # Remove plugin if WORDPRESS_METRICS is empty and plugin exists
    if [ -n "${WORDPRESS_METRICS}" ] && ...
  ```
  Im `else`-Zweig von `if [ -n "${WORDPRESS_METRICS}" ]` ist `WORDPRESS_METRICS` **immer leer**. Die Bedingung ist dort immer `false`. Toter Code, Plugin wird nie entfernt.

  **Vorschlag**: else-Zweig entfernen oder Removal-Logik korrekt implementieren.

- [ ] **Step 3.1.2**: Duplizierten Plugin Management-Kommentarblock entfernen (~L1541-1563 und ~L1622-1646)

---

**Phase 3.2: `PLUGINS_MODIFIED` initialisieren**

- [ ] **Step 3.2.1**: Variable am Anfang deklarieren (neben `COMPOSER_PACKAGES_MODIFIED=false`)

  ```bash
  COMPOSER_PACKAGES_MODIFIED=false
  PLUGINS_MODIFIED=false              # <-- fehlt aktuell
  ```

---

**Phase 3.3: Auto-Update Logik in Hilfsfunktion extrahieren**

- [ ] **Step 3.3.1**: Shared Function `enable_autoupdates()` in `lib-core.sh`

  Die PHP-Serialisierungs-Logik (~L1955-2000 Plugins, ~L2330-2370 Themes) ist fast identisch.

  ```bash
  # Enable auto-updates for a list of plugins or themes
  # Args:
  #   $1 - Type: "plugins" or "themes"
  #   $@ - List of slugs to enable auto-updates for
  enable_autoupdates() {
    local type="$1"
    shift
    local items=("$@")
    local option_name="auto_update_${type}"
    if [ ${#items[@]} -eq 0 ]; then return 0; fi
    # Get current, merge, serialize, update DB
    ...
  }
  ```

---

**Phase 3.4: Wiederholtes `cd /var/www/html` eliminieren**

- [ ] **Step 3.4.1**: Einmal am Anfang des Composer-Blocks setzen, statt 8x wiederholen

---

### 4. Struktur

**Phase 4.1: `set -e` auch in base.sh**

- [ ] **Step 4.1.1**: `set -e` am Anfang von base.sh hinzufügen. Fehler beim Kopieren brechen dann den Init-Container ab.

---

**Phase 4.2: Kritische Env-Vars am Script-Start validieren**

- [ ] **Step 4.2.1**: Validierung am Anfang von `init.sh`

  ```bash
  for required_var in WORDPRESS_DB_HOST WORDPRESS_DB_USER WORDPRESS_DB_PASSWORD WORDPRESS_DB_NAME; do
    if [ -z "$(eval echo \$$required_var)" ]; then
      handle_error "Required environment variable $required_var is not set"
    fi
  done

  if [ "${WP_INIT}" = "true" ]; then
    for required_var in WP_URL WP_ADMIN_USER WP_ADMIN_PASSWORD WP_ADMIN_EMAIL; do
      if [ -z "$(eval echo \$$required_var)" ]; then
        handle_error "Required environment variable $required_var is not set (needed for WP_INIT=true)"
      fi
    done
  fi
  ```

---

**Phase 4.3: Irreführende Lock-Release-Meldung fixen**

- [ ] **Step 4.3.1**: Log-Meldung "Database lock released." entfernen — Lock wird erst im EXIT-Trap released

  ```bash
  # Lock is released via EXIT trap
  echo "Init script completed successfully!"
  exit 0
  ```

---

**Phase 4.4: Langfristig — Template aufteilen (Empfehlung)**

- [ ] **Step 4.4.1** *(Optional)*: `init.sh` als eigenes Template (`_init-script.tpl`) mit `{{ define }}` / `{{ include }}`, damit die Hauptdatei übersichtlich bleibt.

---

### Zusammenfassung

| Prio | Phase | Was | Impact | Status |
|------|-------|-----|--------|--------|
| **Hoch** | 1.1 | Credential Exposure fixen | Security | Done |
| **Hoch** | 1.2 | SQL-Injection Permalink | Security | Done |
| **Hoch** | 3.1.1 | Metrics-Plugin toter Code (Bug!) | Correctness | Done |
| **Mittel** | 1.3 | User-Creation Input-Validierung | Security | Done |
| **Mittel** | 1.4 | Autoloader nur aktive Plugins | Security | Done |
| **Mittel** | 2.1 | Plugin/Theme-Listen konsolidieren | Performance | Done |
| **Mittel** | 2.2 | Composer Themes batchen | Performance | Done |
| **Mittel** | 3.2 | `PLUGINS_MODIFIED` init | Correctness | Done |
| **Niedrig** | 2.3 | Doppeltes `composer install` | Performance | Done |
| **Niedrig** | 3.3 | Auto-Update Hilfsfunktion | DRY | Done |
| **Niedrig** | 3.4 | `cd` Wiederholungen | Cleanup | Done |
| **Niedrig** | 4.1 | `set -e` in base.sh | Reliability | Done |
| **Niedrig** | 4.2 | Env-Var Validierung | Reliability | Done |
| **Niedrig** | 4.3 | Lock-Log irreführend | Correctness | Done |
| **Niedrig** | 4.4 | Template aufteilen | Maintainability | Done |

**Total Steps**: 4 Phasen × 15 Steps = 15 trackbare Items
**Estimated Duration**: 3–5 Stunden Implementation
**Risk Level**: Niedrig — alles sind inkrementelle, abwärtskompatible Änderungen

### Weitere Überlegungen

1. **sh vs bash Kompatibilität**: Im Deployment werden die Scripts via `sh -c` aufgerufen, aber `lib-core.sh` nutzt Bash-Features (Arrays). Solange das WordPress-Image Bash hat, ist das OK — aber ein Kommentar wäre gut.
2. **Composer im Image vorinstallieren**: Statt bei jedem Pod-Start Composer herunterzuladen, könnte ein Custom-Image mit vorinstalliertem Composer gebaut werden (~5s Einsparung + eliminiert externe Abhängigkeit).
3. **Die `wp_plugin_list`/`wp_theme_list` Funktionen sind exzellent** — die 60-200x Beschleunigung gegenüber `wp plugin list` ist ein echtes Highlight. Ebenso das Heartbeat-Locking.
