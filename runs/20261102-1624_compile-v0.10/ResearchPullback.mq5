#property strict
#property version "0.10"
#property description "Independent research baseline. NOT a reproduction of Pau Perdices."
#include <Trade/Trade.mqh>
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
 return INIT_SUCCEEDED;
}

void OnTick()
{
 datetime current=iTime(_Symbol,_Period,0);
 if(current==0 || current==lastBar) return;
 if(BarsCalculated(slowHandle)<SlowEMA+2 || BarsCalculated(atrHandle)<ATRPeriod+2) return;
 double fast[1],slow[1],atr[1]; MqlRates bar[1];
 if(CopyBuffer(fastHandle,0,1,1,fast)!=1 || CopyBuffer(slowHandle,0,1,1,slow)!=1 || CopyBuffer(atrHandle,0,1,1,atr)!=1 || CopyRates(_Symbol,_Period,1,1,bar)!=1) return;
 lastBar=current;
 // Skip all existing positions on this symbol, including manual/other EA positions.
 if(PositionSelect(_Symbol)) return;
 MqlTick tick;
 if(!SymbolInfoTick(_Symbol,tick) || atr[0]<=0 || tick.ask<=tick.bid) return;
 if((tick.ask-tick.bid)/_Point>MaxSpreadPoints) return;
 bool buy=fast[0]>slow[0] && bar[0].low<=fast[0] && bar[0].close>fast[0] && bar[0].close>bar[0].open;
 bool sell=fast[0]<slow[0] && bar[0].high>=fast[0] && bar[0].close<fast[0] && bar[0].close<bar[0].open;
 if(!buy && !sell) return;
 double distance=atr[0]*StopATR;
 double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
 if(tickSize<=0) return;
 double entry=buy?tick.ask:tick.bid;
 double sl=MathRound((buy?entry-distance:entry+distance)/tickSize)*tickSize;
 double tp=MathRound((buy?entry+distance*RewardRisk:entry-distance*RewardRisk)/tickSize)*tickSize;
 sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
 double minDistance=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
 if(buy && (tick.bid-sl<minDistance || tp-tick.bid<minDistance)) return;
 if(sell && (sl-tick.ask<minDistance || tick.ask-tp<minDistance)) return;
 bool sent=buy?trade.Buy(Lots,_Symbol,0,sl,tp,"research-pullback"):trade.Sell(Lots,_Symbol,0,sl,tp,"research-pullback");
 uint code=trade.ResultRetcode();
 if(!sent || (code!=TRADE_RETCODE_DONE && code!=TRADE_RETCODE_PLACED && code!=TRADE_RETCODE_DONE_PARTIAL)) PrintFormat("Order failure: %u %s",code,trade.ResultRetcodeDescription());
}

void OnDeinit(const int reason)
{
 if(fastHandle!=INVALID_HANDLE) IndicatorRelease(fastHandle);
 if(slowHandle!=INVALID_HANDLE) IndicatorRelease(slowHandle);
 if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
 if(!MQLInfoInteger(MQL_TESTER)) return;
 if(!HistorySelect(0,TimeCurrent())) { Print("HistorySelect failed"); return; }
 // Agent-local Files directory. Unique per run; no common/shared file collisions.
 string name="research_deals_"+IntegerToString((long)GetMicrosecondCount())+".csv";
 int file=FileOpen(name,FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
 if(file==INVALID_HANDLE) { Print("CSV open failed: ",GetLastError()); return; }
 FileWrite(file,"deal","position","time_server","symbol","type","entry","volume","price","profit","commission","swap","fee");
 for(int i=0;i<HistoryDealsTotal();i++)
 {
  ulong deal=HistoryDealGetTicket(i);
  if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic) continue;
  FileWrite(file,(string)deal,(string)HistoryDealGetInteger(deal,DEAL_POSITION_ID),TimeToString((datetime)HistoryDealGetInteger(deal,DEAL_TIME),TIME_DATE|TIME_SECONDS),_Symbol,
    (string)HistoryDealGetInteger(deal,DEAL_TYPE),(string)HistoryDealGetInteger(deal,DEAL_ENTRY),DoubleToString(HistoryDealGetDouble(deal,DEAL_VOLUME),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_PRICE),_Digits),
    DoubleToString(HistoryDealGetDouble(deal,DEAL_PROFIT),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_COMMISSION),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_SWAP),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_FEE),8));
 }
 FileClose(file); Print("Deal export (tester agent MQL5/Files): ",name);
}
