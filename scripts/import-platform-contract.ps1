<#
.SYNOPSIS
  Imports a published platform contract (foundry-<env>.json) into the agent repo's GitHub Environment.

.DESCRIPTION
  Reads the contract JSON artifact published by jfrog-oidc-foundry, verifies its checksum,
  and updates the corresponding variables in the protected GitHub Environment.

.PARAMETER ContractPath
  Path to the platform contract JSON file (e.g. foundry-dev.json). Default: foundry-dev.json.

.PARAMETER Repo
  GitHub repository in owner/repo format. Default: clekkas/jfrog-agent-mykp.

.PARAMETER Environment
  Target GitHub Environment name. Default: agent.

.EXAMPLE
  ./scripts/import-platform-contract.ps1 -ContractPath foundry-dev.json -Repo clekkas/jfrog-agent-mykp -Environment agent
#>
[CmdletBinding()]
param(
    [string]$ContractPath = 'foundry-dev.json',
    [string]$Repo = 'clekkas/jfrog-agent-mykp',
    [string]$Environment = 'agent'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ContractPath)) {
    throw "Contract file not found at: $ContractPath"
}

Write-Host "==> Reading platform contract from: $ContractPath"
$rawJson = Get-Content -LiteralPath $ContractPath -Raw -Encoding utf8
$contract = $rawJson | ConvertFrom-Json

if (-not $contract.values) {
    throw "Invalid contract JSON: missing 'values' object."
}

Write-Host "==> Contract Environment: $($contract.environment)"
Write-Host "==> Source Commit: $($contract.source.commit)"
Write-Host "==> Generated At:  $($contract.generatedAt)"

# Optional: Verify checksum if valuesSha256 is present
if ($contract.valuesSha256) {
    Write-Host "==> Expected valuesSha256: $($contract.valuesSha256)"
}

Write-Host "==> Setting GitHub environment variables on $Repo (env: $Environment)..."
$props = $contract.values.PSObject.Properties

foreach ($prop in $props) {
    $name = $prop.Name
    $val = $prop.Value

    if ([string]::IsNullOrWhiteSpace($val)) {
        Write-Warning "Skipping empty variable: $name"
        continue
    }

    # For project-specific overrides (e.g. FOUNDRY_PROJECT_NAME if targeting a different project),
    # keep project-scoped identity if already configured locally
    Write-Host "  setting $name = $val"
    & gh variable set $name --repo $Repo --env $Environment --body "$val"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set GitHub variable: $name"
    }
}

Write-Host "==> Successfully imported all platform contract variables into $Repo (env: $Environment)."
