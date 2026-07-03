version: 0.1
component: command
timeoutInSeconds: 1800
shell: bash
failImmediatelyOnError: true

env:
  variables:
    TARGET_HOST: "<FRONTEND_HOST_IP>" # Change IP address accordingly
    TARGET_USER: "deploy"
    APP_NAME: "frontend"
    APP_BASE: "/WEB/cicdtest/frontend"
  vaultVariables:
    SSH_PRIVATE_KEY_B64: "<SSH_PRIVATE_KEY_OCID>" # Change OCID accordingly

inputArtifacts:
  - name: app-package
    type: GENERIC_ARTIFACT
    registryId: "<ARTIFACT_REGISTRY_OCID>" # Change OCID accordingly
    path: "frontend/app"
    version: "${PACKAGE_VERSION}"
    location: "app.tar.gz"

steps:
  - type: Command
    name: "Deploy frontend"
    command: |
      set -euo pipefail

      echo "=== Starting frontend deployment ==="
      echo "Workspace:"
      pwd
      ls -la

      echo "Checking downloaded artifact:"
      ls -lh app.tar.gz

      echo "Artifact contents:"
      tar -tzf app.tar.gz | head -50

      mkdir -p ~/.ssh
      printf '%s' "$SSH_PRIVATE_KEY_B64" | tr -d '\r\n ' | base64 -d > ~/.ssh/id_ed25519
      chmod 600 ~/.ssh/id_ed25519

      ssh-keyscan -T 10 -H ${TARGET_HOST} >> ~/.ssh/known_hosts

      SSH_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2"
      SCP_OPTS="-i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2"

      echo "Testing SSH:"
      ssh -n ${SSH_OPTS} ${TARGET_USER}@${TARGET_HOST} "hostname && whoami && pwd"

      RELEASE_ID=$(date +%Y%m%d%H%M%S)
      RELEASE_DIR="${APP_BASE}/releases/${RELEASE_ID}"

      echo "Release directory: ${RELEASE_DIR}"

      echo "Creating release directory..."
      ssh -n ${SSH_OPTS} ${TARGET_USER}@${TARGET_HOST} "mkdir -p ${RELEASE_DIR}"

      echo "Copying artifact..."
      scp ${SCP_OPTS} app.tar.gz ${TARGET_USER}@${TARGET_HOST}:${RELEASE_DIR}/app.tar.gz

      echo "Confirm copied artifact:"
      ssh -n ${SSH_OPTS} ${TARGET_USER}@${TARGET_HOST} "ls -lh ${RELEASE_DIR}/app.tar.gz"

      echo "Extracting artifact..."
      ssh -n ${SSH_OPTS} ${TARGET_USER}@${TARGET_HOST} "
        set -e

        cd ${RELEASE_DIR}

        echo 'Before extraction:'
        ls -la

        echo 'Remote artifact contents:'
        tar -tzf app.tar.gz | head -50

        tar -xzf app.tar.gz
        rm -f app.tar.gz

        echo 'After extraction:'
        ls -la
        find . -maxdepth 3 -type f | head -50

        ln -sfn ${RELEASE_DIR} ${APP_BASE}/current

        echo 'Current symlink:'
        ls -l ${APP_BASE}/current

        sudo -n /usr/bin/systemctl reload nginx
		
	echo 'Cleaning old releases, keeping latest 5...'
	cd ${APP_BASE}/releases
	ls -1dt */ | tail -n +6 | xargs -r rm -rf
      "

      echo "=== Frontend deployment completed ==="
