// Script (no trading). Imports monthly tick binaries produced by split_ticks.py into a
// custom symbol whose specification is copied from the broker symbol (Origin).
// Input files: MQL5/Files/gd_ticks/ticks_YYYYMM.bin, records <int64 time_msc, double bid, double ask>.
// Log: MQL5/Files/gd_ticks/import_log.csv  (month, file_ticks, imported, read_back, first, last)
#property script_show_inputs
#property version "1.02"
input string CustomName="XAUUSD_GD";
input string Origin="XAUUSDm";
input string FromMonth="202111";
input string ToMonth="202512";
input bool   CloseTerminal=true;
input bool   ImportTicks=true;   // false = only (re)apply the spec fixes below
input bool   BuildRates=true;    // build M1 bars (bid OHLC) from the same tick files; tester needs bar history

struct RawTick { long msc; double bid; double ask; };

int MonthNext(const int yyyymm){ int y=yyyymm/100,m=yyyymm%100; m++; if(m>12){m=1;y++;} return y*100+m; }

void OnStart()
{
 bool custom=false;
 if(!SymbolExist(CustomName,custom))
 {
  if(!CustomSymbolCreate(CustomName,"Custom\\GoldDesk",Origin)) { PrintFormat("Import: CustomSymbolCreate failed %d",GetLastError()); Finish(); return; }
  CustomSymbolSetString(CustomName,SYMBOL_DESCRIPTION,"XAUUSD ticks from XAUUSD_GMT+0_2020~2026.csv (GMT+0), spec copied from "+Origin);
  PrintFormat("Import: created %s from %s",CustomName,Origin);
 }
 else if(!custom) { PrintFormat("Import: %s exists and is not custom - abort",CustomName); Finish(); return; }
 SymbolSelect(CustomName,true);
 // v1.01: CustomSymbolCreate(origin) left SYMBOL_TRADE_TICK_SIZE / TICK_VALUE at 0 in build 6230.
 // Copy them explicitly from the origin so price rounding and P/L match the broker symbol.
 SymbolSelect(Origin,true);
 double ots=SymbolInfoDouble(Origin,SYMBOL_TRADE_TICK_SIZE),otv=SymbolInfoDouble(Origin,SYMBOL_TRADE_TICK_VALUE);
 double otvp=SymbolInfoDouble(Origin,SYMBOL_TRADE_TICK_VALUE_PROFIT),otvl=SymbolInfoDouble(Origin,SYMBOL_TRADE_TICK_VALUE_LOSS);
 PrintFormat("Import origin %s: ticksize=%.5f tickvalue=%.5f tv_profit=%.5f tv_loss=%.5f",Origin,ots,otv,otvp,otvl);
 if(ots>0) CustomSymbolSetDouble(CustomName,SYMBOL_TRADE_TICK_SIZE,ots);
 if(otv>0) CustomSymbolSetDouble(CustomName,SYMBOL_TRADE_TICK_VALUE,otv);
 PrintFormat("Import spec %s: digits=%d point=%.5f ticksize=%.5f contract=%.2f volmin=%.2f step=%.2f stopslevel=%d swap_mode=%d swap_long=%.4f swap_short=%.4f swap3=%d calc_mode=%d margin_init=%.2f",
   CustomName,(int)SymbolInfoInteger(CustomName,SYMBOL_DIGITS),SymbolInfoDouble(CustomName,SYMBOL_POINT),SymbolInfoDouble(CustomName,SYMBOL_TRADE_TICK_SIZE),
   SymbolInfoDouble(CustomName,SYMBOL_TRADE_CONTRACT_SIZE),SymbolInfoDouble(CustomName,SYMBOL_VOLUME_MIN),SymbolInfoDouble(CustomName,SYMBOL_VOLUME_STEP),
   (int)SymbolInfoInteger(CustomName,SYMBOL_TRADE_STOPS_LEVEL),(int)SymbolInfoInteger(CustomName,SYMBOL_SWAP_MODE),SymbolInfoDouble(CustomName,SYMBOL_SWAP_LONG),
   SymbolInfoDouble(CustomName,SYMBOL_SWAP_SHORT),(int)SymbolInfoInteger(CustomName,SYMBOL_SWAP_ROLLOVER3DAYS),(int)SymbolInfoInteger(CustomName,SYMBOL_TRADE_CALC_MODE),
   SymbolInfoDouble(CustomName,SYMBOL_MARGIN_INITIAL));


 if(BuildRates) ImportRates();
 if(!ImportTicks) { Print("Import: ticks not touched"); Finish(); return; }
 int log=FileOpen("gd_ticks\\import_log.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
 FileWrite(log,"month","file_ticks","imported","read_back","first_msc","last_msc","status");
 int from=(int)StringToInteger(FromMonth),to=(int)StringToInteger(ToMonth);
 long total=0; int bad=0;
 for(int ym=from; ym<=to; ym=MonthNext(ym))
 {
  string fn=StringFormat("gd_ticks\\ticks_%06d.bin",ym);
  int f=FileOpen(fn,FILE_READ|FILE_BIN);
  if(f==INVALID_HANDLE) { FileWrite(log,ym,0,0,0,0,0,"missing_file"); bad++; continue; }
  long n=(long)(FileSize(f)/sizeof(RawTick));
  RawTick raw[]; ArrayResize(raw,(int)n);
  uint got=FileReadArray(f,raw,0,(int)n); FileClose(f);
  if((long)got!=n || n==0) { FileWrite(log,ym,n,0,0,0,0,"read_error"); bad++; continue; }
  MqlTick t[]; ArrayResize(t,(int)n);
  for(int i=0;i<(int)n;i++)
  {
   ZeroMemory(t[i]);
   t[i].time_msc=raw[i].msc; t[i].time=(datetime)(raw[i].msc/1000);
   t[i].bid=raw[i].bid; t[i].ask=raw[i].ask; t[i].flags=TICK_FLAG_BID|TICK_FLAG_ASK;
  }
  long a=raw[0].msc,b=raw[(int)n-1].msc;
  ResetLastError();
  int imp=CustomTicksReplace(CustomName,a,b,t);
  MqlTick chk[]; int back=CopyTicksRange(CustomName,chk,COPY_TICKS_ALL,(ulong)a,(ulong)b);
  string st=(imp==(int)n && back==(int)n)?"ok":StringFormat("mismatch err=%d",GetLastError());
  if(st!="ok") bad++;
  FileWrite(log,ym,n,imp,back,a,b,st); FileFlush(log);
  PrintFormat("Import %06d: file=%I64d imported=%d read_back=%d %s",ym,n,imp,back,st);
  total+=n; ArrayFree(raw); ArrayFree(t); ArrayFree(chk);
 }
 FileClose(log);
 PrintFormat("Import done: %s total_ticks=%I64d problem_months=%d",CustomName,total,bad);
 Finish();
}

// M1 bars from tick files: bid OHLC, tick_volume = tick count, spread = minimum (ask-bid) in points.
void ImportRates()
{
 int log=FileOpen("gd_ticks\\rates_log.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
 FileWrite(log,"month","ticks","bars","replaced","read_back","status");
 int from=(int)StringToInteger(FromMonth),to=(int)StringToInteger(ToMonth); int bad=0; long tot=0;
 double pt=SymbolInfoDouble(CustomName,SYMBOL_POINT);
 for(int ym=from; ym<=to; ym=MonthNext(ym))
 {
  int f=FileOpen(StringFormat("gd_ticks\\ticks_%06d.bin",ym),FILE_READ|FILE_BIN);
  if(f==INVALID_HANDLE) { FileWrite(log,ym,0,0,0,0,"missing_file"); bad++; continue; }
  long n=(long)(FileSize(f)/sizeof(RawTick)); RawTick raw[]; ArrayResize(raw,(int)n);
  uint got=FileReadArray(f,raw,0,(int)n); FileClose(f);
  if((long)got!=n || n==0) { FileWrite(log,ym,n,0,0,0,"read_error"); bad++; continue; }
  MqlRates r[]; ArrayResize(r,0,50000); int nb=0; long cur=-1;
  for(int i=0;i<(int)n;i++)
  {
   long m=raw[i].msc/60000; double b=raw[i].bid; int sp=(int)MathRound((raw[i].ask-raw[i].bid)/pt);
   if(m!=cur)
   {
    ArrayResize(r,nb+1,50000); ZeroMemory(r[nb]);
    r[nb].time=(datetime)(m*60); r[nb].open=b; r[nb].high=b; r[nb].low=b; r[nb].close=b; r[nb].tick_volume=1; r[nb].spread=sp; r[nb].real_volume=0;
    nb++; cur=m;
   }
   else
   {
    int k=nb-1; if(b>r[k].high) r[k].high=b; if(b<r[k].low) r[k].low=b; r[k].close=b; r[k].tick_volume++; if(sp<r[k].spread) r[k].spread=sp;
   }
  }
  datetime a=r[0].time,z=r[nb-1].time;
  ResetLastError(); int rep=CustomRatesReplace(CustomName,a,z,r);
  MqlRates chk[]; int back=CopyRates(CustomName,PERIOD_M1,a,z,chk);
  string st=(rep==nb && back==nb)?"ok":StringFormat("mismatch err=%d",GetLastError()); if(st!="ok") bad++;
  FileWrite(log,ym,n,nb,rep,back,st); FileFlush(log);
  PrintFormat("Rates %06d: ticks=%I64d bars=%d replaced=%d read_back=%d %s",ym,n,nb,rep,back,st);
  tot+=nb; ArrayFree(raw); ArrayFree(r); ArrayFree(chk);
 }
 FileClose(log);
 PrintFormat("Rates done: %s total_bars=%I64d problem_months=%d",CustomName,tot,bad);
}

void Finish(){ if(CloseTerminal) TerminalClose(0); }
