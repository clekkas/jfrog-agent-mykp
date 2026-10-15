$ErrorActionPreference = 'Stop'
$importer = Join-Path $PSScriptRoot 'import-platform-contract.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) "contract-test-$([guid]::NewGuid())"
[void](New-Item -ItemType Directory -Path $temp)
$global:ContractTestWrites = [Collections.Generic.List[string]]::new()
$global:ContractTestReads = 0
$global:ContractTestReadFailure = $false
$global:ContractTestWriteFailure = $false
$global:ContractTestVariables = @()

function gh {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'variable' -and $args[1] -eq 'list') {
        $global:ContractTestReads++
        if ($global:ContractTestReadFailure) { $global:LASTEXITCODE = 1; return }
        ConvertTo-Json -InputObject @($global:ContractTestVariables) -Compress
    } elseif ($args[0] -eq 'variable' -and $args[1] -eq 'set') {
        $global:ContractTestWrites.Add($args[2])
        if ($global:ContractTestWriteFailure) { $global:LASTEXITCODE = 1 }
    } else {
        throw "Unexpected gh invocation: $args"
    }
}

function New-Values {
    [pscustomobject][ordered]@{
        AZURE_TENANT_ID = 'tenant'
        AZURE_SUBSCRIPTION_ID = 'subscription'
        AZURE_RESOURCE_GROUP = 'rg'
        FOUNDRY_ACCOUNT_NAME = 'account'
        FOUNDRY_PROJECT_NAME = 'mysecond-project-for-kp'
        FOUNDRY_PROJECT_RESOURCE_ID = '/subscriptions/subscription/resourceGroups/rg/providers/Microsoft.CognitiveServices/accounts/account/projects/mysecond-project-for-kp'
        FOUNDRY_PROJECT_ENDPOINT = 'https://account.services.ai.azure.com/api/projects/mysecond-project-for-kp'
        FOUNDRY_PROJECT_PRINCIPAL_ID = 'principal'
        JFROG_REGISTRY_CONNECTION_NAME = 'jfrog-registry-acct'
        JFROG_REGISTRY_CONNECTION_ID = '/subscriptions/subscription/resourceGroups/rg/providers/Microsoft.CognitiveServices/accounts/account/connections/jfrog-registry-acct'
        JF_URL = 'https://registry.jfrog.io'
        JFROG_REPO = 'docker'
        JFROG_GITHUB_OIDC_PROVIDER = 'github-oidc'
        REGISTRY_TOKEN_AUDIENCE = 'audience'
        REGISTRY_TOKEN_ENDPOINT = '/access/api/v1/oidc/token'
        REGISTRY_OIDC_PROVIDER_NAME = 'oidc-byor'
    }
}

function Test-Import([string]$Name, [scriptblock]$Change, [string]$ErrorPattern = '') {
    $global:ContractTestWrites.Clear()
    $global:ContractTestReads = 0
    $global:ContractTestReadFailure = $false
    $global:ContractTestWriteFailure = $false
    $values = New-Values
    $global:ContractTestVariables = @($values.PSObject.Properties | ForEach-Object {
        @{ name = $_.Name; value = $_.Value }
    })
    $contract = [pscustomobject]@{ contractVersion = '1'; values = $values; valuesSha256 = '' }
    $fixture = @{
        contract = $contract
        rehash = $true
        expectedWrites = 0
    }
    & $Change $fixture
    if ($fixture.rehash) {
        # Independent canonicalization oracle: Python's JSON encoder, not importer code.
        $hash = ($values | ConvertTo-Json -Compress -Depth 10) |
            python -c 'import sys,json,hashlib; v=json.loads(sys.stdin.buffer.read().decode("utf-8")); print(hashlib.sha256((json.dumps(v,sort_keys=True,ensure_ascii=False,separators=(",",":"))+"\n").encode("utf-8")).hexdigest())'
        if ($LASTEXITCODE -ne 0) { throw 'Fixture hashing failed.' }
        $contract.valuesSha256 = $hash.Trim()
    }
    $path = Join-Path $temp 'contract.json'
    $contract | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
    $caught = $null
    try {
        & $importer -ContractPath $path -Repo test/mykp -Environment agent
    } catch {
        $caught = $_.Exception.Message
    }
    if ($ErrorPattern) {
        if (-not $caught -or $caught -notmatch $ErrorPattern) {
            throw "${Name}: expected error '$ErrorPattern', got '$caught'."
        }
        if ($global:ContractTestWrites.Count -ne $fixture.expectedWrites) {
            throw "${Name}: unexpected variable writes: $($global:ContractTestWrites -join ', ')."
        }
    } else {
        if ($caught) { throw "${Name}: $caught" }
        if ($global:ContractTestWrites.Count -ne $values.PSObject.Properties.Name.Count) {
            throw "${Name}: not all platform variables were written."
        }
    }
    Write-Host "PASS: $Name"
}

try {
    Test-Import 'matching contract' { param($f) }
    Test-Import 'canonical key order, escaping and Unicode' {
        param($f)
        $text = "quote`" slash\ newline`n tab`t backspace`b formfeed`f return`r $([char]0x00e9)$([char]0x4e2d)$([char]0xd83d)$([char]0xde00)"
        $f.contract.values | Add-Member NoteProperty Z_EXTENSION $text
        $f.contract.values | Add-Member NoteProperty A_EXTENSION 'first'
    }
    Test-Import 'case-insensitive ARM ID and optional endpoint slash' {
        param($f)
        $f.contract.values.FOUNDRY_PROJECT_RESOURCE_ID = $f.contract.values.FOUNDRY_PROJECT_RESOURCE_ID.ToUpperInvariant()
        $f.contract.values.FOUNDRY_PROJECT_ENDPOINT += '/'
    }
    Test-Import 'workshop contract cannot retarget mykp' {
        param($f)
        $f.contract.values.FOUNDRY_PROJECT_NAME = 'workshop-demo-project'
        $f.contract.values.FOUNDRY_PROJECT_RESOURCE_ID = $f.contract.values.FOUNDRY_PROJECT_RESOURCE_ID.Replace('mysecond-project-for-kp', 'workshop-demo-project')
        $f.contract.values.FOUNDRY_PROJECT_ENDPOINT = $f.contract.values.FOUNDRY_PROJECT_ENDPOINT.Replace('mysecond-project-for-kp', 'workshop-demo-project')
    } 'Target mismatch'
    Test-Import 'uninitialized environment' {
        param($f)
        $global:ContractTestVariables = @()
    } 'uninitialized'
    Test-Import 'inconsistent project fields' {
        param($f)
        $f.contract.values.FOUNDRY_PROJECT_ENDPOINT = 'https://account.services.ai.azure.com/api/projects/other'
    } 'disagrees'
    Test-Import 'missing required variable' {
        param($f)
        $f.contract.values.PSObject.Properties.Remove('JF_URL')
    } 'missing required'
    Test-Import 'non-string variable' {
        param($f)
        $f.contract.values.JFROG_REPO = 42
    } 'nonempty string'
    Test-Import 'empty extension' {
        param($f)
        $f.contract.values | Add-Member NoteProperty EXTRA ' '
    } 'nonempty string'
    Test-Import 'app-owned variable' {
        param($f)
        $f.contract.values | Add-Member NoteProperty AGENT_AZURE_CLIENT_ID 'other'
    } 'app-owned'
    Test-Import 'unsupported version' {
        param($f)
        $f.contract.contractVersion = '2'
    } 'Unsupported'
    Test-Import 'numeric version is not the published string schema' {
        param($f)
        $f.contract.contractVersion = 1
    } 'Unsupported'
    Test-Import 'missing checksum' {
        param($f)
        $f.rehash = $false
        $f.contract.PSObject.Properties.Remove('valuesSha256')
    } 'requires.*valuesSha256'
    Test-Import 'tampered checksum' {
        param($f)
        $f.rehash = $false
        $f.contract.valuesSha256 = '0' * 64
    } 'mismatch'
    Test-Import 'failed environment read' {
        param($f)
        $global:ContractTestReadFailure = $true
    } 'Cannot read'
    Test-Import 'failed variable write' {
        param($f)
        $global:ContractTestWriteFailure = $true
        $f.expectedWrites = 1
    } 'Failed to set'
} finally {
    Remove-Item -LiteralPath (Join-Path $temp 'contract.json') -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp
    Remove-Variable ContractTestWrites,ContractTestReads,ContractTestReadFailure,ContractTestWriteFailure,ContractTestVariables -Scope Global
}
