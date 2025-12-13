# 📄 Templater Todo Template

This template uses the **Templater** plugin in Obsidian to quickly create tasks using shorthand aliases.

## 🧩 Shorthand Aliases

You can type the following shortcuts, and the template will expand them automatically:

| Shorthand | Expands To      |
| --------- | --------------- |
| `-l`      | `@prio(low)`    |
| `-n`      | `@prio(normal)` |
| `-h`      | `@prio(high)`   |

---

## 🕒 Date Format

The template adds a timestamp in the following format:

```
YYYY-MM-DD HH:mm
```

This format is **required** for compatibility with your `rofi-todo.sh` script.

---

## 🔁 Syncthing Integration

The core idea is to **sync your phone and your Arch Linux machine** using [Syncthing](https://syncthing.net/).  
Since both devices share the same vault folder, todos created on either side remain synchronized and formatted consistently.

---

## ✅ Final Task Format

When you run the template and enter:

```
-h Call Mom
```

It adds the following to `todos.md`:

```markdown
- [ ] @prio(high) Call Mom @2025-08-06 17:10
```

This ensures compatibility with your shell scripts and keeps your task file standardized.

---
