```text
High Level Architecture:

GitHub Organization
 ├── middleware repo  ──┐
 ├── backend repo     ──┼── OCI DevOps External Connection
 └── frontend repo    ──┘      PAT stored in OCI Vault
                                          │
                                          ▼
                                OCI DevOps Project
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    ▼                     ▼                     ▼
             Middleware Build       Backend Build        Frontend Build
             Pipeline               Pipeline             Pipeline
                    │                     │                     │
                    ▼                     ▼                     ▼
            	    	OCI Artifact Registry / build artifact output
                    │                     │                     │
                    ▼                     ▼                     ▼
            	          Deployment Pipeline with Shell Stage
                    │                     │                     │
                    ▼                     ▼                     ▼
             CICDTEST_MIDDLEWARE    CICDTEST_BACKEND      CICDTEST_FRONTEND
             Ubuntu private VM      Ubuntu private VM     Ubuntu private VM


Product used:
Oracle Cloud Infrastructure Compute, Networking, Load Balancer, DevOps/Build Pipeline, Object Storage/Artifacts, GitHub integration, Ubuntu, Nginx, Laravel.

What I created:
A CI/CD deployment workflow for frontend, backend and middleware components hosted on OCI Compute instances. The pipeline builds deployment packages, transfers them to OCI servers, reloads Nginx and verifies application availability.

What I learned:
OCI-based deployment architecture, secure deployment packaging, Nginx reverse proxy/static hosting configuration, GitHub-to-OCI deployment flow, pipeline troubleshooting and environment separation.
