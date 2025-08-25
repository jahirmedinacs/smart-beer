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
