import requests
import base64
import sys

# --- Connection values from Server ---
base_url = server.get("base_url")
gittoken = server.get("token")

if not base_url or not gittoken:
    sys.exit("Error: Base URL or token missing in the selected Server connection.")

# --- Task inputs ---
organization = params.get("organization")
repository = params.get("repository")
branch = params.get("branch")
filename = params.get("filename")

# --- Validate inputs ---
for name, val in [("organization", organization), 
                  ("repository", repository),
                  ("branch", branch), 
                  ("filename", filename)]:
    if not val:
        sys.exit(f"Error: {name} is required.")

# --- Build GitHub API URL ---
url = f"{base_url}/repos/{organization}/{repository}/contents/{filename}?ref={branch}"
headers = {
    "Authorization": f"token {gittoken}",
    "Accept": "application/vnd.github.v3+json"
}

# --- Fetch file from GitHub ---
try:
    response = requests.get(url, headers=headers, verify=False)  # Use verify=True in prod
except Exception as e:
    sys.exit(f"Error connecting to GitHub: {e}")

if response.status_code != 200:
    sys.exit(f"GitHub API error {response.status_code}: {response.text}")

# --- Decode Base64 content ---
content_b64 = response.json().get("content")
if not content_b64:
    sys.exit("Error: 'content' not found in GitHub API response.")

file_content = base64.b64decode(content_b64.strip()).decode("utf-8")

# --- Output to XL Release ---
output['fileContent'] = file_content
print(f"File '{filename}' from repository '{repository}' successfully fetched.")
