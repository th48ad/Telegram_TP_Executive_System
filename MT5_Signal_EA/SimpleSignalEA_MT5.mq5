//+------------------------------------------------------------------+
//|                                        Simple Signal EA v2.0    |
//|                              Autonomous Trailing Stop Edition   |
//|                            Uses JAson.mqh for JSON parsing      |
//+------------------------------------------------------------------+
#property copyright "Simple Signal EA - Autonomous Edition"
#property version   "2.0"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include "JAson.mqh"

//--- Input parameters
input string    ProductionSection = "=== PRODUCTION PARAMETERS ==="; // Production Settings Section
input string    EA_Comment = "Simple Signal EA v2.0";
input bool      EnableTrading = true;               // Enable actual trading
input bool      EnableDebugLogging = true;          // Enable debug logging
input bool      EnableStatisticsLogging = false;    // Enable periodic statistics logging (every 5 min)
input bool      EnableSmartOrderConversion = true;  // Convert invalid limit orders to market orders
input int       MarketOrderDeviation = 20;       // Market order base deviation (points: Gold=5x, Crypto=3x, Forex=1x)
input bool      EnableSounds = true;                // Enable sound alerts
input double    DefaultLotSize = 0.01;              // Default lot size (0 = use risk %)
input double    RiskPercent = 2.0;                  // Risk % per trade (when DefaultLotSize = 0)
input string    ServerURL = "http://127.0.0.1:8888"; // Web server URL
input int       PollIntervalSeconds = 10;           // Poll interval for new signals
input string    SymbolSuffix = ".PRO";              // Symbol suffix (e.g., ".PRO", ".ecn", "")

input string    TestingSection = "=== TESTING PARAMETERS ===";     // Testing Settings Section
input bool      TestMode = false;                   // Enable test mode (no real trading)
input bool      TestConnectToWebServer = true;      // Connect to web server during testing
input string    TestScenario = "ALL";               // Test scenario: "ALL", "SINGLE_TP", "MULTI_TP", "CUSTOM", "LIVE_TEST"
input double    TestInitialPrice = 1.0850;          // Starting price for simulation
input int       TestSpeedMultiplier = 100;          // Speed up simulation (ticks per second)
input bool      TestGenerateSignals = true;         // Generate test signals automatically
input string    TestSymbol = "EURUSD";              // Symbol for test signals

input string    LiveTestSection = "=== LIVE TEST PARAMETERS ===";   // Live Test Settings Section
input bool      LiveTestMode = false;               // Enable live test mode (real orders with test signals)
input double    LiveTestLotSize = 0.01;             // Fixed lot size for live testing
input string    LiveTestSymbol = "ETHUSD";          // Symbol for live testing (ETHUSD, BTCUSD, EURUSD)
input double    LiveTestEntryOffset = 5.0;         // Entry price offset from current market (5 for crypto, 0.0005 for forex)
input double    LiveTestSLDistance = 20.0;           // Stop loss distance (20 for crypto, 0.002 for forex)
input double    LiveTestTP1Distance = 10.0;         // TP1 distance (10 for crypto, 0.001 for forex)
input double    LiveTestTP2Distance = 20.0;         // TP2 distance (20 for crypto, 0.002 for forex)  
input double    LiveTestTP3Distance = 30.0;         // TP3 distance (30 for crypto, 0.003 for forex)

//--- Trading objects
CTrade trade;
CSymbolInfo symbol_info;
CPositionInfo position;
COrderInfo order;

//--- Signal tracking structure (in-memory state)
struct SignalState
{
    string signal_id;       // Unique signal identifier
    int message_id;         // Message ID (used as magic number)
    string symbol;          // Trading symbol
    string action;          // BUY or SELL
    double entry_price;     // Entry price
    double stop_loss;       // Original stop loss
    double tp1;            // Take profit 1
    double tp2;            // Take profit 2  
    double tp3;            // Take profit 3
    bool tp1_hit;          // TP1 reached flag
    bool tp2_hit;          // TP2 reached flag
    bool tp3_hit;          // TP3 reached flag
    bool tp1_partial_done; // 50% close at TP1 completed
    bool tp2_partial_done; // 50% close at TP2 completed
    ulong position_ticket; // Current position ticket (0 if no position)
    datetime last_check;   // Last price check time
    bool is_active;        // Signal is active
    
    // Error tracking flags to prevent log spam (log each error only once per signal)
    bool symbol_select_error_logged;   // SymbolSelect error already logged
    bool symbol_refresh_error_logged;  // RefreshRates error already logged  
    bool invalid_price_error_logged;   // Invalid price error already logged
    bool tp_validation_logged;         // TP validation message already logged
};

//--- Test Framework Structures
struct TestPosition
{
    ulong ticket;              // Simulated ticket number
    string symbol;             // Trading symbol
    ENUM_POSITION_TYPE type;   // Position type (BUY/SELL)
    double volume;             // Position volume
    double price_open;         // Opening price
    double sl;                 // Stop loss
    double tp;                 // Take profit (not used - we manage manually)
    int magic;                 // Magic number
    datetime time_open;        // Opening time
    string comment;            // Comment
    bool is_open;              // Position is open
};

//--- Global variables
SignalState active_signals[]; // Dynamic array to store active signals
int signal_count = 0;            // Number of active signals
datetime last_poll_time = 0;     // Last server poll time
datetime last_log_time = 0;      // Last statistics log time
datetime last_cleanup_time = 0;  // Last signal cleanup time

//--- Test Framework Variables
TestPosition test_positions[];   // Array of simulated positions
int test_position_count = 0;    // Number of test positions
ulong next_test_ticket = 1000000; // Next ticket number for test positions
double current_test_price = 0.0; // Current simulated price
datetime test_start_time = 0;    // Test start time
int test_tick_count = 0;         // Number of simulation ticks
int tests_passed = 0;            // Number of tests passed
int tests_failed = 0;            // Number of tests failed
bool test_framework_initialized = false;

//--- Live Test Variables
datetime last_live_test_signal_time = 0;  // Last live test signal creation time
int live_test_signal_count = 0;           // Number of live test signals created

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("===============================================");
    Print("    SIMPLE SIGNAL EA v2.0 - STARTING UP");
    Print("===============================================");
    Print("Server URL: ", ServerURL);
    Print("Poll Interval: ", PollIntervalSeconds, " seconds");
    Print("Trading: ", EnableTrading ? "ENABLED" : "DISABLED");
    Print("Debug Logging: ", EnableDebugLogging ? "ENABLED" : "DISABLED");
    Print("Statistics Logging: ", EnableStatisticsLogging ? "ENABLED (every 5 min)" : "DISABLED");
    Print("Smart Order Conversion: ", EnableSmartOrderConversion ? "ENABLED" : "DISABLED");
    if(EnableSmartOrderConversion)
    {
        Print("📈 Smart Conversion: Invalid limit orders → Market orders (when price moved favorably)");
        Print("📊 Market Order Deviation: ", MarketOrderDeviation, " base points (symbol-specific multipliers applied)");
        Print("   🥇 Precious Metals (XAUUSD): ", MarketOrderDeviation * 5, " points (5x multiplier)");
        Print("   💰 Crypto (ETHUSD): ", MarketOrderDeviation * 3, " points (3x multiplier)");
        Print("   🏦 Forex/JPY: ", MarketOrderDeviation, " points (1x multiplier)");
        
        // Validate deviation parameter
        if(MarketOrderDeviation < 5)
        {
            Print("⚠️  WARNING: MarketOrderDeviation (", MarketOrderDeviation, ") is very low - may cause order rejections");
        }
        else if(MarketOrderDeviation > 100)
        {
            Print("⚠️  WARNING: MarketOrderDeviation (", MarketOrderDeviation, ") is very high - may cause excessive slippage");
        }
    }
    Print("Sound Alerts: ", EnableSounds ? "ENABLED" : "DISABLED");
    Print("TP Monitoring: REAL-TIME (OnTick)");
    Print("Default Lot Size: ", DefaultLotSize, " (0 = use risk %)");
    Print("Risk Percent: ", RiskPercent, "% per trade");
    Print("Risk Management: ", (DefaultLotSize > 0) ? "Fixed Lot Size" : "Risk % Based");
    Print("Symbol Suffix: ", SymbolSuffix);
    
    // Test mode information
    if(TestMode)
    {
        Print("*** TEST MODE ENABLED (SIMULATION) ***");
        Print("Test Scenario: ", TestScenario);
        Print("Test Symbol: ", TestSymbol);
        Print("Initial Price: ", TestInitialPrice);
        Print("Speed Multiplier: ", TestSpeedMultiplier, "x");
        Print("Web Server: ", TestConnectToWebServer ? "ENABLED" : "DISABLED");
        Print("Generate Signals: ", TestGenerateSignals ? "YES" : "NO");
    }
    else if(LiveTestMode)
    {
        // Determine resolved symbol for display
        string display_symbol = LiveTestSymbol;
        bool is_crypto = (StringFind(LiveTestSymbol, "USD") > 0 && 
                         (StringFind(LiveTestSymbol, "BTC") >= 0 || 
                          StringFind(LiveTestSymbol, "ETH") >= 0 ||
                          StringFind(LiveTestSymbol, "XRP") >= 0 ||
                          StringFind(LiveTestSymbol, "LTC") >= 0 ||
                          StringFind(LiveTestSymbol, "ADA") >= 0));
        
        // Detect precious metals - don't add suffix
        bool is_precious_metal = (StringFind(LiveTestSymbol, "XAU") >= 0 || 
                                 StringFind(LiveTestSymbol, "XAG") >= 0 ||
                                 StringFind(LiveTestSymbol, "GOLD") >= 0 ||
                                 StringFind(LiveTestSymbol, "SILVER") >= 0);
        
        if(!is_crypto)
        {
            display_symbol = LiveTestSymbol + SymbolSuffix;
        }
        
        Print("*** LIVE TEST MODE ENABLED (REAL ORDERS) ***");
        Print("🔬 Creating automatic test signals");
        Print("📡 Also listening for Telegram signals");
        Print("Live Test Symbol: ", display_symbol);
        Print("Live Test Lot Size: ", LiveTestLotSize);
        
        if(is_crypto)
        {
            Print("Entry Offset: ", LiveTestEntryOffset, " (", LiveTestEntryOffset, " units)");
            Print("SL Distance: ", LiveTestSLDistance, " (", LiveTestSLDistance, " units)");
            Print("TP1 Distance: ", LiveTestTP1Distance, " (", LiveTestTP1Distance, " units)");
            Print("TP2 Distance: ", LiveTestTP2Distance, " (", LiveTestTP2Distance, " units)");
            Print("TP3 Distance: ", LiveTestTP3Distance, " (", LiveTestTP3Distance, " units)");
        }
        else
        {
            Print("Entry Offset: 0.0005 (5.0 pips)");
            Print("SL Distance: 0.002 (20.0 pips)");
            Print("TP1 Distance: 0.001 (10.0 pips)");
            Print("TP2 Distance: 0.002 (20.0 pips)");
            Print("TP3 Distance: 0.003 (30.0 pips)");
        }
        
        Print("⚠️  WARNING: This will place REAL orders on your account!");
    }
    Print("===============================================");
    
    // Initialize trading
    trade.SetExpertMagicNumber(0); // We use message_id as magic number
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    // Initialize signal array
    ArrayResize(active_signals, 100); // Set initial capacity to 100 signals
    
    // Manually initialize all signal structures
    for(int i = 0; i < ArraySize(active_signals); i++)
    {
        active_signals[i].signal_id = "";
        active_signals[i].message_id = 0;
        active_signals[i].symbol = "";
        active_signals[i].action = "";
        active_signals[i].entry_price = 0.0;
        active_signals[i].stop_loss = 0.0;
        active_signals[i].tp1 = 0.0;
        active_signals[i].tp2 = 0.0;
        active_signals[i].tp3 = 0.0;
        active_signals[i].tp1_hit = false;
        active_signals[i].tp2_hit = false;
        active_signals[i].tp3_hit = false;
        active_signals[i].tp1_partial_done = false;
        active_signals[i].tp2_partial_done = false;
        active_signals[i].position_ticket = 0;
        active_signals[i].last_check = 0;
        active_signals[i].is_active = false;
        active_signals[i].symbol_select_error_logged = false;
        active_signals[i].symbol_refresh_error_logged = false;
        active_signals[i].invalid_price_error_logged = false;
        active_signals[i].tp_validation_logged = false;
    }
    
    signal_count = 0;
    
    // Test server connection (skip in test mode if web server disabled)
    if(!TestMode || (TestMode && TestConnectToWebServer))
    {
    if(!TestServerConnection())
    {
        Print("[ERROR] Cannot connect to web server at ", ServerURL);
        Print("[HELP] Please start the web server: python simple_web_server.py");
            if(!TestMode) return(INIT_FAILED); // In test mode, allow continuing without server
        }
    }
    
    // Initialize test framework if in test mode
    if(TestMode)
    {
        if(!InitializeTestFramework())
        {
            Print("[ERROR] Failed to initialize test framework");
        return(INIT_FAILED);
        }
    }
    
    // Recover existing positions
    RecoverExistingPositions();
    
    // Clean up any inactive signals after recovery
    CleanupInactiveSignals();
    
    // Start timer
    EventSetTimer(PollIntervalSeconds);
    
    last_log_time = TimeCurrent();
    Print("[SUCCESS] Simple Signal EA initialized successfully");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("===============================================");
    Print("    SIMPLE SIGNAL EA - SHUTTING DOWN");
    Print("    Reason: ", reason);
    Print("===============================================");
    
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| OnTick function - real-time TP monitoring                        |
//+------------------------------------------------------------------+
void OnTick()
{
    // Real-time TP monitoring for all non-test modes
    // This function is called on EVERY price tick for immediate TP detection
    if(!TestMode)
    {
        CheckActiveSIgnals();
    }
    // Note: Test mode uses its own CheckActiveSignalsTest() in OnTimer()
}

//+------------------------------------------------------------------+
//| Timer function - main processing loop                            |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(TestMode)
    {
        // Test mode processing
        RunTestFramework();
        return;
    }
    
    // Get current time for all processing modes
    datetime current_time = TimeCurrent();
    
    if(LiveTestMode)
    {
        // Live test mode processing PLUS Telegram signals
        RunLiveTestMode();
        
        // Also poll for Telegram signals in live test mode
        if(current_time - last_poll_time >= PollIntervalSeconds)
        {
            Print("[LIVE_TEST] Also polling for Telegram signals...");
            PollForNewSignals();
            last_poll_time = current_time;
        }
    }
    else
    {
        // Normal mode: Poll for Telegram signals only
    if(current_time - last_poll_time >= PollIntervalSeconds)
    {
        PollForNewSignals();
        last_poll_time = current_time;
    }
    
        // TP monitoring now handled by OnTick() for real-time response
    }
    
    // Log statistics every 5 minutes (only if statistics logging enabled)
    if(EnableStatisticsLogging && current_time - last_log_time >= 300)
    {
        LogStatistics();
        last_log_time = current_time;
    }
    
    // Clean up inactive signals every 60 seconds (memory management)
    if(current_time - last_cleanup_time >= 60)
    {
        CleanupInactiveSignals();
        last_cleanup_time = current_time;
    }
}

//+------------------------------------------------------------------+
//| Test server connection                                            |
//+------------------------------------------------------------------+
bool TestServerConnection()
{
    string url = ServerURL + "/health";
    char result[];
    string result_headers;
    char post_data[];
    int timeout = 5000;
    string headers = "Content-Type: application/json\r\n";
    
    int res = WebRequest("GET", url, headers, timeout, post_data, result, result_headers);
    
    if(res == 200)
    {
        Print("[SUCCESS] Web server connection established");
        return true;
    }
    else
    {
        Print("[ERROR] Web server connection failed - HTTP ", res);
        return false;
    }
}

//+------------------------------------------------------------------+
//| Poll server for new signals                                      |
//+------------------------------------------------------------------+
void PollForNewSignals()
{
    string url = ServerURL + "/get_pending_signals";
    char result[];
    string result_headers;
    char post_data[];
    int timeout = 10000;
    string headers = "Content-Type: application/json\r\n";
    
    int res = WebRequest("GET", url, headers, timeout, post_data, result, result_headers);
    
    if(res != 200)
    {
        if(EnableDebugLogging)
            Print("[ERROR] Failed to poll for signals - HTTP ", res);
        return;
    }
    
    string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
    
    // Parse JSON response
    CJAVal json;
    if(!json.Deserialize(response))
    {
        Print("[ERROR] Failed to parse server response");
        return;
    }
    
    // Get signals array
    CJAVal signals_array = json["signals"];
    if(signals_array.type != jtARRAY)
    {
        if(EnableDebugLogging)
            Print("[INFO] No pending signals found");
        return;
    }
    
    // Process each signal
    for(int i = 0; i < signals_array.Size(); i++)
    {
        CJAVal signal_json = signals_array[i];
        ProcessNewSignal(signal_json);
    }
}

//+------------------------------------------------------------------+
//| Process a new signal from server                                 |
//+------------------------------------------------------------------+
void ProcessNewSignal(CJAVal &signal_json)
{
    // Extract signal data
    string signal_id = signal_json["id"].ToStr();
    int message_id = (int)signal_json["message_id"].ToDbl();
    string symbol = signal_json["symbol"].ToStr();
    string action = signal_json["action"].ToStr();
    double entry_price = signal_json["entry_price"].ToDbl();
    double stop_loss = signal_json["stop_loss"].ToDbl();
    double tp1 = signal_json["tp1"].ToDbl();
    
    // Handle optional TP levels (null becomes 0.0 in MQL5)
    double tp2 = (signal_json["tp2"].type != jtUNDEF && signal_json["tp2"].type != jtNULL) ? 
                 signal_json["tp2"].ToDbl() : 0.0;
    double tp3 = (signal_json["tp3"].type != jtUNDEF && signal_json["tp3"].type != jtNULL) ? 
                 signal_json["tp3"].ToDbl() : 0.0;
    
    if(EnableDebugLogging)
    {
        Print("[NEW_SIGNAL] ", symbol, " ", action, " @ ", entry_price);
        Print("[NEW_SIGNAL] SL: ", stop_loss, " TP1: ", tp1);
        if(tp2 > 0) Print("[NEW_SIGNAL] TP2: ", tp2);
        if(tp3 > 0) Print("[NEW_SIGNAL] TP3: ", tp3);
        if(tp2 <= 0 && tp3 <= 0) Print("[NEW_SIGNAL] Single TP signal");
    }
    
    // Check if we already have this signal
    if(FindSignalByMessageId(message_id) != -1)
    {
        if(EnableDebugLogging)
            Print("[SKIP] Signal already exists: ", message_id);
        return;
    }
    
    // Add to our tracking array
    if(signal_count >= ArraySize(active_signals))
    {
        Print("[ERROR] Signal array full - cannot add more signals");
        return;
    }
    
    // Store signal in memory
    int index = signal_count;
    active_signals[index].signal_id = signal_id;
    active_signals[index].message_id = message_id;
    active_signals[index].symbol = symbol;
    active_signals[index].action = action;
    active_signals[index].entry_price = entry_price;
    active_signals[index].stop_loss = stop_loss;
    active_signals[index].tp1 = tp1;
    active_signals[index].tp2 = tp2;
    active_signals[index].tp3 = tp3;
    active_signals[index].tp1_hit = false;
    active_signals[index].tp2_hit = false;
    active_signals[index].tp3_hit = false;
    active_signals[index].tp1_partial_done = false;
    active_signals[index].tp2_partial_done = false;
    active_signals[index].position_ticket = 0;
    active_signals[index].last_check = TimeCurrent();
    active_signals[index].is_active = true;
    active_signals[index].symbol_select_error_logged = false;
    active_signals[index].symbol_refresh_error_logged = false;
    active_signals[index].invalid_price_error_logged = false;
    active_signals[index].tp_validation_logged = false;
    
    signal_count++;
    
    // Place limit order
    if(EnableTrading)
    {
        PlaceLimitOrder(index);
    }
    else
    {
        // Calculate what lot size would be used
        double test_lot_size = CalculateLotSize(active_signals[index]);
        Print("[TEST_MODE] Would place order: ", symbol, " ", action, " @ ", entry_price, 
              " (Lot: ", DoubleToString(test_lot_size, 2), ")");
    }
}

//+------------------------------------------------------------------+
//| Place limit order for signal (with smart order conversion)      |
//| Converts invalid limit orders to market orders when favorable   |
//+------------------------------------------------------------------+
void PlaceLimitOrder(int signal_index)
{
    // Access signal directly from array instead of using reference
    // SignalState &signal = active_signals[signal_index];
    
    // Calculate lot size based on risk management settings
    double lot_size = CalculateLotSize(active_signals[signal_index]);
    
    // Construct trading symbol - detect crypto symbols
    string base_symbol = active_signals[signal_index].symbol;
    string trading_symbol = base_symbol;
    
    // Detect if this is a crypto symbol (same logic as Live Test Mode)
    bool is_crypto = (StringFind(base_symbol, "USD") > 0 && 
                     (StringFind(base_symbol, "BTC") >= 0 || 
                      StringFind(base_symbol, "ETH") >= 0 ||
                      StringFind(base_symbol, "XRP") >= 0 ||
                      StringFind(base_symbol, "LTC") >= 0 ||
                      StringFind(base_symbol, "ADA") >= 0));
    
    // Detect precious metals - don't add suffix
    bool is_precious_metal = (StringFind(base_symbol, "XAU") >= 0 || 
                             StringFind(base_symbol, "XAG") >= 0 ||
                             StringFind(base_symbol, "GOLD") >= 0 ||
                             StringFind(base_symbol, "SILVER") >= 0);
    
    if(!LiveTestMode)
    {
        // Only add suffix to non-crypto symbols (forex and precious metals get suffix)
        if(!is_crypto)
        {
            trading_symbol = base_symbol + SymbolSuffix;
        }
        // Only crypto symbols like ETHUSD use base symbol as-is
    }
    // LiveTestMode: symbol is already resolved (ETHUSD or EURUSD.PRO)
    
    // CRITICAL FIX: Update stored symbol in signal array for TP monitoring
    // This ensures CheckSignalTPs uses the correct symbol with suffix
    active_signals[signal_index].symbol = trading_symbol;
    
    // Select symbol in Market Watch
    if(!SymbolSelect(trading_symbol, true))
    {
        Print("[ERROR] Symbol not found in Market Watch: ", trading_symbol);
        Print("[INFO] Base symbol from signal: ", base_symbol);
        Print("[INFO] Configured suffix: ", SymbolSuffix);
        Print("[INFO] Trying to add to Market Watch...");
        
        // Try to add symbol to Market Watch
        if(!SymbolSelect(trading_symbol, true))
        {
            Print("[ERROR] Failed to add symbol to Market Watch: ", trading_symbol);
            ReportEvent(active_signals[signal_index].signal_id, "error", 
                       "Symbol not available: " + trading_symbol, active_signals[signal_index].message_id);
            
            // Mark signal as inactive to prevent infinite checking
            active_signals[signal_index].is_active = false;
            Print("[CLEANUP] Signal ", active_signals[signal_index].message_id, " marked inactive due to symbol not available");
            return;
        }
        else
        {
            Print("[SUCCESS] Added symbol to Market Watch: ", trading_symbol);
        }
    }
    
    // Initialize symbol info
    if(!symbol_info.Name(trading_symbol))
    {
        Print("[ERROR] Failed to initialize symbol info for: ", trading_symbol);
        ReportEvent(active_signals[signal_index].signal_id, "error", 
                   "Failed to initialize symbol: " + trading_symbol, active_signals[signal_index].message_id);
        
        // Mark signal as inactive to prevent infinite checking
        active_signals[signal_index].is_active = false;
        Print("[CLEANUP] Signal ", active_signals[signal_index].message_id, " marked inactive due to symbol initialization error");
        return;
    }
    
    // Refresh symbol quotes
    if(!symbol_info.RefreshRates())
    {
        Print("[ERROR] Failed to refresh rates for: ", trading_symbol);
        ReportEvent(active_signals[signal_index].signal_id, "error", 
                   "Failed to refresh rates: " + trading_symbol, active_signals[signal_index].message_id);
        
        // Mark signal as inactive to prevent infinite checking
        active_signals[signal_index].is_active = false;
        Print("[CLEANUP] Signal ", active_signals[signal_index].message_id, " marked inactive due to rate refresh error");
        return;
    }
    
    // Use the correct MT5 approach with MqlTradeRequest (like legacy EA)
    MqlTradeRequest req = {};
    MqlTradeResult result = {};
    
    // Get current market prices using symbol_info object
    double current_bid = symbol_info.Bid();
    double current_ask = symbol_info.Ask();
    
    // Debug logging for prices
    Print("[DEBUG] Symbol: ", trading_symbol, " | Bid: ", DoubleToString(current_bid, symbol_info.Digits()), 
          " | Ask: ", DoubleToString(current_ask, symbol_info.Digits()));
    
    // Validate prices
    if(current_bid <= 0 || current_ask <= 0)
    {
        Print("[ERROR] Invalid prices - Bid: ", current_bid, " Ask: ", current_ask);
        ReportEvent(active_signals[signal_index].signal_id, "error", 
                   "Invalid market prices", active_signals[signal_index].message_id);
        return;
    }
    
    // Set up basic request parameters
    req.action = TRADE_ACTION_PENDING;
    req.symbol = trading_symbol;  // Use the resolved symbol name
    req.volume = lot_size;
    req.price = active_signals[signal_index].entry_price;
    req.sl = active_signals[signal_index].stop_loss;
    req.tp = 0; // We manage TPs manually
    req.deviation = 10;
    req.magic = active_signals[signal_index].message_id;
    req.comment = EA_Comment + " " + IntegerToString(active_signals[signal_index].message_id);
    req.type_time = ORDER_TIME_GTC;
    req.expiration = 0;
    
    // Set order type based on action and mode
    if(active_signals[signal_index].action == "BUY")
    {
        if(LiveTestMode)
        {
            // Live test mode: Use BUY STOP for easier testing (above market)
            req.type = ORDER_TYPE_BUY_STOP;
            // Validate BUY STOP: entry must be above current ask
            if(active_signals[signal_index].entry_price <= current_ask)
            {
                Print("[ERROR] Invalid BUY STOP price - Entry: ", active_signals[signal_index].entry_price, 
                      " <= Ask: ", current_ask);
                ReportEvent(active_signals[signal_index].signal_id, "error", 
                           "Invalid BUY STOP price", active_signals[signal_index].message_id);
                return;
            }
        }
        else
        {
            // Normal mode: Use BUY LIMIT (below market)
            req.type = ORDER_TYPE_BUY_LIMIT;
            // Validate BUY LIMIT: entry must be below current ask
            if(active_signals[signal_index].entry_price >= current_ask)
            {
                if(EnableSmartOrderConversion)
                {
                    // Smart conversion: Market moved favorably past entry - convert to MARKET order
                    Print("[SMART_CONVERT] BUY LIMIT invalid (Entry: ", active_signals[signal_index].entry_price, 
                          " >= Ask: ", current_ask, ") - Converting to MARKET BUY");
                    Print("[SMART_CONVERT] Favorable movement detected: Market moved UP past entry level");
                    
                    // Calculate symbol-specific deviation
                    int symbol_deviation = CalculateSymbolSpecificDeviation(active_signals[signal_index].symbol);
                    
                    // Convert to market order with proper MT5 parameters
                    req.action = TRADE_ACTION_DEAL;     // Immediate execution
                    req.type = ORDER_TYPE_BUY;          // Market buy
                    req.price = current_ask;            // Use current ask price
                    req.type_filling = GetSymbolFillType(trading_symbol); // Symbol-specific fill type
                    req.type_time = 0;                  // Not needed for market orders
                    req.expiration = 0;                 // Not needed for market orders
                    req.deviation = symbol_deviation;   // Symbol-specific deviation
                    
                    // Update entry price in signal for TP calculations
                    active_signals[signal_index].entry_price = current_ask;
                    
                    Print("[SMART_CONVERT] New order type: MARKET BUY @ ", current_ask, 
                          " | Deviation: ", symbol_deviation, " points | Symbol: ", active_signals[signal_index].symbol, 
                          " | Fill: ", EnumToString(req.type_filling));
                }
                else
                {
                    Print("[ERROR] Invalid BUY LIMIT price - Entry: ", active_signals[signal_index].entry_price, 
                          " >= Ask: ", current_ask);
                    ReportEvent(active_signals[signal_index].signal_id, "error", 
                               "Invalid BUY LIMIT price", active_signals[signal_index].message_id);
                    
                    // Mark signal as inactive to prevent infinite checking
                    active_signals[signal_index].is_active = false;
                    Print("[CLEANUP] Signal ", active_signals[signal_index].message_id, " marked inactive due to price validation error");
                    return;
                }
            }
        }
    }
    else
    {
        if(LiveTestMode)
        {
            // Live test mode: Use SELL STOP for easier testing (below market)
            req.type = ORDER_TYPE_SELL_STOP;
            // Validate SELL STOP: entry must be below current bid
            if(active_signals[signal_index].entry_price >= current_bid)
            {
                Print("[ERROR] Invalid SELL STOP price - Entry: ", active_signals[signal_index].entry_price, 
                      " >= Bid: ", current_bid);
                ReportEvent(active_signals[signal_index].signal_id, "error", 
                           "Invalid SELL STOP price", active_signals[signal_index].message_id);
                return;
            }
        }
        else
        {
            // Normal mode: Use SELL LIMIT (above market)
            req.type = ORDER_TYPE_SELL_LIMIT;
            // Validate SELL LIMIT: entry must be above current bid
            if(active_signals[signal_index].entry_price <= current_bid)
            {
                if(EnableSmartOrderConversion)
                {
                    // Smart conversion: Market moved favorably past entry - convert to MARKET order
                    Print("[SMART_CONVERT] SELL LIMIT invalid (Entry: ", active_signals[signal_index].entry_price, 
                          " <= Bid: ", current_bid, ") - Converting to MARKET SELL");
                    Print("[SMART_CONVERT] Favorable movement detected: Market moved DOWN past entry level");
                    
                    // Calculate symbol-specific deviation
                    int symbol_deviation = CalculateSymbolSpecificDeviation(active_signals[signal_index].symbol);
                    
                    // Convert to market order with proper MT5 parameters
                    req.action = TRADE_ACTION_DEAL;     // Immediate execution
                    req.type = ORDER_TYPE_SELL;         // Market sell
                    req.price = current_bid;            // Use current bid price
                    req.type_filling = GetSymbolFillType(trading_symbol); // Symbol-specific fill type
                    req.type_time = 0;                  // Not needed for market orders
                    req.expiration = 0;                 // Not needed for market orders
                    req.deviation = symbol_deviation;   // Symbol-specific deviation
                    
                    // Update entry price in signal for TP calculations
                    active_signals[signal_index].entry_price = current_bid;
                    
                    Print("[SMART_CONVERT] New order type: MARKET SELL @ ", current_bid, 
                          " | Deviation: ", symbol_deviation, " points | Symbol: ", active_signals[signal_index].symbol, 
                          " | Fill: ", EnumToString(req.type_filling));
                }
                else
                {
                    Print("[ERROR] Invalid SELL LIMIT price - Entry: ", active_signals[signal_index].entry_price, 
                          " <= Bid: ", current_bid);
                    ReportEvent(active_signals[signal_index].signal_id, "error", 
                               "Invalid SELL LIMIT price", active_signals[signal_index].message_id);
                    
                    // Mark signal as inactive to prevent infinite checking
                    active_signals[signal_index].is_active = false;
                    Print("[CLEANUP] Signal ", active_signals[signal_index].message_id, " marked inactive due to price validation error");
                    return;
                }
            }
        }
    }
    
    // Set filling mode (only for limit orders - market orders already have FOK set)
    if(req.action == TRADE_ACTION_PENDING)
    {
        req.type_filling = GetSymbolFillType(trading_symbol);  // Symbol-specific fill type
    }
    // Market orders already have ORDER_FILLING_FOK set during smart conversion
    
    // Place the order
    bool order_result = OrderSend(req, result);
    
    if(order_result)
    {
        // Determine order type for logging
        string order_type_text = "";
        if(req.action == TRADE_ACTION_DEAL)
            order_type_text = "Market order executed";
        else
            order_type_text = "Limit order placed";
            
        Print("[SUCCESS] ", order_type_text, ": ", active_signals[signal_index].symbol, " ", active_signals[signal_index].action, 
              " @ ", active_signals[signal_index].entry_price, " (Lot: ", DoubleToString(lot_size, 2), 
              ", Magic: ", active_signals[signal_index].message_id, ", Ticket: ", result.order, ")");
        
        // Play sound alert for successful order placement
        if(EnableSounds)
        {
            PlaySound("news.wav");  // Default MT5 sound for order placement
        }
        
        // Report to server with conversion info
        string event_data = "ticket=" + IntegerToString((int)result.order) + 
                           ",entry=" + DoubleToString(active_signals[signal_index].entry_price, 5) +
                           ",volume=" + DoubleToString(lot_size, 2);
        
        if(req.action == TRADE_ACTION_DEAL)
            event_data += ",smart_converted=true";
            
        ReportEvent(active_signals[signal_index].signal_id, "order_placed", event_data, active_signals[signal_index].message_id);
    }
    else
    {
        string error_description = "";
        int error_code = result.retcode;
        
        switch(error_code)
        {
            case TRADE_RETCODE_INVALID:         error_description = "Invalid request"; break;
            case TRADE_RETCODE_INVALID_VOLUME:  error_description = "Invalid volume"; break;
            case TRADE_RETCODE_INVALID_PRICE:   error_description = "Invalid price"; break;
            case TRADE_RETCODE_INVALID_STOPS:   error_description = "Invalid stops"; break;
            case TRADE_RETCODE_TRADE_DISABLED:  error_description = "Trade disabled"; break;
            case TRADE_RETCODE_MARKET_CLOSED:   error_description = "Market closed"; break;
            case TRADE_RETCODE_NO_MONEY:        error_description = "No money"; break;
            case TRADE_RETCODE_PRICE_CHANGED:   error_description = "Price changed"; break;
            case TRADE_RETCODE_PRICE_OFF:       error_description = "Off quotes"; break;
            case TRADE_RETCODE_INVALID_EXPIRATION: error_description = "Invalid expiration"; break;
            case TRADE_RETCODE_ORDER_CHANGED:   error_description = "Order changed"; break;
            case TRADE_RETCODE_TOO_MANY_REQUESTS: error_description = "Too many requests"; break;
            case TRADE_RETCODE_NO_CHANGES:      error_description = "No changes"; break;
            case TRADE_RETCODE_SERVER_DISABLES_AT: error_description = "Autotrading disabled by server"; break;
            case TRADE_RETCODE_CLIENT_DISABLES_AT: error_description = "Autotrading disabled by client"; break;
            case TRADE_RETCODE_LOCKED:          error_description = "Locked"; break;
            case TRADE_RETCODE_FROZEN:          error_description = "Frozen"; break;
            case TRADE_RETCODE_INVALID_FILL:    error_description = "Invalid fill"; break;
            case TRADE_RETCODE_CONNECTION:      error_description = "Connection"; break;
            case TRADE_RETCODE_ONLY_REAL:       error_description = "Only real"; break;
            case TRADE_RETCODE_LIMIT_ORDERS:    error_description = "Limit orders"; break;
            case TRADE_RETCODE_LIMIT_VOLUME:    error_description = "Limit volume"; break;
            case TRADE_RETCODE_INVALID_ORDER:   error_description = "Invalid order"; break;
            case TRADE_RETCODE_POSITION_CLOSED: error_description = "Position closed"; break;
            default: error_description = "Unknown error";
        }
        
        Print("[ERROR] Failed to place limit order: ", error_code, " - ", error_description);
        Print("[DEBUG] Request details - Symbol: ", req.symbol, 
              ", Volume: ", req.volume, 
              ", Price: ", req.price, 
              ", SL: ", req.sl, 
              ", Type: ", EnumToString((ENUM_ORDER_TYPE)req.type));
        
        // Play error sound
        if(EnableSounds)
        {
            PlaySound("stops.wav");  // Error sound for failed orders
        }
        
        // Report error to server
        ReportEvent(active_signals[signal_index].signal_id, "error", 
                   "Failed to place order: " + error_description + " (Code: " + IntegerToString(error_code) + ")", 
                   active_signals[signal_index].message_id);
        
        // Mark signal as inactive to prevent infinite checking
        active_signals[signal_index].is_active = false;
        Print("[CLEANUP] Signal ", active_signals[signal_index].message_id, " marked inactive due to order placement failure");
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage or default lot size  |
//+------------------------------------------------------------------+
double CalculateLotSize(const SignalState &signal)
{
    double calculated_volume = 0.0;
    
    // Live test mode override
    if(LiveTestMode)
    {
        if(EnableDebugLogging)
        {
            Print("[LOT_CALC] Live test mode: Using fixed lot size: ", DoubleToString(LiveTestLotSize, 2), " lots");
        }
        return LiveTestLotSize;
    }
    
    // Priority logic: if DefaultLotSize > 0, use it; otherwise use RiskPercent
    bool use_risk_percent = (DefaultLotSize <= 0.0 && RiskPercent > 0.0);
    bool use_default_lot = (DefaultLotSize > 0.0);
    
    if(use_risk_percent)
    {
        // Calculate lot size based on risk percentage
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double risk_amount = balance * RiskPercent / 100.0;
        
        // Detect if this is a crypto symbol (same logic as symbol suffix detection)
        bool is_crypto = (StringFind(signal.symbol, "USD") > 0 && 
                         (StringFind(signal.symbol, "BTC") >= 0 || 
                          StringFind(signal.symbol, "ETH") >= 0 ||
                          StringFind(signal.symbol, "XRP") >= 0 ||
                          StringFind(signal.symbol, "LTC") >= 0 ||
                          StringFind(signal.symbol, "ADA") >= 0));
        
        // Detect precious metals (Gold, Silver) - use point-based calculation like crypto
        bool is_precious_metal = (StringFind(signal.symbol, "XAU") >= 0 || 
                                 StringFind(signal.symbol, "XAG") >= 0 ||
                                 StringFind(signal.symbol, "GOLD") >= 0 ||
                                 StringFind(signal.symbol, "SILVER") >= 0);
        
        // Combine crypto and precious metals for point-based calculation
        bool use_point_calculation = (is_crypto || is_precious_metal);
        
        double sl_distance_units = 0.0;
        double point_value = 0.0;
        
        if(use_point_calculation)
        {
            // POINT-BASED LOGIC: Calculate distance in points directly (Crypto + Precious Metals)
            sl_distance_units = MathAbs(signal.entry_price - signal.stop_loss);
            
            // Get broker's tick value but validate it for point-based symbols
            double broker_tick_value = SymbolInfoDouble(signal.symbol, SYMBOL_TRADE_TICK_VALUE);
            
            // For point-based symbols, broker often returns forex-like values (e.g. $0.01)
            // which are incorrect for point-based contract sizes
            if(broker_tick_value <= 0.1)  // If less than 10 cents, likely wrong for point-based symbols
            {
                // Use proper point values based on symbol type
                if(StringFind(signal.symbol, "ETH") >= 0)
                    point_value = 1.0;  // ETHUSD: $1 per point per lot
                else if(StringFind(signal.symbol, "BTC") >= 0)
                    point_value = 10.0; // BTCUSD: $10 per point per lot (higher value)
                else if(StringFind(signal.symbol, "XAU") >= 0 || StringFind(signal.symbol, "GOLD") >= 0)
                    point_value = 100.0;  // XAUUSD: $100 per point per lot (Gold: 1 lot = 100 oz)
                else if(StringFind(signal.symbol, "XAG") >= 0 || StringFind(signal.symbol, "SILVER") >= 0)
                    point_value = 50.0;  // XAGUSD: $50 per point per lot (Silver: 1 lot = 5000 oz)
                else
                    point_value = 1.0;  // Default for other point-based symbols
            }
            else
            {
                // Use broker's value if it seems reasonable
                point_value = broker_tick_value;
            }
            
            string symbol_type = is_crypto ? "CRYPTO" : "PRECIOUS_METAL";
            if(EnableDebugLogging)
            {
                Print("[LOT_CALC] ", symbol_type, " calculation for ", signal.symbol, ":");
                Print("  Balance: $", DoubleToString(balance, 2));
                Print("  Risk %: ", DoubleToString(RiskPercent, 2), "%");
                Print("  Risk Amount: $", DoubleToString(risk_amount, 2));
                Print("  Entry: ", DoubleToString(signal.entry_price, 5));
                Print("  SL: ", DoubleToString(signal.stop_loss, 5));
                Print("  SL Distance: ", DoubleToString(sl_distance_units, 1), " points");
                Print("  Broker Tick Value: $", DoubleToString(broker_tick_value, 4), " (raw from broker)");
                Print("  Used Point Value: $", DoubleToString(point_value, 2), " per point per lot");
            }
        }
        else
        {
            // FOREX LOGIC: Calculate distance in pips using traditional method
            double symbol_point = SymbolInfoDouble(signal.symbol, SYMBOL_POINT);
            if(symbol_point <= 0) symbol_point = 0.00001; // Default for 5-digit pairs
            
            int symbol_digits = (int)SymbolInfoInteger(signal.symbol, SYMBOL_DIGITS);
            if(symbol_digits <= 0) symbol_digits = 5; // Default
            
            // DEBUG: Log broker's actual values for USDJPY to diagnose pip calculation
            if(StringFind(signal.symbol, "JPY") >= 0)
            {
                Print("[DEBUG_JPY] Symbol: ", signal.symbol);
                Print("[DEBUG_JPY] Broker SYMBOL_POINT: ", DoubleToString(symbol_point, 8));
                Print("[DEBUG_JPY] Broker SYMBOL_DIGITS: ", symbol_digits);
            }
            
            // Calculate pip size (point value for pip calculation)
            double pip_size = symbol_point;
            if(symbol_digits == 5 || symbol_digits == 3) 
                pip_size = symbol_point * 10; // Adjust for 5-digit/3-digit quotes
            
            // Special handling for JPY pairs to fix broker inconsistencies
            if(StringFind(signal.symbol, "JPY") >= 0)
            {
                // JPY pairs should have pip_size = 0.01 regardless of broker's digit count
                pip_size = 0.01;
                Print("[DEBUG_JPY] Forced pip_size to 0.01 for JPY pair");
            }
            
            if(EnableDebugLogging && StringFind(signal.symbol, "JPY") >= 0)
            {
                Print("[DEBUG_JPY] Calculated pip_size: ", DoubleToString(pip_size, 8));
                Print("[DEBUG_JPY] Raw distance: ", DoubleToString(MathAbs(signal.entry_price - signal.stop_loss), 8));
            }
            
            // Calculate stop loss distance in pips
            sl_distance_units = MathAbs(signal.entry_price - signal.stop_loss) / pip_size;
            
            // Get pip value (how much 1 pip costs for 1 lot)
            point_value = SymbolInfoDouble(signal.symbol, SYMBOL_TRADE_TICK_VALUE);
            
            // Special calculation for JPY pairs due to broker inconsistencies
            if(StringFind(signal.symbol, "JPY") >= 0)
            {
                // Manual pip value calculation for JPY pairs
                // Formula: (Pip Size × Contract Size) / Current Rate
                double current_rate = (signal.entry_price + signal.stop_loss) / 2.0; // Use average of entry and SL
                double contract_size = 100000.0; // Standard lot size
                double jpy_pip_size = 0.01; // 1 pip for JPY pairs
                
                point_value = (jpy_pip_size * contract_size) / current_rate;
                
                if(EnableDebugLogging)
                {
                    Print("[DEBUG_JPY] Broker pip value: $", DoubleToString(SymbolInfoDouble(signal.symbol, SYMBOL_TRADE_TICK_VALUE), 4));
                    Print("[DEBUG_JPY] Manual calculation:");
                    Print("[DEBUG_JPY]   Current rate: ", DoubleToString(current_rate, 5));
                    Print("[DEBUG_JPY]   Contract size: ", DoubleToString(contract_size, 0));
                    Print("[DEBUG_JPY]   JPY pip size: ", DoubleToString(jpy_pip_size, 3));
                    Print("[DEBUG_JPY]   Calculated pip value: $", DoubleToString(point_value, 4), " per pip per lot");
                }
            }
            else if(point_value <= 0) 
            {
                // Fallback calculation for major pairs
                if(StringFind(signal.symbol, "USD") >= 0)
                    point_value = 10.0; // $10 per pip for major USD pairs
                else
                    point_value = 1.0; // Fallback
            }
            
            if(EnableDebugLogging)
            {
                Print("[LOT_CALC] FOREX calculation for ", signal.symbol, ":");
                Print("  Balance: $", DoubleToString(balance, 2));
                Print("  Risk %: ", DoubleToString(RiskPercent, 2), "%");
                Print("  Risk Amount: $", DoubleToString(risk_amount, 2));
                Print("  Entry: ", DoubleToString(signal.entry_price, 5));
                Print("  SL: ", DoubleToString(signal.stop_loss, 5));
                Print("  SL Distance: ", DoubleToString(sl_distance_units, 1), " pips");
                Print("  Pip Value: $", DoubleToString(point_value, 2), " per pip per lot");
            }
        }
        
        if(sl_distance_units <= 0)
        {
            Print("[LOT_CALC] Warning: Cannot calculate SL distance, using default lot size");
            calculated_volume = 0.01; // Fallback
        }
        else
        {
            // Calculate lot size: Risk Amount / (SL Distance * Point/Pip Value)
            calculated_volume = risk_amount / (sl_distance_units * point_value);
            
            // Get broker's volume constraints
            double min_lot = SymbolInfoDouble(signal.symbol, SYMBOL_VOLUME_MIN);
            if(min_lot <= 0) min_lot = 0.01;
            
            double max_lot = SymbolInfoDouble(signal.symbol, SYMBOL_VOLUME_MAX);
            if(max_lot <= 0) max_lot = 100.0; // Reasonable default
            
            double volume_step = SymbolInfoDouble(signal.symbol, SYMBOL_VOLUME_STEP);
            if(volume_step <= 0) volume_step = 0.01; // Default step
            
            // Ensure minimum lot size
            if(calculated_volume < min_lot) calculated_volume = min_lot;
            
            // Ensure maximum lot size
            if(calculated_volume > max_lot) calculated_volume = max_lot;
            
            // Round to broker's volume step (most important fix)
            calculated_volume = NormalizeDouble(MathRound(calculated_volume / volume_step) * volume_step, 2);
            
            // Final calculation result logging
            if(EnableDebugLogging)
            {
                Print("  Volume Constraints: Min=", DoubleToString(min_lot, 2), ", Max=", DoubleToString(max_lot, 2), ", Step=", DoubleToString(volume_step, 2));
                Print("  Final Volume: ", DoubleToString(calculated_volume, 2), " lots (normalized)");
            }
        }
    }
    else if(use_default_lot)
    {
        // Use fixed default lot size
        calculated_volume = DefaultLotSize;
        
        if(EnableDebugLogging)
        {
            Print("[LOT_CALC] Using default lot size: ", DoubleToString(calculated_volume, 2), " lots");
        }
    }
    else
    {
        // Both parameters are 0 or invalid - use minimum lot
        calculated_volume = 0.01;
        Print("[LOT_CALC] Warning: Both DefaultLotSize and RiskPercent are 0, using minimum lot size: 0.01");
    }
    
    // Final volume normalization for all calculation paths
    double volume_step = SymbolInfoDouble(signal.symbol, SYMBOL_VOLUME_STEP);
    if(volume_step > 0)
    {
        calculated_volume = NormalizeDouble(MathRound(calculated_volume / volume_step) * volume_step, 2);
    }
    
    return calculated_volume;
}

//+------------------------------------------------------------------+
//| Check all active signals for TP hits and manage trailing stops  |
//+------------------------------------------------------------------+
void CheckActiveSIgnals()
{
    for(int i = 0; i < signal_count; i++)
    {
        if(!active_signals[i].is_active)
            continue;
            
        CheckSignalTPs(i);
    }
}

//+------------------------------------------------------------------+
//| Clean up inactive signals from tracking array (memory cleanup)  |
//+------------------------------------------------------------------+
void CleanupInactiveSignals()
{
    int cleaned_count = 0;
    int original_count = signal_count;
    
    // Compact array by moving active signals to the front
    int write_index = 0;
    for(int read_index = 0; read_index < signal_count; read_index++)
    {
        if(active_signals[read_index].is_active)
        {
            if(write_index != read_index)
            {
                // Move active signal to front of array
                active_signals[write_index] = active_signals[read_index];
            }
            write_index++;
        }
        else
        {
            // Signal is inactive - count it for cleanup
            cleaned_count++;
            if(EnableDebugLogging && cleaned_count <= 3) // Only show first 3 to avoid spam
            {
                Print("[CLEANUP] Removing inactive signal: ", active_signals[read_index].signal_id, 
                      " (Magic: ", active_signals[read_index].message_id, ")");
            }
        }
    }
    
    // Update signal count
    signal_count = write_index;
    
    // Clear unused array slots
    for(int i = signal_count; i < original_count; i++)
    {
        active_signals[i].signal_id = "";
        active_signals[i].message_id = 0;
        active_signals[i].symbol = "";
        active_signals[i].action = "";
        active_signals[i].entry_price = 0.0;
        active_signals[i].stop_loss = 0.0;
        active_signals[i].tp1 = 0.0;
        active_signals[i].tp2 = 0.0;
        active_signals[i].tp3 = 0.0;
        active_signals[i].tp1_hit = false;
        active_signals[i].tp2_hit = false;
        active_signals[i].tp3_hit = false;
        active_signals[i].tp1_partial_done = false;
        active_signals[i].tp2_partial_done = false;
        active_signals[i].position_ticket = 0;
        active_signals[i].last_check = 0;
        active_signals[i].is_active = false;
        active_signals[i].symbol_select_error_logged = false;
        active_signals[i].symbol_refresh_error_logged = false;
        active_signals[i].invalid_price_error_logged = false;
        active_signals[i].tp_validation_logged = false;
    }
    
    if(cleaned_count > 0)
    {
        Print("[CLEANUP] ✅ Cleaned up ", cleaned_count, " inactive signals. Active signals: ", signal_count, 
              " (was ", original_count, ")");
        
        if(EnableDebugLogging && cleaned_count > 3)
        {
            Print("[CLEANUP] Note: ", (cleaned_count - 3), " additional signals cleaned (not shown to avoid spam)");
        }
    }
}

//+------------------------------------------------------------------+
//| Check position close reason when position disappears             |
//+------------------------------------------------------------------+
void CheckPositionCloseReason(int signal_index)
{
    // Get position history to determine close reason
    ulong ticket = active_signals[signal_index].position_ticket;
    
    if(!HistorySelectByPosition(ticket))
    {
        Print("[ERROR] Could not select position history for ticket: ", ticket);
        return;
    }
    
    // Get the last deal for this position (the close deal)
    int deals_total = HistoryDealsTotal();
    if(deals_total == 0)
    {
        Print("[ERROR] No deals found in position history for ticket: ", ticket);
        return;
    }
    
    // Find the close deal (last deal for this position)
    for(int i = deals_total - 1; i >= 0; i--)
    {
        ulong deal_ticket = HistoryDealGetTicket(i);
        if(deal_ticket == 0) continue;
        
        if(HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID) == ticket)
        {
            ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
            
            if(deal_entry == DEAL_ENTRY_OUT || deal_entry == DEAL_ENTRY_OUT_BY)
            {
                // This is the close deal
                double close_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
                ENUM_DEAL_REASON deal_reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(deal_ticket, DEAL_REASON);
                
                Print("[CLOSE_ANALYSIS] Position ", ticket, " closed at ", close_price, " | Reason: ", EnumToString(deal_reason));
                
                // Determine what triggered the close
                AnalyzeCloseReason(signal_index, close_price, deal_reason);
                return;
            }
        }
    }
    
    Print("[ERROR] Could not find close deal for position: ", ticket);
}

//+------------------------------------------------------------------+
//| Analyze close reason and log appropriate event                   |
//+------------------------------------------------------------------+
void AnalyzeCloseReason(int signal_index, double close_price, ENUM_DEAL_REASON deal_reason)
{
    string symbol = active_signals[signal_index].symbol;
    string action = active_signals[signal_index].action;
    double entry_price = active_signals[signal_index].entry_price;
    double sl = active_signals[signal_index].stop_loss;
    double tp1 = active_signals[signal_index].tp1;
    double tp2 = active_signals[signal_index].tp2;
    double tp3 = active_signals[signal_index].tp3;
    
    // Define tolerance for price comparison (1 point for ETHUSD)
    double tolerance = 1.0;
    
    // Check if it was a stop loss hit
    if(MathAbs(close_price - sl) <= tolerance)
    {
        Print("[SL_HIT] ", symbol, " - Position closed by Stop Loss");
        Print("[SL_EXECUTION] Target: ", DoubleToString(sl, 5), 
              " | Actual: ", DoubleToString(close_price, 5), 
              " | Slippage: ", DoubleToString(close_price - sl, 5), " points");
        
        // Calculate loss
        double loss_points = (action == "BUY") ? (entry_price - close_price) : (close_price - entry_price);
        Print("[SL_RESULT] Loss: ", DoubleToString(loss_points, 2), " points");
        
        ReportEvent(active_signals[signal_index].signal_id, "sl_hit", 
                   "price=" + DoubleToString(close_price, 5) + 
                   ",loss_points=" + DoubleToString(loss_points, 2), active_signals[signal_index].message_id);
        
        active_signals[signal_index].is_active = false;
        return;
    }
    
    // Check TP levels (with tolerance)
    bool tp_hit = false;
    string tp_level = "";
    
    if(tp3 > 0 && MathAbs(close_price - tp3) <= tolerance)
    {
        tp_hit = true;
        tp_level = "TP3";
        Print("[TP3_HIT] ", symbol, " - Closing full position");
        Print("[TP3_EXECUTION] Target: ", DoubleToString(tp3, 5), 
              " | Actual: ", DoubleToString(close_price, 5), 
              " | Slippage: ", DoubleToString((action == "BUY" ? close_price - tp3 : tp3 - close_price), 5), " points");
        
        ReportEvent(active_signals[signal_index].signal_id, "tp3_hit", "price=" + DoubleToString(close_price, 5), active_signals[signal_index].message_id);
    }
    else if(tp2 > 0 && MathAbs(close_price - tp2) <= tolerance)
    {
        tp_hit = true;
        tp_level = "TP2";
        Print("[TP2_HIT] ", symbol, " - Position closed at TP2 level");
        Print("[TP2_EXECUTION] Target: ", DoubleToString(tp2, 5), 
              " | Actual: ", DoubleToString(close_price, 5), 
              " | Slippage: ", DoubleToString((action == "BUY" ? close_price - tp2 : tp2 - close_price), 5), " points");
        
        ReportEvent(active_signals[signal_index].signal_id, "tp2_hit", "price=" + DoubleToString(close_price, 5), active_signals[signal_index].message_id);
    }
    else if(tp1 > 0 && MathAbs(close_price - tp1) <= tolerance)
    {
        tp_hit = true;
        tp_level = "TP1";
        Print("[TP1_HIT] ", symbol, " - Position closed at TP1 level");
        Print("[TP1_EXECUTION] Target: ", DoubleToString(tp1, 5), 
              " | Actual: ", DoubleToString(close_price, 5), 
              " | Slippage: ", DoubleToString((action == "BUY" ? close_price - tp1 : tp1 - close_price), 5), " points");
        
        ReportEvent(active_signals[signal_index].signal_id, "tp1_hit", "price=" + DoubleToString(close_price, 5), active_signals[signal_index].message_id);
    }
    
    if(tp_hit)
    {
        // Calculate profit
        double profit_points = (action == "BUY") ? (close_price - entry_price) : (entry_price - close_price);
        Print("[", tp_level, "_RESULT] Profit: ", DoubleToString(profit_points, 2), " points");
        
        active_signals[signal_index].is_active = false;
    }
    else
    {
        // Manual close or other reason
        Print("[MANUAL_CLOSE] ", symbol, " - Position closed manually or by other reason");
        Print("[CLOSE_PRICE] ", DoubleToString(close_price, 5), " | Reason: ", EnumToString(deal_reason));
        
        double pnl_points = (action == "BUY") ? (close_price - entry_price) : (entry_price - close_price);
        Print("[MANUAL_RESULT] P&L: ", DoubleToString(pnl_points, 2), " points");
        
        ReportEvent(active_signals[signal_index].signal_id, "manual_close", 
                   "price=" + DoubleToString(close_price, 5) + 
                   ",pnl_points=" + DoubleToString(pnl_points, 2) +
                   ",reason=" + EnumToString(deal_reason));
        
        active_signals[signal_index].is_active = false;
    }
}

//+------------------------------------------------------------------+
//| Check specific signal for TP levels and manage position          |
//+------------------------------------------------------------------+
void CheckSignalTPs(int signal_index)
{
    // Access signal directly from array instead of using reference
    // SignalState &signal = active_signals[signal_index];
    
    // Find position for this signal
    ulong ticket = FindPositionByMagic(active_signals[signal_index].message_id);
    if(ticket == 0)
    {
        // No position found - check if order is still pending
        if(!HasPendingOrder(active_signals[signal_index].message_id))
        {
            // Neither position nor pending order exists
            
            // Position might have been closed - check if this is a new close event
            if(active_signals[signal_index].position_ticket > 0)
            {
                // Position was open but now closed - determine close reason
                CheckPositionCloseReason(signal_index);
                return;
            }
            else
            {
                // Signal has no position and no pending order - it's orphaned
                // This happens when orders/positions are manually deleted
                Print("[ORPHAN_DETECTED] Signal ", active_signals[signal_index].message_id, 
                      " has no position or pending order - marking as inactive for cleanup");
                
                // Report manual deletion to server
                ReportEvent(active_signals[signal_index].signal_id, "manual_close", 
                           "reason=manual_deletion,no_position_or_order_found", active_signals[signal_index].message_id);
                
                // Mark as inactive for cleanup
                active_signals[signal_index].is_active = false;
                return;
            }
        }
        else
        {
            return; // Order still pending
        }
    }
    
    // Update position ticket if we found one
    if(active_signals[signal_index].position_ticket == 0 && ticket > 0)
    {
        active_signals[signal_index].position_ticket = ticket;
        
        Print("[SUCCESS] Position opened: ", active_signals[signal_index].symbol, " ", active_signals[signal_index].action, 
              " (Ticket: ", ticket, ")");
        
        // Play sound alert for position opening (limit order filled)
        if(EnableSounds)
        {
            PlaySound("alert.wav");  // Different sound for position opening
        }
        
        ReportEvent(active_signals[signal_index].signal_id, "position_opened", 
                   "ticket=" + IntegerToString(ticket), active_signals[signal_index].message_id);
    }
    
    // Get current position info
    if(!position.SelectByTicket(ticket))
        return;
    
    // Get current market price with proper symbol initialization
    string trading_symbol = active_signals[signal_index].symbol;
    
    // Ensure symbol is selected and rates are refreshed
    if(!SymbolSelect(trading_symbol, true))
    {
        // Only log this error once per signal to prevent spam
        if(!active_signals[signal_index].symbol_select_error_logged)
        {
            Print("[TP_ERROR] Cannot select symbol for TP monitoring: ", trading_symbol);
            active_signals[signal_index].symbol_select_error_logged = true;
        }
        return;
    }
    
    // Initialize symbol info and refresh rates
    if(!symbol_info.Name(trading_symbol) || !symbol_info.RefreshRates())
    {
        // Only log this error once per signal to prevent spam
        if(!active_signals[signal_index].symbol_refresh_error_logged)
        {
            Print("[TP_ERROR] Cannot refresh rates for TP monitoring: ", trading_symbol);
            active_signals[signal_index].symbol_refresh_error_logged = true;
        }
        return;
    }
    
    // Get current market price using refreshed symbol info
    double current_price = (active_signals[signal_index].action == "BUY") ? 
                          symbol_info.Bid() : symbol_info.Ask();
    
    // Validate price to prevent false TP triggers
    if(current_price <= 0)
    {
        // Only log this error once per signal to prevent spam
        if(!active_signals[signal_index].invalid_price_error_logged)
        {
            Print("[TP_ERROR] Invalid market price (", current_price, ") for ", trading_symbol, " - skipping TP check");
            active_signals[signal_index].invalid_price_error_logged = true;
        }
        return;
    }
    
    // Validate that position is still profitable before checking TPs
    // This prevents false TP triggers when position was actually closed at SL
    double position_open_price = position.PriceOpen();
    bool is_profitable = false;
    
    if(active_signals[signal_index].action == "BUY")
        is_profitable = (current_price > position_open_price);
    else
        is_profitable = (current_price < position_open_price);
    
    if(!is_profitable)
    {
        // Only log this validation message once per signal to prevent spam
        if(EnableDebugLogging && !active_signals[signal_index].tp_validation_logged)
        {
            Print("[TP_VALIDATION] Position not profitable - skipping TP checks | Open: ", position_open_price, 
                  " | Current: ", current_price, " | Action: ", active_signals[signal_index].action);
            active_signals[signal_index].tp_validation_logged = true;
        }
        return;  // Don't check TPs if position is at loss
    }
    
    // Reset TP validation flag when position becomes profitable again
    if(active_signals[signal_index].tp_validation_logged)
    {
        active_signals[signal_index].tp_validation_logged = false;
    }
    
    // Check TP levels based on action
    if(active_signals[signal_index].action == "BUY")
    {
        // Check TP3 first (full close) - only if TP3 is provided
        if(active_signals[signal_index].tp3 > 0 && !active_signals[signal_index].tp3_hit && current_price >= active_signals[signal_index].tp3)
        {
            active_signals[signal_index].tp3_hit = true;
            Print("[TP3_HIT] ", active_signals[signal_index].symbol, " - Closing full position");
            Print("[TP3_EXECUTION] Target: ", DoubleToString(active_signals[signal_index].tp3, 5), 
                  " | Actual: ", DoubleToString(current_price, 5), 
                  " | Slippage: ", DoubleToString(current_price - active_signals[signal_index].tp3, 5), " points");
            Print("[TP3_DEBUG] BUY condition check: ", current_price, " >= ", active_signals[signal_index].tp3, " = ", (current_price >= active_signals[signal_index].tp3));
            
            // Play sound for TP3 hit
            if(EnableSounds)
            {
                PlaySound("ok.wav");  // Success sound for TP3
            }
            
            if(EnableTrading)
            {
                if(trade.PositionClose(ticket))
                {
                    ReportEvent(active_signals[signal_index].signal_id, "tp3_hit", 
                               "price=" + DoubleToString(current_price, 5));
                    active_signals[signal_index].is_active = false;
                    return;
                }
            }
        }
        
        // Check TP2 (50% close + move SL to TP1) - only if TP2 is provided
        if(active_signals[signal_index].tp2 > 0 && !active_signals[signal_index].tp2_hit && current_price >= active_signals[signal_index].tp2)
        {
            active_signals[signal_index].tp2_hit = true;
            Print("[TP2_HIT] ", active_signals[signal_index].symbol, " - Closing 50% and moving SL to TP1");
            Print("[TP2_EXECUTION] Target: ", DoubleToString(active_signals[signal_index].tp2, 5), 
                  " | Actual: ", DoubleToString(current_price, 5), 
                  " | Slippage: ", DoubleToString(current_price - active_signals[signal_index].tp2, 5), " points");
            
            // Play sound for TP2 hit
            if(EnableSounds)
            {
                PlaySound("timeout.wav");  // Different sound for TP2
            }
            
            if(EnableTrading && !active_signals[signal_index].tp2_partial_done)
            {
                // Close 50% of position
                double current_volume = position.Volume();
                double close_volume = NormalizeDouble(current_volume * 0.5, 2);
                
                if(trade.PositionClosePartial(ticket, close_volume))
                {
                    active_signals[signal_index].tp2_partial_done = true;
                    
                    // Move SL to TP1
                    if(trade.PositionModify(ticket, active_signals[signal_index].tp1, 0))
                    {
                        Print("[SUCCESS] SL moved to TP1: ", active_signals[signal_index].tp1);
                    }
                    
                    ReportEvent(active_signals[signal_index].signal_id, "tp2_hit", 
                               "price=" + DoubleToString(current_price, 5) + 
                               ",closed_50_percent=true,sl_moved_to_tp1=" + DoubleToString(active_signals[signal_index].tp1, 5));
                }
            }
        }
        
        // Check TP1 - behavior depends on whether TP2/TP3 exist
        if(!active_signals[signal_index].tp1_hit && current_price >= active_signals[signal_index].tp1)
        {
            active_signals[signal_index].tp1_hit = true;
            Print("[TP1_EXECUTION] Target: ", DoubleToString(active_signals[signal_index].tp1, 5), 
                  " | Actual: ", DoubleToString(current_price, 5), 
                  " | Slippage: ", DoubleToString(current_price - active_signals[signal_index].tp1, 5), " points");
            
            // Single TP signal - close entire position
            if(active_signals[signal_index].tp2 <= 0 && active_signals[signal_index].tp3 <= 0)
            {
                Print("[TP1_HIT] ", active_signals[signal_index].symbol, " - Single TP signal: Closing full position");
                
                // Play sound for TP1 hit (single TP)
                if(EnableSounds)
                {
                    PlaySound("ok.wav");  // Success sound for single TP completion
                }
                
                if(EnableTrading)
                {
                    if(trade.PositionClose(ticket))
                    {
                        ReportEvent(active_signals[signal_index].signal_id, "tp1_hit", 
                                   "price=" + DoubleToString(current_price, 5) + ",single_tp=true,closed_full=true");
                        active_signals[signal_index].is_active = false;
                        return;
                    }
                }
            }
            // Multi-TP signal - close 50% and move SL to entry
            else
            {
                Print("[TP1_HIT] ", active_signals[signal_index].symbol, " - Multi-TP signal: Closing 50% and moving SL to entry");
                
                // Play sound for TP1 hit (multi-TP)
                if(EnableSounds)
                {
                    PlaySound("connect.wav");  // Different sound for TP1 in multi-TP scenario
                }
                
                if(EnableTrading && !active_signals[signal_index].tp1_partial_done)
            {
                // Close 50% of position
                double current_volume = position.Volume();
                double close_volume = NormalizeDouble(current_volume * 0.5, 2);
                
                if(trade.PositionClosePartial(ticket, close_volume))
                {
                        active_signals[signal_index].tp1_partial_done = true;
                    
                    // Move SL to entry
                        if(trade.PositionModify(ticket, active_signals[signal_index].entry_price, 0))
                    {
                            Print("[SUCCESS] SL moved to entry: ", active_signals[signal_index].entry_price);
                    }
                    
                        ReportEvent(active_signals[signal_index].signal_id, "tp1_hit", 
                               "price=" + DoubleToString(current_price, 5) + 
                                   ",closed_50_percent=true,sl_moved_to_entry=" + DoubleToString(active_signals[signal_index].entry_price, 5));
                    }
                }
            }
        }
    }
    else // SELL
    {
        // Check TP3 first (full close) - only if TP3 is provided
        if(active_signals[signal_index].tp3 > 0 && !active_signals[signal_index].tp3_hit && current_price <= active_signals[signal_index].tp3)
        {
            active_signals[signal_index].tp3_hit = true;
            Print("[TP3_HIT] ", active_signals[signal_index].symbol, " - Closing full position");
            Print("[TP3_EXECUTION] Target: ", DoubleToString(active_signals[signal_index].tp3, 5), 
                  " | Actual: ", DoubleToString(current_price, 5), 
                  " | Slippage: ", DoubleToString(active_signals[signal_index].tp3 - current_price, 5), " points (SELL)");
            Print("[TP3_DEBUG] SELL condition check: ", current_price, " <= ", active_signals[signal_index].tp3, " = ", (current_price <= active_signals[signal_index].tp3));
            
            // Play sound for TP3 hit
            if(EnableSounds)
            {
                PlaySound("ok.wav");  // Success sound for TP3
            }
            
            if(EnableTrading)
            {
                if(trade.PositionClose(ticket))
                {
                    ReportEvent(active_signals[signal_index].signal_id, "tp3_hit", 
                               "price=" + DoubleToString(current_price, 5));
                    active_signals[signal_index].is_active = false;
                    return;
                }
            }
        }
        
        // Check TP2 (50% close + move SL to TP1) - only if TP2 is provided
        if(active_signals[signal_index].tp2 > 0 && !active_signals[signal_index].tp2_hit && current_price <= active_signals[signal_index].tp2)
        {
            active_signals[signal_index].tp2_hit = true;
            Print("[TP2_HIT] ", active_signals[signal_index].symbol, " - Closing 50% and moving SL to TP1");
            Print("[TP2_EXECUTION] Target: ", DoubleToString(active_signals[signal_index].tp2, 5), 
                  " | Actual: ", DoubleToString(current_price, 5), 
                  " | Slippage: ", DoubleToString(active_signals[signal_index].tp2 - current_price, 5), " points (SELL)");
            
            // Play sound for TP2 hit
            if(EnableSounds)
            {
                PlaySound("timeout.wav");  // Different sound for TP2
            }
            
            if(EnableTrading && !active_signals[signal_index].tp2_partial_done)
            {
                // Close 50% of position
                double current_volume = position.Volume();
                double close_volume = NormalizeDouble(current_volume * 0.5, 2);
                
                if(trade.PositionClosePartial(ticket, close_volume))
                {
                    active_signals[signal_index].tp2_partial_done = true;
                    
                    // Move SL to TP1
                    if(trade.PositionModify(ticket, active_signals[signal_index].tp1, 0))
                    {
                        Print("[SUCCESS] SL moved to TP1: ", active_signals[signal_index].tp1);
                    }
                    
                    ReportEvent(active_signals[signal_index].signal_id, "tp2_hit", 
                               "price=" + DoubleToString(current_price, 5) + 
                               ",closed_50_percent=true,sl_moved_to_tp1=" + DoubleToString(active_signals[signal_index].tp1, 5));
                }
            }
        }
        
        // Check TP1 - behavior depends on whether TP2/TP3 exist
        if(!active_signals[signal_index].tp1_hit && current_price <= active_signals[signal_index].tp1)
        {
            active_signals[signal_index].tp1_hit = true;
            Print("[TP1_EXECUTION] Target: ", DoubleToString(active_signals[signal_index].tp1, 5), 
                  " | Actual: ", DoubleToString(current_price, 5), 
                  " | Slippage: ", DoubleToString(active_signals[signal_index].tp1 - current_price, 5), " points (SELL)");
            
            // Single TP signal - close entire position
            if(active_signals[signal_index].tp2 <= 0 && active_signals[signal_index].tp3 <= 0)
            {
                Print("[TP1_HIT] ", active_signals[signal_index].symbol, " - Single TP signal: Closing full position");
                
                // Play sound for TP1 hit (single TP)
                if(EnableSounds)
                {
                    PlaySound("ok.wav");  // Success sound for single TP completion
                }
                
                if(EnableTrading)
                {
                    if(trade.PositionClose(ticket))
                    {
                        ReportEvent(active_signals[signal_index].signal_id, "tp1_hit", 
                                   "price=" + DoubleToString(current_price, 5) + ",single_tp=true,closed_full=true");
                        active_signals[signal_index].is_active = false;
                        return;
                    }
                }
            }
            // Multi-TP signal - close 50% and move SL to entry
            else
            {
                Print("[TP1_HIT] ", active_signals[signal_index].symbol, " - Multi-TP signal: Closing 50% and moving SL to entry");
                
                // Play sound for TP1 hit (multi-TP)
                if(EnableSounds)
                {
                    PlaySound("connect.wav");  // Different sound for TP1 in multi-TP scenario
                }
                
                if(EnableTrading && !active_signals[signal_index].tp1_partial_done)
            {
                // Close 50% of position
                double current_volume = position.Volume();
                double close_volume = NormalizeDouble(current_volume * 0.5, 2);
                
                if(trade.PositionClosePartial(ticket, close_volume))
                {
                        active_signals[signal_index].tp1_partial_done = true;
                    
                    // Move SL to entry
                        if(trade.PositionModify(ticket, active_signals[signal_index].entry_price, 0))
                    {
                            Print("[SUCCESS] SL moved to entry: ", active_signals[signal_index].entry_price);
                    }
                    
                        ReportEvent(active_signals[signal_index].signal_id, "tp1_hit", 
                               "price=" + DoubleToString(current_price, 5) + 
                                   ",closed_50_percent=true,sl_moved_to_entry=" + DoubleToString(active_signals[signal_index].entry_price, 5));
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Find position by magic number                                    |
//+------------------------------------------------------------------+
ulong FindPositionByMagic(int magic_number)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Magic() == magic_number)
            {
                return position.Ticket();
            }
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Check if pending order exists                                    |
//+------------------------------------------------------------------+
bool HasPendingOrder(int magic_number)
{
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(order.SelectByIndex(i))
        {
            if(order.Magic() == magic_number)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Find signal by message ID                                        |
//+------------------------------------------------------------------+
int FindSignalByMessageId(int message_id)
{
    for(int i = 0; i < signal_count; i++)
    {
        if(active_signals[i].message_id == message_id)
        {
            return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Report event to web server                                       |
//+------------------------------------------------------------------+
void ReportEvent(string signal_id, string event_type, string event_data, int message_id = 0)
{
    string url = ServerURL + "/report_event";
    string headers = "Content-Type: application/json\r\n";
    
    // Create JSON payload with both signal_id and message_id for maximum compatibility
    CJAVal json_obj;
    json_obj["signal_id"] = signal_id;
    if(message_id > 0)
        json_obj["message_id"] = message_id;
    json_obj["event_type"] = event_type;
    json_obj["event_data"]["data"] = event_data;
    json_obj["event_data"]["timestamp"] = (int)TimeCurrent();
    
    string json = json_obj.Serialize();
    
    char post_data[];
    StringToCharArray(json, post_data, 0, StringLen(json));
    
    char result[];
    string result_headers;
    int timeout = 5000;
    
    int res = WebRequest("POST", url, headers, timeout, post_data, result, result_headers);
    
    if(res == 200)
    {
        if(EnableDebugLogging)
            Print("[EVENT_REPORTED] ", event_type, " for signal ", signal_id, " (msg_id: ", message_id, ")");
    }
    else
    {
        string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
        Print("[ERROR] Failed to report event: HTTP ", res, " | Response: ", response);
        if(EnableDebugLogging)
        {
            Print("[ERROR] Request payload: ", json);
        }
    }
}

//+------------------------------------------------------------------+
//| Recover existing positions AND pending orders on EA restart      |
//+------------------------------------------------------------------+
void RecoverExistingPositions()
{
    Print("[RECOVERY] Checking for existing positions and pending orders to recover...");
    
    int recovered_positions = 0;
    int recovered_orders = 0;
    
    // Check all current positions
    Print("[RECOVERY] Checking ", PositionsTotal(), " total positions...");
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(position.SelectByIndex(i))
        {
            int magic = (int)position.Magic();
            string symbol = position.Symbol();
            double volume = position.Volume();
            double profit = position.Profit();
            
            Print("[RECOVERY] Position ", i, " - Symbol: ", symbol, ", Magic: ", magic, 
                  ", Volume: ", volume, ", Profit: ", profit);
            
            // Skip positions not managed by us (magic = 0 or very low numbers)
            // Telegram message IDs are typically > 100, so accept magic numbers > 100
            if(magic <= 100)
            {
                Print("[RECOVERY] Skipping position with magic ", magic, " (not managed by EA - too low)");
                continue;
            }
            
            Print("[RECOVERY] Found EA-managed position - Magic: ", magic, ", Ticket: ", position.Ticket());
            
            // Try to recover signal data from server
            if(RecoverSignalFromServer(magic))
            {
                recovered_positions++;
                Print("[RECOVERY] Successfully recovered position with magic ", magic);
            }
            else
            {
                Print("[RECOVERY] Failed to recover position with magic ", magic);
            }
        }
    }
    
    // Check all pending orders
    Print("[RECOVERY] Checking ", OrdersTotal(), " total pending orders...");
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(order.SelectByIndex(i))
        {
            int magic = (int)order.Magic();
            string symbol = order.Symbol();
            double volume = order.VolumeInitial();
            double price = order.PriceOpen();
            
            Print("[RECOVERY] Order ", i, " - Symbol: ", symbol, ", Magic: ", magic, 
                  ", Volume: ", volume, ", Price: ", price, ", Type: ", EnumToString((ENUM_ORDER_TYPE)order.Type()));
            
            // Skip orders not managed by us (magic = 0 or very low numbers)
            // Telegram message IDs are typically > 100, so accept magic numbers > 100
            if(magic <= 100)
            {
                Print("[RECOVERY] Skipping order with magic ", magic, " (not managed by EA - too low)");
                continue;
            }
            
            Print("[RECOVERY] Found EA-managed pending order - Magic: ", magic, ", Ticket: ", order.Ticket(), 
                  ", Symbol: ", order.Symbol(), ", Type: ", EnumToString((ENUM_ORDER_TYPE)order.Type()));
            
            // Try to recover signal data from server
            if(RecoverSignalFromServer(magic))
            {
                recovered_orders++;
                Print("[RECOVERY] Successfully recovered order with magic ", magic);
            }
            else
            {
                Print("[RECOVERY] Failed to recover order with magic ", magic);
            }
        }
    }
    
    Print("[RECOVERY] Recovery complete - Positions: ", recovered_positions, ", Pending Orders: ", recovered_orders, 
          ", Total: ", (recovered_positions + recovered_orders));
}

//+------------------------------------------------------------------+
//| Recover single signal from server                                |
//+------------------------------------------------------------------+
bool RecoverSignalFromServer(int message_id)
{
    string url = ServerURL + "/get_signal_state/" + IntegerToString(message_id);
    char result[];
    string result_headers;
    char post_data[];
    int timeout = 5000;
    string headers = "Content-Type: application/json\r\n";
    
    Print("[RECOVERY] =========================================");
    Print("[RECOVERY] Attempting to recover signal for magic ", message_id);
    Print("[RECOVERY] URL: ", url);
    Print("[RECOVERY] Headers: ", headers);
    Print("[RECOVERY] =========================================");
    
    int res = WebRequest("GET", url, headers, timeout, post_data, result, result_headers);
    
    Print("[RECOVERY] =========================================");
    Print("[RECOVERY] HTTP response code: ", res, " for magic ", message_id);
    Print("[RECOVERY] Response headers: ", result_headers);
    
    if(res == 200)
    {
        string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
        Print("[RECOVERY] Response body: ", response);
    }
    else
    {
        string error_response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
        Print("[RECOVERY] Error response: ", error_response);
    }
    Print("[RECOVERY] =========================================");
    
    if(res != 200)
    {
        if(res == 404)
        {
            Print("[RECOVERY] Signal not found on server for magic ", message_id);
        }
        else
        {
            Print("[RECOVERY] Server error for magic ", message_id, " - HTTP ", res);
        }
        return false;
    }
    
    string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
    
    // Parse signal data
    CJAVal json;
    if(!json.Deserialize(response))
    {
        Print("[ERROR] Failed to parse recovery data for magic ", message_id);
        return false;
    }
    
    // Add to our tracking array
    if(signal_count >= ArraySize(active_signals))
    {
        Print("[ERROR] Signal array full during recovery");
        return false;
    }
    
    int index = signal_count;
    active_signals[index].signal_id = json["id"].ToStr();
    active_signals[index].message_id = message_id;
    
    // Apply suffix logic during recovery (same as PlaceLimitOrder function)
    string base_symbol = json["symbol"].ToStr();
    string trading_symbol = base_symbol;
    
    // Detect if this is a crypto symbol
    bool is_crypto = (StringFind(base_symbol, "USD") > 0 && 
                     (StringFind(base_symbol, "BTC") >= 0 || 
                      StringFind(base_symbol, "ETH") >= 0 ||
                      StringFind(base_symbol, "XRP") >= 0 ||
                      StringFind(base_symbol, "LTC") >= 0 ||
                      StringFind(base_symbol, "ADA") >= 0));
    
    // Detect precious metals - don't add suffix
    bool is_precious_metal = (StringFind(base_symbol, "XAU") >= 0 || 
                             StringFind(base_symbol, "XAG") >= 0 ||
                             StringFind(base_symbol, "GOLD") >= 0 ||
                             StringFind(base_symbol, "SILVER") >= 0);
    
    if(!LiveTestMode)
    {
        // Only add suffix to non-crypto symbols (forex and precious metals get suffix)
        if(!is_crypto)
        {
            trading_symbol = base_symbol + SymbolSuffix;
        }
        // Only crypto symbols like ETHUSD use base symbol as-is
    }
    
    active_signals[index].symbol = trading_symbol;  // Store the full trading symbol with suffix
    active_signals[index].action = json["action"].ToStr();
    active_signals[index].entry_price = json["entry_price"].ToDbl();
    active_signals[index].position_ticket = FindPositionByMagic(message_id);
    active_signals[index].last_check = TimeCurrent();
    active_signals[index].is_active = true;
    
    // Check if we have recovery state information (enhanced format)
    if(json["recovery_state"].type != jtUNDEF && json["recovery_state"].type != jtNULL)
    {
        // Use CURRENT state values (not original)
        active_signals[index].stop_loss = json["stop_loss"].ToDbl();  // Current SL after trailing
        active_signals[index].tp1 = (json["tp1"].type != jtNULL && json["tp1"].ToDbl() > 0) ? json["tp1"].ToDbl() : 0.0;
        active_signals[index].tp2 = (json["tp2"].type != jtNULL && json["tp2"].ToDbl() > 0) ? json["tp2"].ToDbl() : 0.0;
        active_signals[index].tp3 = (json["tp3"].type != jtNULL && json["tp3"].ToDbl() > 0) ? json["tp3"].ToDbl() : 0.0;
        
        // Restore TP hit flags from server state with validation and fallback inference
        if(json["recovery_state"]["tp1_hit"].type != jtUNDEF)
            active_signals[index].tp1_hit = json["recovery_state"]["tp1_hit"].ToBool();
        else
            active_signals[index].tp1_hit = (active_signals[index].tp1 <= 0); // Infer from null TP
            
        if(json["recovery_state"]["tp2_hit"].type != jtUNDEF)
            active_signals[index].tp2_hit = json["recovery_state"]["tp2_hit"].ToBool();
        else
            active_signals[index].tp2_hit = (active_signals[index].tp2 <= 0); // Infer from null TP
            
        if(json["recovery_state"]["tp3_hit"].type != jtUNDEF)
            active_signals[index].tp3_hit = json["recovery_state"]["tp3_hit"].ToBool();
        else
            active_signals[index].tp3_hit = (active_signals[index].tp3 <= 0); // Infer from null TP
            
        active_signals[index].tp1_partial_done = active_signals[index].tp1_hit;
        active_signals[index].tp2_partial_done = active_signals[index].tp2_hit;
        
        // Debug the recovery state values
        Print("[RECOVERY] 🔍 DEBUG: JSON values - tp1_hit type=", json["recovery_state"]["tp1_hit"].type, 
              ", tp2_hit type=", json["recovery_state"]["tp2_hit"].type, 
              ", tp3_hit type=", json["recovery_state"]["tp3_hit"].type);
        Print("[RECOVERY] 🔍 DEBUG: JSON booleans - tp1_hit=", json["recovery_state"]["tp1_hit"].ToBool(), 
              ", tp2_hit=", json["recovery_state"]["tp2_hit"].ToBool(), 
              ", tp3_hit=", json["recovery_state"]["tp3_hit"].ToBool());
        
        Print("[RECOVERY] ✅ Successfully restored signal with CURRENT state: ", active_signals[index].symbol, " ", 
              active_signals[index].action, " @ ", active_signals[index].entry_price, 
              " (Magic: ", message_id, ", Signal ID: ", active_signals[index].signal_id, ")");
        Print("[RECOVERY] Current state - SL: ", active_signals[index].stop_loss, 
              ", TP1: ", (active_signals[index].tp1 > 0 ? DoubleToString(active_signals[index].tp1, 2) : "✅ HIT"),
              ", TP2: ", (active_signals[index].tp2 > 0 ? DoubleToString(active_signals[index].tp2, 2) : "✅ HIT"),
              ", TP3: ", (active_signals[index].tp3 > 0 ? DoubleToString(active_signals[index].tp3, 2) : "✅ HIT"));
        Print("[RECOVERY] TP Status - TP1: ", (active_signals[index].tp1_hit ? "✅ ALREADY HIT" : "⏳ PENDING"),
              ", TP2: ", (active_signals[index].tp2_hit ? "✅ ALREADY HIT" : "⏳ PENDING"),
              ", TP3: ", (active_signals[index].tp3_hit ? "✅ ALREADY HIT" : "⏳ PENDING"));
              
        // Check if signal is fully completed (TP3 hit = full position closed)
        if(active_signals[index].tp3_hit)
        {
            Print("[RECOVERY] 🎯 TP3 ALREADY HIT - Signal should be fully completed!");
            
            // Check if position still exists (shouldn't happen but let's handle it)
            ulong existing_ticket = FindPositionByMagic(message_id);
            if(existing_ticket > 0)
            {
                Print("[RECOVERY] ⚠️  WARNING: Position still exists despite TP3 hit! Closing it now...");
                if(EnableTrading && trade.PositionClose(existing_ticket))
                {
                    Print("[RECOVERY] ✅ Orphaned position closed successfully");
                }
                else
                {
                    Print("[RECOVERY] ❌ Failed to close orphaned position");
                }
            }
            
            Print("[RECOVERY] ⚠️  Marking signal as completed - will not be tracked.");
            active_signals[index].is_active = false;
            // Don't increment signal_count for completed signals
            return true;
        }
        
        Print("[RECOVERY] 🚨 CRITICAL: EA will NOT re-process already hit TPs - continuing from current state");
    }
    else
    {
        // Fallback to original format (legacy compatibility)
        active_signals[index].stop_loss = json["stop_loss"].ToDbl();
        active_signals[index].tp1 = json["tp1"].ToDbl();
        active_signals[index].tp2 = json["tp2"].ToDbl();
        active_signals[index].tp3 = json["tp3"].ToDbl();
    active_signals[index].tp1_hit = false;
    active_signals[index].tp2_hit = false;
    active_signals[index].tp3_hit = false;
    active_signals[index].tp1_partial_done = false;
    active_signals[index].tp2_partial_done = false;
        
        Print("[RECOVERY] ✅ Successfully restored signal (legacy format): ", active_signals[index].symbol, " ", 
              active_signals[index].action, " @ ", active_signals[index].entry_price, 
              " (Magic: ", message_id, ", Signal ID: ", active_signals[index].signal_id, ")");
        Print("[RECOVERY] Signal details - SL: ", active_signals[index].stop_loss, 
              ", TP1: ", active_signals[index].tp1, 
              ", TP2: ", active_signals[index].tp2, 
              ", TP3: ", active_signals[index].tp3);
    }
    
    // Initialize error tracking flags for recovered signals
    active_signals[index].symbol_select_error_logged = false;
    active_signals[index].symbol_refresh_error_logged = false;
    active_signals[index].invalid_price_error_logged = false;
    active_signals[index].tp_validation_logged = false;
    
    signal_count++;
    
    // Report EA restart
    ReportEvent(active_signals[index].signal_id, "ea_started", 
               "recovered_signal=" + active_signals[index].symbol, active_signals[index].message_id);
    
    return true;
}

//+------------------------------------------------------------------+
//| Log statistics (only when EnableStatisticsLogging = true)       |
//+------------------------------------------------------------------+
void LogStatistics()
{
    Print("=== EA STATISTICS ===");
    Print("Active Signals: ", signal_count);
    Print("Open Positions: ", PositionsTotal());
    Print("Pending Orders: ", OrdersTotal());
    
    // Count signals by status
    int pending = 0, active = 0, completed = 0;
    for(int i = 0; i < signal_count; i++)
    {
        if(!active_signals[i].is_active)
            completed++;
        else if(active_signals[i].position_ticket > 0)
            active++;
        else
            pending++;
    }
    
    Print("Signal Status - Pending: ", pending, ", Active: ", active, ", Completed: ", completed);
    Print("====================");
}

//+------------------------------------------------------------------+
//| LIVE TEST MODE FUNCTIONS                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Run live test mode - creates real orders for testing            |
//+------------------------------------------------------------------+
void RunLiveTestMode()
{
    datetime current_time = TimeCurrent();
    
    // TP monitoring now handled by OnTick() for real-time response
    
    // Create new live test signals every 60 seconds
    if(current_time - last_live_test_signal_time >= 60)
    {
        CreateLiveTestSignal();
        last_live_test_signal_time = current_time;
    }
    
    // Log progress every 30 seconds
    if(current_time % 30 == 0)
    {
        LogLiveTestProgress();
    }
}

//+------------------------------------------------------------------+
//| Create a live test signal with real order placement             |
//+------------------------------------------------------------------+
void CreateLiveTestSignal()
{
    // Don't create too many test signals (4 total: 2 BUY + 2 SELL)
    if(live_test_signal_count >= 4)
    {
        Print("[LIVE_TEST] Maximum test signals reached (4). Monitoring existing positions.");
        return;
    }
    
    // Get current market data for test symbol (crypto and precious metals don't use suffix)
    string full_symbol = LiveTestSymbol;
    bool is_crypto = (StringFind(LiveTestSymbol, "USD") > 0 && 
                     (StringFind(LiveTestSymbol, "BTC") >= 0 || 
                      StringFind(LiveTestSymbol, "ETH") >= 0 ||
                      StringFind(LiveTestSymbol, "XRP") >= 0 ||
                      StringFind(LiveTestSymbol, "LTC") >= 0 ||
                      StringFind(LiveTestSymbol, "ADA") >= 0));
    
    // Detect precious metals - don't add suffix
    bool is_precious_metal = (StringFind(LiveTestSymbol, "XAU") >= 0 || 
                             StringFind(LiveTestSymbol, "XAG") >= 0 ||
                             StringFind(LiveTestSymbol, "GOLD") >= 0 ||
                             StringFind(LiveTestSymbol, "SILVER") >= 0);
    
    if(!is_crypto)
    {
        full_symbol = LiveTestSymbol + SymbolSuffix; // Add suffix for non-crypto symbols (forex + precious metals)
    }
    
    if(!SymbolSelect(full_symbol, true))
    {
        Print("[LIVE_TEST] ERROR: Cannot select test symbol: ", full_symbol);
        return;
    }
    
    if(!symbol_info.Name(full_symbol) || !symbol_info.RefreshRates())
    {
        Print("[LIVE_TEST] ERROR: Cannot get market data for: ", full_symbol);
        return;
    }
    
    double current_bid = symbol_info.Bid();
    double current_ask = symbol_info.Ask();
    double current_price = (current_bid + current_ask) / 2.0;
    
    // Determine test type and action
    string action = "";
    string test_type = "";
    bool is_multi_tp = false;
    
    if(live_test_signal_count == 0)
    {
        action = "BUY";
        test_type = "SINGLE TP BUY";
        is_multi_tp = false;
    }
    else if(live_test_signal_count == 1)
    {
        action = "BUY";
        test_type = "MULTI TP BUY";
        is_multi_tp = true;
    }
    else if(live_test_signal_count == 2)
    {
        action = "SELL";
        test_type = "SINGLE TP SELL";
        is_multi_tp = false;
    }
    else if(live_test_signal_count == 3)
    {
        action = "SELL";
        test_type = "MULTI TP SELL";
        is_multi_tp = true;
    }
    else
    {
        Print("[LIVE_TEST] All test scenarios completed");
        return;
    }
    
    // Create test signal parameters
    string signal_id = "LIVE_TEST_" + IntegerToString(live_test_signal_count);
    int message_id = 800000 + live_test_signal_count; // Unique range for live tests
    
    // Calculate prices based on action and current market
    double entry_price, stop_loss, tp1, tp2, tp3;
    
    // Adjust distances based on symbol type
    double entry_offset = is_crypto ? LiveTestEntryOffset : 0.0005;
    double sl_distance = is_crypto ? LiveTestSLDistance : 0.002;
    double tp1_distance = is_crypto ? LiveTestTP1Distance : 0.001;
    double tp2_distance = is_crypto ? LiveTestTP2Distance : 0.002;
    double tp3_distance = is_crypto ? LiveTestTP3Distance : 0.003;
    
    if(action == "BUY")
    {
        // BUY STOP: above market for quick fill
        entry_price = current_ask + entry_offset;
        stop_loss = entry_price - sl_distance;
        tp1 = entry_price + tp1_distance;
        tp2 = is_multi_tp ? entry_price + tp2_distance : 0.0;
        tp3 = is_multi_tp ? entry_price + tp3_distance : 0.0;
    }
    else // SELL
    {
        // SELL STOP: below market for quick fill
        entry_price = current_bid - entry_offset;
        stop_loss = entry_price + sl_distance;
        tp1 = entry_price - tp1_distance;
        tp2 = is_multi_tp ? entry_price - tp2_distance : 0.0;
        tp3 = is_multi_tp ? entry_price - tp3_distance : 0.0;
    }
    
    Print("[LIVE_TEST] ========================================");
    Print("[LIVE_TEST] Creating ", test_type, " test signal");
    Print("[LIVE_TEST] Symbol: ", full_symbol);
    Print("[LIVE_TEST] Action: ", action, " STOP");
    Print("[LIVE_TEST] Entry: ", DoubleToString(entry_price, 5), " (Current: ", DoubleToString(current_price, 5), ")");
    Print("[LIVE_TEST] SL: ", DoubleToString(stop_loss, 5));
    Print("[LIVE_TEST] TP1: ", DoubleToString(tp1, 5));
    if(tp2 > 0) Print("[LIVE_TEST] TP2: ", DoubleToString(tp2, 5));
    if(tp3 > 0) Print("[LIVE_TEST] TP3: ", DoubleToString(tp3, 5));
    Print("[LIVE_TEST] Lot Size: ", LiveTestLotSize);
    Print("[LIVE_TEST] ========================================");
    
    // Add to signal tracking
    if(signal_count >= ArraySize(active_signals))
    {
        Print("[LIVE_TEST] ERROR: Signal array full");
        return;
    }
    
    int index = signal_count;
    active_signals[index].signal_id = signal_id;
    active_signals[index].message_id = message_id;
    active_signals[index].symbol = full_symbol;  // Use resolved symbol name (with or without suffix)
    active_signals[index].action = action;
    active_signals[index].entry_price = entry_price;
    active_signals[index].stop_loss = stop_loss;
    active_signals[index].tp1 = tp1;
    active_signals[index].tp2 = tp2;
    active_signals[index].tp3 = tp3;
    active_signals[index].tp1_hit = false;
    active_signals[index].tp2_hit = false;
    active_signals[index].tp3_hit = false;
    active_signals[index].tp1_partial_done = false;
    active_signals[index].tp2_partial_done = false;
    active_signals[index].position_ticket = 0;
    active_signals[index].last_check = TimeCurrent();
    active_signals[index].is_active = true;
    active_signals[index].symbol_select_error_logged = false;
    active_signals[index].symbol_refresh_error_logged = false;
    active_signals[index].invalid_price_error_logged = false;
    active_signals[index].tp_validation_logged = false;
    
    signal_count++;
    live_test_signal_count++;
    
    // Send to web server (if enabled)
    if(TestConnectToWebServer)
    {
        SendLiveTestSignalToWebServer(index);
    }
    
    // Place the actual limit order
    PlaceLiveTestOrder(index);
    
    // Increment test signal counter
    Print("[LIVE_TEST] Test signal ", live_test_signal_count, " created successfully");
}

//+------------------------------------------------------------------+
//| Place live test order using real MT5 trading functions         |
//+------------------------------------------------------------------+
void PlaceLiveTestOrder(int signal_index)
{
    Print("[LIVE_TEST] Placing REAL limit order for testing...");
    
    // Place the order using existing function (CalculateLotSize will handle live test mode)
    PlaceLimitOrder(signal_index);
    
    Print("[LIVE_TEST] Live test order placement completed");
}

//+------------------------------------------------------------------+
//| Send live test signal to web server                             |
//+------------------------------------------------------------------+
void SendLiveTestSignalToWebServer(int signal_index)
{
    string url = ServerURL + "/add_signal";
    string headers = "Content-Type: application/json\r\n";
    
    // Create JSON payload
    CJAVal json_obj;
    json_obj["id"] = active_signals[signal_index].signal_id;
    json_obj["message_id"] = active_signals[signal_index].message_id;
    json_obj["channel_id"] = -1001234567890; // Test channel ID
    json_obj["symbol"] = active_signals[signal_index].symbol;
    json_obj["action"] = active_signals[signal_index].action;
    json_obj["entry_price"] = active_signals[signal_index].entry_price;
    json_obj["stop_loss"] = active_signals[signal_index].stop_loss;
    json_obj["tp1"] = active_signals[signal_index].tp1;
    
    if(active_signals[signal_index].tp2 > 0)
        json_obj["tp2"] = active_signals[signal_index].tp2;
    if(active_signals[signal_index].tp3 > 0)
        json_obj["tp3"] = active_signals[signal_index].tp3;
    
    json_obj["raw_message"] = "[LIVE_TEST] " + active_signals[signal_index].action + " STOP " + 
                             active_signals[signal_index].symbol + " @ " + 
                             DoubleToString(active_signals[signal_index].entry_price, 5);
    
    string json = json_obj.Serialize();
    
    char post_data[];
    StringToCharArray(json, post_data, 0, StringLen(json));
    
    char result[];
    string result_headers;
    int timeout = 5000;
    
    int res = WebRequest("POST", url, headers, timeout, post_data, result, result_headers);
    
    if(res == 200)
    {
        Print("[LIVE_TEST] Signal registered with web server: ", active_signals[signal_index].signal_id);
    }
    else
    {
        Print("[LIVE_TEST] Failed to register with web server: HTTP ", res);
    }
}

//+------------------------------------------------------------------+
//| Log live test progress                                           |
//+------------------------------------------------------------------+
void LogLiveTestProgress()
{
    // Count test vs Telegram signals
    int test_signals = 0;
    int telegram_signals = 0;
    
    for(int i = 0; i < signal_count; i++)
    {
        if(active_signals[i].is_active)
        {
            if(StringFind(active_signals[i].signal_id, "LIVE_TEST") >= 0)
                test_signals++;
            else
                telegram_signals++;
        }
    }
    
    Print("=== LIVE TEST + TELEGRAM PROGRESS ===");
    Print("Live Test Signals Created: ", live_test_signal_count, "/4");
    Print("Test 0: SINGLE TP BUY - ", (live_test_signal_count > 0) ? "CREATED" : "PENDING");
    Print("Test 1: MULTI TP BUY - ", (live_test_signal_count > 1) ? "CREATED" : "PENDING");
    Print("Test 2: SINGLE TP SELL - ", (live_test_signal_count > 2) ? "CREATED" : "PENDING");
    Print("Test 3: MULTI TP SELL - ", (live_test_signal_count > 3) ? "CREATED" : "PENDING");
    Print("Telegram Signals: ", telegram_signals);
    Print("Total Active Signals: ", signal_count, " (", test_signals, " test + ", telegram_signals, " Telegram)");
    Print("Current Positions: ", PositionsTotal());
    Print("Pending Orders: ", OrdersTotal());
    Print("=====================================");
}

//+------------------------------------------------------------------+
//| TEST FRAMEWORK FUNCTIONS                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Initialize test framework                                         |
//+------------------------------------------------------------------+
bool InitializeTestFramework()
{
    Print("===============================================");
    Print("    INITIALIZING TEST FRAMEWORK");
    Print("===============================================");
    
    // Initialize test position array
    ArrayResize(test_positions, 10);
    test_position_count = 0;
    
    // Initialize test variables
    current_test_price = TestInitialPrice;
    test_start_time = TimeCurrent();
    test_tick_count = 0;
    tests_passed = 0;
    tests_failed = 0;
    
    // Clear test positions
    for(int i = 0; i < ArraySize(test_positions); i++)
    {
        test_positions[i].ticket = 0;
        test_positions[i].symbol = "";
        test_positions[i].type = POSITION_TYPE_BUY;
        test_positions[i].volume = 0.0;
        test_positions[i].price_open = 0.0;
        test_positions[i].sl = 0.0;
        test_positions[i].tp = 0.0;
        test_positions[i].magic = 0;
        test_positions[i].time_open = 0;
        test_positions[i].comment = "";
        test_positions[i].is_open = false;
    }
    
    test_framework_initialized = true;
    
    Print("[TEST] Framework initialized successfully");
    Print("[TEST] Initial price: ", current_test_price);
    Print("[TEST] Speed multiplier: ", TestSpeedMultiplier, "x");
    
    return true;
}

//+------------------------------------------------------------------+
//| Main test framework runner                                        |
//+------------------------------------------------------------------+
void RunTestFramework()
{
    if(!test_framework_initialized) return;
    
    // Simulate price movement
    SimulatePriceMovement();
    
    // Generate test signals if enabled
    if(TestGenerateSignals && test_tick_count % 100 == 0) // Every 100 ticks
    {
        GenerateTestSignal();
    }
    
    // Process existing signals (same as normal mode but with test positions)
    CheckActiveSignalsTest();
    
    // Run specific test scenarios
    if(TestScenario == "ALL" || TestScenario == "SINGLE_TP")
    {
        RunSingleTPTests();
    }
    if(TestScenario == "ALL" || TestScenario == "MULTI_TP")
    {
        RunMultiTPTests();
    }
    
    // Log test progress every 1000 ticks
    if(test_tick_count % 1000 == 0)
    {
        LogTestProgress();
    }
    
    test_tick_count++;
}

//+------------------------------------------------------------------+
//| Simulate price movement                                           |
//+------------------------------------------------------------------+
void SimulatePriceMovement()
{
    // Simple trending price simulation
    static int direction = 1; // 1 for up, -1 for down
    static int trend_duration = 0;
    
    // Change direction occasionally
    if(trend_duration > 200)
    {
        direction *= -1;
        trend_duration = 0;
    }
    
    // Add small random movement
    double pip_size = 0.0001; // For EURUSD
    double movement = pip_size * direction * (0.5 + MathRand() % 3); // 0.5-2.5 pips
    
    current_test_price += movement;
    trend_duration++;
    
    // Keep price in reasonable range
    if(current_test_price > TestInitialPrice + 0.01) current_test_price = TestInitialPrice + 0.01;
    if(current_test_price < TestInitialPrice - 0.01) current_test_price = TestInitialPrice - 0.01;
}

//+------------------------------------------------------------------+
//| Generate test signal                                              |
//+------------------------------------------------------------------+
void GenerateTestSignal()
{
    if(signal_count >= ArraySize(active_signals)) return;
    
    // Create a test signal
    string signal_id = "TEST_" + IntegerToString(test_tick_count);
    int message_id = 900000 + test_tick_count; // Unique message ID
    
    // Randomly choose single or multi TP
    bool multi_tp = (MathRand() % 2 == 0);
    
    double entry = current_test_price;
    double sl = entry - 0.005; // 50 pips SL
    double tp1 = entry + 0.002; // 20 pips TP1
    double tp2 = multi_tp ? entry + 0.004 : 0.0; // 40 pips TP2
    double tp3 = multi_tp ? entry + 0.006 : 0.0; // 60 pips TP3
    
    // Add to signal array
    int index = signal_count;
    active_signals[index].signal_id = signal_id;
    active_signals[index].message_id = message_id;
    active_signals[index].symbol = TestSymbol;
    active_signals[index].action = "BUY";
    active_signals[index].entry_price = entry;
    active_signals[index].stop_loss = sl;
    active_signals[index].tp1 = tp1;
    active_signals[index].tp2 = tp2;
    active_signals[index].tp3 = tp3;
    active_signals[index].tp1_hit = false;
    active_signals[index].tp2_hit = false;
    active_signals[index].tp3_hit = false;
    active_signals[index].tp1_partial_done = false;
    active_signals[index].tp2_partial_done = false;
    active_signals[index].position_ticket = 0;
    active_signals[index].last_check = TimeCurrent();
    active_signals[index].is_active = true;
    active_signals[index].symbol_select_error_logged = false;
    active_signals[index].symbol_refresh_error_logged = false;
    active_signals[index].invalid_price_error_logged = false;
    active_signals[index].tp_validation_logged = false;
    
    signal_count++;
    
    // Send signal to web server first (if enabled) so it knows about this signal ID
    if(TestConnectToWebServer)
    {
        SendTestSignalToWebServer(index);
    }
    
    // Simulate placing the order (immediately fill at current price)
    CreateTestPosition(index);
    
    Print("[TEST_SIGNAL] Generated: ", TestSymbol, " BUY @ ", entry, 
          " | TP1:", tp1, " TP2:", tp2, " TP3:", tp3, " | Multi-TP:", multi_tp);
}

//+------------------------------------------------------------------+
//| Create test position                                              |
//+------------------------------------------------------------------+
void CreateTestPosition(int signal_index)
{
    if(test_position_count >= ArraySize(test_positions)) return;
    
    // Calculate lot size
    double lot_size = CalculateLotSize(active_signals[signal_index]);
    
    // Create simulated position
    int pos_index = test_position_count;
    test_positions[pos_index].ticket = next_test_ticket++;
    test_positions[pos_index].symbol = active_signals[signal_index].symbol;
    test_positions[pos_index].type = (active_signals[signal_index].action == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
    test_positions[pos_index].volume = lot_size;
    test_positions[pos_index].price_open = current_test_price; // Fill at current market price
    test_positions[pos_index].sl = active_signals[signal_index].stop_loss;
    test_positions[pos_index].tp = 0; // We manage TPs manually
    test_positions[pos_index].magic = active_signals[signal_index].message_id;
    test_positions[pos_index].time_open = TimeCurrent();
    test_positions[pos_index].comment = "TEST_POSITION";
    test_positions[pos_index].is_open = true;
    
    // Update signal with position info
    active_signals[signal_index].position_ticket = test_positions[pos_index].ticket;
    
    test_position_count++;
    
    Print("[TEST_POSITION] Created ticket ", test_positions[pos_index].ticket, 
          " | Volume: ", lot_size, " | Price: ", current_test_price);
    
    // Report to web server if enabled
    if(TestConnectToWebServer)
    {
        ReportEvent(active_signals[signal_index].signal_id, "order_placed", 
                   "ticket=" + IntegerToString(test_positions[pos_index].ticket) + 
                   ",entry=" + DoubleToString(current_test_price, 5) +
                   ",volume=" + DoubleToString(lot_size, 2) +
                   ",test_mode=true");
        
        // Also report position opened (simulating immediate fill)
        ReportEvent(active_signals[signal_index].signal_id, "position_opened", 
                   "ticket=" + IntegerToString(test_positions[pos_index].ticket) +
                   ",test_mode=true", active_signals[signal_index].message_id);
    }
}

//+------------------------------------------------------------------+
//| Check active signals in test mode                                |
//+------------------------------------------------------------------+
void CheckActiveSignalsTest()
{
    for(int i = 0; i < signal_count; i++)
    {
        if(!active_signals[i].is_active) continue;
        
        CheckSignalTPsTest(i);
    }
}

//+------------------------------------------------------------------+
//| Check signal TPs in test mode                                    |
//+------------------------------------------------------------------+
void CheckSignalTPsTest(int signal_index)
{
    // Find test position
    int pos_index = FindTestPositionByTicket((int)active_signals[signal_index].position_ticket);
    if(pos_index == -1 || !test_positions[pos_index].is_open) return;
    
    // Use current simulated price
    double current_price = current_test_price;
    
    // Check TP levels (simplified version - only for BUY positions in this example)
    if(active_signals[signal_index].action == "BUY")
    {
        // Check TP3 first (full close)
        if(active_signals[signal_index].tp3 > 0 && !active_signals[signal_index].tp3_hit && 
           current_price >= active_signals[signal_index].tp3)
        {
            active_signals[signal_index].tp3_hit = true;
            CloseTestPosition(pos_index, "TP3_HIT");
            active_signals[signal_index].is_active = false;
            
            Print("[TEST_TP3] Hit at ", current_price, " - Position closed");
            tests_passed++;
            
            // Report to web server if enabled
            if(TestConnectToWebServer)
            {
                ReportEvent(active_signals[signal_index].signal_id, "tp3_hit", 
                           "price=" + DoubleToString(current_price, 5) + ",test_mode=true");
            }
            return;
        }
        
        // Check TP2 (50% close + move SL to TP1)
        if(active_signals[signal_index].tp2 > 0 && !active_signals[signal_index].tp2_hit && 
           current_price >= active_signals[signal_index].tp2)
        {
            active_signals[signal_index].tp2_hit = true;
            active_signals[signal_index].tp2_partial_done = true;
            
            // Close 50% of position
            double original_volume = test_positions[pos_index].volume;
            test_positions[pos_index].volume = NormalizeDouble(original_volume * 0.5, 2);
            
            // Move SL to TP1
            test_positions[pos_index].sl = active_signals[signal_index].tp1;
            
            Print("[TEST_TP2] Hit at ", current_price, " - 50% closed, SL moved to TP1: ", 
                  active_signals[signal_index].tp1);
            tests_passed++;
            
            // Report to web server if enabled
            if(TestConnectToWebServer)
            {
                ReportEvent(active_signals[signal_index].signal_id, "tp2_hit", 
                           "price=" + DoubleToString(current_price, 5) + 
                           ",closed_50_percent=true,sl_moved_to_tp1=" + DoubleToString(active_signals[signal_index].tp1, 5) +
                           ",test_mode=true");
            }
        }
        
        // Check TP1
        if(!active_signals[signal_index].tp1_hit && current_price >= active_signals[signal_index].tp1)
        {
            active_signals[signal_index].tp1_hit = true;
            
            // Single TP signal - close entire position
            if(active_signals[signal_index].tp2 <= 0 && active_signals[signal_index].tp3 <= 0)
            {
                CloseTestPosition(pos_index, "TP1_HIT_SINGLE");
                active_signals[signal_index].is_active = false;
                
                Print("[TEST_TP1] Single TP hit at ", current_price, " - Position closed");
                tests_passed++;
                
                // Report to web server if enabled
                if(TestConnectToWebServer)
                {
                    ReportEvent(active_signals[signal_index].signal_id, "tp1_hit", 
                               "price=" + DoubleToString(current_price, 5) + 
                               ",single_tp=true,closed_full=true,test_mode=true");
                }
            }
            // Multi-TP signal - close 50% and move SL to entry
            else
            {
                active_signals[signal_index].tp1_partial_done = true;
                
                // Close 50% of position
                double original_volume = test_positions[pos_index].volume;
                test_positions[pos_index].volume = NormalizeDouble(original_volume * 0.5, 2);
                
                // Move SL to entry
                test_positions[pos_index].sl = active_signals[signal_index].entry_price;
                
                Print("[TEST_TP1] Multi TP hit at ", current_price, " - 50% closed, SL moved to entry: ", 
                      active_signals[signal_index].entry_price);
                tests_passed++;
                
                // Report to web server if enabled
                if(TestConnectToWebServer)
                {
                    ReportEvent(active_signals[signal_index].signal_id, "tp1_hit", 
                               "price=" + DoubleToString(current_price, 5) + 
                               ",closed_50_percent=true,sl_moved_to_entry=" + DoubleToString(active_signals[signal_index].entry_price, 5) +
                               ",test_mode=true");
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Find test position by ticket                                     |
//+------------------------------------------------------------------+
int FindTestPositionByTicket(int ticket)
{
    for(int i = 0; i < test_position_count; i++)
    {
        if(test_positions[i].ticket == ticket && test_positions[i].is_open)
        {
            return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Close test position                                               |
//+------------------------------------------------------------------+
void CloseTestPosition(int pos_index, string reason)
{
    test_positions[pos_index].is_open = false;
    
    Print("[TEST_CLOSE] Position ", test_positions[pos_index].ticket, 
          " closed. Reason: ", reason, " | Price: ", current_test_price);
}

//+------------------------------------------------------------------+
//| Run single TP tests                                              |
//+------------------------------------------------------------------+
void RunSingleTPTests()
{
    // Implementation for specific single TP test scenarios
    // This would create controlled test signals and validate results
}

//+------------------------------------------------------------------+
//| Run multi TP tests                                               |
//+------------------------------------------------------------------+
void RunMultiTPTests()
{
    // Implementation for specific multi TP test scenarios
    // This would create controlled test signals and validate results
}

//+------------------------------------------------------------------+
//| Log test progress                                                 |
//+------------------------------------------------------------------+
void LogTestProgress()
{
    Print("=== TEST PROGRESS ===");
    Print("Tick: ", test_tick_count);
    Print("Current Price: ", current_test_price);
    Print("Active Signals: ", signal_count);
    Print("Test Positions: ", test_position_count);
    Print("Tests Passed: ", tests_passed);
    Print("Tests Failed: ", tests_failed);
    Print("Runtime: ", (TimeCurrent() - test_start_time), " seconds");
    Print("=====================");
}

//+------------------------------------------------------------------+
//| Send test signal to web server                                   |
//+------------------------------------------------------------------+
void SendTestSignalToWebServer(int signal_index)
{
    string url = ServerURL + "/add_signal";
    string headers = "Content-Type: application/json\r\n";
    
    // Create JSON payload matching the web server's expected format
    CJAVal json_obj;
    json_obj["id"] = active_signals[signal_index].signal_id;
    json_obj["message_id"] = active_signals[signal_index].message_id;
    json_obj["channel_id"] = -1001234567890; // Test channel ID
    json_obj["symbol"] = active_signals[signal_index].symbol;
    json_obj["action"] = active_signals[signal_index].action;
    json_obj["entry_price"] = active_signals[signal_index].entry_price;
    json_obj["stop_loss"] = active_signals[signal_index].stop_loss;
    json_obj["tp1"] = active_signals[signal_index].tp1;
    
    // Add optional TP2/TP3 only if they exist
    if(active_signals[signal_index].tp2 > 0)
        json_obj["tp2"] = active_signals[signal_index].tp2;
    if(active_signals[signal_index].tp3 > 0)
        json_obj["tp3"] = active_signals[signal_index].tp3;
    
    // Create raw message for the signal
    string raw_message = active_signals[signal_index].action + " LIMIT " + active_signals[signal_index].symbol + 
                        " @ " + DoubleToString(active_signals[signal_index].entry_price, 5) +
                        "\\nSL: " + DoubleToString(active_signals[signal_index].stop_loss, 5) +
                        "\\nTP1: " + DoubleToString(active_signals[signal_index].tp1, 5);
    
    if(active_signals[signal_index].tp2 > 0)
        raw_message += "\\nTP2: " + DoubleToString(active_signals[signal_index].tp2, 5);
    if(active_signals[signal_index].tp3 > 0)
        raw_message += "\\nTP3: " + DoubleToString(active_signals[signal_index].tp3, 5);
    raw_message += "\\n\\n[TEST MODE SIGNAL]";
    
    json_obj["raw_message"] = raw_message;
    
    string json = json_obj.Serialize();
    
    char post_data[];
    StringToCharArray(json, post_data, 0, StringLen(json));
    
    char result[];
    string result_headers;
    int timeout = 5000;
    
    int res = WebRequest("POST", url, headers, timeout, post_data, result, result_headers);
    
    if(res == 200)
    {
        Print("[TEST_WEB] Signal sent to web server: ", active_signals[signal_index].signal_id);
    }
    else if(res == 409)
    {
        Print("[TEST_WEB] Signal already exists on server (409) - continuing");
    }
    else
    {
        Print("[TEST_WEB] Failed to send signal to web server: HTTP ", res);
        if(EnableDebugLogging)
        {
            string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
            Print("[TEST_WEB] Response: ", response);
        }
    }
}

//+------------------------------------------------------------------+
//| Get symbol-specific fill type to prevent "Invalid fill" errors   |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetSymbolFillType(string symbol)
{
    // Check broker's supported fill modes for this symbol
    int fill_policy = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
    
    // SYMBOL_FILLING_MODE returns flags:
    // SYMBOL_FILL_FOK = 1    - Fill or Kill
    // SYMBOL_FILL_IOC = 2    - Immediate or Cancel  
    // SYMBOL_FILL_RETURN = 4 - Return (partial fills allowed)
    
    if(EnableDebugLogging)
    {
        Print("[FILL_TYPE] Symbol: ", symbol, " | Broker fill policy: ", fill_policy);
        Print("[FILL_TYPE] Supported modes - FOK: ", ((fill_policy & 1) != 0), 
              ", IOC: ", ((fill_policy & 2) != 0), 
              ", RETURN: ", ((fill_policy & 4) != 0));
    }
    
    // Prefer ORDER_FILLING_RETURN for limit orders (most compatible)
    if((fill_policy & 4) != 0)  // SYMBOL_FILL_RETURN supported
    {
        if(EnableDebugLogging)
            Print("[FILL_TYPE] Using ORDER_FILLING_RETURN for ", symbol);
        return ORDER_FILLING_RETURN;
    }
    // Fallback to IOC if RETURN not supported
    else if((fill_policy & 2) != 0)  // SYMBOL_FILL_IOC supported
    {
        if(EnableDebugLogging)
            Print("[FILL_TYPE] Using ORDER_FILLING_IOC for ", symbol, " (RETURN not supported)");
        return ORDER_FILLING_IOC;
    }
    // Last resort: FOK
    else if((fill_policy & 1) != 0)  // SYMBOL_FILL_FOK supported
    {
        if(EnableDebugLogging)
            Print("[FILL_TYPE] Using ORDER_FILLING_FOK for ", symbol, " (RETURN/IOC not supported)");
        return ORDER_FILLING_FOK;
    }
    else
    {
        // No fill modes supported (should not happen)
        Print("[FILL_ERROR] No fill modes supported for ", symbol, " - using default FOK");
        return ORDER_FILLING_FOK;
    }
}

//+------------------------------------------------------------------+
//| Calculate symbol-specific market order deviation                 |
//+------------------------------------------------------------------+
int CalculateSymbolSpecificDeviation(string symbol)
{
    // Detect symbol type for appropriate deviation
    bool is_precious_metal = (StringFind(symbol, "XAU") >= 0 || 
                             StringFind(symbol, "XAG") >= 0 ||
                             StringFind(symbol, "GOLD") >= 0 ||
                             StringFind(symbol, "SILVER") >= 0);
    
    bool is_jpy_pair = (StringFind(symbol, "JPY") >= 0);
    
    bool is_crypto = (StringFind(symbol, "USD") > 0 && 
                     (StringFind(symbol, "BTC") >= 0 || 
                      StringFind(symbol, "ETH") >= 0 ||
                      StringFind(symbol, "XRP") >= 0 ||
                      StringFind(symbol, "LTC") >= 0 ||
                      StringFind(symbol, "ADA") >= 0));
    
    int symbol_deviation;
    
    if(is_precious_metal)
    {
        // Gold/Silver: Higher deviation due to wider spreads and volatility
        symbol_deviation = MarketOrderDeviation * 5;  // 5x multiplier (e.g., 20 → 100 points)
        if(EnableDebugLogging)
            Print("[DEVIATION_CALC] Precious metal detected: Using ", symbol_deviation, " points (", 
                  DoubleToString(symbol_deviation/100.0, 1), " units)");
    }
    else if(is_crypto)
    {
        // Crypto: Higher deviation due to volatility
        symbol_deviation = MarketOrderDeviation * 3;  // 3x multiplier (e.g., 20 → 60 points)
        if(EnableDebugLogging)
            Print("[DEVIATION_CALC] Crypto detected: Using ", symbol_deviation, " points (", 
                  DoubleToString(symbol_deviation/10.0, 1), " units)");
    }
    else if(is_jpy_pair)
    {
        // JPY pairs: Use default (20 points = 20 pips, which is generous)
        symbol_deviation = MarketOrderDeviation;
        if(EnableDebugLogging)
            Print("[DEVIATION_CALC] JPY pair detected: Using ", symbol_deviation, " points (", 
                  DoubleToString(symbol_deviation/100.0, 2), " yen)");
    }
    else
    {
        // Forex major pairs: Use default
        symbol_deviation = MarketOrderDeviation;
        if(EnableDebugLogging)
            Print("[DEVIATION_CALC] Forex pair detected: Using ", symbol_deviation, " points (", 
                  DoubleToString(symbol_deviation/10.0, 1), " pips)");
    }
    
    return symbol_deviation;
}

//+------------------------------------------------------------------+