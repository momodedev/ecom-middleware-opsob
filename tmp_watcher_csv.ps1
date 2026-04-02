# Watch for first non-zero row in CSV file
$sshKey = "C:\Users\v-chengzhiz\.ssh\id_rsa"
$controlNode = "20.14.74.130"
$csvFile = "/tmp/oceanbase-bench/20260402T062223Z_d8s_v5_centos_nmysql_p_hardreset_v4.csv"
$lastLineCount = 0
$checkInterval = 15

Write-Host "Starting watcher for: $csvFile"
Write-Host "Polling every $checkInterval seconds..."
Write-Host ""

while ($true) {
    try {
        $fullResult = ssh -i $sshKey -o ConnectTimeout=10 azureadmin@$controlNode -p 6666 "wc -l $csvFile 2>/dev/null"
        $lineCount = [int]($fullResult -split '\s+')[0]
        
        if ($lineCount -gt $lastLineCount) {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Line count: $lineCount (was $lastLineCount)"
            $lastLineCount = $lineCount
            
            # If we have more than just header, show first data row
            if ($lineCount -gt 1) {
                Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] *** FIRST DATA ROW DETECTED! Line count = $lineCount ***"
                Write-Host "---FIRST ROW---"
                ssh -i $sshKey -o ConnectTimeout=10 azureadmin@$controlNode -p 6666 "tail -1 $csvFile"
                Write-Host "---"
                break
            }
        }
    }
    catch {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Connection error: $_"
    }
    
    Start-Sleep -Seconds $checkInterval
}

Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Watcher complete!"
