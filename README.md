# 🐳 Blue-Green Deployment with Docker and Nginx

This project demonstrates a **Blue-Green Deployment** setup using **Docker Compose** and **Nginx** as a reverse proxy.  
It runs two application environments — **Blue** and **Green** — allowing zero-downtime updates during deployment.

---

## 🚀 Project Overview

- **Blue Environment:** The active version of the app (default).
- **Green Environment:** The new version for testing before switching traffic.
- **Nginx:** Acts as a load balancer / proxy between Blue and Green apps.
- **CI/CD:** Managed via GitHub Actions (`.github/workflows/ci-cd.yml`) with automatic build, test, and deployment.

---

## 🧱 Project Structure

