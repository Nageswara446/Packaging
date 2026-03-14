import requests
import base64
import sys

# --- Connection values ---
if not server:
    sys.exit("Error: Missing GitHub connection.")

gittoken = server.get("Password/Token")
if not gittoken:
    sys.exit("Error: Git token missing in connection.")

base_url = server.get("Base url")
if not base_url:
    sys.exit("Error: Base URL missing in connection.")

# --- Task values ---
organization = params.get("organization")
repo = params.get("repo")
branch = params.get("branch")
filename = params.get("filename")

if not organization or not repo or not branch or not filename:
    sys.exit("Error: 'organization', 'repo', 'branch', or 'filename' missing in task parameters.")

# --- Build API URL ---
url = f"{base_url}/api/v3/repos/{organization}/{repo}/contents/{filename}?ref={branch}"

headers = {
    "Accept": "application/vnd.github.v3+json",
    "Authorization": f"token {gittoken}"
}

# --- Fetch file ---
response = requests.get(url, headers=headers, verify=False)
if response.status_code != 200:
    sys.exit(f"GitHub API error {response.status_code}: {response.text}")

content_b64 = response.json().get("content")
if not content_b64:
    sys.exit("Error: 'content' not found in GitHub API response.")

# --- Decode file content ---
file_content = base64.b64decode(content_b64).decode("utf-8")

# --- Output back to XLR ---
output['fileContent'] = file_content
