; ion Windows installer — minimal NSIS template.
;
; This file is **rendered** by make-app-windows.sh which substitutes the
; @@VARS@@ placeholders below before invoking makensis. Don't try to compile
; this file directly — `${VAR}` ↔ @@VAR@@ substitution must happen first.
;
; Inspired by tauri-bundler's installer.nsi but stripped to v0 essentials:
;   - per-machine install (admin elevation)
;   - WebView2 Runtime check + Evergreen Bootstrapper download
;   - Start Menu shortcut with AUMID embedded
;   - URL scheme registry registration
;   - Add/Remove Programs entry + uninstaller
;
; Skipped (Tauri ships these, ion v0 doesn't need yet):
;   - License page, sidebar/header images, language picker
;   - Process-kill on upgrade (Tauri plugin dependency)
;   - Per-user install mode (admin-only v0)

Unicode true
ManifestDPIAware true
ManifestDPIAwareness PerMonitorV2

SetCompressor /SOLID lzma

!include MUI2.nsh
!include FileFunc.nsh
!include x64.nsh
!include "Win\COM.nsh"
!include "Win\Propkey.nsh"
!include "utils.nsh"

; ---- Parameters (substituted by make-app-windows.sh) ----
!define PRODUCTNAME       "@@PRODUCTNAME@@"
!define BUNDLEID          "@@BUNDLEID@@"
!define VERSION           "@@VERSION@@"
!define MAINBINARYNAME    "@@MAINBINARYNAME@@"
!define URLSCHEME         "@@URLSCHEME@@"
!define STAGINGDIR        "@@STAGINGDIR@@"
!define OUTFILE           "@@OUTFILE@@"
!define WEBVIEW2APPGUID   "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
!define WEBVIEW2BOOTSTRAPURL "https://go.microsoft.com/fwlink/p/?LinkId=2124703"

; ---- Installer metadata ----
Name "${PRODUCTNAME}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\${PRODUCTNAME}"
InstallDirRegKey HKLM "Software\${BUNDLEID}" "InstallPath"
RequestExecutionLevel admin
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName"     "${PRODUCTNAME}"
VIAddVersionKey "ProductVersion"  "${VERSION}"
VIAddVersionKey "FileVersion"     "${VERSION}.0"
VIAddVersionKey "FileDescription" "${PRODUCTNAME} Installer"

; ---- UI pages ----
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; ---- WebView2 Runtime check + install ----
; Inline at install time so end users with missing runtime get an automatic
; download (~2 MB bootstrap stub which pulls the full ~120 MB runtime).
;
; PowerShell-based download instead of a plugin (inetc / NSISdl): PowerShell
; ships with every Windows 10+ install, supports HTTPS, and avoids vendoring
; a platform-specific plugin DLL in our installer.
!macro EnsureWebView2Runtime
  DetailPrint "Checking WebView2 Runtime..."
  ReadRegStr $0 HKLM "Software\WOW6432Node\Microsoft\EdgeUpdate\Clients\${WEBVIEW2APPGUID}" "pv"
  ${If} $0 == ""
    ReadRegStr $0 HKCU "Software\Microsoft\EdgeUpdate\Clients\${WEBVIEW2APPGUID}" "pv"
  ${EndIf}
  ${If} $0 == ""
    DetailPrint "WebView2 Runtime not found — downloading bootstrapper..."
    nsExec::ExecToLog 'powershell -NoProfile -Command "Invoke-WebRequest -Uri ${WEBVIEW2BOOTSTRAPURL} -OutFile $\"$TEMP\MicrosoftEdgeWebView2Setup.exe$\" -UseBasicParsing"'
    Pop $1
    ${If} $1 != 0
      MessageBox MB_OK|MB_ICONEXCLAMATION "WebView2 Runtime download failed (exit $1). Install manually from https://developer.microsoft.com/microsoft-edge/webview2/ then retry."
      Abort
    ${EndIf}
    DetailPrint "Installing WebView2 Runtime (may take a minute)..."
    ExecWait '"$TEMP\MicrosoftEdgeWebView2Setup.exe" /silent /install'
    Delete "$TEMP\MicrosoftEdgeWebView2Setup.exe"
  ${Else}
    DetailPrint "WebView2 Runtime found: $0"
  ${EndIf}
!macroend

; ---- Install section ----
Section "Install" SecInstall
  SetOutPath "$INSTDIR"

  ; Stage all files from the payload dir. Trailing `/*` (POSIX glob) is
  ; understood by makensis on both macOS and Windows; `\*.*` (Windows shell)
  ; misbehaves under macOS makensis.
  File /r "${STAGINGDIR}/*"

  !insertmacro EnsureWebView2Runtime

  ; Start Menu shortcut with AUMID — required for future Toast WinRT routing.
  CreateDirectory "$SMPROGRAMS\${PRODUCTNAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCTNAME}\${PRODUCTNAME}.lnk" "$INSTDIR\${MAINBINARYNAME}" "" "$INSTDIR\${MAINBINARYNAME}" 0
  !insertmacro SetLnkAppUserModelId "$SMPROGRAMS\${PRODUCTNAME}\${PRODUCTNAME}.lnk"

  ; URL scheme — only register if a non-empty scheme was provided.
  StrCmp "${URLSCHEME}" "" skip_url_scheme 0
    WriteRegStr HKCR "${URLSCHEME}" "" "URL:${PRODUCTNAME} Protocol"
    WriteRegStr HKCR "${URLSCHEME}" "URL Protocol" ""
    WriteRegStr HKCR "${URLSCHEME}\DefaultIcon" "" "$INSTDIR\${MAINBINARYNAME},0"
    WriteRegStr HKCR "${URLSCHEME}\shell\open\command" "" '"$INSTDIR\${MAINBINARYNAME}" "%1"'
  skip_url_scheme:

  ; Install path + uninstaller registration.
  WriteRegStr HKLM "Software\${BUNDLEID}" "InstallPath" "$INSTDIR"
  WriteRegStr HKLM "Software\${BUNDLEID}" "Version"     "${VERSION}"

  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BUNDLEID}" "DisplayName"     "${PRODUCTNAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BUNDLEID}" "DisplayVersion"  "${VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BUNDLEID}" "Publisher"       "${PRODUCTNAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BUNDLEID}" "DisplayIcon"     "$INSTDIR\${MAINBINARYNAME},0"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BUNDLEID}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BUNDLEID}" "InstallLocation" "$INSTDIR"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BUNDLEID}" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BUNDLEID}" "NoRepair" 1
SectionEnd

; ---- Uninstall section ----
Section "Uninstall"
  ; URL scheme cleanup (only if we registered one).
  StrCmp "${URLSCHEME}" "" skip_url_unregister 0
    DeleteRegKey HKCR "${URLSCHEME}"
  skip_url_unregister:

  ; Remove all installed files. RMDir /r is dangerous but $INSTDIR is fixed
  ; to our app dir so it's bounded.
  RMDir /r "$INSTDIR"

  Delete "$SMPROGRAMS\${PRODUCTNAME}\${PRODUCTNAME}.lnk"
  RMDir  "$SMPROGRAMS\${PRODUCTNAME}"

  DeleteRegKey HKLM "Software\${BUNDLEID}"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BUNDLEID}"
SectionEnd
