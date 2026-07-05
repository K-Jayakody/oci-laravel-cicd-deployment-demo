# OCI CI/CD Setup Guide

This guide describes the steps required to configure a CI/CD deployment setup using GitHub, OCI DevOps, OCI Vault, OCI Artifact Registry, OCI Notifications, OCI Load Balancer, and Ubuntu-based application servers.

The setup includes separate build and deployment pipelines for the following components:

* Frontend
* Backend
* Middleware

---

## Security Notice

This guide is a sanitized CI/CD setup example.

Do **not** commit or expose any of the following values:

* Real secrets
* Private keys
* GitHub tokens
* OCI trigger URLs
* OCI trigger secrets
* OCIDs
* Public IP addresses
* Private IP addresses
* Customer names
* Tenancy names
* Environment files
* Production configuration values

All values shown using `<PLACEHOLDER>` must be replaced only in your private environment.

---

# Phase 1 — Prepare GitHub

## Create a GitHub User or Token

Create a GitHub Personal Access Token that OCI DevOps can use to access the required repositories.

Navigate to:

```text
GitHub → Profile → Settings
→ Developer settings
→ Personal access tokens
→ Tokens classic
→ Generate new token
```

## Recommended Token Scope

For public repositories:

```text
Use the minimum required GitHub token scope, such as public_repo.
```

For private repositories:

```text
Use a classic Personal Access Token with the repo scope.
```

Recommended security practices:

* Use a dedicated token for this CI/CD setup.
* Set an expiry date for the token.
* Grant access only to the repositories required for this project where possible.
* Store the token only in OCI Vault.

---

# Phase 2 — Prepare OCI Vault and Secrets

## Create an OCI Vault

Navigate to:

```text
OCI Console
→ Identity & Security
→ Vault
→ Create Vault
```

Use the following details:

```text
Vault name: cicdtest-devops-vault
```

## Create a Master Encryption Key

Inside the vault, create a master encryption key using the following values:

```text
Protection Mode: Software
Name: cicdtest-devops-mek
Key Shape Algorithm: AES
Key Shape Length: 256 bits
```

---

## Store the GitHub PAT as a Secret

Navigate to:

```text
OCI Console
→ Identity & Security
→ Secret Management
→ Create Secret
```

Use the following values:

```text
Name: github-pat-cicdtest
Description: GitHub PAT for OCI DevOps GitHub connection

Compartment: Select the compartment where you want the secret created

Vault compartment: Select the compartment where your vault exists
Vault: Select your vault

Encryption key compartment: Select the compartment where your key exists
Encryption key: Select your master encryption key

Secret generation method: Manual secret generation
Secret type template: Plain-text
Secret contents: Paste your GitHub PAT
```

---

## Create an SSH Key for Deployment

Create an SSH key pair for the deployment user. This key will be used by the OCI DevOps Shell stage to connect to the Ubuntu servers.

You may create the key using `ssh-keygen` on Linux or PuTTYgen on Windows.

Example using Linux:

```bash
ssh-keygen -t rsa -b 4096 -f id_rsa
```

Convert the private key content into base64 format:

```bash
base64 -w 0 id_rsa > id_rsa.b64
```

Store the base64-encoded private key in OCI Vault.

Navigate to:

```text
OCI Console
→ Identity & Security
→ Secret Management
→ Create Secret
```

Use the following values:

```text
Name: ssh-private-key-cicdtest
Secret generation method: Manual secret generation
Secret type template: Plain-text
Secret contents: Paste the base64-encoded private key content
```

> **Important:** Base64 encoding is not encryption. It is only used to safely store or pass the key content as text.

---

# Phase 3 — Prepare IAM Policies

## Create a Dynamic Group for OCI DevOps

Navigate to:

```text
OCI Console
→ Identity & Security
→ Domains
→ Dynamic Groups
→ Create Dynamic Group
```

Use the following name:

```text
DevOpsDynamicGroup
```

Use a DevOps-specific matching rule instead of matching all resources in the compartment.

Recommended matching rule:

```text
ANY {
  ALL {resource.type = 'devopsbuildpipeline', resource.compartment.id = '<COMPARTMENT_OCID>'},
  ALL {resource.type = 'devopsdeploypipeline', resource.compartment.id = '<COMPARTMENT_OCID>'},
  ALL {resource.type = 'devopsrepository', resource.compartment.id = '<COMPARTMENT_OCID>'},
  ALL {resource.type = 'devopsconnection', resource.compartment.id = '<COMPARTMENT_OCID>'}
}
```

Replace:

```text
<COMPARTMENT_OCID>
```

with the OCID of the compartment where the OCI DevOps resources are created.

> **Note:** If your tenancy uses identity domains, you may need to reference the dynamic group in IAM policies using the format `<DOMAIN_NAME>/DevOpsDynamicGroup`.

---

## Create IAM Policies

Create the following IAM policies.

If your tenancy requires identity domain prefixes, use:

```text
Allow dynamic-group <DOMAIN_NAME>/DevOpsDynamicGroup to ...
```

Otherwise, use:

```text
Allow dynamic-group DevOpsDynamicGroup to ...
```

### DevOps, Vault, Artifact, and Notification Policies

```text
Allow dynamic-group DevOpsDynamicGroup to manage devops-family in compartment id <COMPARTMENT_OCID>
Allow dynamic-group DevOpsDynamicGroup to read secret-family in compartment id <COMPARTMENT_OCID>
Allow dynamic-group DevOpsDynamicGroup to manage generic-artifacts in compartment id <COMPARTMENT_OCID>
Allow dynamic-group DevOpsDynamicGroup to read all-artifacts in compartment id <COMPARTMENT_OCID>
Allow dynamic-group DevOpsDynamicGroup to use ons-topics in compartment id <COMPARTMENT_OCID>
```

### Network Policies

```text
Allow dynamic-group DevOpsDynamicGroup to use subnets in compartment id <NETWORK_COMPARTMENT_OCID>
Allow dynamic-group DevOpsDynamicGroup to use vnics in compartment id <NETWORK_COMPARTMENT_OCID>
Allow dynamic-group DevOpsDynamicGroup to use network-security-groups in compartment id <NETWORK_COMPARTMENT_OCID>
Allow dynamic-group DevOpsDynamicGroup to use dhcp-options in compartment id <NETWORK_COMPARTMENT_OCID>
```

### Shell Stage Container Policies

```text
Allow dynamic-group DevOpsDynamicGroup to manage compute-container-instances in compartment id <COMPARTMENT_OCID>
Allow dynamic-group DevOpsDynamicGroup to manage compute-containers in compartment id <COMPARTMENT_OCID>
```

---

# Phase 4 — Prepare Network Access

## Choose a Subnet for the OCI DevOps Shell Stage

Select a subnet that can reach the target Ubuntu servers.

Recommended:

```text
Use a private subnet that has network connectivity to the frontend, backend, and middleware servers.
```

The subnet does not necessarily need to be the same subnet as the application servers, but it must have the correct routing and security rules.

---

## Add Security Rules for SSH Deployment

On the NSG or security list attached to the Ubuntu servers, allow SSH access from the OCI DevOps Shell stage subnet or DevOps deployment NSG.

### Ingress Rule on Ubuntu Server NSG or Security List

```text
Source: <DEVOPS_SHELL_STAGE_SUBNET_CIDR_OR_NSG>
Protocol: TCP
Destination port: 22
Description: Allow OCI DevOps Shell stage SSH deployment
```

---

# Phase 5 — Prepare Ubuntu Servers

Run the following steps on each Ubuntu server.

The servers in this setup are:

* Frontend server
* Backend server
* Middleware server

---

## Create a Deployment User

```bash
sudo adduser deploy
sudo usermod -aG www-data deploy
```

---

## Add the Deployment Public Key

Create the `.ssh` directory for the deployment user:

```bash
sudo mkdir -p /home/deploy/.ssh
```

Edit the `authorized_keys` file:

```bash
sudo vi /home/deploy/.ssh/authorized_keys
```

Paste the content of the deployment public key.

Set the correct ownership and permissions:

```bash
sudo chown -R deploy:deploy /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
sudo chmod 600 /home/deploy/.ssh/authorized_keys
```

---

## Create Deployment Directories

### Frontend

```bash
sudo mkdir -p /WEB/cicdtest/frontend/releases
sudo mkdir -p /WEB/cicdtest/frontend/shared
sudo chown -R deploy:www-data /WEB/cicdtest/frontend
sudo chmod -R 775 /WEB/cicdtest/frontend
```

### Backend

```bash
sudo mkdir -p /WEB/cicdtest/backend/releases
sudo mkdir -p /WEB/cicdtest/backend/shared
sudo chown -R deploy:www-data /WEB/cicdtest/backend
sudo chmod -R 775 /WEB/cicdtest/backend
```

### Middleware

```bash
sudo mkdir -p /WEB/cicdtest/middleware/releases
sudo mkdir -p /WEB/cicdtest/middleware/shared
sudo chown -R deploy:www-data /WEB/cicdtest/middleware
sudo chmod -R 775 /WEB/cicdtest/middleware
```

> **Note:** For production environments, review directory permissions and apply the minimum permissions required by the deployment user and web server process.

---

## Keep Environment Files on the Server

Do not package `.env` files into the deployment artifact.

Create shared `.env` files on each server.

### Frontend

```bash
sudo touch /WEB/cicdtest/frontend/shared/.env
sudo chown deploy:www-data /WEB/cicdtest/frontend/shared/.env
sudo chmod 640 /WEB/cicdtest/frontend/shared/.env
```

### Backend

```bash
sudo touch /WEB/cicdtest/backend/shared/.env
sudo chown deploy:www-data /WEB/cicdtest/backend/shared/.env
sudo chmod 640 /WEB/cicdtest/backend/shared/.env
```

### Middleware

```bash
sudo touch /WEB/cicdtest/middleware/shared/.env
sudo chown deploy:www-data /WEB/cicdtest/middleware/shared/.env
sudo chmod 640 /WEB/cicdtest/middleware/shared/.env
```

---

## Allow Controlled Service Reload or Restart

Edit the sudoers file safely:

```bash
sudo visudo
```

Add the following entries:

```text
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl reload nginx
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart php8.3-fpm
```

> **Note:** Adjust the PHP-FPM version if your server uses a different PHP version.

---

# Phase 6 — Create OCI DevOps Project

## Create a Notification Topic

If you do not already have an OCI Notifications topic, create one.

Navigate to:

```text
OCI Console
→ Developer Services
→ Notifications
→ Topics
→ Create Topic
```

Use the following topic name:

```text
Topic name: cicdtest-devops-topic
```

---

## Create a DevOps Project

Navigate to:

```text
OCI Console
→ Developer Services
→ DevOps
→ Projects
→ Create DevOps Project
```

Use the following project name:

```text
Project name: CICDTEST-DevOps-PROJECT
```

---

# Phase 7 — Create GitHub External Connection

## Create the External Connection

Navigate to:

```text
OCI Console
→ Developer Services
→ DevOps
→ Projects
→ CICDTEST-DevOps-PROJECT
→ External Connections
→ Create External Connection
```

Use the following values:

```text
Name: cicdtest-github-connection
Connection type: GitHub
Vault: cicdtest-devops-vault
Secret: github-pat-cicdtest
```

---

## Validate the Connection

Navigate to:

```text
External Connections
→ Select GitHub connection
→ Validate Connection
```

Confirm that the connection validation is successful before continuing.

---

# Phase 8 — Create Artifact Registry Repository

Navigate to:

```text
OCI Console
→ Developer Services
→ Containers & Artifacts
→ Artifact Registry
→ Create Repository
```

Use the following values:

```text
Repository name: cicdtest-artifacts
Repository type: Generic
Immutable artifacts: Optional, recommended for production
```

Suggested artifact paths:

```text
middleware/app
backend/app
frontend/app
```

Suggested artifact versioning options:

```text
Git commit hash
OCI build run ID
Timestamp
```

Recommended option:

```text
Git commit hash
```

---

# Phase 9 — Add Build Specs to GitHub Repositories

Add a `build_spec.yaml` file to the root of each GitHub repository.

---

## Frontend Repository

Copy the content from:

```text
build-specs/frontend-build_spec.yaml
```

to:

```text
build_spec.yaml
```

In the Deliver Artifacts stage, map the artifact as follows:

```text
Build output artifact: frontend-package
DevOps artifact: frontend-package
Version: ${PACKAGE_VERSION}
```

---

## Backend Repository

Copy the content from:

```text
build-specs/backend-build_spec.yaml
```

to:

```text
build_spec.yaml
```

In the Deliver Artifacts stage, map the artifact as follows:

```text
Build output artifact: backend-package
DevOps artifact: backend-package
Version: ${PACKAGE_VERSION}
```

---

## Middleware Repository

Copy the content from:

```text
build-specs/middleware-build_spec.yaml
```

to:

```text
build_spec.yaml
```

In the Deliver Artifacts stage, map the artifact as follows:

```text
Build output artifact: middleware-package
DevOps artifact: middleware-package
Version: ${PACKAGE_VERSION}
```

---

# Phase 10 — Create DevOps Artifacts

Navigate to:

```text
OCI Console
→ Developer Services
→ DevOps
→ Projects
→ CICDTEST-DevOps-PROJECT
→ Artifacts
→ Add Artifact
```

---

## Frontend Artifact

```text
Name: frontend-package
Type: General Artifact
Artifact source: Artifact Registry Repository
Artifact Location: Set Custom Location
Artifact path: frontend/app
Version: ${PACKAGE_VERSION}
Allow parameterization: Yes
```

---

## Backend Artifact

```text
Name: backend-package
Type: General Artifact
Artifact source: Artifact Registry Repository
Artifact Location: Set Custom Location
Artifact path: backend/app
Version: ${PACKAGE_VERSION}
Allow parameterization: Yes
```

---

## Middleware Artifact

```text
Name: middleware-package
Type: General Artifact
Artifact source: Artifact Registry Repository
Artifact Location: Set Custom Location
Artifact path: middleware/app
Version: ${PACKAGE_VERSION}
Allow parameterization: Yes
```

---

# Phase 11 — Create Build Pipelines

Create the following build pipelines:

```text
build-cicdtest-middleware
build-cicdtest-backend
build-cicdtest-frontend
```

---

## Middleware Build Pipeline

Navigate to:

```text
OCI Console
→ Developer Services
→ DevOps
→ Projects
→ CICDTEST-DevOps-PROJECT
→ Build Pipelines
→ Create Build Pipeline
```

Use the following pipeline name:

```text
Name: build-cicdtest-middleware
```

Add a Managed Build stage:

```text
Stage type: Managed Build
Name: build-middleware
Build source: GitHub
Connection: cicdtest-github-connection
Repository: <MIDDLEWARE_REPOSITORY>
Branch: main
Build source name: middleware-source
Build spec path: build_spec.yaml
```

Add a Deliver Artifacts stage:

```text
Stage type: Deliver Artifacts
Name: deliver-middleware-artifact
Map build output: middleware-package
To DevOps artifact: middleware-package
```

After the deployment pipeline is created, return to this build pipeline and add a Trigger Deployment stage:

```text
Name: trigger-cicdtest-middleware
Stage type: Trigger Deployment
Deployment pipeline: deploy-cicdtest-middleware
```

---

## Backend Build Pipeline

Navigate to:

```text
OCI Console
→ Developer Services
→ DevOps
→ Projects
→ CICDTEST-DevOps-PROJECT
→ Build Pipelines
→ Create Build Pipeline
```

Use the following pipeline name:

```text
Name: build-cicdtest-backend
```

Add a Managed Build stage:

```text
Stage type: Managed Build
Name: build-backend
Build source: GitHub
Connection: cicdtest-github-connection
Repository: <BACKEND_REPOSITORY>
Branch: main
Build source name: backend-source
Build spec path: build_spec.yaml
```

Add a Deliver Artifacts stage:

```text
Stage type: Deliver Artifacts
Name: deliver-backend-artifact
Map build output: backend-package
To DevOps artifact: backend-package
```

After the deployment pipeline is created, return to this build pipeline and add a Trigger Deployment stage:

```text
Name: trigger-cicdtest-backend
Stage type: Trigger Deployment
Deployment pipeline: deploy-cicdtest-backend
```

---

## Frontend Build Pipeline

Navigate to:

```text
OCI Console
→ Developer Services
→ DevOps
→ Projects
→ CICDTEST-DevOps-PROJECT
→ Build Pipelines
→ Create Build Pipeline
```

Use the following pipeline name:

```text
Name: build-cicdtest-frontend
```

Add a Managed Build stage:

```text
Stage type: Managed Build
Name: build-frontend
Build source: GitHub
Connection: cicdtest-github-connection
Repository: <FRONTEND_REPOSITORY>
Branch: main
Build source name: frontend-source
Build spec path: build_spec.yaml
```

Add a Deliver Artifacts stage:

```text
Stage type: Deliver Artifacts
Name: deliver-frontend-artifact
Map build output: frontend-package
To DevOps artifact: frontend-package
```

After the deployment pipeline is created, return to this build pipeline and add a Trigger Deployment stage:

```text
Name: trigger-cicdtest-frontend
Stage type: Trigger Deployment
Deployment pipeline: deploy-cicdtest-frontend
```

---

# Phase 12 — Create Command Specs for Deployment

Create one command specification artifact for each deployment pipeline.

Navigate to:

```text
OCI Console
→ Developer Services
→ DevOps
→ Projects
→ CICDTEST-DevOps-PROJECT
→ Artifacts
→ Add Artifact
```

---

## Middleware Command Spec

```text
Name: deploy-middleware-command-spec
Type: Command specification
Artifact source: Inline
Allow parameterization: Disabled
```

Add the content from:

```text
scripts/deploy-middleware-command-spec.sh
```

---

## Backend Command Spec

```text
Name: deploy-backend-command-spec
Type: Command specification
Artifact source: Inline
Allow parameterization: Disabled
```

Add the content from:

```text
scripts/deploy-backend-command-spec.sh
```

---

## Frontend Command Spec

```text
Name: deploy-frontend-command-spec
Type: Command specification
Artifact source: Inline
Allow parameterization: Disabled
```

Add the content from:

```text
scripts/deploy-frontend-command-spec.sh
```

---

# Phase 13 — Create Deployment Pipelines

Create the following deployment pipelines:

```text
deploy-cicdtest-middleware
deploy-cicdtest-backend
deploy-cicdtest-frontend
```

---

## Middleware Deployment Pipeline

Navigate to:

```text
OCI Console
→ Developer Services
→ DevOps
→ Projects
→ CICDTEST-DevOps-PROJECT
→ Deployment Pipelines
→ Create Pipeline
```

Use the following pipeline name:

```text
Pipeline name: deploy-cicdtest-middleware
```

Add a Shell stage:

```text
Stage type: Integrations - Shell
Name: shell-deploy-middleware
Command spec artifact: deploy-middleware-command-spec
Compartment: DevOps compartment
Availability domain: Select one
Shape: Small flexible shape
VCN: VCN where the private servers are reachable
Subnet: Private subnet that can reach the middleware server
NSG: DevOps deployment NSG, if used
```

---

## Frontend Deployment Pipeline

Navigate to:

```text
OCI Console
→ Developer Services
→ DevOps
→ Projects
→ CICDTEST-DevOps-PROJECT
→ Deployment Pipelines
→ Create Pipeline
```

Use the following pipeline name:

```text
Pipeline name: deploy-cicdtest-frontend
```

Add a Shell stage:

```text
Stage type: Integrations - Shell
Name: shell-deploy-frontend
Command spec artifact: deploy-frontend-command-spec
Compartment: DevOps compartment
Availability domain: Select one
Shape: Small flexible shape
VCN: VCN where the private servers are reachable
Subnet: Private subnet that can reach the frontend server
NSG: DevOps deployment NSG, if used
```

---

## Backend Deployment Pipeline

Navigate to:

```text
OCI Console
→ Developer Services
→ DevOps
→ Projects
→ CICDTEST-DevOps-PROJECT
→ Deployment Pipelines
→ Create Pipeline
```

Use the following pipeline name:

```text
Pipeline name: deploy-cicdtest-backend
```

Add a Shell stage:

```text
Stage type: Integrations - Shell
Name: shell-deploy-backend
Command spec artifact: deploy-backend-command-spec
Compartment: DevOps compartment
Availability domain: Select one
Shape: Small flexible shape
VCN: VCN where the private servers are reachable
Subnet: Private subnet that can reach the backend server
NSG: DevOps deployment NSG, if used
```

---

## Add Trigger Deployment Stages to Build Pipelines

After all deployment pipelines are created, return to each build pipeline and add the Trigger Deployment stage that was skipped earlier.

The final flow for each component should be:

```text
Managed Build
→ Deliver Artifacts
→ Trigger Deployment
→ Shell Deployment
```

---

# Phase 14 — Create Triggers

Create one trigger for each GitHub repository.

Navigate to:

```text
OCI Console
→ Developer Services
→ DevOps
→ Projects
→ CICDTEST-DevOps-PROJECT
→ Triggers
→ Create Trigger
```

> **Important:** Note down the OCI trigger URL and trigger secret.

---

## Middleware Trigger

```text
Name: trigger-middleware-main
Source connection: GitHub
Event: Push
Branch: main
Action: build-cicdtest-middleware
```

---

## Backend Trigger

```text
Name: trigger-backend-main
Source connection: GitHub
Event: Push
Branch: main
Action: build-cicdtest-backend
```

---

## Frontend Trigger

```text
Name: trigger-frontend-main
Source connection: GitHub
Event: Push
Branch: main
Action: build-cicdtest-frontend
```

---

## Create GitHub Webhooks

Create a webhook in each GitHub repository.

Navigate to:

```text
GitHub repository
→ Settings
→ Webhooks
→ Add webhook
```

Use the following values:

```text
Payload URL: <OCI_TRIGGER_URL>
Content type: application/json
Secret: <OCI_TRIGGER_SECRET>
Events: Push events
Active: Enabled
```

> **Note:** For GitHub repositories, the webhook is created inside the specific GitHub repository. Depending on the OCI Console flow, the repository may not appear as a separate selectable field when creating the OCI trigger.

---

# Phase 15 — Configure Nginx Paths

Navigate to the Nginx sites directory:

```bash
cd /etc/nginx/sites-available
```

---

## Frontend Nginx Configuration

Create or update the frontend Nginx configuration file.

Use the content from:

```text
nginx/frontend.conf
```

---

## Backend Nginx Configuration

Create or update the backend Nginx configuration file.

Use the content from:

```text
nginx/backend.conf
```

---

## Validate and Reload Nginx

After updating the configuration files, validate the Nginx configuration:

```bash
sudo nginx -t
```

If the test is successful, reload Nginx:

```bash
sudo systemctl reload nginx
```

---

# Phase 16 — Test the Pipelines Manually

Before relying on GitHub push triggers, test each build pipeline manually.

---

## Enable OCI DevOps Logging

Navigate to:

```text
OCI Console
→ Observability & Management
→ Logging
→ Logs
→ Enable Service Log
```

Use the following values:

```text
Resource compartment: Select the compartment where your DevOps project exists
Service: DevOps
Resource: Select your DevOps project
Log category: DevOps-all logs
Log name: cicdtest-devops-logs
Log group: Create a new log group or select an existing one
```

---

## Run Each Build Pipeline Manually

Run the frontend build pipeline:

```text
Build Pipelines
→ build-cicdtest-frontend
→ Start manual run
```

Run the backend build pipeline:

```text
Build Pipelines
→ build-cicdtest-backend
→ Start manual run
```

Run the middleware build pipeline:

```text
Build Pipelines
→ build-cicdtest-middleware
→ Start manual run
```

Confirm that each pipeline completes successfully before testing webhook-based triggers.

---

# Phase 17 — Production Hardening

## Retain Only the Latest Five Releases

To avoid storing too many old releases on the server, add a cleanup step inside each deployment command spec.

The cleanup command should run near the end of the remote SSH block, after the application has been deployed successfully.

---

## Frontend Cleanup Example

Add the following section after the Nginx reload step:

```bash
sudo -n /usr/bin/systemctl reload nginx

echo 'Cleaning old releases, keeping latest 5...'
cd "${APP_BASE}/releases"
ls -1dt */ | tail -n +6 | xargs -r rm -rf

echo "=== Frontend deployment completed ==="
```

---

## Backend and Middleware Cleanup Example

Add the following section after the Nginx reload and PHP-FPM restart steps:

```bash
sudo -n /usr/bin/systemctl reload nginx
sudo -n /usr/bin/systemctl restart php8.3-fpm

echo 'Cleaning old releases, keeping latest 5...'
cd "${APP_BASE}/releases"
ls -1dt */ | tail -n +6 | xargs -r rm -rf

echo "=== Deployment completed successfully ==="
```

> **Note:** Ensure that `APP_BASE` is correctly set in the deployment command spec before running the cleanup command.

---

## Configure Notifications

Since the notification topic was created earlier, start by adding email subscriptions.

Navigate to:

```text
OCI Console
→ Developer Services
→ Notifications
→ Topics
→ cicdtest-devops-topic
→ Subscriptions
→ Create Subscription
```

Add the email addresses that should receive build and deployment notifications.

Each email recipient must confirm the subscription before notifications are delivered.

---

## Create Events Rules for Build and Deployment Updates

Navigate to:

```text
OCI Console
→ Observability & Management
→ Events Service
→ Rules
→ Create Rule
```

Create the following rules.

### Build Run Updates

```text
Display name: cicdtest-buildrun-updates
Service name: DevOps Build
Event type: BuildRun - Update
Action type: Notifications
Topic: cicdtest-devops-topic
```

### Deployment Updates

```text
Display name: cicdtest-deployment-updates
Service name: DevOps Deploy
Event type: Deployment - Update
Action type: Notifications
Topic: cicdtest-devops-topic
```

---

# Phase 18 — Expose the Frontend Server to the Internet

## Create a Public Load Balancer

Navigate to:

```text
OCI Console
→ Networking
→ Load Balancers
→ Load Balancer
→ Create Load Balancer
```

Use the following values:

```text
Load balancer name: cicdtest-lb
Visibility type: Public
Assign a public IP address: Ephemeral
Choose networking: VCN and public subnet
Configure listener: HTTP
```

---

## Create a Frontend Backend Set

Navigate to:

```text
OCI Console
→ Networking
→ Load Balancers
→ cicdtest-lb
→ Backend Sets
→ Create Backend Set
```

Use the following values:

```text
Name: cicdtest-frontend
Health Check Protocol: HTTP
Health Check Port: 80
```

---

## Attach the Frontend Server as a Backend

Navigate to:

```text
OCI Console
→ Networking
→ Load Balancers
→ cicdtest-lb
→ Backend Sets
→ cicdtest-frontend
→ Add Backends
```

Use the following values:

```text
Backend type: Compute instances
Select backend servers: Select the frontend instance
```

---

## Create a Frontend Listener

Navigate to:

```text
OCI Console
→ Networking
→ Load Balancers
→ cicdtest-lb
→ Listeners
→ Create Listener
```

Use the following values:

```text
Name: cicdtest-frontend-listener
Protocol: HTTP
Port: 80
Backend set: cicdtest-frontend
```

---

## Configure Load Balancer NSG Rules

Attach an NSG to the load balancer and allow HTTP traffic.

### Load Balancer NSG Ingress Rule

```text
Source: 0.0.0.0/0
Protocol: TCP
Destination port: 80
Description: Allow public HTTP traffic to the load balancer
```

### Load Balancer NSG Egress Rule

```text
Destination: <FRONTEND_SERVER_SUBNET_CIDR_OR_FRONTEND_SERVER_NSG>
Protocol: TCP
Destination port: 80
Description: Allow HTTP traffic from load balancer to frontend server
```

---

## Configure Frontend Server NSG Rules

On the frontend server NSG or security list, allow HTTP traffic from the load balancer.

### Frontend Server NSG Ingress Rule

```text
Source: <LOAD_BALANCER_SUBNET_CIDR_OR_NSG>
Protocol: TCP
Destination port: 80
Description: Allow HTTP traffic from OCI Load Balancer to frontend server
```

---

# Final Validation Checklist

Use the following checklist to validate the setup:

* [ ] GitHub PAT is stored only in OCI Vault.
* [ ] SSH private key is stored only in OCI Vault.
* [ ] Dynamic group uses DevOps-specific matching rules.
* [ ] IAM policies are created successfully.
* [ ] OCI DevOps project is created.
* [ ] GitHub external connection is validated.
* [ ] Artifact Registry repository is created.
* [ ] DevOps artifacts are created with parameterized versions.
* [ ] Build pipelines are created.
* [ ] Deployment pipelines are created.
* [ ] Shell stages can reach the target Ubuntu servers.
* [ ] Nginx configuration passes validation.
* [ ] Manual build pipeline runs are successful.
* [ ] Deployment stages complete successfully.
* [ ] GitHub webhooks trigger the correct build pipelines.
* [ ] OCI Logging is enabled for DevOps.
* [ ] OCI Notifications subscriptions are confirmed.
* [ ] Load balancer health checks are passing.
* [ ] Frontend application is accessible through the load balancer.

---

# Summary

This setup provides a CI/CD deployment workflow where GitHub repository updates trigger OCI DevOps build pipelines. The build pipelines package the application artifacts, deliver them to OCI Artifact Registry, and then trigger deployment pipelines. The deployment pipelines use OCI DevOps Shell stages to deploy the artifacts to Ubuntu servers using SSH.

The final architecture includes:

```text
          GitHub Repository
                  |
                  v
          OCI DevOps Trigger
                  |
                  v
      OCI DevOps Build Pipeline
                  |
                  v
        OCI Artifact Registry
                  |
                  v
    OCI DevOps Deployment Pipeline
                  |
                  v
        OCI DevOps Shell Stage
                  |
                  v
      Ubuntu Application Server
                  |
                  v
                Nginx
                  |
                  v
          OCI Load Balancer
                  |
                  v
              End User
```
