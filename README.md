# OCI CI/CD Deployment Project

## Overview

This project demonstrates a CI/CD deployment workflow using GitHub and Oracle Cloud Infrastructure DevOps services.

The setup includes separate build and deployment pipelines for three application components:

- Frontend
- Backend
- Middleware

Each component is maintained in a separate GitHub repository. OCI DevOps is used to build the application artifacts, store the generated packages in OCI Artifact Registry, and deploy them to Ubuntu-based OCI Compute instances using DevOps deployment pipelines with Shell stages.

The frontend application is exposed through an OCI Load Balancer.

---

## High-Level Architecture

```text
GitHub Organization
 ├── middleware repo  ──┐
 ├── backend repo     ──┼── OCI DevOps External Connection
 └── frontend repo    ──┘                |
                                         │
                                         │ GitHub PAT stored securely in OCI Vault
                                         ▼
                                  OCI DevOps Project
                                         │
                   ┌─────────────────────┼─────────────────────┐
                   ▼                     ▼                     ▼
            Middleware Build       Backend Build        Frontend Build
            Pipeline               Pipeline             Pipeline
                   │                     │                     │
                   ▼                     ▼                     ▼
                   OCI Artifact Registry / Generic Build Artifacts
                   │                     │                     │
                   ▼                     ▼                     ▼
            Middleware Deploy      Backend Deploy       Frontend Deploy
            Pipeline               Pipeline             Pipeline
                   │                     │                     │
                   ▼                     ▼                     ▼
            DevOps Shell Stage     DevOps Shell Stage   DevOps Shell Stage
                   │                     │                     │
                   ▼                     ▼                     ▼
            CICDTEST_MIDDLEWARE    CICDTEST_BACKEND     CICDTEST_FRONTEND
            Ubuntu Private VM      Ubuntu Private VM    Ubuntu Private VM
                                                               │
                                                               ▼
                                                       Nginx / Frontend App
                                                               │
                                                               ▼
                                                        OCI Load Balancer
                                                               │
                                                               ▼
                                                            End User
