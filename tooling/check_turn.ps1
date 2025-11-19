param(
    [Parameter(Mandatory=$true)]
    [string]$turnUri
)

Write-Host "Checking TURN server $turnUri ..."
try {
    $uri = $turnUri
    # Robust parsing: accept forms like
    #   turn:host:3478
    #   turn:host:3478?transport=udp
    #   turn://host:3478
    #   turn: [ipv6]:3478
    $clean = $uri -replace '^(turns?:\\/\\/|turns?:)', ''
    # Remove query string if present
    if ($clean -match '\?') { $clean = $clean.Split('?')[0] }

    $hostName = $null
    $port = 3478
    # IPv6 bracketed
    if ($clean -match '^\[(.+?)\](?::(\d+))?$') {
        $hostName = $matches[1]
        if ($matches[2]) { $port = [int]$matches[2] }
    } else {
        # host:port or just host
        $m = $clean -split ':'
        $hostName = $m[0]
        if ($m.Length -gt 1) {
            # Try parse numeric port only (ignore other garbage)
            $portPart = $m[1]
            if ($portPart -match '^(\d+)$') { $port = [int]$portPart }
        }
    }
    Write-Host "Resolving $hostName ..."
    $ips = [System.Net.Dns]::GetHostAddresses($hostName)
    foreach ($ip in $ips) { Write-Host " - $ip" }
    Write-Host "Checking TCP connection to ${hostName}:${port} ..."
    $tcp = New-Object System.Net.Sockets.TcpClient
    $async = $tcp.BeginConnect($hostName, $port, $null, $null)
    $wait = $async.AsyncWaitHandle.WaitOne(3000)
    if (-not $wait) { Write-Host "Connection timeout"; exit 2 }
    $tcp.EndConnect($async)
    Write-Host "TCP connection OK"
    $tcp.Close()
    exit 0
} catch {
    Write-Host "Error: $_"
    exit 3
}