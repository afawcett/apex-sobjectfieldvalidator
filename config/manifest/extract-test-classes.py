import os, json
import sys

test_classes=""
key_to_lookup = "ApexTestClass"

path_to_json = "./force-app/tests"

json_files = [pos_json for pos_json in os.listdir(path_to_json) if pos_json.endswith('.json')]

for json_file in json_files:
    json_file = path_to_json + '/' + json_file
    with open(json_file) as f:
        data = json.load(f)
        if data.has_key(key_to_lookup):
            test_classes += ", ".join(data[key_to_lookup])
    test_classes += ", "

test_classes = test_classes[:-2]

print(test_classes)
