Moodle serves as the stateful application workload for a progressive infrastructure engineering project spanning containerization, Kubernetes orchestration, cloud infrastructure, and automated delivery.

Rather than using a pre-built Moodle image, the application is separated into Nginx, PHP-FPM, and MySQL components with clearly defined responsibilities. Nginx provides the web-facing HTTP layer and routes PHP requests to a custom PHP-FPM application runtime, while MySQL provides the database layer backed by persistent storage.

The same application architecture is progressively evolved across increasingly sophisticated deployment models:

**Docker Compose on GCP → Local Multi-node KinD → Multi-node GKE → Red Hat OpenShift → Azure Red Hat OpenShift (ARO)**

Each phase builds on the previous implementation while introducing additional capabilities in orchestration, persistent state management, networking and ingress, infrastructure as code, cloud services, security, recovery validation, and deployment automation.

---

## Deployment Environment

All infrastructure provisioning and application deployments were initiated from a Windows workstation.

- Workstation: Windows 11
- Local Linux environment: WSL2
- Container runtime: Docker Desktop
- Local Kubernetes: KinD
- Cloud infrastructure: Google Cloud Platform (GCP), Microsoft Azure
- Cloud Kubernetes: Google Kubernetes Engine (GKE), Red Hat OpenShift Developer Sandbox, Azure Red Hat OpenShift (ARO)
- Infrastructure as Code: Terraform
- Container registries: Google Artifact Registry, Azure Container Registry (ACR)
---

## Repository Structure

*Temporary component-level Kustomizations were used during testing to independently deploy and validate each component.*


```text
├── .github/
│   └── workflows/
│       ├── gcp-gke-deploy.yaml           # GCP/GKE CI/CD deployment workflow
│       └── azure-aro-deploy.yaml         # Azure/ARO CI/CD deployment workflow (in development)
│
├── scripts/
│   ├── configure-moodle-aro.sh           # Configure Moodle on Azure Red Hat OpenShift
│   ├── configure-moodle-gke.sh           # Configure Moodle on GKE
│   ├── configure-moodle-openshift.sh     # Configure Moodle on OpenShift
│   ├── deploy-aro.sh                     # Deploy Moodle workloads to ARO
│   ├── deploy-gke.sh                     # Deploy Moodle workloads to GKE
│   ├── deploy-infra.sh                   # Infrastructure deployment automation
│   ├── pre-deploy-aro.sh                 # ARO pre-deployment preparation
│   ├── destroy-all.sh                    # Environment teardown automation
│   ├── verify-all-win.sh                 # Windows deployment validation
│   ├── verify-gcp.sh                     # GCP environment validation
│   └── verify-openshift.sh               # OpenShift deployment validation
│ 
├── docs/                                 # Engineering documentation
│   ├── gcp_terraform_deploy.md           # GCP VM infrastructure provisioning
│   ├── gcp-github-actions-oidc-setup.md  # GCP Workload Identity Federation and GitHub Actions
│   ├── gke_pipeline_troubleshooting.md   # GKE CI/CD pipeline troubleshooting
│   ├── p1_docker_deploy.md               # Phase 1: Docker Compose deployment
│   ├── p1_post_mortem.md                 # Phase 1: Troubleshooting and lessons learned
│   ├── p2_k8_deploy.md                   # Phase 2: Kubernetes KinD deployment
│   ├── p2_post_mortem.md                 # Phase 2: Troubleshooting and lessons learned
│   ├── p3_k8_deploy.md                   # Phase 3: GKE deployment
│   ├── p4_k8_deploy.md                   # Phase 4: OpenShift Developer Sandbox (planned)
│   ├── p4_post_mortem.md                 # Phase 4: Troubleshooting (planned)
│   ├── p5_k8_deploy.md                   # Phase 5: Azure Red Hat OpenShift deployment
│   ├── p5_post_mortem.md                 # Phase 5: Troubleshooting and lessons learned
│   └── persistence-test.png              # Persistent storage validation screenshot
│
├── docker/                               # docker-compose deployment
│   ├── docker-compose.yml                # Moodle multi-container application stack
│   ├── moodledata/                       # Persistent Moodle application data
│   ├── mysql/                            # MySQL database configuration
│   │   └── mysql-data/                   # Persistent MySQL database storage
│   ├── nginx/                            # Nginx reverse proxy container
│   │   ├── Dockerfile                    # Custom Nginx image definition
│   │   └── nginx.conf                    # Nginx configuration
│   └── php/                              # PHP-FPM Moodle application container
│       ├── Dockerfile                    # Custom PHP runtime image
│       ├── entrypoint.sh                 # Container initialization script
│       ├── index.php                     # PHP validation entry point
│       └── testdb.php                    # Database connectivity test
│
├── kubernetes/                           # Kubernetes deployment configurations
│   ├── kind/                             # Local KinD Kubernetes environment
│   │   ├── storage/                      # Persistent Moodle storage
│   │   │   └── moodle-storage.yaml       # Persistent storage configuration
│   │   │
│   │   ├── mysql/                        # MySQL database
│   │   │   ├── deployment.yaml           # MySQL deployment definition
│   │   │   └── service.yaml              # Internal Kubernetes service for MySQL
│   │   │
│   │   ├── php/                          # PHP-FPM Moodle application
│   │   │   ├── deployment.yaml           # PHP-FPM application deployment
│   │   │   └── service.yaml              # Internal service exposing PHP-FPM
│   │   │
│   │   ├── nginx/                        # Nginx reverse proxy
│   │   │   ├── configmap.yaml            # Nginx configuration
│   │   │   ├── deployment.yaml           # Nginx reverse proxy deployment
│   │   │   └── service.yaml              # Internal service exposing Nginx
│   │   │
│   │   └── overlays/                     # KinD-specific configuration
│   │       ├── ingress.yaml              # Local ingress configuration
│   │       ├── kind-config.yaml          # KinD cluster and node configuration
│   │       └── kustomization.yaml        # Kustomize configuration for KinD
│   │ 
│   ├── gcp-gke/                          # Google Kubernetes Engine environment
│   │   ├── storage/                      # Persistent Moodle storage
│   │   │   ├── moodle-storage.yaml       # PersistentVolumeClaim definitions for Moodle data
│   │   │   └── kustomization.yaml        # Kustomize configuration for GKE storage
│   │   │
│   │   ├── mysql/                        # MySQL database
│   │   │   ├── deployment.yaml           # MySQL deployment definition
│   │   │   ├── service.yaml              # Internal Kubernetes service for MySQL
│   │   │   └── kustomization.yaml        # Kustomize configuration for GKE MySQL  
│   │   │
│   │   ├── php/                          # PHP-FPM Moodle application
│   │   │   ├── deployment.yaml           # PHP-FPM application deployment
│   │   │   ├── service.yaml              # Internal service exposing PHP-FPM
│   │   │   └── kustomization.yaml        # Kustomize configuration for GKE PHP   
│   │   │
│   │   ├── nginx/                        # Nginx reverse proxy
│   │   │   ├── configmap.yaml            # Nginx configuration
│   │   │   ├── deployment.yaml           # Nginx reverse proxy deployment
│   │   │   ├── service.yaml              # Internal service exposing Nginx
│   │   │   ├── backendconfig.yaml        # GKE load balancer health-check configuration
│   │   │   └── kustomization.yaml        # Kustomize configuration for GKE Nginx  
│   │   │
│   │   └── overlays/                     # GKE-level configuration
│   │       ├── ingress.yaml              # GKE Ingress configuration for external access
│   │       ├── kustomization.yaml        # Kustomize configuration for GKE Ingress  
│   │       └── managed-cert.yaml         # Google-managed SSL/TLS certificate
│   │
│   ├── openshift/                        # Local OpenShift Environment
│   │    ├── kustomization.yaml           # Base Kustomize configuration
│   │    ├── images/                      # Dockerfile for Moodle initialization image
│   │    │
│   │    ├── storage/                     # Persistent Moodle storage for OpenShift
│   │    │   ├── moodle-storage.yaml      # PVC leveraging OpenShift StorageClasses
│   │    │   └── kustomization.yaml       # Storage component kustomization
│   │    │
│   │    ├── mysql/                       # MySQL database
│   │    │   ├── deployment.yaml          # MySQL deployment
│   │    │   ├── service.yaml             # Internal MySQL service
│   │    │   └── kustomization.yaml       # MySQL component kustomization
│   │    │
│   │    ├── php/                         # PHP-FPM Moodle application
│   │    │   ├── deployment-patch.yaml    # Injects the ServiceAccountName to pass SCC rules
│   │    │   ├── serviceaccount.yaml      # Grants your init container execution rights
│   │    │   ├── service.yaml             # Internal PHP service
│   │    │   └── kustomization.yaml       # PHP component kustomization
│   │    │
│   │    ├── nginx/                       # Nginx reverse proxy
│   │    │   ├── configmap.yaml           # Nginx configuration
│   │    │   ├── deployment.yaml          # Nginx deployment
│   │    │   ├── service.yaml             # Internal Nginx service
│   │    │   └── kustomization.yaml       # Pulls base Nginx files
│   │    │
│   │    └── overlays/                    # Cluster-wide networking configuration
│   │        ├── route.yaml               # OpenShift Route for external HTTPS access to Nginx
│   │        └── kustomization.yaml       # Route component kustomizati
│   │
│   └── azure-aro/                        # P5: Azure Red Hat OpenShift deployment
│        ├── kustomization.yaml           # Base Kustomize configuration
│        ├── images/                      # Dockerfile for Moodle initialization image
│        │
│        ├── storage/                     # Persistent Moodle storage for OpenShift
│        │   ├── moodle-storage.yaml      # Azure-backed persistent storage for Moodle and MySQL
│        │   └── kustomization.yaml       # Storage component kustomization
│        │ 
│        ├── mysql/                       # MySQL database
│        │   ├── deployment.yaml          # MySQL deployment
│        │   ├── service.yaml             # Internal MySQL service
│        │   └── kustomization.yaml       # MySQL component kustomization
│        │
│        ├── php/                         # PHP-FPM Moodle application
│        │   ├── deployment.yaml          # PHP-FPM deployment and Moodle initialization
│        │   ├── service.yaml             # Internal PHP-FPM service
│        │   └── kustomization.yaml       # PHP component kustomization
│        │
│        ├── nginx/                       # Nginx reverse proxy
│        │   ├── configmap.yaml           # Nginx configuration
│        │   ├── deployment.yaml          # Nginx deployment
│        │   ├── service.yaml             # Internal Nginx service
│        │   └── kustomization.yaml       # Nginx component kustomization
│        │
│        └── overlays/                    # ARO-specific configuration
│            ├── route.yaml               # OpenShift Route for external HTTPS access to Nginx
│            └── kustomization.yaml       # Route component kustomization
│
├── terraform/                            # Google Cloud and Azure infrastructure provisioning
│   ├── docker-compose/                   # P1: GCP VM infrastructure for Docker Compose
│   │   ├── deploy.sh                     # Docker deployment script
│   │   ├── main.tf                       # Compute Engine and firewall resources
│   │   ├── outputs.tf                    # Terraform outputs
│   │   ├── providers.tf                  # Google provider configuration
│   │   ├── startup.sh                    # VM startup and application deployment
│   │   └── variables.tf                  # Terraform variables
│   │
│   ├── gcp-gke/                          # P3: GCP infrastructure for GKE
│   │   ├── main.tf                       # GKE, Artifact Registry, static IP, and APIs
│   │   ├── outputs.tf                    # GKE infrastructure outputs
│   │   ├── providers.tf                  # Google provider configuration
│   │   └── variables.tf                  # GCP project, region, and zone variables
│   │
│   └── azure-aro/                        # P5: Azure Red Hat OpenShift infrastructure
│       ├── main.tf                       # ARO cluster, networking, and Azure resources
│       ├── outputs.tf                    # Azure infrastructure outputs
│       ├── providers.tf                  # Azure provider configuration
│       └── variables.tf                  # ARO cluster and Azure configuration variables
│
├── Dockerfile                            # Root custom PHP application image build
├── README.md                             # Project overview and deployment documentation
└── .gitignore                            # Git ignore rules
```
---

## Project Documentation

To keep the repository organized, deployment guides and troubleshooting notes are maintained separately:

* 📄 **[GCP Terraform Deployment Guide](./docs/gcp_terraform_deploy.md)**
* 📄 **[P1 Docker Deployment Guide](./docs/p1_docker_deploy.md)**
* 📄 **[P1 Post-Mortem](./docs/p1_post_mortem.md)**
* 📄 **[P2 Kubernetes Deployment Guide](./docs/p2_k8_deploy.md)**
* 📄 **[P2 Kubernetes Post-Mortem](./docs/p2_post_mortem.md)**
* 📄 **[P3 GCP-GKE Deployment Guide](./docs/p3_k8_deploy.md)**
* 📄 **[P5 Azure-ARO Deployment Guide](./docs/p5_k8_deploy.md)**
* 📄 **[P5 Azure-ARO Post-Mortem](./docs/p5_post_mortem.md)**

---

# Infrastructure Evolution

This project demonstrates the progressive design and evolution of a stateful application platform across containerized, Kubernetes, and cloud-native infrastructure.

Rather than treating each environment as a separate deployment, the same Moodle application architecture is carried through every phase—from Docker Compose on a Google Cloud VM, to a customized multi-node KinD cluster, to a multi-node GKE platform, and ultimately to AWS/EKS. Each phase introduces additional infrastructure capabilities while preserving the application's core architecture and persistent data requirements.

The project covers application decomposition, containerization, Kubernetes orchestration, persistent storage, networking and ingress, infrastructure as code, cloud services, identity and security, and CI/CD automation.


## Phase 1 – Docker Compose Deployment on GCP

### Goal
Design and deploy the initial stateful application architecture on Google Cloud, establishing the container, networking, and persistence model that would become the foundation for the later Kubernetes implementations.

Instead of using a pre-built Moodle container, the application was decomposed into separate services with clearly defined responsibilities. Nginx provides the web-facing HTTP layer and routes PHP requests to a custom PHP-FPM application runtime. MySQL provides the database layer, backed by persistent storage to preserve database state across container recreation. Docker Compose defines the service relationships, internal networking, persistent storage, and application configuration.

Terraform provisioned the underlying Linux Compute Engine infrastructure, including the VM and supporting network and firewall configuration.

### Result
Built and deployed a complete stateful Moodle stack on Google Cloud with independently managed application, web, and database services.

The deployment established the core architecture used throughout the project: separation of application components, custom image construction, persistent application and database data, service networking, infrastructure provisioning, and external web access.

Rather than being replaced in later phases, this architecture became the baseline that was progressively adapted to Kubernetes and cloud-native infrastructure.

---

## Phase 2 – Multi-Node Kubernetes Deployment with KinD

### Goal
Transform the containerized architecture from Phase 1 into a Kubernetes-native deployment while preserving the same separation between the Nginx web layer, PHP-FPM application runtime, MySQL database, and persistent application data.

A customized local multi-node KinD cluster was built with a control-plane and worker node, creating a more realistic Kubernetes environment than a default single-node cluster. Application components were translated from Docker Compose services into Kubernetes Deployments and Services, using Persistent Volume Claims, Secrets, ConfigMaps, and an init container for storage, configuration, credentials, and application initialization.

Ingress was deliberately scheduled on the worker node and integrated with the host network to provide external HTTPS access from Windows 11/WSL2 into the Kubernetes environment.

### Result
Built and validated a complete stateful application stack on a multi-node Kubernetes cluster, including:

* **Multi-node cluster architecture** – separate control-plane and worker node with workload and ingress placement configured on the worker
* **Kubernetes workload decomposition** – Nginx, PHP-FPM, and MySQL implemented as independently managed workloads and services
* **Persistent state management** – application and database data retained across pod deletion and recreation
* **Application initialization** – init container prepares Moodle application files on persistent storage before runtime startup
* **Configuration and secrets management** – Kubernetes ConfigMaps and Secrets separate application configuration and credentials from workloads
* **Ingress and network routing** – external traffic routed through Kubernetes Ingress to Nginx and then internally to PHP-FPM
* **Workload recovery validation** – pods deliberately recreated to confirm Kubernetes recovery behavior and persistence
* **End-to-end application validation** – verified web access, authentication, database connectivity, HTTPS access, and persistent file uploads

Phase 2 demonstrated that the architecture established with Docker Compose could be successfully decomposed into Kubernetes resources while maintaining application functionality and persistent state. It also established the Kubernetes architecture that would be carried forward into GKE in Phase 3.

---

## Phase 3 – Managed Kubernetes Deployment on GKE

### Goal
Evolve the architecture proven in the local multi-node KinD environment into a fully integrated GKE platform. The objective was not simply to run Moodle on Kubernetes, but to carry the same stateful application architecture into Google Cloud while solving the infrastructure, storage, networking, security, recovery, and deployment requirements of a cloud Kubernetes environment.

The platform maintains clearly separated Nginx, PHP-FPM, and MySQL workloads rather than relying on a pre-built Moodle image. Nginx provides the web-facing HTTP layer, receiving application traffic and routing PHP requests to PHP-FPM over the Kubernetes service network. A custom PHP-FPM image provides the Moodle application runtime, while MySQL provides the database layer, backed by persistent storage to preserve database state across pod recreation. The init container prepares the Moodle application files on shared persistent storage before the application starts, while persistent application storage preserves application and user data across workload recreation.

Terraform provisions the GKE and supporting Google Cloud infrastructure, while Kustomize manages reusable and environment-specific Kubernetes configuration.

### Result
Built, integrated, and validated an end-to-end multi-node GKE platform spanning application workloads, persistent storage, cloud networking, infrastructure automation, identity, security, and recovery:

### Result

Built and validated a complete stateful application stack on a multi-node Kubernetes cluster, including:

* **Multi-node cluster architecture** – separate control-plane and worker nodes, with application workloads and the Ingress controller scheduled on the worker
* **Custom application image deployment** – built the custom PHP-FPM 8.2 image with the required Moodle PHP extensions and loaded it directly into the KinD cluster for deployment
* **Kubernetes workload decomposition** – Nginx, PHP-FPM, and MySQL implemented as independently managed Kubernetes workloads and services
* **Persistent storage** – persistent volumes configured for Moodle application files, Moodle data, and the MySQL database
* **MySQL persistence validation** – database state retained across MySQL pod deletion and recreation, confirming that application data was independent of the pod lifecycle
* **Application initialization** – init container prepares Moodle application files on persistent storage before runtime startup
* **Configuration and secrets management** – Kubernetes ConfigMaps and Secrets separate application configuration and credentials from workloads
* **Ingress and network routing** – external traffic routed through Kubernetes Ingress to Nginx and then internally to PHP-FPM
* **Workload recovery validation** – pods deliberately recreated to confirm Kubernetes recovery behavior while maintaining application state
* **End-to-end application validation** – verified web access, authentication, database connectivity, and persistent file uploads

Phase 2 demonstrated that the architecture established with Docker Compose could be successfully decomposed into Kubernetes resources while maintaining application functionality and persistent state. It also established the Kubernetes architecture that would be carried forward into GKE in Phase 3.

### Engineering Outcome
The result is more than a Moodle deployment. The same stateful application has been progressively engineered from Docker Compose, through a customized multi-node local Kubernetes cluster, and into an integrated cloud Kubernetes platform.

The GKE implementation demonstrates not only successful deployment, but also **system integration and operational behavior**: application components communicate across defined service boundaries, state survives workload replacement, Kubernetes restores deleted workloads, external traffic traverses the complete ingress path, and the application remains functional after recovery.

Across the three phases, the project demonstrates system decomposition, component integration, state and lifecycle management, infrastructure as code, cloud networking, secure identity, failure recovery, and repeatable deployment practices.

### Current Work
Complete and validate the end-to-end GitHub Actions deployment workflow, including infrastructure provisioning, container image build and push, Kubernetes deployment, rollout verification, and end-to-end application validation.

---
## Phase 4 – Kubernetes Platform on Red Hat OpenShift

### Goal
Extend the architecture proven on GKE to Red Hat OpenShift and demonstrate that the same stateful application design can be adapted across Kubernetes platforms without replacing the underlying workload architecture. The objective was to preserve the separation of Nginx, PHP-FPM, and MySQL while adapting storage, container security, image builds, networking, and application configuration to OpenShift-specific platform requirements.

The deployment was built and validated on the Red Hat Developer Sandbox, providing a managed OpenShift environment for adapting and testing the existing Kubernetes architecture. Existing GKE Kubernetes manifests were carried forward and modified only where platform differences required it, demonstrating application portability while exposing assumptions that had worked on GKE but were incompatible with OpenShift.

The platform continues to use separate Nginx, PHP-FPM, and MySQL workloads, persistent application and database storage, and an init container that seeds and manages the Moodle application files and `moodledata` persistent storage before the PHP-FPM workload starts. OpenShift Routes replace GKE Ingress for external application access, with edge TLS termination providing the HTTPS endpoint.
### Result
Built, adapted, and validated the existing Kubernetes application architecture on Red Hat OpenShift while preserving the workload and persistence model established in the earlier phases:

* **Migrated the existing Kubernetes architecture to OpenShift** – retained separate Nginx, PHP-FPM, and MySQL workloads rather than redesigning the application around an OpenShift-specific deployment model
* **Adapted workloads to OpenShift security constraints** – removed fixed-UID and root assumptions exposed by the `restricted-v2` Security Context Constraint and validated workloads using OpenShift-assigned non-root identities
* **Built application images natively within OpenShift** – used BuildConfigs and ImageStreams to build and manage the custom PHP-FPM and Moodle initialization images within the platform
* **Adapted the Moodle initialization process** – replaced runtime package installation with a purpose-built init image compatible with OpenShift's restricted container security model
* **Implemented OpenShift-compatible persistent storage** – used shared RWX storage for Moodle application files and RWO storage for Moodle data and MySQL while preserving state across pod replacement
* **Integrated OpenShift application networking** – connected the OpenShift Route to the Nginx Service using a named service port, with Nginx listening on unprivileged port 8080
* **Established HTTPS using OpenShift edge TLS termination** – configured the Route for TLS termination and HTTP-to-HTTPS redirection while adapting Moodle's proxy configuration for operation behind the OpenShift router
* **Validated end-to-end application routing** – confirmed traffic traverses the OpenShift router, Nginx Service, Nginx workload, PHP-FPM service boundary, Moodle application, and MySQL database
* **Validated workload recovery and persistent state** – deliberately deleted the PHP workload and confirmed OpenShift recreated it while preserving Moodle configuration, HTTPS configuration, application data, and database connectivity
* **Validated database recovery** – deliberately recreated the MySQL workload and verified that the persistent database and Moodle tables remained intact
* **Maintained repeatable Kubernetes configuration with Kustomize** – preserved the existing repository structure while isolating OpenShift-specific manifests and configuration
* **Automated Moodle configuration and validation** – adapted the deployment tooling to retrieve OpenShift service and Route information, perform the Moodle CLI installation, configure reverse-proxy behavior, and verify persistence and external application access

### Engineering Outcome
The OpenShift implementation demonstrates that the application architecture is portable across Kubernetes distributions while also showing that portability does not mean deploying identical manifests unchanged.

Moving from GKE to OpenShift exposed platform-specific differences in container security, storage behavior, image management, service routing, TLS termination, and runtime permissions. Rather than weakening OpenShift security controls or replacing the application architecture, the workloads were adapted to operate within the platform's constraints.

The resulting deployment preserves the same architectural path established in the earlier phases:

**OpenShift Route → Nginx → PHP-FPM → MySQL**

while using OpenShift-native capabilities for image builds, routing, security enforcement, and TLS.

This phase extends the project from Kubernetes deployment into **cross-platform Kubernetes engineering**: identifying platform assumptions, adapting workloads to a stricter security model, troubleshooting service and Route integration, validating persistent state through workload failure and recovery, and maintaining a repeatable architecture across local Kubernetes, GKE, and OpenShift.

The OpenShift implementation also provides a practical foundation for a future Azure Red Hat OpenShift (ARO) deployment, where the same workload architecture and OpenShift-specific adaptations can be carried forward into a managed Azure environment.

---

## Phase 5 – Azure Red Hat OpenShift (ARO)

### Goal
Extend the OpenShift architecture validated in Phase 4 to Azure Red Hat OpenShift (ARO), demonstrating how the existing stateful Kubernetes application can be deployed into an Azure-managed OpenShift environment without redesigning the underlying workload architecture.

The objective was to preserve the separation of Nginx, PHP-FPM, and MySQL while integrating Azure infrastructure provisioning, container image management, persistent storage, networking, and OpenShift application deployment.

Terraform was introduced to provision the ARO infrastructure, while Azure Container Registry replaced OpenShift ImageStreams as the source for custom application images. The existing Kubernetes manifests were adapted for Azure-specific storage and registry requirements, retaining the OpenShift deployment model established in the Developer Sandbox.

### Result
Provisioned and deployed the existing Moodle application architecture on Azure Red Hat OpenShift, extending the OpenShift implementation into an Azure-managed environment:

* **Provisioned ARO infrastructure using Terraform** – configured the Azure resource group, virtual networking, subnets, and managed OpenShift cluster in Central US, using the available regional vCPU quota
* **Configured Azure service principal authentication** – established the identities and Azure permissions required for ARO provisioning, including resource-provider access to the virtual network
* **Integrated Azure Container Registry (ACR)** – built the custom PHP-FPM and Moodle initialization images from their Dockerfiles and published them to ACR for deployment into ARO
* **Configured private container image access** – established registry pull permissions and OpenShift image-pull credentials to allow application workloads to retrieve images from ACR
* **Adapted persistent storage to Azure** – configured Azure File CSI storage for shared Moodle application files and Azure Disk CSI storage for Moodle data and MySQL, preserving the existing RWX and RWO storage requirements
* **Preserved the existing OpenShift workload architecture** – deployed separate MySQL, PHP-FPM, and Nginx workloads using Kustomize, retaining the Moodle initialization container and internal service communication
* **Integrated OpenShift application networking** – retained OpenShift Routes for external application access, with Nginx operating on an unprivileged port
* **Managed application credentials through Kubernetes Secrets** – separated database and application credentials from version-controlled deployment manifests
* **Troubleshot Azure-specific deployment dependencies** – resolved infrastructure provisioning permissions, persistent storage configuration, registry authentication, and missing Kubernetes Secrets
* **Validated application deployment and persistence** – confirmed the Moodle application was operational on ARO and that persistent application data survived workload replacement
* **Investigated OpenShift container security behavior** – identified PHP-FPM and MySQL running as root despite the non-root behavior observed in the Developer Sandbox, prompting further investigation into namespace selection, deployment permissions, and SCC enforcement
* **Managed infrastructure lifecycle and cloud costs** – used Terraform to provision and remove the ARO environment, with additional state reconciliation required when cluster provisioning completed after a Terraform timeout

### Engineering Outcome
The Azure Red Hat OpenShift implementation demonstrates that the application architecture developed across Docker Compose, KinD, GKE, and the OpenShift Developer Sandbox can be carried forward into a managed Azure environment while preserving the separation of application workloads and persistent storage.

Moving from the Developer Sandbox to ARO introduced additional infrastructure responsibilities, including Azure resource provisioning, service principal permissions, container registry authentication, and Azure-backed storage. These differences required changes to the supporting infrastructure and deployment configuration rather than a redesign of the Moodle application.

The deployment retained the established application path:

**OpenShift Route → Nginx → PHP-FPM → MySQL**

while integrating Azure-native infrastructure and container image services with OpenShift application orchestration.

The deployment also exposed a container security difference requiring further validation. Although the application was operational and persistent storage was functioning, PHP-FPM and MySQL were observed running as root. A dedicated OpenShift project and stricter deployment security configuration were identified for subsequent validation rather than treating the working deployment as fully compliant with the intended non-root security model.

This phase extends the project into **multi-cloud Kubernetes infrastructure engineering**: provisioning managed OpenShift infrastructure through Terraform, integrating external container registries, adapting persistent storage to cloud-provider capabilities, troubleshooting infrastructure and application dependencies, and managing the lifecycle of a resource-intensive cloud environment.

Together, the five phases demonstrate the progression from containerized application deployment to portable Kubernetes architecture, OpenShift platform adaptation, and managed infrastructure provisioning across Google Cloud and Microsoft Azure.