import os
import json
from PIL import Image

data_dir = r"Amparish\card-lens-main\ml\data\private\expo_business_cards"
camera_dir = os.path.join(data_dir, "Camera")
manifest_path = os.path.join(data_dir, "source_manifest.jsonl")

print("Generating blank source_manifest.jsonl...")

with open(manifest_path, 'w', encoding='utf-8') as f:
    for filename in os.listdir(camera_dir):
        if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
            filepath = os.path.join(camera_dir, filename)
            try:
                with Image.open(filepath) as img:
                    width, height = img.size
                
                # Write a blank manifest entry for human review
                entry = {
                    "card_id": filename.split('.')[0],
                    "image": filename,
                    "width": width,
                    "height": height,
                    "annotations": [] 
                }
                f.write(json.dumps(entry) + '\n')
            except Exception as e:
                pass

print(f"Created {manifest_path} for your 55 cards!")
