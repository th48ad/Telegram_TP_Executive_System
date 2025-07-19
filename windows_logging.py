#!/usr/bin/env python3
"""
Windows-safe logging utility for emoji handling
Ensures emojis are properly displayed on Windows systems
"""

import logging
import os
import sys
import signal
import atexit


class ImmediateFlushFileHandler(logging.FileHandler):
    """Custom FileHandler that flushes immediately after each log message"""
    
    def emit(self, record):
        """Emit a record and immediately flush to disk"""
        try:
            super().emit(record)
            self.flush()  # Force immediate flush to disk
        except Exception as e:
            self.handleError(record)


# Global list to track all file handlers for cleanup
_active_file_handlers = []


def _cleanup_handlers():
    """Cleanup function to flush and close all file handlers"""
    for handler in _active_file_handlers:
        try:
            handler.flush()
            handler.close()
        except:
            pass


def _signal_handler(signum, frame):
    """Signal handler for graceful shutdown"""
    print("\n[SIGNAL] Received interrupt signal, flushing logs...")
    _cleanup_handlers()
    sys.exit(0)


# Register cleanup functions
atexit.register(_cleanup_handlers)
signal.signal(signal.SIGINT, _signal_handler)  # Ctrl-C
if hasattr(signal, 'SIGTERM'):
    signal.signal(signal.SIGTERM, _signal_handler)  # Termination


class WindowsSafeFormatter(logging.Formatter):
    """Custom formatter that replaces emojis with text on Windows or when forced"""
    
    def __init__(self, *args, force_emoji_replacement=False, **kwargs):
        super().__init__(*args, **kwargs)
        self.force_emoji_replacement = force_emoji_replacement
        
        # Comprehensive emoji mapping
        self.emoji_map = {
            '🔴': '[RED]', 
            '🟢': '[GREEN]', 
            '📊': '[CHART]',
            '💰': '[MONEY]', 
            '⚠️': '[WARNING]', 
            '✅': '[CHECK]',
            '❌': '[X]', 
            '🚀': '[ROCKET]',
            '📡': '[SIGNAL]',
            '📱': '[PHONE]',
            '📁': '[FOLDER]',
            '📝': '[LOG]',
            '🌐': '[WEB]',
            '🎯': '[TARGET]',
            '🤖': '[AI]',
            '💡': '[TIP]',
            '🔍': '[MONITOR]',
            '📅': '[DATE]',
            '📩': '[MSG_IN]',
            '📨': '[MSG_PROCESS]',
            '🏗️': '[BUILD]',
            '⏭️': '[SKIP]',
            '🛑': '[STOP]',
            '🏁': '[FINISH]',
            '💬': '[CHAT]',
            '👂': '[LISTEN]',
            '📜': '[SCROLL]',
            '🔥': '[FIRE]',
            '💻': '[COMPUTER]',
            '🎪': '[EVENT]',
            '📍': '[LOCATION]',
            '⏰': '[TIME]',
            '📏': '[LENGTH]',
            '📊': '[STATS]',
            '🔍': '[ANALYZE]',
            '💱': '[CURRENCY]',
            '💰': '[PRICE]',
            '📤': '[SEND]',
            '🌐': '[URL]',
            '📋': '[DATA]',
            '📥': '[RECEIVE]',
            '⏱️': '[TIMER]',
            '🌡️': '[TEMP]',
            '💡': '[IDEA]',
            '🎯': '[RESULT]'
        }
    
    def format(self, record):
        try:
            msg = super().format(record)
            # Replace emojis on Windows OR when forced (for testing/compatibility)
            if os.name == 'nt' or self.force_emoji_replacement:
                for emoji, replacement in self.emoji_map.items():
                    msg = msg.replace(emoji, replacement)
            return msg
        except Exception:
            return "[UNICODE ERROR] Could not format message"


def setup_windows_safe_logging(logger_name: str, log_file: str = None, level: int = logging.INFO, 
                              force_emoji_replacement: bool = None):
    """
    Setup Windows-safe logging with emoji replacement
    
    Args:
        logger_name: Name of the logger
        log_file: Optional log file path
        level: Logging level
        force_emoji_replacement: Force emoji replacement regardless of OS (None = auto-detect)
    
    Returns:
        Configured logger
    """
    logger = logging.getLogger(logger_name)
    
    # Clear existing handlers to avoid duplicates
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
    
    # Auto-detect force_emoji_replacement if not specified
    if force_emoji_replacement is None:
        # Force emoji replacement if we detect we're likely to run on Windows
        # or if environment variable is set
        force_emoji_replacement = (
            os.name == 'nt' or 
            os.getenv('FORCE_EMOJI_REPLACEMENT', '').lower() in ('true', '1', 'yes')
        )
    
    # Create formatters with emoji handling
    detailed_formatter = WindowsSafeFormatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        force_emoji_replacement=force_emoji_replacement
    )
    
    simple_formatter = WindowsSafeFormatter(
        '%(asctime)s - %(levelname)s - %(message)s',
        force_emoji_replacement=force_emoji_replacement
    )
    
    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(simple_formatter)
    logger.addHandler(console_handler)
    
    # File handler if specified
    if log_file:
        try:
            # Use ImmediateFlushFileHandler for immediate disk writing
            file_handler = ImmediateFlushFileHandler(log_file, encoding='utf-8')
            file_handler.setFormatter(detailed_formatter)
            logger.addHandler(file_handler)
            
            # Register for cleanup on exit
            _active_file_handlers.append(file_handler)
            
            print(f"✅ Log file created: {log_file} (immediate flush enabled)")
        except Exception as e:
            print(f"❌ Warning: Could not create file handler for {log_file}: {e}")
    
    logger.setLevel(level)
    logger.propagate = False  # Prevent duplicate messages
    
    return logger


def force_flush_all_logs():
    """Force flush all active file handlers immediately"""
    flushed_count = 0
    for handler in _active_file_handlers:
        try:
            handler.flush()
            flushed_count += 1
        except:
            pass
    return flushed_count


def safe_print(message: str, force_emoji_replacement: bool = None):
    """
    Windows-safe print function that replaces emojis
    
    Args:
        message: Message to print
        force_emoji_replacement: Force emoji replacement regardless of OS (None = auto-detect)
    """
    # Auto-detect force_emoji_replacement if not specified
    if force_emoji_replacement is None:
        force_emoji_replacement = (
            os.name == 'nt' or 
            os.getenv('FORCE_EMOJI_REPLACEMENT', '').lower() in ('true', '1', 'yes')
        )
    
    if force_emoji_replacement:
        emoji_map = {
            '🔴': '[RED]', 
            '🟢': '[GREEN]', 
            '📊': '[CHART]',
            '💰': '[MONEY]', 
            '⚠️': '[WARNING]', 
            '✅': '[CHECK]',
            '❌': '[X]', 
            '🚀': '[ROCKET]',
            '📡': '[SIGNAL]',
            '📱': '[PHONE]',
            '📁': '[FOLDER]',
            '📝': '[LOG]',
            '🌐': '[WEB]',
            '🎯': '[TARGET]',
            '🤖': '[AI]',
            '💡': '[TIP]',
            '🔍': '[MONITOR]',
            '📅': '[DATE]'
        }
        for emoji, replacement in emoji_map.items():
            message = message.replace(emoji, replacement)
    
    print(message) 