// Ion Windows — the application manifest every Ion exe carries: a Common Controls v6
// dependency, so TaskDialogIndirect (messageBox) resolves. The object holds a finished
// RT_MANIFEST resource tree in .rsrc$01, the shape a resource compiler emits, so it links
// with zig cc and clang+lld alike without one.
//
// Language 0 marks it a MinGW default manifest: lld in MinGW mode drops it when the app
// links its own manifest resource (llvm WindowsResourceParser::cleanUpManifests).

__asm__(
    ".section .rsrc$01,\"dr\"\n"
    ".Lroot:\n"
    ".long 0, 0\n.short 0, 0, 0, 1\n"
    ".long 24, 0x80000000 + (.Ltype - .Lroot)\n"
    ".Ltype:\n"
    ".long 0, 0\n.short 0, 0, 0, 1\n"
    ".long 1, 0x80000000 + (.Lname - .Lroot)\n"
    ".Lname:\n"
    ".long 0, 0\n.short 0, 0, 0, 1\n"
    ".long 0, .Lentry - .Lroot\n"
    ".Lentry:\n"
    ".rva .Lmanifest\n"
    ".long .Lend - .Lmanifest, 0, 0\n"
    ".Lmanifest:\n"
    ".ascii \"<?xml version='1.0' encoding='UTF-8' standalone='yes'?>\\r\\n\"\n"
    ".ascii \"<assembly xmlns='urn:schemas-microsoft-com:asm.v1' manifestVersion='1.0'>\\r\\n\"\n"
    ".ascii \"  <dependency>\\r\\n\"\n"
    ".ascii \"    <dependentAssembly>\\r\\n\"\n"
    ".ascii \"      <assemblyIdentity type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'/>\\r\\n\"\n"
    ".ascii \"    </dependentAssembly>\\r\\n\"\n"
    ".ascii \"  </dependency>\\r\\n\"\n"
    ".ascii \"</assembly>\\r\\n\"\n"
    ".Lend:\n"
    ".text\n"
);
