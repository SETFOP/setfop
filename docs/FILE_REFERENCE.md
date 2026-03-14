# SETFOP File Reference

## Source Files (GitHub)
| File | Purpose |
|------|---------|
| `setfop-daemon.py` | Main Python daemon — monitors files, detects changes |
| `setfop-daemon.config` | Default JSON config template |
| `setfop-daemon.service` | Systemd unit file template |
| `VERSION` | Semantic version string (e.g., `2.0.0`) |

## Installed Files (Server)
| Path | Purpose |
|------|---------|
| `/usr/local/bin/setfop-daemon` | Running daemon binary |
| `/etc/setfop/setfop-daemon.config` | Active configuration (edit to customize) |
| `/var/lib/setfop/baseline.setfop` | File integrity snapshot (auto-managed) |
| `/var/log/setfop/drift.log` | Change detection logs |
| `/etc/systemd/system/setfop-daemon.service` | Service definition |
| `/var/run/setfop.pid` | Process ID file (auto-managed) |
