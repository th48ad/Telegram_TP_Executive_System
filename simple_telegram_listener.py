#!/usr/bin/env python3
"""
Simplified Telegram Listener
Only processes new limit order signals - ignores replies and follow-ups
"""

import asyncio
import logging
import time
import uuid
from datetime import datetime
from telethon import TelegramClient, events, functions
from telethon.errors import UserAlreadyParticipantError, InviteHashExpiredError
import requests
import json
import re

from simple_signal_parser import SimplifiedSignalParser, TradingSignal
from config import Config
from windows_logging import setup_windows_safe_logging

# Setup Windows-safe logging with forced emoji replacement for Windows compatibility
logger = setup_windows_safe_logging(__name__, force_emoji_replacement=True)

class SimpleTelegramListener:
    """Simplified Telegram listener for new signals only"""
    
    def __init__(self, config: Config):
        self.config = config
        self.api_id = config.TELEGRAM_API_ID
        self.api_hash = config.TELEGRAM_API_HASH
        self.phone_number = config.TELEGRAM_PHONE_NUMBER
        
        # Multi-channel configuration (NEW)
        self.channel_list = config.get_channel_list()
        self.target_entities = []  # List of channel entities
        self.channel_info = {}     # Map entity_id -> channel_info
        
        # Backwards compatibility - single channel
        self.channel_username = getattr(config, 'TELEGRAM_CHANNEL_USERNAME', None)
        self.invite_link = getattr(config, 'TELEGRAM_CHANNEL_INVITE_LINK', None)
        self.target_entity = None  # Keep for backwards compatibility
        
        # Initialize parser and client
        self.signal_parser = SimplifiedSignalParser()
        self.client = None
        
        # Web server config
        self.web_server_url = f"http://localhost:{config.MT4_HTTP_PORT}"
        
        # Statistics
        self.start_time = time.time()
        self.messages_processed = 0
        self.signals_found = 0
        self.signals_sent = 0
        
        logger.info("SimpleTelegramListener initialized")
    
    async def initialize(self):
        """Initialize Telegram client and authenticate"""
        try:
            # Create client
            self.client = TelegramClient(
                'simple_telegram_session',
                self.api_id,
                self.api_hash,
                flood_sleep_threshold=60
            )
            
            # Connect and authenticate
            logger.info("=" * 50)
            logger.info("   TELEGRAM AUTHENTICATION")
            logger.info("=" * 50)
            logger.info("Connecting to Telegram servers...")
            await self.client.connect()
            
            if not await self.client.is_user_authorized():
                logger.info(f"Authenticating with phone: {self.phone_number}")
                await self.client.start(phone=self.phone_number)
                logger.info("✅ Authentication successful")
            else:
                logger.info("✅ Already authenticated (using existing session)")
            
            logger.info("=" * 50)
            
            # Connect to target channel
            if not await self._connect_to_channel():
                raise Exception("Failed to connect to target channel")
            
            return True
            
        except Exception as e:
            logger.error(f"Initialization failed: {e}")
            return False
    
    async def _connect_to_channel(self):
        """Connect to all configured channels (multi-channel support)"""
        try:
            if not self.channel_list:
                # Fallback to single channel for backwards compatibility
                if self.invite_link or self.channel_username:
                    return await self._connect_single_channel()
                else:
                    logger.error("No channels configured for monitoring")
                    return False
            
            # Multi-channel setup
            logger.info("=" * 50)
            logger.info("   MULTI-CHANNEL TELEGRAM CONNECTION")
            logger.info("=" * 50)
            logger.info(f"Channels to monitor: {len(self.channel_list)}")
            
            success_count = 0
            for i, channel in enumerate(self.channel_list, 1):
                logger.info(f"\n🔗 Connecting to channel {i}/{len(self.channel_list)}: {channel}")
                
                try:
                    entity = None
                    channel_type = ""
                    
                    # Handle invite links
                    if channel.startswith('https://t.me/+'):
                        hash_match = re.search(r't\.me/\+([a-zA-Z0-9_-]+)', channel)
                        if hash_match:
                            invite_hash = hash_match.group(1)
                            try:
                                from telethon.tl.functions.messages import ImportChatInviteRequest
                                result = await self.client(ImportChatInviteRequest(invite_hash))
                                entity = result.chats[0]
                                channel_type = "PRIVATE (Joined via invite)"
                            except UserAlreadyParticipantError:
                                channel_type = "PRIVATE (Already member)"
                                # Find the channel in dialogs by known IDs or names
                                logger.info(f"   Already member - looking for channel in dialogs...")
                                
                                # Get channel mappings from configuration
                                known_channels = self.config.get_channel_mappings()
                                
                                if invite_hash in known_channels:
                                    target_id = known_channels[invite_hash]['id']
                                    target_name = known_channels[invite_hash]['name']
                                    
                                    async for dialog in self.client.iter_dialogs():
                                        if dialog.entity.id == target_id:
                                            entity = dialog.entity
                                            logger.info(f"   ✅ Found channel by ID: {target_name}")
                                            break
                                else:
                                    # Fallback: try invite link matching (original method)
                                    async for dialog in self.client.iter_dialogs():
                                        if hasattr(dialog.entity, 'title') and not hasattr(dialog.entity, 'username'):
                                            try:
                                                from telethon.tl.functions.messages import ExportChatInviteRequest
                                                export = await self.client(ExportChatInviteRequest(dialog.entity))
                                                if hasattr(export, 'link') and invite_hash in export.link:
                                                    entity = dialog.entity
                                                    break
                                            except:
                                                continue
                            except Exception as e:
                                logger.error(f"❌ Failed to join via invite: {e}")
                                logger.error(f"   Invite hash: {invite_hash}")
                                logger.error(f"   Error type: {type(e).__name__}")
                    
                    # Handle public channels or usernames
                    else:
                        try:
                            entity = await self.client.get_entity(channel)
                            channel_type = "PUBLIC"
                        except Exception as e:
                            logger.error(f"❌ Failed to get entity for {channel}: {e}")
                            logger.error(f"   Error type: {type(e).__name__}")
                            continue
                    
                    if entity:
                        self.target_entities.append(entity)
                        self.channel_info[entity.id] = {
                            'name': getattr(entity, 'title', channel),
                            'type': channel_type,
                            'username': channel,
                            'participants': getattr(entity, 'participants_count', 'Unknown')
                        }
                        
                        logger.info(f"✅ Connected: {entity.title} (ID: {entity.id})")
                        success_count += 1
                    else:
                        logger.error(f"❌ Failed to connect to: {channel}")
                        logger.error(f"   Reason: No entity returned from connection attempt")
                        
                except Exception as e:
                    logger.error(f"❌ Error connecting to {channel}: {e}")
                    logger.error(f"   Error type: {type(e).__name__}")
            
            # Set first entity as primary for backwards compatibility
            if self.target_entities:
                self.target_entity = self.target_entities[0]
            
            logger.info("=" * 50)
            logger.info(f"✅ Connected to {success_count}/{len(self.channel_list)} channels")
            logger.info("=" * 50)
            
            return success_count > 0
            
        except Exception as e:
            logger.error(f"Error in multi-channel connection: {e}")
            return False

    async def _connect_single_channel(self):
        """Fallback method for single channel connection (backwards compatibility)"""
        try:
            # Try invite link first (for private channels)
            if self.invite_link:
                # Extract hash from invite link
                hash_match = re.search(r't\.me/\+([a-zA-Z0-9_-]+)', self.invite_link)
                if hash_match:
                    try:
                        from telethon.tl.functions.messages import ImportChatInviteRequest
                        invite_hash = hash_match.group(1)
                        
                        result = await self.client(ImportChatInviteRequest(invite_hash))
                        self.target_entity = result.chats[0]
                        
                        logger.info("=" * 50)
                        logger.info("   SINGLE CHANNEL CONNECTION (FALLBACK)")
                        logger.info("=" * 50)
                        logger.info(f"Channel Type: PRIVATE")
                        logger.info(f"Channel Name: {self.target_entity.title}")
                        logger.info(f"Channel ID: {self.target_entity.id}")
                        logger.info("=" * 50)
                        return True
                        
                    except UserAlreadyParticipantError:
                        # Find in dialogs
                        async for dialog in self.client.iter_dialogs():
                            if hasattr(dialog.entity, 'title') and not hasattr(dialog.entity, 'username'):
                                self.target_entity = dialog.entity
                                logger.info("=" * 50)
                                logger.info("   SINGLE CHANNEL CONNECTION (FALLBACK)")
                                logger.info("=" * 50)
                                logger.info(f"Channel Type: PRIVATE (Already Member)")
                                logger.info(f"Channel Name: {self.target_entity.title}")
                                logger.info("=" * 50)
                                return True
            
            # Try public channel
            if self.channel_username:
                self.target_entity = await self.client.get_entity(self.channel_username)
                logger.info("=" * 50)
                logger.info("   SINGLE CHANNEL CONNECTION (FALLBACK)")
                logger.info("=" * 50)
                logger.info(f"Channel Type: PUBLIC")
                logger.info(f"Channel Name: {self.target_entity.title}")
                logger.info("=" * 50)
                return True
            
            logger.error("No valid single channel configuration found")
            return False
            
        except Exception as e:
            logger.error(f"Single channel connection failed: {e}")
            return False
    
    async def _process_message(self, event):
        """Process incoming message for signals"""
        try:
            message = event.message
            text = message.text or ""
            message_id = message.id
            channel_id = event.chat_id
            
            # Get channel info for logging (MULTI-CHANNEL ENHANCEMENT)
            channel_name = "Unknown Channel"
            if hasattr(event, 'chat') and event.chat:
                channel_name = getattr(event.chat, 'title', str(channel_id))
            elif channel_id in self.channel_info:
                channel_name = self.channel_info[channel_id]['name']
            
            # Log that we received a message with channel source
            logger.info(f"📩 Message received from {channel_name} (ID: {message_id})")
            
            # Skip empty messages
            if not text.strip():
                logger.info(f"⏭️ Skipping empty message {message_id}")
                return
            
            self.messages_processed += 1
            
            # VERBOSE LOGGING: Complete message details
            logger.info("=" * 80)
            logger.info(f"🔍 VERBOSE MESSAGE ANALYSIS - ID: {message_id}")
            logger.info("=" * 80)
            logger.info(f"📍 Channel ID: {channel_id}")
            logger.info(f"📱 Message ID: {message_id}")
            logger.info(f"⏰ Timestamp: {message.date}")
            logger.info(f"📝 Full Message Text:")
            logger.info(f"┌─ START MESSAGE ─┐")
            for i, line in enumerate(text.split('\n'), 1):
                logger.info(f"│ {i:2}: {line}")
            logger.info(f"└─ END MESSAGE ───┘")
            logger.info(f"📏 Text Length: {len(text)} characters")
            logger.info(f"📊 Line Count: {len(text.split(chr(10)))}")
            logger.info("=" * 80)
            
            # Check if this is a reply (ignore replies)
            is_reply = hasattr(message, 'reply_to') and message.reply_to is not None
            if is_reply:
                logger.info(f"⏭️ Ignoring reply message {message_id}")
                return
            
            # Try to parse as signal
            signal = self.signal_parser.parse_signal(text, is_reply=is_reply)
            
            if signal:
                self.signals_found += 1
                
                # VERBOSE LOGGING: Signal details
                logger.info("=" * 80)
                logger.info(f"🎯 SIGNAL DETECTED SUCCESSFULLY")
                logger.info("=" * 80)
                logger.info(f"💱 Pair: {signal.pair}")
                logger.info(f"📊 Action: {signal.action.value}")
                logger.info(f"💰 Entry Price: {signal.entry_price}")
                logger.info(f"🛑 Stop Loss: {signal.stop_loss}")
                logger.info(f"🎯 TP1: {signal.take_profit_1}")
                if signal.take_profit_2:
                    logger.info(f"🎯 TP2: {signal.take_profit_2}")
                if signal.take_profit_3:
                    logger.info(f"🎯 TP3: {signal.take_profit_3}")
                logger.info(f"📝 TPs Count: {len(signal.get_take_profits())}")
                logger.info("=" * 80)
                
                # Send to web server
                if await self._send_signal_to_server(signal, message_id, channel_id):
                    self.signals_sent += 1
                    logger.info(f"✅ Signal sent to server successfully")
                else:
                    logger.error(f"❌ Failed to send signal to server")
            else:
                logger.info("=" * 80)
                logger.info(f"❌ NO VALID SIGNAL DETECTED")
                logger.info("=" * 80)
                
        except Exception as e:
            logger.error(f"Error processing message {message_id}: {e}")
    
    async def _send_signal_to_server(self, signal: TradingSignal, message_id: int, channel_id: int) -> bool:
        """Send parsed signal to web server"""
        try:
            signal_data = {
                'id': str(uuid.uuid4()),  # Generate unique signal ID
                'message_id': message_id,
                'channel_id': channel_id,
                'symbol': signal.pair,
                'action': signal.action.value,
                'entry_price': signal.entry_price,
                'stop_loss': signal.stop_loss,
                'tp1': signal.take_profit_1,
                'tp2': signal.take_profit_2,  # Can be None
                'tp3': signal.take_profit_3,  # Can be None
                'raw_message': signal.raw_text
            }
            
            # VERBOSE LOGGING: JSON payload
            logger.info("=" * 80)
            logger.info(f"📤 SENDING TO WEB SERVER")
            logger.info("=" * 80)
            logger.info(f"🌐 URL: {self.web_server_url}/add_signal")
            logger.info(f"📋 JSON Payload:")
            import json
            formatted_json = json.dumps(signal_data, indent=2, ensure_ascii=False)
            for i, line in enumerate(formatted_json.split('\n'), 1):
                logger.info(f"│ {i:2}: {line}")
            logger.info("=" * 80)
            
            # Send to web server
            response = requests.post(
                f"{self.web_server_url}/add_signal",
                json=signal_data,
                timeout=10
            )
            
            # VERBOSE LOGGING: Server response
            logger.info("=" * 80)
            logger.info(f"📥 WEB SERVER RESPONSE")
            logger.info("=" * 80)
            logger.info(f"📊 Status Code: {response.status_code}")
            logger.info(f"⏱️ Response Time: {response.elapsed.total_seconds():.3f}s")
            logger.info(f"📋 Response Headers:")
            for key, value in response.headers.items():
                logger.info(f"│   {key}: {value}")
            logger.info(f"📝 Response Body:")
            try:
                response_json = response.json()
                formatted_response = json.dumps(response_json, indent=2, ensure_ascii=False)
                for i, line in enumerate(formatted_response.split('\n'), 1):
                    logger.info(f"│ {i:2}: {line}")
            except:
                logger.info(f"│   {response.text}")
            logger.info("=" * 80)
            
            if response.status_code == 200:
                logger.info("✅ SUCCESS: Signal accepted by web server")
                return True
            elif response.status_code == 409:
                logger.warning("⚠️ WARNING: Signal already exists in database (considering as success)")
                return True  # Consider this success
            else:
                logger.error(f"❌ ERROR: Server returned error: {response.status_code} - {response.text}")
                return False
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to send signal to server: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error sending signal: {e}")
            return False
    
    async def _check_server_health(self):
        """Check if web server is running"""
        try:
            response = requests.get(f"{self.web_server_url}/health", timeout=5)
            return response.status_code == 200
        except:
            return False
    
    async def start_listening(self):
        """Start listening for messages"""
        if not self.target_entity:
            logger.error("No target entity configured")
            return False
        
        try:
            # Check server health
            if not await self._check_server_health():
                logger.error(f"Web server not responding at {self.web_server_url}")
                logger.error("Please start the web server first: python simple_web_server.py")
                return False
            
            logger.info(f"Web server is healthy at {self.web_server_url}")
            
            # Set up message handler for ALL channels
            if self.target_entities:
                @self.client.on(events.NewMessage(chats=self.target_entities))
                async def message_handler(event):
                    await self._process_message(event)
            else:
                # Fallback to single channel
                @self.client.on(events.NewMessage(chats=self.target_entity))
                async def message_handler(event):
                    await self._process_message(event)
            
            # Display startup information
            logger.info("=" * 60)
            logger.info("   MULTI-CHANNEL TELEGRAM SIGNAL LISTENER - ACTIVE")
            logger.info("=" * 60)
            
            if self.target_entities:
                logger.info(f"📡 Monitoring {len(self.target_entities)} Channels:")
                for entity in self.target_entities:
                    channel_info = self.channel_info.get(entity.id, {})
                    logger.info(f"  • {entity.title} ({channel_info.get('type', 'Unknown')})")
            else:
                logger.info(f"📡 Monitoring Channel: {getattr(self.target_entity, 'title', 'Unknown')}")
            
            logger.info(f"🎯 Signal Types: LIMIT ORDERS ONLY")
            logger.info(f"❌ Ignoring: Market orders, replies, close instructions")
            logger.info(f"🤖 AI Validation: {'ENABLED' if self.signal_parser.openai_client else 'DISABLED'}")
            logger.info(f"🌐 Web Server: {self.web_server_url}")
            logger.info("=" * 60)
            logger.info("🚀 Ready to process signals from all channels...")
            
            # Start statistics logging task
            asyncio.create_task(self._log_statistics())
            
            # Keep running
            await self.client.run_until_disconnected()
            
        except Exception as e:
            logger.error(f"Error in message listener: {e}")
            return False
    
    async def _log_statistics(self):
        """Log statistics periodically"""
        while True:
            try:
                await asyncio.sleep(300)  # Every 5 minutes
                
                uptime = time.time() - self.start_time
                uptime_formatted = str(datetime.fromtimestamp(uptime) - datetime.fromtimestamp(0)).split('.')[0]
                
                # Only log statistics if debug statistics are enabled
                if getattr(self.config, 'DEBUG_STATISTICS', False) or logger.isEnabledFor(logging.DEBUG):
                    logger.debug(f"=== STATS ===")
                    logger.debug(f"Uptime: {uptime_formatted}")
                    logger.debug(f"Messages processed: {self.messages_processed}")
                    logger.debug(f"Signals found: {self.signals_found}")
                    logger.debug(f"Signals sent to server: {self.signals_sent}")
                    if self.messages_processed > 0:
                        signal_rate = (self.signals_found / self.messages_processed) * 100
                        logger.debug(f"Signal detection rate: {signal_rate:.1f}%")
                    
                    # Check server health
                    server_healthy = await self._check_server_health()
                    logger.debug(f"Web server status: {'HEALTHY' if server_healthy else 'ERROR'}")
                
            except Exception as e:
                logger.error(f"Statistics logging error: {e}")
    
    async def shutdown(self):
        """Graceful shutdown"""
        logger.info("Shutting down SimpleTelegramListener...")
        try:
            if self.client and self.client.is_connected():
                await self.client.disconnect()
            logger.info("Shutdown complete")
        except Exception as e:
            logger.error(f"Shutdown error: {e}")

async def main():
    """Main entry point"""
    try:
        # Load configuration
        config = Config()
        
        # Create and initialize listener
        listener = SimpleTelegramListener(config)
        
        if not await listener.initialize():
            logger.error("Failed to initialize listener")
            return
        
        # Start listening
        await listener.start_listening()
        
    except KeyboardInterrupt:
        logger.info("Received interrupt signal")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
    finally:
        if 'listener' in locals():
            await listener.shutdown()

if __name__ == "__main__":
    asyncio.run(main()) 