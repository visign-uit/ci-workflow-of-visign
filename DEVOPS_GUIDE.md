# DevOps Guide: Visign (Next.js + FastAPI) on Azure AKS

Enterprise-grade GitOps deployment using:
- **Bicep** for Infrastructure as Code
- **GitHub Actions** for CI/CD
- **ArgoCD** for GitOps synchronization
- **Azure Key Vault CSI** for secrets management

---

## Architecture Overview

```
┌─────────────┐ push ┌──────┐       ┌───────────────────────┐
│ GitHub      │──────►│ ACR  │◄──────│ AKS Cluster           │
│ Repo        │      │      │ pull  │ (visign-dev/          │
└─────────────┘      └──────┘       │  visign-prod)         │
       dev/main              └──────┬──────┬─────────┘
                                    │      │
              ┌─────────────────────┘      │
              │                            │
              ▼                            ▼
       ┌──────────────┐             ┌──────────────┐
       │ ArgoCD       │             │ Azure Key    │
       │ Auto-syncs   │             │ Vault (CSI)  │
       └──────────────┘             └──────────────┘
```

### GitOps Flow

1. **Developer pushes code** to `dev` or `main` branch
2. **GitHub Actions** builds Docker image → pushes to ACR with tag like `dev-<commit-sha>`
3. **GitHub Actions** updates `kustomization.yaml` with new image tag → commits to Git
4. **ArgoCD** detects the Git change → automatically syncs to AKS
5. **New pods** roll out with updated image (secrets injected via Key Vault CSI)

---

## Environment Topology

| Branch | ArgoCD App   | Namespace    | Replicas      | Configuration                  |
|--------|--------------|--------------|---------------|--------------------------------|
| `dev`  | `visign-dev` | `visign-dev` | 1 per service | Cost-optimized, autoscale 1-4  |
| `main` | `visign-prod`| `visign-prod`| 2 per service | HA across zones, autoscale 2-6 |

- Separate namespaces: dev and prod are completely isolated
- Separate overlays: `k8s-specifications/overlays/dev/` and `k8s-specifications/overlays/prod/`

---

## Stage 0: Prerequisites

### Required Tools

```powershell
winget install -e --id Microsoft.AzureCLI
az aks install-cli
winget install Docker.DockerDesktop
winget install Git.Git
winget install ArgoCD.CLI
```

### Login to Azure

```powershell
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

---

## Stage 1: Infrastructure Deployment (Bicep)

### Available Deployment Modes

**Single Cluster Mode** (`single-cluster.bicepparam`):
- ONE AKS cluster with TWO namespaces
- Best for: Student accounts, learning, cost optimization
- ACR/KV are separate per environment (dev/prod suffixes)

**Separate Cluster Mode** (`dev.bicepparam` or `prod.bicepparam`):
- Dedicated AKS cluster per environment
- Best for: Production, enterprise isolation
- Creates separate resource groups: `visign-rg-dev`, `visign-rg-prod`

### Single Cluster Deployment (Student/Learning)

```powershell
cd visign-llmates/infra

az deployment sub create `
  --subscription "<YOUR_SUBSCRIPTION_ID>" `
  --location southeastasia `
  --template-file main-single-cluster.bicep `
  --parameters parameters/single-cluster-wrapper.bicepparam
```

**Resources Created:**

| Resource        | Name             | Notes                           |
|-----------------|------------------|---------------------------------|
| AKS Cluster     | `visign-aks`     | Shared by dev & prod namespaces |
| ACR (dev)       | `visigndacr-...` | Dev image registry              |
| ACR (prod)      | `visignpacr-...` | Prod image registry             |
| Key Vault (dev) | `visigndkv-...`  | Dev secrets                     |
| Key Vault (prod)| `visignpkv-...`  | Prod secrets                    |

### Separate Cluster Deployment (Production)

```powershell
cd visign-llmates/infra

az deployment sub create `
  --subscription "<YOUR_SUBSCRIPTION_ID>" `
  --template-file main.subscription.bicep `
  --parameters parameters/dev.bicepparam

az deployment sub create `
  --subscription "<YOUR_SUBSCRIPTION_ID>" `
  --template-file main.subscription.bicep `
  --parameters parameters/prod.bicepparam
```

### Connect to AKS

```powershell
az aks get-credentials --resource-group visign-rg --name visign-aks --overwrite-existing

kubectl get nodes
```

---

## Stage 2: Configure GitHub Repository Secrets

Run the following script to enable admin on both ACRs and retrieve credentials:

```powershell
$DEPLOYMENT_OUTPUTS = az deployment sub show `
  --subscription "<YOUR_SUBSCRIPTION_ID>" `
  --name main-single-cluster `
  --query "properties.outputs" `
  | ConvertFrom-Json

$DEV_ACR_NAME = $DEPLOYMENT_OUTPUTS.devAcrName.value
$PROD_ACR_NAME = $DEPLOYMENT_OUTPUTS.prodAcrName.value
$DEV_KV_NAME = $DEPLOYMENT_OUTPUTS.devKeyVaultName.value
$PROD_KV_NAME = $DEPLOYMENT_OUTPUTS.prodKeyVaultName.value

az acr update -n $DEV_ACR_NAME -g visign-rg --admin-enabled true
az acr update -n $PROD_ACR_NAME -g visign-rg --admin-enabled true

$DEV_ACR_CREDS  = az acr credential show -n $DEV_ACR_NAME  -g visign-rg | ConvertFrom-Json
$PROD_ACR_CREDS = az acr credential show -n $PROD_ACR_NAME -g visign-rg | ConvertFrom-Json

$TENANT_ID = az account show --query tenantId -o tsv
$CSI_CLIENT_ID = az aks show --resource-group visign-rg --name visign-aks `
  --query "addonProfiles.azureKeyvaultSecretsProvider.identity.clientId" -o tsv

Write-Host "--- ACR Credentials (Add to GitHub Secrets) ---"
Write-Host "DEV_ACR_LOGIN_SERVER : $($DEPLOYMENT_OUTPUTS.devAcrLoginServer.value)"
Write-Host "DEV_ACR_USERNAME     : $($DEV_ACR_CREDS.username)"
Write-Host "DEV_ACR_PASSWORD     : $($DEV_ACR_CREDS.passwords[0].value)"
Write-Host "PROD_ACR_LOGIN_SERVER: $($DEPLOYMENT_OUTPUTS.prodAcrLoginServer.value)"
Write-Host "PROD_ACR_USERNAME    : $($PROD_ACR_CREDS.username)"
Write-Host "PROD_ACR_PASSWORD    : $($PROD_ACR_CREDS.passwords[0].value)"
Write-Host "`n--- Secrets Provider Config (Update YAML files) ---"
Write-Host "TENANT_ID            : $TENANT_ID"
Write-Host "CSI_CLIENT_ID        : $CSI_CLIENT_ID"
Write-Host "DEV_KV_NAME          : $DEV_KV_NAME"
Write-Host "PROD_KV_NAME         : $PROD_KV_NAME"
```

Go to **GitHub Repo → Settings → Secrets and variables → Actions** and add:

| Secret Name | Value |
|---|---|
| `DEV_ACR_LOGIN_SERVER` | from script output |
| `DEV_ACR_USERNAME` | from script output |
| `DEV_ACR_PASSWORD` | from script output |
| `PROD_ACR_LOGIN_SERVER` | from script output |
| `PROD_ACR_USERNAME` | from script output |
| `PROD_ACR_PASSWORD` | from script output |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Clerk publishable key |

**Update Secrets Provider Configuration:**

After running the script above, update the following files with the values shown:

- `k8s-specifications/overlays/dev/secrets-provider.yaml`: Set `userAssignedIdentityID` and `tenantId` with CSI_CLIENT_ID and TENANT_ID values. Update `keyvaultName` with DEV_KV_NAME from script output.
- `k8s-specifications/overlays/prod/secrets-provider.yaml`: Set `userAssignedIdentityID` and `tenantId` with CSI_CLIENT_ID and TENANT_ID values. Update `keyvaultName` with PROD_KV_NAME from script output.

Commit and push to both `dev` and `main` branches.
---

## Stage 3: Populate Key Vault Secrets

Run the following consolidated script to grant yourself access, populate secrets, and verify:

```powershell
$DEPLOYMENT_OUTPUTS = az deployment sub show `
  --subscription "<YOUR_SUBSCRIPTION_ID>" `
  --name main-single-cluster `
  --query "properties.outputs" `
  | ConvertFrom-Json

$DEV_KV_NAME  = $DEPLOYMENT_OUTPUTS.devKeyVaultName.value
$PROD_KV_NAME = $DEPLOYMENT_OUTPUTS.prodKeyVaultName.value
$OBJECT_ID    = az ad signed-in-user show --query id -o tsv

az role assignment create `
  --assignee $OBJECT_ID `
  --role "Key Vault Secrets Officer" `
  --scope (az keyvault show --name $DEV_KV_NAME --query id -o tsv)

az role assignment create `
  --assignee $OBJECT_ID `
  --role "Key Vault Secrets Officer" `
  --scope (az keyvault show --name $PROD_KV_NAME --query id -o tsv)

Write-Host "Waiting 120 seconds for RBAC propagation..."
Start-Sleep -Seconds 120

az keyvault secret set --vault-name $DEV_KV_NAME --name "DATABASE-URL"          --value '<YOUR_DEV_DATABASE_URL>'
az keyvault secret set --vault-name $DEV_KV_NAME --name "CLERK-PUBLISHABLE-KEY" --value '<YOUR_DEV_CLERK_PK>'
az keyvault secret set --vault-name $DEV_KV_NAME --name "CLERK-SECRET-KEY"      --value '<YOUR_DEV_CLERK_SK>'
az keyvault secret set --vault-name $DEV_KV_NAME --name "OPENAI-API-KEY"        --value '<YOUR_OPENAI_KEY>'
az keyvault secret set --vault-name $DEV_KV_NAME --name "TORCH-COMPUTE"         --value 'cpu'

az keyvault secret set --vault-name $PROD_KV_NAME --name "DATABASE-URL"          --value '<YOUR_PROD_DATABASE_URL>'
az keyvault secret set --vault-name $PROD_KV_NAME --name "CLERK-PUBLISHABLE-KEY" --value '<YOUR_PROD_CLERK_PK>'
az keyvault secret set --vault-name $PROD_KV_NAME --name "CLERK-SECRET-KEY"      --value '<YOUR_PROD_CLERK_SK>'
az keyvault secret set --vault-name $PROD_KV_NAME --name "OPENAI-API-KEY"        --value '<YOUR_OPENAI_KEY>'
az keyvault secret set --vault-name $PROD_KV_NAME --name "TORCH-COMPUTE"         --value 'gpu'

az keyvault secret list --vault-name $DEV_KV_NAME  --query "[].name" -o table
az keyvault secret list --vault-name $PROD_KV_NAME --query "[].name" -o table
```

---

## Stage 3.5: Install cert-manager (REQUIRED for HTTPS)

**CRITICAL:** Install these components BEFORE ArgoCD syncs. Without them, `Certificate` and `ClusterIssuer` CRDs will not exist and ArgoCD will error.

### 1. Install cert-manager

```powershell
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml
kubectl get pods -n cert-manager
```

Wait until all pods show `STATUS: Running`.

### 2. Create Cloudflare API Token Secret

1. Go to Cloudflare Dashboard → API Tokens → Create Token
2. Choose **Edit zone DNS** template → Scope to your zone (`lyhua.dpdns.org`) → Create Token
3. Copy the token (shown only once)

```powershell
kubectl create secret generic cloudflare-api-token `
  --from-literal=api-token=YOUR_CLOUDFLARE_API_TOKEN `
  --namespace=cert-manager
```

### 3. Install NGINX Ingress Controller

```powershell
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-basic `
  --create-namespace `
  --set controller.replicaCount=1 `
  --set controller.nodeSelector."kubernetes.io/os"=linux `
  --set controller.service.annotations."service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path"=/healthz

kubectl get pods -n ingress-basic
kubectl get svc -n ingress-basic
```

Wait until `ingress-nginx-controller` shows an `EXTERNAL-IP` (not `<pending>`).

### 4. Get the Ingress LoadBalancer IP and Configure DNS

```powershell
kubectl get svc -n ingress-basic ingress-nginx-controller
```

Note the `EXTERNAL-IP`. Add two A records at **Cloudflare Dashboard → your zone → DNS → Records**:

| Type | Name   | Value             | Proxy status              |
|------|--------|-------------------|---------------------------|
| A    | `dev`  | `<EXTERNAL-IP>`   | **DNS Only** (grey cloud) |
| A    | `prod` | `<EXTERNAL-IP>`   | **DNS Only** (grey cloud) |

> Cloudflare proxy mode blocks Let's Encrypt. Keep DNS Only until certificates are issued.

Both `dev.lyhua.dpdns.org` and `prod.lyhua.dpdns.org` point to the same IP — the NGINX controller routes by hostname to the correct namespace.

### 5. Verify cert-manager

```powershell
kubectl get pods -n cert-manager
kubectl get clusterissuer letsencrypt-dns
```

---

## Stage 4: Trigger First Build

### Push to GitHub

```powershell
git checkout -b dev
git add .
git commit -m "Initial DevOps setup"
git push -u origin dev

git checkout -b main
git push -u origin main
```

### Monitor CI Workflows

Go to **GitHub Actions** tab. Two workflows will run per push:
- **CI - Visign Web Service** — builds Next.js frontend
- **CI - Visign AI Service** — builds FastAPI backend

Each workflow builds, pushes to ACR, updates `kustomization.yaml`, and commits back to Git.

### Verify Images in ACR

```powershell
az acr repository list -n $DEV_ACR_NAME --output table
az acr repository show-tags -n $DEV_ACR_NAME --repository visign-ai --output table

az acr repository list -n $PROD_ACR_NAME --output table
az acr repository show-tags -n $PROD_ACR_NAME --repository visign-ai --output table
```

### Verify kustomization Updated

```powershell
git log k8s-specifications/overlays/dev/kustomization.yaml
git log k8s-specifications/overlays/prod/kustomization.yaml
```

---

## Stage 6: Install and Configure ArgoCD

### Install ArgoCD

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Install ArgoCD AppProjects

AppProjects must exist before applications. Apply all three:

```powershell
kubectl apply -f k8s-specifications/argocd/appproject-dev.yaml
kubectl apply -f k8s-specifications/argocd/appproject-prod.yaml
kubectl apply -f k8s-specifications/argocd/appproject-infra.yaml
```

### Connect Repository (REQUIRED for private repos)

For private repositories, ArgoCD needs credentials to access the Git repo. Connect it to both projects:

```powershell
argocd repo add https://github.com/LyyHua/visign-llmates `
  --username <GITHUB_USERNAME> `
  --password <GITHUB_PAT> `
  --project dev-project

argocd repo add https://github.com/LyyHua/visign-llmates `
  --username <GITHUB_USERNAME> `
  --password <GITHUB_PAT> `
  --project prod-project

argocd repo add https://github.com/LyyHua/visign-llmates `
  --username <GITHUB_USERNAME> `
  --password <GITHUB_PAT> `
  --project infra-project
```

Skip this step if your repository is public.

### Port Forward ArgoCD (Student Accounts)

```powershell
kubectl port-forward svc/argocd-server -n argocd 8081:80
```

Access at: http://localhost:8081

### Get Admin Password

```powershell
kubectl get secret argocd-initial-admin-secret -n argocd `
  -o jsonpath="{.data.password}" | base64 -d
```

### Configure RBAC (Optional)

Edit `k8s-specifications/argocd/rbac-cm.yaml` then apply:

```powershell
kubectl apply -f k8s-specifications/argocd/rbac-cm.yaml
```

### Login and Apply Applications

```powershell
argocd login localhost:8081 --username admin --password <YOUR_PASSWORD>

kubectl apply -f k8s-specifications/argocd/application-visign-infra.yaml
kubectl apply -f k8s-specifications/argocd/application-visign-dev.yaml
kubectl apply -f k8s-specifications/argocd/application-visign-prod.yaml

argocd app list
```

### Verify Deployment

```powershell
argocd app get visign-dev
argocd app get visign-prod
argocd app get visign-infra

kubectl get pods -n visign-dev
kubectl get pods -n visign-prod

kubectl describe pod -n visign-dev -l app=visign-web | grep -A 10 "Mounts"
```

Expected pods (dev): `visign-web` (1 replica), `visign-ai` (1 replica)

Expected pods (prod): `visign-web` (2 replicas), `visign-ai` (2 replicas)

---

## Stage 7: Access Applications

### Port Forwarding

```powershell
kubectl port-forward -n visign-dev svc/visign-web 3000:3000
kubectl port-forward -n visign-dev svc/visign-ai 8000:8000
```

- Frontend: http://localhost:3000
- API: http://localhost:8000

---

## Updating Applications

After initial setup, do NOT use manual `kubectl apply` commands:

```
Push code to GitHub
    ↓
GitHub Actions builds & pushes image to ACR
    ↓
GitHub Actions updates kustomization.yaml image tag
    ↓
GitHub Actions commits change back to Git
    ↓
ArgoCD detects Git change (3-min interval)
    ↓
ArgoCD auto-syncs cluster with new image
    ↓
New pods deploy automatically
```

### Manual Rollback

```powershell
git log k8s-specifications/overlays/dev/kustomization.yaml
git revert <bad-commit-hash>
git push origin dev
```

---

## Troubleshooting

### Pod in CrashLoopBackOff

```powershell
kubectl logs -n visign-dev -l app=visign-web --tail=50
kubectl describe pod -n visign-dev -l app=visign-web
kubectl get secret visign-secrets -n visign-dev
```

Common causes:
1. Missing Key Vault secrets — verify Stage 3 is complete
2. Key Vault CSI mount failure — check pod events
3. Database connectivity — verify `DATABASE_URL` secret value

### ArgoCD Shows "OutOfSync"

```powershell
argocd app diff visign-dev
argocd app sync visign-dev
```

### ImagePullBackOff

```powershell
az acr repository show-tags --name $DEV_ACR_NAME --repository visign-web
cat k8s-specifications/overlays/dev/kustomization.yaml | grep newTag
kubectl describe pod -n visign-dev -l app=visign-web | grep -A 5 "Failed"
```

### Concurrent Workflow Conflicts

The CI workflow has `concurrency: cancel-in-progress: true` and `git pull --rebase` to handle conflicts. If conflicts persist, wait for the current run to finish before pushing again.

---

## Appendix

### Role Assignments Handled by Bicep

All role assignments are created automatically during `az deployment sub create`. No manual `az role assignment create` commands are needed.

| Identity | Role | Scope |
|---|---|---|
| CI/CD managed identity | AcrPush | DEV ACR |
| CI/CD managed identity | AcrPush | PROD ACR |
| CI/CD managed identity | Key Vault Secrets Officer | DEV KV |
| CI/CD managed identity | Key Vault Secrets Officer | PROD KV |
| CI/CD managed identity | AKS RBAC Cluster Admin | AKS |
| AKS kubelet identity | AcrPull | PROD ACR |
| AKS CSI addon identity | Key Vault Secrets User | DEV KV |
| AKS CSI addon identity | Key Vault Secrets User | PROD KV |

### How Secrets Are Injected

The `SecretProviderClass` in `k8s-specifications/overlays/base/secrets-provider.yaml` maps Key Vault secret names to Kubernetes secret keys:

```yaml
objects: |
  array:
  - |
    objectName: DATABASE-URL
    objectType: secret
secretObjects:
- secretName: visign-secrets
  type: Opaque
  data:
  - objectName: DATABASE-URL
    key: DATABASE_URL
```

The deployments mount this Kubernetes secret via the CSI volume. Each environment's `SecretProviderClass` references its own Key Vault — dev pods read from the dev Key Vault, prod pods read from the prod Key Vault.

### Key Learnings

1. Always verify which file `kustomization.yaml` actually references — a typo between `secret` and `secrets` caused repeated failures
2. Role assignments take 1-5 minutes to propagate — if you get `ForbiddenByRbac`, wait and retry
3. Use `--force --grace-period=0` to immediately delete stuck pods after fixing configs
4. ArgoCD AppProjects MUST be created before Applications — ordering matters
5. Cloudflare proxy mode blocks Let's Encrypt — set to DNS Only for certificate issuance
6. CSI secrets require `userAssignedIdentityID` even with `useVMManagedIdentity: "true"` when multiple identities exist on the node
