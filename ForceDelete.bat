@echo off
chcp 936 >nul 2>&1
title 强制删除工具
setlocal enabledelayedexpansion

:: 检查是否拖入了文件/文件夹
if "%~1"=="" (
    echo [提示] 请将文件或文件夹拖放到本脚本图标上。
    pause
    exit /b 1
)

:: 循环处理每个拖入的参数（支持多选拖入）
:loop
if "%~1"=="" goto :done

echo ============================================
echo  目标: %~1
echo ============================================

:: 路径不存在则跳过
if not exist "%~1\" if not exist "%~1" (
    echo [错误] 路径不存在
    goto :next
)

:: 强制删除（del /f /q /a、rd /s /q 自带强制参数）
call :forceDelete "%~1"

:: 验证删除结果，失败则查找并终止占用进程
if exist "%~1" (
    echo [失败] 删除未成功，目标正被程序占用。
    call :handleLocked "%~1"
) else (
    echo [成功] 已强制删除
)
echo.

:next
shift
goto :loop

:done
echo ============================================
echo  全部处理完成
echo ============================================
pause
exit /b 0

:: ============ 子过程：强制删除（区分文件与文件夹） ============
:forceDelete
if exist "%~1\" (
    rd /s /q "%~1" 2>nul
) else if exist "%~1" (
    del /f /q /a "%~1" 2>nul
)
goto :eof

:: ============ 子过程：查找占用进程并终止后删除 ============
:handleLocked
set "LOCKED_PATH=%~1"
set "PS1=%TEMP%\ForceDelete_Detect.ps1"
set "PSOUT=%TEMP%\ForceDelete_Detect.txt"
set "PIDLIST="

echo [查找] 正在查找占用该目标的进程，请稍候...
call :writeDetector

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" "%LOCKED_PATH%" > "%PSOUT%" 2>nul
del "%PS1%" >nul 2>&1

if not exist "%PSOUT%" (
    echo [提示] 未能执行占用检测，可选择终止 explorer 后重试。
    goto :askExplorer
)

for /f "usebackq tokens=1,2 delims=|" %%A in ("%PSOUT%") do (
    echo     [PID %%A] %%B
    set "PIDLIST=!PIDLIST!%%A "
)
del "%PSOUT%" >nul 2>&1

:: 未检测到占用进程，提供终止 explorer 的兜底选项
if "!PIDLIST!"=="" (
    echo [提示] 未检测到占用该目标的进程，可能被资源管理器占用。
    goto :askExplorer
)

echo.
echo [警告] 终止进程可能导致该程序未保存的数据丢失！
set "ANS="
set /p "ANS=是否终止上述进程并删除？[Y/N] "
if /i not "!ANS:~-1!"=="Y" (
    echo [跳过] 已跳过该目标，未终止任何进程。
    goto :eof
)

echo [操作] 正在终止占用进程...
for %%P in (!PIDLIST!) do taskkill /f /pid %%P >nul 2>&1

ping -n 3 127.0.0.1 >nul 2>&1
call :forceDelete "%LOCKED_PATH%"

if exist "%LOCKED_PATH%" (
    echo [失败] 进程已终止，但目标仍无法删除。
) else (
    echo [成功] 已终止占用进程并删除
)
goto :eof

:: 兜底：终止 explorer.exe 后重试
:askExplorer
echo.
echo [警告] 终止 explorer.exe 后桌面会短暂刷新并自动恢复。
set "ANS="
set /p "ANS=请选择: [E]终止explorer并重试  [其他]跳过 : "
if /i not "!ANS:~-1!"=="E" (
    echo [跳过] 已跳过该目标。
    goto :eof
)

echo [操作] 正在终止 explorer.exe 并重试...
taskkill /f /im explorer.exe >nul 2>&1

ping -n 3 127.0.0.1 >nul 2>&1
call :forceDelete "%LOCKED_PATH%"

if exist "%LOCKED_PATH%" (
    echo [失败] explorer 已终止，但目标仍无法删除。
) else (
    echo [成功] 已终止 explorer 并删除
)
goto :eof

:: ============ 子过程：生成占用检测脚本 ============
:writeDetector
> "%PS1%" echo param([string]$Target)
>>"%PS1%" echo $ErrorActionPreference = 'SilentlyContinue'
>>"%PS1%" echo if ([string]::IsNullOrEmpty($Target)) { exit 0 }
>>"%PS1%" echo $full = [System.IO.Path]::GetFullPath($Target)
>>"%PS1%" echo if (-not (Test-Path -LiteralPath $full)) { exit 0 }
>>"%PS1%" echo.
>>"%PS1%" echo Add-Type -TypeDefinition @'
>>"%PS1%" echo using System;
>>"%PS1%" echo using System.Runtime.InteropServices;
>>"%PS1%" echo public static class RM {
>>"%PS1%" echo   [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
>>"%PS1%" echo   public static extern int RmStartSession(out uint h, int f, string k);
>>"%PS1%" echo   [DllImport("rstrtmgr.dll")]
>>"%PS1%" echo   public static extern int RmEndSession(uint h);
>>"%PS1%" echo   [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
>>"%PS1%" echo   public static extern int RmRegisterResources(uint h, uint n, string[] f, uint na, IntPtr a, uint ns, string[] s);
>>"%PS1%" echo   [DllImport("rstrtmgr.dll")]
>>"%PS1%" echo   public static extern int RmGetList(uint h, out uint need, ref uint cnt, IntPtr buf, ref uint reason);
>>"%PS1%" echo }
>>"%PS1%" echo '@
>>"%PS1%" echo.
>>"%PS1%" echo $files = New-Object 'System.Collections.Generic.List[string]'
>>"%PS1%" echo if (Test-Path -LiteralPath $full -PathType Container) {
>>"%PS1%" echo     foreach ($i in Get-ChildItem -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue) {
>>"%PS1%" echo         if ($i.PSIsContainer) { continue }
>>"%PS1%" echo         $files.Add($i.FullName)
>>"%PS1%" echo         if ($files.Count -ge 500) { break }
>>"%PS1%" echo     }
>>"%PS1%" echo     if ($files.Count -eq 0) { $files.Add($full) }
>>"%PS1%" echo } else {
>>"%PS1%" echo     $files.Add($full)
>>"%PS1%" echo }
>>"%PS1%" echo.
>>"%PS1%" echo $h = [uint32]0
>>"%PS1%" echo $key = [Guid]::NewGuid().ToString()
>>"%PS1%" echo if ([RM]::RmStartSession([ref]$h, 0, $key) -ne 0) { exit 0 }
>>"%PS1%" echo $arr = $files.ToArray()
>>"%PS1%" echo if ([RM]::RmRegisterResources($h, [uint32]$arr.Length, $arr, 0, [IntPtr]::Zero, 0, $null) -ne 0) {
>>"%PS1%" echo     [void][RM]::RmEndSession($h)
>>"%PS1%" echo     exit 0
>>"%PS1%" echo }
>>"%PS1%" echo $skip = New-Object 'System.Collections.Generic.HashSet[int]'
>>"%PS1%" echo $cur = $PID
>>"%PS1%" echo for ($k = 0; $k -lt 6; $k++) {
>>"%PS1%" echo     [void]$skip.Add($cur)
>>"%PS1%" echo     $q = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $cur) -ErrorAction SilentlyContinue
>>"%PS1%" echo     if (-not $q) { break }
>>"%PS1%" echo     $cur = [int]$q.ParentProcessId
>>"%PS1%" echo     if ($cur -le 0) { break }
>>"%PS1%" echo }
>>"%PS1%" echo $need = [uint32]0
>>"%PS1%" echo $cnt = [uint32]0
>>"%PS1%" echo $reason = [uint32]0
>>"%PS1%" echo [void][RM]::RmGetList($h, [ref]$need, [ref]$cnt, [IntPtr]::Zero, [ref]$reason)
>>"%PS1%" echo if ($need -gt 0) {
>>"%PS1%" echo     $sz = 668
>>"%PS1%" echo     $buf = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($sz * [int]$need)
>>"%PS1%" echo     try {
>>"%PS1%" echo         $cnt = $need
>>"%PS1%" echo         $rc = [RM]::RmGetList($h, [ref]$need, [ref]$cnt, $buf, [ref]$reason)
>>"%PS1%" echo         if ($rc -eq 0) {
>>"%PS1%" echo             for ($i = 0; $i -lt [int]$cnt; $i++) {
>>"%PS1%" echo                 $procId = [System.Runtime.InteropServices.Marshal]::ReadInt32($buf, $i * $sz)
>>"%PS1%" echo                 if ($procId -le 0) { continue }
>>"%PS1%" echo                 if ($skip.Contains($procId)) { continue }
>>"%PS1%" echo                 $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
>>"%PS1%" echo                 if ($p) { [Console]::WriteLine([string]$procId + '^|' + $p.ProcessName) }
>>"%PS1%" echo             }
>>"%PS1%" echo         }
>>"%PS1%" echo     } finally {
>>"%PS1%" echo         [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
>>"%PS1%" echo     }
>>"%PS1%" echo }
>>"%PS1%" echo [void][RM]::RmEndSession($h)
>>"%PS1%" echo exit 0
goto :eof
