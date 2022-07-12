unit uRESTResponseHelper;



interface



uses
  System.Classes, System.JSON.Readers, System.JSON.Types;


type
  TRESTResponseReader = class
  private
    jsonReader: TJSONTextReader;
    textReader: TStringReader;

    function GotoNext(path: string): boolean;

  protected
  public
    constructor Create(response: string);

    function GetNextValueAsDouble(path: string; var value: Double): Boolean;
    function GetNextValueAsInteger(path: string; var value: Integer): Boolean;
    function GetNextValueAsString(path: string; var value: string): Boolean;
    procedure SetResponse(response: string);

  end;



implementation



{ TRESTResponseReader }



constructor TRESTResponseReader.Create(response: string);
begin
  SetResponse(response);
end;



function TRESTResponseReader.GetNextValueAsDouble(path: string; var value: Double): Boolean;
begin
  if GotoNext(path) then
  begin
    value := jsonReader.ReadAsDouble;
    result := true;
  end
  else
    result := false;
end;



function TRESTResponseReader.GetNextValueAsInteger(path: string; var value: Integer): Boolean;
begin
  if GotoNext(path) then
  begin
    value := jsonReader.ReadAsInteger;
    result := true;
  end
  else
    result := false;
end;



function TRESTResponseReader.GetNextValueAsString(path: string; var value: string): Boolean;
begin
  if GotoNext(path) then
  begin
    value := jsonReader.ReadAsString;
    result := true;
  end
  else
    result := false;
end;



function TRESTResponseReader.GotoNext(path: string): boolean;
begin
  result := false;
  repeat
    result := jsonReader.Read;
  until (((jsonReader.TokenType = TJsonToken.PropertyName) and (jsonReader.path = path)) or (not result));
end;



procedure TRESTResponseReader.SetResponse(response: string);
begin
  if textReader <> nil then
    textReader.Destroy;
  if jsonReader <> nil then
    jsonReader.Destroy;

  textReader := TStringReader.Create(response);
  jsonReader := TJSONTextReader.Create(textReader);
end;



end.
