# Run a program in Ripes CLI and report retired instructions, simulation time,
# instructions per second, and the peak host memory of the Ripes process.
#
# Usage:
#   .\measure-ripes.ps1 -Src mem_loop.s
#   .\measure-ripes.ps1 -Src mem_loop.s -Proc RV32_5S
#
# The peaks come from GetProcessMemoryInfo, queried through a handle that is
# held open until after Ripes exits, so they cover the whole run rather than
# whatever a polling loop happened to sample.
param(
    [Parameter(Mandatory = $true)][string]$Src,
    [string]$Proc = 'RV32_ISS',
    [string]$Ripes = ''
)
if (-not $Ripes) { $Ripes = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\Ripes\Ripes.exe' }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PsApi {
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_MEMORY_COUNTERS {
        public uint cb, PageFaultCount;
        public UIntPtr PeakWorkingSetSize, WorkingSetSize,
            QuotaPeakPagedPoolUsage, QuotaPagedPoolUsage,
            QuotaPeakNonPagedPoolUsage, QuotaNonPagedPoolUsage,
            PagefileUsage, PeakPagefileUsage;
    }
    [DllImport("psapi.dll", SetLastError = true)]
    public static extern bool GetProcessMemoryInfo(IntPtr h, out PROCESS_MEMORY_COUNTERS c, uint cb);
}
'@ -ErrorAction SilentlyContinue

$src   = (Resolve-Path $Src).Path
$ripes = (Resolve-Path $Ripes).Path
$out   = [IO.Path]::GetTempFileName()
$cliArgs = @('--mode', 'cli', '--src', "`"$src`"", '-t', 'asm', '--proc', $Proc, '--iret', '--exectime')

$p = Start-Process -FilePath $ripes -ArgumentList $cliArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput $out
$handle = $p.Handle          # keep the handle open so the counters survive exit
$p.WaitForExit()

$c = New-Object PsApi+PROCESS_MEMORY_COUNTERS
$ok = [PsApi]::GetProcessMemoryInfo($handle, [ref]$c, [Runtime.InteropServices.Marshal]::SizeOf($c))
$peakWS   = if ($ok) { [uint64]$c.PeakWorkingSetSize } else { 0 }
$peakPriv = if ($ok) { [uint64]$c.PeakPagefileUsage } else { 0 }

$text  = Get-Content $out -Raw
Remove-Item $out
$iret  = [regex]::Match($text, 'instructions retired\s+(\d+)').Groups[1].Value
$ms    = [regex]::Match($text, 'execution time \(ms\)\s+(\d+)').Groups[1].Value

Write-Host $text.Trim()
Write-Host '-----'
Write-Host ("processor            : {0}" -f $Proc)
Write-Host ("retired instructions : {0}" -f $iret)
Write-Host ("simulation time (ms) : {0}" -f $ms)
if ($iret -and $ms -and [double]$ms -gt 0) {
    Write-Host ("instructions/second  : {0:N0}" -f ([double]$iret / [double]$ms * 1000))
}
Write-Host ("peak working set     : {0:N0} bytes ({1:N1} MiB)" -f $peakWS, ($peakWS / 1MB))
Write-Host ("peak private bytes   : {0:N0} bytes ({1:N1} MiB)" -f $peakPriv, ($peakPriv / 1MB))
