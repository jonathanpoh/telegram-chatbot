import requests, os, sys, time
from dotenv import load_dotenv

load_dotenv()

TELEGRAM_TOKEN = os.environ["TELEGRAM_TOKEN"]
OPENROUTER_KEY = os.environ["OPENROUTER_API_KEY"]
ALLOWED_CHAT_ID = os.environ.get("ALLOWED_CHAT_ID")  # optional allowlist; see README
SYSTEM_PROMPT = "You are Lars, Jonathan's sex therapist and confidant. Respond professionally and grounded on real medical science."
CONTEXT_LIMIT = 20  # messages kept per chat (sliding window)

def get_llm_response(history):
	r = requests.post(
		"https://openrouter.ai/api/v1/chat/completions",
		headers={"Authorization": f"Bearer {OPENROUTER_KEY}"},
		json={
			"model": "deepseek/deepseek-v4.1-flash", 
			"messages": [{"role": "system", "content": SYSTEM_PROMPT}] + history,
			"temperature": 0.7,
			"max_tokens": 2000,
			"frequency_penalty": 1.1,
		},
		timeout=120,
	)
	data = r.json()
	if "choices" not in data:
		raise RuntimeError(data.get("error", data))
	return data["choices"][0]["message"]["content"]

def send_message(chat_id, text):
	requests.post(
		f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage",
		json={"chat_id": chat_id, "text": text},
		timeout=30,
	)

def get_updates(offset):
	r = requests.get(
		f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/getUpdates",
		params={"offset": offset, "timeout": 30},
		timeout=40,
	)
	return r.json().get("result", [])

def handle(history, text):
	"""Append the user turn, call the model, append the reply. Returns the reply."""
	history.append({"role": "user", "content": text})
	try:
		reply = get_llm_response(history)
	except Exception:
		history.pop()
		raise
	history.append({"role": "assistant", "content": reply})
	del history[:-CONTEXT_LIMIT]
	return reply

def run_telegram():
	histories = {}  # chat_id -> message list
	offset = None
	print("Polling Telegram. Ctrl-C to stop.")
	while True:
		try:
			updates = get_updates(offset)
		except requests.RequestException as e:
			print(f"poll error: {e}")
			time.sleep(5)
			continue

		for update in updates:
			offset = update["update_id"] + 1
			message = update.get("message") or {}
			text = message.get("text")
			chat_id = (message.get("chat") or {}).get("id")
			if not text or chat_id is None:
				continue

			print(f"[{chat_id}] you> {text}")
			if ALLOWED_CHAT_ID and str(chat_id) != ALLOWED_CHAT_ID:
				print(f"  ignored (not {ALLOWED_CHAT_ID})")
				continue

			history = histories.setdefault(chat_id, [])
			if text in ("/reset", "/start"):
				history.clear()
				send_message(chat_id, "*The forge is swept clean.*")
				continue

			try:
				reply = handle(history, text)
			except Exception as e:
				print(f"  error: {e}")
				send_message(chat_id, f"[error: {e}]")
				continue
			print(f"[{chat_id}] lars> {reply}")
			send_message(chat_id, reply)

def run_cli():
	history = []
	print("Chatting with Lars. Ctrl-C or /quit to exit.\n")
	while True:
		try:
			user_input = input("you> ").strip()
		except (EOFError, KeyboardInterrupt):
			print()
			break
		if not user_input:
			continue
		if user_input in ("/quit", "/exit"):
			break
		if user_input == "/reset":
			history.clear()
			print("(history cleared)\n")
			continue

		try:
			reply = handle(history, user_input)
		except Exception as e:
			print(f"error: {e}\n")
			continue
		print(f"\ngrix> {reply}\n")

if __name__ == "__main__":
	if "--cli" in sys.argv:
		run_cli()
	else:
		try:
			run_telegram()
		except KeyboardInterrupt:
			print()
