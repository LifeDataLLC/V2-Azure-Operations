#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 1 access verification — asserts all ACCESS-01/02/03 success criteria and the D-03
    negative SPN invariant via deterministic Azure CLI checks.

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

.NOTES
    Pitfall 2: Use --all (NOT the --scope flag) when listing role assignments.
               The --scope form throws (MissingSubscription) on this subscription.
    Pitfall 3: ACCESS-03 is VERIFY-ONLY — do NOT pre-emptively grant Contributor-on-V2.
               Escalate only if a real 403 appears.
    Pitfall 4: Use verbatim mixed-case LD-NonProd-EastUS-V3 (ARM preserves casing).
    JMESPath:   Do NOT use | pipes in --query on Windows (az.cmd re-parses through cmd.exe).
                Filter in PowerShell instead.
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

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
$total = $passCount + $failCount
if ($failCount -eq 0) {
    Write-Host "  RESULT: ALL $passCount/$total CHECKS PASSED" -ForegroundColor Green
    Write-Host "  Phase 1 access gate: OPEN" -ForegroundColor Green
} else {
    Write-Host "  RESULT: $failCount/$total CHECKS FAILED ($passCount passed)" -ForegroundColor Red
    Write-Host "  Phase 1 access gate: BLOCKED — review FAIL lines above" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Pitfall 3 reminder: if ACCESS-03a/b failed with a real 403," -ForegroundColor Yellow
    Write-Host "  report it — do NOT pre-emptively grant Contributor-on-V2." -ForegroundColor Yellow
}
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($failCount -gt 0) { exit 1 }
exit 0
