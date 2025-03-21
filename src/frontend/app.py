from flask import Flask, request, jsonify, render_template_string
from markupsafe import escape
import requests
import os
import re
from dotenv import load_dotenv

import logging
# Import the `configure_azure_monitor()` function from the
# `azure.monitor.opentelemetry` package.
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry import trace


load_dotenv()

APP_NAME=os.getenv("APP_NAME","app.frontend")
LEVEL = os.getenv("LOG_LEVEL", "INFO")

if ("APPLICATIONINSIGHTS_CONNECTION_STRING" in os.environ):
    # Configure OpenTelemetry to use Azure Monitor with the 
    # APPLICATIONINSIGHTS_CONNECTION_STRING environment variable.
    configure_azure_monitor(
        logger_name=APP_NAME,  # Set the namespace for the logger in which you would like to collect telemetry for if you are collecting logging telemetry. This is imperative so you do not collect logging telemetry from the SDK itself.
        enable_live_metrics=True
    )

logger = logging.getLogger(APP_NAME)  # Logging telemetry will be collected from logging calls made with this logger and all of it's children loggers.
logger.setLevel(LEVEL)
tracer=trace.get_tracer(APP_NAME)

if ("APPLICATIONINSIGHTS_CONNECTION_STRING" not in os.environ):
    logger.warning("APPLICATIONINSIGHTS_CONNECTION_STRING not found in environment variables.")

backend = os.getenv("BACKEND", "http://localhost:8080")
PORT = os.getenv("PORT", 80)

app = Flask(APP_NAME)
FlaskInstrumentor().instrument_app(app)

@app.route('/')
def index():
    # HTML template with form and table
    html = '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Simple Web App</title>
    </head>
    <body>
        <h1>Simple Web App</h1>
        <h2>Set Value</h2>
        <form id="valueForm">
            <label for="key">Key:</label>
            <input type="text" id="key" name="key" required>
            <label for="value">Value:</label>
            <input type="text" id="value" name="value" required>
            <button type="submit">Submit</button>
        </form>
        <h2>Update Value</h2>
        <form id="updateValueForm">
            <label for="ukey">Key:</label>
            <input type="text" id="ukey" name="ukey" required>
            <label for="uvalue">Value:</label>
            <input type="text" id="uvalue" name="uvalue" required>
            <button type="submit">Submit</button>
        </form>
        <h2>Get Value</h2>
        <form id="getValueForm">
            <label for="getKey">Key:</label>
            <input type="text" id="getKey" name="getKey" required>
            <button type="submit">Submit</button>
        </form>
        <div id="showValue"></div>
        <h2>Values</h2>
        <table id="valuesTable" border="1">
            <thead>
                <tr>
                    <th>Key</th>
                    <th>Value</th>
                </tr>
            </thead>
            <tbody>
            </tbody>
        </table>
        <script>
            document.getElementById('valueForm').onsubmit = function(event) {
                event.preventDefault();
                const key = document.getElementById('key').value;
                const value = document.getElementById('value').value;
                fetch('/set', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ key: key, value: value })
                }).then(response => response.json()).then(data => {
                    if (data.message === 'Value set successfully') {
                        const table = document.getElementById('valuesTable').getElementsByTagName('tbody')[0];
                        const newRow = table.insertRow();
                        const cellKey = newRow.insertCell(0);
                        const cellValue = newRow.insertCell(1);
                        cellKey.textContent = key;
                        cellValue.textContent = value;
                    } else {
                        alert('Failed to set value: ' + data.message);
                    }
                }).catch(error => {
                    alert('An error occurred: ' + error.message);
                });
            };
            document.getElementById('updateValueForm').onsubmit = function(event) {
                event.preventDefault();
                const key = document.getElementById('ukey').value;
                const value = document.getElementById('uvalue').value;
                fetch('/update', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ key: key, value: value })
                }).then(response => response.json()).then(data => {
                    if (data.message === 'Value updated successfully') {
                        const table = document.getElementById('valuesTable').getElementsByTagName('tbody')[0];
                        const newRow = table.insertRow();
                        const cellKey = newRow.insertCell(0);
                        const cellValue = newRow.insertCell(1);
                        cellKey.textContent = key;
                        cellValue.textContent = value;
                    } else {
                        alert('Failed to set value: ' + data.message);
                    }
                }).catch(error => {
                    alert('An error occurred: ' + error.message);
                });
            };
            document.getElementById('getValueForm').onsubmit = function(event) {
                event.preventDefault();
                const key = document.getElementById('getKey').value;
                fetch(`/get/${key}`).then(response => response.json()).then(data => {
                    if (data.key && data.value) {
                        document.getElementById('showValue').textContent = `Key: ${data.key}, Value: ${data.value}`;
                    } else {
                        alert('Key not found');
                    }
                }).catch(error => {
                    alert('An error occurred: ' + error.message);
                });
            };
        </script>
    </body>
    </html>
    '''
    return render_template_string(html)

@app.route('/set', methods=['POST'])
def set_value():
    with tracer.start_as_current_span("set_value"):
        # send a rest post request to the backend
        r=requests.post(backend + '/set', json=request.json)
        return r.json(), r.status_code # jsonify({"message": "Value set successfully"}), 200

@app.route('/update', methods=['POST'])
def update_value():
    with tracer.start_as_current_span("update_value"):
        # send a rest post request to the backend
        r=requests.post(backend + '/update', json=request.json)
        return r.json(), r.status_code

@app.route('/get/<key>', methods=['GET'])
def get_value(key):
    with tracer.start_as_current_span("get_value"):    
        # Input validation - only allow alphanumeric characters and some safe symbols
        if not re.match(r'^[a-zA-Z0-9_-]+$', key):
            return jsonify({"message": "Invalid key format"}), 400
            
        try:
            # Use proper URL formatting instead of string concatenation
            response = requests.get(f"{backend}/get/{key}", timeout=5)
            
            if response.status_code == 200:
                data = response.json()
                sanitized_data = {escape(k): escape(v) if isinstance(v, str) else v for k, v in data.items()}
                return jsonify(sanitized_data), 200
            elif response.status_code == 404:
                return jsonify({"message": "Key not found"}), 404
            else:
                # Log the actual error but don't expose details to client
                logger.error(f"Backend error: {response.text}")
                return jsonify({"message": "Internal server error"}), 500
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Request error: {str(e)}", exc_info=True)
            return jsonify({"message": "Error communicating with backend"}), 500
    
@app.route('/health', methods=['GET'])
def health():
    response = requests.get(backend + '/ping')
    if response.status_code == 200:
        return jsonify({"message": "Healthy"}), 200
    else:
        return jsonify({"message": "Backend Unhealthy"}), 500

    # send a rest get request to the backend
    # response = requests.get(backend + '/health')


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT)