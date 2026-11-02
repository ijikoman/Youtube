// Deal export for research EAs (tester use). No trading code here.
//
// Selection rule:
//  1. Position IDs = DEAL_POSITION_ID of entry deals (DEAL_ENTRY_IN / DEAL_ENTRY_INOUT)
//     whose symbol == symbol AND magic == magic.  -> only positions this EA opened.
//  2. Exported deals = every deal on `symbol` whose DEAL_POSITION_ID is in that set,
//     regardless of the deal's own magic (tester "end of test" close, SL/TP, manual or
//     another-magic close of our position are all included).
//  3. Each deal ticket is written once (tickets collected, sorted, de-duplicated).
// Other positions on the same symbol (different magic / manual) are never opened by us,
// so their position IDs are not in the set and none of their deals are exported.
#property strict

bool ResearchIdIn(const long &ids[],const long id)
{
 int n=ArraySize(ids);
 if(n==0) return false;
 int k=ArrayBsearch(ids,id);
 return (k>=0 && k<n && ids[k]==id);
}

// Returns number of rows written, or -1 on failure.
int ResearchExportDeals(const string symbol,const ulong magic,const string prefix)
{
 // End of window far beyond TimeCurrent() so deals stamped at/after the last tick
 // (e.g. the tester's end-of-test close) are not cut off by the selection window.
 if(!HistorySelect(0,TimeCurrent()+86400*366)) { Print("Export: HistorySelect failed ",GetLastError()); return -1; }
 int total=HistoryDealsTotal();

 long ids[]; int nIds=0;
 for(int i=0;i<total;i++)
 {
  ulong d=HistoryDealGetTicket(i); if(d==0) continue;
  long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
  if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT) continue;
  if(HistoryDealGetString(d,DEAL_SYMBOL)!=symbol || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=magic) continue;
  long pid=HistoryDealGetInteger(d,DEAL_POSITION_ID);
  bool seen=false; for(int j=0;j<nIds;j++) if(ids[j]==pid) { seen=true; break; }
  if(seen) continue;
  ArrayResize(ids,nIds+1,256); ids[nIds++]=pid;
 }
 ArraySort(ids);

 ulong tickets[]; int nT=0;
 for(int i=0;i<total;i++)
 {
  ulong d=HistoryDealGetTicket(i); if(d==0) continue;
  if(HistoryDealGetString(d,DEAL_SYMBOL)!=symbol) continue;
  if(!ResearchIdIn(ids,HistoryDealGetInteger(d,DEAL_POSITION_ID))) continue;
  ArrayResize(tickets,nT+1,1024); tickets[nT++]=d;
 }
 ArraySort(tickets);

 string name=prefix+IntegerToString((long)GetMicrosecondCount())+".csv";
 int file=FileOpen(name,FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
 if(file==INVALID_HANDLE) { Print("Export: CSV open failed: ",GetLastError()); return -1; }
 FileWrite(file,"deal","position","time_server","time_msc","symbol","type","entry","reason","magic","volume","price","profit","commission","swap","fee","comment");
 int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
 int rows=0,dups=0; ulong prev=0;
 for(int i=0;i<nT;i++)
 {
  ulong d=tickets[i];
  if(i>0 && d==prev) { dups++; continue; }
  prev=d;
  FileWrite(file,(string)d,(string)HistoryDealGetInteger(d,DEAL_POSITION_ID),
    TimeToString((datetime)HistoryDealGetInteger(d,DEAL_TIME),TIME_DATE|TIME_SECONDS),(string)HistoryDealGetInteger(d,DEAL_TIME_MSC),symbol,
    (string)HistoryDealGetInteger(d,DEAL_TYPE),(string)HistoryDealGetInteger(d,DEAL_ENTRY),(string)HistoryDealGetInteger(d,DEAL_REASON),
    (string)HistoryDealGetInteger(d,DEAL_MAGIC),DoubleToString(HistoryDealGetDouble(d,DEAL_VOLUME),8),DoubleToString(HistoryDealGetDouble(d,DEAL_PRICE),digits),
    DoubleToString(HistoryDealGetDouble(d,DEAL_PROFIT),8),DoubleToString(HistoryDealGetDouble(d,DEAL_COMMISSION),8),
    DoubleToString(HistoryDealGetDouble(d,DEAL_SWAP),8),DoubleToString(HistoryDealGetDouble(d,DEAL_FEE),8),HistoryDealGetString(d,DEAL_COMMENT));
  rows++;
 }
 FileClose(file);

 // Evidence for the end-of-test timing question: if any of our positions is still open
 // here, its closing deal would be created after this export and be missing from the CSV.
 int stillOpen=0;
 for(int i=PositionsTotal()-1;i>=0;i--)
 {
  ulong t=PositionGetTicket(i); if(t==0) continue;
  if(PositionGetString(POSITION_SYMBOL)==symbol && ResearchIdIn(ids,PositionGetInteger(POSITION_IDENTIFIER))) stillOpen++;
 }
 PrintFormat("Export: %s rows=%d positions=%d history_deals_total=%d duplicates_skipped=%d own_positions_open_at_export=%d",
   name,rows,nIds,total,dups,stillOpen);
 return rows;
}
