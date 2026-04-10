#property strict
#include <Trade/Trade.mqh>

CTrade trade;

// === INPUT ===
input double LotAwal = 0.04;
input double Multiplier = 1.3;
input int GridStepPoints = 300;
input int MaxLayer = 6;

input double ProfitTrigger = 3.0;
input double BasketCloseProfit = 5.0;

input double MaxDrawdownPercent = 25.0;

input double HedgeTrigger = -5.0;
input int MinLayerForHedge = 3;
input double HedgeMultiplier = 1.2;

input int ATR_Period = 14;
input double ATR_Multiplier = 1.5;

input int TradeDelay = 5;

// === GLOBAL ===
double lastPrice = 0;
int layer = 0;
datetime lastTradeTime = 0;
bool hedgeMode = false;
int atrHandle;

int OnInit()
{
   atrHandle = iATR(_Symbol, PERIOD_M1, ATR_Period);

   if(atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
// LOT NORMALIZER
double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / stepLot) * stepLot;

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
bool CanTrade()
{
   if(TimeCurrent() - lastTradeTime < TradeDelay)
      return false;

   lastTradeTime = TimeCurrent();
   return true;
}

//+------------------------------------------------------------------+
double GetTotalProfit()
{
   double total = 0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i))
         total += PositionGetDouble(POSITION_PROFIT);
   }
   return total;
}

//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type, double lot, string comment="")
{
   if(!CanTrade()) return;

   lot = NormalizeLot(lot);

   if(type == ORDER_TYPE_BUY)
      trade.Buy(lot,_Symbol,0,0,0,comment);
   else
      trade.Sell(lot,_Symbol,0,0,0,comment);

   lastPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

//+------------------------------------------------------------------+
bool IsStrongTrend()
{
   double now = iClose(_Symbol, PERIOD_M1, 0);
   double prev = iClose(_Symbol, PERIOD_M1, 10);

   return (MathAbs(now - prev) > 300 * _Point);
}

//+------------------------------------------------------------------+
bool IsHedgeExist()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i))
      {
         string c;
         PositionGetString(POSITION_COMMENT, c);
         if(c == "HEDGE")
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void CheckEntry()
{
   if(PositionsTotal() == 0)
   {
      hedgeMode = false;

      if(MathRand()%2==0)
         OpenPosition(ORDER_TYPE_BUY, LotAwal);
      else
         OpenPosition(ORDER_TYPE_SELL, LotAwal);

      layer = 1;
   }
}

//+------------------------------------------------------------------+
void CheckGrid()
{
   if(hedgeMode) return;
   if(layer >= MaxLayer) return;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(MathAbs(price - lastPrice) >= GridStepPoints * _Point)
   {
      if(!PositionSelect(_Symbol)) return;

      long type;
      PositionGetInteger(POSITION_TYPE, type);

      double lot = NormalizeLot(LotAwal * MathPow(Multiplier, layer));

      if(type == POSITION_TYPE_BUY)
         OpenPosition(ORDER_TYPE_BUY, lot);
      else
         OpenPosition(ORDER_TYPE_SELL, lot);

      layer++;
   }
}

//+------------------------------------------------------------------+
void CheckHedge()
{
   double profit = GetTotalProfit();

   if(profit > HedgeTrigger) return;
   if(layer < MinLayerForHedge) return;
   if(!IsStrongTrend()) return;
   if(IsHedgeExist()) return;

   if(!PositionSelect(_Symbol)) return;

   long type;
   PositionGetInteger(POSITION_TYPE, type);

   double lot = NormalizeLot(LotAwal * MathPow(HedgeMultiplier, layer));

   if(type == POSITION_TYPE_BUY)
      OpenPosition(ORDER_TYPE_SELL, lot, "HEDGE");
   else
      OpenPosition(ORDER_TYPE_BUY, lot, "HEDGE");

   hedgeMode = true;
}

//+------------------------------------------------------------------+
void CheckHedgeExit()
{
   double hedgeProfit = 0;

   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i))
      {
         string c;
         PositionGetString(POSITION_COMMENT, c);

         if(c == "HEDGE")
            hedgeProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }

   if(hedgeProfit >= BasketCloseProfit)
      CloseAll();
}

//+------------------------------------------------------------------+
void ApplyATR_Trailing()
{
   double totalProfit = GetTotalProfit();

   if(totalProfit < ProfitTrigger) return;

   double atr[];
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0)
      return;

   double atrValue = atr[0];

   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i))
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         long type;
         PositionGetInteger(POSITION_TYPE, type);

         double sl;

         if(type == POSITION_TYPE_BUY)
            sl = price - (atrValue * ATR_Multiplier);
         else
            sl = price + (atrValue * ATR_Multiplier);

         double currentSL = PositionGetDouble(POSITION_SL);

         if(MathAbs(currentSL - sl) > (_Point * 10))
            trade.PositionModify(ticket, sl, 0);
      }
   }
}

//+------------------------------------------------------------------+
void CloseProfitable()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i))
      {
         double profit = PositionGetDouble(POSITION_PROFIT);

         if(profit > 0)
         {
            trade.PositionClose(PositionGetInteger(POSITION_TICKET));
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
void CheckRecovery()
{
   double profit = GetTotalProfit();

   if(profit >= ProfitTrigger && PositionsTotal() > 1)
      CloseProfitable();
}

//+------------------------------------------------------------------+
void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i))
         trade.PositionClose(PositionGetInteger(POSITION_TICKET));
   }
   layer = 0;
   hedgeMode = false;
}

//+------------------------------------------------------------------+
void CheckDrawdown()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   if((bal - eq)/bal*100 >= MaxDrawdownPercent)
      CloseAll();
}

//+------------------------------------------------------------------+
void OnTick()
{
   CheckDrawdown();

   CheckEntry();

   ApplyATR_Trailing();

   double profit = GetTotalProfit();

   if(profit < 0)
      CheckGrid();

   CheckHedge();

   CheckHedgeExit();

   CheckRecovery();

   if(profit >= BasketCloseProfit)
      CloseAll();
}
