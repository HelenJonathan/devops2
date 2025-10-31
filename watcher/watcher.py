SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")

import time
import re
import os
from datetime import datetime, timedelta

def tail_logs():
    log_path = "/var/log/nginx/access.log"
    print("👀 Log watcher started...")

    while not os.path.exists(log_path):
        time.sleep(1)

    with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
        f.readlines()
        while True:
            line = f.readline()
            if not line:
                time.sleep(1)
                continue
            process_line(line)


            now = datetime.now()
            total.append(now)
            if parse_line(line):
                errors.append(now)


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
