#!/usr/bin/env python3
"""
Simplified Telegram Signal Web Server
Clean, minimal implementation focused on core EA communication
"""

import sqlite3
import json
import logging
from datetime import datetime
from typing import Dict, List, Optional
from flask import Flask, request, jsonify
import threading
import time
import os
from windows_logging import setup_windows_safe_logging

# Setup Windows-safe logging with forced emoji replacement for Windows compatibility
logger = setup_windows_safe_logging(__name__, force_emoji_replacement=True)

class SimpleSignalServer:
    """Simplified web server for EA communication"""
    
    def __init__(self, db_path: str = "signals.db", port: int = 8888):
        self.db_path = db_path
        self.port = port
        self.app = Flask(__name__)
        self.running = False
        
        # Initialize database
        self._init_database()
        self._setup_routes()
        
        logger.info(f"SimpleSignalServer initialized - DB: {db_path}, Port: {port}")
    
    def _init_database(self):
        """Initialize database with simplified schema"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                # Read and execute schema
                schema_path = os.path.join(os.path.dirname(__file__), 'database_schema.sql')
                if os.path.exists(schema_path):
                    with open(schema_path, 'r') as f:
                        schema = f.read()
                    conn.executescript(schema)
                else:
                    # Fallback - create tables inline (supports 1-3 TP levels)
                    conn.executescript("""
                        CREATE TABLE IF NOT EXISTS signals (
                            id TEXT PRIMARY KEY,
                            message_id INTEGER UNIQUE NOT NULL,
                            channel_id INTEGER NOT NULL,
                            symbol TEXT NOT NULL,
                            action TEXT NOT NULL,
                            entry_price REAL NOT NULL,
                            stop_loss REAL NOT NULL,
                            tp1 REAL NOT NULL,
                            tp2 REAL,
                            tp3 REAL,
                            raw_message TEXT NOT NULL,
                            status TEXT DEFAULT 'pending',
                            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                        );
                        
                        CREATE TABLE IF NOT EXISTS trade_events (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            signal_id TEXT NOT NULL,
                            event_type TEXT NOT NULL,
                            event_data TEXT,
                            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                            FOREIGN KEY (signal_id) REFERENCES signals(id)
                        );
                        
                        CREATE INDEX IF NOT EXISTS idx_signals_status ON signals(status);
                        CREATE INDEX IF NOT EXISTS idx_signals_message_id ON signals(message_id);
                    """)
                    
                conn.commit()
                logger.info("Database initialized successfully")
                
        except Exception as e:
            logger.error(f"Database initialization failed: {e}")
            raise
    
    def _setup_routes(self):
        """Setup Flask routes"""
        
        @self.app.before_request
        def log_request_info():
            """Log all incoming requests for debugging"""
            if request.path != '/health':  # Skip health checks to avoid spam
                logger.info(f"=== REQUEST DEBUG ===")
                logger.info(f"Method: {request.method}")
                logger.info(f"Path: {request.path}")
                logger.info(f"Full URL: {request.url}")
                logger.info(f"Headers: {dict(request.headers)}")
                if request.method in ['POST', 'PUT'] and request.is_json:
                    logger.info(f"JSON Data: {request.get_json()}")
                logger.info(f"==================")
        
        @self.app.route('/health', methods=['GET'])
        def health():
            """Health check endpoint"""
            return jsonify({
                'status': 'healthy',
                'timestamp': datetime.now().isoformat(),
                'server': 'SimpleSignalServer'
            })
        
        @self.app.route('/get_pending_signals', methods=['GET'])
        def get_pending_signals():
            """Get all pending signals for EA to process"""
            try:
                with sqlite3.connect(self.db_path) as conn:
                    cursor = conn.execute("""
                        SELECT id, message_id, symbol, action, entry_price, stop_loss, tp1, tp2, tp3
                        FROM signals 
                        WHERE status = 'pending'
                        ORDER BY created_at ASC
                        LIMIT 10
                    """)
                    
                    signals = []
                    for row in cursor.fetchall():
                        signal = {
                            'id': row[0],
                            'message_id': row[1],  # This becomes magic number
                            'symbol': row[2],
                            'action': row[3],
                            'entry_price': row[4],
                            'stop_loss': row[5],
                            'tp1': row[6],
                            'tp2': row[7],
                            'tp3': row[8]
                        }
                        signals.append(signal)
                    
                    # Only log when there are actual signals to avoid log spam
                    if len(signals) > 0:
                        logger.info(f"Returned {len(signals)} pending signals to EA")
                    
                    return jsonify({'signals': signals})
                    
            except Exception as e:
                logger.error(f"Error getting pending signals: {e}")
                return jsonify({'error': str(e)}), 500
        
        @self.app.route('/report_event', methods=['POST'])
        def report_event():
            """EA reports trade events"""
            logger.info("=== DEBUG: /report_event endpoint called with enhanced fallback logic ===")
            try:
                # Handle JSON parsing errors
                data = request.get_json()
                if not data:
                    return jsonify({'error': 'No JSON data provided'}), 400
            except Exception as e:
                return jsonify({'error': 'Invalid JSON format'}), 400
            
            try:
                
                signal_id = data.get('signal_id')
                message_id = data.get('message_id')  # Alternative to signal_id
                event_type = data.get('event_type')
                event_data = data.get('event_data', {})
                
                if not event_type:
                    return jsonify({'error': 'event_type is required'}), 400
                
                with sqlite3.connect(self.db_path) as conn:
                    # Enhanced fallback logic: try signal_id first, then fallback to message_id
                    original_signal_id = signal_id
                    
                    # If signal_id not provided, look it up by message_id
                    if not signal_id and message_id:
                        cursor = conn.execute("SELECT id FROM signals WHERE message_id = ?", (message_id,))
                        row = cursor.fetchone()
                        if row:
                            signal_id = row[0]
                        else:
                            return jsonify({'error': f'No signal found for message_id {message_id}'}), 404
                    
                    if not signal_id:
                        return jsonify({'error': 'signal_id or message_id is required'}), 400
                    
                    # Verify signal_id exists - with fallback to message_id if signal_id is wrong
                    cursor = conn.execute("SELECT id FROM signals WHERE id = ?", (signal_id,))
                    signal_exists = cursor.fetchone()
                    
                    if not signal_exists:
                        # If signal_id verification failed and we have message_id, try fallback
                        if message_id and original_signal_id:  # signal_id was provided but wrong
                            logger.info(f"Signal ID '{original_signal_id}' not found, trying fallback with message_id {message_id}")
                            fallback_cursor = conn.execute("SELECT id FROM signals WHERE message_id = ?", (message_id,))
                            fallback_row = fallback_cursor.fetchone()
                            if fallback_row:
                                signal_id = fallback_row[0]  # Use the correct signal_id from message_id lookup
                                logger.info(f"Fallback successful: wrong signal_id '{original_signal_id}' → correct signal_id '{signal_id}' via message_id {message_id}")
                            else:
                                logger.warning(f"Fallback failed: no signal found for message_id {message_id}")
                                return jsonify({'error': f'Signal not found: {original_signal_id} (fallback by message_id {message_id} also failed)'}), 404
                        else:
                            return jsonify({'error': f'Signal not found: {signal_id}'}), 404
                    
                    # Store the event
                    conn.execute("""
                        INSERT INTO trade_events (signal_id, event_type, event_data)
                        VALUES (?, ?, ?)
                    """, (signal_id, event_type, json.dumps(event_data)))
                    
                    # Update signal status based on event type
                    if event_type == 'order_placed':
                        new_status = 'active'
                    elif event_type in ['tp3_hit', 'sl_hit', 'manual_close']:
                        new_status = 'completed'
                    elif event_type == 'error':
                        new_status = 'failed'
                    else:
                        new_status = None
                    
                    if new_status:
                        conn.execute("""
                            UPDATE signals 
                            SET status = ?, updated_at = CURRENT_TIMESTAMP 
                            WHERE id = ?
                        """, (new_status, signal_id))
                    
                    conn.commit()
                
                logger.info(f"Event recorded: {event_type} for signal {signal_id}")
                return jsonify({'status': 'success'})
                
            except Exception as e:
                logger.error(f"Error reporting event: {e}")
                return jsonify({'error': str(e)}), 500
        
        @self.app.route('/get_signal_state/<int:message_id>', methods=['GET'])
        def get_signal_state(message_id):
            """Get signal state for EA recovery with current state calculation"""
            logger.info(f"=== DEBUG: EA Recovery Request Received ===")
            logger.info(f"Requested message_id: {message_id}")
            logger.info(f"Request URL: {request.url}")
            logger.info(f"Request method: {request.method}")
            
            try:
                with sqlite3.connect(self.db_path) as conn:
                    # Get signal details
                    logger.info(f"Querying database for message_id: {message_id}")
                    cursor = conn.execute("""
                        SELECT id, symbol, action, entry_price, stop_loss, tp1, tp2, tp3, status
                        FROM signals 
                        WHERE message_id = ?
                    """, (message_id,))
                    
                    row = cursor.fetchone()
                    logger.info(f"Database query result: {row}")
                    
                    if not row:
                        logger.warning(f"No signal found for message_id: {message_id}")
                        # Let's also check what signals DO exist in the database
                        all_cursor = conn.execute("SELECT message_id, symbol, action, status FROM signals ORDER BY created_at DESC LIMIT 10")
                        all_signals = all_cursor.fetchall()
                        logger.info(f"Available signals in database: {all_signals}")
                        return jsonify({'error': 'Signal not found'}), 404
                    
                    # Store original values
                    signal_id = row[0]
                    original_entry = row[3]
                    original_sl = row[4]
                    original_tp1 = row[5]
                    original_tp2 = row[6]
                    original_tp3 = row[7]
                    
                    # Get all events for this signal in chronological order
                    cursor = conn.execute("""
                        SELECT event_type, event_data, timestamp
                        FROM trade_events 
                        WHERE signal_id = ?
                        ORDER BY timestamp ASC
                    """, (signal_id,))
                    
                    events = []
                    tp1_hit = False
                    tp2_hit = False
                    tp3_hit = False
                    current_sl = original_sl
                    
                    # Process events to determine current state
                    for event_row in cursor.fetchall():
                        event_type = event_row[0]
                        events.append({
                            'event_type': event_type,
                            'event_data': json.loads(event_row[1]) if event_row[1] else {},
                            'timestamp': event_row[2]
                        })
                        
                        # Track TP hits and SL updates
                        if event_type == 'tp1_hit':
                            tp1_hit = True
                            current_sl = original_entry  # Move SL to entry after TP1
                        elif event_type == 'tp2_hit':
                            tp2_hit = True
                            current_sl = original_tp1    # Move SL to TP1 after TP2
                        elif event_type == 'tp3_hit':
                            tp3_hit = True
                            # TP3 closes full position, so state doesn't matter
                    
                    # Calculate current TP levels (only those not hit yet)
                    current_tp1 = None if tp1_hit else original_tp1
                    current_tp2 = None if tp2_hit else original_tp2
                    current_tp3 = None if tp3_hit else original_tp3
                    
                    # Determine current status
                    if tp3_hit:
                        current_status = 'completed'
                    elif tp1_hit or tp2_hit:
                        current_status = 'active_partial'
                    else:
                        current_status = row[8]  # Original status
                    
                    # Return CURRENT state, not original
                    signal_data = {
                        'id': signal_id,
                        'message_id': message_id,
                        'symbol': row[1],
                        'action': row[2],
                        'entry_price': original_entry,
                        'stop_loss': current_sl,        # CURRENT SL (after trailing adjustments)
                        'tp1': current_tp1,             # Only if not hit yet
                        'tp2': current_tp2,             # Only if not hit yet  
                        'tp3': current_tp3,             # Only if not hit yet
                        'status': current_status,
                        'recovery_state': {
                            'tp1_hit': tp1_hit,
                            'tp2_hit': tp2_hit,
                            'tp3_hit': tp3_hit,
                            'original_sl': original_sl,
                            'original_tp1': original_tp1,
                            'original_tp2': original_tp2,
                            'original_tp3': original_tp3
                        },
                        'events': events
                    }
                    
                    logger.info(f"=== DEBUG: Sending response to EA ===")
                    logger.info(f"Signal found: {signal_data['symbol']} {signal_data['action']}")
                    logger.info(f"Response data: {json.dumps(signal_data, indent=2)}")
                    logger.info(f"Returned CURRENT signal state for message_id {message_id}")
                    logger.info(f"Recovery state: TP1={tp1_hit}, TP2={tp2_hit}, TP3={tp3_hit}, Current SL={current_sl}")
                    return jsonify(signal_data)
                    
            except Exception as e:
                logger.error(f"Error getting signal state: {e}")
                return jsonify({'error': str(e)}), 500
        
        @self.app.route('/add_signal', methods=['POST'])
        def add_signal():
            """Add new signal (called by Python listener)"""
            try:
                # Handle JSON parsing errors
                data = request.get_json()
                if not data:
                    return jsonify({'error': 'No JSON data provided'}), 400
            except Exception as e:
                return jsonify({'error': 'Invalid JSON format'}), 400
            
            try:
                # Validate required fields (tp2 and tp3 are now optional)
                required_fields = ['id', 'message_id', 'channel_id', 'symbol', 'action', 
                                 'entry_price', 'stop_loss', 'tp1', 'raw_message']
                
                for field in required_fields:
                    if field not in data:
                        return jsonify({'error': f'Missing required field: {field}'}), 400
                
                # Validate data types
                try:
                    float(data['entry_price'])
                    float(data['stop_loss'])
                    float(data['tp1'])
                    int(data['message_id'])
                    int(data['channel_id'])
                except (ValueError, TypeError):
                    return jsonify({'error': 'Invalid data types for numeric fields'}), 400
                
                # Validate optional fields
                tp2 = data.get('tp2')
                tp3 = data.get('tp3')
                
                if tp2 is not None:
                    try:
                        float(tp2)
                    except (ValueError, TypeError):
                        return jsonify({'error': 'Invalid data type for tp2'}), 400
                
                if tp3 is not None:
                    try:
                        float(tp3)
                    except (ValueError, TypeError):
                        return jsonify({'error': 'Invalid data type for tp3'}), 400
                
                # Validate action
                if data['action'] not in ['BUY', 'SELL']:
                    return jsonify({'error': 'Invalid action: must be BUY or SELL'}), 400
                
                with sqlite3.connect(self.db_path) as conn:
                    conn.execute("""
                        INSERT INTO signals 
                        (id, message_id, channel_id, symbol, action, entry_price, stop_loss, 
                         tp1, tp2, tp3, raw_message, status)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
                    """, (
                        data['id'], data['message_id'], data['channel_id'], data['symbol'],
                        data['action'], data['entry_price'], data['stop_loss'],
                        data['tp1'], tp2, tp3, data['raw_message']
                    ))
                    conn.commit()
                
                logger.info(f"New signal added: {data['symbol']} {data['action']} (ID: {data['id']})")
                return jsonify({'status': 'success', 'message': 'Signal added'})
                
            except sqlite3.IntegrityError as e:
                logger.error(f"Signal already exists: {e}")
                return jsonify({'error': 'Signal already exists'}), 409
            except Exception as e:
                logger.error(f"Error adding signal: {e}")
                return jsonify({'error': str(e)}), 500
        
        @self.app.route('/stats', methods=['GET'])
        def stats():
            """Get server statistics"""
            try:
                with sqlite3.connect(self.db_path) as conn:
                    cursor = conn.execute("""
                        SELECT 
                            COUNT(*) as total_signals,
                            SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
                            SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) as active,
                            SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
                            SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed
                        FROM signals
                    """)
                    
                    stats_row = cursor.fetchone()
                    
                    cursor = conn.execute("SELECT COUNT(*) FROM trade_events")
                    total_events = cursor.fetchone()[0]
                    
                    return jsonify({
                        'total_signals': stats_row[0],
                        'pending_signals': stats_row[1],
                        'active_signals': stats_row[2], 
                        'completed_signals': stats_row[3],
                        'failed_signals': stats_row[4],
                        'total_events': total_events,
                        'server_uptime': time.time() - self.start_time if hasattr(self, 'start_time') else 0
                    })
                    
            except Exception as e:
                logger.error(f"Error getting stats: {e}")
                return jsonify({'error': str(e)}), 500
    
    def start(self):
        """Start the web server"""
        self.start_time = time.time()
        self.running = True
        logger.info(f"Starting SimpleSignalServer on port {self.port}")
        self.app.run(host='0.0.0.0', port=self.port, debug=False)
    
    def stop(self):
        """Stop the web server"""
        self.running = False
        logger.info("SimpleSignalServer stopped")

def main():
    """Main entry point"""
    server = SimpleSignalServer()
    try:
        server.start()
    except KeyboardInterrupt:
        logger.info("Received interrupt signal")
        server.stop()

if __name__ == "__main__":
    main() 