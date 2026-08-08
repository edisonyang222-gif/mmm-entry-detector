//+------------------------------------------------------------------+
//| AW_Panel.mqh                                                      |
//| Chart HUD (top-right) for Alpha Wave Lite                         |
//+------------------------------------------------------------------+
#property copyright "Alpha Wave"

#ifndef AW_PANEL_MQH
#define AW_PANEL_MQH

#include "AW_Common.mqh"

class CAWPanel
  {
private:
   long              m_chart_id;
   string            m_prefix;
   int               m_x;
   int               m_y;
   int               m_font_size;
   color             m_bg;
   color             m_fg;
   color             m_accent;
   bool              m_created;

   string Key(const string id) const { return m_prefix+"_"+id; }

   void EnsureLabel(const string id,const int y_off,const string text,const color clr)
     {
      const string name=Key(id);
      if(ObjectFind(m_chart_id,name)<0)
        {
         ObjectCreate(m_chart_id,name,OBJ_LABEL,0,0,0);
         ObjectSetInteger(m_chart_id,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
         ObjectSetInteger(m_chart_id,name,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
         ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(m_chart_id,name,OBJPROP_HIDDEN,true);
         ObjectSetString(m_chart_id,name,OBJPROP_FONT,"Consolas");
         ObjectSetInteger(m_chart_id,name,OBJPROP_FONTSIZE,m_font_size);
        }
      ObjectSetInteger(m_chart_id,name,OBJPROP_XDISTANCE,m_x);
      ObjectSetInteger(m_chart_id,name,OBJPROP_YDISTANCE,m_y+y_off);
      ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,clr);
      ObjectSetString(m_chart_id,name,OBJPROP_TEXT,text);
     }

   void EnsureRect(void)
     {
      const string name=Key("BG");
      if(ObjectFind(m_chart_id,name)<0)
        {
         ObjectCreate(m_chart_id,name,OBJ_RECTANGLE_LABEL,0,0,0);
         ObjectSetInteger(m_chart_id,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
         ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(m_chart_id,name,OBJPROP_HIDDEN,true);
         ObjectSetInteger(m_chart_id,name,OBJPROP_BACK,false);
         ObjectSetInteger(m_chart_id,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
        }
      ObjectSetInteger(m_chart_id,name,OBJPROP_XDISTANCE,m_x+8);
      ObjectSetInteger(m_chart_id,name,OBJPROP_YDISTANCE,m_y-6);
      ObjectSetInteger(m_chart_id,name,OBJPROP_XSIZE,280);
      ObjectSetInteger(m_chart_id,name,OBJPROP_YSIZE,320);
      ObjectSetInteger(m_chart_id,name,OBJPROP_BGCOLOR,m_bg);
      ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,m_accent);
     }

public:
                     CAWPanel(void)
     {
      m_chart_id=0;
      m_prefix="AWLitePanel";
      m_x=20;
      m_y=20;
      m_font_size=9;
      m_bg=C'24,24,28';
      m_fg=clrWhite;
      m_accent=clrGoldenrod;
      m_created=false;
     }

   bool Init(const long chart_id,const string prefix="AWLitePanel")
     {
      m_chart_id=chart_id;
      m_prefix=prefix;
      m_created=true;
      EnsureRect();
      return true;
     }

   void Deinit(void)
     {
      ObjectsDeleteAll(m_chart_id,m_prefix);
      m_created=false;
     }

   void Render(const string symbol,
               const ENUM_AW_BIAS bias,
               const ENUM_AW_BIAS h4,
               const ENUM_AW_BIAS h1,
               const ENUM_AW_BIAS m15,
               const AWSessionLevels &sess,
               const AWFibSetupState &fib,
               const AWSweepState &sweep,
               const AWConfirmState &conf,
               const AWScoreState &score)
     {
      if(!m_created) return;
      const int d=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      const int lh=14;
      int y=0;

      EnsureRect();
      EnsureLabel("T0",y,"Alpha Wave Lite",m_accent); y+=lh+4;
      EnsureLabel("T1",y,"Bias: "+AW_BiasToText(bias),m_fg); y+=lh;
      EnsureLabel("T2",y,"H4:  "+AW_BiasToText(h4),m_fg); y+=lh;
      EnsureLabel("T3",y,"H1:  "+AW_BiasToText(h1),m_fg); y+=lh;
      EnsureLabel("T4",y,"M15: "+AW_BiasToText(m15),m_fg); y+=lh+4;

      EnsureLabel("T5",y,"PDH: "+AW_PriceOrNA(sess.pdh,d),m_fg); y+=lh;
      EnsureLabel("T6",y,"PDL: "+AW_PriceOrNA(sess.pdl,d),m_fg); y+=lh+4;

      EnsureLabel("T7",y,"Asia High: "+AW_PriceOrNA(sess.asia_high,d),m_fg); y+=lh;
      EnsureLabel("T8",y,"Asia Low:  "+AW_PriceOrNA(sess.asia_low,d),m_fg); y+=lh+4;

      EnsureLabel("T9",y,"Current Setup: "+(score.setup_name==""?"None":score.setup_name),m_fg); y+=lh;
      EnsureLabel("T10",y,"Fib Zone: "+(fib.in_zone?"YES":(fib.ready?"armed":"no")),m_fg); y+=lh;
      EnsureLabel("T11",y,"Liquidity Sweep: "+(sweep.last_name==""?"None":sweep.last_name),m_fg); y+=lh;
      EnsureLabel("T12",y,"M5 Confirmation: "+(conf.active?conf.name:"None"),m_fg); y+=lh+4;

      color sc=m_fg;
      if(score.band==AW_SCORE_APLUS) sc=clrLime;
      else if(score.band==AW_SCORE_VALID) sc=clrDodgerBlue;
      else if(score.band==AW_SCORE_LOW_QUALITY) sc=clrOrange;
      else sc=clrSilver;

      EnsureLabel("T13",y,
                  StringFormat("Trade Score: %d (%s)",score.score,AW_ScoreBandToText(score.band)),
                  sc); y+=lh+4;
      EnsureLabel("T14",y,"Status: "+AW_UiStatusToText(score.ui_status),sc);

      ChartRedraw(m_chart_id);
     }
  };

#endif
//+------------------------------------------------------------------+
