import os
import json
import time
import requests
from collections import deque

LOG_PATH = "/var/log/nginx/access.log"
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
ERROR_RATE_THRESHOLD = float(os.getenv("ERROR_RATE_THRESHOLD", 2))
WINDOW_SIZE = int(os.getenv("WINDOW_SIZE", 200))
ALERT_COOLDOWN_SEC = int(os.getenv("ALERT_COOLDOWN_SEC", 300))

last_alert_time = 0
last_pool = None
window = deque(maxlen=WINDOW_SIZE)

def post_to_slack(message):
    if not SLACK_WEBHOOK_URL:
        print("⚠️ No Slack webhook set. Skipping alert.")
        return
    requests.post(SLACK_WEBHOOK_URL, json={"text": message})

def tail_logs():
    global last_pool, last_alert_time
    with open(LOG_PATH, "r") as f:
        f.seek(0, 2)
        while True:
            line = f.readline()
            if not line:
                time.sleep(0.5)
                continue

            try:
                data = json.loads(line.strip())
                pool = data.get("x_app_pool")
                status = int(data.get("status", 0))
                window.append(status)

                # Detect failover
                if last_pool and pool != last_pool:
                    now = time.time()
                    if now - last_alert_time > ALERT_COOLDOWN_SEC:
                        post_to_slack(f"⚠️ Failover detected: {last_pool} → {pool}")
                        last_alert_time = now
                last_pool = pool

                # Error-rate alert
                if len(window) >= WINDOW_SIZE:
                    errors = sum(1 for s in window if 500 <= s < 600)
                    rate = (errors / len(window)) * 100
                    if rate > ERROR_RATE_THRESHOLD:
                        now = time.time()
                        if now - last_alert_time > ALERT_COOLDOWN_SEC:
                            post_to_slack(f"🚨 High error rate: {rate:.2f}% (> {ERROR_RATE_THRESHOLD}%)")
                            last_alert_time = now

            except json.JSONDecodeError:
                continue

if __name__ == "__main__":
    print("👀 Log watcher started...")
    tail_logs()
