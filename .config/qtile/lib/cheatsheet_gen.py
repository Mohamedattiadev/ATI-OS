"""Auto-generate CHEATSHEET dict from lib/keys.py via AST parse.

Format matches popups/QtileCheatsheet.py:
    { "Category": [(label, combo_str), ...], ... }

Base Keys collect under "Global"; each KeyChord becomes its own category
named after its `mode=` (or `name=`) kwarg. Only keys with `desc=` shown.
"""
import ast
import os


MOD_MAP = {
    "mod4": "Super",
    "mod1": "Mod",
    "control": "Ctrl",
    "shift": "Shift",
    "mod": "Super",
    "mod2": "Mod",
}


def _mods_to_str(mods_ast):
    """Turn ast.List of mod strings/names into 'Super + Shift' style."""
    parts = []
    for m in mods_ast.elts:
        if isinstance(m, ast.Constant):
            parts.append(MOD_MAP.get(m.value, m.value))
        elif isinstance(m, ast.Name):
            parts.append(MOD_MAP.get(m.id, m.id.capitalize()))
    return " + ".join(parts)


def _key_to_str(k_ast):
    if isinstance(k_ast, ast.Constant):
        return str(k_ast.value)
    if isinstance(k_ast, ast.Name):
        return k_ast.id
    return ast.unparse(k_ast)


def _combo(mods, key):
    m = _mods_to_str(mods)
    k = _key_to_str(key)
    return f"{m} + {k}" if m else k


def _extract_desc(call):
    """Find desc=... kwarg on a Key(...) call. Return None if absent."""
    for kw in call.keywords:
        if kw.arg == "desc" and isinstance(kw.value, ast.Constant):
            return kw.value.value
    return None


def _extract_name(call):
    """Find name= or mode= kwarg on KeyChord(...)."""
    for kw in call.keywords:
        if kw.arg in ("name", "mode") and isinstance(kw.value, ast.Constant):
            if isinstance(kw.value.value, str):
                return kw.value.value
    return None


def _process_call(call, global_bucket, chord_buckets):
    if not isinstance(call.func, ast.Name):
        return
    if call.func.id == "Key":
        if len(call.args) < 2:
            return
        desc = _extract_desc(call)
        if not desc:
            return
        mods, key = call.args[0], call.args[1]
        if not isinstance(mods, ast.List):
            return
        global_bucket.append((desc, _combo(mods, key)))
    elif call.func.id == "KeyChord":
        # KeyChord(mods, key, submappings, name="Mode", ...)
        if len(call.args) < 3:
            return
        name = _extract_name(call) or "Chord"
        submaps = call.args[2]
        bucket = chord_buckets.setdefault(name.upper(), [])
        if isinstance(submaps, ast.List):
            for sub in submaps.elts:
                if isinstance(sub, ast.Call):
                    _process_call(sub, bucket, chord_buckets)


def build_cheatsheet(keys_py_path=None):
    if keys_py_path is None:
        keys_py_path = os.path.join(os.path.dirname(__file__), "keys.py")
    with open(keys_py_path) as f:
        tree = ast.parse(f.read())

    global_bucket = []
    chord_buckets = {}

    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id == "keys":
                if isinstance(node.value, ast.List):
                    for item in node.value.elts:
                        if isinstance(item, ast.Call):
                            _process_call(item, global_bucket, chord_buckets)

    # Prune empty chord categories; normalize "-MODE" -> " MODE" for display
    result = {"Global": global_bucket}
    for name, items in chord_buckets.items():
        if not items:
            continue
        pretty = name.replace("-", " ")
        result[pretty] = items
    return result


CHEATSHEET = build_cheatsheet()
