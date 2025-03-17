from flask import Flask, request, jsonify
import pyodbc
import os
from dotenv import load_dotenv

import logging
# Import the `configure_azure_monitor()` function from the
# `azure.monitor.opentelemetry` package.
from azure.monitor.opentelemetry import configure_azure_monitor

load_dotenv()

APP_NAME=os.getenv("APP_NAME", "app.backend") 
LEVEL = os.getenv("LOG_LEVEL", "INFO")

if ("APPLICATIONINSIGHTS_CONNECTION_STRING" in os.environ):
    # Configure OpenTelemetry to use Azure Monitor with the 
    # APPLICATIONINSIGHTS_CONNECTION_STRING environment variable.
    configure_azure_monitor(
        logger_name=APP_NAME,  # Set the namespace for the logger in which you would like to collect telemetry for if you are collecting logging telemetry. This is imperative so you do not collect logging telemetry from the SDK itself.
    )

logger = logging.getLogger(APP_NAME)  # Logging telemetry will be collected from logging calls made with this logger and all of it's children loggers.
logger.setLevel(LEVEL)

if ("APPLICATIONINSIGHTS_CONNECTION_STRING" not in os.environ):
    logger.warning("APPLICATIONINSIGHTS_CONNECTION_STRING not found in environment variables.")

logging.info("Reading environment variables")
table_name = os.getenv("TableName", "Value_Store")
if table_name is None or table_name == "":
    raise ValueError("TableName environment variable not set")
conn_str = os.environ["ConnectionString"]
PORT=int(os.getenv("PORT", 8080))
conn = None

app = Flask(APP_NAME)

def getConnection()->pyodbc.Connection:
    global conn
    global conn_str

    if conn is None:
        try:
            logger.info("Connecting to database")
            conn = pyodbc.connect(conn_str)
        except pyodbc.Error as e:
            logger.error("Error connecting to database", exc_info=True)
            raise e

    return conn

@app.route('/ping', methods=['GET'])
def ping():
    return jsonify({"message": "pong"}), 200

@app.route('/health', methods=['GET'])
def health():
    # check if the redis server is healthy
    try:
        conn = getConnection()
        info=conn.getinfo(pyodbc.SQL_DBMS_NAME)
        logger.info("DBMS Name: %s",info)
    except pyodbc.Error:
        return jsonify({"message": "Unhealthy"}), 500

    return jsonify({"message": "Healthy"}), 200

@app.route('/set', methods=['POST'])
def create_value():
    logger.info("Value %s",request.json)
    key = request.json.get('key')
    value = request.json.get('value')
    query=f"INSERT INTO {table_name}([key], [stored_value]) VALUES (?, ?)"
    logger.info("Query %s",query)
    conn = getConnection()
    conn.execute(query, key, value)
    conn.commit()
    return jsonify({"message": "Value set successfully"}), 200

@app.route('/update', methods=['POST'])
def set_value():
    key = request.json.get('key')
    value = request.json.get('value')
    conn = getConnection()
    conn.execute(f"UPDATE {table_name} SET [stored_value] = ? WHERE [key] = ?;", value, key)
    conn.commit()
    return jsonify({"message": "Value updated successfully"}), 200

@app.route('/get/<key>', methods=['GET'])
def get_value(key):
    conn = getConnection()
    cursor = conn.cursor()
    cursor.execute(f"SELECT [stored_value] FROM {table_name} WHERE [key] = ?;", (key,))
    row = cursor.fetchone()
    if row:
        return jsonify({"key": key, "value": row[0]}), 200
    else:
        return jsonify({"message": "Key not found"}), 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT)