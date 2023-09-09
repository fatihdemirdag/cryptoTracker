program CryptoTracker;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  System.StrUtils,
  System.Diagnostics,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Generics.Collections,
  REST.Types,
  REST.Response.Adapter,
  REST.Client,
  Math,
  FMX.Memo,
  Windows,
  Winapi.ShellAPI,
  uExchangeDataHolder in 'uExchangeDataHolder.pas',
  uRESTResponseHelper in 'uRESTResponseHelper.pas',
  uUtilityMethods in 'uUtilityMethods.pas';


type

  TMessage = packed record
    t: TDateTime;
    symbol: string[16];
    rate: double;
    interval: cardinal;
    step: integer;
  end;

var
  cliExchangeInfo: TRESTClient;
  reqExchangeInfo: TRESTRequest;
  rspExchangeInfo: TRESTResponse;

  cliSymbolPrice: TRESTClient;
  reqSymbolPrice: TRESTRequest;
  rspSymbolPrice: TRESTResponse;

  dataHolder: TExchangeDataHolder;
  restReader: TRESTResponseReader;

  fStopWatch     : TStopwatch;
  fInterval      : double;
  fStepIndex     : integer;
  fTimeIndex     : double;
  fPriceCheckTime: double;
  fMessages      : TList<TMessage>;
  formatSettings : TFormatSettings;

  fMailOn   : Boolean;
  fMusicOn  : Boolean;
  fLineCount: integer;

  memRules    : TMemo;
  filterString: string;
  strfavs     : TStringList;
  fAllCoins   : Boolean;



function getElapsedTime: double;
begin
  if fStopWatch.IsHighResolution then
  begin
    result := fStopWatch.Elapsed.Ticks / fStopWatch.Elapsed.TicksPerMillisecond;
  end
  else
  begin
    result := fStopWatch.ElapsedMilliseconds;
  end;
end;



procedure checkRule(coin, condition: string; value: double; offset: cardinal);
var
  current, prev: double;
  ratio        : double;
  msg          : TMessage;
begin
  current := dataHolder.GetMarketData(coin + 'USDT', 0);

  if (LowerCase(condition) = 'change') and (dataHolder.GetDataDepth > (offset + 1)) then
  begin
    prev  := dataHolder.GetMarketData(coin + 'USDT', offset);
    ratio := (current - prev) * 100.0 / prev;

    if abs(ratio) >= value then
    begin
      msg.t        := now();
      msg.symbol   := coin;
      msg.rate     := round(ratio * 100) / 100;
      msg.interval := offset;
      msg.step     := fStepIndex;
      fMessages.Insert(0, msg);

      if msg.rate > 0.0 then
      begin
        mMailMessage := mMailMessage + DateToStr(msg.t) + ' ' + TimeToStr(msg.t) + ': ' + msg.symbol + ' raised ' +
            FloatToStr(msg.rate) + ' in the last ' + GetIntervalStr(msg.interval, fInterval) + #13 + #10;
      end
      else
      begin
        mMailMessage := mMailMessage + DateToStr(msg.t) + ' ' + TimeToStr(msg.t) + ': ' + msg.symbol + ' dropped ' +
            FloatToStr(msg.rate) + ' in the last ' + GetIntervalStr(msg.interval, fInterval) + #13 + #10;
      end;
    end;
  end;
end;



procedure cleanupMessages;
var
  I: cardinal;
begin
  if fMessages.Count > 0 then
  begin
    for I := 0 to fMessages.Count - 1 do
    begin
      if fMessages[I].step < fStepIndex - (300 div Trunc(fInterval / 1000.0)) then
        fMessages.DeleteRange(I, fMessages.Count - I);
    end;
  end;
end;



procedure DelayTimer;
var
  idleTime: double;
begin
  idleTime := fInterval * fStepIndex - getElapsedTime;
  if idleTime < 0 then
    idleTime := 0.0;

{$IF Defined(MSWINDOWS)}
  Sleep(round(idleTime));
{$ELSEIF Defined(POSIX)}
  usleep(idleTime * 1000);
{$ENDIF POSIX}
end;



procedure InitializeDataHolder;
var
  dataAva                      : Boolean;
  symbol, baseAsset, quoteAsset: string;
  id                           : integer;
begin
  if dataHolder <> nil then
    dataHolder.Destroy;
  dataHolder := TExchangeDataHolder.Create('binance');

  reqExchangeInfo.Execute;

  if restReader <> nil then
    restReader.Destroy;

  restReader := TRESTResponseReader.Create(rspExchangeInfo.Content);

  id := 0;
  repeat
    dataAva := true;
    dataAva := dataAva and restReader.GetNextValueAsString('symbols[' + inttostr(id) + '].symbol', symbol);
    dataAva := dataAva and restReader.GetNextValueAsString('symbols[' + inttostr(id) + '].baseAsset', baseAsset);
    dataAva := dataAva and restReader.GetNextValueAsString('symbols[' + inttostr(id) + '].quoteAsset', quoteAsset);
    Inc(id);
    if dataAva and EndsStr('USDT', symbol) then
    begin
      dataHolder.AddMarket(symbol, baseAsset, quoteAsset);
      Print(format('%1s ', [symbol]), TCTColor.LightGreen);
    end;
  until not dataAva;

  fMessages := TList<TMessage>.Create();
end;



procedure InitializeREST;
var
  I       : integer;
  strParam: string;
begin
  cliExchangeInfo          := TRESTClient.Create('https://api3.binance.com/api/v3/exchangeInfo');
  reqExchangeInfo          := TRESTRequest.Create(nil);
  rspExchangeInfo          := TRESTResponse.Create(nil);
  reqExchangeInfo.Client   := cliExchangeInfo;
  reqExchangeInfo.Response := rspExchangeInfo;

  cliSymbolPrice          := TRESTClient.Create('https://api3.binance.com/api/v3/ticker/price');
  reqSymbolPrice          := TRESTRequest.Create(nil);
  rspSymbolPrice          := TRESTResponse.Create(nil);
  reqSymbolPrice.Client   := cliSymbolPrice;
  reqSymbolPrice.Response := rspSymbolPrice;

  if not fAllCoins then
  begin
    strParam := '[';
    for I    := 1 to strfavs.Count - 2 do
    begin
      if I <> 1 then
        strParam := strParam + ',';
      strParam   := strParam + '"' + strfavs[I] + 'USDT' + '"';
    end;
    strParam := strParam + ']';

    reqSymbolPrice.Params.AddItem('symbols', strParam, TRestRequestParameterKind.pkGETorPOST, [poDoNotEncode],
        TRestContentType.ctTEXT_PLAIN);
  end;
end;



procedure InitializeRules;
var
  strInterval: string;
  I          : integer;
begin
  GetLocaleFormatSettings(LOCALE_SYSTEM_DEFAULT, formatSettings);
  formatSettings.DecimalSeparator := '.';

  memRules := TMemo.Create(nil);
  memRules.Lines.LoadFromFile('rules.txt');
  filterString := memRules.Lines[0];

  if memRules.Lines[1] = 'mailon' then
    fMailOn := true
  else
    fMailOn := false;

  if memRules.Lines[2] = 'musicon' then
    fMusicOn := true
  else
    fMusicOn := false;

  strInterval := memRules.Lines[3];
  fInterval   := StrToFloat(strInterval, formatSettings);

  fLineCount := StrToInt(memRules.Lines[4]);

  strfavs := TStringList.Create;
  strfavs.Clear;
  strfavs.Delimiter       := '#';
  strfavs.StrictDelimiter := true;
  strfavs.DelimitedText   := filterString;

  for I := 0 to strfavs.Count - 1 do
  begin
    if strfavs[I] = 'ALL' then
      fAllCoins := true;
  end;
end;



procedure parseRule(rule: string);
var
  strRule                       : TStringList;
  coin, condition, sValue       : string;
  sInterval, sAlertLevel, sEmail: string;
  value                         : double;
  interval                      : cardinal;
  iCoin                         : string;
  I                             : integer;
begin
  strRule := TStringList.Create;
  strRule.Clear;
  strRule.Delimiter       := ' ';
  strRule.StrictDelimiter := true;
  strRule.DelimitedText   := rule;

  if strRule.Count >= 2 then
  begin
    coin      := strRule[0];
    condition := strRule[1];
    if condition = 'value' then
    begin
      sValue      := strRule[2];
      sEmail      := strRule[3];
      sInterval   := '0';
      sAlertLevel := '0';
    end
    else if (condition = 'change') and (strRule.Count = 4) then
    begin
      sValue    := strRule[2];
      sInterval := strRule[3];
    end;

    value    := StrToFloat(sValue, formatSettings);
    interval := StrToInt(sInterval) div Trunc(fInterval / 1000.0);

    if coin = 'FAV' then
    begin
      for I := 0 to dataHolder.GetMarketCount - 1 do
      begin
        iCoin := dataHolder.GetMarket(I).coin;
        if filterString.Contains('#' + iCoin + '#') then
          checkRule(iCoin, condition, value, interval);
      end;
    end
    else if coin = 'ANY' then
    begin
      for I := 0 to dataHolder.GetMarketCount - 1 do
      begin
        iCoin := dataHolder.GetMarket(I).coin;
        checkRule(iCoin, condition, value, interval);
      end;
    end
    else
      checkRule(coin, condition, value, interval);
  end;
end;



procedure ParseRules;
var
  I: integer;
begin
  mMailMessage := '';

  for I := 5 to memRules.Lines.Count - 1 do
  begin
    parseRule(memRules.Lines[I]);
  end;

  if (mMailMessage <> '') and (fMailOn) then
  begin
    sendMail('Crypto alert ' + TimeToStr(now), mMailMessage);
  end
  else if (mMailMessage <> '') and (fMusicOn) then
  begin
    PlaySound;
  end;
end;



procedure StartTimer;
begin
  // fInterval  := 5000.0;
  fStepIndex := 0;
  fStopWatch.Start;
end;



procedure UpdatePrices;
var
  dataAva         : Boolean;
  id              : integer;
  symbol, strPrice: string;
  price           : double;
begin
  reqSymbolPrice.Execute;

  restReader.SetResponse(rspSymbolPrice.Content);

  id := 0;
  repeat
    dataAva := true;
    dataAva := dataAva and restReader.GetNextValueAsString('[' + inttostr(id) + '].symbol', symbol);
    dataAva := dataAva and restReader.GetNextValueAsString('[' + inttostr(id) + '].price', strPrice);
    Inc(id);
    price := StrToFloat(strPrice, formatSettings);

    dataHolder.NewMarketData(symbol, price);
  until not dataAva;

  dataHolder.ApplyNewData;
end;



procedure WriteCoin(coin: string);
var
  currValue, prevValue{, predValue, predAcc}   : double;
  val1min, val5min, val15min, val30min, val1h: double;
  rat1min, rat5min, rat15min, rat30min, rat1h: double;
  clrInc, clrDec, clrNat                     : TCTColor;
begin
  clrInc := TCTColor.LightGreen;
  clrDec := TCTColor.LightRed;
  clrNat := TCTColor.White;
  currValue := 0.0;

  if dataHolder.GetDataDepth >= 1 then
  begin
    currValue := dataHolder.GetMarketData(coin + 'USDT', 0);
    prevValue := dataHolder.GetMarketData(coin + 'USDT', 1);
    //predValue := dataHolder.GetMarketPrediction(coin + 'USDT', 0);
    //predAcc   := dataHolder.GetPredictionAccuracy(coin + 'USDT', 0);

    if prevValue > currValue then
      Print(format('%8s  %16s ', [coin, FloatFormatAsString(currValue, 8)]), clrDec)
    else if prevValue = currValue then
      Print(format('%8s  %16s ', [coin, FloatFormatAsString(currValue, 8)]), clrNat)
    else
      Print(format('%8s  %16s ', [coin, FloatFormatAsString(currValue, 8)]), clrInc);
  end
  else
    Print(format('%8s  %16s ', [coin, '0.00000000']), clrNat);

  if dataHolder.GetDataDepth > Trunc(60000.0 / fInterval) then
  begin
    val1min := dataHolder.GetMarketData(coin + 'USDT', Trunc(60000.0 / fInterval));
    rat1min := (currValue - val1min) / val1min * 100.0;

    if rat1min = 0.0 then
      Print(format('%7s ', [FloatFormatAsString(rat1min, 2)]), clrNat)
    else if rat1min > 0.0 then
      Print(format('%7s ', [FloatFormatAsString(rat1min, 2)]), clrInc)
    else
      Print(format('%7s ', [FloatFormatAsString(rat1min, 2)]), clrDec);
  end
  else
    Print(format('%7s ', ['0.00']), clrNat);

  if dataHolder.GetDataDepth > Trunc(300000.0 / fInterval) then
  begin
    val5min := dataHolder.GetMarketData(coin + 'USDT', Trunc(300000.0 / fInterval));
    rat5min := (currValue - val5min) / val5min * 100.0;

    if rat5min = 0.0 then
      Print(format('%7s ', [FloatFormatAsString(rat5min, 2)]), clrNat)
    else if rat5min > 0.0 then
      Print(format('%7s ', [FloatFormatAsString(rat5min, 2)]), clrInc)
    else
      Print(format('%7s ', [FloatFormatAsString(rat5min, 2)]), clrDec);
  end
  else
    Print(format('%7s ', ['0.00']), clrNat);

  if dataHolder.GetDataDepth > Trunc(900000.0 / fInterval) then
  begin
    val15min := dataHolder.GetMarketData(coin + 'USDT', Trunc(900000.0 / fInterval));
    rat15min := (currValue - val15min) / val15min * 100.0;

    if rat15min = 0.0 then
      Print(format('%7s ', [FloatFormatAsString(rat15min, 2)]), clrNat)
    else if rat15min > 0.0 then
      Print(format('%7s ', [FloatFormatAsString(rat15min, 2)]), clrInc)
    else
      Print(format('%7s ', [FloatFormatAsString(rat15min, 2)]), clrDec);
  end
  else
    Print(format('%7s ', ['0.00']), clrNat);

  if dataHolder.GetDataDepth > Trunc(1800000.0 / fInterval) then
  begin
    val30min := dataHolder.GetMarketData(coin + 'USDT', Trunc(1800000.0 / fInterval));
    rat30min := (currValue - val30min) / val30min * 100.0;

    if rat30min = 0.0 then
      Print(format('%7s ', [FloatFormatAsString(rat30min, 2)]), clrNat)
    else if rat30min > 0.0 then
      Print(format('%7s ', [FloatFormatAsString(rat30min, 2)]), clrInc)
    else
      Print(format('%7s ', [FloatFormatAsString(rat30min, 2)]), clrDec);
  end
  else
    Print(format('%7s ', ['0.00']), clrNat);

  if dataHolder.GetDataDepth > Trunc(3600000.0 / fInterval) then
  begin
    val1h := dataHolder.GetMarketData(coin + 'USDT', Trunc(3600000.0 / fInterval));
    rat1h := (currValue - val1h) / val1h * 100.0;

    if rat1h = 0.0 then
      Print(format('%7s |', [FloatFormatAsString(rat1h, 2)]), clrNat)
    else if rat1h > 0.0 then
      Print(format('%7s |', [FloatFormatAsString(rat1h, 2)]), clrInc)
    else
      Print(format('%7s |', [FloatFormatAsString(rat1h, 2)]), clrDec);
  end
  else
    Print(format('%7s |', ['0.00']), clrNat);
end;



procedure WriteMessage(index: cardinal);
var
  msg                       : TMessage;
  color                     : TCTColor;
  text, intervalstr, timestr: string;
begin
  msg := fMessages[index];

  timestr := TimeToStr(msg.t);

  if msg.rate < 0.0 then
  begin
    if msg.step >= fStepIndex - 1 then
      color := TCTColor.White
    else if msg.step >= fStepIndex - 15 then
      color := TCTColor.LightRed
    else if msg.step >= fStepIndex - 90 then
      color := TCTColor.Red
    else
      color := TCTColor.DarkGray;
    text    := ' lost ';
  end
  else
  begin
    if msg.step >= fStepIndex - 1 then
      color := TCTColor.White
    else if msg.step >= fStepIndex - 15 then
      color := TCTColor.LightGreen
    else if msg.step >= fStepIndex - 90 then
      color := TCTColor.Green
    else
      color := TCTColor.DarkGray;
    text    := ' gained ';
  end;

  intervalstr := GetIntervalStr(msg.interval, fInterval);

  Print(' ' + timestr + ' [' + inttostr(msg.step) + ']: ' + msg.symbol + text + FloatToStr(msg.rate) + ' in ' +
      intervalstr, color);
end;



procedure UpdateScreen;
var
  I: integer;
begin
  Print(' ' + #13 + #10, TCTColor.White);
  Print('  Coin         Value        1 min   5 min   15min   30min    1 h                                                    '
      + #13 + #10, TCTColor.White);
  Print('-------- ----------------- ------- ------- ------- ------- -------   -----------------------------------------------'
      + #13 + #10, TCTColor.White);

  for I := 0 to fLineCount do
  begin
    if (I div 2 < strfavs.Count - 2) and (I mod 2 = 0) and (strfavs[I div 2 + 1] <> 'ALL') then
      WriteCoin(strfavs[I div 2 + 1])
    else
      Print('                                                                   |', TCTColor.White);

    if I < fMessages.Count then
      WriteMessage(I);

    Print('' + #13 + #10, TCTColor.Black);
  end;

  Print(DateToStr(now) + ' ' + TimeToStr(now) + ': ' + 'Check Time ' + FloatToStr(round(fPriceCheckTime)) + ' msec' +
      #13 + #10, TCTColor.Cyan);

  if fMailOn then
    Print('[    Mail On    ] ', TCTColor.LightGreen)
  else
    Print('[    Mail Off   ] ', TCTColor.LightRed);

  if fMusicOn then
    Print('[   Alert On    ] ', TCTColor.LightGreen)
  else
    Print('[   Alert Off   ] ', TCTColor.LightRed);

  Print('Interval: ', TCTColor.White);
  Print(FloatToStr(fInterval), TCTColor.Magenta);
  Print(' ms ', TCTColor.White);

  Print('    DataSize: ', TCTColor.White);
  Print(inttostr(rspSymbolPrice.Content.length), TCTColor.Cyan);
  Print(' bytes ', TCTColor.White);

  Print('    Step: ', TCTColor.White);
  Print(inttostr(fStepIndex), TCTColor.Cyan);
end;



begin
  InitializeRules;
  InitializeREST;
  InitializeDataHolder;
  InitializeMail;

  StartTimer;
  fStepIndex := 0;
  repeat
    try
      if mPlayer <> nil then
        mPlayer.Stop;

      fTimeIndex := getElapsedTime;
      UpdatePrices;
      fPriceCheckTime := getElapsedTime - fTimeIndex;
      ParseRules;
      UpdateScreen;
      cleanupMessages;

      Inc(fStepIndex);
      DelayTimer;
    except
      on E: Exception do
        Writeln(E.ClassName, ': ', E.Message);
    end;
  until false;


end.
