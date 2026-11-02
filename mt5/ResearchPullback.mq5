#property strict
#property version "0.11"
#property description "Independent research baseline. NOT a reproduction of Pau Perdices."
#property description "v0.11: diagnostics + deal export by position ID only. Trading rules identical to v0.10."
#include <Trade/Trade.mqh>
#include "ResearchExport.mqh"
input int FastEMA=20;
input int SlowEMA=50;
input int ATRPeriod=14;
input double StopATR=1.5;
input double RewardRisk=2.0;
input double Lots=0.01;
input ulong Magic=2601102;
input int DeviationPoints=20;
input int MaxSpreadPoints=100;
CTrade trade;
int fastHandle=INVALID_HANDLE,slowHandle=INVALID_HANDLE,atrHandle=INVALID_HANDLE;
datetime lastBar=0;
// ---- diagnostics only (v0.11): counters/statistics, never used in trading decisions ----
long dgBars=0,dgSkipPos=0,dgSkipTick=0,dgSignals=0,dgSigBuy=0,dgSigSell=0,dgSpreadBlocked=0,dgSpreadBlockedSig=0,dgStopsSkip=0,dgOrders=0,dgOrderFail=0;
long dgTicks=0; double dgSpMin=DBL_MAX,dgSpMax=0;
long dgHistAll[],dgHistBar[]; // spread in points, index clamped to DG_HIST-1
#define DG_HIST 20001
void DgAdd(long &h[],double pts){ int k=(int)MathRound(pts); if(k<0) k=0; if(k>=DG_HIST) k=DG_HIST-1; h[k]++; }
string DgStats(const long &h[],const int limit)
{
 long n=0,le=0; for(int i=0;i<DG_HIST;i++){ n+=h[i]; if(i<=limit) le+=h[i]; }
 if(n==0) return "n=0";
 int mn=-1,mx=-1,md=-1; long c=0;
 for(int i=0;i<DG_HIST;i++) if(h[i]>0){ if(mn<0) mn=i; mx=i; }
 for(int i=0;i<DG_HIST;i++){ c+=h[i]; if(c*2>=n){ md=i; break; } }
 return StringFormat("n=%I64d min=%dpt(%s) median=%dpt(%s) max=%dpt(%s) share<=%dpt=%.2f%%",n,
   mn,DoubleToString(mn*_Point,_Digits),md,DoubleToString(md*_Point,_Digits),mx,DoubleToString(mx*_Point,_Digits),limit,100.0*le/n);
}

int OnInit()
{
 if(FastEMA<1 || SlowEMA<=FastEMA || ATRPeriod<1 || StopATR<=0 || RewardRisk<=0 || Lots<=0 || MaxSpreadPoints<1 || DeviationPoints<0) return INIT_PARAMETERS_INCORRECT;
 double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
 if(step<=0 || Lots<minLot || Lots>maxLot || MathAbs(Lots/step-MathRound(Lots/step))>1e-7) return INIT_PARAMETERS_INCORRECT;
 fastHandle=iMA(_Symbol,_Period,FastEMA,0,MODE_EMA,PRICE_CLOSE);
 slowHandle=iMA(_Symbol,_Period,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
 atrHandle=iATR(_Symbol,_Period,ATRPeriod);
 if(fastHandle==INVALID_HANDLE || slowHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE) return INIT_FAILED;
 trade.SetExpertMagicNumber(Magic);
 trade.SetDeviationInPoints(DeviationPoints);
 trade.SetTypeFillingBySymbol(_Symbol);
 ArrayResize(dgHistAll,DG_HIST); ArrayInitialize(dgHistAll,0); ArrayResize(dgHistBar,DG_HIST); ArrayInitialize(dgHistBar,0);
 return INIT_SUCCEEDED;
}

void OnTick()
{
 { MqlTick dt; if(SymbolInfoTick(_Symbol,dt) && dt.ask>0 && dt.bid>0){ double sp=dt.ask-dt.bid; dgTicks++; if(sp<dgSpMin) dgSpMin=sp; if(sp>dgSpMax) dgSpMax=sp; DgAdd(dgHistAll,sp/_Point);} } // diagnostics only
 datetime current=iTime(_Symbol,_Period,0);
 if(current==0 || current==lastBar) return;
 if(BarsCalculated(slowHandle)<SlowEMA+2 || BarsCalculated(atrHandle)<ATRPeriod+2) return;
 double fast[1],slow[1],atr[1]; MqlRates bar[1];
 if(CopyBuffer(fastHandle,0,1,1,fast)!=1 || CopyBuffer(slowHandle,0,1,1,slow)!=1 || CopyBuffer(atrHandle,0,1,1,atr)!=1 || CopyRates(_Symbol,_Period,1,1,bar)!=1) return;
 lastBar=current;
 dgBars++;
 // Skip all existing positions on this symbol, including manual/other EA positions.
 if(PositionSelect(_Symbol)) { dgSkipPos++; return; }
 MqlTick tick;
 if(!SymbolInfoTick(_Symbol,tick) || atr[0]<=0 || tick.ask<=tick.bid) { dgSkipTick++; return; }
 // v0.11: signal is evaluated before the spread check only so the diagnostics can count
 // spread-blocked signals. Inputs are already fixed; the decision is identical to v0.10.
 bool buy=fast[0]>slow[0] && bar[0].low<=fast[0] && bar[0].close>fast[0] && bar[0].close>bar[0].open;
 bool sell=fast[0]<slow[0] && bar[0].high>=fast[0] && bar[0].close<fast[0] && bar[0].close<bar[0].open;
 if(buy||sell) { dgSignals++; if(buy) dgSigBuy++; else dgSigSell++; }
 DgAdd(dgHistBar,(tick.ask-tick.bid)/_Point);
 if((tick.ask-tick.bid)/_Point>MaxSpreadPoints)
 {
  dgSpreadBlocked++;
  if(buy||sell) { dgSpreadBlockedSig++; PrintFormat("Diag spread-skip %s signal: ask-bid=%s (%.0fpt) > MaxSpreadPoints=%d",buy?"buy":"sell",DoubleToString(tick.ask-tick.bid,_Digits),(tick.ask-tick.bid)/_Point,MaxSpreadPoints); }
  return;
 }
 if(!buy && !sell) return;
 double distance=atr[0]*StopATR;
 double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
 if(tickSize<=0) return;
 double entry=buy?tick.ask:tick.bid;
 double sl=MathRound((buy?entry-distance:entry+distance)/tickSize)*tickSize;
 double tp=MathRound((buy?entry+distance*RewardRisk:entry-distance*RewardRisk)/tickSize)*tickSize;
 sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
 double minDistance=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
 if(buy && (tick.bid-sl<minDistance || tp-tick.bid<minDistance)) { dgStopsSkip++; return; }
 if(sell && (sl-tick.ask<minDistance || tick.ask-tp<minDistance)) { dgStopsSkip++; return; }
 dgOrders++;
 bool sent=buy?trade.Buy(Lots,_Symbol,0,sl,tp,"research-pullback"):trade.Sell(Lots,_Symbol,0,sl,tp,"research-pullback");
 uint code=trade.ResultRetcode();
 if(!sent || (code!=TRADE_RETCODE_DONE && code!=TRADE_RETCODE_PLACED && code!=TRADE_RETCODE_DONE_PARTIAL)) { dgOrderFail++; PrintFormat("Order failure: %u %s",code,trade.ResultRetcodeDescription()); }
}

void OnDeinit(const int reason)
{
 if(fastHandle!=INVALID_HANDLE) IndicatorRelease(fastHandle);
 if(slowHandle!=INVALID_HANDLE) IndicatorRelease(slowHandle);
 if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
 PrintFormat("Diag symbol: name=%s description=\"%s\" path=\"%s\" digits=%d point=%s ticksize=%s contract=%.2f spread_float=%s stopslevel=%d",
   _Symbol,SymbolInfoString(_Symbol,SYMBOL_DESCRIPTION),SymbolInfoString(_Symbol,SYMBOL_PATH),_Digits,DoubleToString(_Point,10),
   DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),10),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),
   SymbolInfoInteger(_Symbol,SYMBOL_SPREAD_FLOAT)?"true":"false",(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL));
 PrintFormat("Diag spread all ticks (ask-bid): %s  [price min=%s max=%s]",DgStats(dgHistAll,MaxSpreadPoints),
   dgTicks>0?DoubleToString(dgSpMin,_Digits):"-",dgTicks>0?DoubleToString(dgSpMax,_Digits):"-");
 PrintFormat("Diag spread at checked new-bar ticks: %s",DgStats(dgHistBar,MaxSpreadPoints));
 PrintFormat("Diag counts: new_bars=%I64d skip_position=%I64d skip_tick_or_atr=%I64d signals=%I64d (buy=%I64d sell=%I64d) spread_blocked_bars=%I64d spread_blocked_signals=%I64d stops_level_skip=%I64d orders_sent=%I64d order_failures=%I64d",
   dgBars,dgSkipPos,dgSkipTick,dgSignals,dgSigBuy,dgSigSell,dgSpreadBlocked,dgSpreadBlockedSig,dgStopsSkip,dgOrders,dgOrderFail);
 if(!MQLInfoInteger(MQL_TESTER)) return;
 // v0.11: deals of positions opened by this EA (symbol+magic on the entry deal), incl. closes with other magic / end-of-test.
 ResearchExportDeals(_Symbol,Magic,"research_deals_");
}
