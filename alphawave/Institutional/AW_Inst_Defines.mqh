//+------------------------------------------------------------------+
//| AW_Inst_Defines.mqh                                              |
//| Alpha Wave Institutional — types                                 |
//+------------------------------------------------------------------+
#ifndef AW_INST_DEFINES_MQH
#define AW_INST_DEFINES_MQH

enum ENUM_AW_REGIME
{
   AW_REGIME_TRENDING = 0,
   AW_REGIME_RANGING,
   AW_REGIME_HIGH_VOL,
   AW_REGIME_LOW_VOL,
   AW_REGIME_UNSTABLE
};

enum ENUM_AW_GRADE
{
   AW_GRADE_NO_TRADE = 0,
   AW_GRADE_C,
   AW_GRADE_B,
   AW_GRADE_A,
   AW_GRADE_A_PLUS
};

enum ENUM_AW_EA_STATUS
{
   AW_STATUS_NORMAL = 0,
   AW_STATUS_REDUCED_RISK,
   AW_STATUS_A_PLUS_ONLY,
   AW_STATUS_STOPPED
};

enum ENUM_AW_DD_LEVEL
{
   AW_DD_OK = 0,
   AW_DD_LEVEL1,
   AW_DD_LEVEL2,
   AW_DD_LEVEL3
};

string AW_RegimeName(const ENUM_AW_REGIME r)
{
   switch(r)
   {
      case AW_REGIME_TRENDING:  return "TRENDING";
      case AW_REGIME_RANGING:   return "RANGING";
      case AW_REGIME_HIGH_VOL:  return "HIGH VOLATILITY";
      case AW_REGIME_LOW_VOL:   return "LOW VOLATILITY";
      default:                  return "UNSTABLE";
   }
}

string AW_GradeName(const ENUM_AW_GRADE g)
{
   switch(g)
   {
      case AW_GRADE_A_PLUS: return "A+";
      case AW_GRADE_A:      return "A";
      case AW_GRADE_B:      return "B";
      case AW_GRADE_C:      return "C";
      default:               return "NO TRADE";
   }
}

string AW_StatusName(const ENUM_AW_EA_STATUS s)
{
   switch(s)
   {
      case AW_STATUS_REDUCED_RISK: return "REDUCED RISK";
      case AW_STATUS_A_PLUS_ONLY:  return "A+ ONLY";
      case AW_STATUS_STOPPED:      return "STOPPED";
      default:                     return "NORMAL";
   }
}

#endif
