<img width="1230" height="990" alt="image" src="https://github.com/user-attachments/assets/8c219877-1379-47bf-b7e7-574ba1db993d" />

# Chekushka — Modern Active Directory User Inspector

Chekushka is a lightweight WPF-based PowerShell tool for quickly inspecting and managing Active Directory user accounts.  
It provides a clean modern UI, fast search, FGPP‑aware password expiry logic, and one‑click account unlock.

This version includes a redesigned interface (Style A: Clean & Minimal) and multiple performance improvements.

---

## Features

### Search
- Search by **login (sAMAccountName)** or **surname**
- Automatic wildcard search for surnames
- Multi‑match selection via **Out‑GridView**

### User Information
Displays key AD attributes:
- Full name and login
- Disabled status
- Locked status
- Account expiration
- Password expiration (FGPP‑aware)
- Must‑change‑password flag

### Account Unlock
- Unlock button appears only when the account is locked
- Automatic refresh after unlock

### FGPP‑Aware Password Expiry
Correctly calculates password expiration using:
- Resultant Fine-Grained Password Policy (FGPP)
- Default Domain Password Policy fallback
- Special cases:
  - Password never expires
  - Must change at next logon
  - Unknown PasswordLastSet

### Modern UI
- Clean, minimal layout
- Larger readable fonts (Segoe UI)
- Flat buttons with accent colors
- Rounded corners and soft backgrounds
- Status bar with color-coded messages

### Performance Optimizations
- AD module loaded once
- Reduced AD property retrieval
- Cached domain password policy
- Simplified logic and UI updates

---

## Requirements

- Windows 10 or 11  
- PowerShell 5.1  
- RSAT / ActiveDirectory module  
- Domain-joined workstation or server  
- Permissions to read AD user objects  
- Optional: permissions to unlock accounts  

---

## Running the Tool

1. Save the script as `Chekushka.ps1`
2. Open PowerShell **as Administrator**
3. Run.
