"""
Configuration module for Telegram Signal Listener
Manages all settings, credentials, and configuration options
"""

import os
from typing import Optional, List
from dataclasses import dataclass

# Load environment variables from .env file
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    # python-dotenv is optional - if not installed, rely on system env vars
    pass

@dataclass
class Config:
    """Configuration class for the Telegram Signal Listener system"""
    
    # Telegram Bot API Configuration (for bot method)
    TELEGRAM_BOT_TOKEN: str = ""
    TELEGRAM_CHANNEL_ID: str = ""  # Can be channel username (@channel) or numeric ID
    
    # Telegram MTProto Configuration (for user account method)
    TELEGRAM_API_ID: str = ""
    TELEGRAM_API_HASH: str = ""
    TELEGRAM_PHONE_NUMBER: str = ""
    TELEGRAM_CHANNEL_USERNAME: str = ""  # For private channels, leave empty and use invite link
    TELEGRAM_CHANNEL_INVITE_LINK: str = ""  # Private channel invite link: https://t.me/+hashcode
    
    # Multi-Channel Configuration (NEW FEATURE)
    TELEGRAM_CHANNELS: str = ""  # Comma-separated: "SignalTest,TakeProfitEXECUTIVE"
    TELEGRAM_INVITE_LINKS: str = ""  # Comma-separated invite links for private channels
    
    TELEGRAM_SESSION_STRING: str = ""  # Optional: save session to avoid re-auth
    
    # MT4 Configuration (LEGACY - only used by test files)
    # Production uses web server architecture (port 8000)
    MT4_COMMUNICATION_METHOD: str = "http"  # HTTP-only clean implementation
    MT4_HTTP_HOST: str = "localhost"        # Host for HTTP communication
    MT4_HTTP_PORT: int = 8888               # Port for legacy socket communication (test files only)
    MT4_HTTP_TIMEOUT: int = 5               # HTTP request timeout in seconds
    
    # Trading Configuration
    DEFAULT_RISK_PERCENT: float = 1.0  # Default risk per trade as % of account
    DEFAULT_LOT_SIZE: float = 0.1       # Default lot size for trades
    MAX_CONCURRENT_TRADES: int = 5
    ENABLE_TRADE_FILTERS: bool = True
    
    # Magic Number Configuration (must match EA settings)
    BASE_MAGIC_NUMBER: int = 77777     # Base magic number for signal identification
    MAGIC_INCREMENT: int = 1000        # Increment between signals (must match EA)
    
    # Logging Configuration
    LOG_LEVEL: str = "INFO"
    LOG_FILE: str = "telegram_signals.log"
    DEBUG_STATISTICS: bool = False  # Enable 5-minute statistics logging
    
    # File Communication Settings (if using file method)
    SIGNALS_DIRECTORY: str = "signals"
    PROCESSED_SIGNALS_DIRECTORY: str = "processed_signals"
    
    # Risk Management
    MIN_RISK_REWARD_RATIO: float = 1.0  # Minimum RR ratio to accept signal
    MAX_SPREAD_PIPS: float = 3.0  # Maximum spread to allow trade
    
    def __init__(self):
        """Initialize configuration from environment variables or defaults"""
        self.load_from_environment()
        self.validate_config()
    
    def load_from_environment(self) -> None:
        """Load configuration from environment variables"""
        # Telegram Bot API settings
        self.TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', self.TELEGRAM_BOT_TOKEN)
        self.TELEGRAM_CHANNEL_ID = os.getenv('TELEGRAM_CHANNEL_ID', self.TELEGRAM_CHANNEL_ID)
        
        # Telegram MTProto settings
        self.TELEGRAM_API_ID = os.getenv('TELEGRAM_API_ID', self.TELEGRAM_API_ID)
        self.TELEGRAM_API_HASH = os.getenv('TELEGRAM_API_HASH', self.TELEGRAM_API_HASH)
        self.TELEGRAM_PHONE_NUMBER = os.getenv('TELEGRAM_PHONE_NUMBER', self.TELEGRAM_PHONE_NUMBER)
        self.TELEGRAM_CHANNEL_USERNAME = os.getenv('TELEGRAM_CHANNEL_USERNAME', self.TELEGRAM_CHANNEL_USERNAME)
        self.TELEGRAM_CHANNEL_INVITE_LINK = os.getenv('TELEGRAM_CHANNEL_INVITE_LINK', self.TELEGRAM_CHANNEL_INVITE_LINK)
        
        # Multi-channel support (NEW)
        self.TELEGRAM_CHANNELS = os.getenv('TELEGRAM_CHANNELS', self.TELEGRAM_CHANNELS)
        self.TELEGRAM_INVITE_LINKS = os.getenv('TELEGRAM_INVITE_LINKS', self.TELEGRAM_INVITE_LINKS)
        
        self.TELEGRAM_SESSION_STRING = os.getenv('TELEGRAM_SESSION_STRING', self.TELEGRAM_SESSION_STRING)
        
        # MT4 settings (HTTP only)
        self.MT4_COMMUNICATION_METHOD = os.getenv('MT4_COMMUNICATION_METHOD', self.MT4_COMMUNICATION_METHOD)
        self.MT4_HTTP_HOST = os.getenv('MT4_HTTP_HOST', self.MT4_HTTP_HOST)
        self.MT4_HTTP_PORT = int(os.getenv('MT4_HTTP_PORT', self.MT4_HTTP_PORT))
        self.MT4_HTTP_TIMEOUT = int(os.getenv('MT4_HTTP_TIMEOUT', self.MT4_HTTP_TIMEOUT))
        
        # Trading settings
        self.DEFAULT_RISK_PERCENT = float(os.getenv('DEFAULT_RISK_PERCENT', self.DEFAULT_RISK_PERCENT))
        self.DEFAULT_LOT_SIZE = float(os.getenv('DEFAULT_LOT_SIZE', self.DEFAULT_LOT_SIZE))
        self.MAX_CONCURRENT_TRADES = int(os.getenv('MAX_CONCURRENT_TRADES', self.MAX_CONCURRENT_TRADES))
        self.ENABLE_TRADE_FILTERS = os.getenv('ENABLE_TRADE_FILTERS', 'true').lower() == 'true'
        
        # Magic number settings
        self.BASE_MAGIC_NUMBER = int(os.getenv('BASE_MAGIC_NUMBER', self.BASE_MAGIC_NUMBER))
        self.MAGIC_INCREMENT = int(os.getenv('MAGIC_INCREMENT', self.MAGIC_INCREMENT))
        
        # Logging settings
        self.LOG_LEVEL = os.getenv('LOG_LEVEL', self.LOG_LEVEL)
        self.LOG_FILE = os.getenv('LOG_FILE', self.LOG_FILE)
        self.DEBUG_STATISTICS = os.getenv('DEBUG_STATISTICS', str(self.DEBUG_STATISTICS)).lower() in ('true', '1', 'yes')
        
        # File communication settings
        self.SIGNALS_DIRECTORY = os.getenv('SIGNALS_DIRECTORY', self.SIGNALS_DIRECTORY)
        self.PROCESSED_SIGNALS_DIRECTORY = os.getenv('PROCESSED_SIGNALS_DIRECTORY', self.PROCESSED_SIGNALS_DIRECTORY)
        
        # Risk management
        self.MIN_RISK_REWARD_RATIO = float(os.getenv('MIN_RISK_REWARD_RATIO', self.MIN_RISK_REWARD_RATIO))
        self.MAX_SPREAD_PIPS = float(os.getenv('MAX_SPREAD_PIPS', self.MAX_SPREAD_PIPS))
    
    def validate_config(self) -> None:
        """Validate configuration and raise errors for invalid settings"""
        errors = []
        
        # Validate Telegram settings - either Bot API or MTProto required
        has_bot_config = bool(self.TELEGRAM_BOT_TOKEN and self.TELEGRAM_CHANNEL_ID)
        has_mtproto_config = bool(self.TELEGRAM_API_ID and self.TELEGRAM_API_HASH and self.TELEGRAM_PHONE_NUMBER)
        
        if not has_bot_config and not has_mtproto_config:
            errors.append("Either Bot API credentials (TELEGRAM_BOT_TOKEN + TELEGRAM_CHANNEL_ID) or MTProto credentials (TELEGRAM_API_ID + TELEGRAM_API_HASH + TELEGRAM_PHONE_NUMBER) are required")
        
        # Validate MT4 settings (HTTP only)
        if self.MT4_COMMUNICATION_METHOD != 'http':
            errors.append("MT4_COMMUNICATION_METHOD must be 'http' (only HTTP supported)")
        
        if not (1 <= self.MT4_HTTP_PORT <= 65535):
            errors.append("MT4_HTTP_PORT must be between 1 and 65535")
        
        if self.MT4_HTTP_TIMEOUT <= 0:
            errors.append("MT4_HTTP_TIMEOUT must be greater than 0")
        
        # Validate trading settings
        if self.DEFAULT_RISK_PERCENT <= 0 or self.DEFAULT_RISK_PERCENT > 10:
            errors.append("DEFAULT_RISK_PERCENT must be between 0 and 10")
        
        if self.DEFAULT_LOT_SIZE <= 0 or self.DEFAULT_LOT_SIZE > 100:
            errors.append("DEFAULT_LOT_SIZE must be between 0 and 100")
        
        if self.MAX_CONCURRENT_TRADES <= 0:
            errors.append("MAX_CONCURRENT_TRADES must be greater than 0")
        
        if self.MIN_RISK_REWARD_RATIO <= 0:
            errors.append("MIN_RISK_REWARD_RATIO must be greater than 0")
        
        if errors:
            raise ValueError("Configuration errors:\n" + "\n".join(f"- {error}" for error in errors))
    
    def to_dict(self) -> dict:
        """Convert configuration to dictionary"""
        return {
            'telegram': {
                'bot_token': '***' if self.TELEGRAM_BOT_TOKEN else '',
                'channel_id': self.TELEGRAM_CHANNEL_ID
            },
            'mt4': {
                'communication_method': self.MT4_COMMUNICATION_METHOD,
                'http_host': self.MT4_HTTP_HOST,
                'http_port': self.MT4_HTTP_PORT,
                'http_timeout': self.MT4_HTTP_TIMEOUT
            },
            'trading': {
                'default_risk_percent': self.DEFAULT_RISK_PERCENT,
                'default_lot_size': self.DEFAULT_LOT_SIZE,
                'max_concurrent_trades': self.MAX_CONCURRENT_TRADES,
                'enable_trade_filters': self.ENABLE_TRADE_FILTERS,
                'min_risk_reward_ratio': self.MIN_RISK_REWARD_RATIO,
                'max_spread_pips': self.MAX_SPREAD_PIPS,
                'base_magic_number': self.BASE_MAGIC_NUMBER,
                'magic_increment': self.MAGIC_INCREMENT
            },
            'logging': {
                'log_level': self.LOG_LEVEL,
                'log_file': self.LOG_FILE
            }
        }
    
    def print_config(self) -> None:
        """Print current configuration (hiding sensitive data)"""
        import json
        print("Current Configuration:")
        print(json.dumps(self.to_dict(), indent=2))
    
    def get_channel_list(self) -> List[str]:
        """Get list of channels to monitor"""
        channels = []
        
        # Multi-channel configuration (priority)
        if self.TELEGRAM_CHANNELS:
            channels.extend([ch.strip() for ch in self.TELEGRAM_CHANNELS.split(',') if ch.strip()])
        elif self.TELEGRAM_INVITE_LINKS:
            channels.extend([link.strip() for link in self.TELEGRAM_INVITE_LINKS.split(',') if link.strip()])
        # Fallback to single channel (backwards compatible)
        elif self.TELEGRAM_CHANNEL_USERNAME:
            channels.append(self.TELEGRAM_CHANNEL_USERNAME)
        elif self.TELEGRAM_CHANNEL_INVITE_LINK:
            channels.append(self.TELEGRAM_CHANNEL_INVITE_LINK)
            
        return channels

# Create a sample .env file for easy configuration
ENV_TEMPLATE = """# Telegram Configuration
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHANNEL_ID=@your_channel_or_numeric_id

# Telegram MTProto Configuration (for user account method)
TELEGRAM_API_ID=your_api_id_here
TELEGRAM_API_HASH=your_api_hash_here
TELEGRAM_PHONE_NUMBER=your_phone_number_here
TELEGRAM_CHANNEL_USERNAME=
TELEGRAM_CHANNEL_INVITE_LINK=https://t.me/+your_invite_hash

# Multi-Channel Configuration (NEW)
TELEGRAM_CHANNELS=SignalTest,TakeProfitEXECUTIVE
TELEGRAM_INVITE_LINKS=

TELEGRAM_SESSION_STRING=

# MT4 Configuration (LEGACY - only used by test files)
# Production uses web server architecture (port 8000)
MT4_COMMUNICATION_METHOD=http
MT4_HTTP_HOST=localhost
MT4_HTTP_PORT=8888
MT4_HTTP_TIMEOUT=5

# Trading Configuration
DEFAULT_RISK_PERCENT=1.0
DEFAULT_LOT_SIZE=0.1
MAX_CONCURRENT_TRADES=5
ENABLE_TRADE_FILTERS=true
MIN_RISK_REWARD_RATIO=1.0
MAX_SPREAD_PIPS=3.0

# Magic Number Configuration (must match EA settings)
BASE_MAGIC_NUMBER=77777
MAGIC_INCREMENT=1000

# Logging Configuration
LOG_LEVEL=INFO
LOG_FILE=telegram_signals.log
DEBUG_STATISTICS=false

# File Communication Settings
SIGNALS_DIRECTORY=signals
PROCESSED_SIGNALS_DIRECTORY=processed_signals
"""

def create_env_file(filename: str = ".env") -> None:
    """Create a sample .env file with configuration template"""
    if not os.path.exists(filename):
        with open(filename, 'w') as f:
            f.write(ENV_TEMPLATE)
        print(f"Created {filename} file. Please edit it with your actual configuration.")
    else:
        print(f"{filename} already exists. Not overwriting.")

# For testing configuration
def test_config():
    """Test configuration loading and validation"""
    try:
        config = Config()
        print("[OK] Configuration loaded successfully")
        config.print_config()
        return True
    except ValueError as e:
        print(f"[ERROR] Configuration validation failed: {e}")
        return False

if __name__ == "__main__":
    # Create sample .env file
    create_env_file()
    
    # Test configuration
    test_config() 