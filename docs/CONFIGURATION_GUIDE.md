# Configuration Guide

## Edit `/etc/setfop/setfop-daemon.config`

```json
{
  "watch_paths": ["/etc", "/usr/bin", "/home"],
  "baseline_path": "/var/lib/setfop/baseline.setfop",
  "log_path": "/var/log/setfop/drift.log",
  "log_max_bytes": 10485760,
  "log_backup_count": 5,
  "snapshot_interval": 3600
}