# Use the official Python image from the Docker Hub
FROM python:3.13-slim

RUN apt update && apt install unixodbc -y
# Set the working directory
WORKDIR /app

# Copy the requirements file into the container
COPY requirements.txt .

# Install the dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code into the container
COPY *.py .

# Expose the port the app runs on
EXPOSE 80

# Run the application
CMD ["gunicorn", "--bind", "0.0.0.0:80", "app:app"]