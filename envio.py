import sys
import os
import base64
import requests
from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential
from msal import ConfidentialClientApplication


def log(message):
    print(f"[envio.py] {message}", flush=True)


if len(sys.argv) < 2:
    print("Error: no se indicó correo destinatario.")
    print("Uso: python3 envio.py destinatario@dominio.cl [cc1@dominio.cl cc2@dominio.cl]")
    sys.exit(1)

recipient_email = sys.argv[1]
cc_emails = sys.argv[2:] if len(sys.argv) > 2 else []

key_vault_uri = "https://kv-ca-admcloud-eastus2.vault.azure.net/"
script_dir = os.path.dirname(os.path.abspath(__file__))
file_path = os.path.join(script_dir, "cves.zip")
attachment_name = "cves.zip"

if not os.path.exists(file_path):
    print(f"Error: no existe el archivo adjunto {file_path}")
    sys.exit(1)

log(f"Leyendo adjunto: {file_path}")
with open(file_path, "rb") as file:
    encoded_content = base64.b64encode(file.read()).decode("utf-8")
log("Adjunto codificado.")

log("Conectando a Key Vault.")
credential = DefaultAzureCredential()
client = SecretClient(vault_url=key_vault_uri, credential=credential)

CLIENT_SECRET = str(client.get_secret("checkapp").value)
CLIENT_ID = str(client.get_secret("checkappid").value)
TENANT_ID = str(client.get_secret("tenantid").value)
log("Secretos cargados desde Key Vault.")

GRAPH_ENDPOINT = "https://graph.microsoft.com/v1.0"

app = ConfidentialClientApplication(
    CLIENT_ID,
    authority=f"https://login.microsoftonline.com/{TENANT_ID}",
    client_credential=CLIENT_SECRET
)

log("Solicitando token de Microsoft Graph.")
token = app.acquire_token_for_client(scopes=["https://graph.microsoft.com/.default"])

if "access_token" not in token:
    print("Error al obtener token de Microsoft Graph:")
    print(token)
    sys.exit(1)

access_token = token["access_token"]
log("Token de Microsoft Graph obtenido.")

sender_email = "francisco.mackay@security.cl"

subject = "CVEs informe"
body = (
    "Estimados/as,\n\n"
    "Adjunto a este correo encontrarán el informe solicitado de CVEs.\n\n"
    "Cordialmente,\n\n"
    "STC Cloud Admin\n"
)

message = {
    "message": {
        "subject": subject,
        "body": {
            "contentType": "Text",
            "content": body
        },
        "toRecipients": [
            {"emailAddress": {"address": recipient_email}}
        ],
        "ccRecipients": [
            {"emailAddress": {"address": email}} for email in cc_emails
        ],
        "attachments": [
            {
                "@odata.type": "#microsoft.graph.fileAttachment",
                "name": attachment_name,
                "contentType": "application/zip",
                "contentBytes": encoded_content
            }
        ]
    }
}

headers = {
    "Authorization": f"Bearer {access_token}",
    "Content-Type": "application/json"
}

log(f"Enviando correo a {recipient_email} con {len(cc_emails)} copia(s).")
response = requests.post(
    f"{GRAPH_ENDPOINT}/users/{sender_email}/sendMail",
    json=message,
    headers=headers
)

if response.status_code == 202:
    print("Correo enviado exitosamente.")
else:
    print(f"Error al enviar el correo. Status: {response.status_code}")
    try:
        print(response.json())
    except Exception:
        print(response.text)
    sys.exit(1)
