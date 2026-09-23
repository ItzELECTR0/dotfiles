@{
    RootModule = 'ELECTRO.System.psm1'
    ModuleVersion = '1.0.0'
    GUID = '181b8f41-bd7c-4f4f-87ee-c7a7ba7294db'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Show-Clients', 'Show-Monitors', 'Show-Devices', 'Start-macOS', 'Mount-macOS', 'Mount-Windows', 'Clear-CustOTALogs', 'wineprefix', 'Test-PodmanComposeProject', 'Start-PodmanContainerUpdate', 'Update-EFIstub', 'Update-AUR', 'Update-AURgitPackage', 'Update-ElectricAUR', 'Update-Flatpak', 'Update-DKMS', 'Update-System', 'Upgrade-System')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
