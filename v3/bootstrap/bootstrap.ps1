#Requires -Version 5.1
<#
.SYNOPSIS
    Idempotent bootstrap: provisions the secretless CI OIDC identity for LifeData nonprod IaC,
    then stands up the Terraform remote-state storage account, containers, and SPN data-plane role.

.DESCRIPTION
    Creates (or verifies already-created):
      1. Entra app registration  — display name: $appName
      2. Service principal       — tied to the app registration
      3. Federated identity credential (FIC) from fic-nonprod.json — GitHub Actions OIDC, no secret
      4. Contributor role assignment scoped to resource group $rg only
      5. Storage account stldtfstateeastus in iac-shared — control-plane creation (TLS1_2,
         shared-key disabled, blob-public disabled, public-network Enabled per D-208a)
      6. Blob data-protection settings — versioning + 90-day blob & container soft-delete
         (separate blob-service-properties update call; NOT create flags — RESEARCH Pitfall 2)
      7. Storage Blob Data Contributor role on the SA for the CI SPN (objectId $spnObjId) and
         for the running operator — ordered BEFORE container creation (RBAC propagation, Pitfall 4)
      8. Blob containers tfstate-nonprod and tfstate-prod — AAD data-plane (--auth-mode login,
         required because shared-key access is disabled — RESEARCH Pitfall 3)

    Safe to re-run: each step guards with an existence check before creating.
    NEVER creates a client secret or certificate — OIDC federated credential only (ACCESS-01).
    Role assignment scope is the nonprod RG only — no subscription scope, no V2 access (ACCESS-02, D-03).

.PREREQUISITES
    - az CLI 2.61+ logged in to subscription $subscriptionId / tenant $tenantId
    - Caller is Owner of resource group $rg (damir.contractor@lifedatacorp.com is verified Owner)
    - Caller must hold (or be granted by Step 7) Contributor on iac-shared to create the storage account
    - Tenant allowedToCreateApps = true (verified for this tenant)
    - Run from the repository root (V2-Azure-Operations/) so that the relative path
      v3/bootstrap/fic-nonprod.json resolves correctly.

.OUTPUTS
    Prints the resulting appId (ARM_CLIENT_ID), SPN object ID, state SA id, container names,
    and the SPN role scope to stdout.
    These are non-secret identifiers; record the appId for Plan 01-02 verification and
    the SA id / container names for the Phase 2 backend contract.

.NOTES
    Phase: 01-access + 02-remote-state / Plans: 01-01, 02-01
    Date: 2026-06-17 (Phase 1), 2026-06-18 (Phase 2 extension)
    Ops repo: github.com/LifeDataLLC/V2-Azure-Operations (branch: main)
#>

# ─── Configuration ────────────────────────────────────────────────────────────
$subscriptionId = 'e3e4d658-d924-4c2b-ad05-a4457e197527'
$tenantId       = 'b504d3d4-ffb7-40f4-b25a-97ccb238fde3'
$rg             = 'LD-NonProd-EastUS-V3'
$appName        = 'ld-iac-cicd-nonprod'
$githubRepo     = 'LifeDataLLC/V2-Azure-Operations'
$ficParamsFile  = "$PSScriptRoot/fic-nonprod.json"
$ficName        = 'github-nonprod-main'
$roleScope      = "/subscriptions/$subscriptionId/resourceGroups/LD-NonProd-EastUS-V3"  # verbatim casing (Pitfall 4)

# Phase 2: Remote State — configuration (D-201..D-209, RESEARCH Pattern 1)
$stateRg       = 'iac-shared'                              # D-202: already exists, never managed by TF
$saName        = 'stldtfstateeastus'                       # D-203: st<purpose><env> convention, 17 chars
$location      = 'eastus'
$spnObjId      = 'd199cf8a-c401-42c1-8a52-96d2ee2bf92c'   # CI SPN objectId (RESEARCH-verified; --assignee-object-id)
$containers    = @('tfstate-nonprod', 'tfstate-prod')      # D-205/D-206: both created now; only nonprod wired in M1
$retentionDays = 90                                        # D-208: blob + container soft-delete retention
# ──────────────────────────────────────────────────────────────────────────────

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "=== LifeData nonprod CI OIDC bootstrap ==="
Write-Host "  Subscription : $subscriptionId"
Write-Host "  Tenant       : $tenantId"
Write-Host "  Target RG    : $rg"
Write-Host "  App name     : $appName"
Write-Host "  GitHub repo  : $githubRepo"
Write-Host ""

# ─── Step 0: Set subscription (avoids MissingSubscription errors) ─────────────
Write-Host "[0] Setting active subscription..."
az account set `
    --subscription $subscriptionId
Write-Host "    OK: subscription set."
Write-Host ""

# ─── Step 1: App registration ─────────────────────────────────────────────────
Write-Host "[1] Ensuring app registration '$appName' exists..."
$app = az ad app list `
    --display-name $appName `
    --query "[0]" `
    --output json | ConvertFrom-Json

if ($app) {
    Write-Host "    SKIP: app already exists (appId=$($app.appId), objectId=$($app.id))."
} else {
    Write-Host "    CREATE: app not found — creating..."
    $app = az ad app create `
        --display-name $appName `
        --sign-in-audience AzureADMyOrg `
        --output json | ConvertFrom-Json
    Write-Host "    OK: app created (appId=$($app.appId), objectId=$($app.id))."
}

$appId       = $app.appId
$appObjectId = $app.id
Write-Host ""

# ─── Step 2: Service principal ────────────────────────────────────────────────
Write-Host "[2] Ensuring service principal for appId=$appId exists..."
$sp = az ad sp list `
    --filter "appId eq '$appId'" `
    --query "[0]" `
    --output json | ConvertFrom-Json

if ($sp) {
    Write-Host "    SKIP: SPN already exists (objectId=$($sp.id))."
} else {
    Write-Host "    CREATE: SPN not found — creating..."
    $sp = az ad sp create `
        --id $appId `
        --output json | ConvertFrom-Json
    Write-Host "    OK: SPN created (objectId=$($sp.id))."
}

$spnObjectId = $sp.id
Write-Host ""

# ─── Step 3: Federated identity credential ────────────────────────────────────
Write-Host "[3] Ensuring federated identity credential '$ficName' exists on app..."
# NOTE: az on Windows is az.cmd, which re-parses args through cmd.exe — a JMESPath
# query containing a '|' pipe (e.g. "[?name=='x']|[0]") makes cmd.exe treat '|' as a
# shell pipe and fail with "'[0]' is not recognized". Filter without the pipe and take
# the first element in PowerShell instead. (Surfaced during the 2026-06-17 bootstrap run.)
$ficMatches = az ad app federated-credential list `
    --id $appObjectId `
    --query "[?name=='$ficName']" `
    --output json | ConvertFrom-Json
$fic = if ($ficMatches) { @($ficMatches)[0] } else { $null }

if ($fic) {
    Write-Host "    SKIP: FIC '$ficName' already exists."
    Write-Host "    issuer  = $($fic.issuer)"
    Write-Host "    subject = $($fic.subject)"
} else {
    if (-not (Test-Path $ficParamsFile)) {
        Write-Error "FIC parameters file not found: $ficParamsFile"
        exit 1
    }
    Write-Host "    CREATE: FIC not found — creating from $ficParamsFile..."
    $fic = az ad app federated-credential create --parameters $ficParamsFile `
        --id $appObjectId `
        --output json | ConvertFrom-Json
    Write-Host "    OK: FIC created (name=$($fic.name), issuer=$($fic.issuer), subject=$($fic.subject))."
}
Write-Host ""

# ─── Step 4: RG-scoped Contributor role assignment ────────────────────────────
Write-Host "[4] Ensuring Contributor role assignment on RG '$rg' for SPN..."
Write-Host "    Scope: $roleScope"
# az role assignment create is idempotent on (assignee, role, scope).
# Using --assignee with the appId (SPN's appId is also accepted by ARM).
az role assignment create `
    --assignee $appId `
    --role "Contributor" `
    --scope $roleScope `
    --output none
Write-Host "    OK: Contributor role assignment ensured."
Write-Host ""

# ─── Step 5: State storage account (control plane) ───────────────────────────
Write-Host "[5] Ensuring state storage account '${saName}' exists in '${stateRg}'..."
# NOTE: Filter in PowerShell with Where-Object — do NOT use a JMESPath '|' pipe inside
# --query on Windows (az.cmd re-parses through cmd.exe; Pitfall 5 Windows az.cmd bug).
$saList = az storage account list -g $stateRg -o json | ConvertFrom-Json
$sa = @($saList | Where-Object { $_.name -eq $saName })[0]
if ($sa) {
    Write-Host "    SKIP: storage account already exists (name=${saName})."
} else {
    Write-Host "    CREATE: storage account not found — creating..."
    # D-208a (amended 2026-06-18): --public-network-access Enabled is required in M1.
    # D-208 originally specified Disabled, but with no private endpoint and GitHub-hosted runners,
    # Disabled blocks both the Owner workstation and CI runners from the blob data plane.
    # OIDC fixes identity, not network reachability (RESEARCH Pitfall 1 / Open Q1).
    # The data plane remains hard-locked by: AAD-only auth + shared-key disabled +
    # Storage Blob Data Contributor RBAC + TLS1_2 + no anonymous blob.
    # Full network lockdown (private endpoint + IP rules + Disabled) is DEFERRED to M3 security
    # milestone per D-208a. This comment cites D-208a + RESEARCH Pitfall 1.
    az storage account create `
        --name $saName `
        --resource-group $stateRg `
        --location $location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --min-tls-version TLS1_2 `
        --allow-blob-public-access false `
        --allow-shared-key-access false `
        --public-network-access Enabled `
        --output none
    Write-Host "    OK: storage account created (name=${saName})."
}
Write-Host ""

# ─── Step 6: Data protection (separate control-plane call) ───────────────────
Write-Host "[6] Setting blob data-protection properties on '${saName}'..."
# IMPORTANT: versioning and soft-delete are NOT flags on 'az storage account create' —
# they must be set via 'az storage account blob-service-properties update' (RESEARCH Pitfall 2).
# This call is inherently idempotent (sets state), so no existence guard is needed.
az storage account blob-service-properties update `
    --account-name $saName `
    --resource-group $stateRg `
    --enable-versioning true `
    --enable-delete-retention true `
    --delete-retention-days $retentionDays `
    --enable-container-delete-retention true `
    --container-delete-retention-days $retentionDays `
    --output none
Write-Host "    OK: versioning=true, blob soft-delete=${retentionDays}d, container soft-delete=${retentionDays}d."
Write-Host ""

# ─── Step 7: Role grants (control plane, ordered BEFORE container creation) ──
# Grant roles BEFORE Step 8 container ops so the data-plane role propagates first.
# RBAC propagation can take up to ~30 min on first run (RESEARCH Pitfall 4) — if Step 8
# returns 403 immediately after first bootstrap, wait a few minutes and re-run.
Write-Host "[7] Ensuring Storage Blob Data Contributor role on '${saName}'..."
# Fetch the SA resource ID from ARM — do NOT hand-build the scope string; iac-shared is
# lowercase but ARM preserves casing in scope strings (RESEARCH Pitfall 7).
$saId = az storage account show -n $saName -g $stateRg --query id -o tsv

# Grant CI SPN the data-plane role (D-204: data-plane only; no Contributor/control-plane on iac-shared).
# az role assignment create is idempotent on (assignee, role, scope) — no existence guard needed.
Write-Host "    Granting SPN (objectId=${spnObjId}) Storage Blob Data Contributor on SA..."
az role assignment create `
    --assignee-object-id $spnObjId `
    --assignee-principal-type ServicePrincipal `
    --role "Storage Blob Data Contributor" `
    --scope $saId `
    --output none
Write-Host "    OK: CI SPN role assignment ensured."

# Also grant the running operator the same data-plane role so Step 8's --auth-mode login
# container ops succeed under shared-key-disabled (RESEARCH Pitfall 3).
Write-Host "    Granting operator Storage Blob Data Contributor on SA..."
$operatorObjId = az ad signed-in-user show --query id -o tsv
az role assignment create `
    --assignee-object-id $operatorObjId `
    --assignee-principal-type User `
    --role "Storage Blob Data Contributor" `
    --scope $saId `
    --output none
Write-Host "    OK: operator role assignment ensured."
Write-Host ""

# ─── Step 8: Blob containers (data plane, AAD only) ──────────────────────────
Write-Host "[8] Ensuring blob containers exist in '${saName}'..."
# ALWAYS use --auth-mode login — shared-key access is disabled; key auth would error
# KeyBasedAuthenticationNotPermitted (RESEARCH Pitfall 3).
# NOTE: a 403 immediately after Step 7 may indicate RBAC propagation delay (up to ~30 min,
# RESEARCH Pitfall 4), not misconfiguration. Re-run bootstrap after a few minutes if this occurs.
foreach ($c in $containers) {
    $exists = az storage container exists `
                --account-name $saName `
                --name $c `
                --auth-mode login `
                --query exists -o tsv
    if ($exists -eq 'true') {
        Write-Host "    SKIP: container '${c}' already exists."
    } else {
        Write-Host "    CREATE: container '${c}' not found — creating..."
        az storage container create `
            --account-name $saName `
            --name $c `
            --auth-mode login `
            --output none
        Write-Host "    OK: container '${c}' created."
    }
}
Write-Host ""

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host "=== Bootstrap complete ==="
Write-Host ""
Write-Host "  ARM_CLIENT_ID       (appId)      : $appId"
Write-Host "  App object ID                    : $appObjectId"
Write-Host "  SPN object ID                    : $spnObjectId"
Write-Host "  Role scope (Phase 1)             : $roleScope"
Write-Host ""
Write-Host "  === Phase 2: Remote State Backend ==="
Write-Host "  State SA id                      : $saId"
Write-Host "  State SA name                    : ${saName}"
Write-Host "  State RG                         : ${stateRg}"
Write-Host "  Containers                       : $($containers -join ', ')"
Write-Host "  SPN data-plane role scope        : $saId"
Write-Host "  SPN objectId (role grantee)      : ${spnObjId}"
Write-Host ""
Write-Host "Record ARM_CLIENT_ID for Plan 01-02 verification."
Write-Host "Record State SA id + container names for the Phase 2 backend contract (Plan 02-02)."
Write-Host "No client secret was created — OIDC federated credential only."
Write-Host ""
