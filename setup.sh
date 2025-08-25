#!/bin/bash
# ==============================================================================
# Script to create the project structure for "Autonomous Brewing" (v2.1 English)
#
# This script generates a complete and populated microservices architecture with
# functional sample code, including:
#   - A sensor node (Raspberry Pi) with a simulator and sync script.
#   - A central server (Mini PC) with:
#     - Data ingestion service (Redis and MongoDB).
#     - Docker Compose configuration for Redis, MongoDB, and Cassandra.
#     - A Django backend API (with functional views).
#     - An improved frontend with data tables and styles.
# ==============================================================================

# --- Project Name ---
PROJECT_NAME="autonomous_brewing"

# --- Verification to avoid overwriting an existing directory ---
if [ -d "$PROJECT_NAME" ]; then
  echo "Error: The directory '$PROJECT_NAME' already exists. Please remove it or choose another name."
  exit 1
fi

echo "🚀 Creating the populated project structure: $PROJECT_NAME..."

# --- Root Directory ---
mkdir "$PROJECT_NAME"
cd "$PROJECT_NAME"

# --- Main README ---
cat > README.md <<EOF
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
    - Navigate to \`raspberry_pi\`.
    - Run \`python3 sensor_simulator.py\` to start generating data.
    - Configure and run \`./sync_reports.sh\` to send the data to the server.

2.  **Central Server:**
    - Navigate to \`central_server/database\` and run \`docker-compose up -d\` to launch the databases.
    - Navigate to \`central_server/services/data_ingestion\`, install dependencies (\`pip install -r requirements.txt\`), and run \`python3 ingest.py\`.
    - Navigate to \`central_server/api_backend\`, create a virtual environment, install dependencies (\`pip install -r requirements.txt\`), and run the server (\`python3 manage.py runserver\`).
    - Open \`central_server/frontend/index.html\` in your browser.
EOF

# ==============================================================================
# 1. Sensor Node Structure (Raspberry Pi)
# ==============================================================================
echo "  -> Setting up the sensor node (raspberry_pi)..."
mkdir -p raspberry_pi/reports

# --- Sensor Simulator ---
cat > raspberry_pi/sensor_simulator.py <<EOF
import json
import time
import random
from datetime import datetime, timezone

# Directory where reports will be saved
REPORTS_DIR = 'reports'

def generate_sensor_data():
    """Simulates reading data from sensors."""
    return {
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'temperature_celsius': round(random.uniform(18.0, 22.5), 2),
        'pressure_psi': round(random.uniform(14.5, 15.5), 2),
        'co2_vol': round(random.uniform(2.0, 2.7), 2),
        'batch_id': 'B001-LAGER'
    }

if __name__ == "__main__":
    print("Starting sensor simulator... Press Ctrl+C to stop.")
    try:
        while True:
            data = generate_sensor_data()
            filename = f"{REPORTS_DIR}/report_{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}.json"
            
            with open(filename, 'w') as f:
                json.dump(data, f, indent=4)
                
            print(f"Report generated: {filename}")
            time.sleep(5) # Generate a report every 5 seconds
    except KeyboardInterrupt:
        print("\nStopping simulator.")
EOF

# --- Synchronization Script (rsync) ---
cat > raspberry_pi/sync_reports.sh <<EOF
#!/bin/bash
# Script to synchronize sensor reports with the central server using rsync.

# --- Configuration ---
# Ensure the remote user has write permissions in DEST_DIR
# and that SSH authentication (preferably with a public key) is configured.
SOURCE_DIR="./reports/"
REMOTE_USER="user"
REMOTE_HOST="ip_of_mini_pc"
DEST_DIR="/path/to/autonomous_brewing/central_server/incoming_reports/"

echo "Starting report synchronization..."

# Infinite loop to synchronize and then clean up the already sent files
while true; do
  # The --remove-source-files flag deletes source files after a successful transfer.
  rsync -avz --remove-source-files "\$SOURCE_DIR"*.json "\$REMOTE_USER@\$REMOTE_HOST:\$DEST_DIR"
  
  if [ \$? -eq 0 ]; then
    echo "Synchronization successful at \$(date)."
  else
    echo "Synchronization error at \$(date)."
  fi
  
  sleep 30 # Attempt to sync every 30 seconds
done
EOF

# ==============================================================================
# 2. Central Server Structure (Mini PC)
# ==============================================================================
echo "  -> Setting up the central server (central_server)..."
mkdir -p central_server/{incoming_reports,services/data_ingestion,database,api_backend,frontend/static/{css,js}}

# --- Data Ingestion Service (Improved with MongoDB persistence) ---
echo "    -> Creating data ingestion service..."
cat > central_server/services/data_ingestion/ingest.py <<EOF
import time
import json
import os
import redis
import pymongo
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from datetime import datetime, timezone

# --- Configuration ---
INCOMING_DIR = '../../incoming_reports'
# Redis Config
REDIS_HOST = 'localhost'
REDIS_PORT = 6379
CACHE_EXPIRATION_SECONDS = 3 * 24 * 60 * 60 # 3 days
# MongoDB Config
MONGO_HOST = 'localhost'
MONGO_PORT = 27017
MONGO_DB = 'brewing_db'
MONGO_COLLECTION = 'sensor_readings'

# --- Database Connections ---
try:
    redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=0, decode_responses=True)
    redis_client.ping()
    print("Successfully connected to Redis.")
except redis.exceptions.ConnectionError as e:
    print(f"Error connecting to Redis: {e}")
    exit(1)

try:
    mongo_client = pymongo.MongoClient(f"mongodb://root:example@{MONGO_HOST}:{MONGO_PORT}/")
    db = mongo_client[MONGO_DB]
    collection = db[MONGO_COLLECTION]
    # Create an index on the timestamp to optimize queries
    collection.create_index([("timestamp", pymongo.DESCENDING)])
    print("Successfully connected to MongoDB.")
except pymongo.errors.ConnectionFailure as e:
    print(f"Error connecting to MongoDB: {e}")
    exit(1)


def persist_to_mongodb(data):
    """Inserts the data into MongoDB."""
    try:
        # Convert the timestamp string to a MongoDB datetime object
        data['timestamp'] = datetime.fromisoformat(data['timestamp'])
        collection.insert_one(data)
        print(f"Data inserted into MongoDB for batch: {data.get('batch_id')}")
        # TODO: Implement archiving logic to Cassandra for data > 30 days
        # This would typically be a separate batch process (e.g., a daily cron job).
    except Exception as e:
        print(f"Error inserting into MongoDB: {e}")

class ReportHandler(FileSystemEventHandler):
    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith('.json'):
            print(f"New report detected: {event.src_path}")
            self.process_report(event.src_path)

    def process_report(self, filepath):
        try:
            with open(filepath, 'r') as f:
                data = json.load(f)
            
            # 1. Save to Cache (Redis)
            key = f"sensor_data:{data['timestamp']}"
            redis_client.setex(key, CACHE_EXPIRATION_SECONDS, json.dumps(data))
            print(f"Data saved to Redis with key: {key}")
            
            # 2. Save to Permanent Storage (MongoDB)
            persist_to_mongodb(data.copy()) # Pass a copy to avoid mutation

            # 3. Clean up processed file
            os.remove(filepath)
            print(f"File processed and deleted: {filepath}")

        except Exception as e:
            print(f"Error processing file {filepath}: {e}")

if __name__ == "__main__":
    print("Starting data ingestion service...")
    event_handler = ReportHandler()
    observer = Observer()
    observer.schedule(event_handler, INCOMING_DIR, recursive=False)
    observer.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
        print("\nIngestion service stopped.")
    observer.join()
EOF

cat > central_server/services/data_ingestion/requirements.txt <<EOF
redis
watchdog
pymongo
EOF

# --- Database Configuration (Docker) ---
echo "    -> Creating Docker configuration for databases..."
cat > central_server/database/docker-compose.yml <<EOF
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: redis_cache
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    restart: unless-stopped

  mongo:
    image: mongo:6.0
    container_name: mongodb_permanent
    ports:
      - "27017:27017"
    environment:
      - MONGO_INITDB_ROOT_USERNAME=root
      - MONGO_INITDB_ROOT_PASSWORD=example
    volumes:
      - mongo_data:/data/db
    restart: unless-stopped

  cassandra:
    image: cassandra:4.0
    container_name: cassandra_transactional
    ports:
      - "9042:9042"
    volumes:
      - cassandra_data:/var/lib/cassandra
    environment:
      - CASSANDRA_CLUSTER_NAME=BrewingCluster
      - CASSANDRA_DC=dc1
      - CASSANDRA_RACK=rack1
      - CASSANDRA_ENDPOINT_SNITCH=GossipingPropertyFileSnitch
    restart: unless-stopped

volumes:
  redis_data:
  mongo_data:
  cassandra_data:
EOF

# --- Backend API (Django) ---
echo "    -> Creating Django backend structure..."
mkdir -p central_server/api_backend/brewing_project
mkdir -p central_server/api_backend/data_api/management/commands
mkdir -p central_server/api_backend/metrics

cat > central_server/api_backend/manage.py <<EOF
#!/usr/bin/env python
import os
import sys

def main():
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'brewing_project.settings')
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError("Couldn't import Django.") from exc
    execute_from_command_line(sys.argv)

if __name__ == '__main__':
    main()
EOF

cat > central_server/api_backend/brewing_project/settings.py <<EOF
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
SECRET_KEY = 'django-insecure-a-super-secret-key-for-the-project'
DEBUG = True
ALLOWED_HOSTS = ['*'] # Allow all hosts for development

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'corsheaders',
    'data_api',
    'metrics',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'corsheaders.middleware.CorsMiddleware', # CORS Middleware
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'brewing_project.urls'
WSGI_APPLICATION = 'brewing_project.wsgi.application'

# Allow CORS requests from any origin (for development only)
CORS_ALLOW_ALL_ORIGINS = True

# No DATABASES config needed as we don't use the Django ORM
DATABASES = {}

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True
STATIC_URL = 'static/'
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
EOF

cat > central_server/api_backend/brewing_project/urls.py <<EOF
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/', include('data_api.urls')),
]
EOF

cat > central_server/api_backend/data_api/urls.py <<EOF
from django.urls import path
from .views import RealtimeDataView, HistoricalDataView

urlpatterns = [
    path('realtime/', RealtimeDataView.as_view(), name='realtime_data'),
    path('historical/', HistoricalDataView.as_view(), name='historical_data'),
]
EOF

cat > central_server/api_backend/data_api/views.py <<EOF
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.pagination import PageNumberPagination
import redis
import json
import pymongo
from bson import json_util
from datetime import datetime, timedelta, timezone

# --- Database Connections ---
REDIS_CLIENT = redis.Redis(host='localhost', port=6379, db=0, decode_responses=True)
MONGO_CLIENT = pymongo.MongoClient("mongodb://root:example@localhost:27017/")
MONGO_DB = MONGO_CLIENT['brewing_db']
MONGO_COLLECTION = MONGO_DB['sensor_readings']

class RealtimeDataView(APIView):
    """
    Endpoint to get the most recent data from the Redis cache.
    """
    def get(self, request, *args, **kwargs):
        try:
            keys = REDIS_CLIENT.keys('sensor_data:*')
            if not keys:
                return Response([])
            
            # Get all values and sort them in Python
            pipeline = REDIS_CLIENT.pipeline()
            for key in keys:
                pipeline.get(key)
            
            values = pipeline.execute()
            
            # Deserialize and sort by timestamp descending
            data = sorted(
                [json.loads(v) for v in values if v], 
                key=lambda x: x['timestamp'], 
                reverse=True
            )
            
            return Response(data[:20]) # Return the 20 most recent
        except Exception as e:
            return Response({"error": str(e)}, status=500)


class StandardResultsSetPagination(PageNumberPagination):
    page_size = 50
    page_size_query_param = 'page_size'
    max_page_size = 1000

class HistoricalDataView(APIView):
    """
    Endpoint to get paginated historical data from MongoDB.
    """
    pagination_class = StandardResultsSetPagination

    @property
    def paginator(self):
        if not hasattr(self, '_paginator'):
            self._paginator = self.pagination_class()
        return self._paginator

    def get(self, request, *args, **kwargs):
        try:
            # Build query based on parameters (e.g., batch_id, dates)
            query = {}
            batch_id = request.query_params.get('batch_id')
            if batch_id:
                query['batch_id'] = batch_id

            # Get documents sorted by timestamp
            queryset = MONGO_COLLECTION.find(query).sort("timestamp", pymongo.DESCENDING)
            
            # Paginate the results
            page = self.paginator.paginate_queryset(list(queryset), request, view=self)
            
            # Safely serialize BSON to JSON
            serialized_page = json.loads(json_util.dumps(page))

            return self.paginator.get_paginated_response(serialized_page)
        except Exception as e:
            return Response({"error": str(e)}, status=500)
EOF

cat > central_server/api_backend/requirements.txt <<EOF
django
djangorestframework
redis
pymongo
django-cors-headers
EOF

# --- Frontend (Improved) ---
echo "    -> Creating the frontend..."
cat > central_server/frontend/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Real-Time Monitoring - Autonomous Brewing</title>
    <link rel="stylesheet" href="static/css/styles.css">
</head>
<body>
    <header>
        <h1>🍺 Real-Time Monitoring</h1>
        <nav>
            <a href="index.html" class="active">Real-Time</a>
            <a href="history.html">Historical</a>
        </nav>
    </header>
    <main>
        <h2>Last 20 Sensor Readings (Cache)</h2>
        <div id="realtime-container" class="data-container">
            <table id="realtime-table">
                <thead>
                    <tr>
                        <th>Timestamp (UTC)</th>
                        <th>Batch ID</th>
                        <th>Temperature (°C)</th>
                        <th>Pressure (PSI)</th>
                        <th>CO2 (Vol)</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="5">Loading data...</td></tr>
                </tbody>
            </table>
        </div>
    </main>
    <script src="static/js/app.js"></script>
</body>
</html>
EOF

cat > central_server/frontend/history.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Historical Data - Autonomous Brewing</title>
    <link rel="stylesheet" href="static/css/styles.css">
</head>
<body>
    <header>
        <h1>📜 Historical Data (MongoDB)</h1>
        <nav>
            <a href="index.html">Real-Time</a>
            <a href="history.html" class="active">Historical</a>
        </nav>
    </header>
    <main>
        <h2>Historical Data Search</h2>
        <div id="historical-container" class="data-container">
             <table id="historical-table">
                <thead>
                    <tr>
                        <th>Timestamp (UTC)</th>
                        <th>Batch ID</th>
                        <th>Temperature (°C)</th>
                        <th>Pressure (PSI)</th>
                        <th>CO2 (Vol)</th>
                    </tr>
                </thead>
                <tbody>
                    <tr><td colspan="5">Loading data...</td></tr>
                </tbody>
            </table>
            <div class="pagination" id="pagination-controls"></div>
        </div>
    </main>
    <script src="static/js/history.js"></script>
</body>
</html>
EOF

cat > central_server/frontend/static/css/styles.css <<EOF
:root {
    --primary-color: #2c3e50;
    --secondary-color: #ffbf00;
    --bg-color: #f4f4f9;
    --font-color: #333;
    --card-bg: #ffffff;
    --border-radius: 8px;
}
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 0; background-color: var(--bg-color); color: var(--font-color); line-height: 1.6; }
header { background-color: var(--primary-color); color: white; padding: 1rem 2rem; text-align: center; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
nav { margin-top: 1rem; }
nav a { color: white; margin: 0 1rem; text-decoration: none; padding-bottom: 5px; }
nav a.active { font-weight: bold; border-bottom: 2px solid var(--secondary-color); }
main { padding: 2rem; max-width: 1200px; margin: auto; }
.data-container { background: var(--card-bg); padding: 1.5rem; border-radius: var(--border-radius); box-shadow: 0 4px 8px rgba(0,0,0,0.1); }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 12px 15px; border-bottom: 1px solid #ddd; }
thead tr { background-color: #f2f2f2; }
tbody tr:nth-child(even) { background-color: #f9f9f9; }
tbody tr:hover { background-color: #f1f1f1; }
.pagination { margin-top: 20px; text-align: center; }
.pagination button { background-color: var(--primary-color); color: white; border: none; padding: 10px 15px; margin: 0 5px; border-radius: 4px; cursor: pointer; }
.pagination button:disabled { background-color: #ccc; cursor: not-allowed; }
.pagination span { vertical-align: middle; }
EOF

cat > central_server/frontend/static/js/app.js <<EOF
document.addEventListener('DOMContentLoaded', () => {
    const API_URL = 'http://localhost:8000/api/realtime/';
    const tableBody = document.querySelector('#realtime-table tbody');

    const fetchRealtimeData = async () => {
        try {
            const response = await fetch(API_URL);
            if (!response.ok) throw new Error(\`HTTP error! status: \${response.status}\`);
            const data = await response.json();
            
            renderTable(data);

        } catch (error) {
            tableBody.innerHTML = \`<tr><td colspan="5">Error loading data: \${error.message}</td></tr>\`;
            console.error('Error fetching realtime data:', error);
        }
    };

    const renderTable = (data) => {
        tableBody.innerHTML = ''; // Clear table
        
        if (!data || data.length === 0) {
            tableBody.innerHTML = '<tr><td colspan="5">No recent data in cache.</td></tr>';
            return;
        }

        data.forEach(row => {
            const tr = document.createElement('tr');
            tr.innerHTML = \`
                <td>\${new Date(row.timestamp).toLocaleString()}</td>
                <td>\${row.batch_id}</td>
                <td>\${row.temperature_celsius}</td>
                <td>\${row.pressure_psi}</td>
                <td>\${row.co2_vol}</td>
            \`;
            tableBody.appendChild(tr);
        });
    };

    // Load data on start and then every 5 seconds
    fetchRealtimeData();
    setInterval(fetchRealtimeData, 5000);
});
EOF

cat > central_server/frontend/static/js/history.js <<EOF
document.addEventListener('DOMContentLoaded', () => {
    const API_BASE_URL = 'http://localhost:8000/api/historical/';
    const tableBody = document.querySelector('#historical-table tbody');
    const paginationControls = document.getElementById('pagination-controls');
    
    let currentPageUrl = API_BASE_URL;

    const fetchHistoricalData = async (url) => {
        try {
            const response = await fetch(url);
            if (!response.ok) throw new Error(\`HTTP error! status: \${response.status}\`);
            const data = await response.json();
            
            renderTable(data.results);
            renderPagination(data);

        } catch (error) {
            tableBody.innerHTML = \`<tr><td colspan="5">Error loading data: \${error.message}</td></tr>\`;
            console.error('Error fetching historical data:', error);
        }
    };

    const renderTable = (data) => {
        tableBody.innerHTML = ''; // Clear table
        
        if (!data || data.length === 0) {
            tableBody.innerHTML = '<tr><td colspan="5">No historical data found.</td></tr>';
            return;
        }

        data.forEach(row => {
            const tr = document.createElement('tr');
            // MongoDB returns an object for the date, we access \$date
            const timestamp = row.timestamp?.\$date ? new Date(row.timestamp.\$date).toLocaleString() : 'N/A';
            tr.innerHTML = \`
                <td>\${timestamp}</td>
                <td>\${row.batch_id}</td>
                <td>\${row.temperature_celsius}</td>
                <td>\${row.pressure_psi}</td>
                <td>\${row.co2_vol}</td>
            \`;
            tableBody.appendChild(tr);
        });
    };

    const renderPagination = (data) => {
        paginationControls.innerHTML = '';
        
        const prevButton = document.createElement('button');
        prevButton.textContent = 'Previous';
        prevButton.disabled = !data.previous;
        prevButton.addEventListener('click', () => fetchHistoricalData(data.previous));

        const nextButton = document.createElement('button');
        nextButton.textContent = 'Next';
        nextButton.disabled = !data.next;
        nextButton.addEventListener('click', () => fetchHistoricalData(data.next));
        
        const countSpan = document.createElement('span');
        countSpan.textContent = \` Total: \${data.count} records \`;

        paginationControls.appendChild(prevButton);
        paginationControls.appendChild(countSpan);
        paginationControls.appendChild(nextButton);
    };

    // Load initial data
    fetchHistoricalData(currentPageUrl);
});
EOF


# --- Finalization ---
cd ..
echo "✅ Project '$PROJECT_NAME' created and populated successfully!"
echo ""
echo "Generated structure:"
# Use 'tree' if available, otherwise a simple 'ls'.
if command -v tree &> /dev/null
then
    tree -L 3 "$PROJECT_NAME"
else
    ls -R "$PROJECT_NAME"
fi
echo ""
echo "Recommended next steps:"
echo "1. cd $PROJECT_NAME"
echo "2. Review README.md to understand the architecture and execution steps."
echo "3. Run 'chmod +x raspberry_pi/sync_reports.sh' to make the sync script executable."

