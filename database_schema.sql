-- Simplified Database Schema for Telegram Signal System
-- Clean, minimal design focused on core functionality

-- Main signals table - one record per telegram signal (supports 1-3 TP levels)
CREATE TABLE IF NOT EXISTS signals (
    id TEXT PRIMARY KEY,                    -- Unique signal identifier
    message_id INTEGER UNIQUE NOT NULL,     -- Telegram message ID (used as magic number)
    channel_id INTEGER NOT NULL,           -- Telegram channel ID
    symbol TEXT NOT NULL,                  -- Trading symbol (e.g., "EURUSD")
    action TEXT NOT NULL,                  -- "BUY" or "SELL"
    entry_price REAL NOT NULL,             -- Limit order entry price
    stop_loss REAL NOT NULL,               -- Initial stop loss
    tp1 REAL NOT NULL,                     -- Take profit level 1 (required)
    tp2 REAL,                              -- Take profit level 2 (optional)
    tp3 REAL,                              -- Take profit level 3 (optional)
    raw_message TEXT NOT NULL,             -- Original telegram message
    status TEXT DEFAULT 'pending',         -- 'pending', 'active', 'completed', 'failed'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trade events table - tracks all EA actions and status changes
CREATE TABLE IF NOT EXISTS trade_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signal_id TEXT NOT NULL,               -- References signals.id
    event_type TEXT NOT NULL,              -- Event type (see below)
    event_data TEXT,                       -- JSON data for event details
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (signal_id) REFERENCES signals(id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_signals_status ON signals(status);
CREATE INDEX IF NOT EXISTS idx_signals_message_id ON signals(message_id);
CREATE INDEX IF NOT EXISTS idx_trade_events_signal ON trade_events(signal_id);
CREATE INDEX IF NOT EXISTS idx_trade_events_type ON trade_events(event_type);

-- Event types for trade_events.event_type:
-- 'order_placed'     - EA placed limit order
-- 'position_opened'  - Limit order filled, position opened
-- 'tp1_hit'         - TP1 reached, SL moved to entry
-- 'tp2_hit'         - TP2 reached, 50% closed, SL moved to TP1
-- 'tp3_hit'         - TP3 reached, position fully closed
-- 'sl_hit'          - Stop loss triggered
-- 'manual_close'    - Position closed manually by user
-- 'error'           - EA encountered an error
-- 'ea_started'      - EA started/restarted, loaded signal 