# ══════════════════════════════════════════════════════════════
# 广科课表 · 发布脚本
#
# 一条命令产出可分发、且签名正确的 release APK：
#   解析版本号 → 前置检查 → 构建 → 签名校验 → 复制到 release\ → 打印发布摘要
#
# 用法（在项目根目录）：
#   .\tools\release.ps1
#   .\tools\release.ps1 -Notes "修复了小组件在深色模式下的显示问题"
#   .\tools\release.ps1 -SkipBuild     # 跳过构建，用现有产物
#   .\tools\release.ps1 -SkipVerify    # 跳过签名校验（不推荐）
#
# 详细说明见 tools\README.md
# ══════════════════════════════════════════════════════════════

param(
    [string]$Notes,
    [switch]$SkipBuild,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

# 项目根目录（本脚本位于 tools\ 下；全部逻辑用绝对路径，不改当前目录）
$repoRoot = Split-Path -Parent $PSScriptRoot

function Fail([string]$message) {
    Write-Host ''
    Write-Host "[发布失败] $message" -ForegroundColor Red
    exit 1
}

# ───────────────────── 1. 解析版本号 ─────────────────────
Write-Host '▶ 解析版本号...' -ForegroundColor Cyan

$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
if (-not (Test-Path $pubspecPath)) {
    Fail "找不到 pubspec.yaml：$pubspecPath"
}
$versionLine = Get-Content -Path $pubspecPath -Encoding UTF8 |
    Where-Object { $_ -match '^version:' } |
    Select-Object -First 1
if (-not $versionLine) {
    Fail 'pubspec.yaml 里找不到 version: 行'
}
if ($versionLine -notmatch '^version:\s*(\d+(?:\.\d+){0,2})\+(\d+)\s*$') {
    Fail "版本号格式不对，期望 version: x.y.z+n，实际读到：$versionLine"
}
$versionName = $Matches[1]
$versionCode = $Matches[2]
Write-Host "  版本 $versionName (build $versionCode)"

# ───────────────────── 2. 前置检查 ─────────────────────
Write-Host '▶ 前置检查...' -ForegroundColor Cyan

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Fail '找不到 flutter 命令。请确认 Flutter 已安装，且其 bin 目录已加入 PATH。'
}

if (-not $env:JAVA_HOME) {
    Fail '未设置环境变量 JAVA_HOME。请设置为 JDK 17 安装目录（例如 E:\dev\jiankebiao\jdk17）。'
}
if (-not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    Fail "JAVA_HOME（$env:JAVA_HOME）目录里没有 bin\java.exe，请检查环境变量。"
}

$sdkRoot = $env:ANDROID_HOME
if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_SDK_ROOT }
if (-not $sdkRoot) {
    Fail '未设置环境变量 ANDROID_HOME 或 ANDROID_SDK_ROOT。请设置为 Android SDK 目录。'
}
if (-not (Test-Path $sdkRoot)) {
    Fail "Android SDK 目录不存在：$sdkRoot"
}

$keyPropertiesPath = Join-Path $repoRoot 'android\key.properties'
if (-not (Test-Path $keyPropertiesPath)) {
    Fail "缺少 android\key.properties（$keyPropertiesPath）。`n没有它 release 构建会回退到 debug 签名，发出去的包无法覆盖安装。"
}
Write-Host '  flutter / JDK / Android SDK / key.properties 均就绪'

# ───────────────────── 3. 构建 ─────────────────────
$apkPath = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'

if ($SkipBuild) {
    Write-Host '▶ 跳过构建（-SkipBuild），使用现有产物' -ForegroundColor Yellow
    if (-not (Test-Path $apkPath)) {
        Fail "找不到现有产物 $apkPath，请去掉 -SkipBuild 完整跑一次。"
    }
} else {
    Write-Host '▶ 开始构建（flutter build apk --release，通常需要几分钟）...' -ForegroundColor Cyan
    Push-Location $repoRoot
    try {
        & flutter --no-version-check build apk --release
    } finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) {
        Fail "flutter build 失败（退出码 $LASTEXITCODE）。请把上面的报错信息发回来排查。"
    }
}

# ───────────────────── 4. 产物检查 ─────────────────────
Write-Host '▶ 检查构建产物...' -ForegroundColor Cyan
if (-not (Test-Path $apkPath)) {
    Fail "找不到 $apkPath，构建产物异常。"
}
$apkItem = Get-Item -Path $apkPath
if ($apkItem.Length -lt 10MB) {
    Fail ("APK 只有 {0:N2} MB（小于 10 MB），产物异常，可能是构建被中断或打出了错误变体。" -f ($apkItem.Length / 1MB))
}
Write-Host ("  产物正常：{0:N2} MB" -f ($apkItem.Length / 1MB))

# ───────────────────── 5. 签名校验 ─────────────────────
$verifyPassed = $false
if ($SkipVerify) {
    Write-Host '▶ 跳过签名校验（-SkipVerify，不推荐：debug 签名的包发出去无法覆盖安装）' -ForegroundColor Yellow
} else {
    Write-Host '▶ 校验签名...' -ForegroundColor Cyan
    $buildToolsRoot = Join-Path $sdkRoot 'build-tools'
    if (-not (Test-Path $buildToolsRoot)) {
        Fail "SDK 目录下没有 build-tools：$buildToolsRoot"
    }
    $btDirs = @(
        Get-ChildItem -Path $buildToolsRoot -Directory |
            Where-Object { $_.Name -match '^\d+(\.\d+){0,}$' } |
            Sort-Object { [version]$_.Name }
    )
    if ($btDirs.Count -eq 0) {
        Fail "build-tools 下没有版本目录：$buildToolsRoot"
    }
    # 从最新版本往回找第一个带 apksigner.bat 的
    $apksignerBat = $null
    for ($i = $btDirs.Count - 1; $i -ge 0; $i--) {
        $candidate = Join-Path $btDirs[$i].FullName 'apksigner.bat'
        if (Test-Path $candidate) {
            $apksignerBat = $candidate
            break
        }
    }
    if (-not $apksignerBat) {
        Fail "build-tools 各版本目录里都没找到 apksigner.bat（$buildToolsRoot）。"
    }

    # 注意：不能加 2>&1（$ErrorActionPreference='Stop' 下会误报 NativeCommandError）
    $certOutput = & $apksignerBat verify --print-certs $apkPath | Out-String
    if ($LASTEXITCODE -ne 0) {
        Fail "apksigner 校验失败（退出码 $LASTEXITCODE），APK 可能未签名或已损坏。"
    }
    if ($certOutput -match 'CN=Android Debug') {
        Fail '这个 APK 是 debug 签名的，绝不能发出去！请检查 android\key.properties 是否配置正确，然后去掉 -SkipBuild 重新构建。'
    }
    if ($certOutput -notmatch 'CN=Guangke Timetable') {
        Fail ("签名证书不是预期的 CN=Guangke Timetable，可能用错了 keystore。apksigner 输出：`n{0}" -f $certOutput)
    }
    $verifyPassed = $true
    Write-Host '  签名正确：CN=Guangke Timetable'
}

# ───────────────────── 6. 哈希与大小 ─────────────────────
$sha256 = (Get-FileHash -Path $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sizeBytes = $apkItem.Length

# ───────────────────── 7. 复制到 release\ ─────────────────────
Write-Host '▶ 复制到 release\ ...' -ForegroundColor Cyan
$releaseDir = Join-Path $repoRoot 'release'
if (-not (Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir | Out-Null
}
$destName = "jiankebiao-$versionName+$versionCode.apk"
$destPath = Join-Path $releaseDir $destName
Copy-Item -Path $apkPath -Destination $destPath -Force

# ───────────────────── 8. 发布摘要 ─────────────────────
$signerText = if ($verifyPassed) { 'CN=Guangke Timetable  ✅' } else { '已跳过校验（-SkipVerify）' }
$notesText = if ($Notes) { $Notes } else { '(未填写)' }
$buildTime = $apkItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')

Write-Host ''
Write-Host '══════════════ 发布摘要 ══════════════' -ForegroundColor Green
Write-Host "版本    : $versionName (build $versionCode)"
Write-Host "文件    : release\$destName"
Write-Host ("大小    : {0:N2} MB ({1:N0} 字节)" -f ($sizeBytes / 1MB), $sizeBytes)
Write-Host "SHA256  : $sha256"
Write-Host "签名    : $signerText"
Write-Host "构建时间: $buildTime"
Write-Host "发布说明: $notesText"
Write-Host '══════════════════════════════════════' -ForegroundColor Green
Write-Host ''
Write-Host '分发提示：把这个 apk 发给同学，安装前需先卸载旧版本'
Write-Host '（debug 包与 release 包签名不同，不能覆盖安装）'

exit 0
