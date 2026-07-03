version: 0.1
component: command
timeoutInSeconds: 1800
shell: bash
failImmediatelyOnError: true

env:
  variables:
    TARGET_HOST: "<MIDDLEWARE_HOST_IP>" # Change IP address accordingly
    TARGET_USER: "deploy"
    APP_NAME: "middleware"
    APP_BASE: "/WEB/cicdtest/middleware"
  vaultVariables:
    SSH_PRIVATE_KEY_B64: "<SSH_PRIVATE_KEY_OCID>" # Change OCID accordingly

inputArtifacts:
  - name: app-package
    type: GENERIC_ARTIFACT
    registryId: "<ARTIFACT_REGISTRY_OCID>" # Change OCID accordingly
    path: "middleware/app"
    version: "${PACKAGE_VERSION}"
    location: "app.tar.gz"

steps:
  - type: Command
    name: "Deploy middleware"
    command: |
      set -euo pipefail

      echo "=== Starting middleware deployment ==="
      echo "Target host: ${TARGET_HOST}"
      echo "Application base: ${APP_BASE}"

      echo "Checking downloaded artifact:"
      ls -lh app.tar.gz

      mkdir -p ~/.ssh
      printf '%s' "$SSH_PRIVATE_KEY_B64" | tr -d '\r\n ' | base64 -d > ~/.ssh/id_ed25519
      chmod 600 ~/.ssh/id_ed25519

      ssh-keyscan -T 10 -H ${TARGET_HOST} >> ~/.ssh/known_hosts

      SSH_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2"
      SCP_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2"

      echo "Testing SSH connection..."
      ssh -n ${SSH_OPTS} ${TARGET_USER}@${TARGET_HOST} "hostname && whoami && pwd"

      RELEASE_ID=$(date +%Y%m%d%H%M%S)
      RELEASE_DIR="${APP_BASE}/releases/${RELEASE_ID}"

      echo "Creating release directory: ${RELEASE_DIR}"
      ssh -n ${SSH_OPTS} ${TARGET_USER}@${TARGET_HOST} "mkdir -p ${RELEASE_DIR}"

      echo "Copying artifact..."
      scp ${SCP_OPTS} app.tar.gz ${TARGET_USER}@${TARGET_HOST}:${RELEASE_DIR}/app.tar.gz

      echo "Deploying middleware release..."
      ssh -n ${SSH_OPTS} ${TARGET_USER}@${TARGET_HOST} "
        set -e

        cd ${RELEASE_DIR}

        echo 'Before extraction:'
        ls -la

        tar -xzf app.tar.gz
        rm -f app.tar.gz

        echo 'After extraction:'
        ls -la

        if [ -f ${APP_BASE}/shared/.env ]; then
          ln -sfn ${APP_BASE}/shared/.env ${RELEASE_DIR}/.env
        fi

        ln -sfn ${RELEASE_DIR} ${APP_BASE}/current

        if [ -f ${APP_BASE}/current/artisan ]; then
          cd ${APP_BASE}/current

          php artisan config:clear || true
          php artisan cache:clear || true
          php artisan route:clear || true
          php artisan view:clear || true

          php artisan config:cache || true
          php artisan route:cache || true
        fi

        echo 'Current symlink:'
        ls -l ${APP_BASE}/current

        sudo -n /usr/bin/systemctl reload nginx
        sudo -n /usr/bin/systemctl restart php8.3-fpm
		
	echo 'Cleaning old releases, keeping latest 5...'
	cd ${APP_BASE}/releases
	ls -1dt */ | tail -n +6 | xargs -r rm -rf
      "

      echo "=== Middleware deployment completed successfully ==="
