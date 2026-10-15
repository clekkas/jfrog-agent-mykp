<#
.SYNOPSIS
  Imports a published platform contract (foundry-<env>.json) into the agent repo's GitHub Environment.

.DESCRIPTION
  Reads the contract JSON artifact published by jfrog-oidc-foundry, verifies its checksum,
  and updates platform variables only if its project matches the initialized GitHub Environment.

.PARAMETER ContractPath
  Path to an approved contract for this repository's project. The workshop dev contract is not valid.

.PARAMETER Repo
  GitHub repository in owner/repo format. Default: clekkas/jfrog-agent-mykp.

.PARAMETER Environment
  Target GitHub Environment name. Default: agent.

.EXAMPLE
  ./scripts/import-platform-contract.ps1 -ContractPath foundry-mykp.json -Repo clekkas/jfrog-agent-mykp -Environment agent
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ContractPath,
    [string]$Repo = 'clekkas/jfrog-agent-mykp',
    [string]$Environment = 'agent'
)

$ErrorActionPreference = 'Stop'

function Get-ValuesSha256([psobject]$Values) {
    $names = [string[]]@($Values.PSObject.Properties.Name)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    function Format-JsonString([string]$s) {
        $sb = [Text.StringBuilder]::new('"')
        foreach ($c in $s.ToCharArray()) {
            switch ($c) {
                '"' { [void]$sb.Append('\"') }
                '\' { [void]$sb.Append('\\') }
                "`n" { [void]$sb.Append('\n') }
                "`r" { [void]$sb.Append('\r') }
                "`t" { [void]$sb.Append('\t') }
                "`b" { [void]$sb.Append('\b') }
                "`f" { [void]$sb.Append('\f') }
                default { if ([int]$c -lt 0x20) { [void]$sb.AppendFormat('\u{0:x4}', [int]$c) } else { [void]$sb.Append($c) } }
            }
        }
        [void]$sb.Append('"')
        $sb.ToString()
    }
    $json = '{' + (($names | ForEach-Object { (Format-JsonString $_) + ':' + (Format-JsonString ([string]$Values.$_)) }) -join ',') + '}'
    # Match the publisher's jq -S -c output, including its trailing LF.
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $ContractPath)) {
    throw "Contract file not found at: $ContractPath"
}

Write-Host "==> Reading platform contract from: $ContractPath"
$rawJson = Get-Content -LiteralPath $ContractPath -Raw -Encoding utf8
$contract = $rawJson | ConvertFrom-Json

if ($contract.contractVersion -isnot [string] -or $contract.contractVersion -cne '1') {
    throw "Unsupported contractVersion '$($contract.contractVersion)'; expected '1'."
}
if ($contract.values -isnot [pscustomobject]) {
    throw "Invalid contract JSON: 'values' must be a flat string object."
}

$required = @(
    'AZURE_TENANT_ID', 'AZURE_SUBSCRIPTION_ID', 'AZURE_RESOURCE_GROUP',
    'FOUNDRY_ACCOUNT_NAME', 'FOUNDRY_PROJECT_NAME', 'FOUNDRY_PROJECT_RESOURCE_ID',
    'FOUNDRY_PROJECT_ENDPOINT', 'FOUNDRY_PROJECT_PRINCIPAL_ID',
    'JFROG_REGISTRY_CONNECTION_NAME', 'JFROG_REGISTRY_CONNECTION_ID', 'JF_URL',
    'JFROG_REPO', 'JFROG_GITHUB_OIDC_PROVIDER', 'REGISTRY_TOKEN_AUDIENCE',
    'REGISTRY_TOKEN_ENDPOINT', 'REGISTRY_OIDC_PROVIDER_NAME'
)
$values = $contract.values
$missing = @($required | Where-Object { $values.PSObject.Properties.Name -cnotcontains $_ })
if ($missing.Count) { throw "Contract is missing required values: $($missing -join ', ')." }

foreach ($prop in $values.PSObject.Properties) {
    if ($prop.Name -cnotmatch '^[A-Z][A-Z0-9_]*$' -or
        $prop.Name -match '^(AGENT_|STATE_|MODEL_|SUPPORTED_|RAI_|RUNNER_|TERRAFORM_|IMPORT_|PLATFORM_CONTRACT_)' -or
        $prop.Name -eq 'AZURE_CLIENT_ID') {
        throw "Contract may not set app-owned or invalid variable '$($prop.Name)'."
    }
    if ($prop.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($prop.Value)) {
        throw "Contract variable '$($prop.Name)' must be a nonempty string."
    }
}
if ($contract.valuesSha256 -isnot [string] -or $contract.valuesSha256 -cnotmatch '^[0-9a-f]{64}$') {
    throw 'Contract requires a lowercase 64-hex valuesSha256.'
}
$actualSha = Get-ValuesSha256 $values
if ($actualSha -cne $contract.valuesSha256) {
    throw "valuesSha256 mismatch: expected $($contract.valuesSha256), computed $actualSha."
}

$expectedId = "/subscriptions/$($values.AZURE_SUBSCRIPTION_ID)/resourceGroups/$($values.AZURE_RESOURCE_GROUP)/providers/Microsoft.CognitiveServices/accounts/$($values.FOUNDRY_ACCOUNT_NAME)/projects/$($values.FOUNDRY_PROJECT_NAME)"
$expectedEndpoint = "https://$($values.FOUNDRY_ACCOUNT_NAME).services.ai.azure.com/api/projects/$($values.FOUNDRY_PROJECT_NAME)"
if ($values.FOUNDRY_PROJECT_RESOURCE_ID -ine $expectedId -or
    $values.FOUNDRY_PROJECT_ENDPOINT -notmatch '^https://[^/?#]+/api/projects/[^/?#]+/?$' -or
    $values.FOUNDRY_PROJECT_ENDPOINT.TrimEnd('/') -ine $expectedEndpoint) {
    throw 'Contract project resource ID or endpoint disagrees with its account/project fields.'
}

$rawVariables = & gh variable list --repo $Repo --env $Environment --json name,value
if ($LASTEXITCODE -ne 0) { throw "Cannot read variables for $Repo environment '$Environment'." }
$current = @{}
foreach ($variable in ($rawVariables | ConvertFrom-Json)) { $current[$variable.name] = $variable.value }
$targetKeys = $required[0..6]
$mismatches = @($targetKeys | Where-Object {
    -not $current.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($current[$_]) -or
    $(if ($_ -eq 'FOUNDRY_PROJECT_ENDPOINT') {
        $current[$_].TrimEnd('/') -ine $values.$_.TrimEnd('/')
    } else {
        $current[$_] -ine $values.$_
    })
})
if ($mismatches.Count) {
    throw "Target mismatch or uninitialized environment: $($mismatches -join ', '). Bootstrap the intended project first and obtain a matching-project published contract. No variables were written."
}

Write-Host "==> Verified contract for $($values.FOUNDRY_PROJECT_NAME), sha256 $actualSha"
Write-Host "==> Setting platform variables on $Repo (env: $Environment)..."

foreach ($prop in $values.PSObject.Properties) {
    $name = $prop.Name
    $val = $prop.Value
    Write-Host "  setting $name = $val"
    & gh variable set $name --repo $Repo --env $Environment --body "$val"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set GitHub variable: $name"
    }
}

Write-Host "==> Successfully imported all platform contract variables into $Repo (env: $Environment)."
