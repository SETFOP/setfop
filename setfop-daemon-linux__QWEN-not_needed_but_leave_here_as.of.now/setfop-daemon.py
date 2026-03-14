#!/usr/bin/env python3
# =============================================================================
#  setfop-daemon — SET File Owner Permission Daemon
#  Part of the SETFOP project: https://github.com/SETFOP/setfop
#
#  Watches file permission/ownership changes in configured paths and logs
#  any drift against a known-good baseline snapshot (.setfop file).
#
#  Author : SETFOP Project
#  License: MIT
# =============================================================================

VERSION = "1.1"

# ── Stdlib imports ────────────────────────────────────────────────────────────
#!/usr/bin/env python3
# =============================================================================
#  setfop-daemon.py - SETFOP File Integrity Monitoring Daemon
#  Version: 2.0.0
# =============================================================================

import os
import sys
import json
import time
import signal
import logging
import subprocess
import hashlib
from datetime import datetime
from pathlib import Path
from logging.handlers import RotatingFileHandler

try:
    import inotify_simple
except ImportError:
    print("ERROR: inotify_simple package not installed. Install with: pip3 install inotify_simple")
    sys.exit(1)

# ── Version ──────────────────────────────────────────────────────────────────
VERSION = "2.0.0"

# ── Default Paths ─────────────────────────────────────────────────────────────
CONFIG_PATH = "/etc/setfop/setfop-daemon.config"
PID_FILE = "/var/run/setfop.pid"
LOG_DIR = "/var/log/setfop"
LIB_DIR = "/var/lib/setfop"

# ── Global Variables ──────────────────────────────────────────────────────────
running = True
baseline = {}
config = {}
logger = None
notifier = None
watch_descriptors = {}

# ── Signal Handlers ───────────────────────────────────────────────────────────
def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    global running
    logger.info(f"Received signal {signum}, shutting down...")
    running = False

# ── Configuration ─────────────────────────────────────────────────────────────
def load_config():
    """Load configuration from JSON file"""
    global config
    
    default_config = {
        "watch_paths": ["/opt"],
        "baseline_path": "/var/lib/setfop/baseline.setfop",
        "log_path": "/var/log/setfop/drift.log",
        "log_max_bytes": 10485760,
        "log_backup_count": 5,
        "snapshot_interval": 3600
    }
    
    try:
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, 'r') as f:
                config = json.load(f)
                # Merge with defaults for any missing keys
                for key, value in default_config.items():
                    if key not in config:
                        config[key] = value
        else:
            config = default_config
    except Exception as e:
        print(f"WARNING: Could not load config: {e}. Using defaults.")
        config = default_config
    
    return config

# ── Logging Setup ─────────────────────────────────────────────────────────────
def setup_logging():
    """Configure rotating file logger"""
    global logger
    
    log_path = config.get("log_path", "/var/log/setfop/drift.log")
    log_max_bytes = config.get("log_max_bytes", 10485760)
    log_backup_count = config.get("log_backup_count", 5)
    
    # Ensure log directory exists
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    
    logger = logging.getLogger('setfop')
    logger.setLevel(logging.INFO)
    
    # Rotating file handler
    handler = RotatingFileHandler(
        log_path,
        maxBytes=log_max_bytes,
        backupCount=log_backup_count
    )
    
    formatter = logging.Formatter(
        '%(asctime)s | %(levelname)-8s | %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    
    return logger

# ── Extended Attributes ───────────────────────────────────────────────────────
def get_file_attributes(filepath):
    """
    Get extended file attributes using lsattr command
    Returns attribute string like '----e-----------' or None on error
    """
    try:
        result = subprocess.run(
            ['lsattr', filepath],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            # lsattr output: "----e----------- ./filename"
            parts = result.stdout.strip().split()
            if len(parts) >= 1:
                return parts[0]
    except (subprocess.TimeoutExpired, FileNotFoundError, Exception):
        pass
    
    return None

def get_file_stat_info(filepath):
    """
    Get comprehensive file information including:
    - Standard permissions (mode, uid, gid)
    - Timestamps (mtime, ctime, atime)
    - Extended attributes (via lsattr)
    - File size
    - Inode number
    """
    try:
        stat_info = os.stat(filepath, follow_symlinks=False)
        attrs = get_file_attributes(filepath)
        
        return {
            'mode': oct(stat_info.st_mode)[-4:],  # e.g., '0644'
            'uid': stat_info.st_uid,
            'gid': stat_info.st_gid,
            'size': stat_info.st_size,
            'mtime': stat_info.st_mtime,
            'ctime': stat_info.st_ctime,
            'atime': stat_info.st_atime,
            'inode': stat_info.st_ino,
            'nlink': stat_info.st_nlink,
            'attrs': attrs  # Extended attributes from lsattr
        }
    except (OSError, FileNotFoundError) as e:
        return None

# ── Baseline Management ───────────────────────────────────────────────────────
def load_baseline():
    """Load existing baseline from disk"""
    global baseline
    
    baseline_path = config.get("baseline_path", "/var/lib/setfop/baseline.setfop")
    
    try:
        if os.path.exists(baseline_path):
            with open(baseline_path, 'r') as f:
                baseline = json.load(f)
            logger.info(f"Loaded baseline with {len(baseline)} entries")
        else:
            baseline = {}
            logger.info("No existing baseline found, will create new one")
    except Exception as e:
        logger.error(f"Error loading baseline: {e}")
        baseline = {}
    
    return baseline

def save_baseline():
    """Save current baseline to disk"""
    baseline_path = config.get("baseline_path", "/var/lib/setfop/baseline.setfop")
    
    try:
        # Ensure directory exists
        os.makedirs(os.path.dirname(baseline_path), exist_ok=True)
        
        # Write to temp file first, then rename (atomic operation)
        temp_path = baseline_path + '.tmp'
        with open(temp_path, 'w') as f:
            json.dump(baseline, f, indent=2)
        
        os.rename(temp_path, baseline_path)
        logger.debug(f"Baseline saved: {len(baseline)} entries")
    except Exception as e:
        logger.error(f"Error saving baseline: {e}")

def create_baseline_snapshot():
    """Create or update baseline for all watched paths"""
    global baseline
    
    watch_paths = config.get("watch_paths", [])
    files_processed = 0
    
    logger.info("Creating baseline snapshot...")
    
    for watch_path in watch_paths:
        if not os.path.exists(watch_path):
            logger.warning(f"Watch path does not exist: {watch_path}")
            continue
        
        try:
            for root, dirs, files in os.walk(watch_path):
                # Skip virtual filesystems
                dirs[:] = [d for d in dirs if d not in ['proc', 'sys', 'dev', 'run']]
                
                for filename in files:
                    filepath = os.path.join(root, filename)
                    
                    try:
                        # Skip symlinks
                        if os.path.islink(filepath):
                            continue
                        
                        stat_info = get_file_stat_info(filepath)
                        if stat_info:
                            baseline[filepath] = stat_info
                            files_processed += 1
                            
                            # Progress indicator
                            if files_processed % 1000 == 0:
                                logger.info(f"  Processed {files_processed} files...")
                    
                    except (PermissionError, FileNotFoundError, OSError):
                        # Skip files we can't access
                        continue
        
        except PermissionError:
            logger.warning(f"Permission denied accessing: {watch_path}")
    
    save_baseline()
    logger.info(f"Baseline snapshot complete: {files_processed} files indexed")
    return files_processed

# ── Change Detection ──────────────────────────────────────────────────────────
def detect_changes(filepath, event_mask):
    """
    Detect and log changes to a file
    Returns dict with change details or None if no changes
    """
    changes = {
        'filepath': filepath,
        'timestamp': datetime.now().isoformat(),
        'events': [],
        'details': {}
    }
    
    # Map inotify flags to human-readable events
    event_map = {
        inotify_simple.Flags.CREATE: 'FILE_ADDED',
        inotify_simple.Flags.DELETE: 'FILE_REMOVED',
        inotify_simple.Flags.MODIFY: 'FILE_MODIFIED',
        inotify_simple.Flags.ATTRIB: 'METADATA_CHANGED',
        inotify_simple.Flags.PERMISSION: 'PERMISSION_ACCESS',
        inotify_simple.Flags.MOVED_FROM: 'FILE_MOVED_AWAY',
        inotify_simple.Flags.MOVED_TO: 'FILE_MOVED_HERE',
    }
    
    # Convert event_mask to readable events
    for flag, event_name in event_map.items():
        if event_mask & flag:
            changes['events'].append(event_name)
    
    # Get current file state
    current_stat = get_file_stat_info(filepath)
    
    # Check if file exists in baseline
    if filepath in baseline:
        old_stat = baseline[filepath]
        
        # Detect specific changes
        if current_stat:
            # Permission changes
            if old_stat.get('mode') != current_stat.get('mode'):
                changes['details']['mode_change'] = {
                    'old': old_stat.get('mode'),
                    'new': current_stat.get('mode')
                }
            
            # Ownership changes
            if old_stat.get('uid') != current_stat.get('uid') or \
               old_stat.get('gid') != current_stat.get('gid'):
                changes['details']['ownership_change'] = {
                    'old_uid': old_stat.get('uid'),
                    'old_gid': old_stat.get('gid'),
                    'new_uid': current_stat.get('uid'),
                    'new_gid': current_stat.get('gid')
                }
            
            # Extended attribute changes (chattr)
            if old_stat.get('attrs') != current_stat.get('attrs'):
                changes['details']['attrs_change'] = {
                    'old': old_stat.get('attrs'),
                    'new': current_stat.get('attrs'),
                    'description': describe_attr_change(
                        old_stat.get('attrs'),
                        current_stat.get('attrs')
                    )
                }
            
            # Size changes
            if old_stat.get('size') != current_stat.get('size'):
                changes['details']['size_change'] = {
                    'old': old_stat.get('size'),
                    'new': current_stat.get('size')
                }
            
            # Update baseline
            baseline[filepath] = current_stat
        else:
            # File was deleted
            changes['details']['deleted'] = True
            if filepath in baseline:
                del baseline[filepath]
    else:
        # New file
        if current_stat:
            changes['details']['new_file'] = True
            baseline[filepath] = current_stat
    
    # Only return if there are actual changes
    if changes['details']:
        return changes
    
    return None

def describe_attr_change(old_attrs, new_attrs):
    """
    Provide human-readable description of attribute changes
    """
    if not old_attrs or not new_attrs:
        return "Extended attributes changed"
    
    changes = []
    
    # Common attribute flags
    attr_flags = {
        0: ('A', 'No atime updates'),
        1: ('S', 'Synchronous updates'),
        2: ('a', 'Append only'),
        3: ('c', 'Compressed'),
        4: ('d', 'No dump'),
        5: ('D', 'Synchronous directory updates'),
        6: ('e', 'Extent format'),
        7: ('i', 'Immutable'),
        8: ('I', 'Indexed directory'),
        9: ('j', 'Data journalling'),
        10: ('s', 'Secure deletion'),
        11: ('t', 'No tail-merging'),
        12: ('T', 'Top of directory hierarchy'),
        13: ('u', 'Undeletable'),
    }
    
    for i, (flag, desc) in attr_flags.items():
        if i < len(old_attrs) and i < len(new_attrs):
            old_flag = old_attrs[i]
            new_flag = new_attrs[i]
            
            if old_flag != new_flag:
                if new_flag == flag:
                    changes.append(f"Added: {desc} ({flag})")
                elif old_flag == flag:
                    changes.append(f"Removed: {desc} ({flag})")
                else:
                    changes.append(f"Changed at position {i}: {old_flag} → {new_flag}")
    
    if changes:
        return "; ".join(changes)
    else:
        return "Extended attributes modified"

def log_change(change):
    """Log detected changes to file and console"""
    filepath = change['filepath']
    events = ', '.join(change['events'])
    details = change['details']
    
    # Build log message
    log_parts = [events, filepath]
    
    if 'mode_change' in details:
        mode = details['mode_change']
        log_parts.append(f"mode: {mode['old']} → {mode['new']}")
    
    if 'ownership_change' in details:
        owner = details['ownership_change']
        log_parts.append(f"uid: {owner['old_uid']}→{owner['new_uid']} gid: {owner['old_gid']}→{owner['new_gid']}")
    
    if 'attrs_change' in details:
        attrs = details['attrs_change']
        log_parts.append(f"attrs: {attrs['old']} → {attrs['new']} ({attrs['description']})")
    
    if 'size_change' in details:
        size = details['size_change']
        log_parts.append(f"size: {size['old']}→{size['new']}")
    
    if 'new_file' in details:
        log_parts.append("NEW FILE")
    
    if 'deleted' in details:
        log_parts.append("DELETED")
    
    log_message = ' | '.join(log_parts)
    
    # Log with appropriate level
    if 'FILE_ADDED' in events or 'FILE_REMOVED' in events:
        logger.warning(log_message)
    elif 'attrs_change' in details or 'mode_change' in details:
        logger.warning(log_message)
    else:
        logger.info(log_message)

# ── inotify Monitoring ────────────────────────────────────────────────────────
def setup_watches():
    """Setup inotify watches for all configured paths"""
    global notifier, watch_descriptors
    
    notifier = inotify_simple.INotify()
    
    # Flags to watch for
    flags = (
        inotify_simple.Flags.CREATE |
        inotify_simple.Flags.DELETE |
        inotify_simple.Flags.MODIFY |
        inotify_simple.Flags.ATTRIB |        # Critical for chattr detection
        inotify_simple.Flags.PERMISSION |
        inotify_simple.Flags.MOVED_FROM |
        inotify_simple.Flags.MOVED_TO |
        inotify_simple.Flags.DELETE_SELF |
        inotify_simple.Flags.MOVE_SELF
    )
    
    watch_paths = config.get("watch_paths", [])
    
    for path in watch_paths:
        if os.path.exists(path):
            try:
                wd = notifier.add_watch(path, flags, recursive=True)
                watch_descriptors[wd] = path
                logger.info(f"Watching: {path} (wd={wd})")
            except Exception as e:
                logger.error(f"Failed to watch {path}: {e}")
        else:
            logger.warning(f"Path does not exist: {path}")
    
    return len(watch_descriptors)

def process_events():
    """Process inotify events"""
    global notifier
    
    if not notifier:
        return
    
    try:
        events = notifier.read(timeout=1000)  # 1 second timeout
        
        for event in events:
            # Get the full filepath
            path = watch_descriptors.get(event.wd, '')
            filepath = os.path.join(path, event.name) if event.name else path
            
            # Detect and log changes
            change = detect_changes(filepath, event.mask)
            
            if change:
                log_change(change)
                # Save baseline periodically
                save_baseline()
    
    except Exception as e:
        logger.error(f"Error processing events: {e}")

# ── Periodic Snapshot ─────────────────────────────────────────────────────────
def periodic_snapshot():
    """Periodically verify files against baseline"""
    interval = config.get("snapshot_interval", 3600)
    
    if interval <= 0:
        return  # Disabled
    
    logger.info(f"Starting periodic snapshot (interval: {interval}s)")
    
    last_snapshot = time.time()
    
    while running:
        time.sleep(1)
        
        now = time.time()
        if now - last_snapshot >= interval:
            logger.info("Performing periodic integrity check...")
            
            # Check all files in baseline
            for filepath in list(baseline.keys()):
                if os.path.exists(filepath):
                    current_stat = get_file_stat_info(filepath)
                    if current_stat:
                        old_stat = baseline[filepath]
                        
                        # Check for changes not caught by inotify
                        if old_stat.get('attrs') != current_stat.get('attrs'):
                            change = {
                                'filepath': filepath,
                                'timestamp': datetime.now().isoformat(),
                                'events': ['PERIODIC_CHECK'],
                                'details': {
                                    'attrs_change': {
                                        'old': old_stat.get('attrs'),
                                        'new': current_stat.get('attrs'),
                                        'description': describe_attr_change(
                                            old_stat.get('attrs'),
                                            current_stat.get('attrs')
                                        )
                                    }
                                }
                            }
                            log_change(change)
                            baseline[filepath] = current_stat
                    else:
                        # File exists but can't stat it
                        logger.warning(f"Cannot stat file: {filepath}")
                else:
                    # File in baseline no longer exists
                    change = {
                        'filepath': filepath,
                        'timestamp': datetime.now().isoformat(),
                        'events': ['PERIODIC_CHECK'],
                        'details': {'deleted': True}
                    }
                    log_change(change)
                    del baseline[filepath]
            
            save_baseline()
            last_snapshot = now

# ── Main Functions ────────────────────────────────────────────────────────────
def daemonize():
    """Daemonize the process"""
    # Write PID file
    with open(PID_FILE, 'w') as f:
        f.write(str(os.getpid()))
    
    logger.info(f"Daemonizing - further logs in drift.log")
    logger.info(f"PID {os.getpid()} written to {PID_FILE}")

def main():
    """Main entry point"""
    global running
    
    print(f"\n{'='*60}")
    print(f"  SETFOP Daemon v{VERSION}")
    print(f"  File Integrity Monitoring System")
    print(f"{'='*60}\n")
    
    # Load configuration
    load_config()
    
    # Setup logging
    setup_logging()
    
    # Setup signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    # Daemonize
    daemonize()
    
    # Load or create baseline
    load_baseline()
    
    # Initial baseline if empty
    if not baseline:
        create_baseline_snapshot()
    
    # Setup inotify watches
    num_watches = setup_watches()
    logger.info(f"inotify watching {num_watches} director(ies)")
    
    # Start scheduler loop
    logger.info("Scheduler loop started")
    
    try:
        while running:
            process_events()
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt")
    finally:
        # Cleanup
        logger.info("Shutting down...")
        save_baseline()
        
        if notifier:
            notifier.close()
        
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
        
        logger.info("SETFOP daemon stopped")

if __name__ == "__main__":
    main()
