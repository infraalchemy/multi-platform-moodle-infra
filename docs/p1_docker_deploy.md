# Phase 1 Deployment Runbook: Docker Compose Deployment on GCP VM

This runbook documents the deployment, validation, and persistence testing of a containerized Moodle environment using Docker Compose on a Google Cloud Platform (GCP) Compute Engine virtual machine.

*Note: The database table prefix (`mdl_`) must remain identical across all deployment phases and upgrades. Changing this value causes Moodle to drop its mapping to existing tables, generating an empty schema and resulting in total application data loss.*

---

# Prerequisites

This deployment assumes a clean Linux Compute Engine VM has already been provisioned.
The VM provides the host environment for the Docker Compose application stack.

Required software on the host VM:
- Docker Engine
- Docker Compose CLI
- Git

Verify installations:
```bash
docker --version
docker-compose version
git --version
```

---

# Deployment Workflow

The deployment process follows this sequence:

1. Configure Docker runtime permissions
2. Clone infrastructure repository and prepare environment configuration
3. Build custom application container images
4. Launch isolated application services
5. Validate container health and internal networking
6. Complete Moodle web installation wizard configuration
7. Verify database initialization
8. Execute persistence validation after container recreation
9. Stop or remove deployment resources when required.

---

## Connect to the Host Virtual Machine

Connect directly to your running cloud instance using the browser console interface:
1. Open your web browser to the **GCP Compute Engine Console**.
2. Click the blue **SSH** button link on the far right of your VM's row.

Alternatively, connect directly via your local terminal command line:
```bash
gcloud compute ssh <YOUR_VM_NAME> --zone=<YOUR_VM_ZONE>
```

---

## Configure Docker Permissions

Enable Docker and configure the local user for non-root Docker execution:
```bash
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

Verify Docker commands execute without elevated privileges:
```bash
docker ps
```

Expected result:
```text
CONTAINER ID   IMAGE   COMMAND   CREATED   STATUS   PORTS   NAMES
```

---

## Application Deployment

Clone the project repository:
```bash
git clone <your-repository-url>
cd multi-platform-moodle-infra/docker
```

Verify the Docker deployment structure:
```bash
ls -la
```

Expected:
```text
docker-compose.yml
nginx/
php/
mysql/
```

---

## Configure Environment Variables

The `.env` file contains database credentials and sensitive configuration values. It is excluded from source control through `.gitignore`.
The `.env` file must be created in the same directory as `docker-compose.yml`.
```bash
nano .env
```

Populate the required variables:
```text
MYSQL_ROOT_PASSWORD=your_secure_root_password
MYSQL_DATABASE=moodle
MYSQL_USER=moodleuser
MYSQL_PASSWORD=your_secure_moodle_password
```

Verify the Docker Compose configuration:
```bash
docker-compose config
```

*Note: The generated configuration should display resolved service definitions without missing variables.*

---

## Build Application Images

Build the custom application images:
```bash
docker-compose build --no-cache
```

Expected output:
```text
Creating docker_mysql_1   ... done
Creating docker_php-fpm_1 ... done
Creating docker_nginx_1   ... done
```

Start the application stack in detached mode:
```bash
docker-compose up -d
```

Expected deployment output:
```text
[+] Running 5/5
 ✔ Network docker_web_network Created
 ✔ Volume docker_moodle_code Created
 ✔ Container docker-php-fpm-1 Started
 ✔ Container docker-mysql-1 Started
 ✔ Container docker-nginx-1 Started
```

---

# Runtime Verification

Verify the application containers are running:
```bash
docker ps
```

Expected services:
```text
docker-nginx-1
docker-php-fpm-1
docker-mysql-1
```

Verify the container networking layer:
```bash
docker network inspect docker_web_network
```

*Note: Confirm that the containers are connected to the expected application network and can communicate through Docker service discovery.*

---

## HTTP Endpoint Verification

Validate that the Nginx reverse proxy is responding locally from the VM:
```bash
curl -I http://localhost
```

Expected response:
```text
HTTP/1.1 302 Found
```

Retrieve the external VM address for browser access:
```bash
curl -4 ifconfig.me
```

Verify that a Google Cloud firewall rule allows inbound HTTP (TCP port 80) to the target VM instance.
- **TCP Port:** `80`
- **Source:** Required client access range
- **Target:** VM instance

Open the Moodle deployment in your browser:
```text
http://<YOUR_VM_EXTERNAL_IP>
```

---

# Moodle Web Installation

Complete the Moodle installation wizard using the following sequence:

**Choose Language**
- Select the installation language.

**Confirm Paths**
- Verify the web address and Moodle data directory.

**Choose Database Driver**
- Select the database type:
  - MySQL / MariaDB

**Database Settings**
- Enter the database configuration:

| Setting | Value |
| :--- | :--- |
| **Web Address** | `http://<YOUR_VM_EXTERNAL_IP>` |
| **Moodle Directory** | `/var/www/html` |
| **Moodle Data Directory** | `/var/www/moodledata` |
| **Database Type** | `MySQL` |
| **Database Host** | `mysql` |
| **Database Port** | `3306` |
| **Database Name** | `moodle` |
| **Database User** | `<MYSQL_USER from .env>` |
| **Database Password** | `<MYSQL_PASSWORD from .env>` |
| **Table Prefix** | `mdl_` |

**Copyright Notice**
- Accept the Moodle GPL license agreement.

**Server Checks**
- Review PHP extensions and environment requirements.
- Continue once all required checks pass.

**Installation**
- Allow Moodle to create the database tables and complete application initialization.

**Setup Administrator Account**
- Leave the browser open at this page.
- Complete administrator configuration using Moodle CLI tools inside the PHP-FPM container.

*Notes: Maintain a consistent Moodle database table prefix (mdl_) throughout upgrades. Changing the prefix can create data migration issues and require a time-consuming, potentially risky recovery process.*

---

# Administrator Setup Completion (CLI)

The Moodle administrator account was configured using Moodle's built-in command-line tools inside the running PHP-FPM container.

Identify the running container name for PHP-FPM:
```bash
docker ps
```

Reset the administrator password:
```bash
docker exec -it <php-fpm-name> php /var/www/html/admin/cli/reset_password.php --username=admin
```

Clear Moodle application caches:
```bash
docker exec -it <php-fpm-name> php /var/www/html/admin/cli/purge_caches.php
```

This completes the administrator setup while preserving the existing Moodle installation state.

---

## Storage Validation

Verify the running containers and their assigned names: 
```bash
docker ps
```

Verify that Moodle application files are available inside the PHP-FPM container:
```bash
docker exec <php-fpm-name> ls /var/www/html
```

Verify that Nginx has access to the same shared application volume:
```bash
docker exec <nginx-name> ls /var/www/html
```

Validate write permissions within the Moodle persistent data directory:
```bash
docker exec <php-fpm-name> touch /var/www/moodledata/write_test.txt
```

*Note: Successful completion confirms that the PHP runtime can write to persistent application storage.*

---

## Database Verification

Connect to the MySQL container:
```bash
docker exec -it <mysql-name> mysql -u root -p
```

Verify database creation:
```sql
SHOW DATABASES;
```

Expected output:
```text
+--------------------+
| Database           |
+--------------------+
| information_schema |
| moodle             |
| mysql              |
| performance_schema |
| sys                |
+--------------------+	
5 rows in set (0.02 sec)
```

Verify configured database users:
```sql
SELECT user, host FROM mysql.user;
```

Expected output:
```text
+------------+------+
| user       | host |
+------------+------+
| moodleuser | %    |
| root       | %    |
+------------+------+
```

Exit MySQL:
```sql
exit;
```

---

# Create Moodle Test Data for Persistence Validation

Before recreating the container stack, create application data to verify database and file storage persistence.

## 1. Initial Moodle Setup

* Log into the Moodle web interface as the administrator.
* Complete and save the administrator profile.
* Upload an administrator profile image.
* Create a test course: `Infrastructure Test Course`
* Upload a course image.
* Confirm the profile image and course image render correctly before container recreation.

## 2. Establish Persistence Markers

Verify that the database contains existing application records and record the output count:
```bash
docker exec -it <mysql-name> mysql -u moodleuser -p -e "USE moodle; SELECT COUNT(*) FROM mdl_user;"
```

Create a direct persistence file marker inside the Moodle data volume via the command line:
```bash
docker exec <php-fpm-name> bash -c "echo 'Persistence Token Verification' > /var/www/moodledata/persistence_lock.txt"
```

Verify the marker file exists:
```bash
docker exec <php-fpm-name> cat /var/www/moodledata/persistence_lock.txt
```

Expected output:
```text
Persistence Token Verification
```

## 3. Execute Container Lifecycle Disruption

Stop and remove the running application containers to trigger structural replacement:
```bash
docker-compose down
```
*Note: `docker-compose down` removes containers and networks but preserves named Docker volumes. Persistent application and database storage remain intact.*

Verify that application containers no longer exist:
```bash
docker ps -a
```

Expected result:
```text
No active Moodle application containers
```

Recreate the application stack from persistent volumes:
```bash
docker-compose up -d
```

Verify that new container instances are running cleanly:
```bash
docker ps
```
*Note: The container IDs and creation timestamps will differ from the original deployment, confirming full container replacement.*

## 4. Validate Data Consistency Post-Recovery

Verify the filesystem persistence marker survived container recreation:
```bash
docker exec <php-fpm-name> cat /var/www/moodledata/persistence_lock.txt
```
Expected output:
```text
Persistence Token Verification
```

Verify that the MySQL database volume retained application records:
```bash
docker exec -it <mysql-name> mysql -u moodleuser -p -e "USE moodle; SELECT COUNT(*) FROM mdl_user;"
```
Expected result:
```text
The returned user count matches the value recorded before container recreation.
```

## 5. Application Recovery Validation

Open the Moodle site in your web browser:
```text
http://<YOUR_VM_EXTERNAL_IP>
```

Expected results:
* Moodle login page loads successfully.
* Administrator credentials continue to function.
* Previously created courses remain available.
* Uploaded files remain accessible.

Successful completion confirms absolute decoupling between:
* Container lifecycle
* Application runtime
* Persistent storage
* Database state

## 6. Stop and Purge the Docker Compose Deployment

When retiring the lab, remove the application containers, project networks, named volumes, and local Docker images:
```bash
docker-compose down -v --rmi all
```

Expected Results:
```text
Stopping docker_nginx_1 ... done
Stopping docker_mysql_1 ... done
Stopping docker_php-fpm_1 ... done
Removing docker_nginx_1 ... done
Removing docker_mysql_1 ... done
Removing docker_php-fpm_1 ... done
Removing network docker_web_network
Removing volume docker_mysql_data
Removing volume docker_moodledata
Removing volume docker_moodle_code
Removing image docker_php-fpm
Removing image docker_nginx
Removing image mysql:8.0
```

*Note: The `-v` flag removes persistent volumes, purging all Moodle database records and file assets. The `--rmi all` option deletes base images, forcing a clean rebuild during subsequent deployment runs.*
