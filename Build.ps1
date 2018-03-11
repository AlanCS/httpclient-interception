param(
    [Parameter(Mandatory = $false)][string] $Configuration = "Release",
    [Parameter(Mandatory = $false)][string] $VersionSuffix = "",
    [Parameter(Mandatory = $false)][string] $OutputPath = "",
    [Parameter(Mandatory = $false)][switch] $SkipTests,
    [Parameter(Mandatory = $false)][switch] $DisableCodeCoverage
)

$ErrorActionPreference = "Stop"

$solutionPath = Split-Path $MyInvocation.MyCommand.Definition
$solutionFile = Join-Path $solutionPath "HttpClientInterception.sln"
$libraryProject = Join-Path $solutionPath "src\HttpClientInterception\JustEat.HttpClientInterception.csproj"
$testProject = Join-Path $solutionPath "tests\HttpClientInterception.Tests\JustEat.HttpClientInterception.Tests.csproj"

$dotnetVersion = "2.1.300-preview1-008174"

if ($OutputPath -eq "") {
    $OutputPath = Join-Path "$(Convert-Path "$PSScriptRoot")" "artifacts"
}

if ($env:CI -ne $null) {
    if (($VersionSuffix -eq "" -and $env:APPVEYOR_REPO_TAG -eq "false" -and $env:APPVEYOR_BUILD_NUMBER -ne "") -eq $true) {
        $ThisVersion = $env:APPVEYOR_BUILD_NUMBER -as [int]
        $VersionSuffix = "beta" + $ThisVersion.ToString("0000")
    }
}

$installDotNetSdk = $false;

if (((Get-Command "dotnet.exe" -ErrorAction SilentlyContinue) -eq $null) -and ((Get-Command "dotnet" -ErrorAction SilentlyContinue) -eq $null)) {
    Write-Host "The .NET Core SDK is not installed."
    $installDotNetSdk = $true
}
else {
    $installedDotNetVersion = (dotnet --version | Out-String).Trim()
    if ($installedDotNetVersion -ne $dotnetVersion) {
        Write-Host "The required version of the .NET Core SDK is not installed. Expected $dotnetVersion but $installedDotNetVersion was found."
        $installDotNetSdk = $true
    }
}

if ($installDotNetSdk -eq $true) {
    $env:DOTNET_INSTALL_DIR = Join-Path "$(Convert-Path "$PSScriptRoot")" ".dotnetcli"

    if (!(Test-Path $env:DOTNET_INSTALL_DIR)) {
        mkdir $env:DOTNET_INSTALL_DIR | Out-Null
        $installScript = Join-Path $env:DOTNET_INSTALL_DIR "install.ps1"
        Invoke-WebRequest "https://raw.githubusercontent.com/dotnet/cli/v$dotnetVersion/scripts/obtain/dotnet-install.ps1" -OutFile $installScript -UseBasicParsing
        & $installScript -Version "$dotnetVersion" -InstallDir "$env:DOTNET_INSTALL_DIR" -NoPath
    }

    $env:PATH = "$env:DOTNET_INSTALL_DIR;$env:PATH"
    $dotnet = Join-Path "$env:DOTNET_INSTALL_DIR" "dotnet.exe"
}
else {
    $dotnet = "dotnet"
}

function DotNetPack {
    param([string]$Project)

    if ($VersionSuffix) {
        & $dotnet pack $Project --output $OutputPath --configuration $Configuration --version-suffix "$VersionSuffix" --include-symbols --include-source
    }
    else {
        & $dotnet pack $Project --output $OutputPath --configuration $Configuration --include-symbols --include-source
    }
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet pack failed with exit code $LASTEXITCODE"
    }
}

function DotNetTest {
    param([string]$Project)

    if ($DisableCodeCoverage -eq $true) {
        & $dotnet test $Project --output $OutputPath --framework $framework
    }
    else {

        if ($installDotNetSdk -eq $true) {
            $dotnetPath = $dotnet
        }
        else {
            $dotnetPath = (Get-Command "dotnet.exe").Source
        }

        $nugetPath = Join-Path $env:USERPROFILE ".nuget\packages"

        $openCoverVersion = "4.6.519"
        $openCoverPath = Join-Path $nugetPath "OpenCover\$openCoverVersion\tools\OpenCover.Console.exe"

        $reportGeneratorVersion = "3.1.2"
        $reportGeneratorPath = Join-Path $nugetPath "ReportGenerator\$reportGeneratorVersion\tools\ReportGenerator.exe"

        $coverageOutput = Join-Path $OutputPath "code-coverage.xml"
        $reportOutput = Join-Path $OutputPath "coverage"

        & $openCoverPath `
            `"-target:$dotnetPath`" `
            `"-targetargs:test $Project --output $OutputPath`" `
            -output:$coverageOutput `
            -hideskipped:All `
            -mergebyhash `
            -oldstyle `
            -register:user `
            -skipautoprops `
            `"-filter:+[JustEat.HttpClientInterception]* -[JustEat.HttpClientInterception.Tests]*`"

        & $reportGeneratorPath `
            `"-reports:$coverageOutput`" `
            `"-targetdir:$reportOutput`" `
            -verbosity:Warning
    }

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet test failed with exit code $LASTEXITCODE"
    }
}

Write-Host "Packaging solution..." -ForegroundColor Green

DotNetPack $libraryProject

if ($SkipTests -eq $false) {
    Write-Host "Running tests..." -ForegroundColor Green
    DotNetTest $testProject
}
