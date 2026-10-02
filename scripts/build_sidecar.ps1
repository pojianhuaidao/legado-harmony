# 书山侧载包构建脚本：在构建期应用静态图标方案并产出可侧载 HAP。
#
# 为什么需要这个脚本：
#   桌面图标是编译期资源（module.json5 的 icon / startWindowIcon 引用 + icon.png）。
#   应用内选择图标只会持久化 preferences（appIconId），不会改动 module.json5，
#   因此“重新构建后桌面生效”必须由构建流程在打包前调用 apply_static_icon.py。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File scripts\build_sidecar.ps1
#       # 使用当前保存的 appIconId（自动读取设置页持久化的选择）构建
#   powershell -ExecutionPolicy Bypass -File scripts\build_sidecar.ps1 -IconId warm_book
#       # 指定方案构建（apply default 恢复默认图标）
#   powershell -ExecutionPolicy Bypass -File scripts\build_sidecar.ps1 -SkipBuild
#       # 只切换图标引用，不执行构建（查看 module.json5 状态用 python scripts\apply_static_icon.py status）
#
# 产物: output\entry-default-unsigned.hap（可直接 hdc install 侧载）
param(
    [string]$IconId = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# 1. 确定要应用的图标方案：显式 -IconId > 设置页持久化的 appIconId > 默认不切换
if (-not $IconId) {
    # ArkUI preferences 常见落盘位置（读不到则保持当前 module.json5 引用）
    $candidates = @(
        (Join-Path $env:APPDATA 'com.legado3.harmony\shared_prefs\app_icon_settings.xml'),
        (Join-Path $env:APPDATA 'com.legado3.harmony\preferences\app_icon_settings.xml'),
        (Join-Path $env:APPDATA 'com.legado3.harmony\shared_prefs\AppIconSettingsStore.xml')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $m = Select-String -Path $c -Pattern 'appIconId[^>]*value="([^"]+)"' -ErrorAction SilentlyContinue
            if ($m) {
                $IconId = $m.Matches[0].Groups[1].Value
                Write-Host "[icon] 读取设置页持久化 appIconId=$IconId"
                break
            }
        }
    }
}

if ($IconId) {
    Write-Host "[icon] 应用静态图标方案: $IconId"
    python scripts\apply_static_icon.py apply $IconId
} else {
    Write-Host "[icon] 未指定图标方案，沿用当前 module.json5 引用（python scripts\apply_static_icon.py status 可查看）"
}

if ($SkipBuild) {
    Write-Host "[icon] -SkipBuild，仅切换图标引用，跳过构建。"
    exit 0
}

# 2. 定位 hvigor 构建器（DevEco Studio 自带；命令行环境无 hvigorw 时给出指引）
$hvigorScript = $null
$devEco = Get-ChildItem 'C:\Program Files\Huawei\DevEco Studio' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($devEco) {
    $candidate = Join-Path $devEco.FullName 'tools\hvigor\bin\hvigorw.js'
    if (Test-Path $candidate) { $hvigorScript = $candidate }
}
$node = Get-Command node -ErrorAction SilentlyContinue

if (-not $hvigorScript) {
    Write-Host "`n[error] 未找到 DevEco Studio 的 hvigorw.js（tools\hvigor\bin\hvigorw.js）。"
    Write-Host "请使用 DevEco Studio 打开本工程后执行 File > Sync and Build，或配置 hvigorw 后重跑本脚本。"
    Write-Host "图标引用已按上述方案切换，构建后安装即可在桌面看到新图标。"
    exit 2
}
if (-not $node) {
    Write-Host "[error] 未找到 node，无法执行 hvigorw.js。"
    exit 2
}

# 3. 构建侧载 HAP（assembleHap 默认产出 unsigned HAP，可直接 hdc 侧载）
Write-Host "[build] node $hvigorScript assembleHap --mode module -p product=default -p buildMode=release"
& $node $hvigorScript assembleHap --mode module -p product=default -p buildMode=release
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[error] 构建失败（exit=$LASTEXITCODE）。"
    exit $LASTEXITCODE
}

$hap = Get-ChildItem output -Filter '*.hap' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '\.part$' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $hap) {
    Write-Host "[error] 构建完成但未在 output\ 找到 HAP 产物。"
    exit 1
}
Write-Host "`n[ok] 侧载包: $($hap.FullName)"
Write-Host "安装: hdc install -r `"$($hap.FullName)`""
Write-Host "图标方案已写入 module.json5，安装后桌面图标立即可见。"
