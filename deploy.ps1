<#
.SYNOPSIS
  Deploy the hosted agent with Terraform (AzAPI) from a workstation.

  Defaults target project mysecond-project-for-kp and the account-shared registry connection
  jfrog-registry-acct; override with parameters if needed.

.EXAMPLE
    ./deploy.ps1 -Image trialndswdc.jfrog.io/byor-demo-docker/agent-mykp@sha256:<digest>
    ./deploy.ps1 -Image <digest-ref> -AutoApprove
#>
[CmdletBinding()]
param(
    [switch]$AutoApprove,
    [string]$AgentService = 'mykp-hosted-agent',
    # Digest-pinned reference: <registry-host>/<repo>/<image>@sha256:<64 hex>
    [Parameter(Mandatory)][string]$Image,
    [string]$ProjectEndpoint = 'https://kaiser-foundry-resource.services.ai.azure.com/api/projects/mysecond-project-for-kp',
    [string]$RegistryConnectionName = 'jfrog-registry-acct',
    [string]$ModelDeployment = 'gpt-5-mini',
    [bool]$ImportExistingAgent = $false
)

$ErrorActionPreference = 'Stop'
$agentTfDir = Join-Path $PSScriptRoot 'infra\hosted-agent'

function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}

if ($Image -notmatch '^[^/]+/.+@sha256:[0-9a-f]{64}$') { throw "Image must be digest-pinned (<host>/<repo>/<image>@sha256:<64 hex>), got '$Image'." }

if (-not (Test-Path (Join-Path $agentTfDir 'backend.hcl'))) {
    throw "Missing $agentTfDir\backend.hcl (remote state). Run scripts/bootstrap-github-oidc.ps1 first."
}

Write-Host "==> Terraform: hosted agent $AgentService (connection: $RegistryConnectionName)"
Invoke-Checked terraform @("-chdir=$agentTfDir", 'init', '-input=false', '-backend-config=backend.hcl')
Invoke-Checked terraform @(
    "-chdir=$agentTfDir", 'plan', '-input=false', '-out=tfplan',
    "-var=project_endpoint=$ProjectEndpoint",
    "-var=agent_name=$AgentService",
    "-var=image_uri=$Image",
    "-var=registry_connection_name=$RegistryConnectionName",
    "-var=model_deployment_name=$ModelDeployment",
    "-var=import_existing_agent=$($ImportExistingAgent.ToString().ToLowerInvariant())"
)
if (-not $AutoApprove) {
    $answer = Read-Host 'Apply the hosted-agent plan? (y/N)'
    if ($answer -notmatch '^(y|yes)$') { Write-Host 'Aborted.'; exit 1 }
}
Invoke-Checked terraform @("-chdir=$agentTfDir", 'apply', '-input=false', 'tfplan')
Remove-Item (Join-Path $agentTfDir 'tfplan') -ErrorAction SilentlyContinue

$version = (& terraform "-chdir=$agentTfDir" output -raw agent_version)
Write-Host "Hosted agent version: $version"
