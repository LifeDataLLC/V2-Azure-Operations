#Requires -Version 5.1
<#
.SYNOPSIS
    Idempotent bootstrap: provisions the secretless CI OIDC identity for LifeData nonprod IaC.

.DESCRIPTION
    Creates (or verifies already-created):
      1. Entra app registration  — display name: $appName
      2. Service principal       — tied to the app registration
      3. Federated identity credential (FIC) from fic-nonprod.json — GitHub Actions OIDC, no secret
      4. Contributor role assignment scoped to resource group $rg only

    Safe to re-run: each step guards with an existence check before creating.
    NEVER creates a client secret or certificate — OIDC federated credential only (ACCESS-01).
    Role assignment scope is the nonprod RG only — no subscription scope, no V2 access (ACCESS-02, D-03).

.PREREQUISITES
    - az CLI 2.61+ logged in to subscription $subscriptionId / tenant $tenantId
    - Caller is Owner of resource group $rg (damir.contractor@lifedatacorp.com is verified Owner)
    - Tenant allowedToCreateApps = true (verified for this tenant)
    - Run from the repository root (V2-Azure-Operations/) so that the relative path
      v3/bootstrap/fic-nonprod.json resolves correctly.

.OUTPUTS
    Prints the resulting appId (ARM_CLIENT_ID) and SPN object ID to stdout.
    These are non-secret identifiers; record the appId for Plan 01-02 verification.

.NOTES
    Phase: 01-access / Plan: 01-01
    Date: 2026-06-17
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
$fic = az ad app federated-credential list `
    --id $appObjectId `
    --query "[?name=='$ficName']|[0]" `
    --output json | ConvertFrom-Json

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

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host "=== Bootstrap complete ==="
Write-Host ""
Write-Host "  ARM_CLIENT_ID       (appId)      : $appId"
Write-Host "  App object ID                    : $appObjectId"
Write-Host "  SPN object ID                    : $spnObjectId"
Write-Host "  Role scope                       : $roleScope"
Write-Host ""
Write-Host "Record ARM_CLIENT_ID for Plan 01-02 verification."
Write-Host "No client secret was created — OIDC federated credential only."
Write-Host ""
