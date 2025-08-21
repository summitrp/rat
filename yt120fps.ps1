# Supabase PowerShell Command Executor - Output Table Version
param(
    [int]$IntervalMs = 500
)

$SUPABASE_URL = "https://lqaogssskwveuwbggfph.supabase.co"
$SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxxYW9nc3Nza3d2ZXV3YmdnZnBoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTU4MDYzNjAsImV4cCI6MjA3MTM4MjM2MH0.6iR5kbIbSMf_CNlQHc4Dd86do_52jEloJW8nz9N7Zuc"

$headers = @{
    'apikey' = $SUPABASE_ANON_KEY
    'Authorization' = "Bearer $SUPABASE_ANON_KEY"
    'Content-Type' = 'application/json'
}

$processedCommands = @{}

Write-Host "Starting Supabase Command Executor (Output Table Mode)..." -ForegroundColor Green
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow

while ($true) {
    try {
        # Get unprocessed commands
        $commands = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/runcmd?or=(executed.is.null,executed.eq.false)&order=timestamp.asc" -Method GET -Headers $headers -TimeoutSec 5
        
        foreach ($cmd in $commands) {
            # Skip if already processed
            if ($processedCommands.ContainsKey($cmd.id)) { continue }
            
            # Mark as processed immediately
            $processedCommands[$cmd.id] = $true
            
            Write-Host "Executing: $($cmd.command)" -ForegroundColor Cyan
            
            # Execute command first, then handle database operations
            try {
                $output = cmd /c $cmd.command 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
                Write-Host "Output: $output" -ForegroundColor Green
                Write-Host "Exit Code: $exitCode" -ForegroundColor Green
                
                # Clean up output - keep it simple and readable
                $cleanOutput = $output.Trim()
                if ($cleanOutput.Length -gt 2000) {
                    $cleanOutput = $cleanOutput.Substring(0, 2000) + "`n... [truncated]"
                }
                
                # Include command_id in the output data
                $outputBody = @{
                    command_id = $cmd.id
                    command = $cmd.command
                    output = $cleanOutput
                    exit_code = [int]$exitCode
                } | ConvertTo-Json -Depth 1
                
                Write-Host "Sending output data..." -ForegroundColor Magenta
                
                try {
                    $result = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/output" -Method POST -Headers $headers -Body $outputBody -TimeoutSec 10
                    Write-Host "✓ Saved output to output table" -ForegroundColor Green
                } catch {
                    Write-Host "Failed to save output: $($_.Exception.Message)" -ForegroundColor Red
                    if ($_.Exception.Response) {
                        $responseStream = $_.Exception.Response.GetResponseStream()
                        $reader = New-Object System.IO.StreamReader($responseStream)
                        $responseBody = $reader.ReadToEnd()
                        Write-Host "Response Body: $responseBody" -ForegroundColor Red
                    }
                }
                
            } catch {
                Write-Host "Execution failed: $($_.Exception.Message)" -ForegroundColor Red
                
                # Save error to output table with command_id
                $errorBody = @{
                    command_id = $cmd.id
                    command = $cmd.command
                    output = "Execution failed: $($_.Exception.Message)"
                    exit_code = -1
                } | ConvertTo-Json -Depth 1
                
                try {
                    Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/output" -Method POST -Headers $headers -Body $errorBody -TimeoutSec 10 | Out-Null
                    Write-Host "✓ Saved error to output table" -ForegroundColor Yellow
                } catch {
                    Write-Host "Failed to save error output: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            
            # Delete from runcmd table after processing
            try {
                Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/runcmd?id=eq.$($cmd.id)" -Method DELETE -Headers $headers -TimeoutSec 5 | Out-Null
                Write-Host "Deleted command from runcmd table" -ForegroundColor Yellow
            } catch {
                Write-Host "Failed to delete command $($cmd.id): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        Start-Sleep -Milliseconds $IntervalMs
        
    } catch {
        Write-Host "Error checking commands: $($_.Exception.Message)" -ForegroundColor Red
        Start-Sleep -Milliseconds 2000
    }
}
