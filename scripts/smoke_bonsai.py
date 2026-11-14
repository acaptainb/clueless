#!/usr/bin/env python3
"""M0 smoke test: 9B text, 9B screenshot, 2B watcher JSON. Localhost only, stdlib only."""
import base64, json, sys, time, urllib.request, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OFF = {"chat_template_kwargs": {"enable_thinking": False},
       "temperature": 0.7, "top_p": 0.8, "top_k": 20, "presence_penalty": 1.5}

def chat(port, messages, max_tokens, **extra):
    body = {"messages": messages, "max_tokens": max_tokens, **OFF, **extra}
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions",
                                 json.dumps(body).encode(), {"Content-Type": "application/json"})
    t0 = time.time()
    r = json.load(urllib.request.urlopen(req, timeout=300))
    dt = time.time() - t0
    tm = r.get("timings", {})
    return r["choices"][0]["message"]["content"], dt, tm

def report(name, out, dt, tm):
    print(f"\n== {name}: {dt:.2f}s total | prompt {tm.get('prompt_n')} tok @ {tm.get('prompt_per_second', 0):.0f}/s"
          f" | gen {tm.get('predicted_n')} tok @ {tm.get('predicted_per_second', 0):.0f}/s")
    print(out.strip())

report("9B text", *chat(8080, [{"role": "user", "content": "In one sentence, what does the learning rate do in gradient descent?"}], 80))

img = base64.b64encode((ROOT / "smoke/shot.png").read_bytes()).decode()
report("9B screenshot", *chat(8080, [{"role": "user", "content": [
    {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{img}"}},
    {"type": "text", "text": "This is the lecture slide on screen. What is the learning rate value, the batch size, and when is the homework due? Answer briefly."}]}], 120))

lines = """[L212 14:03:01] Maya: The design review went fine.
[L213 14:03:05] Sam: We still need the API changes merged.
[L215 14:03:10] Maya: Yusuf, can your team still hit Friday?"""
report("2B watcher", *chat(8082, [
    {"role": "system", "content": 'You watch a meeting transcript for the user. Reply with JSON only: {"needs_user": true|false, "reason": "name"|"question"|"none"}. needs_user is true only if the last line addresses the user or asks them something.'},
    {"role": "user", "content": f"User name: Yusuf\n\n{lines}"}], 30,
    response_format={"type": "json_object"}))
