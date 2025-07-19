#!/usr/bin/env python3
"""
Main Launcher for Simple Signal System
Starts both web server and Telegram listener with unified logging
"""

import asyncio
import logging
import threading
import time
import signal
import sys
from datetime import datetime

from simple_web_server import SimpleSignalServer
from simple_telegram_listener import SimpleTelegramListener
from config import Config
from windows_logging import setup_windows_safe_logging

class SimpleSignalSystem:
    """Main system launcher that manages both web server and Telegram listener"""
    
    def __init__(self):
        self.config = Config()
        self.web_server = None
        self.telegram_listener = None
        self.running = False
        self.shutdown_event = None  # Will be set in start()
        
        # Setup unified logging
        self._setup_logging()
        
        self.logger = logging.getLogger(__name__)
    
    def _setup_logging(self):
        """Setup unified logging for both components with Windows emoji support"""
        # Force emoji replacement for Windows compatibility
        # This ensures emojis are replaced with text even on non-Windows systems for testing
        force_replacement = True  # Always use safe text replacements for Windows compatibility
        
        # Setup Windows-safe logging for root logger
        root_logger = setup_windows_safe_logging('', 'signal_system.log', logging.INFO, force_replacement)
        
        # Reduce noise from some libraries
        logging.getLogger('telethon').setLevel(logging.WARNING)
        logging.getLogger('werkzeug').setLevel(logging.WARNING)
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info(f"Received signal {signum} - initiating shutdown...")
        self.running = False
        # Set the shutdown event to interrupt async loops
        if hasattr(self, 'shutdown_event'):
            # Schedule the event to be set in the event loop
            try:
                asyncio.get_event_loop().call_soon_threadsafe(self.shutdown_event.set)
            except:
                # If no event loop, try to create one
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
    
    async def _start_telegram_listener(self):
        """Start Telegram listener"""
        try:
            self.logger.info("📡 Starting Telegram listener...")
            self.telegram_listener = SimpleTelegramListener(self.config)
            
            # Initialize and start
            if await self.telegram_listener.initialize():
                await self.telegram_listener.start_listening()
            else:
                self.logger.error("❌ Failed to initialize Telegram listener")
                self.running = False
                
        except Exception as e:
            self.logger.error(f"❌ Telegram listener error: {e}")
            self.running = False
    
    def _show_startup_banner(self):
        """Display startup banner"""
        self.logger.info("=" * 70)
        self.logger.info("   🚀 SIMPLE SIGNAL SYSTEM STARTING UP")
        self.logger.info("=" * 70)
        self.logger.info(f"📅 Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        self.logger.info(f"🌐 Web Server Port: {self.config.MT4_HTTP_PORT}")
        self.logger.info(f"📱 Phone: {self.config.TELEGRAM_PHONE_NUMBER}")
        self.logger.info(f"📁 Database: signals.db")
        self.logger.info(f"📝 Logs: signal_system.log")
        self.logger.info("=" * 70)
    
    def _show_ready_banner(self):
        """Display ready banner"""
        self.logger.info("=" * 70)
        self.logger.info("   ✅ SIMPLE SIGNAL SYSTEM READY")
        self.logger.info("=" * 70)
        self.logger.info("🌐 Web Server: RUNNING")
        self.logger.info("📡 Telegram Listener: ACTIVE") 
        self.logger.info("🎯 Monitoring: LIMIT ORDERS ONLY")
        self.logger.info("❌ Ignoring: Market orders, replies, close instructions")
        self.logger.info("🤖 MT5 EA: Ready to connect")
        self.logger.info("=" * 70)
        self.logger.info("💡 Tip: Attach SimpleSignalEA_MT5.mq5 to your MT5 chart")
        self.logger.info("🔍 Monitor: http://localhost:{}/stats".format(self.config.MT4_HTTP_PORT))
        self.logger.info("=" * 70)
    
    async def start(self):
        """Start the complete system"""
        self.running = True
        self.shutdown_event = asyncio.Event()
        
        # Setup signal handlers now that we have an event loop
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
            
            # Start Telegram listener in background task
            telegram_task = asyncio.create_task(self._start_telegram_listener())
            
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
        finally:
            await self.shutdown()
    
    async def shutdown(self):
        """Graceful shutdown"""
        self.logger.info("=" * 50)
        self.logger.info("   🛑 SHUTTING DOWN SIGNAL SYSTEM")
        self.logger.info("=" * 50)
        
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
        
        self.logger.info("🏁 Signal system shutdown complete")

async def main():
    """Main entry point"""
    try:
        system = SimpleSignalSystem()
        await system.start()
    except Exception as e:
        logging.error(f"Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main()) 