#!/usr/bin/env python3
"""
Simplified Signal Parser
Only handles new limit order signals - ignores replies and market orders
"""

import re
import logging
from dataclasses import dataclass
from enum import Enum
from typing import Optional, Dict, Any
import openai
import os
from dotenv import load_dotenv
from windows_logging import safe_print

# Load environment variables
load_dotenv()

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class SignalAction(Enum):
    """Trading signal actions"""
    BUY = "BUY"
    SELL = "SELL"

@dataclass
class TradingSignal:
    """Simplified trading signal data - supports 1-3 take profit levels"""
    pair: str
    action: SignalAction
    entry_price: float
    stop_loss: float
    take_profit_1: float
    take_profit_2: Optional[float] = None  # Now optional
    take_profit_3: Optional[float] = None  # Now optional
    raw_text: str = ""
    
    def get_take_profits(self) -> list:
        """Get all non-None take profit levels"""
        tps = [self.take_profit_1]
        if self.take_profit_2 is not None:
            tps.append(self.take_profit_2)
        if self.take_profit_3 is not None:
            tps.append(self.take_profit_3)
        return tps
    
    def is_valid(self) -> bool:
        """Validate signal has all required fields and proper price levels"""
        import logging
        logger = logging.getLogger(__name__)
        
        # Check required fields (TP1 is required, TP2/TP3 are optional)
        required_check = all([self.pair, self.action, self.entry_price, self.stop_loss, self.take_profit_1])
        if not required_check:
            logger.info(f"❌ Validation failed: Missing required fields - pair:{self.pair}, action:{self.action}, entry:{self.entry_price}, sl:{self.stop_loss}, tp1:{self.take_profit_1}")
            return False
        
        # Get valid take profits (non-None values)
        take_profits = self.get_take_profits()
        
        # Validate price relationships
        if self.action == SignalAction.BUY:
            # For BUY: SL < Entry < TP1 < TP2 < TP3 (if they exist)
            if not (self.stop_loss < self.entry_price < self.take_profit_1):
                logger.info(f"❌ BUY validation failed: Price order should be SL < Entry < TP1. Got SL:{self.stop_loss}, Entry:{self.entry_price}, TP1:{self.take_profit_1}")
                return False
            
            # Check additional TPs are in ascending order
            for i in range(len(take_profits) - 1):
                if take_profits[i] >= take_profits[i + 1]:
                    logger.info(f"❌ BUY validation failed: TPs not in ascending order - TP{i+1}:{take_profits[i]} >= TP{i+2}:{take_profits[i + 1]}")
                    return False
                    
        else:  # SELL
            # For SELL: TP3 < TP2 < TP1 < Entry < SL (if they exist)
            if not (self.take_profit_1 < self.entry_price < self.stop_loss):
                logger.info(f"❌ SELL validation failed: Price order should be TP1 < Entry < SL. Got TP1:{self.take_profit_1}, Entry:{self.entry_price}, SL:{self.stop_loss}")
                return False
            
            # Check additional TPs are in descending order
            for i in range(len(take_profits) - 1):
                if take_profits[i] <= take_profits[i + 1]:
                    logger.info(f"❌ SELL validation failed: TPs not in descending order - TP{i+1}:{take_profits[i]} <= TP{i+2}:{take_profits[i + 1]}")
                    return False
        
        logger.info(f"✅ Signal validation passed!")            
        return True

class SimplifiedSignalParser:
    """Simplified parser for limit order signals only"""
    
    def __init__(self):
        # Setup OpenAI if API key is available
        self.openai_client = None
        if os.getenv('OPENAI_API_KEY'):
            openai.api_key = os.getenv('OPENAI_API_KEY')
            self.openai_client = openai
            logger.info("OpenAI API configured for signal validation")
        else:
            logger.warning("No OpenAI API key found - using regex parsing only")
        
        # Compile regex patterns
        self._compile_patterns()
        
    def _compile_patterns(self):
        """Compile regex patterns for signal detection"""
        # Currency pair pattern (e.g., EURUSD, GBPJPY)
        self.pair_pattern = re.compile(r'\b([A-Z]{6})\b')
        
        # Enhanced action pattern - handles multiple formats
        self.action_pattern = re.compile(r'\b(BUY|SELL)\s+LIMIT(?:\s+ORDER)?\b|\blimit\s+order\b', re.IGNORECASE)
        
        # Emoji patterns for action detection
        self.buy_emoji_pattern = re.compile(r'🟢')  # Green circle = BUY
        self.sell_emoji_pattern = re.compile(r'🔴')  # Red circle = SELL
        
        # Enhanced price patterns - more flexible formats including "Order:" and "Limit Order:"
        self.entry_pattern = re.compile(r'(?:ENTRY|PRICE|Entry|ORDER|Limit\s+Order)[\s:@]*([0-9]+\.?[0-9]*)|@\s*([0-9]+\.?[0-9]*)', re.IGNORECASE)
        self.sl_pattern = re.compile(r'(?:SL|STOP\s*LOSS|Stop-loss|Stop\s+Loss)[\s:@]*([0-9]+\.?[0-9]*)', re.IGNORECASE)
        
        # Flexible TP patterns - handles numbered TPs including "Target Profit"
        self.tp_numbered_pattern = re.compile(r'(?:TP|TAKE\s*PROFIT|TARGET\s*PROFIT)[\s]*([1-3])[\s:@]*([0-9]+\.?[0-9]*)', re.IGNORECASE)
        self.tp_simple_pattern = re.compile(r'(?:Take-profit|TAKE\s*PROFIT|TARGET\s*PROFIT)[\s:@]*([0-9]+\.?[0-9]*)', re.IGNORECASE)
        
        # Pattern to detect if this is a reply or follow-up message
        # Exclude "profit" when it's part of "take-profit" or "take profit"
        self.reply_indicators = re.compile(r'\b(?:close|hit|move|partial)\b|(?<!\btake[- ])\bprofit\b|\b(?:sl|tp)\s+(?:hit|move|to)\b', re.IGNORECASE)
        
    def is_new_signal(self, text: str, is_reply: bool = False) -> bool:
        """Check if this is a new signal (not a reply or follow-up)"""
        # If it's explicitly marked as a reply, ignore it
        if is_reply:
            return False
        
        # Check for limit order pattern OR emoji indicators
        has_limit_order = self.action_pattern.search(text)
        has_emoji_action = self.buy_emoji_pattern.search(text) or self.sell_emoji_pattern.search(text)
        
        if not (has_limit_order or has_emoji_action):
            return False
        
        # Check if it contains reply indicators (close, hit, etc.)
        if self.reply_indicators.search(text):
            return False
        
        # Must contain currency pair
        if not self.pair_pattern.search(text):
            return False
        
        # Must have entry price and stop loss
        if not (self.entry_pattern.search(text) and self.sl_pattern.search(text)):
            return False
        
        # Must have at least one take profit
        has_tp = (self.tp_numbered_pattern.search(text) or self.tp_simple_pattern.search(text))
        if not has_tp:
            return False
        
        return True
    
    def parse_signal_with_regex(self, text: str) -> Optional[TradingSignal]:
        """Parse signal using regex patterns - handles 1-3 TP levels"""
        try:
            # Extract currency pair
            pair_match = self.pair_pattern.search(text)
            if not pair_match:
                return None
            pair = pair_match.group(1)
            
            # Extract action - check emojis first, then explicit BUY/SELL
            action = None
            if self.buy_emoji_pattern.search(text):
                action = SignalAction.BUY
            elif self.sell_emoji_pattern.search(text):
                action = SignalAction.SELL
            else:
                # Try explicit BUY/SELL pattern
                action_match = self.action_pattern.search(text)
                if action_match and action_match.group(1):
                    action = SignalAction(action_match.group(1).upper())
            
            if not action:
                return None
            
            # Extract entry price (handle both capture groups)
            entry_match = self.entry_pattern.search(text)
            if not entry_match:
                return None
            entry_price = float(entry_match.group(1) if entry_match.group(1) else entry_match.group(2))
            
            # Extract stop loss
            sl_match = self.sl_pattern.search(text)
            if not sl_match:
                return None
            stop_loss = float(sl_match.group(1))
            
            # Extract take profits - handle both numbered and simple formats
            tp1, tp2, tp3 = None, None, None
            
            # Try numbered TP format first (TP1, TP2, TP3)
            tp_numbered_matches = self.tp_numbered_pattern.findall(text)
            if tp_numbered_matches:
                tp_dict = {int(level): float(price) for level, price in tp_numbered_matches}
                tp1 = tp_dict.get(1)
                tp2 = tp_dict.get(2)
                tp3 = tp_dict.get(3)
            else:
                # Try simple TP format (single "Take-profit")
                tp_simple_match = self.tp_simple_pattern.search(text)
                if tp_simple_match:
                    tp1 = float(tp_simple_match.group(1))
            
            # Must have at least TP1
            if tp1 is None:
                return None
            
            signal = TradingSignal(
                pair=pair,
                action=action,
                entry_price=entry_price,
                stop_loss=stop_loss,
                take_profit_1=tp1,
                take_profit_2=tp2,
                take_profit_3=tp3,
                raw_text=text
            )
            
            return signal if signal.is_valid() else None
            
        except (ValueError, KeyError) as e:
            logger.debug(f"Regex parsing failed: {e}")
            return None
    
    def validate_with_openai(self, text: str) -> Optional[Dict[str, Any]]:
        """Validate and extract signal using OpenAI"""
        if not self.openai_client:
            return None
        
        prompt = f"""
You are a forex trading signal parser. Extract ONLY new limit order signals.

FOCUS ON TEXT CONTENT ONLY - IGNORE ANY EMOJIS OR COLOR INDICATORS.

IGNORE any messages that are:
- Replies or follow-up messages
- Market orders 
- Close instructions
- TP hit notifications
- SL move instructions

SUPPORTED SIGNAL FORMATS:
1. Traditional: "BUY LIMIT EURUSD @ 1.0850, SL: 1.0800, TP1: 1.0900, TP2: 1.0950, TP3: 1.1000"
2. Formatted signals: "Buy Limit Order: 1.16050, Target Profit 1: 1.16350, Stop Loss: 1.15750"

PARSING RULES:
- Look for explicit "Buy" or "Sell" text to determine action
- "Buy Limit Order" = BUY action
- "Sell Limit Order" = SELL action
- Ignore any emoji or color indicators completely

FLEXIBLE TP LEVELS:
- Signals may have 1, 2, or 3 take-profit levels
- tp2 and tp3 should be null if not provided
- Always include at least tp1

For VALID limit order signals, extract this JSON format:
{{
    "is_valid_signal": true,
    "pair": "GBPJPY",
    "action": "SELL",
    "entry_price": 199.231,
    "stop_loss": 199.558,
    "tp1": 198.736,
    "tp2": null,
    "tp3": null
}}

EXAMPLES:

Example 1 (Single TP):
Input: "GBPJPY Sell Limit Order: 199.231 Take-profit: 198.736 Stop-loss: 199.558"
Output: {{"is_valid_signal": true, "pair": "GBPJPY", "action": "SELL", "entry_price": 199.231, "stop_loss": 199.558, "tp1": 198.736, "tp2": null, "tp3": null}}

Example 2 (Multiple TPs):
Input: "EURUSD BUY LIMIT 1.0850 SL: 1.0800 TP1: 1.0900 TP2: 1.0950"
Output: {{"is_valid_signal": true, "pair": "EURUSD", "action": "BUY", "entry_price": 1.0850, "stop_loss": 1.0800, "tp1": 1.0900, "tp2": 1.0950, "tp3": null}}

Example 3 (Your format):
Input: "#signals EURUSD Buy Limit Order: 1.16050 Target Profit 1: 1.16350 Target Profit 2: 1.16650 Target Profit 3: 1.16950 Stop Loss: 1.15750"
Output: {{"is_valid_signal": true, "pair": "EURUSD", "action": "BUY", "entry_price": 1.16050, "stop_loss": 1.15750, "tp1": 1.16350, "tp2": 1.16650, "tp3": 1.16950}}

For invalid messages, return: {{"is_valid_signal": false}}

Message to analyze:
{text}
"""
        
        try:
            # VERBOSE LOGGING: OpenAI request
            logger.info("=" * 80)
            logger.info(f"🤖 OPENAI API REQUEST")
            logger.info("=" * 80)
            logger.info(f"🌐 Model: gpt-3.5-turbo")
            logger.info(f"🌡️ Temperature: 0.1")
            logger.info(f"📏 Max Tokens: 200")
            logger.info(f"📝 Prompt Length: {len(prompt)} characters")
            logger.info(f"📋 Full Prompt:")
            logger.info(f"┌─ START PROMPT ─┐")
            for i, line in enumerate(prompt.split('\n'), 1):
                logger.info(f"│ {i:2}: {line}")
            logger.info(f"└─ END PROMPT ───┘")
            logger.info("=" * 80)
            
            response = self.openai_client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1,
                max_tokens=200
            )
            
            import json
            raw_content = response.choices[0].message.content
            
            # VERBOSE LOGGING: OpenAI response  
            logger.info("=" * 80)
            logger.info(f"🤖 OPENAI API RESPONSE")
            logger.info("=" * 80)
            logger.info(f"💰 Usage - Prompt: {response.usage.prompt_tokens} tokens")
            logger.info(f"💰 Usage - Completion: {response.usage.completion_tokens} tokens") 
            logger.info(f"💰 Usage - Total: {response.usage.total_tokens} tokens")
            logger.info(f"🎯 Finish Reason: {response.choices[0].finish_reason}")
            logger.info(f"📝 Raw Response:")
            logger.info(f"┌─ START RESPONSE ─┐")
            for i, line in enumerate(raw_content.split('\n'), 1):
                logger.info(f"│ {i:2}: {line}")
            logger.info(f"└─ END RESPONSE ───┘")
            logger.info("=" * 80)
            
            result = json.loads(raw_content)
            logger.info(f"🔍 Parsed JSON Result: {result}")
            
            if result.get('is_valid_signal'):
                logger.info("✅ OpenAI detected valid signal")
                return result
            else:
                logger.info("❌ OpenAI says not a valid signal")
                return None
            
        except Exception as e:
            logger.error(f"OpenAI validation failed: {e}")
            return None
    
    def parse_signal(self, text: str, is_reply: bool = False) -> Optional[TradingSignal]:
        """Main parsing method - tries OpenAI FIRST, falls back to regex"""
        
        # Skip if explicitly marked as reply
        if is_reply:
            logger.debug("Skipping message marked as reply")
            return None
        
        # Try OpenAI parsing FIRST (if available)
        if self.openai_client:
            logger.info("🤖 Trying OpenAI parsing first...")
            openai_result = self.validate_with_openai(text)
            if openai_result:
                try:
                    logger.info(f"🏗️ Creating TradingSignal from OpenAI result...")
                    signal = TradingSignal(
                        pair=openai_result['pair'],
                        action=SignalAction(openai_result['action']),
                        entry_price=float(openai_result['entry_price']),
                        stop_loss=float(openai_result['stop_loss']),
                        take_profit_1=float(openai_result['tp1']),
                        take_profit_2=float(openai_result['tp2']) if openai_result['tp2'] is not None else None,
                        take_profit_3=float(openai_result['tp3']) if openai_result['tp3'] is not None else None,
                        raw_text=text
                    )
                    
                    logger.info(f"🏗️ Signal created: {signal.pair} {signal.action.value} @ {signal.entry_price}")
                    logger.info(f"🏗️ SL: {signal.stop_loss}, TP1: {signal.take_profit_1}, TP2: {signal.take_profit_2}, TP3: {signal.take_profit_3}")
                    
                    if signal.is_valid():
                        logger.info(f"🤖 OpenAI parsed signal: {signal.pair} {signal.action.value} @ {signal.entry_price}")
                        return signal
                    else:
                        logger.info("❌ OpenAI result failed TradingSignal.is_valid() check")
                        
                except (KeyError, ValueError) as e:
                    logger.error(f"❌ OpenAI result parsing failed: {e}")
            else:
                logger.info("❌ OpenAI did not detect a valid signal")
        
        # Fall back to regex parsing (only if OpenAI failed or unavailable)
        logger.info("📝 Falling back to regex parsing...")
        
        # Only apply regex filter if OpenAI is not available or failed
        if not self.is_new_signal(text, is_reply):
            logger.info("❌ Regex filter: not a new signal")
            return None
        
        signal = self.parse_signal_with_regex(text)
        if signal:
            logger.info(f"📝 Regex parsed signal: {signal.pair} {signal.action.value} @ {signal.entry_price}")
        else:
            logger.info("❌ Regex parsing also failed")
        
        return signal

# Test the parser
if __name__ == "__main__":
    parser = SimplifiedSignalParser()
    
    # Test signals - including variable TP levels
    test_signals = [
        "BUY LIMIT EURUSD @ 1.0850\nSL: 1.0800\nTP1: 1.0900\nTP2: 1.0950\nTP3: 1.1000",
        "SELL LIMIT GBPUSD @ 1.2500\nSL: 1.2550\nTP1: 1.2450\nTP2: 1.2400\nTP3: 1.2350",
        "Placed a limit order on 🔴 GBPJPY\nEntry: 199.231\nTake-profit: 198.736\nStop-loss: 199.558",  # Single TP with emoji
        "🟢 EURUSD limit order\nEntry: 1.0850\nSL: 1.0800\nTP1: 1.0900\nTP2: 1.0950",  # Two TPs
        "Close half position at TP2",  # Should be ignored
        "BUY MARKET EURUSD",  # Should be ignored
        "TP1 hit, move SL to entry"  # Should be ignored
    ]
    
    for i, test_text in enumerate(test_signals, 1):
        print(f"\nTest {i}: {test_text[:50]}...")
        signal = parser.parse_signal(test_text)
        if signal:
            safe_print(f"✅ Parsed: {signal.pair} {signal.action.value} @ {signal.entry_price}", force_emoji_replacement=True)
        else:
            safe_print("❌ Not a valid signal (correctly filtered)", force_emoji_replacement=True) 