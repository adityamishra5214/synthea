import urllib.request
import zipfile
import os

url = "https://synthetichealth.github.io/synthea-sample-data/downloads/synthea_sample_data_csv_apr2020.zip"
zip_path = "data/synthea_sample_data_csv_apr2020.zip"
extract_path = "data/raw"

os.makedirs("data", exist_ok=True)
os.makedirs(extract_path, exist_ok=True)

print(f"Downloading Synthea sample CSV data from {url}...")
urllib.request.urlretrieve(url, zip_path)
print(f"Downloaded to {zip_path} ({os.path.getsize(zip_path)} bytes). Extracting...")

with zipfile.ZipFile(zip_path, 'r') as zip_ref:
    zip_ref.extractall(extract_path)

print("Extracted files in data/raw:")
for root, dirs, files in os.walk(extract_path):
    for f in files:
        full = os.path.join(root, f)
        print(f"  {f}: {os.path.getsize(full)} bytes")
