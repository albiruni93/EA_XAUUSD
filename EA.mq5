#property strict
#include <Trade/Trade.mqh>

CTrade trade;

// === INPUT ===
input double LotAwal = 0.01;
input double Multiplier = 1.4;
input int GridStep = 300; // points
input int MaxLayer = 6;

input double ProfitLockTrigger = 3.0;
input double TrailingStepUSD = 1.0;

input double RecoveryTarget = 3.0; // target recovery basket
input double BasketCloseDiff = 3.0;

input double MaxDrawdownPercent = 25.0;

// === GLOBAL ===
double lastPrice = 0;
int layer = 0;

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
void OpenPosition(ENUM_ORDER_TYPE type, double lot)
{
   if(type == ORDER_TYPE_BUY)
      trade.Buy(lot,_Symbol);
   else
      trade.Sell(lot,_Symbol);

   lastPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   trade.PositionClose(ticket);
}

//+------------------------------------------------------------------+
void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i))
         ClosePosition(PositionGetInteger(POSITION_TICKET));
   }
   layer = 0;
}

//+------------------------------------------------------------------+
// CLOSE PRIORITAS LAYER AWAL
void CloseOldestFirst()
{
   double bestProfit = -999;

   ulong bestTicket = 0;

   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i))
      {
         double profit = PositionGetDouble(POSITION_PROFIT);

         if(profit > bestProfit)
         {
            bestProfit = profit;
            bestTicket = PositionGetInteger(POSITION_TICKET);
         }
      }
   }

   if(bestTicket > 0)
      ClosePosition(bestTicket);
}

//+------------------------------------------------------------------+
// TRAILING BERBASIS USD
void ApplyTrailing()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i))
      {
         double profit = PositionGetDouble(POSITION_PROFIT);

         if(profit >= ProfitLockTrigger)
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            double open = PositionGetDouble(POSITION_PRICE_OPEN);

            double sl;

            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               sl = open + (TrailingStepUSD * _Point * 10);
            else
               sl = open - (TrailingStepUSD * _Point * 10);

            trade.PositionModify(ticket, sl, 0);
         }
      }
   }
}

//+------------------------------------------------------------------+
void CheckGrid()
{
   if(layer >= MaxLayer) return;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(MathAbs(price - lastPrice) >= GridStep * _Point)
   {
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double lot = LotAwal * MathPow(Multiplier, layer);

      if(type == POSITION_TYPE_BUY)
         OpenPosition(ORDER_TYPE_BUY, lot);
      else
         OpenPosition(ORDER_TYPE_SELL, lot);

      layer++;
   }
}

//+------------------------------------------------------------------+
void CheckEntry()
{
   if(PositionsTotal() == 0)
   {
      if(MathRand() % 2 == 0)
         OpenPosition(ORDER_TYPE_BUY, LotAwal);
      else
         OpenPosition(ORDER_TYPE_SELL, LotAwal);

      layer = 1;
   }
}

//+------------------------------------------------------------------+
void CheckRecovery()
{
   double totalProfit = GetTotalProfit();

   // Recovery close partial
   if(totalProfit >= RecoveryTarget && PositionsTotal() > 1)
   {
      CloseOldestFirst();
   }
}

//+------------------------------------------------------------------+
void CheckBasketClose()
{
   double totalProfit = GetTotalProfit();

   if(totalProfit >= BasketCloseDiff)
   {
      CloseAll();
   }
}

//+------------------------------------------------------------------+
void CheckDrawdown()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   double dd = (balance - equity) / balance * 100.0;

   if(dd >= MaxDrawdownPercent)
      CloseAll();
}

//+------------------------------------------------------------------+
void OnTick()
{
   CheckDrawdown();

   CheckEntry();

   ApplyTrailing();

   double totalProfit = GetTotalProfit();

   if(totalProfit < 0)
      CheckGrid();

   CheckRecovery();

   CheckBasketClose();
}
