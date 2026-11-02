// Diagnostic only. Places NO orders. Tester-only bar/indicator dump used to
// cross-check ResearchPullback entries against its written spec.
#property version "1.00"
#property description "Diagnostic: dumps closed bars, EMA/ATR values and spread. No trading."
input int FastEMA=20;
input int SlowEMA=50;
input int ATRPeriod=14;
input int WarmupBars=1500;
int hf,hs,ha,file=INVALID_HANDLE;
datetime lastBar=0;

int OnInit()
{
 if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
 hf=iMA(_Symbol,_Period,FastEMA,0,MODE_EMA,PRICE_CLOSE);
 hs=iMA(_Symbol,_Period,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
 ha=iATR(_Symbol,_Period,ATRPeriod);
 if(hf==INVALID_HANDLE||hs==INVALID_HANDLE||ha==INVALID_HANDLE) return INIT_FAILED;
 file=FileOpen("bardump_"+_Symbol+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
 if(file==INVALID_HANDLE) return INIT_FAILED;
 FileWrite(file,"time","open","high","low","close","spread_pts","ema_fast","ema_slow","atr","first_tick_time","first_bid","first_ask","phase");
 return INIT_SUCCEEDED;
}

void Row(const MqlRates &r,double f,double s,double a,string ft,string fb,string fa,string phase)
{
 FileWrite(file,TimeToString(r.time,TIME_DATE|TIME_SECONDS),DoubleToString(r.open,_Digits),DoubleToString(r.high,_Digits),DoubleToString(r.low,_Digits),DoubleToString(r.close,_Digits),
   (string)r.spread,DoubleToString(f,8),DoubleToString(s,8),DoubleToString(a,8),ft,fb,fa,phase);
}

void OnTick()
{
 datetime cur=iTime(_Symbol,_Period,0);
 if(cur==0||cur==lastBar) return;
 MqlTick t; SymbolInfoTick(_Symbol,t);
 if(lastBar==0)
 {
  MqlRates rr[]; double f[],s[],a[];
  int n=CopyRates(_Symbol,_Period,1,WarmupBars,rr);
  if(n>0 && CopyBuffer(hf,0,1,n,f)==n && CopyBuffer(hs,0,1,n,s)==n && CopyBuffer(ha,0,1,n,a)==n)
   for(int i=0;i<n-1;i++) Row(rr[i],f[i],s[i],a[i],"","","","warmup");
 }
 MqlRates b[1]; double f1[1],s1[1],a1[1];
 if(CopyRates(_Symbol,_Period,1,1,b)!=1||CopyBuffer(hf,0,1,1,f1)!=1||CopyBuffer(hs,0,1,1,s1)!=1||CopyBuffer(ha,0,1,1,a1)!=1) return;
 lastBar=cur;
 // Row = the just-closed bar; first_tick_* = first tick of the following (current) bar.
 Row(b[0],f1[0],s1[0],a1[0],TimeToString(t.time,TIME_DATE|TIME_SECONDS),DoubleToString(t.bid,_Digits),DoubleToString(t.ask,_Digits),"live");
}

void OnDeinit(const int reason)
{
 if(file!=INVALID_HANDLE) FileClose(file);
 PrintFormat("BarDump: digits=%d point=%.10f ticksize=%.10f contract=%.2f stopslevel=%d volmin=%.2f step=%.2f",
   _Digits,_Point,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),
   (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP));
}
