"""Verifica se a tarefa permanece após recriar o contêiner MongoDB no CI."""

import os
import subprocess
import time
import urllib.error
from uuid import uuid4

from smoke import request

base = f"http://127.0.0.1:{os.environ.get('FRONTEND_PORT', '8080')}"
task_id = request(base, "/todos", 201, "POST", {"text": f"Persistência PM04 {uuid4()}"})["_id"]
route = f"/todos/{task_id}"
try:
    assert request(base, route, method="PATCH")["completed"] is True
    subprocess.run(
        [
            "docker", "compose", "--env-file", ".env.example", "up", "-d",
            "--force-recreate", "--no-deps", "--wait", "--wait-timeout", "120", "mongo",
        ],
        check=True,
    )
    for _ in range(30):
        try:
            if request(base, "/health")["database"] == "connected":
                break
        except (TimeoutError, urllib.error.URLError):
            pass
        time.sleep(2)
    else:
        raise RuntimeError("API indisponível após recriar o MongoDB")
    tasks = request(base, "/todos")
    assert any(todo["_id"] == task_id and todo["completed"] is True for todo in tasks)
    print("A tarefa e seu estado foram preservados após recriar o MongoDB.")
finally:
    try:
        request(base, route, method="DELETE")
    except (TimeoutError, urllib.error.URLError):
        pass
