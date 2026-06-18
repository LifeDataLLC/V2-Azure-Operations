#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 1 + Phase 2 verification — asserts ACCESS-01/02/03, D-03 negative, SEC-GREP,
    and STATE-01/02 success criteria via deterministic Azure CLI checks.

.DESCRIPTION
    Run under the HUMAN identity (damir.contractor@lifedatacorp.com) — NOT the SPN.

    WHY THE HUMAN, NOT THE SPN:
    CONTEXT.md D-03 gives the CI SPN ZERO access to the V2 estate (LD-Prod-EastUS-V2,
    LD-NonProd-EastUS-V2). CONTEXT.md D-04/D-05 place the "readable as authoring reference
    incl. the 403" responsibility on the human identity.  The SPN's access is verified by
    INSPECTING its role assignments and FIC — not by logging in as it (there is no secret/cert
    by design; end-to-end OIDC login is proven in Phase 5 via the GitHub Actions runner —
    RESEARCH Open Question 1).

    This intentionally overrides ROADMAP Phase 1 success-criteria 4 & 5, which say "under the
    SPN identity" — per CONTEXT.md D-03/D-04/D-05 those reads belong to the human identity.

    Checks implemented:
      ACCESS-01a  No client secret on the app (az ad app credential list returns [])
      ACCESS-01b  FIC present with correct issuer / subject / audience
      ACCESS-02a  SPN has Contributor scoped to LD-NonProd-EastUS-V3 (--all, NOT --scope)
      ACCESS-02b  RG LD-NonProd-EastUS-V3 resolves (az group show succeeds)
      D-03 NEG    SPN has ZERO role assignments to either V2 RG or the subscription
      ACCESS-03a  Human reads LD-Prod-EastUS-V2 prod App Service config without 403
                  (az webapp auth show + az webapp config show succeed)
      ACCESS-03b  Human reads both V2 RGs (az resource list returns >0 resources each)
      SEC-GREP    No ARM_CLIENT_SECRET or client_secret in v3/ tree
      STATE-01a   stldtfstateeastus SA: minimumTlsVersion=TLS1_2, allowSharedKeyAccess=false,
                  allowBlobPublicAccess=false, publicNetworkAccess=Enabled (D-208a M1 value)
      STATE-01b   stldtfstateeastus blob data-protection: versioning ON, blob soft-delete 90d,
                  container soft-delete 90d (D-208)
      STATE-01c   CI SPN holds Storage Blob Data Contributor scoped to stldtfstateeastus (D-204);
                  uses --all NOT --scope (Pitfall 2 MissingSubscription)
      STATE-02    Both tfstate-nonprod and tfstate-prod containers exist; checked via AAD
                  (--auth-mode login, shared-key disabled); a 403 immediately after first
                  bootstrap may be RBAC propagation delay (Pitfall 4) — re-run after a few min

.NOTES
    Pitfall 2: Use --all (NOT the --scope flag) when listing role assignments.
               The --scope form throws (MissingSubscription) on this subscription.
    Pitfall 3: ACCESS-03 is VERIFY-ONLY — do NOT pre-emptively grant Contributor-on-V2.
               Escalate only if a real 403 appears.
    Pitfall 4: Use verbatim mixed-case LD-NonProd-EastUS-V3 (ARM preserves casing).
    JMESPath:   Do NOT use | pipes in --query on Windows (az.cmd re-parses through cmd.exe).
                Filter in PowerShell instead.
    STATE-02:   A 403 on container-exists immediately after first bootstrap run may be RBAC
                propagation delay (up to ~30 min). Re-run verify.ps1 after a few minutes.
#>

[CmdletBinding()]
param (
    # SPN app (client) ID — ARM_CLIENT_ID from the bootstrap run (01-01-SUMMARY.md)
    [string]$SpnAppId = 'c31558f0-981b-43c0-b783-6ddf9d5e564c',

    # App registration object ID (id, not appId) — from 01-01-SUMMARY.md
    [string]$AppObjectId = 'be462a66-9aad-4824-a709-c0a02cf99489'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Configuration ────────────────────────────────────────────────────────────
$subscriptionId    = 'e3e4d658-d924-4c2b-ad05-a4457e197527'
$tenantId          = 'b504d3d4-ffb7-40f4-b25a-97ccb238fde3'

# V3 (new estate) — the SPN's allowed scope
$nonprodV3Rg       = 'LD-NonProd-EastUS-V3'   # verbatim casing (Pitfall 4)

# V2 (old PHI estate) — the SPN must have ZERO access here
$prodV2Rg          = 'LD-Prod-EastUS-V2'
$nonprodV2Rg       = 'LD-NonProd-EastUS-V2'

# FIC expected values (must match fic-nonprod.json exactly)
$ficIssuer         = 'https://token.actions.githubusercontent.com'
$ficSubject        = 'repo:LifeDataLLC/V2-Azure-Operations:ref:refs/heads/main'
$ficAudience       = 'api://AzureADTokenExchange'

# Phase 2: Remote State — configuration (D-202..D-208)
$stateRg           = 'iac-shared'                               # D-202: already exists; lowercase (Pitfall 7)
$saName            = 'stldtfstateeastus'                        # D-203
$retentionDays     = 90                                         # D-208: blob + container soft-delete
$stateContainers   = @('tfstate-nonprod', 'tfstate-prod')       # D-205/D-206

# ─── Helpers ──────────────────────────────────────────────────────────────────
$passCount = 0
$failCount = 0

function Assert-Pass {
    param([string]$CheckId, [string]$Message)
    Write-Host "  PASS  [$CheckId] $Message" -ForegroundColor Green
    $script:passCount++
}

function Assert-Fail {
    param([string]$CheckId, [string]$Message)
    Write-Host "  FAIL  [$CheckId] $Message" -ForegroundColor Red
    $script:failCount++
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Phase 1 Access Verification — LifeData IaC (ld-iac-cicd-nonprod)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SpnAppId   : $SpnAppId"
Write-Host "  AppObjectId: $AppObjectId"
Write-Host "  Run as     : HUMAN identity (see .DESCRIPTION)"
Write-Host ""

# ─── Subscription scope ───────────────────────────────────────────────────────
Write-Host "── Subscription scope ──────────────────────────────────────────────"
az account set --subscription $subscriptionId 2>&1 | Out-Null
$currentSub = az account show --query "id" -o tsv 2>&1
if ($currentSub -eq $subscriptionId) {
    Assert-Pass 'SCOPE' "Active subscription is $subscriptionId"
} else {
    Assert-Fail 'SCOPE' "Expected subscription $subscriptionId but got: $currentSub"
}

# ─── ACCESS-01a: No client secret on the app ──────────────────────────────────
Write-Host ""
Write-Host "── ACCESS-01a: No client secret on app ─────────────────────────────"
$credJson = az ad app credential list --id $AppObjectId -o json 2>&1
try {
    # Wrap in @() so an empty array ('[]') yields Count 0 instead of $null — under
    # Set-StrictMode -Latest, reading .Count on a bare $null throws (false FAIL on the
    # no-secret success case). @() also normalizes a single-object result to an array.
    $creds = @($credJson | ConvertFrom-Json)
    if ($creds.Count -eq 0) {
        Assert-Pass 'ACCESS-01a' "az ad app credential list returned [] — no secret present"
    } else {
        Assert-Fail 'ACCESS-01a' "az ad app credential list returned $($creds.Count) credential(s) — secret must not exist"
    }
} catch {
    Assert-Fail 'ACCESS-01a' "Failed to parse credential list output: $credJson"
}

# ─── ACCESS-01b: FIC present with correct issuer / subject / audience ─────────
Write-Host ""
Write-Host "── ACCESS-01b: FIC issuer / subject / audience ─────────────────────"
$ficJson = az ad app federated-credential list --id $AppObjectId -o json 2>&1
try {
    $fics = $ficJson | ConvertFrom-Json
    # Filter in PowerShell — no JMESPath | pipe (Windows az.cmd re-parses through cmd.exe)
    $matchingFic = $fics | Where-Object {
        $_.issuer -eq $ficIssuer -and
        $_.subject -eq $ficSubject -and
        $_.audiences -contains $ficAudience
    }
    if ($matchingFic) {
        Assert-Pass 'ACCESS-01b' "FIC found: issuer=$ficIssuer subject=$ficSubject audience=$ficAudience"
    } else {
        Assert-Fail 'ACCESS-01b' "No FIC matched expected issuer/subject/audience. FICs returned: $($fics | ConvertTo-Json -Compress)"
    }
} catch {
    Assert-Fail 'ACCESS-01b' "Failed to parse federated-credential list output: $ficJson"
}

# ─── ACCESS-02a: SPN has Contributor on LD-NonProd-EastUS-V3 ─────────────────
Write-Host ""
Write-Host "── ACCESS-02a: SPN Contributor on $nonprodV3Rg ─"
# Use --all, NOT the --scope flag (Pitfall 2 — throws MissingSubscription on this subscription)
$roleJson = az role assignment list --assignee $SpnAppId --all -o json 2>&1
try {
    $allRoles = $roleJson | ConvertFrom-Json
    # Filter in PowerShell (no JMESPath | pipe)
    $v3Roles = $allRoles | Where-Object { $_.scope -like "*$nonprodV3Rg*" }
    $contributorRole = $v3Roles | Where-Object { $_.roleDefinitionName -eq 'Contributor' }
    if ($contributorRole) {
        Assert-Pass 'ACCESS-02a' "SPN has Contributor on scope: $($contributorRole.scope)"
    } else {
        Assert-Fail 'ACCESS-02a' "No Contributor assignment scoped to '$nonprodV3Rg' found for SPN $SpnAppId"
    }
} catch {
    Assert-Fail 'ACCESS-02a' "Failed to parse role assignment list output: $roleJson"
}

# ─── ACCESS-02b: RG LD-NonProd-EastUS-V3 resolves ────────────────────────────
Write-Host ""
Write-Host "── ACCESS-02b: RG $nonprodV3Rg resolves ────────────────────────────"
$rgState = az group show -n $nonprodV3Rg --query "properties.provisioningState" -o tsv 2>&1
if ($rgState -eq 'Succeeded') {
    Assert-Pass 'ACCESS-02b' "az group show -n $nonprodV3Rg returned provisioningState=Succeeded"
} else {
    Assert-Fail 'ACCESS-02b' "az group show -n $nonprodV3Rg returned: $rgState (expected Succeeded)"
}

# ─── D-03 NEGATIVE: SPN has ZERO V2 / subscription access ────────────────────
Write-Host ""
Write-Host "── D-03 NEGATIVE: SPN has zero V2 / subscription access ────────────"
# Re-use $allRoles from ACCESS-02a (already fetched above with --all)
try {
    if (-not $allRoles) {
        $roleJson2 = az role assignment list --assignee $SpnAppId --all -o json 2>&1
        $allRoles  = $roleJson2 | ConvertFrom-Json
    }

    # Detect any assignment scoped to either V2 RG
    $v2ProdRoles    = $allRoles | Where-Object { $_.scope -like "*$prodV2Rg*" }
    $v2NonprodRoles = $allRoles | Where-Object { $_.scope -like "*$nonprodV2Rg*" }

    # Detect bare subscription-scope assignments (exactly "/subscriptions/<id>" — no RG segment)
    $subScope       = "/subscriptions/$subscriptionId"
    $subScopeRoles  = $allRoles | Where-Object { $_.scope -eq $subScope }

    $forbidden = @($v2ProdRoles) + @($v2NonprodRoles) + @($subScopeRoles)

    if ($forbidden.Count -eq 0) {
        Assert-Pass 'D-03-NEG' "SPN has ZERO assignments scoped to $prodV2Rg, $nonprodV2Rg, or subscription root"
    } else {
        $details = $forbidden | ForEach-Object { "$($_.roleDefinitionName)@$($_.scope)" }
        Assert-Fail 'D-03-NEG' "SPN has FORBIDDEN V2/subscription access: $($details -join ', ')"
    }
} catch {
    Assert-Fail 'D-03-NEG' "Failed to evaluate D-03 negative check: $_"
}

# ─── SEC-GREP: No ARM_CLIENT_SECRET or client_secret in v3/ tree ──────────────
Write-Host ""
Write-Host "── SEC-GREP: No secret material in v3/ ─────────────────────────────"
# Determine the v3 directory relative to this script's location
$v3Dir = Join-Path $PSScriptRoot '..'
$v3Dir = (Resolve-Path $v3Dir).Path
# Exclude THIS script from the scan — verify.ps1 legitimately names the tokens in its own
# SEC-GREP guard/comments (a self-match would be a false positive). Use a real alternation
# regex (NOT -SimpleMatch, which would search for the literal "ARM_CLIENT_SECRET|client_secret").
$selfPath = $MyInvocation.MyCommand.Path
$secretMatches = Get-ChildItem -Path $v3Dir -Recurse -File |
    Where-Object { $_.FullName -ne $selfPath } |
    Select-String -Pattern 'ARM_CLIENT_SECRET|client_secret' -ErrorAction SilentlyContinue
if (-not $secretMatches) {
    Assert-Pass 'SEC-GREP' "No ARM_CLIENT_SECRET or client_secret found under $v3Dir (excluding this verify script's own guard text)"
} else {
    $matchSummary = $secretMatches | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }
    Assert-Fail 'SEC-GREP' "Secret material found in v3/ tree: $($matchSummary -join ', ')"
}

# ─── ACCESS-03a: Human reads prod App Service config (403 cleared) ────────────
Write-Host ""
Write-Host "── ACCESS-03a: Human reads prod App Service config (403 cleared) ───"
Write-Host "   NOTE: Runs under HUMAN identity — overrides ROADMAP criteria 4&5 (D-04/D-05)"
# Resolve a prod app name dynamically to avoid hardcoding
$prodAppName = az webapp list -g $prodV2Rg --query "[0].name" -o tsv 2>&1
if (-not $prodAppName -or $prodAppName -match 'ERROR') {
    Assert-Fail 'ACCESS-03a-list' "az webapp list -g $prodV2Rg failed or returned no apps: $prodAppName"
} else {
    Assert-Pass 'ACCESS-03a-list' "Resolved prod app name: $prodAppName"

    # az webapp auth show (uses Microsoft.Web/sites/config/list/Action — was previously 403)
    $authResult = az webapp auth show -g $prodV2Rg -n $prodAppName 2>&1
    if ($LASTEXITCODE -eq 0 -and $authResult -notmatch '403' -and $authResult -notmatch 'AuthorizationFailed') {
        Assert-Pass 'ACCESS-03a-auth' "az webapp auth show -g $prodV2Rg -n $prodAppName succeeded (no 403)"
    } else {
        Assert-Fail 'ACCESS-03a-auth' "az webapp auth show returned error or 403: $authResult"
    }

    # az webapp config show (minTls, ftpsState — also previously 403)
    $configResult = az webapp config show -g $prodV2Rg -n $prodAppName 2>&1
    if ($LASTEXITCODE -eq 0 -and $configResult -notmatch '403' -and $configResult -notmatch 'AuthorizationFailed') {
        Assert-Pass 'ACCESS-03a-config' "az webapp config show -g $prodV2Rg -n $prodAppName succeeded (no 403)"
    } else {
        Assert-Fail 'ACCESS-03a-config' "az webapp config show returned error or 403: $configResult"
    }
}

# ─── ACCESS-03b: Human reads both V2 RGs ─────────────────────────────────────
Write-Host ""
Write-Host "── ACCESS-03b: Human reads both V2 RGs ──────────────────────────────"
Write-Host "   NOTE: Runs under HUMAN identity — overrides ROADMAP criteria 4&5 (D-04/D-05)"

foreach ($rg in @($prodV2Rg, $nonprodV2Rg)) {
    $resourcesJson = az resource list -g $rg -o json 2>&1
    try {
        $resources = $resourcesJson | ConvertFrom-Json
        if ($resources.Count -gt 0) {
            Assert-Pass "ACCESS-03b-$rg" "az resource list -g $rg returned $($resources.Count) resources"
        } else {
            Assert-Fail "ACCESS-03b-$rg" "az resource list -g $rg returned 0 resources (expected >0)"
        }
    } catch {
        Assert-Fail "ACCESS-03b-$rg" "az resource list -g $rg failed or returned non-JSON: $resourcesJson"
    }
}

# ── STATE-01/STATE-02 ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "── STATE-01/02: Remote State Backend (Phase 2) ─────────────────────"
Write-Host "   Runs under HUMAN identity (control-plane reads + data-plane container check)"

# ─── STATE-01a: SA security settings ─────────────────────────────────────────
Write-Host ""
Write-Host "── STATE-01a: SA security settings (TLS, shared-key, blob-public, PNA) ─"
# Use {field:path} projection — no | pipe in --query (Windows az.cmd Pitfall 5)
$saSettingsJson = az storage account show -n $saName -g $stateRg `
    --query "{tls:minimumTlsVersion, sharedKey:allowSharedKeyAccess, blobPublic:allowBlobPublicAccess, pna:publicNetworkAccess}" `
    -o json 2>&1
try {
    $saSettings = $saSettingsJson | ConvertFrom-Json
    if ($saSettings.tls -eq 'TLS1_2') {
        Assert-Pass 'STATE-01a-tls' "minimumTlsVersion = TLS1_2"
    } else {
        Assert-Fail 'STATE-01a-tls' "minimumTlsVersion = $($saSettings.tls) (expected TLS1_2)"
    }
    if ($saSettings.sharedKey -eq $false) {
        Assert-Pass 'STATE-01a-sharedKey' "allowSharedKeyAccess = false (AAD-only data plane)"
    } else {
        Assert-Fail 'STATE-01a-sharedKey' "allowSharedKeyAccess = $($saSettings.sharedKey) (expected false)"
    }
    if ($saSettings.blobPublic -eq $false) {
        Assert-Pass 'STATE-01a-blobPublic' "allowBlobPublicAccess = false"
    } else {
        Assert-Fail 'STATE-01a-blobPublic' "allowBlobPublicAccess = $($saSettings.blobPublic) (expected false)"
    }
    # D-208a: publicNetworkAccess=Enabled is the expected M1 value — full network lockdown
    # (private endpoint + IP rules + Disabled) is deferred to M3 security milestone.
    if ($saSettings.pna -eq 'Enabled') {
        Assert-Pass 'STATE-01a-pna' "publicNetworkAccess = Enabled (M1 accepted value per D-208a; full lockdown deferred to M3)"
    } else {
        Assert-Fail 'STATE-01a-pna' "publicNetworkAccess = $($saSettings.pna) (expected Enabled for M1 per D-208a)"
    }
} catch {
    Assert-Fail 'STATE-01a' "Failed to parse SA settings output: $saSettingsJson"
}

# ─── STATE-01b: Blob data-protection settings ─────────────────────────────────
Write-Host ""
Write-Host "── STATE-01b: Blob data-protection (versioning + soft-delete 90d) ────"
$blobPropsJson = az storage account blob-service-properties show `
    -n $saName -g $stateRg `
    --query "{ver:isVersioningEnabled, del:deleteRetentionPolicy, cdel:containerDeleteRetentionPolicy}" `
    -o json 2>&1
try {
    $blobProps = $blobPropsJson | ConvertFrom-Json
    if ($blobProps.ver -eq $true) {
        Assert-Pass 'STATE-01b-versioning' "isVersioningEnabled = true"
    } else {
        Assert-Fail 'STATE-01b-versioning' "isVersioningEnabled = $($blobProps.ver) (expected true)"
    }
    if ($blobProps.del.enabled -eq $true -and $blobProps.del.days -eq $retentionDays) {
        Assert-Pass 'STATE-01b-blobDel' "blob deleteRetentionPolicy: enabled=true, days=$retentionDays"
    } else {
        Assert-Fail 'STATE-01b-blobDel' "blob deleteRetentionPolicy: enabled=$($blobProps.del.enabled), days=$($blobProps.del.days) (expected enabled=true, days=$retentionDays)"
    }
    if ($blobProps.cdel.enabled -eq $true -and $blobProps.cdel.days -eq $retentionDays) {
        Assert-Pass 'STATE-01b-containerDel' "container deleteRetentionPolicy: enabled=true, days=$retentionDays"
    } else {
        Assert-Fail 'STATE-01b-containerDel' "container deleteRetentionPolicy: enabled=$($blobProps.cdel.enabled), days=$($blobProps.cdel.days) (expected enabled=true, days=$retentionDays)"
    }
} catch {
    Assert-Fail 'STATE-01b' "Failed to parse blob-service-properties output: $blobPropsJson"
}

# ─── STATE-01c: CI SPN data-plane role ───────────────────────────────────────
Write-Host ""
Write-Host "── STATE-01c: CI SPN Storage Blob Data Contributor on ${saName} ──────"
# Use --all, NOT --scope (Pitfall 2 — throws MissingSubscription on this subscription).
# Filter in PowerShell — no JMESPath | pipe (Windows az.cmd Pitfall 5).
# Re-use $allRoles if already populated by ACCESS-02a; otherwise re-fetch.
try {
    if (-not $allRoles) {
        $roleJson3 = az role assignment list --assignee $SpnAppId --all -o json 2>&1
        $allRoles  = $roleJson3 | ConvertFrom-Json
    }
    # Wrap in @() before .Count — StrictMode-safe (empty result is $null without @())
    $stateRoles = @($allRoles | Where-Object {
        $_.roleDefinitionName -eq 'Storage Blob Data Contributor' -and
        $_.scope -like "*$saName*"
    })
    if ($stateRoles.Count -eq 1) {
        Assert-Pass 'STATE-01c' "SPN has Storage Blob Data Contributor scoped to ${saName}: $($stateRoles[0].scope)"
    } elseif ($stateRoles.Count -gt 1) {
        Assert-Pass 'STATE-01c' "SPN has $($stateRoles.Count) Storage Blob Data Contributor assignments scoped to ${saName} (at least 1 required)"
    } else {
        Assert-Fail 'STATE-01c' "No Storage Blob Data Contributor assignment scoped to '${saName}' found for SPN $SpnAppId"
    }
} catch {
    Assert-Fail 'STATE-01c' "Failed to evaluate STATE-01c role check: $_"
}

# ─── STATE-02: Both containers exist (AAD data-plane) ────────────────────────
Write-Host ""
Write-Host "── STATE-02: State containers exist (--auth-mode login) ─────────────"
# ALWAYS use --auth-mode login — shared-key access is disabled on the state SA.
# NOTE: a 403 immediately after first bootstrap may be RBAC propagation delay (up to ~30 min,
# RESEARCH Pitfall 4), not misconfiguration. Re-run verify.ps1 after a few minutes if this occurs.
foreach ($c in $stateContainers) {
    $existsRaw = az storage container exists `
        --account-name $saName `
        --name $c `
        --auth-mode login `
        --query exists -o tsv 2>&1
    $exists = ($existsRaw | Out-String).Trim()
    if ($exists -eq 'true') {
        Assert-Pass "STATE-02-$c" "Container '${c}' exists in ${saName} (AAD auth)"
    } else {
        # May be propagation delay — note it in the FAIL message
        Assert-Fail "STATE-02-$c" "Container '${c}' does not exist or returned error (raw: $existsRaw). If 403, wait ~30 min for RBAC propagation (Pitfall 4) and re-run."
    }
}

# ─── STATE-03: No backend "local" {} anywhere under v3/ ──────────────────────
Write-Host ""
Write-Host "── STATE-03: No backend `"local`" in v3/ .tf files (static grep) ──────"
# Mirror the SEC-GREP idiom above: real alternation -Pattern (NOT -SimpleMatch),
# exclude this verify script itself (it names the guard pattern in comments —
# a self-match would be a false positive), scan all *.tf under v3/.
# STATE-03: The aztfexport artifacts under terraform/LD-*-EastUS-V2/terraform.tf
# use `backend "local" {}` — those must NEVER be carried into v3/ (D-207, RESEARCH
# Anti-Patterns). PASS = zero matches across all .tf files under v3/.
$selfPath = $MyInvocation.MyCommand.Path
$localBackendMatches = Get-ChildItem -Path $v3Dir -Recurse -File -Filter '*.tf' |
    Where-Object { $_.FullName -ne $selfPath } |
    Select-String -Pattern 'backend\s+"local"' -ErrorAction SilentlyContinue
if (-not $localBackendMatches) {
    Assert-Pass 'STATE-03' "No backend `"local`" found in any .tf file under $v3Dir — remote azurerm backend only (STATE-03)"
} else {
    $matchSummary = $localBackendMatches | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }
    Assert-Fail 'STATE-03' "backend `"local`" found in v3/ .tf file(s): $($matchSummary -join ', ') — must use backend `"azurerm`" only (STATE-03)"
}

# ─── STATE-01-init: terraform init smoke proof against live nonprod backend ───
Write-Host ""
Write-Host "── STATE-01-init: terraform init -backend-config=nonprod.backend.hcl ──"
# Human use_cli path (az login first; use_oidc=true is harmless — only exercised
# in CI when ARM_OIDC_REQUEST_* env vars are present, which they are not here).
# NOTE: end-to-end OIDC login (CI path) is proven in Phase 5 — no SPN secret
# is available by design, so we do NOT attempt SPN login here.
# Pitfall 4: a transient 403 immediately after Plan 02-01 may be RBAC propagation
# delay (up to ~30 min). If this assert fails with a 403, re-run after a few min.
$tfDir = Join-Path $v3Dir 'terraform'
Push-Location $tfDir
try {
    $initOutput = terraform init -backend-config=nonprod.backend.hcl -input=false 2>&1
    $initExit   = $LASTEXITCODE
    $initStr    = $initOutput | Out-String

    if ($initExit -eq 0) {
        # Guard: output must NOT contain an access-key prompt — that would mean
        # the backend fell back to key auth (shared-key should be disabled).
        if ($initStr -notmatch 'access_key' -and
            $initStr -notmatch 'Enter a value' -and
            $initStr -notmatch 'storage account access key') {
            Assert-Pass 'STATE-01-init' "terraform init exited 0 with no access-key prompt (AAD/use_cli path)"
        } else {
            Assert-Fail 'STATE-01-init' "terraform init exited 0 but output contained an access-key prompt — shared-key may not be disabled. Output: $initStr"
        }
    } else {
        Assert-Fail 'STATE-01-init' "terraform init exited $initExit. If 403: may be RBAC propagation (Pitfall 4) — re-run after a few min. Output: $initStr"
    }
} catch {
    Assert-Fail 'STATE-01-init' "terraform init threw an exception: $_"
} finally {
    Pop-Location
}

# ─── STATE-01-stateList: terraform state list returns empty (no apply yet) ────
Write-Host ""
Write-Host "── STATE-01-stateList: terraform state list (expected empty) ───────────"
Push-Location $tfDir
try {
    $stateListOutput = terraform state list 2>&1
    $stateListExit   = $LASTEXITCODE
    $stateListStr    = ($stateListOutput | Out-String).Trim()

    if ($stateListExit -eq 0) {
        # Empty state is correct — no terraform apply has run in this phase.
        Assert-Pass 'STATE-01-stateList' "terraform state list exited 0 (empty: '$stateListStr') — remote backend reachable + readable; no apply run yet (correct for Phase 2)"
    } else {
        Assert-Fail 'STATE-01-stateList' "terraform state list exited $stateListExit. Output: $stateListStr"
    }
} catch {
    Assert-Fail 'STATE-01-stateList' "terraform state list threw an exception: $_"
} finally {
    Pop-Location
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
$total = $passCount + $failCount
if ($failCount -eq 0) {
    Write-Host "  RESULT: ALL $passCount/$total CHECKS PASSED" -ForegroundColor Green
    Write-Host "  Phase 1 access gate:      OPEN" -ForegroundColor Green
    Write-Host "  Phase 2 state gate:       OPEN" -ForegroundColor Green
    Write-Host "  Phase 2 STATE-03 gate:    OPEN (no local backend in v3/)" -ForegroundColor Green
    Write-Host "  Phase 2 init smoke gate:  OPEN (terraform init + state list clean)" -ForegroundColor Green
} else {
    Write-Host "  RESULT: $failCount/$total CHECKS FAILED ($passCount passed)" -ForegroundColor Red
    Write-Host "  Phase 1/2 gate: BLOCKED — review FAIL lines above" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Pitfall 3 reminder: if ACCESS-03a/b failed with a real 403," -ForegroundColor Yellow
    Write-Host "  report it — do NOT pre-emptively grant Contributor-on-V2." -ForegroundColor Yellow
    Write-Host "  STATE-02 reminder: a 403 on container-exists right after first" -ForegroundColor Yellow
    Write-Host "  bootstrap run may be RBAC propagation delay (Pitfall 4)." -ForegroundColor Yellow
    Write-Host "  STATE-01-init reminder: a 403 on terraform init right after Plan 02-01" -ForegroundColor Yellow
    Write-Host "  may be RBAC propagation delay — re-run verify.ps1 after a few minutes." -ForegroundColor Yellow
    Write-Host "  Wait a few minutes and re-run verify.ps1 before treating as a failure." -ForegroundColor Yellow
}
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($failCount -gt 0) { exit 1 }
exit 0
