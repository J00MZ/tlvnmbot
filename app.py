import os
import sqlite3
import time
from sqlite3 import Error

import requests
from bs4 import BeautifulSoup

TOKEN = "6375529982:AAEZSQvo97c7PUIsPZFFJlNhUApC8KqhKYw"
CHAT_ID = "447766753"


def create_connection():
    conn = None
    db_file = os.path(os.environ.get("PWD") + "price.db")
    try:
        conn = sqlite3.connect(db_file)
        if conn:
            print(sqlite3.version)
    except Error as e:
        print(e)

    if conn:
        return conn
    else:
        return None


def create_table(conn):
    try:
        query = """CREATE TABLE IF NOT EXISTS PriceData (
                    time text NOT NULL,
                    price text NOT NULL
                );"""
        conn.execute(query)
    except Error as e:
        print(e)


def send_message(text: str, chat_id: str, token: str):
    base_url = (
        f"https://api.telegram.org/bot{token}/sendMessage?chat_id={chat_id}&text={text}"
    )
    requests.get(base_url)


def parse_price():
    response = requests.get("https://fastlane.co.il/")
    soup = BeautifulSoup(response.text, "html.parser")
    price = soup.find("span", {"id": "lblPrice"}).text
    print("bs found price: %s", price)
    return price


def main():
    conn = create_connection()
    create_table(conn)

    last_price = None
    while True:
        try:
            current_price = parse_price()
            if current_price != last_price:
                send_message(f"New price: {current_price}", CHAT_ID, TOKEN)
                last_price = current_price

                # insert last_price into the database
                with conn:
                    query = """INSERT INTO PriceData(time, price) VALUES(?, ?);"""
                    conn.execute(
                        query, (time.strftime("%Y-%m-%d %H:%M:%S"), last_price)
                    )

        except Exception as e:
            send_message(f"Error: {e}", "YourChatId", "YourBotToken")
        time.sleep(300)  # wait for 5 minutes
