# Use the official Python image from the Docker Hub
FROM python:3.13-slim

# Set the working directory
WORKDIR /app

# Copy the requirements file into the container
COPY requirements.txt .

# Install the dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code into the container
COPY *.py .
COPY startup.sh .

# Expose the port the app runs on
ENV PORT 80
ENV BACKEND http://localhost:8080
ENV LOG_LEVEL INFO
EXPOSE ${PORT}

# Run the application
CMD ["sh", "startup.sh"]