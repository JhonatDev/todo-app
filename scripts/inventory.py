"""Transforma os outputs do Terraform em inventário e variáveis do deploy."""

import json
import os
import sys
from pathlib import Path

outputs = json.load(sys.stdin)
infra = outputs["ansible_inventory_data"]["value"]
domain = os.environ.get("APP_DOMAIN") or outputs["suggested_https_domain"]["value"]
inventory = {
    "all": {
        "vars": {
            "ansible_user": infra["ssh_user"],
            "db_private_ip": infra["db_private_ip"],
            "db_volume_id": infra["db_volume_id"],
            "app_domain": domain,
        },
        "children": {
            "database": {"hosts": {"mongo": {"ansible_host": infra["db_host"]}}},
            "application": {"hosts": {"web": {"ansible_host": infra["app_host"]}}},
        },
    }
}
Path(sys.argv[1]).write_text(json.dumps(inventory), encoding="utf-8")
with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as environment:
    for name, value in {
        "APP_URL": f"https://{domain}",
        "APP_PUBLIC_IP": outputs["app_public_ip"]["value"],
        "DB_TARGET": f"{infra['ssh_user']}@{infra['db_host']}",
    }.items():
        environment.write(f"{name}={value}\n")
