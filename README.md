# Install Ubuntu
Various scripts for ubuntu installation.

## Nerds fonts on Windows Terminal
Install cool fonts for windows Terminal. Then edit Settings->Profile->Appearance

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/vatsan-madhavan/NerdFontInstaller/main/NerdFontInstaller.ps1" -OutFile "NerdFontInstaller.ps1"
.\NerdFontInstaller.ps1
```

## Powershell on Ubuntu

```powershell
curl -fsSL https://raw.githubusercontent.com/OctarinaCompany/InstallUbuntu/refs/heads/main/scripts/install_powershell.sh | bash
```

then 

```powershell
pwsh
```

