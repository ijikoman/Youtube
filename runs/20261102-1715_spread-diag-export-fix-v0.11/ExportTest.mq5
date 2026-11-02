// Tester-only test harness for ResearchExport.mqh. NOT a strategy.
// Scenario (same symbol, hedging account):
//   A: own magic BUY 0.01            -> closed later by a DIFFERENT magic (CloserMagic)
//   F: foreign magic BUY 0.01        -> closed by foreign magic   (must NOT be exported)
//   G: foreign magic SELL 0.01       -> left open, closed by end of test (must NOT be exported)
//   C: own magic SELL 0.02           -> partial close 0.01 by own magic, remainder closed by end of test
// Expected export: A in, A out(magic=CloserMagic), C in, C partial out, C end-of-test out = 5 rows.
#property version "1.00"
#include <Trade/Trade.mqh>
#include "ResearchExport.mqh"
input ulong OwnMagic=2601102;
input ulong ForeignMagic=999;
input ulong CloserMagic=555;
CTrade own,foreign,closer;
int bars=0; datetime lastBar=0; ulong posA=0,posC=0,posF=0;

int OnInit()
{
 if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
 own.SetExpertMagicNumber(OwnMagic); foreign.SetExpertMagicNumber(ForeignMagic); closer.SetExpertMagicNumber(CloserMagic);
 own.SetTypeFillingBySymbol(_Symbol); foreign.SetTypeFillingBySymbol(_Symbol); closer.SetTypeFillingBySymbol(_Symbol);
 return INIT_SUCCEEDED;
}

ulong LastPos(CTrade &t)
{
 ulong deal=t.ResultDeal(); if(deal==0 || !HistoryDealSelect(deal)) return 0;
 return (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
}

void OnTick()
{
 datetime cur=iTime(_Symbol,_Period,0);
 if(cur==0 || cur==lastBar) return;
 lastBar=cur; bars++;
 if(bars==2)
 {
  own.Buy(0.01,_Symbol,0,0,0,"A own");          posA=LastPos(own);
  foreign.Buy(0.01,_Symbol,0,0,0,"F foreign");  posF=LastPos(foreign);
  foreign.Sell(0.01,_Symbol,0,0,0,"G foreign");
  own.Sell(0.02,_Symbol,0,0,0,"C own");         posC=LastPos(own);
  PrintFormat("ExportTest opened: A=%I64u F=%I64u C=%I64u",posA,posF,posC);
 }
 if(bars==5)
 {
  bool a=closer.PositionClose(posA);                 // own position closed with another magic
  bool f=foreign.PositionClose(posF);
  bool c=own.PositionClosePartial(posC,0.01);
  PrintFormat("ExportTest closes: A_by_closer=%s F=%s C_partial=%s",a?"ok":"fail",f?"ok":"fail",c?"ok":"fail");
 }
}

void OnDeinit(const int reason)
{
 int rows=ResearchExportDeals(_Symbol,OwnMagic,"exporttest_deals_");
 PrintFormat("ExportTest expected rows=5 got=%d",rows);
}
