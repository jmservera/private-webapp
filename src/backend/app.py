from flask import Flask, request, jsonify
import pyodbc
import os
import logging
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig()
logging.getLogger().setLevel(logging.INFO)

app = Flask(__name__)



logging.info("Reading environment variables")
table_name = os.environ["TableName"]
conn_str = os.environ["ConnectionString"]

conn = None

def getConnection()->pyodbc.Connection:
    global conn
    global conn_str
    try:
        if conn is None:
            logging.info("Connecting to database")
            conn = pyodbc.connect(conn_str)        
    except pyodbc.Error as e:
        logging.error("Error connecting to database: %s %s", conn_str, e)

    return conn

@app.route('/health', methods=['GET'])
def health():
    # check if the redis server is healthy
    try:
        _ = getConnection().getinfo()
    except pyodbc.Error:
        return jsonify({"message": "Unhealthy"}), 500

    return jsonify({"message": "Healthy"}), 200

@app.route('/set', methods=['POST'])
def create_value():
    logging.info("Value %s",request.json)
    key = request.json.get('key')
    value = request.json.get('value')
    query=f"INSERT INTO {table_name}([key], [stored_value]) VALUES (?, ?)"
    logging.info("Query %s",query)
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
    app.run(host='0.0.0.0', port=8080)