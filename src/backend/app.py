from flask import Flask, request, jsonify
import pyodbc
import os

app = Flask(__name__)


conn_str = os.environ["ConnectionString"]
table_name = os.environ["TableName"]


conn = pyodbc.connect(conn_str)

@app.route('/health', methods=['GET'])
def health():
    # check if the redis server is healthy
    try:
        _ = conn.getinfo()
    except pyodbc.Error:
        return jsonify({"message": "Unhealthy"}), 500

    return jsonify({"message": "Healthy"}), 200

@app.route('/create', methods=['POST'])
def create_value():
    key = request.json.get('key')
    value = request.json.get('value')
    conn.execute("INSERT INTO ${TableName} ([key], [stored_value]) VALUES (?, ?)", key, value)
    return jsonify({"message": "Value set successfully"}), 200

@app.route('/set', methods=['POST'])
def set_value():
    key = request.json.get('key')
    value = request.json.get('value')
    conn.execute("UPDATE ${TableName} ([key], [stored_value]) VALUES (?, ?)", key, value)
    return jsonify({"message": "Value updated successfully"}), 200

@app.route('/get/<key>', methods=['GET'])
def get_value(key):
    cursor = conn.cursor()
    cursor.execute("SELECT [stored_value] FROM ${TableName} WHERE [keys] = ?", key)
    row = cursor.fetchone()
    if row:
        return jsonify({"key": key, "value": row[0]}), 200
    else:
        return jsonify({"message": "Key not found"}), 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)