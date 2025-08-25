# Project: Autonomous Brewing - Monitoring and Control System

This project implements a system to monitor and control the craft beer brewing process. This version includes functional sample code in all components.

## Architecture

- **Sensor Node (raspberry_pi):** A Raspberry Pi 5 captures sensor data and sends it to the central server.
- **Central Server (central_server):** A Mini PC receives the data, processes it, and serves it via an API.
  - **Data Transport:** Rsync transfers report files in JSON format.
  - **Ingestion Service:** A Python microservice reads the reports and loads them into Redis (cache) and MongoDB (permanent storage).
  - **Databases (Docker):**
    - **Redis:** Cache for real-time data (last 3 days).
    - **MongoDB:** Primary storage for medium-term data.
    - **Cassandra:** Long-term storage for transactional data (>30 days).
  - **Backend:** a REST API developed with Django serves data from Redis and MongoDB.
  - **Frontend:** A web interface for real-time and historical data visualization with data tables.
  - **Metrics and Predictions:** Python/Django modules for analysis.

## Getting Started

1.  **Sensor Node:**
    - Navigate to `raspberry_pi`.
    - Run `python3 sensor_simulator.py` to start generating data.
    - Configure and run `./sync_reports.sh` to send the data to the server.

2.  **Central Server:**
    - Navigate to `central_server/database` and run `docker-compose up -d` to launch the databases.
    - Navigate to `central_server/services/data_ingestion`, install dependencies (`pip install -r requirements.txt`), and run `python3 ingest.py`.
    - Navigate to `central_server/api_backend`, create a virtual environment, install dependencies (`pip install -r requirements.txt`), and run the server (`python3 manage.py runserver`).
    - Open `central_server/frontend/index.html` in your browser.
