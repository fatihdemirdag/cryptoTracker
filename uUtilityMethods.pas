unit uUtilityMethods;


interface


uses
  System.StrUtils, System.SysUtils, System.Types,
  Windows, Winapi.ShellAPI,
  IdSMTP,
  IdExplicitTLSClientServerBase,
  IdMessage,
  IdSSLOpenSSL,
  FMX.Media;


type
  TCTColor = (Black = 0, Blue = 1, Green = 2, Cyan = 3, Red = 4, Magenta = 5, Brown = 6, LightGray = 7, DarkGray = 8,
      LightBlue = 9, LightGreen = 10, LightCyan = 11, LightRed = 12, LightMagenta = 13, Yellow = 14, White = 15);

function FloatFormatAsString(value: double; fraction: cardinal): string;
function GetIntervalStr(int: cardinal; interval: double): string;
procedure InitializeMail;
procedure PlaySound;
procedure Print(text: string; color: TCTColor);
procedure SendMail(header, msg: string);

var
  // Mail
  mSMTP        : TIdSMTP;
  mMessage     : TIdMessage;
  mSSLIOHandler: TIdSSLIOHandlerSocketOpenSSL;
  mMailMessage : string;

  // Media
  mPlayer: TMediaPlayer;


implementation



function FloatFormatAsString(value: double; fraction: cardinal): string;
var
  str       : string;
  loc, cfraq: integer;
  I         : integer;
begin
  str := FloatToStrF(value, TFloatFormat.ffNumber, fraction, 8);
  loc := Pos('.', str);
  if loc = 0 then
  begin
    str := str + '.';
    loc := length(str);
  end;

  cfraq := length(str) - loc;
  if cfraq <= fraction then
  begin
    for I := cfraq to fraction - 1 do
      str := str + '0';
  end
  else
    SetLength(str, loc + fraction);

  result := str;
end;



function GetIntervalStr(int: cardinal; interval: double): string;
var
  intervalTime: cardinal;
begin
  intervalTime := Trunc(int * interval / 1000);

  if (intervalTime mod 60 = 0) and (intervalTime mod 3600 <> 0) then
    result := inttostr(intervalTime div 60) + ' mins '
  else if intervalTime mod 3600 = 0 then
    result := inttostr(intervalTime div 3600) + ' hrs '
  else
    result := inttostr(intervalTime) + ' secs ';
end;



procedure InitializeMail;
begin
  mSSLIOHandler := TIdSSLIOHandlerSocketOpenSSL.Create(nil);

  mSMTP                             := TIdSMTP.Create(nil);
  mSMTP.Host                        := 'smtp.gmail.com';
  mSMTP.Port                        := 587;
  mSMTP.IOHandler                   := mSSLIOHandler;
  mSMTP.Username                    := 'crypto.fdemirdag@gmail.com';
  mSMTP.Password                    := 'pass147963';
  mSMTP.UseEhlo                     := true;
  mSMTP.ValidateAuthLoginCapability := true;
  mSMTP.UseTLS                      := IdExplicitTLSClientServerBase.utUseExplicitTLS;
  mSMTP.AuthType                    := satDefault;

  mSSLIOHandler.Host := 'smtp.gmail.com';
  mSSLIOHandler.Port := 587;

  mMessage := TIdMessage.Create(nil);
  mMessage.Recipients.Add;
  mMessage.Recipients[0].Address := 'crypto.fdemirdag@gmail.com';
  mMessage.Recipients[0].Domain  := 'gmail.com';
  mMessage.Recipients[0].text    := 'crypto.fdemirdag@gmail.com';
  mMessage.Recipients[0].User    := 'crypto.fdemirdag';
end;



procedure PlaySound;
begin
  if mPlayer = nil then
  begin
    mPlayer          := TMediaPlayer.Create(nil);
    mPlayer.FileName := 'bimp.mp3';
    mPlayer.Volume   := 100;
  end
  else
  begin
    mPlayer.Play;
  end;
end;



procedure Print(text: string; color: TCTColor);
var
  TextAttr: Byte;
begin
  TextAttr := cardinal(color) and $0F;
  SetConsoleTextAttribute(TTextRec(Output).Handle, TextAttr);

  Write(text);
end;



procedure SendMail(header, msg: string);
begin
  if not mSMTP.Connected then
    mSMTP.Connect;

  if mSMTP.Connected then
  begin
    if mSMTP.Authenticate then
    begin
      mMessage.Body.Clear;
      mMessage.Body.Add(msg);
      mMessage.Subject := header;
      mSMTP.Send(mMessage);
    end;
    mSMTP.Disconnect();
  end;
end;


end.