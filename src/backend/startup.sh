#!/bin/sh

# omg https://learn.microsoft.com/en-us/answers/questions/1648397/azure-container-app-service-environment-variables
printenv > .env
gunicorn --bind 0.0.0.0:8080 app:app