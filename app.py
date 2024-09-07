import logging
import os
from datetime import datetime as dt

import aiohttp
import coloredlogs
from bs4 import BeautifulSoup
from telegram.ext import Application, CommandHandler, MessageHandler, filters

logger = logging.getLogger(__name__)
LOGLEVEL = os.getenv("LOGLEVEL", "INFO").upper()
coloredlogs.install(level=LOGLEVEL)
TELEGRAM_TOKEN = os.getenv("TG_TOKEN")
CHANNEL_ID = "@tlvnmupdates"

last_price = None


async def start(update, context):
    """Handle the /start command"""
    welcome_message = """
    Hi! 👋 I'm the Tel Aviv Fast Lane bot! 🏎️🚙🛣️📈📉
    Click /add_me for a link to the updates channel
    Click /get_price to get price of the lane now
    """
    await update.message.reply_text(welcome_message)


async def add_to_channel(update, context):
    """Add user to channel"""
    user = update.message.from_user
    user_id = user.id
    await update.message.reply_text(f"Join channel {CHANNEL_ID} for regular updates.")
    logger.info("Sent user %s link to channel %s", user_id, CHANNEL_ID)


async def send_price_update(context):
    """Send price update to the channel"""
    price = await get_price()
    if price:
        message = f"Fast Lane current price: {price} NIS as of {dt.now().strftime('%H:%M:%S')}"
        await context.bot.send_message(chat_id=CHANNEL_ID, text=message)
    else:
        logger.warning("Failed to get price for scheduled update")


async def check_and_send_price_update(context):
    """Check for price changes and send update if changed"""
    global last_price
    current_price = await get_price()

    if current_price and current_price != last_price:
        message = f"Fast Lane price update: {current_price} NIS as of {dt.now().strftime('%H:%M:%S')}"
        await context.bot.send_message(chat_id=CHANNEL_ID, text=message)
        last_price = current_price
        logger.info(f"Price changed to {current_price}. Update sent.")
    elif current_price is None:
        logger.warning("Failed to get price for scheduled update")
    else:
        logger.info(f"Price unchanged at {current_price}. No update sent.")


async def get_price():
    """Scrape and parse price from website"""
    async with aiohttp.ClientSession() as session:
        async with session.get(
            "https://fastlane.co.il/", auth=None, ssl=False
        ) as response:
            html_content = await response.text()

    soup = BeautifulSoup(html_content, "html.parser")
    price_element = soup.find("span", {"id": "lblPrice"})
    if price_element:
        return price_element.text.strip()
    return None


async def get_current_price(update, context):
    """Handle the /get_price command"""
    price = await get_price()
    if price:
        await update.message.reply_text(
            f"Fast Lane current price: {price} NIS as of {dt.now().strftime('%H:%M:%S')}"
        )
    else:
        await update.message.reply_text("Sorry, couldn't find the current price.")


def validate_env_vars():
    """Validate required environment variables"""
    required_vars = ["TG_TOKEN"]
    logger.info("Validating required environment variables")
    for var in required_vars:
        if not os.getenv(var):
            raise ValueError(f"Missing required environment variable: {var}")
    logger.info("Environment variables validated successfully")


async def echo(update, context):
    """Echo the user message."""
    await update.message.reply_text(
        f"""You said: {update.message.text}
        I don't understand that, but I'll pass it on!"""
    )


async def error(update, context):
    """Log Errors caused by Updates."""
    logger.warning('Update "%s" caused error "%s"', update, context.error)


def main():
    """main function to start the bot"""
    application = Application.builder().token(token=TELEGRAM_TOKEN).build()

    # Add job queue
    job_queue = application.job_queue
    job_queue.run_repeating(
        check_and_send_price_update, interval=300, first=10
    )  # Run every 5 minutes, start after 10 seconds

    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("add_me", add_to_channel))
    application.add_handler(CommandHandler("get_price", get_current_price))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, echo))
    application.add_error_handler(error)
    # application.add_handler(CallbackQueryHandler(button))
    application.run_polling()


if __name__ == "__main__":
    validate_env_vars()
    logger.info("Starting bot... ")
    main()
