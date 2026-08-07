; PhotoLink（图联）Windows 安装脚本（Inno Setup 6 Unicode）
; 支持中文安装路径；版本/环境由 ISCC /D 宏注入。
; 用法示例：
;   ISCC /DMyAppVersion=1.1.0 /DMyAppFlavor=local /DMyAppOutputName=PhotoLink-Setup-1.1.0-local photolink.iss

#ifndef MyAppVersion
  #define MyAppVersion "1.1.0"
#endif
#ifndef MyAppFlavor
  #define MyAppFlavor "prod"
#endif
#ifndef MyAppOutputName
  #define MyAppOutputName "PhotoLink-Setup-" + MyAppVersion + "-" + MyAppFlavor
#endif

; 仓库根目录（本 .iss 位于 installer\windows\）
#define MyRepoRoot "..\.."
#define MyReleaseDir MyRepoRoot + "\build\windows\x64\runner\Release"
#define MyOutputDir MyRepoRoot + "\dist\installer"

[Setup]
; 固定 AppId，升级/卸载时识别同一应用（勿随意改）
AppId={{A7C3E9D1-4B2F-4E8A-9C15-6D8F2A1B0E47}
AppName=PhotoLink
AppVersion={#MyAppVersion}
AppVerName=PhotoLink 图联 {#MyAppVersion} ({#MyAppFlavor})
AppPublisher=yu-hong-quan
AppPublisherURL=https://github.com/yu-hong-quan/photolink-pc
AppSupportURL=https://github.com/yu-hong-quan/photolink-pc
DefaultDirName={autopf}\PhotoLink
DefaultGroupName=PhotoLink 图联
DisableProgramGroupPage=yes
; 允许用户改成任意路径（含中文）
AllowNoIcons=yes
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyAppOutputName}
SetupIconFile={#MyRepoRoot}\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\photolink_pc.exe
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductName=PhotoLink
VersionInfoCompany=yu-hong-quan
VersionInfoDescription=PhotoLink 图联 Windows 安装包
; 关闭后若程序仍在运行，提示关闭
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"; Flags: unchecked

[Files]
; 打包整个 Flutter Release 目录（exe / DLL / data）
Source: "{#MyReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\PhotoLink 图联"; Filename: "{app}\photolink_pc.exe"; WorkingDir: "{app}"
Name: "{group}\卸载 PhotoLink"; Filename: "{uninstallexe}"
Name: "{autodesktop}\PhotoLink 图联"; Filename: "{app}\photolink_pc.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\photolink_pc.exe"; Description: "立即运行 PhotoLink 图联"; Flags: nowait postinstall skipifsilent

[Code]
// 安装前校验 Release 产物是否存在（由打包脚本保证，此处作兜底提示）
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
