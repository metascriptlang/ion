; NSIS helper macros for ion installer.
;
; Trimmed-down adaptation of tauri-bundler's nsis/utils.nsh — we keep only
; the AUMID-on-shortcut macro (essential for Toast WinRT upgrade in Phase 5
; v2) and drop the Tauri-plugin-dependent process-kill / multi-mode helpers.
;
; Reference: ~/metascript/refs/tauri/crates/tauri-bundler/src/bundle/windows/nsis/utils.nsh

; Sets the AppUserModelID on a .lnk shortcut so Windows routes Toast clicks
; back to our app. Without this, modern Toast (WinRT) won't deliver clicks
; even when the AUMID is set programmatically — the shortcut is the binding.
!macro SetLnkAppUserModelId shortcut
  !insertmacro ComHlpr_CreateInProcInstance ${CLSID_ShellLink} ${IID_IShellLink} r0 ""
  ${If} $0 P<> 0
    ${IUnknown::QueryInterface} $0 '("${IID_IPersistFile}",.r1)'
    ${If} $1 P<> 0
      ${IPersistFile::Load} $1 '("${shortcut}", ${STGM_READWRITE})'
      ${IUnknown::QueryInterface} $0 '("${IID_IPropertyStore}",.r2)'
      ${If} $2 P<> 0
        System::Call 'Oleaut32::SysAllocString(w "${BUNDLEID}") i.r3'
        System::Call '*${SYSSTRUCT_PROPERTYKEY}(${PKEY_AppUserModel_ID})p.r4'
        System::Call '*${SYSSTRUCT_PROPVARIANT}(${VT_BSTR},,&i4 $3)p.r5'
        ${IPropertyStore::SetValue} $2 '($4,$5)'

        System::Call 'Oleaut32::SysFreeString($3)'
        System::Free $4
        System::Free $5
        ${IPropertyStore::Commit} $2 ""
        ${IUnknown::Release} $2 ""
        ${IPersistFile::Save} $1 '("${shortcut}",1)'
      ${EndIf}
      ${IUnknown::Release} $1 ""
    ${EndIf}
    ${IUnknown::Release} $0 ""
  ${EndIf}
!macroend
