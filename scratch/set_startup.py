import winreg

key = winreg.OpenKey(
    winreg.HKEY_CURRENT_USER,
    r"Software\Microsoft\Windows\CurrentVersion\Run",
    0,
    winreg.KEY_SET_VALUE
)
val = '"C:\\bluetooth keyboard and mouse\\MobileKemo.exe"'
winreg.SetValueEx(key, "MobileKemo", 0, winreg.REG_SZ, val)
winreg.CloseKey(key)

# Verify
key_read = winreg.OpenKey(
    winreg.HKEY_CURRENT_USER,
    r"Software\Microsoft\Windows\CurrentVersion\Run",
    0,
    winreg.KEY_READ
)
result, _ = winreg.QueryValueEx(key_read, "MobileKemo")
winreg.CloseKey(key_read)
print(f"REGISTRY AUTO-RUN VERIFIED: {result}")
