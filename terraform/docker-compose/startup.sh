#!/bin/bash
set -e
exec > /var/log/startup.log 2>&1

echo "Starting setup..."

# Install dependencies
sudo apt update
sudo apt install -y docker.io docker-compose git

sudo systemctl enable docker
sudo systemctl start docker

# Use known directory
cd /opt

# Fresh clone
rm -rf multi-platform-moodle-infra
git clone https://github.com/infraalchemy/multi-platform-moodle-infra.git

cd /opt/multi-platform-moodle-infra/docker

# Fetch secret from GCP
MYSQL_ROOT_PASSWORD=$(gcloud secrets versions access latest \
  --secret="mysql-root-password")

# Create .env file
cat <<EOF > .env
MYSQL_DATABASE=moodle
MYSQL_USER=moodleuser
MYSQL_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
EOF

# Deploy
sudo docker-compose down || true
sudo docker-compose build --no-cache
sudo docker-compose up -d

sudo docker ps
