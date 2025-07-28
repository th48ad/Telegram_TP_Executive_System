#!/usr/bin/env python3
"""
Enhanced Main Launcher with Network Recovery
Includes automatic restart for network failures
"""

import asyncio
import logging
import threading
import time
import signal
import sys
from datetime import datetime
import traceback

from simple_web_server import SimpleSignalServer
from simple_telegram_listener import SimpleTelegramListener
from config import Config
from windows_logging import setup_windows_safe_logging

class EnhancedSignalSystem:
    """Enhanced system launcher with automatic recovery"""
    
    def __init__(self):
        self.config = Config()
        self.web_server = None
        self.telegram_listener = None
        self.running = False
        self.shutdown_event = None
        self.max_restart_attempts = 10  # Maximum restart attempts
        self.restart_delay = 60  # Seconds between restart attempts
        self.current_restart_count = 0
        
        # Setup unified logging
        self._setup_logging()
        self.logger = logging.getLogger(__name__)
    
    def _setup_logging(self):
        """Setup unified logging for both components with Windows emoji support"""
        force_replacement = True
        root_logger = setup_windows_safe_logging('', 'signal_system.log', logging.INFO, force_replacement)
        logging.getLogger('telethon').setLevel(logging.WARNING)
        logging.getLogger('werkzeug').setLevel(logging.WARNING)
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info(f"Received signal {signum} - initiating graceful shutdown...")
        self.running = False
        if hasattr(self, 'shutdown_event'):
            try:
                asyncio.get_event_loop().call_soon_threadsafe(self.shutdown_event.set)
            except:
                pass
    
    def _start_web_server(self):
        """Start web server in a separate thread"""
        try:
            self.logger.info("🌐 Starting web server...")
            self.web_server = SimpleSignalServer(port=self.config.MT4_HTTP_PORT)
            self.web_server.start()
        except Exception as e:
            self.logger.error(f"❌ Web server failed to start: {e}")
            self.running = False
    
    async def _start_telegram_listener_with_recovery(self):
        """Start Telegram listener with automatic recovery"""
        while self.running:
            try:
                self.logger.info("📡 Starting Telegram listener...")
                self.telegram_listener = SimpleTelegramListener(self.config)
                
                # Initialize and start
                if await self.telegram_listener.initialize():
                    self.logger.info("✅ Telegram listener initialized successfully")
                    
                    # Reset restart count on successful start
                    self.current_restart_count = 0
                    
                    # Start listening - this will block until disconnected
                    await self.telegram_listener.start_listening()
                    
                    # If we reach here, the listener stopped (could be normal or error)
                    if not self.running:
                        self.logger.info("📡 Telegram listener stopped due to shutdown request")
                        break
                    else:
                        raise Exception("Telegram listener disconnected unexpectedly")
                else:
                    raise Exception("Failed to initialize Telegram listener")
                    
            except asyncio.CancelledError:
                self.logger.info("📡 Telegram listener cancelled")
                break
                
            except Exception as e:
                self.current_restart_count += 1
                error_msg = str(e)
                
                # Check for specific error types
                if "TimeoutError" in error_msg or "WinError 121" in error_msg:
                    self.logger.warning(f"🌐 Network connectivity issue detected: {error_msg}")
                elif "ConnectionError" in error_msg:
                    self.logger.warning(f"🔌 Connection error detected: {error_msg}")
                else:
                    self.logger.error(f"❌ Telegram listener error: {error_msg}")
                    self.logger.debug(f"Full traceback: {traceback.format_exc()}")
                
                # Check if we should attempt restart
                if self.current_restart_count >= self.max_restart_attempts:
                    self.logger.error(f"🛑 Maximum restart attempts ({self.max_restart_attempts}) reached")
                    self.logger.error(f"🛑 Giving up on automatic recovery - manual intervention required")
                    self.running = False
                    break
                
                if not self.running:
                    break
                
                # Calculate backoff delay (exponential backoff with max)
                backoff_delay = min(self.restart_delay * (2 ** (self.current_restart_count - 1)), 300)  # Max 5 minutes
                
                self.logger.warning(f"🔄 Attempt {self.current_restart_count}/{self.max_restart_attempts} failed")
                self.logger.warning(f"⏱️ Waiting {backoff_delay} seconds before retry...")
                
                # Cleanup current listener
                if self.telegram_listener:
                    try:
                        await self.telegram_listener.shutdown()
                    except:
                        pass
                    self.telegram_listener = None
                
                # Wait before retry (with cancellation support)
                try:
                    await asyncio.wait_for(self.shutdown_event.wait(), timeout=backoff_delay)
                    # If shutdown_event was set, exit
                    break
                except asyncio.TimeoutError:
                    # Timeout expired, continue with retry
                    pass
                
                self.logger.info(f"🔄 Attempting restart {self.current_restart_count + 1}/{self.max_restart_attempts}...")
    
    def _show_startup_banner(self):
        """Display startup banner"""
        self.logger.info("=" * 70)
        self.logger.info("   🚀 ENHANCED SIGNAL SYSTEM STARTING UP")
        self.logger.info("=" * 70)
        self.logger.info(f"📅 Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        self.logger.info(f"🌐 Web Server Port: {self.config.MT4_HTTP_PORT}")
        self.logger.info(f"📱 Phone: {self.config.TELEGRAM_PHONE_NUMBER}")
        self.logger.info(f"📁 Database: signals.db")
        self.logger.info(f"📝 Logs: signal_system.log")
        self.logger.info(f"🔄 Auto-Recovery: ENABLED (Max: {self.max_restart_attempts} attempts)")
        self.logger.info("=" * 70)
    
    def _show_ready_banner(self):
        """Display ready banner"""
        self.logger.info("=" * 70)
        self.logger.info("   ✅ ENHANCED SIGNAL SYSTEM READY")
        self.logger.info("=" * 70)
        self.logger.info("🌐 Web Server: RUNNING")
        self.logger.info("📡 Telegram Listener: ACTIVE (with auto-recovery)")
        self.logger.info("🎯 Monitoring: LIMIT ORDERS ONLY")
        self.logger.info("❌ Ignoring: Market orders, replies, close instructions")
        self.logger.info("🤖 MT5 EA: Ready to connect")
        self.logger.info("🛡️ Network Recovery: ENABLED")
        self.logger.info("=" * 70)
        self.logger.info("💡 Tip: Attach SimpleSignalEA_MT5.mq5 to your MT5 chart")
        self.logger.info("🔍 Monitor: http://localhost:{}/stats".format(self.config.MT4_HTTP_PORT))
        self.logger.info("=" * 70)
    
    async def start(self):
        """Start the complete system with recovery"""
        self.running = True
        self.shutdown_event = asyncio.Event()
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
        self._show_startup_banner()
        
        try:
            # Start web server in background thread
            web_thread = threading.Thread(target=self._start_web_server, daemon=True)
            web_thread.start()
            
            # Wait for web server to start
            await asyncio.sleep(3)
            
            # Check if web server started successfully
            import requests
            try:
                response = requests.get(f"http://localhost:{self.config.MT4_HTTP_PORT}/health", timeout=5)
                if response.status_code == 200:
                    self.logger.info("✅ Web server started successfully")
                else:
                    raise Exception(f"Web server health check failed: {response.status_code}")
            except Exception as e:
                self.logger.error(f"❌ Web server startup verification failed: {e}")
                return
            
            # Show ready banner
            self._show_ready_banner()
            
            # Start Telegram listener with recovery
            telegram_task = asyncio.create_task(self._start_telegram_listener_with_recovery())
            
            # Wait for either the telegram task to complete or shutdown signal
            done, pending = await asyncio.wait(
                [telegram_task, asyncio.create_task(self.shutdown_event.wait())],
                return_when=asyncio.FIRST_COMPLETED
            )
            
            # Cancel any remaining tasks
            for task in pending:
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
            
        except KeyboardInterrupt:
            self.logger.info("🛑 Shutdown requested by user")
        except Exception as e:
            self.logger.error(f"❌ System error: {e}")
            self.logger.debug(f"Full traceback: {traceback.format_exc()}")
        finally:
            await self.shutdown()
    
    async def shutdown(self):
        """Graceful shutdown"""
        self.logger.info("=" * 50)
        self.logger.info("   🛑 SHUTTING DOWN ENHANCED SIGNAL SYSTEM")
        self.logger.info("=" * 50)
        
        self.running = False
        
        # Shutdown Telegram listener
        if self.telegram_listener:
            try:
                await self.telegram_listener.shutdown()
                self.logger.info("✅ Telegram listener stopped")
            except Exception as e:
                self.logger.error(f"❌ Error stopping Telegram listener: {e}")
        
        # Shutdown web server
        if self.web_server:
            try:
                self.web_server.stop()
                self.logger.info("✅ Web server stopped")
            except Exception as e:
                self.logger.error(f"❌ Error stopping web server: {e}")
        
        self.logger.info("🏁 Enhanced signal system shutdown complete")

async def main():
    """Main entry point"""
    try:
        system = EnhancedSignalSystem()
        await system.start()
    except Exception as e:
        logging.error(f"Fatal error: {e}")
        logging.debug(f"Full traceback: {traceback.format_exc()}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main()) 