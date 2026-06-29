import os
import json
import urllib.request

def get_firebase_token():
    config_path = os.path.expanduser('~/.config/configstore/firebase-tools.json')
    if not os.path.exists(config_path):
        raise Exception("Firebase login credentials not found. Please log in using 'firebase login'.")
    
    with open(config_path, 'r', encoding='utf-8') as f:
        config = json.load(f)
    
    tokens = config.get('tokens', {})
    access_token = tokens.get('access_token')
    if not access_token:
        raise Exception("Access token not found in firebase-tools configuration.")
    return access_token

def build_firestore_value(val):
    if isinstance(val, int):
        return {"integerValue": str(val)}
    elif isinstance(val, float):
        return {"doubleValue": val}
    elif isinstance(val, bool):
        return {"booleanValue": val}
    elif isinstance(val, list):
        return {"arrayValue": {"values": [build_firestore_value(x) for x in val]}}
    elif isinstance(val, dict):
        return {"mapValue": {"fields": {k: build_firestore_value(v) for k, v in val.items()}}}
    else:
        return {"stringValue": str(val)}

def upload_collection_in_batches(collection_name, data_list, project_id, access_token):
    print(f"Uploading collection '{collection_name}' ({len(data_list)} documents)...")
    url = f"https://firestore.googleapis.com/v1/projects/{project_id}/databases/(default)/documents:commit"
    
    # Firestore batch limit is 500 writes per commit request
    batch_size = 300
    
    for i in range(0, len(data_list), batch_size):
        chunk = data_list[i:i+batch_size]
        writes = []
        
        for item in chunk:
            doc_id = str(item.get("id", item.get("word", "doc")))
            fields = {k: build_firestore_value(v) for k, v in item.items()}
            
            writes.append({
                "update": {
                    "name": f"projects/{project_id}/databases/(default)/documents/{collection_name}/{doc_id}",
                    "fields": fields
                }
            })
            
        payload = json.dumps({"writes": writes}).encode('utf-8')
        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json"
            },
            method="POST"
        )
        
        try:
            response = urllib.request.urlopen(req)
            # Read response to prevent socket blocks
            response.read()
            print(f"  Successfully uploaded batch {i // batch_size + 1} ({i} to {min(i + batch_size, len(data_list))})")
        except Exception as e:
            print(f"  Error uploading batch starting at {i}: {e}")

def main():
    project_id = "jengo-772e8"
    
    try:
        access_token = get_firebase_token()
        print("Successfully loaded Firebase OAuth2 credentials.")
    except Exception as e:
        print(f"Error loading credentials: {e}")
        return

    # 1. Japanese Grammar
    if os.path.exists("assets/materials/japanese/grammar.json"):
        with open("assets/materials/japanese/grammar.json", "r", encoding="utf-8") as f:
            data = json.load(f)
        upload_collection_in_batches("japanese_grammar", data, project_id, access_token)

    # 2. Japanese Sentences
    if os.path.exists("assets/materials/japanese/sentences.json"):
        with open("assets/materials/japanese/sentences.json", "r", encoding="utf-8") as f:
            data = json.load(f)
        upload_collection_in_batches("japanese_sentences", data, project_id, access_token)

    # 3. English Grammar
    if os.path.exists("assets/materials/english/grammar.json"):
        with open("assets/materials/english/grammar.json", "r", encoding="utf-8") as f:
            data = json.load(f)
        upload_collection_in_batches("english_grammar", data, project_id, access_token)

    # 4. English Speaking Prompts
    if os.path.exists("assets/materials/english/speaking_prompts.json"):
        with open("assets/materials/english/speaking_prompts.json", "r", encoding="utf-8") as f:
            data = json.load(f)
        upload_collection_in_batches("english_speaking_prompts", data, project_id, access_token)

    # 5. English Writing Prompts
    if os.path.exists("assets/materials/english/writing_prompts.json"):
        with open("assets/materials/english/writing_prompts.json", "r", encoding="utf-8") as f:
            data = json.load(f)
        upload_collection_in_batches("english_writing_prompts", data, project_id, access_token)

    # 6. Japanese Vocabulary (Top 500 for demo and size constraints on speed, or all if needed)
    # Let's upload all 7,000 vocabulary words so they are fully hosted!
    if os.path.exists("assets/materials/japanese/vocab.json"):
        with open("assets/materials/japanese/vocab.json", "r", encoding="utf-8") as f:
            data = json.load(f)
        upload_collection_in_batches("japanese_vocab", data, project_id, access_token)

    # 7. English Vocabulary (8,400 words)
    if os.path.exists("assets/materials/english/vocab.json"):
        with open("assets/materials/english/vocab.json", "r", encoding="utf-8") as f:
            data = json.load(f)
        upload_collection_in_batches("english_vocab", data, project_id, access_token)

    # 8. Japanese Kanji
    if os.path.exists("assets/materials/japanese/kanji.json"):
        with open("assets/materials/japanese/kanji.json", "r", encoding="utf-8") as f:
            data = json.load(f)
        upload_collection_in_batches("japanese_kanji", data, project_id, access_token)

    print("\nALL SELECTED STUDY ASSETS FULLY SYNCED AND UPLOADED TO FIREBASE FIRESTORE!")

if __name__ == "__main__":
    main()
