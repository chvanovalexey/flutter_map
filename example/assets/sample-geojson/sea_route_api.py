import json
import random
import requests
import os

# Number of API requests to make
NUM_ITERATIONS = 50

# API endpoint
API_ENDPOINT = "https://europe-west1-bollo-tracker.cloudfunctions.net/calculateComplexSeaRoute"

# Load the sample GeoJSON file
with open("sample-req.geojson", "r") as f:
    sample_geojson = json.load(f)

# Function to modify coordinates within reasonable limits
def modify_coordinates(coordinates):
    # Longitude range: -180 to 180
    # Latitude range: -90 to 90
    longitude, latitude = coordinates
    
    # Add random offset (between -5 and 5 degrees)
    new_longitude = longitude + random.uniform(-50, 50)
    new_latitude = latitude + random.uniform(-50, 50)
    
    # Ensure coordinates stay within valid ranges
    new_longitude = max(-180, min(180, new_longitude))
    new_latitude = max(-90, min(90, new_latitude))
    
    return [new_longitude, new_latitude]

# Function to modify all coordinates in the GeoJSON
def modify_all_coordinates(geojson_data):
    modified_data = json.loads(json.dumps(geojson_data))  # Deep copy
    
    for feature in modified_data["features"]:
        if feature["geometry"]["type"] == "Point":
            feature["geometry"]["coordinates"] = modify_coordinates(feature["geometry"]["coordinates"])
    
    return modified_data

# Main loop to send API requests
for i in range(1, NUM_ITERATIONS + 1):
    print(f"Processing iteration {i}/{NUM_ITERATIONS}...")
    
    # Modify the coordinates
    modified_geojson = modify_all_coordinates(sample_geojson)
    
    try:
        # Send the API request
        response = requests.post(
            API_ENDPOINT,
            json=modified_geojson,
            headers={"Content-Type": "application/json"}
        )
        
        # Check if the request was successful
        if response.status_code == 200:
            # Save the response to a file using UTF-8 encoding
            output_filename = f"{i}.geojson"
            with open(output_filename, "w", encoding="utf-8") as f:
                f.write(response.text)
            print(f"Successfully saved response to {output_filename}")
        else:
            print(f"API request failed with status code: {response.status_code}")
            print(f"Response: {response.text}")
    
    except Exception as e:
        print(f"Error during API request: {e}")

print("All iterations completed.") 