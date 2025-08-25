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
