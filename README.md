# Chekushka

<img width="620" height="395" alt="image" src="https://github.com/user-attachments/assets/9305ab9a-511d-47e2-b8eb-4e1c6cdd577b" />

<br>

**User account management tool that queries the PDC Emulator for lockout status and unlocks accounts on both the PDC Emulator and the nearest domain controller.**

## Overview

Chekushka is a PowerShell-based GUI tool designed for Active Directory administrators to quickly check user account status and unlock locked accounts. Unlike traditional AD tools that query any domain controller (which may have stale lockout information), Chekushka always queries the PDC Emulator for accurate lockout status and performs unlocks on both the PDC Emulator and the nearest domain controller to ensure immediate effect.

## Features

- Search users by login (sAMAccountName) or surname (sn) with wildcard support
- Real-time lockout status - always queries the PDC Emulator for authoritative information
- Dual unlock - unlocks the account on both:
  - PDC Emulator (authoritative source)
  - Nearest writable domain controller (for immediate replication)
- Comprehensive account information:
  - Locked / Disabled status (red highlight for critical states)
  - Password expiration date with policy calculation
  - Account expiration date
  - "Must change password at next logon" flag
- Clean WPF GUI with color-coded warnings
- Multi-match handling - grid view for surname searches with multiple results
- Enter key support - press Enter to search

## Requirements

| Requirement | Details |
|-------------|---------|
| OS | Windows Server 2012+ or Windows 10/11 (with RSAT) |
| PowerShell | Version 5.1 or higher |
| Modules | Active Directory module (RSAT) |
| Permissions | Read user attributes + Unlock-ADAccount privileges |
| .NET Framework | 4.5+ (included with PowerShell 5.1+) |
