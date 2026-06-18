# validate.ps1 — Phase 3 structural-assertion gate (STRUCT-01/02/03 + AUTH-01/03 + D-307 + STATE-03)
#
# PURPOSE:
#   Codifies the locked decisions from 03-VALIDATION.md and 03-CONTEXT.md as
#   machine-checkable PASS/FAIL assertions. Runs after every phase wave and
#   before /gsd-verify-work to prove the authored config is internally consistent.
#
# USAGE:
#   cd V2-Azure-Operations/v3/terraform
#   pwsh -File validate.ps1
#   Exit code 0 = all PASS. Non-zero = one or more FAIL (see output).
#
# MODELLED ON: Phase 1 verify.ps1 pattern (same PASS/FAIL per-assertion style).
#
# DESIGN NOTES:
#   - Paths are relative to this file's directory (V2-Azure-Operations/v3/terraform/).
#   - grep -v '^#' strips comment lines before counting — prevents comment text
#     from triggering false positives on structural patterns.
#   - terraform validate uses -backend=false to avoid remote-state coupling during
#     authoring. Full apply-time validation happens in Phase 4.
#   - terraform fmt -check is non-destructive (exits non-zero if files need formatting).
#   - NO `terraform apply` or `terraform import` is performed — Phase 3 authors only.
#
# EXIT CODES:
#   0 = all assertions PASS
#   1 = one or more assertions FAIL

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Change to the script's directory (V2-Azure-Operations/v3/terraform/)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

$Pass = 0
$Fail = 0

function Assert {
    param(
        [string]$Label,
        [bool]$Condition,
        [string]$FailMsg = ""
    )
    if ($Condition) {
        Write-Host "  PASS  $Label" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  FAIL  $Label" -ForegroundColor Red
        if ($FailMsg) {
            Write-Host "        $FailMsg" -ForegroundColor Red
        }
        $script:Fail++
    }
}

Write-Host ""
Write-Host "=== Phase 3 Structural-Assertion Gate ===" -ForegroundColor Cyan
Write-Host "  Working dir: $ScriptDir"
Write-Host ""

# ---------------------------------------------------------------------------
# STRUCT-01: All 8 module directories exist
# ---------------------------------------------------------------------------
Write-Host "--- STRUCT-01: Module directories ---" -ForegroundColor Cyan

$RequiredModules = @(
    "modules/networking",
    "modules/sql",
    "modules/storage",
    "modules/keyvault",
    "modules/app-service",
    "modules/apim",
    "modules/app-gateway",
    "modules/observability"
)

foreach ($mod in $RequiredModules) {
    Assert "Module dir exists: $mod" (Test-Path $mod -PathType Container) `
        "Expected directory '$mod' to exist under v3/terraform/"
}

# ---------------------------------------------------------------------------
# STRUCT-01 / AUTH-01 (D-311): NO azurerm_resource_group resource block anywhere
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- STRUCT-01 / AUTH-01 (D-311): No managed resource group block ---" -ForegroundColor Cyan

# grep recursively for resource "azurerm_resource_group" — must be ABSENT
# Using -v '^#' to exclude comment lines, then searching remaining content
$RgMatches = @(Get-ChildItem -Recurse -Include "*.tf" |
    Where-Object { $_.FullName -notlike "*/.terraform/*" -and $_.FullName -notlike "*\.terraform\*" } |
    Select-String -Pattern '^\s*resource\s+"azurerm_resource_group"' |
    Where-Object { $_.Line.TrimStart() -notmatch '^#' })

Assert "No 'resource azurerm_resource_group' block anywhere (D-311)" `
    ($RgMatches.Count -eq 0) `
    "Found $($RgMatches.Count) azurerm_resource_group resource block(s) — use data source instead (D-311)"

# ---------------------------------------------------------------------------
# STRUCT-02 (D-314): required_version and provider version pins in versions.tf
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- STRUCT-02 (D-314): Version pins in versions.tf ---" -ForegroundColor Cyan

Assert "versions.tf exists" (Test-Path "versions.tf" -PathType Leaf)

if (Test-Path "versions.tf") {
    $VersionsContent = Get-Content "versions.tf" -Raw

    Assert "required_version '~> 1.15' present (D-314)" `
        ($VersionsContent -match '(?m)required_version\s*=\s*"~>\s*1\.15"') `
        "versions.tf must contain: required_version = `"~> 1.15`""

    Assert "azurerm provider version '~> 4.0' present (D-314)" `
        ($VersionsContent -match '(?m)version\s*=\s*"~>\s*4\.0"') `
        "versions.tf must contain: version = `"~> 4.0`" under required_providers.azurerm"
}

# ---------------------------------------------------------------------------
# STRUCT-02 (D-314): .terraform.lock.hcl has hashes for BOTH linux_amd64 + windows_amd64
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- STRUCT-02 (D-314): Dual-platform lockfile ---" -ForegroundColor Cyan

Assert ".terraform.lock.hcl exists (D-314)" (Test-Path ".terraform.lock.hcl" -PathType Leaf)

if (Test-Path ".terraform.lock.hcl") {
    $LockContent = Get-Content ".terraform.lock.hcl" -Raw

    # The lockfile encodes dual-platform coverage via multiple h1: hashes.
    # When terraform providers lock -platform=linux_amd64 -platform=windows_amd64 is run:
    # - Single h1: hash = single platform (incomplete)
    # - Two or more h1: hashes = both platforms validated
    # Evidence: running `terraform providers lock -platform=linux_amd64 -platform=windows_amd64`
    # from this directory exits 0 ("already tracked" = both covered).
    $H1Count = ([regex]::Matches($LockContent, '"h1:')).Count

    Assert "Lockfile has >= 2 h1: hashes (dual-platform linux_amd64 + windows_amd64 — D-314)" `
        ($H1Count -ge 2) `
        "Only $H1Count h1: hash(es) found. Run: terraform providers lock -platform=linux_amd64 -platform=windows_amd64"

    Assert "Lockfile pins azurerm provider (D-314)" `
        ($LockContent -match 'hashicorp/azurerm') `
        "Lockfile must contain hashicorp/azurerm provider entry"
}

# ---------------------------------------------------------------------------
# STATE-03: NO backend "local" anywhere (must use azurerm backend)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- STATE-03: No local backend ---" -ForegroundColor Cyan

$LocalBackendMatches = @(Get-ChildItem -Recurse -Include "*.tf" |
    Where-Object { $_.FullName -notlike "*\.terraform\*" } |
    Select-String -Pattern '^\s*backend\s+"local"' |
    Where-Object { $_.Line.TrimStart() -notmatch '^#' })

Assert "No 'backend local' block anywhere (STATE-03)" `
    ($LocalBackendMatches.Count -eq 0) `
    "Found $($LocalBackendMatches.Count) 'backend local' block(s) — v3/ must use azurerm backend (D-207)"

# Positive assertion: backend.tf uses azurerm
if (Test-Path "backend.tf") {
    $BackendContent = Get-Content "backend.tf" -Raw
    Assert "backend.tf uses 'backend azurerm' (STATE-03)" `
        ($BackendContent -match '(?m)backend\s+"azurerm"') `
        "backend.tf must declare backend 'azurerm', not 'local'"
} else {
    Assert "backend.tf exists (STATE-03)" $false "backend.tf not found"
}

# ---------------------------------------------------------------------------
# STRUCT-03 (D-313): WHATS-DIFFERENT.md exists; no per-env .tf copies
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- STRUCT-03 (D-313): WHATS-DIFFERENT.md + no per-env .tf copies ---" -ForegroundColor Cyan

Assert "WHATS-DIFFERENT.md exists (D-313 / SC6)" (Test-Path "WHATS-DIFFERENT.md" -PathType Leaf)

# No per-env .tf copies: the only env-specific files should be the two .tfvars
$EnvTfCopies = @(Get-ChildItem -Recurse -Include "*.tf" |
    Where-Object {
        $_.Name -match '^(dev|qa|staging|prod)\.' -or
        $_.Name -match '\.(dev|qa|staging|prod)\.tf$'
    })

$EnvTfNames = if ($EnvTfCopies.Count -gt 0) { ($EnvTfCopies | ForEach-Object { $_.Name }) -join ', ' } else { "" }
Assert "No per-env .tf copies (only tfvars differ — STRUCT-03)" `
    ($EnvTfCopies.Count -eq 0) `
    "Found per-env .tf copies: $EnvTfNames. Only nonprod.tfvars/prod.tfvars should vary."

# ---------------------------------------------------------------------------
# AUTH-01: NO import blocks targeting existing V2 resources / aztfexport LD-* refs
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- AUTH-01: No import blocks or aztfexport LD-* references in v3/ HCL ---" -ForegroundColor Cyan

# import blocks must not appear in the v3 config (D-311 / AUTH-01)
# Top-level import blocks start at column 0 (no leading whitespace) — these are
# the Terraform "import {} to = ... id = ..." resource-state-capture blocks.
# Nested "import { content_format = 'openapi' }" blocks inside azurerm_api_management_api
# resource bodies are indented and are NOT state-capture constructs — they are excluded.
$ImportBlockMatches = @(Get-ChildItem -Recurse -Include "*.tf" |
    Where-Object { $_.FullName -notlike "*\.terraform\*" } |
    Select-String -Pattern '^import\s*\{' |
    Where-Object { $_.Line.TrimStart() -notmatch '^#' })

Assert "No top-level 'import {}' blocks in v3/ HCL (AUTH-01 — no aztfexport state capture)" `
    ($ImportBlockMatches.Count -eq 0) `
    "Found $($ImportBlockMatches.Count) top-level import block(s) — v3/ must not import V2 resources (AUTH-01)"

# AUTH-01 integrity: v3/ HCL must not target LD-*-EastUS-V2 RGs as resource destinations.
# Pattern: resource_group_name = "LD-..." or id = "...LD-..." in non-comment HCL lines.
# Evidence citations in description strings (e.g. "Evidence: terraform/LD-Prod-EastUS-V2/...")
# are explicitly allowed — they are documentation, not functional references.
# This assertion uses a targeted pattern to distinguish functional targeting from citation text.
$LegacyRgTargets = @(Get-ChildItem -Recurse -Include "*.tf" |
    Where-Object { $_.FullName -notlike "*\.terraform\*" } |
    Select-String -Pattern '(?:resource_group_name|name)\s*=\s*"LD-(Prod|NonProd)-EastUS-V2' |
    Where-Object { $_.Line.TrimStart() -notmatch '^#' })

Assert "No functional LD-*-EastUS-V2 RG targeting in v3/ HCL (AUTH-01 — no aztfexport state capture)" `
    ($LegacyRgTargets.Count -eq 0) `
    "Found $($LegacyRgTargets.Count) functional V2-RG reference(s) — v3/ must not manage V2 resources (AUTH-01)"

# ---------------------------------------------------------------------------
# AUTH-03 (D-315): azurerm_mssql_virtual_network_rule present in modules/sql
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- AUTH-03 (D-315): SQL VNet rule and APIM children present ---" -ForegroundColor Cyan

$SqlVnetRule = @(Get-ChildItem "modules/sql" -Recurse -Include "*.tf" -ErrorAction SilentlyContinue |
    Select-String -Pattern '^\s*resource\s+"azurerm_mssql_virtual_network_rule"' |
    Where-Object { $_.Line.TrimStart() -notmatch '^#' })

Assert "azurerm_mssql_virtual_network_rule present in modules/sql (D-315 / AUTH-03)" `
    ($SqlVnetRule.Count -gt 0) `
    "azurerm_mssql_virtual_network_rule not found in modules/sql/*.tf — must be explicitly authored (D-315)"

# APIM children: assert all required child resource types are present in modules/apim
$ApimChildTypes = @(
    'azurerm_api_management_api\b',
    'azurerm_api_management_product\b',
    'azurerm_api_management_named_value\b',
    'azurerm_api_management_subscription\b',
    'azurerm_api_management_policy_fragment\b'
)

foreach ($childType in $ApimChildTypes) {
    $ApimMatches = @(Get-ChildItem "modules/apim" -Recurse -Include "*.tf" -ErrorAction SilentlyContinue |
        Select-String -Pattern "^\s*resource\s+`"$childType" |
        Where-Object { $_.Line.TrimStart() -notmatch '^#' })
    $cleanName = $childType.Replace('\b', '')
    Assert "APIM child '$cleanName' present in modules/apim (D-309 / AUTH-03)" `
        ($ApimMatches.Count -gt 0) `
        "Resource type '$cleanName' not found in modules/apim/*.tf"
}

# ---------------------------------------------------------------------------
# D-307: Key posture vars have NO default in variables.tf / module variables.tf
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- D-307: Posture vars have no default ---" -ForegroundColor Cyan

# For each key posture variable, confirm there is no 'default =' line within
# the variable block. Strategy: extract the variable block and check for default.
$PostureVars = @(
    @{ name = "sql_auditing_enabled";          file = "variables.tf" },
    @{ name = "kv_enable_rbac_authorization";  file = "variables.tf" },
    @{ name = "appgw_sku_tier";               file = "modules/app-gateway/variables.tf" },
    @{ name = "apim_sku_name";               file = "modules/apim/variables.tf" }
)

foreach ($pv in $PostureVars) {
    if (-not (Test-Path $pv.file)) {
        Assert "No default on '$($pv.name)' in $($pv.file) (D-307)" $false "$($pv.file) not found"
        continue
    }

    $content = Get-Content $pv.file -Raw
    # Extract the variable block for this specific variable
    # Match from 'variable "<name>" {' to the matching closing brace
    $pattern = "(?ms)variable\s+`"$([regex]::Escape($pv.name))`"\s*\{.*?\n\}"
    $block = [regex]::Match($content, $pattern).Value

    if (-not $block) {
        Assert "No default on '$($pv.name)' in $($pv.file) (D-307)" $false `
            "Variable '$($pv.name)' not found in $($pv.file)"
        continue
    }

    # Check: no 'default =' assignment in the variable block
    # Exclude lines that contain 'default' only in string literals or descriptions
    $hasDefault = $block -match '(?m)^\s*default\s*='
    Assert "No 'default =' on '$($pv.name)' in $($pv.file) (D-307)" `
        (-not $hasDefault) `
        "Variable '$($pv.name)' has a default value — remove it (D-307 no-default rule)"
}

# ---------------------------------------------------------------------------
# Build gate: terraform fmt -check -recursive
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Build gate: terraform fmt -check -recursive ---" -ForegroundColor Cyan

$FmtResult = & terraform fmt -check -recursive 2>&1
$FmtExit = $LASTEXITCODE

Assert "terraform fmt -check -recursive (all .tf files clean)" `
    ($FmtExit -eq 0) `
    "terraform fmt found formatting issues. Run: terraform fmt -recursive`n$FmtResult"

# ---------------------------------------------------------------------------
# Build gate: terraform init -backend=false && terraform validate
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Build gate: terraform init + validate ---" -ForegroundColor Cyan

# init with -backend=false avoids remote-state coupling during authoring (D-207)
$InitResult = & terraform init -backend=false -upgrade=false 2>&1
$InitExit = $LASTEXITCODE

Assert "terraform init -backend=false succeeds" `
    ($InitExit -eq 0) `
    "terraform init failed (exit $InitExit):`n$($InitResult | Select-Object -Last 10 | Out-String)"

if ($InitExit -eq 0) {
    $ValidateResult = & terraform validate 2>&1
    $ValidateExit = $LASTEXITCODE

    Assert "terraform validate succeeds" `
        ($ValidateExit -eq 0) `
        "terraform validate failed (exit $ValidateExit):`n$($ValidateResult | Out-String)"
} else {
    Assert "terraform validate succeeds" $false "Skipped — terraform init failed"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
$Total = $Pass + $Fail

if ($Fail -eq 0) {
    Write-Host "  PASS  All $Total assertions passed" -ForegroundColor Green
} else {
    Write-Host "  FAIL  $Fail of $Total assertions failed" -ForegroundColor Red
}
Write-Host "========================================="
Write-Host ""

exit $Fail
