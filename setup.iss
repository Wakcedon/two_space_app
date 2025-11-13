; setup.iss — улучшенный Inno Setup для Flutter (Windows, русский язык)
#define MyAppName "TwoSpace"
#define MyAppExeName "two_space_app.exe"
#define MyAppVersion "1.0.5-fix01"
#define MyAppPublisher "Synapse Corp"
#define MyAppURL "https://twospace.ru"

[Setup]
AppId={#MyAppName}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputBaseFilename={#MyAppName}_setup_v{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=.
WindowVisible=yes
; --- Язык интерфейса ---
ShowLanguageDialog=no
; ------------------------

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительные ярлыки:"; Flags: unchecked
Name: "quicklaunchicon"; Description: "Добавить ярлык в папку быстрого запуска"; GroupDescription: "Дополнительные ярлыки:"; Flags: unchecked; OnlyBelowVersion: 6.1
Name: "pinstartmenu"; Description: "Закрепить в меню «Пуск»"; GroupDescription: "Интеграция с Windows:"; Flags: unchecked; MinVersion: 6.2

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Запустить {#MyAppName}"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
function IsAppRunning(const FileName: string): Boolean;
var
  FSWbemLocator: Variant;
  FWMIService: Variant;
  FWbemObjectSet: Variant;
begin
  Result := False;
  try
    FSWbemLocator := CreateOleObject('WbemScripting.SWbemLocator');
    FWMIService := FSWbemLocator.ConnectServer('', 'root\CIMV2', '', '');
    FWbemObjectSet := FWMIService.ExecQuery(Format('SELECT * FROM CIM_Process WHERE Name="%s"', [FileName]));
    if not VarIsNull(FWbemObjectSet) and (FWbemObjectSet.Count > 0) then
      Result := True;
  except
    // Игнорируем ошибки (например, на старых Windows без WMI)
  end;
end;

function InitializeSetup(): Boolean;
begin
  // Завершить процесс, если он уже запущен
  if IsAppRunning(ExpandConstant('{#MyAppExeName}')) then
  begin
    MsgBox(ExpandConstant('{#MyAppName} сейчас запущен. Пожалуйста, закройте приложение и нажмите "Повторить".'), mbError, MB_OK);
    Result := False;
  end
  else
    Result := True;
end;
