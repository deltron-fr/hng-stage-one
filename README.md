# Automated Deployment Script 

This Bash script automates the end-to-end deployment of a Dockerized application onto a remote server via SSH.  
It handles repository cloning, Docker installation, app deployment, and Nginx configuration.

---

## Features

- Verifies connectivity (ping + SSH)
- Installs Docker and Nginx automatically
- Builds and deploys the application using Docker or Docker Compose
- Configures Nginx reverse proxy
- Validates running containers and service response
- Centralized logging and error trapping

---

## Usage

```bash
chmod +x deploy.sh
./deploy.sh
```

**Example:**

```bash

Enter GitHub repo URL: <github_url>
Enter GitHub Personal Access Token: github_pat_12...
Enter remote server username: user1
Enter remote server IP: <server_ip>
Enter branch name (default: main):
Enter path to SSH private key: <private_key_file>
Enter app port: 8000
```

---

## Script Workflow

1. **Input Passing** — Ensures all inputs are provided.
2. **Repository Handling**
   - Clones repo if not present.
   - Pulls latest changes if already cloned.
3. **Connectivity Test** — Pings and SSHs into the remote host.
4. **Remote Setup**
   - Installs Docker and Nginx.
   - Verifies installation.
5. **App Deployment**
   - Syncs code to remote.
   - Runs `docker compose up -d` if `docker-compose.yml` exists.
   - Otherwise builds image manually and runs container.
6. **Nginx Configuration**
   - Creates `/etc/nginx/sites-available/app`
   - Enables it in `sites-enabled`
   - Restarts Nginx.
7. **Validation**
   - Lists running containers.
   - Performs health check on app endpoint.
8. **Cleanup (optional)**
   - Stops containers and removes Nginx config:
     ```bash
     ./deploy.sh --cleanup
     ```

---

## Logging and Error Handling

- All output is logged to `deploy_YYYYMMDD_HHMMSS.log`.
---

## Cleanup Command

To completely remove the deployment (containers, repo, Nginx config):

```bash
./deploy.sh --cleanup
```

---

## Requirements

- Bash 4.0+
- SSH access to the remote server
- Ubuntu 20.04+ (or similar Debian-based OS)
- Git installed locally

