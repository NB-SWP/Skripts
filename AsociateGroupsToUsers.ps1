$WorkerScript = {
    param (
        $InputQueue,
        $OutputQueue,
        $ShouldExit
    )

    $workItem = $null
    While (! $ShouldExit.Value) {
        if ($InputQueue.TryDequeue([ref] $workItem)) {

            $users = Get-ADGroupMember $workItem
            $outputMap = @{}
            $outputMap["Group"] = $workItem.Name
            $outputMap["User"] = New-Object System.Collections.ArrayList
            $outputMap["Count"] = $users.Count

            foreach ($user in $users) { 
                [void]$outputMap["User"].Add($user.sAMAccountName)
            }

            $OutputQueue.Enqueue($outputMap)
        }
        else {
            Start-Sleep -m 100
        }
    }
}

$ServerQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[Microsoft.ActiveDirectory.Management.ADGroup]
$OutputQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[System.Collections.Hashtable]
$shouldExit = $false

$groups = Get-ADGroup -Filter "*"

Write-Output "Groups Count AD Filter"
$groups.Count

$groupUserdict = @{}

Write-Output "Add Groups to Queue"
foreach ($group in $groups) { 
    $ServerQueue.Enqueue($group)
}
Write-Output "Groups in Queue"

$threadcount = 10

$pool = [runspacefactory]::CreateRunspacePool(1, $threadcount)
$pool.open()

$handles = New-Object System.Collections.ArrayList

Write-Output "Start"
try {
    for ($i = 0; $i -lt $threadcount; $i++) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool

        [void]$ps.AddScript($WorkerScript).
            AddParameter("InputQueue", $ServerQueue).
            AddParameter("OutputQueue", $OutputQueue).
            AddParameter("ShouldExit", [ref] $shouldExit)
        
            [void]$handles.Add($ps.BeginInvoke())
    }

    Write-Output "Threads started"
    Start-Sleep -Seconds 60

    do {
        $scriptOut = $null

        While($OutputQueue.TryDequeue([ref] $scriptOut)) {
            $groupUserdict[$scriptOut["Group"]] =  $scriptOut["User"]
        }

        if ($ServerQueue.Count -eq 0 -and -not $shouldExit) {
            Write-Output "Serverqueue emptied"
            $shouldExit = $true
        }

        $busy = $handles | Where-Object { -Not $_.IsCompleted }
    }while($busy)
}
finally {
    $pool.Dispose()
}

Write-Output "Finished"
Write-Output "Groups count Dict"
$groupUserdict.Keys.Count

$groupUserdict | ConvertTo-Json | Out-File "Groups.json"