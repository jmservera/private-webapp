# Use the official Python image from the Docker Hub
FROM python:3.13-slim

RUN apt-get update && \
    apt-get install g++ gnupg2 curl -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
RUN curl https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list

RUN apt-get update && \
    ACCEPT_EULA=Y apt-get install -y msodbcsql18 && \
    echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc && \
    . ~/.bashrc && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


# Set the working directory
WORKDIR /app

# Copy the requirements file into the container
COPY requirements.txt .

# Install the dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code into the container
COPY *.py .
COPY startup.sh .

ENV ConnectionString ""
ENV TableName "Value_Store"
ENV PORT 8080
ENV LOG_LEVEL INFO
# Expose the port the app runs on
EXPOSE ${PORT}

# Run the application
CMD ["sh", "startup.sh"]