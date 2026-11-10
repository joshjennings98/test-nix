"""Deterministic ACP fixture: no network, credentials or project file access."""
import json
import sys
import time

pending = None
permission = None


def send(message):
    print(json.dumps({"jsonrpc": "2.0", **message}), flush=True)


def reply(identifier, result):
    send({"id": identifier, "result": result})


def chunk(text, kind="agent_message_chunk", message_id=None):
    update = {"sessionUpdate": kind, "content": {"type": "text", "text": text}}
    if message_id is not None:
        update["messageId"] = message_id
    send({"method": "session/update", "params": {
        "sessionId": "inline-test", "update": update}})


for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    identifier = message.get("id")
    if method == "initialize":
        time.sleep(0.1)
        reply(identifier, {"protocolVersion": 1, "agentCapabilities": {}, "authMethods": []})
    elif method == "session/new":
        reply(identifier, {"sessionId": "inline-test"})
    elif method == "session/prompt":
        pending = identifier
        prompt = "".join(item.get("text", "") for item in message["params"]["prompt"])
        if "TEST_HISTORY" in prompt:
            chunk("## Result\n\n**Checking** files.", message_id="intro")
            chunk("Private reasoning", kind="agent_thought_chunk")
            send({"method": "session/update", "params": {
                "sessionId": "inline-test", "update": {
                    "sessionUpdate": "tool_call", "toolCallId": "history-tool",
                    "title": "Synthetic history tool", "kind": "read", "status": "completed",
                    "content": [{"type": "content", "content": {
                        "type": "text", "text": "Tool output must stay out"}}]}}})
            chunk("Done with `example.el`.", message_id="answer")
            reply(identifier, {"stopReason": "end_turn"})
            pending = None
        elif "TEST_BLOCKS" in prompt:
            chunk("Checking ")
            chunk("files.")
            chunk("Considering the result", kind="agent_thought_chunk")
            chunk("Done ", message_id="answer-1")
            chunk("now.", message_id="answer-1")
            chunk("Another message.", message_id="answer-2")
            reply(identifier, {"stopReason": "end_turn"})
            pending = None
        elif "TEST_ERROR" in prompt:
            send({"id": identifier, "error": {"code": -32603, "message": "Synthetic agent failure"}})
            pending = None
        elif "TEST_HOLD" in prompt:
            chunk("Waiting for interruption")
        elif "TEST_PERMISSION" in prompt:
            permission = "permission-1"
            send({"id": permission, "method": "session/request_permission", "params": {
                "sessionId": "inline-test",
                "toolCall": {"toolCallId": "tool-1", "title": "Synthetic tool", "kind": "read", "status": "pending"},
                "options": [{"optionId": "allow", "name": "Allow", "kind": "allow_once"},
                            {"optionId": "reject", "name": "Reject", "kind": "reject_once"}]}})
        else:
            chunk("Echo: ")
            chunk(prompt)
            reply(identifier, {"stopReason": "end_turn"})
            pending = None
    elif method == "session/cancel":
        if pending is not None:
            reply(pending, {"stopReason": "cancelled"})
            pending = None
    elif permission is not None and identifier == permission:
        chunk("Permission handled")
        reply(pending, {"stopReason": "end_turn"})
        permission = None
        pending = None
    elif method and identifier is not None:
        send({"id": identifier, "error": {"code": -32601, "message": "Unsupported fixture method"}})
