#!/home/ati/.config/GptScript/venv/bin/python
# -*- coding: utf-8 -*-

import os
import subprocess
import time
import re
from dotenv import load_dotenv

# Load .env from the correct path (adjust if needed)
load_dotenv(dotenv_path=os.path.expanduser("~/.config/GptScript/user.env"))

TRIGGER_PREFIXES = ["/gpt", "/mail", "/sum"]
CONTEXT_FILE = "/tmp/gpt_context_history.txt"

def get_clipboard_text():
    time.sleep(0.1)
    try:
        result = subprocess.run(['xclip', '-selection', 'clipboard', '-o'],
                                capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except Exception:
        return None


def append_to_context(prompt, response):
    with open(CONTEXT_FILE, "a", encoding="utf-8") as f:
        f.write(f"User: {prompt.strip()}\nAssistant: {response.strip()}\n\n")

def reset_context():
    open(CONTEXT_FILE, "w").close()

def get_context():
    try:
        with open(CONTEXT_FILE, "r", encoding="utf-8") as f:
            return f.read().strip()
    except FileNotFoundError:
        return ""

def copy_to_clipboard(text):
    try:
        subprocess.run(['xclip', '-selection', 'clipboard'], input=text, text=True, check=True)
    except:
        pass

def type_text(text):
    try:
        subprocess.run(['xdotool', 'type', '--clearmodifiers', '--delay', '5', text], check=True)
    except:
        pass

def get_gemini_response(prompt):
    import google.generativeai as genai
    import re
    from templates import PERSONA_RULES

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        return None

    genai.configure(api_key=api_key, transport="rest")
    model = genai.GenerativeModel("gemini-2.5-flash-lite")

    persona = PERSONA_RULES.strip()
    name = os.getenv("NAME", "")
    email = os.getenv("EMAIL", "")
    student_id = os.getenv("STUDENT_ID", "")
    github = os.getenv("GITHUB", "")
    linkedin = os.getenv("LINKEDIN", "")
    instagram = os.getenv("INSTAGRAM", "")      # NEW
    x_link = os.getenv("X", "")                 # NEW

    user_info = f"""User Information:

- Name: {name}

- Email: {email}

- Student ID: {student_id}

- GitHub: {github}

- LinkedIn: {linkedin}

- Instagram: {instagram}

- X: {x_link}
"""

    final_prompt = f"{persona}\n\n{user_info}\nRespond directly. Do not ask for more info.\n\nPrompt: {prompt.strip()}"

    response = model.generate_content(final_prompt)
    raw_text = response.text.strip()

    # Clean markdown formatting
    clean_text = re.sub(r'[*_]{1,2}', '', raw_text)  # remove *, **, _, __
    clean_text = re.sub(r'^#{1,6}\s*', '', clean_text, flags=re.MULTILINE)  # remove markdown headers

    return clean_text

LAST_GPT_RESPONSE = ""  # Add this line at the top of your script or in a config section

def handle_gpt(original_text, prompt):
    cleaned_text = re.sub(r'^.*?(/gpt\s+)', '', original_text, flags=re.IGNORECASE | re.DOTALL).strip()

    # Handle reset
    if "/reset" in original_text.lower():
        reset_context()
        return "Conversation context cleared."

    # Build prompt with memory
    context = get_context()
    full_prompt = f"{context}\n\nUser: {cleaned_text}" if context else cleaned_text

    response = get_gemini_response(full_prompt.strip())
    if response:
        append_to_context(cleaned_text, response)
        return response

    return "Failed to generate a response."

def handle_mail(prompt):
    import re
    from templates import MAIL_TEMPLATE

    # Get fresh env values AFTER load_dotenv()
    name = os.getenv("NAME", "Mohamed Attia").strip()
    student_id = os.getenv("STUDENT_ID", "Unknown ID").strip()
    department = "Software Engineering"

    # Extract recipient
    extract_prompt = (
        f"From this message, extract ONLY the name or title of the email recipient. "
        f"Return just the name/title. Message: {prompt}"
    )
    recipient_raw = get_gemini_response(extract_prompt)
    recipient = recipient_raw.strip().split('\n')[0] if recipient_raw else "Professor"

    # Generate subject and body
    subject_prompt = (
        f"Write a final, professional email subject for this message: {prompt}. "
        f"Do not include placeholders like [Your Name] or [Course Name/Semester]."
    )
    body_prompt = (
        f"Write only the main message body (no greeting or closing) for an email to {recipient}. "
        f"The email is about: {prompt}. Avoid including 'Dear', 'Sincerely', name, or subject."
    )

    subject_raw = get_gemini_response(subject_prompt)
    body = get_gemini_response(body_prompt)

    # Clean up subject
    subject = re.sub(r'^Subject:\s*', '', subject_raw.strip(), flags=re.IGNORECASE)

    if subject and body and MAIL_TEMPLATE:
        return MAIL_TEMPLATE.format(
            subject=subject,
            recipient=recipient,
            body=body,
            name=name,
            student_id=student_id,
            department=department
        )
    return None

def handle_sum(original_text):
    clean_text = original_text.replace("/sum", "").strip()
    prompt = f"Summarize the following:\n\n{clean_text}"
    summary = get_gemini_response(prompt)

    if summary:
        # Copy only the original input (without the summary) to clipboard
        copy_to_clipboard(clean_text)

        # Return only the summary to be typed
        return summary

    return None
def main():
    clip = get_clipboard_text()
    if not clip:
        return

    match = re.search(r'/(gpt|mail|sum)\s*(.*)', clip, re.IGNORECASE | re.DOTALL)
    if not match:
        return

    command = match.group(1).lower()
    prompt = match.group(2).strip()

    if command == "gpt":
        output = handle_gpt(clip, prompt)
    elif command == "mail":
        output = handle_mail(prompt)
    elif command == "sum":
        output = handle_sum(clip)
    else:
        output = None

    if output:
        type_text(output)

if __name__ == "__main__":
    main()
