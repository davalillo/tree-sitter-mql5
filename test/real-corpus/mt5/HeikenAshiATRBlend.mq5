#property copyright "© 2026 tshalgo"
#property link "https://www.mql5.com/en/users/protimetrader"
#property description "Heiken Ashi ATR Blend with EMA trend filter and signals."
#property version "1.00"

#property indicator_chart_window
#property indicator_buffers 10
#property indicator_plots 6

//--- Plot 0: Heiken Ashi candles                                      |
#property indicator_label1 "HA Open;HA High;HA Low;HA Close"
#property indicator_type1 DRAW_COLOR_CANDLES
#property indicator_color1 clrDodgerBlue, clrRed
#property indicator_style1 STYLE_SOLID
#property indicator_width1 1

//--- Plot 1: Fast EMA                                                  |
#property indicator_label2 "Fast EMA"
#property indicator_type2 DRAW_LINE
#property indicator_color2 clrDodgerBlue
#property indicator_style2 STYLE_SOLID
#property indicator_width2 1

//--- Plot 2: Slow EMA                                                  |
#property indicator_label3 "Slow EMA"
#property indicator_type3 DRAW_LINE
#property indicator_color3 clrOrange
#property indicator_style3 STYLE_SOLID
#property indicator_width3 1

//--- Plot 3: ATR                                                       |
#property indicator_label4 "ATR"
#property indicator_type4 DRAW_NONE

//--- Plot 4: Buy                                                       |
#property indicator_label5 "Buy"
#property indicator_type5 DRAW_ARROW
#property indicator_color5 clrLime
#property indicator_style5 STYLE_SOLID
#property indicator_width5 2

//--- Plot 5: Sell                                                      |
#property indicator_label6 "Sell"
#property indicator_type6 DRAW_ARROW
#property indicator_color6 clrRed
#property indicator_style6 STYLE_SOLID
#property indicator_width6 2

//+------------------------------------------------------------------+
//| Inputs - Core Signal Logic                                       |
//+------------------------------------------------------------------+
input group "=== Core Signal Logic ==="
input int    InpFastEMAPeriod       = 20;   // Fast EMA period
input int    InpSlowEMAPeriod       = 50;   // Slow EMA period
input int    InpATRPeriod           = 14;   // ATR period
input double InpMultiplier          = 0.8;  // Signal sensitivity
input double InpBlendFactor         = 0.3;  // Signal blend factor
input double InpMinEmaSeparationATR = 0.25; // Minimum EMA separation (ATR)

//+------------------------------------------------------------------+
//| Inputs - Signal / Visual Behavior                                |
//+------------------------------------------------------------------+
input group "=== Signal / Visual Behavior ==="
input double InpArrowOffsetATR      = 0.30; // Arrow distance from price (ATR)
input bool   InpSignalsEnabled      = true; // Enable signals

//+------------------------------------------------------------------+
//| Inputs - Alerts                                                   |
//+------------------------------------------------------------------+
input group "=== Alerts ==="
input bool   InpPopupAlert          = true;  // Enable popup alerts
input bool   InpPushAlert            = false; // Enable push notifications


// INDICATOR BUFFERS
//--- Heiken Ashi
double HAOpenBuffer[];
double HAHighBuffer[];
double HALowBuffer[];
double HACloseBuffer[];
double HAColorBuffer[];

//--- Moving averages
double FastEMABuffer[];
double SlowEMABuffer[];

//--- ATR
double ATRBuffer[];

//--- Signals
double BuyBuffer[];
double SellBuffer[];

// INDICATOR HANDLES
int ATRHandle = INVALID_HANDLE;
int FastEMAHandle = INVALID_HANDLE;
int SlowEMAHandle = INVALID_HANDLE;

// ALERT STATE
datetime LastBuyAlertTime = 0;
datetime LastSellAlertTime = 0;

// UTILITY
bool ValidValue(const double value) {
    return (value != EMPTY_VALUE && MathIsValidNumber(value));
}

// SEND ALERT
void SendSignalAlert(const string signal) {
    string timeframe = EnumToString((ENUM_TIMEFRAMES)_Period);

    string message =
        _Symbol + " " +
        timeframe +
        " - " +
        signal;

    if (InpPopupAlert)
        Alert(message);

    if (InpPushAlert)
        SendNotification(message);
}

// INITIALIZATION
int OnInit() {
    // Validate parameters
    if (InpMinEmaSeparationATR < 0.0) {
        Print("EMA separation cannot be negative. Using 0.25.");
    }

    if (InpFastEMAPeriod < 1) {
        Print("Fast EMA period must be >= 1. Using 20.");
    }

    if (InpSlowEMAPeriod < 2) {
        Print("Slow EMA period must be >= 2. Using 50.");
    }

    // Bind indicator buffers
    //--- HA OHLC
    SetIndexBuffer(0, HAOpenBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, HAHighBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, HALowBuffer, INDICATOR_DATA);
    SetIndexBuffer(3, HACloseBuffer, INDICATOR_DATA);

    //--- HA candle color
    SetIndexBuffer(4, HAColorBuffer, INDICATOR_COLOR_INDEX);

    //--- EMA buffers
    SetIndexBuffer(5, FastEMABuffer, INDICATOR_DATA);
    SetIndexBuffer(6, SlowEMABuffer, INDICATOR_DATA);

    //--- ATR
    SetIndexBuffer(7, ATRBuffer, INDICATOR_CALCULATIONS);

    //--- Signals
    SetIndexBuffer(8, BuyBuffer, INDICATOR_DATA);
    SetIndexBuffer(9, SellBuffer, INDICATOR_DATA);

    // Set series direction
    ArraySetAsSeries(HAOpenBuffer, true);
    ArraySetAsSeries(HAHighBuffer, true);
    ArraySetAsSeries(HALowBuffer, true);
    ArraySetAsSeries(HACloseBuffer, true);
    ArraySetAsSeries(HAColorBuffer, true);

    ArraySetAsSeries(FastEMABuffer, true);
    ArraySetAsSeries(SlowEMABuffer, true);

    ArraySetAsSeries(ATRBuffer, true);

    ArraySetAsSeries(BuyBuffer, true);
    ArraySetAsSeries(SellBuffer, true);

    // Configure HA candle colors
    PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 2);

    PlotIndexSetInteger(
        0,
        PLOT_LINE_COLOR,
        0,
        clrDodgerBlue);

    PlotIndexSetInteger(
        0,
        PLOT_LINE_COLOR,
        1,
        clrRed);

    // Configure arrows
    PlotIndexSetInteger(4, PLOT_ARROW, 233);
    PlotIndexSetInteger(5, PLOT_ARROW, 234);

    PlotIndexSetDouble(
        4,
        PLOT_EMPTY_VALUE,
        EMPTY_VALUE);

    PlotIndexSetDouble(
        5,
        PLOT_EMPTY_VALUE,
        EMPTY_VALUE);

    // Create ATR
    int atrPeriod = MathMax(InpATRPeriod, 2);

    ATRHandle =
        iATR(
            _Symbol,
            PERIOD_CURRENT,
            atrPeriod);

    if (ATRHandle == INVALID_HANDLE) {
        Print(
            "Failed to create ATR handle. Error = ",
            GetLastError());

        return (INIT_FAILED);
    }

    // Create Fast EMA
    int fastPeriod = MathMax(InpFastEMAPeriod, 1);

    FastEMAHandle =
        iMA(
            _Symbol,
            PERIOD_CURRENT,
            fastPeriod,
            0,
            MODE_EMA,
            PRICE_CLOSE);

    if (FastEMAHandle == INVALID_HANDLE) {
        Print(
            "Failed to create Fast EMA handle. Error = ",
            GetLastError());

        return (INIT_FAILED);
    }

    // Create Slow EMA
    int slowPeriod = MathMax(InpSlowEMAPeriod, 2);

    SlowEMAHandle =
        iMA(
            _Symbol,
            PERIOD_CURRENT,
            slowPeriod,
            0,
            MODE_EMA,
            PRICE_CLOSE);

    if (SlowEMAHandle == INVALID_HANDLE) {
        Print(
            "Failed to create Slow EMA handle. Error = ",
            GetLastError());

        return (INIT_FAILED);
    }

    // Indicator name
    IndicatorSetString(
        INDICATOR_SHORTNAME,
        "Heiken Ashi ATR Blend");

    return (INIT_SUCCEEDED);
}

// DEINITIALIZATION
void OnDeinit(const int reason) {
    if (ATRHandle != INVALID_HANDLE) {
        IndicatorRelease(ATRHandle);
        ATRHandle = INVALID_HANDLE;
    }

    if (FastEMAHandle != INVALID_HANDLE) {
        IndicatorRelease(FastEMAHandle);
        FastEMAHandle = INVALID_HANDLE;
    }

    if (SlowEMAHandle != INVALID_HANDLE) {
        IndicatorRelease(SlowEMAHandle);
        SlowEMAHandle = INVALID_HANDLE;
    }
}

// MAIN CALCULATION
int OnCalculate(
    const int rates_total,
    const int prev_calculated,
    const datetime& time[],
    const double& open[],
    const double& high[],
    const double& low[],
    const double& close[],
    const long& tick_volume[],
    const long& volume[],
    const int& spread[]) {
    // Minimum bars
    if (rates_total < 2)
        return (0);

    // Make price arrays series
    ArraySetAsSeries(time, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);

    // Copy ATR / EMA data
    int copiedATR =
        CopyBuffer(
            ATRHandle,
            0,
            0,
            rates_total,
            ATRBuffer);

    int copiedFast =
        CopyBuffer(
            FastEMAHandle,
            0,
            0,
            rates_total,
            FastEMABuffer);

    int copiedSlow =
        CopyBuffer(
            SlowEMAHandle,
            0,
            0,
            rates_total,
            SlowEMABuffer);

    if (copiedATR <= 0 ||
        copiedFast <= 0 ||
        copiedSlow <= 0) {
        return (prev_calculated);
    }

    // Determine calculation range
    int start;

    if (prev_calculated == 0) {
        // Full calculation.
        start = rates_total - 1;

        ArrayInitialize(
            BuyBuffer,
            EMPTY_VALUE);

        ArrayInitialize(
            SellBuffer,
            EMPTY_VALUE);
    } else {
        // Recalculate one additional older bar.
        start =
            rates_total -
            prev_calculated;

        if (start < 0)
            start = 0;

        if (start < rates_total - 1)
            start++;
    }

    // Smoothing state
    double smoothOpen = 0.0;
    double smoothHigh = 0.0;
    double smoothLow = 0.0;
    double smoothClose = 0.0;

    bool smoothingInitialized = false;

    // Recover previous smoothing state on incremental calculation
    if (prev_calculated > 0 &&
        start < rates_total - 1) {
        int previousIndex = start + 1;

        smoothOpen =
            HAOpenBuffer[previousIndex];

        smoothHigh =
            HAHighBuffer[previousIndex];

        smoothLow =
            HALowBuffer[previousIndex];

        smoothClose =
            HACloseBuffer[previousIndex];

        if (ValidValue(smoothOpen) &&
            ValidValue(smoothHigh) &&
            ValidValue(smoothLow) &&
            ValidValue(smoothClose)) {
            smoothingInitialized = true;
        }
    }

    for (int i = start; i >= 0; i--) {
        if (IsStopped())
            return (prev_calculated);

        // Standard Heiken Ashi
        double haOpen;
        double haHigh;
        double haLow;
        double haClose;

        if (i == rates_total - 1) {
            haOpen = open[i];
            haHigh = high[i];
            haLow = low[i];
            haClose = close[i];
        } else {
            // Standard HA formulas
            haOpen =
                (HAOpenBuffer[i + 1] +
                 HACloseBuffer[i + 1]) /
                2.0;

            haClose =
                (open[i] +
                 high[i] +
                 low[i] +
                 close[i]) /
                4.0;

            haHigh =
                MathMax(
                    high[i],
                    MathMax(
                        haOpen,
                        haClose));

            haLow =
                MathMin(
                    low[i],
                    MathMin(
                        haOpen,
                        haClose));
        }

        // ATR
        double atr = ATRBuffer[i];
        if (!ValidValue(atr))
            atr = 0.0;

        // Smoothed Heiken Ashi
        if (!smoothingInitialized ||
            smoothClose <= 0.0) {
            smoothOpen = haOpen;
            smoothHigh = haHigh;
            smoothLow = haLow;
            smoothClose = haClose;

            smoothingInitialized = true;
        } else {
            // ATR threshold
            double threshold =
                atr * InpMultiplier;

            // Difference from previous smoothed close
            double diff =
                haClose - smoothClose;

            // Significant move
            if (MathAbs(diff) >= threshold) {
                smoothOpen = haOpen;
                smoothHigh = haHigh;
                smoothLow = haLow;
                smoothClose = haClose;
            } else {
                // Blend open
                smoothOpen =
                    smoothOpen *
                        (1.0 - InpBlendFactor) +
                    haOpen *
                        InpBlendFactor;

                // Blend close
                smoothClose =
                    smoothClose *
                        (1.0 - InpBlendFactor) +
                    haClose *
                        InpBlendFactor;

                smoothHigh =
                    MathMax(
                        smoothHigh,
                        haHigh);

                smoothLow =
                    MathMin(
                        smoothLow,
                        haLow);
            }
        }

        HAOpenBuffer[i] = smoothOpen;
        HAHighBuffer[i] = smoothHigh;
        HALowBuffer[i] = smoothLow;
        HACloseBuffer[i] = smoothClose;

        // Candle color
        if (smoothClose >= smoothOpen)
            HAColorBuffer[i] = 0; // DodgerBlue
        else
            HAColorBuffer[i] = 1; // Red

        // Default signal values
        BuyBuffer[i] = EMPTY_VALUE;
        SellBuffer[i] = EMPTY_VALUE;

        if (i >= rates_total - 1)
            continue;

        // EMA values
        double fast =
            FastEMABuffer[i];

        double slow =
            SlowEMABuffer[i];

        if (!ValidValue(fast) ||
            !ValidValue(slow) ||
            atr <= 0.0) {
            continue;
        }

        // Current HA direction
        bool bullish =
            HACloseBuffer[i] >
            HAOpenBuffer[i];

        bool bearish =
            HACloseBuffer[i] <
            HAOpenBuffer[i];

        // Previous HA direction
        bool wasBullish =
            HACloseBuffer[i + 1] >
            HAOpenBuffer[i + 1];

        bool wasBearish =
            HACloseBuffer[i + 1] <
            HAOpenBuffer[i + 1];

        // EMA separation in ATR units
        double emaSeparationATR =
            MathAbs(fast - slow) /
            atr;

        // Early-entry filter
        bool closeEmaSeparation =
            emaSeparationATR <=
            InpMinEmaSeparationATR;

        // BUY SIGNAL
        if (bullish &&
            !wasBullish &&
            fast > slow &&
            closeEmaSeparation) {
            BuyBuffer[i] =
                HALowBuffer[i] -
                atr *
                    InpArrowOffsetATR;

            if (InpSignalsEnabled &&
                i == 0 &&
                time[i] != LastBuyAlertTime) {
                SendSignalAlert("BUY signal");

                LastBuyAlertTime =
                    time[i];
            }
        }

        // SELL SIGNAL
        if (bearish &&
            !wasBearish &&
            fast < slow &&
            closeEmaSeparation) {
            SellBuffer[i] =
                HAHighBuffer[i] +
                atr *
                    InpArrowOffsetATR;

            // Alert only for current bar.
            if (InpSignalsEnabled &&
                i == 0 &&
                time[i] != LastSellAlertTime) {
                SendSignalAlert("SELL signal");

                LastSellAlertTime =
                    time[i];
            }
        }
    }

    return (rates_total);
}
