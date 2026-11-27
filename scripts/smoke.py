"""Confere a página, a conexão com o banco e o ciclo de vida de uma tarefa."""

import json
import sys
import urllib.request
from uuid import uuid4


def request(base, route, expected=200, method="GET", data=None):
    body = None if data is None else json.dumps(data).encode("utf-8")
    call = urllib.request.Request(
        base + route, data=body, headers={"Content-Type": "application/json"}, method=method
    )
    with urllib.request.urlopen(call, timeout=15) as response:
        if response.status != expected:
            raise RuntimeError(f"{method} {route}: HTTP {response.status}; esperado {expected}")
        payload = response.read()
        if response.headers.get_content_type() == "application/json":
            return json.loads(payload)
        return payload


def verify(base):
    assert b'id="root"' in request(base, "/"), "Página do React ausente"
    assert request(base, "/health")["database"] == "connected", "MongoDB indisponível"
    description = f"PM04 validação {uuid4()}"
    created = request(base, "/todos", 201, "POST", {"text": description})
    task_id = created["_id"]
    route = f"/todos/{task_id}"
    try:
        assert created["completed"] is False
        assert any(todo["_id"] == task_id for todo in request(base, "/todos"))
        assert request(base, route, method="PATCH")["completed"] is True
        assert request(base, route, method="PATCH")["completed"] is False
    finally:
        request(base, route, method="DELETE")
    assert all(todo["_id"] != task_id for todo in request(base, "/todos"))
    print(f"{base}: página, saúde, listagem, criação, conclusão, reabertura e exclusão verificadas.")


if __name__ == "__main__":
    verify(sys.argv[1].rstrip("/"))
