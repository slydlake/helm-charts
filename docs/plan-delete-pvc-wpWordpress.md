## Plan: PVC `wp-wordpress` löschen ✅

Kurzfassung: Das PVC `wp-wordpress` steckt im Status `Terminating`, weil noch ein Pod (`wp-pvc-debug`) die PVC nutzt. Lösche zuerst den Pod, warte auf Freigabe und lösche dann das PVC. Wenn das PVC trotzdem hängen bleibt, entferne vorsichtig die Finalizer (Datenverlust möglich).

### Überblick & wichtige Hinweise 🔧
- **StorageClass:** `longhorn` (Longhorn-Volume als Backend)
- **PV:** `pvc-1ad80c56-5de6-4b09-8f2f-9733e963c26f` (ReclaimPolicy: Delete)
- **Blocker:** `kubernetes.io/pvc-protection` Finalizer + laufender Pod
- **Risiko:** Mittel — Daten gehen verloren, wenn Volume entfernt wird. Erstelle vorher ggf. ein Backup/Snapshot in Longhorn.

---

### Schritte (konkret & ausführbar) ✅

Phase 1 — Status prüfen
1. [ ] Prüfe die PVC-Details (Used By, Finalizers, Events)

```bash
kubectl describe pvc wp-wordpress
# Erwartet: "Used By:" listet keine Pods, sonst Pod(s) zuerst löschen
```

2. [ ] Prüfe das zugeordnete PV

```bash
kubectl get pv pvc-1ad80c56-5de6-4b09-8f2f-9733e963c26f -o yaml
# Erwartet: schauen auf .spec.claimRef, .metadata.finalizers, .spec.persistentVolumeReclaimPolicy
```

Phase 2 — Sicheres Löschen (empfohlen) 🔄
3. [ ] Pod(s) löschen, die das PVC verwenden

```bash
kubectl delete pod wp-pvc-debug
# Validation: kubectl get pod wp-pvc-debug -> NotFound
```

4. [ ] PVC löschen

```bash
kubectl delete pvc wp-wordpress
# Validation: kubectl get pvc wp-wordpress -> NotFound
```

Phase 3 — Falls PVC weiterhin "Terminating" bleibt (stuck) ⚠️
5. [ ] Finalizer des PVC entfernen (nur wenn keine Pods mehr dran hängen)

```bash
# Zeige aktuelle Finalizer
kubectl get pvc wp-wordpress -o json | jq '.metadata.finalizers'
# Entfernen der Finalizer (force) — bewusstes, destruktives Vorgehen
kubectl patch pvc wp-wordpress -p '{"metadata":{"finalizers":[]}}' --type=merge
# Validation: kubectl get pvc wp-wordpress -o json | jq '.metadata.finalizers' -> null/[]
```

6. [ ] Falls das PV ebenfalls hängen bleibt, Finalizer entfernen & PV löschen

```bash
kubectl patch pv pvc-1ad80c56-5de6-4b09-8f2f-9733e963c26f -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete pv pvc-1ad80c56-5de6-4b09-8f2f-9733e963c26f
```

Phase 4 — Longhorn Backend prüfen (falls Volume weiter existiert) 🗂️
7. [ ] Longhorn-Volume in Longhorn UI oder via CR löschen

```bash
# Namespace prüfen (häufig longhorn-system)
kubectl get ns | grep -i longhorn
# Falls vorhanden, suche Volume
kubectl -n longhorn-system get volumes.longhorn.io | grep pvc-1ad80c56
# Löschen in Longhorn UI oder:
kubectl -n longhorn-system delete volumes.longhorn.io pvc-1ad80c56-5de6-4b09-8f2f-9733e963c26f
```

---

### Validierung (letzte Prüfung) ✅
- `kubectl get pvc,pv | grep pvc-1ad80c56` → sollte nichts mehr ausgeben
- `kubectl get pods --all-namespaces -o wide | grep wp-wordpress` → keine Pods mit diesem Claim

### Risiken & Empfehlungen 💡
- Entfernen von Finalizern ist destruktiv und kann zu Datenverlust führen. Wenn die Daten wichtig sind: erst Snapshot in Longhorn erstellen.
- Wenn du unsicher bist, gib mir kurz Bescheid; ich kann dir die exakten Befehle schrittweise nennen, damit du sie interaktiv ausführst.

---

**Geschätzte Dauer:** 5–15 Minuten (je nach Longhorn/Pod Zustand)
**Risikolevel:** Mittel — prüfe Backups vor dem Entfernen von Finalizern

---

Wenn du willst, führe ich dir die nächsten Shell-Befehle vor, ohne sie hier auszuführen — sag mir einfach "jetzt löschen" und ob ich zuerst den Pod entfernen soll oder ob du ein Backup machen willst.