#!/usr/bin/env python3

import os
import subprocess
import sys
import shutil
from pathlib import Path

HOME = str(Path.home())
CONFIG_DIR = os.path.join(HOME, ".config", "GptScript")
VENV_DIR = os.path.join(CONFIG_DIR, "venv")
ENV_FILE = os.path.join(CONFIG_DIR, "user.env")
EXAMPLE_ENV = "user.env.example"

def run(cmd, check=True):
    print(f"> {cmd}")
    subprocess.run(cmd, shell=True, check=check)

def ensure_packages():
    print("\n[+] Installing system dependencies...")
    run("sudo pacman -S --noconfirm xclip xdotool python python-virtualenv")

def setup_virtualenv():
    if not os.path.exists(VENV_DIR):
        print(f"\n[+] Creating virtual environment in {VENV_DIR}...")
        run(f"python -m venv {VENV_DIR}")
    print("[+] Installing Python dependencies...")
    run(f"{VENV_DIR}/bin/pip install -r requirements.txt")

def copy_files():
    print(f"\n[+] Setting up config directory at {CONFIG_DIR}")
    os.makedirs(CONFIG_DIR, exist_ok=True)
    for file in ["gpt_inline_auto.py", "templates.py"]:
        shutil.copy(file, CONFIG_DIR)

    if not os.path.exists(ENV_FILE):
        print("[+] Creating user.env from example...")
        shutil.copy(EXAMPLE_ENV, ENV_FILE)
    else:
        print("[+] user.env already exists, skipping.")

def check_env_var():
    print("\n[+] Checking GEMINI_API_KEY...")
    try:
        with open("/etc/environment", "r") as f:
            env = f.read()
            if "GEMINI_API_KEY" not in env:
                raise FileNotFoundError
        print("[✔] GEMINI_API_KEY already set in /etc/environment.")
    except:
        print("[!] GEMINI_API_KEY not found in /etc/environment.")
        print("    Please add it manually or use the following command:")
        print('    sudo bash -c \'echo "GEMINI_API_KEY=your-key-here" >> /etc/environment\'')
        print("    Then reboot or run `source /etc/environment`.")

def make_executable():
    script_path = os.path.join(CONFIG_DIR, "gpt_inline_auto.py")
    print(f"\n[+] Making {script_path} executable...")
    run(f"chmod +x {script_path}")

def main():
    ensure_packages()
    setup_virtualenv()
    copy_files()
    check_env_var()
    make_executable()
    print("\n✅ Setup complete. You can now run:")
    print(f"  {CONFIG_DIR}/gpt_inline_auto.py")

if __name__ == "__main__":
    main()
