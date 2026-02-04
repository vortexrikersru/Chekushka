<img width="1162" height="937" alt="image" src="https://github.com/user-attachments/assets/5bc27d75-8712-4acd-8630-6be6ea28e1ef" />

---

# **Chekushka — Application Documentation**

## **1. Overview**
**Chekushka** is a PowerShell‑based WPF application designed for Active Directory (AD) user diagnostics and basic account management.  
Its primary purpose is to provide a fast, GUI‑driven way to:

- Search for AD users by **login** or **surname**
- Display key account status attributes
- Detect password expiration using **FGPP‑aware logic**
- Unlock locked accounts
- Highlight problematic states visually (red/bold indicators)

The tool is intended for helpdesk engineers, system administrators, and support teams who need a lightweight, reliable AD inspection utility.

---

## **2. Features**

### **2.1 Search Capabilities**
The application supports two search modes:

| Mode | Description |
|------|-------------|
| **Login** | Exact match on `sAMAccountName` |
| **Surname** | `sn -like` search with multi‑result selection via `Out‑GridView` |

The search field accepts partial surnames (e.g., “Ivanov*”).

---

### **2.2 Displayed User Information**
After a successful search, the UI displays:

| Field | Source | Description |
|-------|--------|-------------|
| **User** | `Name`, `SamAccountName` | Full name and login |
| **Disabled** | `Enabled` | Whether the account is disabled |
| **Locked** | `LockedOut` | Whether the account is locked |
| **Password expired** | Calculated | Based on FGPP or Default Domain Policy |
| **Account expired** | `AccountExpirationDate` | Expiration date and status |
| **Must change password** | `pwdLastSet` | Indicates forced password change |
| **Password expires** | Calculated | Human‑readable expiry date |

Problematic states (disabled, locked, expired, etc.) are highlighted in **red bold text**.

---

### **2.3 Account Unlocking**
If the user is locked out:

- The **Unlock** button becomes visible.
- Clicking it runs `Unlock‑ADAccount`.
- After unlocking, the tool automatically refreshes the user data.

---

### **2.4 FGPP‑Aware Password Expiration Logic**
The application correctly handles:

- Default Domain Password Policy
- Fine‑Grained Password Policies (FGPP)

Logic flow:

1. Attempt to read FGPP via `Get‑ADUserResultantPasswordPolicy`.
2. If FGPP exists → use its `MaxPasswordAge`.
3. Otherwise → use the domain’s default `MaxPasswordAge`.
4. If both fail → fallback to **120 days**.

Special cases:

| Condition | Display |
|-----------|---------|
| `PasswordNeverExpires` | “Password never expires” |
| `pwdLastSet = 0` | “Must change at next logon” |
| Missing `PasswordLastSet` | “PasswordLastSet unknown” |

---

## **3. User Interface Structure**

### **3.1 Search Section**
- Radio buttons: **Login**, **Surname**
- Textbox for search input
- Search button
- Enter key also triggers search

### **3.2 Result Section**
Displays all user attributes in a structured grid.

### **3.3 Status Bar**
A text block at the bottom shows:

- Errors
- Warnings
- Operation results (e.g., “Account unlocked successfully”)

---

## **4. Internal Architecture**

### **4.1 XAML UI**
The interface is defined entirely in XAML and loaded at runtime using:

```powershell
[Windows.Markup.XamlReader]::Load()
```

### **4.2 Core Functions**

#### **Clear-Result**
Resets all UI fields and visual formatting.

#### **Get-DefaultDomainMaxPasswordAgeDays**
Reads the domain’s default password policy.  
Fallback: **120 days**.

#### **Format-Date**
Formats dates as `dd/MM/yyyy`.

#### **Mark-RedBold**
Applies red/bold styling to UI elements.

#### **Get-PasswordExpiryInfo**
Implements FGPP‑aware password expiration logic.

#### **Run-Search**
Main workflow:

1. Validate input  
2. Load AD module  
3. Perform search  
4. Handle multi‑result surname search  
5. Populate UI  
6. Highlight issues  
7. Enable unlock button if needed

#### **Unlock Handler**
Unlocks the selected user and refreshes the UI.

---

## **5. Error Handling**
The application gracefully handles:

- Missing AD module
- Invalid search input
- AD connectivity issues
- Cancelled multi‑selection
- Exceptions during unlock

All errors are displayed in the **status bar**.

---

## **6. Requirements**

### **6.1 Software**
- Windows PowerShell 5.1
- .NET Framework (WPF components)
- RSAT Active Directory module

### **6.2 Permissions**
To unlock accounts or read certain attributes, the operator must have:

- AD read permissions
- Account unlock rights (if unlocking is used)

---
