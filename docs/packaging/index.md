# GitLab Packages

GitLab Packages (`gitlab-packages`) deploys a package hosting infrastructure (currently DEB and RPM) via Google Cloud Platform. The infrastructure is *mostly* service-free and uses Google Cloud CDN load balancers in front of Google Cloud Storage buckets to host repositories.

Access to package repositories is directly via the load balancer over HTTPS, using a URL map to direct requests to the correct bucket and path. Public repositories are directly accessed and cached via the CDN. Access to private repositories requires HTTP Basic authentication for read access, and requests are initially directed to a service which authenticates the user and returns a redirect to a signed URL on success. Requests to private repositories are not cached to prevent unintentionally allowing unauthorized access.

Packages are delivered to a triggered pipeline in `gitlab-packages`, which After packages are copied to the desttination bucket and folder, repository metadata is generated using a tool in a container from the `gitlab-package-tools` project.

GCP Project: `distrib-gl-packages-a81393c3`
Current maturity level: *Experiment*

Note: the `test`, `internal`, and `prod` environments described below are produced by the same Terraform configuration. They are all functionally identical and differ only in names and network addresses.

## Experiment

### Service Catalog

_The items below will be reviewed by Scalability:Practices team._

- [ ] Link to the [service catalog entry](https://gitlab.com/gitlab-com/runbooks/-/tree/master/services) for the service. Ensure that the all of the fields are populated.

### Infrastructure

_The items below will be reviewed by the Scalability:Practices team._

- [ ] Do we use IaC (e.g., Terraform) for all the infrastructure related to this feature? If not, what kind of resources are not covered?
  - We have a dedicated project for all related IaC and automation: https://gitlab.com/gitlab-org/distribution/build-architecture/framework/foundation/gitlab-packages
  - A separate project is used to produce a packaging tools container that builds packages and package repositories, which is used in the publishing automation: https://gitlab.com/gitlab-org/distribution/build-architecture/framework/foundation/gitlab-package-tools
- [ ] Is the service covered by any DDoS protection solution (GCP/AWS load-balancers or Cloudflare usually cover this)?
  - The service is fronted by a dual-stack GCP global load balancer (included in the Terraform code).
  - The backend services for the public storage bucket and BlobSigner have firewalls with a basic rate-limiting rule.
- [ ] Are all cloud infrastructure resources labeled according to the [Infrastructure Labels and Tags](https://about.gitlab.com/handbook/infrastructure-standards/labels-tags/) guidelines?
  - Yes. This is included in the Terraform code.

#### Other infrastructure notes
ADRs for the design are available in the [Build Architecture Documentation](https://gitlab.com/gitlab-org/distribution/build-architecture/documentation/-/tree/main/architecture-decision-records/packager?ref_type=heads) project. When we go public with the project, these will need to be moved to the public [Engineering Design Documents](https://gitlab.com/gitlab-com/content-sites/handbook/-/tree/main/content/handbook/engineering/architecture/design-documents) repository.

- Availability:
  - To prevent a circular dependency on `gitlab.com` for producing and publishing packages, the project will be mirrored on `ops.gitlab.com`, which will run the CI and integrate with GCP via OAuth.
  - All services are accessed via a dual-stack GCP global load balancer using global anycast IP addresses for shorter, regional network routes.
  - We are using multi-regional GCS Cloud Storage buckets (`US` regions) to maintain replicas of stored content.
  - The BlobSigner service (available via the load balancers) is deployed to multiple geographic regions. These regions are all "core" GCP regions which would be available in cases of a critical GCP outage.
    - `europe-west1`
    - `us-west1`
    - `us-central1`
    - `europe-north1`
- Scalability:
  - GCP global load balancer: globally scaled by design.
  - BlobSigner 
    - Has a health-check route (`/healthz`) that also checks whether correct IAM policies are set up for the service
    - Is available behind the load balancer, which is configured with health checks
    - Auto-scales based on instance utilization
    - Ensures a minimum number of healthy instances are available during deployment

### Operational Risk

_The items below will be reviewed by the Scalability:Practices team._

- [ ] List the top three operational risks when this feature goes live.
  - The BlobSigner service could fail to start and/or have a runtime error which prevents access to private package repositories.
  - Unknown and unpredictable external dependencies (customer scripts, customer firewalls, using http access to retrieve packages, etc.) could prevent access to the new repositories or cause errors when we switch over.
  - GCP global load balancers could be misconfigured and not match the structure used by PackageCloud at `packages.gitlab.com`.
- [ ] For each component and dependency, what is the blast radius of failures? Is there anything in the feature design that will reduce this risk?
  - GCP Cloud Storage
    - Critical blast radius (packages are not available at all)
    - Mitigations by design
      - Public access is prevented - only available via load balancers
      - Load balancers have CDN caching enabled
      - Bucket names contain a random component to prevent "name squatting" and unintentional direct access (which could increase billing)
      - Are multi-regional (`US` regions) and automatically replicate to multiple geographic locations
  - GCP global load balancers
    - High blast radius (prevents access to the packages via the "easy" DNS names)
    - Mitigations by design
      - Uses GCP core infrastructure, which is expected to be available during a critical GCP outage
      - Is dual-stack to increase network availability via multiple routes
      - Uses global anycast addreses to shorten network routes and limit impacts of external network outages to specific regions
  - BlobSigner
    - Low blast radius (private packages cannot be retrieved via the load balancer)
    - Mitigations by design
      - Has a health-check route that includes checking whether authentication should work
      - Is only available via the load balancer
      - Load balancer uses health checks to ensure only healthy instances receive traffic
      - Deployments are configured to ensure a minimum number of healthy instances
      - Logs are available to identify the source of problems
      - Can be instantiated locally for detailed trace logging to the local workstation (may contain sensitive data)

### Monitoring and Alerting

_The items below will be reviewed by the Scalability:Practices team._

- [ ] Link to the [metrics catalog](https://gitlab.com/gitlab-com/runbooks/-/tree/master/metrics-catalog/services) for the service

### Deployment

_The items below will be reviewed by the Delivery team._

- [ ] Will a [change management issue](https://about.gitlab.com/handbook/engineering/infrastructure/change-management/) be used for rollout? If so, link to it here.
  - We will not use a Change Management issue for initial rollout of the production infrastructure because it will not be public yet.
  - We will not use a Change Management issue for internal onboarding because only package publishing is affected (which is a small number of pipelines) and a revert MR in the affected projects will resolve the problem.
  - We may need a Change Management issue to change the `packages.gitlab.com` DNS record to point to the new infrastructure when we are ready to make the new repositories public.
- [ ] Can the new product feature be safely rolled back once it is live, can it be disabled using a feature flag?
  - The project uses GitLab environments linked to Terraform state, so we can use the environment rollback feature.
- [ ] How are the artifacts being built for this feature (e.g., using the [CNG](https://gitlab.com/gitlab-org/build/CNG/) or another image building pipeline).
  - Package Tools: used to build packages and generate package repositories during the publishing automation
    - Container is built in a dedicated project: https://gitlab.com/gitlab-org/distribution/build-architecture/framework/foundation/gitlab-package-tools
    - Used in the `gitlab-packages` pipeline to generate package repository metadata
  - BlobSigner
    - Cloud Run Function container built by GCP from source archive in the `test-gcf-gitlab-packages-5345da93d24c1a97` bucket
    - Deployed by `gitlab-packages` during Terraform deployment

### Security Considerations

_The items below will be reviewed by the Infrasec team._

- [ ] Link or list information for new resources of the following type:
  - GCP Project: `distrib-gl-packages-a81393c3`
  - New Subnets: GCP default for project
  - VPC/Network Peering: N/A
  - DNS names: `gitlab-packages.com`
    - `test.gitlab-packages.com`: "alpha" for testing infrastructure changes
    - `internal.gitlab-packages.com`: publishing point for internal-only packages (nightly, pre-release)
    - `prod.gitlab-packages.com`: CNAME of `packages.gitlab.com`
  - Entry-points exposed to the internet (Public IPs, Load-Balancers, Buckets, etc...):
    - GCP global load balancer (dual-stack):
      - `test`
        - IPv4: `34.8.144.79`
        - IPv6: `2600:1901:0:773c::`
        - acceses `test-gitlab-packages-public-a68289e45e3fda1c` via HMAC keys
      - `internal`: TBD
      - `prod`: TBD
    - GCP Cloud Storage buckets (public access disabled, uniform ACLs):
      - `test`
        - `test-gcf-gitlab-packages-5345da93d24c1a97`: GCP Cloud Run Function source archives
        - `test-gitlab-packages-private-897a6e41ebf24f17`: private repositories (nightly, pre-release)
        - `test-gitlab-packages-public-a68289e45e3fda1c`: public repositories
      - `internal`: TBD
      - `prod`: TBD
    - GCP Cloud Run Functions:
      - `test`
        - `test-blobsigner`
          - accessed via the GCP load balancer (only internal traffic is allowed)
          - accepts HTTP Basic logins
          - uses a dedicated service account limited to read-only access to sign a storage blob URL
          - returns storage blob URL via 302 redirect
      - `internal`: TBD
      - `prod`: TBD
  - Other (anything relevant that might be worth mention):
    - GCP global load balancers are only accessible via HTTPS (no redirects from HTTP). This is to prevent accidental credential exposure via an unencrypted channel and to prevent MITM attacks.
- [ ] Were the [GitLab security development guidelines](https://docs.gitlab.com/ee/development/secure_coding_guidelines.html) followed for this feature?
  - Yes. The Terraform code is mostly not applicable to the guidelines, but the Python code written for BlobSigner was written according to the guidelines.
- [ ] Was an [Application Security Review](https://handbook.gitlab.com/handbook/security/security-engineering/application-security/appsec-reviews/) requested, if appropriate? Link it here.
- [ ] Do we have an automatic procedure to update the infrastructure (OS, container images, packages, etc...). For example, using unattended upgrade or [renovate bot](https://github.com/renovatebot/renovate) to keep dependencies up-to-date?
  - Cloud Run Functions: 
    - A scheduled pipeline runs periodically to update `uv` dependencies and pin them
    - Every scheduled pipeline run, the new container is rebuilt, published, and deployed
  - Package Tools
    - Base container version is not pinned.
    - Dependency versions are not pinned.
    - Packages in the base image are updated during the container build.
    - Will be rebuilt and published via a scheduled pipeline to keep them updated.
  - Other dependencies are mainly developer-focused and are maintained via `mise`. In the rare instance a CVE impacts one of these dependencies, we will update it manually to prevent a breaking change.
- [ ] For IaC (e.g., Terraform), is there any secure static code analysis tools like ([kics](https://github.com/Checkmarx/kics) or [checkov](https://github.com/bridgecrewio/checkov))? If not and new IaC is being introduced, please explain why.
- [ ] If we're creating new containers (e.g., a Dockerfile with an image build pipeline), are we using `kics` or `checkov` to scan Dockerfiles or [GitLab's container](https://docs.gitlab.com/ee/user/application_security/container_scanning/#configuration) scanner for vulnerabilities?
  - Cloud Run Functions are built in a container provided by Google.
  - Automated container scanning is enabled for published Cloud Run Functions in the Terraform code. 

### Identity and Access Management

_The items below will be reviewed by the Infrasec team._

- [ ] Are we adding any new forms of Authentication (New service-accounts, users/password for storage, OIDC, etc...)?
  - `sa-gitlab-oidc-61583905`: administrative service account able to perform all actions required by automation
  - OIDC integration between the `gitlab-packages` project and a GCP Workload Identity Federation pool.
    - Pool ID: `gitlab-oidc-pool-61583905`
    - Connected service account: `sa-gitlab-oidc-61583905`
    - Attribute conditions: `attribute.project_id == "61583905"`
  - `sa-automation`: service account used by Delivery team to retrieve read-only HTTP Basic credentials from GCP Secret Manager
  - `gl-delivery`: service account used by CI pipelines to assume other service accounts:
    - All environments 
      - `sa-automation`: assumed during Terraform operations
    - `test`
      - `sa-test-private-bucket-writer`: assumed when publishing private packages
      - `sa-test-public-bucket-writer`: assumed when publishing public packages
    - `internal`: TBD
    - `prod`: TBD
  - PGP keys are stored in GCP Secrets Manager and encrypted by a CMK:
    - `test`
      - `test-pgp-pkgkey`: Package signing key
      - `test-pgp-pkgkey-passphrase`: Decryption passphrase for package signing key
      - `test-pgp-repokey`: Repository signing key
      - `test-pgp-repokey-passphrase`: Decryption passphrase for repository sining key
    - `internal`: TBD
    - `prod`: TBD
  - GCP Cloud Storage buckets are accessed by service accounts with restricted privileges:
    - `test`
      - `test-gcf-gitlab-packages-5345da93d24c1a97`: GCP Cloud Run Function source archives
      - `test-gitlab-packages-private-897a6e41ebf24f17`: private repositories (nightly, pre-release)
        - `sa-test-private-bucket-reader`: service account used for read-only access
        - `sa-test-private-bucket-writer`: service account used for read-write access
        - `sa-test-private-url-signer`: service account with read-only access used to sign object blob URLs
      - `test-gitlab-packages-public-a68289e45e3fda1c`: public repositories
        - `sa-test-public-bucket-reader`: service account used for read-only access
        - `sa-test-public-bucket-writer`: service account used for read-write access
    - `internal`: TBD
    - `prod`: TBD
  - GCP Cloud Functions:
    - `test`
      - `test-blobsigner`
        - Service account identity: `sa-test-private-bucket-reader@distrib-gl-packages`
        - Assumes `sa-test-private-url-signer` to sign object blob URLs
    - `internal`: TBD
    - `prod`: TBD
  - Upon deployment to `prod`, all users added to the project will be de-privileged and will only have access via the following mechanism:
    - Must have an OIDC token from `ops.gitlab.com`
    - Must be added to Terraform automation to allow access
    - Must assume roles using `gcloud` functionality to perform actions
- [ ] Was effort put in to ensure that the new service follows the [least privilege principle](https://en.wikipedia.org/wiki/Principle_of_least_privilege), so that permissions are reduced as much as possible?
  - Terraform IaC de-privileges all default service accounts.
  - Upon deployment to `prod`, all GitLab users are de-privileged.
  - Only necessary GCP service APIs are enabled in IaC code.
  - Service accounts have only the permissions required to perform a single task.
  - Default access permissions are restricted to viewing configuration.
  - Only permitted principals may assume another service account.
  - Elevated access permissions can only be gained by assuming the appropriate service account.
  - Only one service account (`sa-automation`) has full administrative privileges and has no long-term credentials.
  - Only the GitLab CI service account may assume the `sa-automation` service account unless otherwise configured in IaC.
- [ ] Do firewalls follow the least privilege principle (w/ network policies in Kubernetes or firewalls on cloud provider)?
  - The only "service" running outside of GitLab is `blobsigner`, which only has read-only access to private package repositories.
  - The `blobsigner` service is restricted to internal network access (via load balancers) only. 
- [ ] Is the service covered by a [WAF (Web Application Firewall)](https://cheatsheetseries.owasp.org/cheatsheets/Secure_Cloud_Architecture_Cheat_Sheet.html#web-application-firewall) in [Cloudflare](https://gitlab.com/gitlab-com/runbooks/-/tree/master/docs/cloudflare#how-we-use-page-rules-and-waf-rules-to-counter-abuse-and-attacks)?
  - Yes. Basic firewalls with simple rate-limit rules are enabled on the public bucket and BlobSigner backend services.
  - The basic firewall in front of BlobSigner should be updated with more comprehensive rules based on AppSec review.

### Logging, Audit and Data Access

_The items below will be reviewed by the Infrasec team._

- [ ] Did we make an effort to redact customer data from logs?
  - The only component which creates logs is BlobSigner.
  - Logs only contain generic error information by default:
    - The type of failure
    - Origin IP address
    - Accessed path
  - Trace logs can be enabled via a local instance with the `TRACE=1` environment variable set.
- [ ] What kind of data is stored on each system (secrets, customer data, audit, etc...)?
  - GCP Key Management
    - `test`
      - `test-keyring-pgp` encrypts
        - `test-pgp-pkgkey`: Package signing key
        - `test-pgp-pkgkey-passphrase`: Decryption passphrase for package signing key
        - `test-pgp-repokey`: Repository signing key
        - `test-pgp-repokey-passphrase`: Decryption passphrase for repository sining key
      - `test-keyring-blobsigner`: encrypts objects in the `test-gcf-gitlab-packages-5345da93d24c1a97` bucket
      - `test-keyring-storage`: Encrypts the HMAC secret used to access the `test-gitlab-packages-public-a68289e45e3fda1c` bucket
  - GCP Secret Manager
    - PGP keys and decryption secrets
      - `test`
        - `test-pgp-pkgkey`: Package signing key
        - `test-pgp-pkgkey-passphrase`: Decryption passphrase for package signing key
        - `test-pgp-repokey`: Repository signing key
        - `test-pgp-repokey-passphrase`: Decryption passphrase for repository sining key
      - `internal`: TBD
      - `prod`: TBD
- [ ] How is data rated according to our [data classification standard](https://about.gitlab.com/handbook/engineering/security/data-classification-standard/) (customer data is RED)?
  - Public packages: GREEN
  - Private packages: ORANGE (due to possible open security issues)
  - BlobSigner credentials: ORANGE (due to possible open security issues)
  - PGP keys: RED
- [ ] Do we have audit logs for when data is accessed? If you are unsure or if using the central logging and a new pubsub topic was created, create an issue in the [Security Logging Project](https://gitlab.com/gitlab-com/gl-security/engineering-and-research/security-logging/security-logging/-/issues/new?issuable_template=add-remove-change-log-source) using the `add-remove-change-log-source` template.
  - Logging available
    - BlobSigner emits basic error and access logs to GCP logs
    - As of production deployment, all non-automation logins will be traceable via `ops.gitlab.com`
    - Package uploads via automation will be traceable via CI pipelines on `ops.gitlab.com`
  - [ ] Ensure appropriate logs are being kept for compliance and requirements for retention are met.
    - Automation and manual login logs are kept on `ops.gitlab.com` and have the same retention as normal CI login and pipeline logs
    - BlobSigner logs have no retention requirements (diagnostic only) and are not automatically deleted in any case
  - [ ] If the data classification = Red for the new environment, please create a [Security Compliance Intake issue](https://gitlab.com/gitlab-com/gl-security/security-assurance/security-compliance-commercial-and-dedicated/security-compliance-intake/-/issues/new?issue[title]=System%20Intake:%20%5BSystem%20Name%20FY2%23%20Q%23%5D&issuable_template=intakeform). Note this is not necessary if the service is deployed in existing Production infrastructure.

## Beta

### Monitoring and Alerting

_The items below will be reviewed by the Scalability:Practices team._

- [ ] Link to examples of logs on https://logs.gitlab.net
- [ ] Link to the [Grafana dashboard](https://dashboards.gitlab.net) for this service.

### Backup, Restore, DR and Retention

_The items below will be reviewed by the Scalability:Practices team._

- [ ] Are there custom backup/restore requirements?
- [ ] Are backups monitored?
- [ ] Was a restore from backup tested?
- [ ] Link to information about growth rate of stored data.

### Deployment

_The items below will be reviewed by the Delivery team._

- [ ] Will a [change management issue](https://about.gitlab.com/handbook/engineering/infrastructure/change-management/) be used for rollout? If so, link to it here.
- [ ] Does this feature have any version compatibility requirements with other components (e.g., Gitaly, Sidekiq, Rails) that will require a specific order of deployments?
- [ ] Is this feature validated by our [QA blackbox tests](https://gitlab.com/gitlab-org/gitlab-qa)?
- [ ] Will it be possible to roll back this feature? If so explain how it will be possible.

### Security

_The items below will be reviewed by the InfraSec team._

- [ ] Put yourself in an attacker's shoes and list some examples of "What could possibly go wrong?". Are you OK going into Beta knowing that?
- [ ] Link to any outstanding security-related epics & issues for this feature. Are you OK going into Beta with those still on the TODO list?

## General Availability

### Monitoring and Alerting

_The items below will be reviewed by the Scalability:Practices team._

- [ ] Link to the troubleshooting runbooks.
- [ ] Link to an example of an alert and a corresponding runbook.
- [ ] Confirm that on-call SREs have access to this service and will be on-call. If this is not the case, please add an explanation here.

### Operational Risk

_The items below will be reviewed by the Scalability:Practices team._

- [ ] Link to notes or testing results for assessing the outcome of failures of individual components.
- [ ] What are the potential scalability or performance issues that may result with this change?
- [ ] What are a few operational concerns that will not be present at launch, but may be a concern later?
- [ ] Are there any single points of failure in the design? If so list them here.
- [ ] As a thought experiment, think of worst-case failure scenarios for this product feature, how can the blast-radius of the failure be isolated?

### Backup, Restore, DR and Retention

_The items below will be reviewed by the Scalability:Practices team._

- [ ] Are there any special requirements for Disaster Recovery for both Regional and Zone failures beyond our current Disaster Recovery processes that are in place?
- [ ] How does data age? Can data over a certain age be deleted?

### Performance, Scalability and Capacity Planning

_The items below will be reviewed by the Scalability:Practices team._

- [ ] Link to any performance validation that was done according to [performance guidelines](https://docs.gitlab.com/ee/development/performance.html).
- [ ] Link to any load testing plans and results.
- [ ] Are there any potential performance impacts on the Postgres database or Redis when this feature is enabled at GitLab.com scale?
- [ ] Explain how this feature uses our [rate limiting](https://gitlab.com/gitlab-com/runbooks/-/tree/master/docs/rate-limiting) features.
- [ ] Are there retry and back-off strategies for external dependencies?
- [ ] Does the feature account for brief spikes in traffic, at least 2x above the expected rate?

### Deployment

_The items below will be reviewed by the Delivery team._

- [ ] Will a [change management issue](https://about.gitlab.com/handbook/engineering/infrastructure/change-management/) be used for rollout? If so, link to it here.
- [ ] Are there healthchecks or SLIs that can be relied on for deployment/rollbacks?
- [ ] Does building artifacts or deployment depend at all on [gitlab.com](https://gitlab.com)?
