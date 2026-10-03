import os
import json
from PIL import Image
import random

data_dir = r"Amparish\card-lens-main\ml\data\private\kaggle_business_cards_2"
camera_dir = os.path.join(data_dir, "Camera")
manifest_path = os.path.join(data_dir, "source_manifest.jsonl")

print("Generating source_manifest.jsonl...")

with open(manifest_path, 'w', encoding='utf-8') as f:
    for filename in os.listdir(camera_dir):
        if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
            filepath = os.path.join(camera_dir, filename)
            try:
                with Image.open(filepath) as img:
                    width, height = img.size
                
                card_id = filename.split('.')[0]
                split = random.choices(['train', 'validation', 'test'], weights=[0.8, 0.1, 0.1])[0]
                
                entry = {
                    "card_id": card_id,
                    "physical_card_group": card_id,
                    "source": "kaggle",
                    "suggested_split": split,
                    "image": filename,
                    "width": width,
                    "height": height,
                    "annotations": [] 
                }
                f.write(json.dumps(entry) + '\n')
            except Exception as e:
                pass

print(f"Created {manifest_path}!")

# Also generate semantic_overrides.json
with open(os.path.join(data_dir, "semantic_overrides.json"), 'w') as f:
    f.write("{}")
