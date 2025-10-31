import os
import time
import re
import requests
from datetime import datetime, timedelta

# Slack webhook setup
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")

# Configuration
LOG_PATH = "/var/log/nginx/access.log"
WINDOW_SIZE = 60               # seconds
ERROR_RATE_THRESHOLD = 0.2     # 20% errors
ALERT_COOLDOWN_SEC = 60        # seconds

# Initialize trackers
total = []
errors = []
last_alert_time = datetime.min

# Regex to detect error lines (HTTP 5xx or 4xx)
ERROR_PATTERN = re.compile(r'HTTP/[0-9\.]+" (4\d{2}|5\d{2})')

def send_slack_alert(message: str):
    """Send alert message to Slack via webhook"""
    if not SLACK_WEBHOOK_URL:
        print("⚠️ No Slack webhook URL found. Set SLACK_WEBHOOK_URL in environment.")
        return

    try:
        response = requests.post(SLACK_WEBHOOK_URL, json={"text": message})
        if response.status_code != 200:
            print(f"⚠️ Failed to send Slack message: {response.text}")
    except Exception as e:
        print(f"❌ Slack send error: {e}")

def monitor_logs():
    """Continuously monitor the Nginx access log for high error rates"""
    global last_alert_time

    print("👀 Log watcher started...")

    while not os.path.exists(LOG_PATH):
        print(f"⏳ Waiting for {LOG_PATH} to exist...")
        time.sleep(2)

    with open(LOG_PATH, "r", encoding="utf-8", errors="ignore") as f:
        f.seek(0, os.SEEK_END)  # Skip old logs
        while True:
            line = f.readline()
            if not line:
                time.sleep(1)
                continue

            now = datetime.now()
            total.append(now)

            if ERROR_PATTERN.search(line):
                errors.append(now)

            # Keep only recent entries in the window
            total[:] = [t for t in total if now - t < timedelta(seconds=WINDOW_SIZE)]
            errors[:] = [t for t in errors if now - t < timedelta(seconds=WINDOW_SIZE)]

            if total:
                rate = len(errors) / len(total)
                if rate > ERROR_RATE_THRESHOLD:
                    if (now - last_alert_time).total_seconds() > ALERT_COOLDOWN_SEC:
                        message = f"🚨 ALERT: High error rate detected! ({rate*100:.1f}%) at {now.strftime('%H:%M:%S')}"
                        print(message)
                        send_slack_alert(message)
                        last_alert_time = now
                else:
                    print(f"✅ OK: Error rate {rate*100:.1f}% at {now.strftime('%H:%M:%S')}")

if __name__ == "__main__":
    try:
        monitor_logs()
    except KeyboardInterrupt:
        print("👋 Stopped watcher.")
