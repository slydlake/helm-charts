## Plan: Non-Root Base Init + Lock Crash Safety

**TL;DR:** Root-Nutzung auf einen minimalen 1-Zeiler Fix-Permissions-Container reduzieren. `wordpress-base` läuft dann komplett als uid 33 — alle Dateien werden natürlich 33:33 owned, kein `chown` mehr nötig. Für Crash-Safety: SIGTERM-Trap in init.sh, damit der DB-Lock vor Container-Kill released wird.

### Architecture & Constraints

**Architecture Overview:**
```
Init Container Pipeline (sequentiell):
┌─────────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│  fix-permissions    │──▶│  wordpress-base   │──▶│  wordpress-init  │
│  (root, 1 command)  │   │  (uid 33, non-root)│  │  (uid 33, non-root)│
│  chown -R 33:33     │   │  cp core, htaccess │  │  plugins, themes  │
│  + chmod 2775       │   │  mu-plugins, libs  │  │  config, composer │
└─────────────────────┘   └──────────────────┘   └──────────────────┘
```

**Constraints & Limitations:**
- Longhorn RWX (NFS-basiert) ignoriert `fsGroup` — PVC mount startet als `root:root 755`
- NFS akzeptiert `chown` nur von uid 0 mit CHOWN Capability
- Pod Security Standards "restricted" warnt bei root-Containern (akzeptabel für minimalen Fix-Perm-Container)
- Die copy-lock im base.sh (`noclobber`) hat 120s Stale-Detection als Safety-Net
- Die DB-Locks im init.sh haben 60s Heartbeat-Stale-Detection als Safety-Net

### Detailed Steps with Code Examples

**Phase 1: Fix-Permissions Init Container (minimaler Root)**

- [ ] **Step 1.1**: Neuen Init Container `wordpress-fix-permissions` in `deployment.yaml` VOR `wordpress-base` einfügen

  ```yaml
  initContainers:
    # Minimal root container - ONLY fixes PVC ownership for NFS-based storage
    # (e.g. Longhorn RWX) that doesn't respect Kubernetes fsGroup settings.
    # All subsequent containers run as non-root uid 33 (www-data).
    - name: {{ .Chart.Name }}-fix-permissions
      image: {{ include "slycharts.image" (dict "image" .Values.image "defaultTag" .Chart.AppVersion) }}
      {{- with .Values.containerSecurityContextBase }}
      securityContext:
        {{- toYaml . | nindent 12 }}
      {{- end }}
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      command: ["sh", "-c", "chown -R 33:33 /tmp/wordpress && chmod 2775 /tmp/wordpress && echo 'PVC ownership fixed!'"]
      volumeMounts:
        - name: {{ include "wordpress.fullname" . }}
          mountPath: /tmp/wordpress
    - name: {{ .Chart.Name }}-base
      # ... (jetzt mit containerSecurityContext statt containerSecurityContextBase)
  ```

  **Validation**: `helm template test . --values samples/advanced2.values.yaml | grep -A 20 "fix-permissions"`
  **Expected**: Container mit root securityContext und nur `chown` command

- [ ] **Step 1.2**: `wordpress-base` wieder auf `containerSecurityContext` umstellen (non-root)

  ```yaml
    - name: {{ .Chart.Name }}-base
      image: {{ include "slycharts.image" (dict "image" .Values.image "defaultTag" .Chart.AppVersion) }}
      {{- with .Values.containerSecurityContext }}  # <-- war: containerSecurityContextBase
      securityContext:
        {{- toYaml . | nindent 12 }}
      {{- end }}
  ```

  **Validation**: `helm template test . | grep -B 2 -A 10 "wordpress-base"`
  **Expected**: `runAsNonRoot: true`, keine capabilities, `runAsUser` nicht 0

- [ ] **Step 1.3**: `containerSecurityContextBase` in `values.yaml` verschlanken — FOWNER droppen

  ```yaml
  containerSecurityContextBase:
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    privileged: false
    capabilities:
      drop:
        - ALL
      add:
        - CHOWN
        - DAC_OVERRIDE
    seccompProfile:
      type: RuntimeDefault
  ```

  **Validation**: `grep -A 10 containerSecurityContextBase values.yaml`
  **Expected**: Nur CHOWN + DAC_OVERRIDE (kein FOWNER mehr)

- [ ] **Step 1.4**: `values.schema.json` prüfen und ggf. anpassen falls `containerSecurityContextBase` Properties sich geändert haben

  **Validation**: `helm lint . --values samples/advanced2.values.yaml`

**Phase 2: Base-Init komplett non-root machen**

- [ ] **Step 2.1**: Root-Check + recursive chown am Anfang von `_init-base.tpl` entfernen

  ```bash
  # ENTFERNEN - wird jetzt vom fix-permissions Container erledigt:
  # if [ "$(id -u)" = "0" ]; then
  #   echo "Fixing PVC ownership (recursive chown to 33:33)..."
  #   chown -R 33:33 /tmp/wordpress
  #   chmod 2775 /tmp/wordpress
  #   echo "PVC ownership fixed!"
  # fi
  ```

  **Validation**: `grep -n "chown\|id -u" templates/_init-base.tpl`
  **Expected**: Keine chown-Aufrufe mehr

- [ ] **Step 2.2**: `chown -R 33:33` aus `copy_wp_core()` entfernen — Dateien sind schon uid 33 owned

  ```bash
  copy_wp_core() {
    local LOCK_FILE="/tmp/wordpress/.wp-copy-lock"
    if (set -o noclobber; echo "$$" > "$LOCK_FILE") 2>/dev/null; then
      trap 'rm -f "$LOCK_FILE"' EXIT
      echo "Copying WordPress core files..."
      cd /usr/src/wordpress || exit 1
      for item in *; do
        if [ "$item" != "wp-content" ]; then
          cp -rf "$item" /tmp/wordpress/ || exit 1
        fi
      done
      # No chown needed - running as uid 33, files are already owned correctly
      rm -f "$LOCK_FILE"
      trap - EXIT
      echo "WordPress core files copied successfully!"
    else
      # ... (wait logic bleibt gleich)
    fi
  }
  ```

  **Validation**: `grep -n "chown" templates/_init-base.tpl`
  **Expected**: Keine Treffer

- [ ] **Step 2.3**: `chown www-data:www-data` aus MU-Plugins Sektion entfernen

  Vorher:
  ```bash
  mkdir -p /tmp/wordpress/wp-content/mu-plugins
  chown www-data:www-data /tmp/wordpress/wp-content/mu-plugins
  chmod 755 /tmp/wordpress/wp-content/mu-plugins
  ```

  Nachher:
  ```bash
  mkdir -p /tmp/wordpress/wp-content/mu-plugins
  chmod 755 /tmp/wordpress/wp-content/mu-plugins
  ```

  Und bei den Datei-Kopier-Stellen:
  ```bash
  # Vorher:
  chown www-data:www-data /tmp/wordpress/wp-content/mu-plugins/{{ .key }}
  chmod 644 /tmp/wordpress/wp-content/mu-plugins/{{ .key }}

  # Nachher (chown entfernen, chmod behalten):
  chmod 644 /tmp/wordpress/wp-content/mu-plugins/{{ .key }}
  ```

  Gleich für den `find -exec`:
  ```bash
  # Vorher:
  find /tmp/wordpress/wp-content/mu-plugins -type f -exec chown www-data:www-data {} \;
  find /tmp/wordpress/wp-content/mu-plugins -type f -exec chmod 644 {} \;

  # Nachher:
  find /tmp/wordpress/wp-content/mu-plugins -type f -exec chmod 644 {} \;
  ```

  **Validation**: `grep -n "chown" templates/_init-base.tpl`
  **Expected**: 0 Treffer

- [ ] **Step 2.4**: Alle 8 Samples mit `helm template` validieren

  ```bash
  for f in samples/*.values.yaml; do
    echo "=== $f ===" && helm template test . --values "$f" > /dev/null 2>&1 && echo "OK" || echo "FAIL"
  done
  ```

  **Expected**: 8× OK

**Phase 3: Lock-Release bei Container-Crash**

- [ ] **Step 3.1**: SIGTERM/SIGINT Trap in `_init-script.tpl` hinzufügen (vor dem EXIT Trap)

  ```bash
  # Ensure locks are released even when the container is killed (SIGTERM from kubelet)
  # SIGTERM → exit 1 → triggers EXIT trap → releases locks + stops heartbeat
  # Note: SIGKILL (after terminationGracePeriodSeconds) cannot be caught,
  # but the heartbeat-based stale detection handles that case (60s timeout)
  trap 'echo "Received termination signal, cleaning up..."; exit 1' TERM INT
  trap '_stop_heartbeat; release_bootstrap_lock; release_config_lock' EXIT
  ```

  **Beachte**: `trap 'exit 1' TERM INT` muss VOR `trap ... EXIT` stehen. Ablauf bei SIGTERM:
  1. TERM trap feuert → `exit 1`
  2. EXIT trap feuert → Locks released, Heartbeat gestoppt
  3. Prozess terminiert sauber

  **Validation**: `grep -n "trap" templates/_init-script.tpl`
  **Expected**: 3 trap-Zeilen (TERM INT, EXIT, und der `trap - EXIT` weiter unten)

- [ ] **Step 3.2**: Sicherstellen, dass die stale-Lock Detection ausreicht für SIGKILL

  Die Heartbeat-basierte Stale-Detection greift nach 60s (`STALE_THRESHOLD=60`). Das deckt den Fall ab, wenn:
  - SIGKILL nach `terminationGracePeriodSeconds` (default 30s) den Prozess sofort beendet
  - Der nächste Pod startet und auf den Lock wartet
  - Nach 60s ohne Heartbeat-Update wird der Lock als stale erkannt und überschrieben

  **Validation**: Kein Code-Change nötig, nur Review dass `STALE_THRESHOLD=60` in `_init-lib-lock.tpl` passt.

**Phase 4: Cleanup & Docs**

- [ ] **Step 4.1**: Kommentar bei `containerSecurityContextBase` in `values.yaml` aktualisieren

  ```yaml
  ## @param containerSecurityContextBase object Security context for the fix-permissions init container
  ## Runs as root to fix PVC ownership on NFS-based storage (e.g. Longhorn RWX).
  ## Only used for a single chown command. All other containers remain non-root.
  ```

- [ ] **Step 4.2**: Helm lint + template für alle Samples

  ```bash
  helm lint . --values samples/advanced2.values.yaml && echo "Lint OK"
  ```

### Infrastructure Context
- **Storage**: Longhorn RWX (NFS-basiert), ignoriert fsGroup
- **Cluster**: Talos Linux, Pod Security Standards "restricted" (warnings OK)
- **Bestehende Safety-Nets**: 
  - Filesystem Lock: 120s stale-detection via Datei-Check
  - DB Lock: 60s stale-detection via Heartbeat-Timestamp

### Further Considerations
1. **`terminationGracePeriodSeconds`**: Default ist 30s. Das ist genug für den PHP-basierten Lock-Release (< 1s). Falls du längere Init-Scripts hast, könnte man den Wert erhöhen — brauchen wir aber vmtl. nicht.
2. **FOWNER droppen**: Der aktuelle `containerSecurityContextBase` hat CHOWN+FOWNER+DAC_OVERRIDE. FOWNER ist für `chown -R` nicht nötig (das braucht nur CHOWN + DAC_OVERRIDE für Traversal). Spart eine Capability und eine PodSecurity-Warning weniger.

### Checklist Summary
**Total Steps**: 4 Phasen × 2-4 Steps = **12 trackable items**
**Estimated Duration**: ~30-45 min
**Risk Level**: Low — Architektur bleibt gleich, nur Root-Scope wird minimiert + Trap hinzugefügt
