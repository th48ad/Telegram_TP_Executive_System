# Cursor AI Assistant - Codebase Onboarding Guide

> **⚡ READ THIS FIRST** - This document brings you up to speed on the entire Telegram TP Executive System codebase, recent improvements, and development patterns. Read it thoroughly before making any code changes.

## 🎯 System Overview

This is a **production-ready Telegram signal processing system** that bridges Telegram trading signals with MetaTrader 5 (MT5) Expert Advisors (EAs). The system processes real-time trading signals, stores them in a database, and provides APIs for MT5 EAs to retrieve and execute trades.

### 🏗️ Core Architecture

```
Telegram Channels -> Python Listener -> Signal Parser -> Database -> Web API -> MT5 EA
                                    ↓
                               OpenAI GPT-3.5 (Signal Validation)
```

**Data Flow:**
1. **Telegram Listener** monitors channels for trading signals
2. **Signal Parser** uses OpenAI + regex fallback to extract trade data
3. **Database** stores signals and trade events with full audit trail
4. **Web Server** exposes REST API for EA integration
5. **MT5 EA** polls for signals and reports trade events back

## 📁 Key Components

### 🔥 Core Files (CRITICAL - Touch these carefully)

| File | Purpose | Key Notes |
|------|---------|-----------|
| `main.py` | System orchestrator | Starts web server + Telegram listener |
| `simple_web_server.py` | Flask REST API | **6 endpoints**, handles all EA communication |
| `simple_telegram_listener.py` | Telegram message processor | Uses Telethon, **limit orders only** |
| `simple_signal_parser.py` | Signal extraction engine | OpenAI + regex fallback, **very robust** |
| `config.py` | Central configuration | Environment variables, **DEBUG controls** |

### 🧪 Testing & Tools

| File | Purpose | Key Notes |
|------|---------|-----------|
| `tests/test_web_server.py` | **Comprehensive test suite** | **7 test categories**, 100% pass rate |
| `MT5_Signal_EA/TelegramSignalPolling_MT5.mq5` | MT5 Expert Advisor | Production-ready, **real-time TP monitoring** |

### 📊 Database Schema

**Signals Table:**
- Core fields: `id`, `message_id`, `symbol`, `action`, `entry_price`, `stop_loss`, `tp1`, `tp2`, `tp3`
- Status tracking: `status` (pending/active/completed/failed)
- **message_id** serves as **magic number** for MT5 integration

**Events Table:**
- Full audit trail of all trade activities
- Links to signals via `signal_id` or `message_id`
- Event types: `order_placed`, `tp1_hit`, `tp2_hit`, `tp3_hit`, `sl_hit`, `manual_close`, etc.

## 🚀 Recent Improvements & Features

### ✅ **Enhanced Signal State Recovery** (CRITICAL FEATURE)
- System can rebuild signal state from event history
- **TP progression tracking**: TP1→TP2→TP3 with SL movements
- **Recovery state**: tracks `tp1_hit`, `tp2_hit`, `tp3_hit` flags
- **Automatic SL adjustment**: SL moves to entry after TP1, to TP1 price after TP2

### ✅ **Dual-ID Event Reporting** (MAJOR IMPROVEMENT)
- `/report_event` accepts **both** `signal_id` AND `message_id`
- **Fallback mechanism**: if signal_id fails, tries message_id
- **Enhanced error handling** with specific error messages

### ✅ **Real-Time TP Monitoring** (PERFORMANCE BOOST)
- EA uses `OnTick()` instead of timer-based checks
- **Immediate TP detection** reduces slippage
- **Memory management**: automatic cleanup of orphaned signals

### ✅ **Debug-Level Statistics** (LOG BLOAT FIX)
- Periodic stats moved behind `DEBUG_STATISTICS` flag
- Prevents log spam in production
- **5-minute interval** stats when enabled

### ✅ **Crypto Symbol Support** (BROKER COMPATIBILITY)
- Handles incorrect broker tick values for crypto pairs
- **Volume normalization** using `SYMBOL_VOLUME_STEP`
- Proper point values: ETHUSD=$1, BTCUSD=$10 per point per lot

### ✅ **Enhanced Error Handling**
- **Orphaned signal cleanup**: signals marked inactive on order errors
- **Session invalidation recovery**: automatic Telegram re-authentication
- **Comprehensive validation** with detailed error messages

## 🌐 REST API Endpoints

| Endpoint | Method | Purpose | Key Notes |
|----------|--------|---------|-----------|
| `/health` | GET | Server health check | Always returns `healthy` status |
| `/add_signal` | POST | Add new trading signal | **Validates all required fields** |
| `/get_pending_signals` | GET | Get active signals | Returns signals not yet completed |
| `/report_event` | POST | Report trade events | **Dual-ID support** (signal_id OR message_id) |
| `/get_signal_state/<message_id>` | GET | Get signal + event history | **State recovery from events** |
| `/stats` | GET | System statistics | Total signals, events, uptime |

### 🔑 **EA Integration Pattern**
```
1. EA polls /get_pending_signals
2. EA opens trades using message_id as magic number
3. EA reports events via /report_event (using message_id)
4. EA monitors TP hits in real-time with OnTick()
5. System automatically tracks state changes
```

## 🛠️ Development Patterns & Conventions

### 🎯 **Testing Requirements**
- **ALWAYS run the test suite** before and after changes: `cd tests && python test_web_server.py`
- **100% pass rate required** - all 7 test categories must pass
- Test covers: health, signals, events, state recovery, stats, concurrency

### 📝 **Logging Standards**
- Use structured logging with emojis: `🚀`, `✅`, `❌`, `⚠️`
- **Statistics behind DEBUG flag**: `if config.DEBUG_STATISTICS:`
- **Critical errors** always logged, info/debug level-appropriate

### 🗄️ **Database Patterns**
- **Always use transactions** for multi-table operations
- **message_id is sacred** - it's the bridge between Telegram and MT5
- **Event ordering matters** - use timestamps for chronological reconstruction

### 🔒 **Security Considerations**
- **No sensitive data in logs** (API keys, phone numbers partially masked)
- **Input validation** on all endpoints
- **SQL injection protection** via parameterized queries

## ⚙️ Configuration Management

### 📋 **Environment Variables** (.env file)
```bash
# Telegram Configuration
TELEGRAM_API_ID=your_api_id
TELEGRAM_API_HASH=your_api_hash
TELEGRAM_PHONE=+1234567890

# OpenAI Configuration  
OPENAI_API_KEY=your_openai_key

# Server Configuration
WEB_SERVER_PORT=8888
DATABASE_PATH=signals.db

# Debug Controls
DEBUG_STATISTICS=false  # Set to true for development only
```

### 🎛️ **Key Configuration Notes**
- **Phone number format**: Must include country code (+1, +44, etc.)
- **Database path**: Relative to project root
- **Port 8888**: Standard port, change if conflicts occur
- **DEBUG_STATISTICS**: **NEVER enable in production** (log bloat)

## 🚨 Critical Implementation Details

### ⚡ **Signal Processing Rules**
- **LIMIT ORDERS ONLY** - system ignores market orders, replies, close instructions
- **Telegram Authentication**: May require periodic re-authentication
- **OpenAI Fallback**: If GPT fails, regex parser handles standard formats
- **Volume Calculation**: Different for crypto vs forex pairs

### 🎯 **EA Integration Gotchas**
- **Magic Number = message_id**: This is the key correlation
- **TP Nullification**: When TP1 hits, TP1 field becomes `null` in responses
- **SL Movement**: Automatic SL adjustments after each TP hit
- **Real-time Monitoring**: Use OnTick() not OnTimer() for TP detection

### 🔧 **System Recovery**
- **Signal State**: Can be rebuilt from event history
- **Orphaned Signals**: Automatically cleaned up on errors
- **Memory Management**: Built-in cleanup prevents memory leaks
- **Session Recovery**: Telegram sessions auto-recover from invalidation

## 🧪 Testing & Verification

### ✅ **Test Suite Coverage**
1. **Health Check** - Server responsiveness
2. **Add Signal** - Signal validation and storage (4 scenarios)
3. **Get Pending Signals** - Signal retrieval and structure
4. **Report Event** - Event logging with dual-ID support (3 scenarios)
5. **Get Signal State** - State reconstruction from events
6. **Stats Endpoint** - System metrics accuracy
7. **Concurrent Access** - Multi-threaded performance (10 parallel requests)

### 🎯 **How to Test Changes**
```bash
# 1. Start the system
python main.py

# 2. In another terminal, run tests
cd tests
python test_web_server.py

# 3. Check specific endpoint
curl http://localhost:8888/health
curl http://localhost:8888/stats

# 4. Monitor logs
tail -f signal_system.log
```

## 🚀 Common Development Tasks

### 🔧 **Adding New Event Types**
1. Update event type validation in `simple_web_server.py`
2. Add handling logic in signal state recovery
3. Update EA to report new event type
4. Add test cases for new event type

### 📊 **Database Schema Changes**
1. **NEVER** alter existing columns without migration
2. Always add new columns as nullable initially
3. Update both `database.py` and any hard-coded queries
4. Test with existing data before deployment

### 🌐 **API Endpoint Changes**
1. **Maintain backwards compatibility** - EAs depend on current structure
2. Add new optional fields, don't remove existing ones
3. Update test suite to cover new functionality
4. Document changes in this file

## 🏃‍♂️ Quick Start for New Tasks

### 📋 **Before Making Any Changes:**
1. **Read this entire document** (you're doing it now ✅)
2. **Start the system**: `python main.py`
3. **Run test suite**: `cd tests && python test_web_server.py`
4. **Verify 100% pass rate** before proceeding
5. **Check current stats**: `curl localhost:8888/stats`

### 🎯 **For Bug Fixes:**
1. **Reproduce the issue** with test cases
2. **Check logs** for error patterns
3. **Make minimal changes** to fix the root cause
4. **Re-run full test suite** to ensure no regressions
5. **Verify fix with real-world scenario**

### 🚀 **For New Features:**
1. **Understand the data flow** (Telegram → Parser → DB → API → EA)
2. **Design database changes** if needed (migrations!)
3. **Update API endpoints** maintaining backwards compatibility
4. **Add comprehensive test coverage**
5. **Update EA if integration changes**
6. **Update this document** with new patterns

## ⚠️ Critical Warnings

### 🚨 **Never Break These:**
- **message_id correlation** between Telegram and MT5
- **Backwards compatibility** of API responses
- **Event ordering** in database (timestamps matter)
- **Signal status transitions** (pending→active→completed)

### 💀 **Dangerous Operations:**
- Modifying database schema without migrations
- Changing API response structure (breaks EAs)
- Removing environment variables (breaks deployments)
- Disabling event logging (loses audit trail)

### 🔧 **Safe Practices:**
- Always use transactions for multi-table operations
- Add new fields as optional/nullable first
- Test with real Telegram messages when possible
- Monitor system logs after any changes

## 🎯 Success Metrics

**System is healthy when:**
- ✅ Test suite: 100% pass rate (7/7 tests)
- ✅ API responses: < 100ms average
- ✅ Memory usage: Stable over time
- ✅ Signal processing: No orphaned signals
- ✅ Event tracking: Complete audit trail
- ✅ EA integration: Seamless magic number lookups

## 🆘 Emergency Procedures

### 🚨 **System Down:**
1. Check `signal_system.log` for errors
2. Verify database connectivity: `sqlite3 signals.db ".tables"`
3. Test API manually: `curl localhost:8888/health`
4. Restart system: `python main.py`

### 🔧 **Database Corruption:**
1. **STOP** the system immediately
2. Backup current database: `cp signals.db signals.db.backup`
3. Check integrity: `sqlite3 signals.db "PRAGMA integrity_check;"`
4. Restore from known good backup if needed

### 📱 **Telegram Authentication Issues:**
1. Delete session file: `rm *.session`
2. Restart system - will prompt for re-authentication
3. Approve login on your Telegram app
4. Monitor logs for successful connection

---

## 🎉 You're Now Ready!

You've been fully briefed on the **Telegram TP Executive System**. This is a **production-ready, battle-tested** codebase with comprehensive error handling, state recovery, and real-time performance optimizations.

**Key mantras:**
- 🧪 **Test everything** (100% pass rate required)
- 🔄 **Maintain backwards compatibility** (EAs depend on it)
- 📊 **Preserve data integrity** (message_id is sacred)
- ⚡ **Keep it performant** (real-time trading system)

**Next steps:**
1. Run the test suite to confirm environment
2. Make your changes following the patterns above
3. Test thoroughly with real scenarios
4. Update this document with any new patterns

Happy coding! 🚀 