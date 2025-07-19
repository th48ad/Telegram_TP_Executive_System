# Telegram Signal Trading System

**A comprehensive automated trading system that monitors Telegram channels for trading signals and executes them via MetaTrader 5 with autonomous position management.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![MT5](https://img.shields.io/badge/platform-MetaTrader%205-green.svg)](https://www.metatrader5.com/)

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [API Reference](#api-reference)
- [Database Schema](#database-schema)
- [EA Configuration](#ea-configuration)
- [Signal Format](#signal-format)
- [Monitoring & Logging](#monitoring--logging)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Contributing](#contributing)
- [License](#license)

## 🔍 Overview

This system automates the entire trading workflow from signal detection to position closure:

1. **📡 Monitors** Telegram channels for trading signals
2. **🤖 Parses** signals using AI-enhanced pattern recognition
3. **💾 Stores** signals in SQLite database with full audit trail
4. **📊 Exposes** REST API for MetaTrader 5 integration
5. **🎯 Executes** trades via custom MT5 Expert Advisor
6. **🔄 Manages** positions autonomously with trailing stops
7. **📈 Reports** all events back to central database

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Telegram       │    │   Python Core    │    │   MetaTrader 5  │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │   Signal    │◄┼────┼─│  Telegram    │ │    │ │    Expert   │ │
│ │  Channels   │ │    │ │  Listener    │ │    │ │   Advisor   │ │
│ └─────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
│                 │    │         │        │    │         ▲       │
└─────────────────┘    │         ▼        │    │         │       │
                       │ ┌──────────────┐ │    │         │       │
┌─────────────────┐    │ │    Signal    │ │    │         │       │
│    OpenAI       │    │ │   Parser     │ │    │         │       │
│      API        │◄───┼─│ (AI Enhanced)│ │    │         │       │
└─────────────────┘    │ └──────────────┘ │    │         │       │
                       │         │        │    │         │       │
                       │         ▼        │    │         │       │
                       │ ┌──────────────┐ │    │         │       │
                       │ │   SQLite     │ │    │         │       │
                       │ │  Database    │ │    │         │       │
                       │ └──────────────┘ │    │         │       │
                       │         │        │    │         │       │
                       │         ▼        │    │         │       │
                       │ ┌──────────────┐ │    │         │       │
                       │ │   REST API   │ │◄───┼─────────┘       │
                       │ │  Web Server  │ │    │                 │
                       │ └──────────────┘ │    │                 │
                       └──────────────────┘    └─────────────────┘
```

### Core Components

#### 1. **Telegram Listener** (`simple_telegram_listener.py`)
- Monitors Telegram channels using Telethon library
- Supports both Bot API and MTProto user account methods
- Handles private channels via invite links
- Real-time message processing with rate limiting
- Automatic session management and reconnection

#### 2. **Signal Parser** (`simple_signal_parser.py`)
- AI-enhanced signal parsing using OpenAI GPT models
- Regex fallback for offline operation
- Supports 1-3 take profit levels
- Validates signal format and market conditions
- Extracts: symbol, direction, entry, stop loss, take profits

#### 3. **Web Server** (`simple_web_server.py`)
- RESTful API for MT5 communication
- SQLite database with full audit trail
- Signal state management and recovery
- Event reporting and status tracking
- Health monitoring and statistics

#### 4. **MetaTrader 5 Expert Advisor** (`MT5_Signal_EA/SimpleSignalEA_MT5.mq5`)
- Autonomous position management
- Real-time TP monitoring via OnTick()
- Intelligent trailing stops
- Risk management with position sizing
- Complete trade lifecycle reporting

#### 5. **Configuration Management** (`config.py`)
- Environment-based configuration
- Validation and error handling
- Support for multiple deployment environments
- Secure credential management

## ✨ Features

### 🎯 **Signal Processing**
- **Multi-format support**: Handles various Telegram signal formats
- **AI enhancement**: OpenAI integration for complex signal parsing
- **Validation**: Comprehensive signal validation before execution
- **Deduplication**: Prevents duplicate signal processing

### 🔄 **Position Management**
- **Autonomous trailing**: Dynamic stop loss management
- **Partial closures**: Graduated position closure at TP levels
- **Risk management**: Position sizing based on account risk percentage
- **Recovery**: Automatic signal recovery after EA restart

### 📊 **Monitoring & Reporting**
- **Real-time events**: Complete trade lifecycle tracking
- **Database audit**: Full signal and event history
- **Health checks**: System status monitoring
- **Statistics**: Performance metrics and analytics

### 🛡️ **Security & Reliability**
- **Error handling**: Comprehensive error handling and recovery
- **Rate limiting**: Telegram API rate limiting compliance
- **Session management**: Automatic session recovery
- **Data integrity**: Database constraints and validation

## 📋 Prerequisites

### Software Requirements
- **Python 3.8+** with pip
- **MetaTrader 5** platform
- **SQLite 3** (included with Python)

### Telegram Requirements
- **Telegram account** with API credentials
- **Channel access** (member of signal channel)
- **API credentials** from https://my.telegram.org

### Trading Requirements
- **MetaTrader 5** broker account
- **VPS/Server** for 24/7 operation (recommended)
- **Stable internet** connection

## 🚀 Installation

### 1. Clone Repository
```bash
git clone https://github.com/yourusername/telegram-signal-trading.git
cd telegram-signal-trading
```

### 2. Create Virtual Environment
```bash
python -m venv venv

# Windows
venv\Scripts\activate

# Linux/Mac
source venv/bin/activate
```

### 3. Install Dependencies
```bash
pip install -r requirements.txt
```

### 4. Configure Environment
```bash
# Copy example configuration
cp .env.example .env

# Edit with your actual values
nano .env  # or your preferred editor
```

### 5. Initialize Database
```bash
# Database will be created automatically on first run
python -c "from simple_web_server import SimpleSignalServer; server = SimpleSignalServer(); print('Database initialized')"
```

### 6. Install MetaTrader 5 EA
1. Copy `MT5_Signal_EA/SimpleSignalEA_MT5.mq5` to your MT5 `MQL5/Experts/` folder
2. Copy `MT5_Signal_EA/JAson.mqh` to your MT5 `MQL5/Include/` folder
3. Compile the EA in MetaEditor
4. Enable WebRequest for `http://localhost:8888` in MT5 settings

## ⚙️ Configuration

### Environment Variables

Create a `.env` file based on `.env.example`:

```bash
# Telegram Configuration
TELEGRAM_API_ID=your_api_id
TELEGRAM_API_HASH=your_api_hash
TELEGRAM_PHONE_NUMBER=+1234567890
TELEGRAM_CHANNEL_INVITE_LINK=https://t.me/+your_invite_hash

# MT5 Communication
MT4_HTTP_HOST=localhost
MT4_HTTP_PORT=8888
MT4_HTTP_TIMEOUT=5

# Trading Configuration
DEFAULT_RISK_PERCENT=1.0
MAX_CONCURRENT_TRADES=5
ENABLE_TRADE_FILTERS=true

# Logging
LOG_LEVEL=INFO
LOG_FILE=telegram_signals.log
DEBUG_STATISTICS=false

# Optional: OpenAI for enhanced parsing
OPENAI_API_KEY=your_openai_api_key
```

### MetaTrader 5 EA Parameters

#### Production Parameters
- **EnableTrading**: `true` - Enable live trading
- **EnableDebugLogging**: `false` - Reduce log noise in production
- **RiskPercent**: `2.0` - Risk percentage per trade
- **ServerURL**: `http://127.0.0.1:8888` - Web server endpoint
- **SymbolSuffix**: `.PRO` - Broker-specific symbol suffix

#### Testing Parameters
- **TestMode**: `false` - Disable for live trading
- **LiveTestMode**: `false` - Disable for production

## 🎮 Usage

### 1. Start the System
```bash
# Start both web server and Telegram listener
python main.py
```

### 2. Attach EA to MT5
1. Open MetaTrader 5
2. Drag `SimpleSignalEA_MT5` to any chart
3. Configure parameters as needed
4. Enable automated trading

### 3. Monitor Operations
```bash
# Check system health
curl http://localhost:8888/health

# View pending signals
curl http://localhost:8888/pending_signals

# Check statistics
curl http://localhost:8888/stats
```

### 4. View Logs
```bash
# System logs
tail -f signal_system.log

# MT5 logs (check MT5 Experts tab)
```

## 📡 API Reference

### Base URL
```
http://localhost:8888
```

### Endpoints

#### `GET /health`
System health check
```json
{
  "status": "healthy",
  "timestamp": "2024-07-18T10:30:00Z",
  "database": "connected",
  "version": "2.0"
}
```

#### `GET /pending_signals`
Get pending signals for EA processing
```json
{
  "signals": [
    {
      "id": "uuid-string",
      "message_id": 12345,
      "symbol": "EURUSD",
      "action": "BUY",
      "entry_price": 1.0850,
      "stop_loss": 1.0800,
      "tp1": 1.0900,
      "tp2": 1.0950,
      "tp3": 1.1000
    }
  ]
}
```

#### `POST /report_event`
Report trading events from EA
```json
{
  "signal_id": "uuid-string",
  "event_type": "tp1_hit",
  "event_data": {
    "execution_price": 1.0899,
    "slippage": 0.0001
  }
}
```

#### `GET /get_signal_state/<message_id>`
Get signal state for recovery
```json
{
  "signal": {
    "id": "uuid-string",
    "status": "active",
    "recovery_state": {
      "tp1_hit": true,
      "tp2_hit": false,
      "tp3_hit": false,
      "current_sl": 1.0850
    }
  }
}
```

#### `POST /add_signal`
Add new signal (internal use)
```json
{
  "message_id": 12345,
  "channel_id": -1001234567890,
  "symbol": "EURUSD",
  "action": "BUY",
  "entry_price": 1.0850,
  "stop_loss": 1.0800,
  "tp1": 1.0900,
  "tp2": 1.0950,
  "tp3": 1.1000,
  "raw_message": "Original telegram message"
}
```

#### `GET /stats`
System statistics
```json
{
  "total_signals": 150,
  "active_signals": 3,
  "completed_signals": 145,
  "failed_signals": 2,
  "success_rate": 96.7,
  "database_size": "2.5MB"
}
```

## 🗄️ Database Schema

### Signals Table
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT (PK) | Unique signal identifier |
| message_id | INTEGER (UNIQUE) | Telegram message ID |
| channel_id | INTEGER | Telegram channel ID |
| symbol | TEXT | Trading symbol |
| action | TEXT | "BUY" or "SELL" |
| entry_price | REAL | Limit order entry price |
| stop_loss | REAL | Initial stop loss |
| tp1 | REAL | Take profit level 1 |
| tp2 | REAL | Take profit level 2 (optional) |
| tp3 | REAL | Take profit level 3 (optional) |
| raw_message | TEXT | Original telegram message |
| status | TEXT | Signal status |
| created_at | TIMESTAMP | Creation time |
| updated_at | TIMESTAMP | Last update time |

### Trade Events Table
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER (PK) | Auto-increment ID |
| signal_id | TEXT (FK) | References signals.id |
| event_type | TEXT | Event type |
| event_data | TEXT | JSON event details |
| timestamp | TIMESTAMP | Event timestamp |

### Event Types
- `order_placed` - EA placed limit order
- `position_opened` - Limit order filled
- `tp1_hit` - TP1 reached, SL moved to entry
- `tp2_hit` - TP2 reached, 50% closed
- `tp3_hit` - TP3 reached, position closed
- `sl_hit` - Stop loss triggered
- `manual_close` - Manual position closure
- `error` - EA error occurred
- `ea_started` - EA started/restarted

## 🎯 Signal Format

### Supported Formats

#### Basic Format
```
EURUSD BUY @ 1.0850
SL: 1.0800
TP: 1.0900
```

#### Multi-TP Format
```
#signals 🔴 EURUSD

▫️ Buy Limit Order: 1.0850

▫️ Target Profit 1: 1.0900
▫️ Target Profit 2: 1.0950  
▫️ Target Profit 3: 1.1000

▫️ Stop Loss: 1.0800
```

#### Emoji Format
```
🔥 EURUSD BUY 🔥
📈 Entry: 1.0850
🛑 SL: 1.0800
🎯 TP1: 1.0900
🎯 TP2: 1.0950
🎯 TP3: 1.1000
```

### Parsing Logic
1. **OpenAI First**: If API key configured, uses GPT for parsing
2. **Regex Fallback**: Pattern matching for standard formats
3. **Validation**: Checks price relationships and market hours
4. **Filtering**: Removes replies, confirmations, and non-signals

## 📊 Monitoring & Logging

### Log Files
- **signal_system.log**: Main system log
- **MT5 Experts**: EA execution log
- **Database**: SQLite file with all data

### Log Levels
- **DEBUG**: Detailed debugging information
- **INFO**: General information and events
- **WARNING**: Warning conditions
- **ERROR**: Error conditions requiring attention

### Health Monitoring
```bash
# Check system status
curl http://localhost:8888/health

# Monitor logs in real-time
tail -f signal_system.log

# Check database
sqlite3 signals.db "SELECT COUNT(*) FROM signals WHERE status='active';"
```

### Performance Metrics
- Signal processing latency
- Database query performance  
- Telegram API response times
- EA execution speeds
- Memory usage monitoring

## 🔧 Troubleshooting

### Common Issues

#### 1. Telegram Authentication Failed
```bash
# Error: "The key is not registered in the system"
# Solution: Delete session file and re-authenticate
rm *.session
python simple_telegram_listener.py
```

#### 2. EA Not Receiving Signals
```bash
# Check web server status
curl http://localhost:8888/health

# Verify EA parameters
# - ServerURL: http://127.0.0.1:8888
# - EnableTrading: true
# - WebRequest allowed in MT5 settings
```

#### 3. Database Locked Error
```bash
# Stop all processes
pkill -f "python.*main.py"
pkill -f "python.*simple_web_server.py"

# Restart system
python main.py
```

#### 4. OpenAI API Errors
```bash
# Check API key validity
export OPENAI_API_KEY="your_key"
python -c "import openai; print(openai.models.list())"

# Fallback to regex parsing by removing API key
```

#### 5. Signal Parsing Issues
```bash
# Enable debug logging
export LOG_LEVEL=DEBUG
python main.py

# Check parsed signals
curl http://localhost:8888/stats
```

### Debug Mode

Enable comprehensive debugging:
```bash
# Environment
export LOG_LEVEL=DEBUG
export DEBUG_STATISTICS=true

# EA Parameters  
EnableDebugLogging = true

# Database queries
sqlite3 signals.db "SELECT * FROM trade_events ORDER BY timestamp DESC LIMIT 10;"
```

## 🔒 Security Considerations

### Credential Management
- **Never commit** `.env` files to version control
- **Use environment variables** for sensitive data
- **Rotate API keys** regularly
- **Restrict file permissions** on configuration files

### Network Security
- **Firewall rules** for web server port
- **VPN access** for remote management
- **SSL/TLS** for production deployments
- **API rate limiting** compliance

### Trading Security
- **Risk management** limits in EA
- **Position size** validation
- **Stop loss** mandatory on all trades
- **Account monitoring** for unusual activity

### Data Protection
- **Database encryption** for sensitive data
- **Log rotation** to prevent disk space issues
- **Backup strategies** for critical data
- **Access controls** on system files

## 🤝 Contributing

### Development Setup
```bash
# Fork and clone repository
git clone https://github.com/yourusername/telegram-signal-trading.git
cd telegram-signal-trading

# Create development environment
python -m venv dev-env
source dev-env/bin/activate  # Linux/Mac
# or dev-env\Scripts\activate  # Windows

# Install development dependencies
pip install -r requirements.txt
pip install -r requirements-dev.txt

# Run tests
python -m pytest tests/
```

### Code Style
- **PEP 8** compliance for Python code
- **Type hints** for function parameters
- **Docstrings** for all public functions
- **Unit tests** for new features

### Contribution Process
1. **Fork** the repository
2. **Create** feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** changes (`git commit -m 'Add amazing feature'`)
4. **Push** to branch (`git push origin feature/amazing-feature`)
5. **Open** Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

**Trading financial instruments involves substantial risk of loss and is not suitable for all investors. Past performance is not indicative of future results. This software is provided for educational purposes only. Use at your own risk.**

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/telegram-signal-trading/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/telegram-signal-trading/discussions)
- **Wiki**: [Project Wiki](https://github.com/yourusername/telegram-signal-trading/wiki)

---

**Built with ❤️ for the trading community** 