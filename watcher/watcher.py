import time
import re
import os
from datetime import datetime, timedelta

LOG_FILE = "/var/log/nginx/access.log"
ERROR_RATE_THRESHOLD = float(os.getenv("ERROR_RATE_THRESHOLD", 0.3))  # 30%
WINDOW_SIZE = int(os.getenv("WINDOW_SIZE", 60))  # seconds
ALERT_COOLDOWN_SEC = int(os.getenv("ALERT_COOLDOWN_SEC", 60))
last_alert_time = datetime.min

print("👀 Log watcher started... monitoring nginx logs")

def parse_line(line):
    """Check if line is an error (status 4xx or 5xx)."""
    match = re.search(r'"\s(\d{3})\s', line)
    if match:
        code = int(match.group(1))
        return code >= 400
    return False

def monitor_logs():
    global last_alert_time
    errors, total = [], []
    start_time = datetime.now()

    with open(LOG_FILE, "r", errors="ignore") as f:
        f.seek(0, os.SEEK_END)  # Go to end initially
        while True:
            line = f.readline()
            if not line:
                time.sleep(1)
                continue

            now = datetime.now()
            total.append(now)
            if parse_line(line):
                errors.append(now)

            # remove entries older than WINDOW_SIZE
            total = [t for t in total if now - t < timedelta(seconds=WINDOW_SIZE)]
            errors = [t for t in errors if now - t < timedelta(seconds=WINDOW_SIZE)]

            if total:
                rate = len(errors) / len(total)
                if rate > ERROR_RATE_THRESHOLD and (now - last_alert_time).total_seconds() > ALERT_COOLDOWN_SEC:
                    print(f"🚨 ALERT: High error rate detected ({rate*100:.1f}%) at {now.strftime('%H:%M:%S')}")
                    last_alert_time = now
                else:
                    print(f"✅ OK: Error rate {rate*100:.1f}% at {now.strftime('%H:%M:%S')}")

if __name__ == "__main__":
    try:
        monitor_logs()
    except KeyboardInterrupt:
        print("👋 Stopped watcher.")
