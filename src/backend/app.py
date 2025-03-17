from flask import Flask, request, jsonify
import pyodbc
import os
from dotenv import load_dotenv
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.dbapi import trace_integration, instrument_connection
from opentelemetry import trace

import logging
# Import the `configure_azure_monitor()` function from the
# `azure.monitor.opentelemetry` package.
from azure.monitor.opentelemetry import configure_azure_monitor

load_dotenv()

APP_NAME=os.getenv("APP_NAME", "app.backend") 
PORT=int(os.getenv("PORT", 8080))
LEVEL = os.getenv("LOG_LEVEL", "INFO")
conn_str = os.environ["ConnectionString"]

if ("APPLICATIONINSIGHTS_CONNECTION_STRING" in os.environ):
    # Configure OpenTelemetry to use Azure Monitor with the 
    # APPLICATIONINSIGHTS_CONNECTION_STRING environment variable.
    configure_azure_monitor(
        logger_name=APP_NAME,  # Set the namespace for the logger in which you would like to collect telemetry for if you are collecting logging telemetry. This is imperative so you do not collect logging telemetry from the SDK itself.
    )

logger = logging.getLogger(APP_NAME)  # Logging telemetry will be collected from logging calls made with this logger and all of it's children loggers.
logger.setLevel(LEVEL)
tracer=trace.get_tracer(APP_NAME)

if ("APPLICATIONINSIGHTS_CONNECTION_STRING" not in os.environ):
    logger.warning("APPLICATIONINSIGHTS_CONNECTION_STRING not found in environment variables.")

logging.info("Reading environment variables")
table_name = os.getenv("TableName", "Value_Store")
if table_name is None or table_name == "":
    raise ValueError("TableName environment variable not set")

app = Flask(APP_NAME)

FlaskInstrumentor().instrument_app(app)
trace_integration(pyodbc, "connect", "odbc",enable_commenter=True)

@app.route('/ping', methods=['GET'])
def ping():
    return jsonify({"message": "pong"}), 200

@app.route('/health', methods=['GET'])
def health():    
    with pyodbc.connect(conn_str) as conn:
        try:
            info=conn.getinfo(pyodbc.SQL_DBMS_NAME)
            logger.info("DBMS Name: %s",info)
        except pyodbc.Error:
            return jsonify({"message": "Unhealthy"}), 500

    return jsonify({"message": "Healthy"}), 200

@app.route('/set', methods=['POST'])
def create_value():
    with tracer.start_as_current_span("create_value"):
        logger.info("Value %s",request.json)
        key = request.json.get('key')
        value = request.json.get('value')
        query=f"INSERT INTO {table_name}([key], [stored_value]) VALUES (?, ?)"
        with pyodbc.connect(conn_str) as conn:
            logger.info("Query %s",query)
            conn.execute(query, key, value)
            conn.commit()
            return jsonify({"message": "Value set successfully"}), 200

@app.route('/update', methods=['POST'])
def set_value():
    with tracer.start_as_current_span("set_value"):
        key = request.json.get('key')
        value = request.json.get('value')
        with pyodbc.connect(conn_str) as conn:
            conn.execute(f"UPDATE {table_name} SET [stored_value] = ? WHERE [key] = ?;", value, key)
            conn.commit()
            return jsonify({"message": "Value updated successfully"}), 200

@app.route('/get/<key>', methods=['GET'])
def get_value(key):
    with tracer.start_as_current_span("get_value"):
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            cursor.execute(f"SELECT [stored_value] FROM {table_name} WHERE [key] = ?;", (key,))
            row = cursor.fetchone()
            if row:
                return jsonify({"key": key, "value": row[0]}), 200
            else:
                return jsonify({"message": "Key not found"}), 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT)